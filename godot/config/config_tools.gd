extends RefCounted
## Helpers shared by the config command-line tools (godot/tools/config_*.gd) and the debug balance panel.

## Flattens nested JSON-shaped data to {"a.b.c": leaf}. Arrays of numbers stay one leaf; arrays of objects get [i] in the path.
static func flatten(value, prefix: String = "", out: Dictionary = {}) -> Dictionary:
	if value is Dictionary:
		for key in value:
			if String(key).begins_with("_"):
				continue
			flatten(value[key], key if prefix.is_empty() else "%s.%s" % [prefix, key], out)
	elif value is Array and not value.is_empty() and value[0] is Dictionary:
		for i in value.size():
			flatten(value[i], "%s[%d]" % [prefix, i], out)
	else:
		out[prefix] = value
	return out


## Differences between two flattened tables: [{"path", "old", "new"}] (missing side = null), sorted by path.
static func diff(a: Dictionary, b: Dictionary) -> Array:
	var rows: Array = []
	var paths: Dictionary = {}
	for key in a:
		paths[key] = true
	for key in b:
		paths[key] = true
	var keys: Array = paths.keys()
	keys.sort()
	for key in keys:
		var old = a.get(key, null)
		var new = b.get(key, null)
		if not _same(old, new):
			rows.append({"path": key, "old": old, "new": new})
	return rows


## A value as a designer writes it: 2.0 shows as 2, 0.25 stays 0.25, lists show each number the same way.
static func show(value) -> String:
	if value is float or value is int:
		return str(int(value)) if float(value) == roundf(float(value)) else str(value)
	if value is Array:
		var parts: PackedStringArray = []
		for item in value:
			parts.append(show(item))
		return "[" + ", ".join(parts) + "]"
	return str(value)


static func _same(x, y) -> bool:
	if (x is float or x is int) and (y is float or y is int):
		return absf(float(x) - float(y)) < 0.0000001
	return typeof(x) == typeof(y) and str(x) == str(y) if x is Array or y is Array else x == y


static func format_diff(rows: Array) -> String:
	var lines: PackedStringArray = []
	for row in rows:
		lines.append("%s: %s -> %s" % [row["path"], "(absent)" if row["old"] == null else show(row["old"]), "(absent)" if row["new"] == null else show(row["new"])])
	return "\n".join(lines)


## Reads a JSON file (res://, user:// or an absolute path). Returns {} when missing or invalid.
static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## The shipped file as it was committed at HEAD (via git); {} when git or the file is unavailable.
static func git_head_json(repo_path: String) -> Dictionary:
	var output: Array = []
	var code := OS.execute("git", ["show", "HEAD:" + repo_path], output, true)
	if code != 0 or output.is_empty():
		return {}
	var parsed = JSON.parse_string(String(output[0]))
	return parsed if parsed is Dictionary else {}
