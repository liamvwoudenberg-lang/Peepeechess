extends RefCounted
## Loader for the externalised role tuning in `balance_v1.json` (profiles, ability definitions, attack
## tables, movement profiles). Use it through `preload` (no global class on purpose):
##
##   const Balance := preload("res://combat/data/balance_data.gd")
##   Balance.profile("n")  # fresh copy
##
## What lives here vs. elsewhere:
##   * HERE: everything the v1 FighterStats contract does NOT carry (poise, armour, guard, dodge, stamina
##     economy, movement feel, attack frame data, ability behaviour).
##   * NOT HERE: HP, stamina, base damage, move speed, reach, light/heavy/parry ticks, ability cooldown and the
##     ability id. Those are contract stats and always come from the BattleRequest.
##
## Determinism / multiplayer: the server and every client MUST run the same tuning. `tuning_id()` names it,
## `tuning_hash()` is a stable SHA-256 of the canonical (sorted-key, type-normalised) data, and `stamp()`
## combines them ("balance-v1:<16 hex>"). Whitespace/key order in the file do not change the hash.
##
## JSON has no int/float distinction in Godot (everything parses as float), so values are re-typed from the
## key tables below; a tick count is always an int, a distance always a float.
##
## Overrides (tests, tooling, balance sweeps): `apply_override(patch)` deep-merges a patch onto the shipped
## data, validates the result and installs it only when valid. It is process-global: ALWAYS pair it with
## `clear_override()` (try/finally style) - `is_overridden()` tells whether one is active. Getters return
## copies, so callers can never mutate the active table. A running fight keeps the profile it copied at
## setup; overrides only affect fights started afterwards.

const DATA_PATH := "res://combat/data/balance_v1.json"
const SCHEMA := 1

const PROFILE_STR_KEYS := ["display", "weapon"]
const PROFILE_INT_KEYS := [
	"poise_regen_delay", "stagger_immunity_ticks", "stamina_regen_delay", "guardbreak_stun",
	"parry_recovery_ticks", "parry_cooldown_ticks", "parry_stagger_ticks", "riposte_ticks",
	"dodge_ticks", "dodge_iframe_start", "dodge_iframe_end", "dodge_cooldown_ticks", "hit_react_ticks",
]
const PROFILE_FLOAT_KEYS := [
	"radius", "armor", "poise", "poise_regen_per_tick", "sprint_mult", "sprint_drain_per_tick",
	"stamina_regen_per_tick", "block_arc_deg", "block_cost_mult", "block_move_mult",
	"parry_arc_deg", "parry_cost", "parry_refund", "riposte_mult", "dodge_cost", "dodge_distance",
	# Movement profile (FighterMovement). Pawn and Knight equal the original global constants.
	"accel", "decel", "turn_free", "turn_locked", "turn_attack_startup", "turn_attack_startup_locked",
	"attack_steer_startup", "attack_steer_other", "parry_steer",
]

const ABILITY_KEY_TYPES := {
	"kind": "string", "role": "string", "cast_ticks": "int", "stamina_cost": "float", "buff_ticks": "int",
	"hp_threshold": "float", "move_mult": "float", "attack_speed_mult": "float", "damage_mult": "float",
	"regen_mult": "float", "combo_length": "int", "guard_cost_mult": "float", "guard_unbreakable": "bool",
	"poise_mult": "float", "blink_distance": "float", "blink_tick": "int", "iframe_ticks": "int",
	# royal-counter (King)
	"counter_start": "int", "counter_end": "int", "counter_arc_deg": "float", "counter_stagger_ticks": "int",
	"stance_move_mult": "float", "stance_turn_mult": "float",
	# experimental abilities are refused unless the caller opts in (see AbilityComponent.setup)
	"experimental": "bool",
}
const ABILITY_REQUIRED := {
	"buff": ["kind", "role", "cast_ticks", "stamina_cost", "buff_ticks"],
	"attack": ["kind", "role", "stamina_cost"],
	"blink": ["kind", "role", "cast_ticks", "stamina_cost", "blink_distance", "blink_tick", "iframe_ticks"],
	"counter": ["kind", "role", "cast_ticks", "stamina_cost", "counter_start", "counter_end", "counter_arc_deg",
			"counter_stagger_ticks", "stance_move_mult", "stance_turn_mult"],
}
const ATTACK_INT_KEYS := ["combo_index", "absolute_ticks", "hitstun_ticks"]
const ATTACK_STR_KEYS := ["id", "animation"]
const ATTACK_KINDS := ["LIGHT", "HEAVY", "ABILITY"]

static var _base: Dictionary = {}      # shipped, normalised
static var _active: Dictionary = {}    # what getters serve (== _base unless overridden)
static var _overridden := false
static var _revision := 0
static var _hash := ""
static var _tables: Dictionary = {}    # role -> {"light": [...], "heavy": ..., "abilities": {...}} built lazily
static var _tables_rev := -1


# ---- public API -----------------------------------------------------------------------------
static func tuning_id() -> String:
	_ensure()
	return String(_active["tuning_id"])


static func tuning_hash() -> String:
	_ensure()
	return _hash


## "balance-v1:ab12cd34ef567890" - what a client and server compare before a fight.
static func stamp() -> String:
	_ensure()
	return "%s:%s" % [_active["tuning_id"], _hash.substr(0, 16)]


## Increments whenever the served data changes (override applied/cleared). Caches key on it.
static func revision() -> int:
	_ensure()
	return _revision


static func is_overridden() -> bool:
	_ensure()
	return _overridden


static func roles() -> Array:
	_ensure()
	return _active["profiles"].keys()


static func has_role(role: String) -> bool:
	_ensure()
	return _active["profiles"].has(role)


## Fresh copy of the role profile ({} when unknown).
static func profile(role: String) -> Dictionary:
	_ensure()
	return _active["profiles"].get(role, {}).duplicate()


## Fresh copy of the ability definition ({} when unknown).
static func ability(id: String) -> Dictionary:
	_ensure()
	return _active["abilities"].get(id, {}).duplicate()


static func ability_ids() -> Array:
	_ensure()
	return _active["abilities"].keys()


static func has_ability(id: String) -> bool:
	_ensure()
	return _active["abilities"].has(id)


## Attack tables for a role: {"light": Array[AttackDefinition], "heavy": AttackDefinition, "abilities": {id: def}}.
## The definitions are shared and cached until the data revision changes; treat them as read-only.
static func attack_tables(role: String) -> Dictionary:
	_ensure()
	if _tables_rev != _revision:
		_tables.clear()
		_tables_rev = _revision
	if not _tables.has(role):
		var src: Dictionary = _active["attacks"].get(role, {})
		if src.is_empty():
			return {}
		var lights: Array = []
		for entry in src["light"]:
			lights.append(_build_attack(entry))
		var abilities := {}
		for id in src["abilities"]:
			abilities[id] = _build_attack(src["abilities"][id])
		_tables[role] = {"light": lights, "heavy": _build_attack(src["heavy"]), "abilities": abilities}
	return _tables[role]


## A deep copy of the full normalised data (for tooling and for building overrides).
static func snapshot() -> Dictionary:
	_ensure()
	return _active.duplicate(true)


## Deep-merges `patch` onto the SHIPPED data and installs the result if it validates. Returns the list of
## validation errors (empty = installed). `patch` may carry its own "tuning_id"; otherwise the id becomes
## "<base id>+override" so a client/server mismatch is visible in `stamp()`.
## Arrays (the "light" attack chain) are replaced as a whole, dictionaries are merged key by key.
static func apply_override(patch: Dictionary) -> Array:
	_ensure()
	var merged := _merge(_base.duplicate(true), patch.duplicate(true))
	if not patch.has("tuning_id"):
		merged["tuning_id"] = String(_base["tuning_id"]) + "+override"
	var errors := validate(merged)
	if not errors.is_empty():
		return errors
	_install(_normalise(merged), true)
	return []


static func clear_override() -> void:
	_ensure()
	if _overridden:
		_install(_base.duplicate(true), false)


## Validates raw (JSON-shaped) data. Returns human-readable problems; empty = valid.
static func validate(data: Dictionary) -> Array:
	var errors: Array = []
	if typeof(data.get("tuning_id", null)) != TYPE_STRING or String(data["tuning_id"]).is_empty():
		errors.append("tuning_id must be a non-empty string")
	if int(data.get("schema", -1)) != SCHEMA:
		errors.append("schema must be %d" % SCHEMA)
	for section in ["profiles", "abilities", "attacks"]:
		if typeof(data.get(section, null)) != TYPE_DICTIONARY:
			errors.append("%s must be an object" % section)
	if not errors.is_empty():
		return errors
	for role in data["profiles"]:
		_validate_profile(String(role), data["profiles"][role], errors)
	for id in data["abilities"]:
		_validate_ability(String(id), data["abilities"][id], errors)
	for role in data["profiles"]:
		if not data["attacks"].has(role):
			errors.append("attacks.%s missing" % role)
	for role in data["attacks"]:
		if not data["profiles"].has(role):
			errors.append("attacks.%s has no profile" % role)
			continue
		_validate_attacks(String(role), data["attacks"][role], data["abilities"], errors)
	for id in data["abilities"]:
		var def = data["abilities"][id]
		if typeof(def) == TYPE_DICTIONARY and def.has("role"):
			var role := String(def["role"])
			if not data["profiles"].has(role):
				errors.append("ability %s: role '%s' has no profile" % [id, role])
			elif String(def.get("kind", "")) in ["attack", "counter"] and not (data["attacks"].get(role, {}).get("abilities", {}) as Dictionary).has(id):
				errors.append("ability %s: needs its AttackDefinition in attacks.%s.abilities.%s (the swing / the riposte)" % [id, role, id])
	return errors


# ---- internals ------------------------------------------------------------------------------
static func _ensure() -> void:
	if not _base.is_empty():
		return
	var text := FileAccess.get_file_as_string(DATA_PATH)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("balance_data: %s is missing or not valid JSON" % DATA_PATH)
		parsed = {"tuning_id": "invalid", "schema": SCHEMA, "profiles": {}, "abilities": {}, "attacks": {}}
	else:
		var errors := validate(parsed)
		if not errors.is_empty():
			push_error("balance_data: %s is invalid: %s" % [DATA_PATH, "; ".join(errors)])
	_base = _normalise(parsed)
	_install(_base.duplicate(true), false)


static func _install(data: Dictionary, overridden: bool) -> void:
	_active = data
	_overridden = overridden
	_revision += 1
	_hash = JSON.stringify(_active, "", true).sha256_text()


static func _merge(into: Dictionary, patch: Dictionary) -> Dictionary:
	for key in patch:
		if into.has(key) and typeof(into[key]) == TYPE_DICTIONARY and typeof(patch[key]) == TYPE_DICTIONARY:
			_merge(into[key], patch[key])
		else:
			into[key] = patch[key]
	return into


static func _validate_profile(role: String, p, errors: Array) -> void:
	if typeof(p) != TYPE_DICTIONARY:
		errors.append("profiles.%s must be an object" % role)
		return
	var known: Array = PROFILE_STR_KEYS + PROFILE_INT_KEYS + PROFILE_FLOAT_KEYS
	for key in known:
		if not p.has(key):
			errors.append("profiles.%s.%s missing" % [role, key])
		elif key in PROFILE_STR_KEYS:
			if typeof(p[key]) != TYPE_STRING:
				errors.append("profiles.%s.%s must be a string" % [role, key])
		elif not _is_number(p[key]):
			errors.append("profiles.%s.%s must be a number" % [role, key])
	for key in p:
		if not (key in known):
			errors.append("profiles.%s.%s is not a known key" % [role, key])
	if not errors.is_empty():
		return
	# Ranges that would silently break the simulation.
	for key in ["radius", "poise", "poise_regen_per_tick", "sprint_mult", "block_arc_deg", "parry_arc_deg",
			"dodge_distance", "accel", "decel", "turn_free", "turn_locked", "turn_attack_startup",
			"turn_attack_startup_locked", "block_move_mult"]:
		if float(p[key]) <= 0.0:
			errors.append("profiles.%s.%s must be > 0" % [role, key])
	if float(p["armor"]) < 0.0 or float(p["armor"]) >= 1.0:
		errors.append("profiles.%s.armor must be in [0, 1)" % role)
	for key in ["dodge_ticks", "parry_recovery_ticks", "hit_react_ticks"]:
		if int(p[key]) < 1:
			errors.append("profiles.%s.%s must be >= 1" % [role, key])
	if int(p["dodge_iframe_start"]) < 0 or int(p["dodge_iframe_end"]) <= int(p["dodge_iframe_start"]) \
			or int(p["dodge_iframe_end"]) > int(p["dodge_ticks"]):
		errors.append("profiles.%s: dodge i-frames must satisfy 0 <= start < end <= dodge_ticks" % role)


static func _validate_ability(id: String, a, errors: Array) -> void:
	if typeof(a) != TYPE_DICTIONARY:
		errors.append("abilities.%s must be an object" % id)
		return
	var kind := String(a.get("kind", ""))
	if not ABILITY_REQUIRED.has(kind):
		errors.append("abilities.%s.kind '%s' is unknown" % [id, kind])
		return
	for key in ABILITY_REQUIRED[kind]:
		if not a.has(key):
			errors.append("abilities.%s.%s missing" % [id, key])
	for key in a:
		if not ABILITY_KEY_TYPES.has(key):
			errors.append("abilities.%s.%s is not a known key" % [id, key])
			continue
		var want: String = ABILITY_KEY_TYPES[key]
		var value = a[key]
		var ok: bool = (typeof(value) == TYPE_STRING) if want == "string" \
				else (typeof(value) == TYPE_BOOL) if want == "bool" else _is_number(value)
		if not ok:
			errors.append("abilities.%s.%s must be a %s" % [id, key, want])
	if kind == "counter" and a.has("counter_start") and a.has("counter_end") and a.has("cast_ticks"):
		if int(a["counter_start"]) < 0 or int(a["counter_end"]) <= int(a["counter_start"]) \
				or int(a["cast_ticks"]) <= int(a["counter_end"]):
			errors.append("abilities.%s: need 0 <= counter_start < counter_end < cast_ticks" % id)


static func _validate_attacks(role: String, table, abilities: Dictionary, errors: Array) -> void:
	if typeof(table) != TYPE_DICTIONARY or typeof(table.get("light", null)) != TYPE_ARRAY \
			or typeof(table.get("heavy", null)) != TYPE_DICTIONARY or typeof(table.get("abilities", null)) != TYPE_DICTIONARY:
		errors.append("attacks.%s needs light[], heavy{}, abilities{}" % role)
		return
	if (table["light"] as Array).size() < 3:
		errors.append("attacks.%s.light needs at least 3 links" % role)
	var index := 0
	for entry in table["light"]:
		_validate_attack("attacks.%s.light[%d]" % [role, index], entry, errors)
		index += 1
	_validate_attack("attacks.%s.heavy" % role, table["heavy"], errors)
	for id in table["abilities"]:
		_validate_attack("attacks.%s.abilities.%s" % [role, id], table["abilities"][id], errors)


static func _attack_types() -> Dictionary:
	var out := {}
	var probe := AttackDefinition.new()
	for p in probe.get_property_list():
		if (p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE) and (p["usage"] & PROPERTY_USAGE_STORAGE):
			out[p["name"]] = p["type"]
	return out


static func _validate_attack(where: String, d, errors: Array) -> void:
	if typeof(d) != TYPE_DICTIONARY:
		errors.append("%s must be an object" % where)
		return
	var types := _attack_types()
	for key in ["id", "kind"]:
		if not d.has(key):
			errors.append("%s.%s missing" % [where, key])
	for key in d:
		if not types.has(key):
			errors.append("%s.%s is not an AttackDefinition field" % [where, key])
		elif key == "kind":
			if not (String(d[key]) in ATTACK_KINDS):
				errors.append("%s.kind must be one of %s" % [where, ATTACK_KINDS])
		elif key in ATTACK_STR_KEYS:
			if typeof(d[key]) != TYPE_STRING:
				errors.append("%s.%s must be a string" % [where, key])
		elif not _is_number(d[key]):
			errors.append("%s.%s must be a number" % [where, key])
	if d.has("startup_end") and d.has("active_end") and d.has("cancel_from") \
			and _is_number(d["startup_end"]) and _is_number(d["active_end"]) and _is_number(d["cancel_from"]):
		if not (0.0 <= float(d["startup_end"]) and float(d["startup_end"]) < float(d["active_end"])
				and float(d["active_end"]) <= float(d["cancel_from"]) + 0.0001 and float(d["cancel_from"]) <= 1.0):
			errors.append("%s: need startup_end < active_end <= cancel_from <= 1" % where)


static func _is_number(v) -> bool:
	return typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT


## Re-types every value from the key tables (JSON parses numbers as float) and copies deeply.
static func _normalise(raw: Dictionary) -> Dictionary:
	var out := {"tuning_id": String(raw["tuning_id"]), "schema": int(raw["schema"]),
			"profiles": {}, "abilities": {}, "attacks": {}}
	for role in raw["profiles"]:
		var p: Dictionary = raw["profiles"][role]
		var q := {}
		for key in p:
			if key in PROFILE_STR_KEYS:
				q[key] = String(p[key])
			elif key in PROFILE_INT_KEYS:
				q[key] = int(p[key])
			else:
				q[key] = float(p[key])
		out["profiles"][role] = q
	for id in raw["abilities"]:
		var a: Dictionary = raw["abilities"][id]
		var b := {}
		for key in a:
			match String(ABILITY_KEY_TYPES.get(key, "float")):
				"string": b[key] = String(a[key])
				"int": b[key] = int(a[key])
				"bool": b[key] = bool(a[key])
				_: b[key] = float(a[key])
		out["abilities"][id] = b
	for role in raw["attacks"]:
		var t: Dictionary = raw["attacks"][role]
		var lights: Array = []
		for entry in t["light"]:
			lights.append(_normalise_attack(entry))
		var abilities := {}
		for id in t["abilities"]:
			abilities[id] = _normalise_attack(t["abilities"][id])
		out["attacks"][role] = {"light": lights, "heavy": _normalise_attack(t["heavy"]), "abilities": abilities}
	return out


static func _normalise_attack(d: Dictionary) -> Dictionary:
	var out := {}
	for key in d:
		if key == "kind":
			out[key] = String(d[key])
		elif key in ATTACK_STR_KEYS:
			out[key] = String(d[key])
		elif key in ATTACK_INT_KEYS:
			out[key] = int(d[key])
		else:
			out[key] = float(d[key])
	return out


static func _build_attack(d: Dictionary) -> AttackDefinition:
	var def := AttackDefinition.new()
	for key in d:
		if key == "kind":
			def.kind = ATTACK_KINDS.find(String(d[key]))
		else:
			def.set(key, d[key])
	return def
