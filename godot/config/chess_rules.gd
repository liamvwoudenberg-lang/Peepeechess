extends RefCounted
## Loader and validator for config/chess_rules.json: every tunable rule switch and number outside combat balance (time controls,
## computer levels, duel AI levels, the chess computer's Battle Chess model, King's last stand ordering, campaign and training
## constants). Use through preload; every getter returns a typed COPY, so callers can never mutate the active data.
##
##   const ChessRules := preload("res://config/chess_rules.gd")
##   ChessRules.time_controls()        # [[label, initial_ms, increment_ms], ...]
##
## Chess legality itself (FIDE rules) is deliberately NOT configurable: see `_fixed_rules` in the file and docs/game/RULES_CONFIG.md.
## Combat balance is config/balance.json (loader combat/data/balance_data.gd).
##
## Development override (debug builds only, never in release builds or during online/ranked matches):
## `user://config_override/chess_rules.json` or `--config-dir=<dir>` holding a chess_rules.json with just the keys to change;
## dictionaries merge key by key, arrays are replaced whole.
const Balance := preload("res://combat/data/balance_data.gd")
const Meta := preload("res://config/config_meta.gd")

const DATA_PATH := "res://config/chess_rules.json"
const META_PATH := "res://config/chess_rules_meta.json"
const SOURCE_LABEL := "config/chess_rules.json"
const OVERRIDE_PATH := "user://config_override/chess_rules.json"
const SCHEMA := 1

const LEVEL_INT_KEYS := ["max_depth", "q_ply", "node_limit", "time_ms", "noise", "margin"]
const LEVEL_FLOAT_KEYS := ["blunder", "skill"]
const DUEL_INT_PARAMS := ["react_extra", "timing_jitter", "follow_max"]
const DUEL_LEVELS := ["easy", "normal", "hard", "expert"]

static var _base: Dictionary = {}
static var _active: Dictionary = {}
static var _overridden := false
static var _override_errors: Array = []


# ---- public getters ---------------------------------------------------------------------------
static func time_controls() -> Array:
	var out: Array = []
	for entry in _d()["time_controls"]:
		out.append([String(entry["label"]), int(entry["initial_ms"]), int(entry["increment_ms"])])
	return out


## {level(int): {name, max_depth, q_ply, node_limit, time_ms, noise, margin, blunder, skill, style, attack_style}}
static func computer_levels() -> Dictionary:
	var out := {}
	for key in _d()["computer_levels"]:
		var raw: Dictionary = _d()["computer_levels"][key]
		var level := {}
		for field in raw:
			if field in LEVEL_INT_KEYS:
				level[field] = int(raw[field])
			elif field in LEVEL_FLOAT_KEYS:
				level[field] = float(raw[field])
			else:
				level[field] = String(raw[field])
		out[int(key)] = level
	return out


static func min_computer_level() -> int:
	return int(computer_levels().keys().min())


static func max_computer_level() -> int:
	return int(computer_levels().keys().max())


## {"easy": {label, style, skill, params: {...}, summary}, ...}
static func duel_ai_levels() -> Dictionary:
	var out := {}
	for id in _d()["duel_ai_levels"]:
		var raw: Dictionary = _d()["duel_ai_levels"][id]
		var params := {}
		for key in raw.get("params", {}):
			params[key] = int(raw["params"][key]) if key in DUEL_INT_PARAMS else float(raw["params"][key])
		out[id] = {"label": String(raw["label"]), "style": String(raw["style"]), "skill": float(raw["skill"]), "params": params, "summary": String(raw["summary"])}
	return out


static func battle_fight_value() -> Dictionary:
	var out := {}
	for role in _d()["battle_ai"]["fight_value"]:
		out[role] = int(_d()["battle_ai"]["fight_value"][role])
	return out


static func battle_tier() -> Dictionary:
	var out := {}
	for role in _d()["battle_ai"]["tier"]:
		out[role] = float(_d()["battle_ai"]["tier"][role])
	return out


static func royal_piece_values() -> Dictionary:
	var out := {}
	for role in _d()["royal"]["piece_values"]:
		out[role] = int(_d()["royal"]["piece_values"][role])
	return out


static func campaign_start_lives() -> int:
	return int(_d()["campaign"]["start_lives"])


static func campaign_max_boon_stack() -> int:
	return int(_d()["campaign"]["max_boon_stack"])


static func campaign_boon_offer_size() -> int:
	return int(_d()["campaign"]["boon_offer_size"])


static func campaign_level_by_encounter() -> Array:
	var out: Array = []
	for level in _d()["campaign"]["level_by_encounter"]:
		out.append(String(level))
	return out


## {"vitality": {title, text, health?, stamina?, cost?, regen?}, ...} (numbers as floats)
static func campaign_boons() -> Dictionary:
	var out := {}
	for id in _d()["campaign"]["boons"]:
		var raw: Dictionary = _d()["campaign"]["boons"][id]
		var boon := {}
		for key in raw:
			boon[key] = String(raw[key]) if key in ["title", "text"] else float(raw[key])
		out[id] = boon
	return out


static func training_combo_window_ticks() -> int:
	return int(_d()["training"]["combo_window_ticks"])


static func training_default_counter_window_ticks() -> int:
	return int(_d()["training"]["default_counter_window_ticks"])


static func training_whiff_punish_window_ticks() -> int:
	return int(_d()["training"]["whiff_punish_window_ticks"])


static func training_max_lesson_ticks() -> int:
	return int(_d()["training"]["max_lesson_ticks"])


static func snapshot() -> Dictionary:
	return _d().duplicate(true)


static func is_overridden() -> bool:
	_d()
	return _overridden


static func override_errors() -> Array:
	_d()
	return _override_errors.duplicate()


## Applies a patch on top of the shipped data (tests, the debug panel). Returns validation errors (empty = applied).
static func apply_override(patch: Dictionary) -> Array:
	_d()
	var merged := _merge(_base.duplicate(true), _strip(patch.duplicate(true)))
	var errors := validate(merged)
	if errors.is_empty():
		_active = merged
		_overridden = true
	return errors


static func clear_override() -> void:
	_d()
	_active = _base.duplicate(true)
	_overridden = false


## Forgets everything read so far (tests that swap files).
static func reset() -> void:
	_base = {}
	_active = {}
	_overridden = false
	_override_errors = []


# ---- validation ---------------------------------------------------------------------------------
static func validate(raw: Dictionary) -> Array:
	var data: Dictionary = _strip(raw.duplicate(true))
	var errors: Array = []
	if int(data.get("schema", -1)) != SCHEMA:
		errors.append("%s: schema must be %d" % [SOURCE_LABEL, SCHEMA])
	for section in ["time_controls", "computer_levels", "duel_ai_levels", "battle_ai", "royal", "campaign", "training"]:
		if not data.has(section):
			errors.append("%s: section %s is missing" % [SOURCE_LABEL, section])
	if not errors.is_empty():
		return errors
	if not data["time_controls"] is Array or (data["time_controls"] as Array).is_empty():
		errors.append("%s: time_controls must be a non-empty list" % SOURCE_LABEL)
	var levels = data["computer_levels"]
	if not levels is Dictionary:
		errors.append("%s: computer_levels must be an object keyed 1, 2, 3 ..." % SOURCE_LABEL)
	else:
		for number in range(1, levels.size() + 1):
			if not (levels as Dictionary).has(str(number)):
				errors.append("%s: computer_levels must be numbered 1..%d without gaps (missing %d)" % [SOURCE_LABEL, levels.size(), number])
		for key in levels:
			for needed in LEVEL_INT_KEYS + LEVEL_FLOAT_KEYS + ["name", "style", "attack_style"]:
				if not (levels[key] as Dictionary).has(needed):
					errors.append("%s: computer_levels.%s.%s is missing" % [SOURCE_LABEL, key, needed])
	if data["duel_ai_levels"] is Dictionary:
		for id in DUEL_LEVELS:
			if not (data["duel_ai_levels"] as Dictionary).has(id):
				errors.append("%s: duel_ai_levels.%s is missing (easy, normal, hard and expert are required)" % [SOURCE_LABEL, id])
	var campaign = data["campaign"]
	if campaign is Dictionary:
		var by_encounter = campaign.get("level_by_encounter", [])
		if not by_encounter is Array or by_encounter.size() != 12:
			errors.append("%s: campaign.level_by_encounter must list exactly 12 levels" % SOURCE_LABEL)
		else:
			for i in by_encounter.size():
				if String(by_encounter[i]) not in DUEL_LEVELS:
					errors.append("%s: campaign.level_by_encounter[%d] = %s must be one of %s" % [SOURCE_LABEL, i, by_encounter[i], ", ".join(DUEL_LEVELS)])
		if not campaign.get("boons", {}) is Dictionary or (campaign.get("boons", {}) as Dictionary).size() < int(campaign.get("boon_offer_size", 1)):
			errors.append("%s: campaign.boons needs at least boon_offer_size boons" % SOURCE_LABEL)
	if not errors.is_empty():
		return errors
	# every leaf against the metadata: type, range, unit, unknown names
	var meta: Dictionary = Meta.meta(META_PATH).get("paths", {})
	if meta.is_empty():
		return errors
	var flat: Dictionary = {}
	_flat(data, "", flat)
	for path in flat:
		if path == "schema":
			continue
		var spec = null
		for pattern in meta:
			if String(path).match(String(pattern)):
				spec = meta[pattern]
				break
		if spec == null:
			errors.append("%s: %s is not a known setting%s" % [SOURCE_LABEL, path, Meta._suggest(String(path), meta.keys())])
			continue
		Meta._check_value(flat[path], spec, path, SOURCE_LABEL, errors)
	return errors


# ---- internals ------------------------------------------------------------------------------------
static func _d() -> Dictionary:
	if _base.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if not parsed is Dictionary:
			push_error("%s is missing or not valid JSON" % SOURCE_LABEL)
			parsed = {}
		else:
			var errors := validate(parsed)
			if not errors.is_empty():
				push_error("%s is invalid: %s" % [SOURCE_LABEL, "; ".join(errors)])
		_base = _strip(parsed)
		_active = _base.duplicate(true)
		_overridden = false
		_load_dev_override()
	return _active


static func override_file() -> String:
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--config-dir="):
			return arg.substr("--config-dir=".length()).path_join("chess_rules.json")
	return ProjectSettings.globalize_path(OVERRIDE_PATH)


static func _load_dev_override() -> void:
	_override_errors = []
	if not Balance.dev_overrides_allowed():
		return
	var path := override_file()
	if not FileAccess.file_exists(path):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		_override_errors = ["%s is not a valid JSON object" % path]
		return
	var merged := _merge(_base.duplicate(true), _strip(parsed))
	var errors := validate(merged)
	if errors.is_empty():
		_active = merged
		_overridden = true
	else:
		_override_errors = errors
		push_warning("chess rules override %s ignored: %s" % [path, "; ".join(errors)])


static func _strip(value):
	if value is Dictionary:
		var out := {}
		for key in value:
			if String(key).begins_with("_"):
				continue
			out[key] = _strip(value[key])
		return out
	if value is Array:
		var items := []
		for item in value:
			items.append(_strip(item))
		return items
	return value


static func _merge(into: Dictionary, patch: Dictionary) -> Dictionary:
	for key in patch:
		if into.get(key) is Dictionary and patch[key] is Dictionary:
			_merge(into[key], patch[key])
		else:
			into[key] = patch[key]
	return into


static func _flat(value, prefix: String, out: Dictionary) -> void:
	if value is Dictionary:
		for key in value:
			_flat(value[key], String(key) if prefix.is_empty() else "%s.%s" % [prefix, key], out)
	elif value is Array:
		for i in value.size():
			_flat(value[i], "%s[%d]" % [prefix, i], out)
	else:
		out[prefix] = value
