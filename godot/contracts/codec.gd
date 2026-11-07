class_name ContractCodec
extends RefCounted
## Implements only the JSON Schema keywords used in v1; fail closed on unknown keywords.
const SCHEMA_PATH = "res://contracts/v1/schema.json"
const KEYWORDS = ["$ref", "type", "properties", "required", "additionalProperties", "items", "minItems", "maxItems", "enum", "const", "anyOf", "minimum", "maximum", "pattern", "minLength", "maxLength"]
var schema: Dictionary

func _init() -> void:
	schema = JSON.parse_string(FileAccess.get_file_as_string(SCHEMA_PATH))

func valid(type_name: String, value: Variant) -> bool:
	return schema["$defs"].has(type_name) and _check(schema["$defs"][type_name], value)

func encode(type_name: String, value: Variant) -> Dictionary:
	if not valid(type_name, value):
		return {"ok": false, "code": "INVALID_PAYLOAD"}
	return {"ok": true, "text": JSON.stringify(value, "", true, true)}

func decode(type_name: String, text: String) -> Dictionary:
	var parser = JSON.new()
	if parser.parse(text) != OK:
		return {"ok": false, "code": "INVALID_PAYLOAD"}
	if not valid(type_name, parser.data):
		return {"ok": false, "code": "INVALID_PAYLOAD"}
	return {"ok": true, "value": parser.data}

func _check(rule: Dictionary, value: Variant) -> bool:
	for keyword in rule:
		if keyword not in KEYWORDS:
			return false
	if rule.has("$ref"):
		var name: String = rule["$ref"].get_slice("/", 2)
		return schema["$defs"].has(name) and _check(schema["$defs"][name], value)
	if rule.has("anyOf"):
		for candidate in rule.anyOf:
			if _check(candidate, value):
				return true
		return false
	if rule.has("const") and (typeof(value) == TYPE_BOOL or value != rule["const"]):
		return false
	if rule.has("enum") and value not in rule["enum"]:
		return false
	var kind: String = rule.get("type", "")
	match kind:
		"object":
			if not value is Dictionary:
				return false
			for key in rule.required:
				if not value.has(key):
					return false
			for key in value:
				if not rule.properties.has(key) or not _check(rule.properties[key], value[key]):
					return false
		"array":
			if not value is Array or value.size() < rule.minItems or value.size() > rule.maxItems:
				return false
			for item in value:
				if not _check(rule.items, item):
					return false
		"string":
			if not value is String or value.length() < rule.get("minLength", 0) or value.length() > rule.get("maxLength", 2147483647):
				return false
			if rule.has("pattern"):
				var regex = RegEx.new()
				if regex.compile(rule.pattern) != OK or regex.search(value) == null:
					return false
		"integer", "number":
			if not (value is int or value is float) or not is_finite(float(value)):
				return false
			if kind == "integer" and floor(value) != value:
				return false
			if value < rule.minimum or value > rule.maximum:
				return false
		"boolean":
			if not value is bool:
				return false
		"null":
			if value != null:
				return false
	return true
