extends RefCounted
## Checks a tuning file against its metadata (config/balance_meta.json): every value's type, unit-bearing range and every key's
## existence. Errors name the file, the key path, the value, the allowed range and the unit, e.g.
##   config/balance.json: profiles.n.armor = -0.3 is below the minimum 0 (unit: fraction)
## The metadata is also the source of the generated reference table (see config_reference.gd).

static var _cache: Dictionary = {}


static func meta(path: String) -> Dictionary:
	if not _cache.has(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		_cache[path] = parsed if parsed is Dictionary else {}
	return _cache[path]


static func check(data: Dictionary, label: String, meta_path: String) -> Array:
	var m := meta(meta_path)
	var errors: Array = []
	if m.is_empty():
		return errors   # no metadata shipped (e.g. a stripped test pack): only the structural checks run
	var allowed_top := ["tuning_id", "schema", "profiles", "abilities", "attacks", "duel_length", "hit_stun", "pacing", "attacker_edge"]
	for key in data:
		if String(key) not in allowed_top:
			errors.append("%s: %s is not a known section%s" % [label, key, _suggest(String(key), allowed_top)])
	var profiles: Dictionary = data.get("profiles", {})
	for role in profiles:
		_check_keys(profiles[role], m.get("profiles", {}), "profiles.%s" % role, label, errors)
	var abilities: Dictionary = data.get("abilities", {})
	for id in abilities:
		_check_keys(abilities[id], m.get("abilities", {}), "abilities.%s" % id, label, errors)
	var attacks: Dictionary = data.get("attacks", {})
	for role in attacks:
		var table = attacks[role]
		if not table is Dictionary:
			continue
		var lights = table.get("light", [])
		if lights is Array:
			for i in lights.size():
				_check_keys(lights[i], m.get("attacks", {}), "attacks.%s.light[%d]" % [role, i], label, errors)
		_check_keys(table.get("heavy", {}), m.get("attacks", {}), "attacks.%s.heavy" % role, label, errors)
		var ability_attacks = table.get("abilities", {})
		if ability_attacks is Dictionary:
			for id in ability_attacks:
				_check_keys(ability_attacks[id], m.get("attacks", {}), "attacks.%s.abilities.%s" % [role, id], label, errors)
	var paths: Dictionary = m.get("paths", {})
	for key in ["tuning_id", "schema"]:
		if data.has(key):
			_check_value(data[key], paths.get(key, {}), key, label, errors)
	for section in ["duel_length", "hit_stun", "pacing", "attacker_edge"]:
		if data.has(section):
			_walk(data[section], section, paths, label, errors)
	return errors


static func _check_keys(entry, spec: Dictionary, path: String, label: String, errors: Array) -> void:
	if not entry is Dictionary:
		return   # the structural validator reports non-objects
	for key in entry:
		var key_path := "%s.%s" % [path, key]
		if not spec.has(key):
			errors.append("%s: %s is not a known setting%s" % [label, key_path, _suggest(String(key), spec.keys())])
			continue
		_check_value(entry[key], spec[key], key_path, label, errors)


static func _walk(value, path: String, paths: Dictionary, label: String, errors: Array) -> void:
	var spec = _lookup(path, paths)
	if spec != null:
		_check_value(value, spec, path, label, errors)
		return
	if value is Dictionary:
		for key in value:
			_walk(value[key], "%s.%s" % [path, key], paths, label, errors)
	else:
		var parent := path.substr(0, path.rfind("."))
		var siblings: Array = []
		for known in paths:
			if String(known).begins_with(parent + "."):
				siblings.append(String(known).substr(parent.length() + 1))
		errors.append("%s: %s is not a known setting%s" % [label, path, _suggest(path.substr(path.rfind(".") + 1), siblings)])


static func _lookup(path: String, paths: Dictionary):
	if paths.has(path):
		return paths[path]
	var cut := path.rfind(".")
	if cut >= 0 and paths.has(path.substr(0, cut) + ".*"):
		return paths[path.substr(0, cut) + ".*"]
	return null


static func _check_value(value, spec: Dictionary, path: String, label: String, errors: Array) -> void:
	if spec.is_empty():
		return
	var type := String(spec.get("type", ""))
	var unit := String(spec.get("unit", ""))
	var unit_text := " (unit: %s)" % unit if not unit.is_empty() else ""
	match type:
		"float", "int":
			if not (value is float or value is int) or value is bool:
				errors.append("%s: %s = %s must be a number%s" % [label, path, str(value), unit_text])
				return
			if type == "int" and absf(float(value) - roundf(float(value))) > 0.0001:
				errors.append("%s: %s = %s must be a whole number%s" % [label, path, str(value), unit_text])
			if spec.has("min") and float(value) < float(spec["min"]):
				errors.append("%s: %s = %s is below the minimum %s%s" % [label, path, _n(value), _n(spec["min"]), unit_text])
			if spec.has("max") and float(value) > float(spec["max"]):
				errors.append("%s: %s = %s is above the maximum %s%s" % [label, path, _n(value), _n(spec["max"]), unit_text])
		"string":
			if not value is String:
				errors.append("%s: %s = %s must be text" % [label, path, str(value)])
		"bool":
			if not value is bool:
				errors.append("%s: %s = %s must be true or false" % [label, path, str(value)])
		_:
			pass   # enums and pairs are checked by the structural validator


static func _n(v) -> String:
	return str(int(v)) if float(v) == roundf(float(v)) else str(v)


static func _suggest(word: String, options: Array) -> String:
	var best := ""
	var best_distance := 99
	for option in options:
		var d := _distance(word, String(option))
		if d < best_distance:
			best_distance = d
			best = String(option)
	return " (did you mean %s?)" % best if best_distance <= 3 and not best.is_empty() else ""


static func _distance(a: String, b: String) -> int:
	var row: Array = []
	for j in b.length() + 1:
		row.append(j)
	for i in range(1, a.length() + 1):
		var previous: int = row[0]
		row[0] = i
		for j in range(1, b.length() + 1):
			var current: int = row[j]
			var cost := 0 if a[i - 1] == b[j - 1] else 1
			row[j] = mini(mini(row[j] + 1, row[j - 1] + 1), previous + cost)
			previous = current
	return row[b.length()]
