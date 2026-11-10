class_name StrictNetworkJson
extends RefCounted
## Duplicate-aware pre-scan before Godot JSON discards repeated keys.
var _text = ""
var _at = 0
var _valid = true

func decode(bytes: PackedByteArray, maximum: int) -> Dictionary:
	if bytes.is_empty() or bytes.size() > maximum:
		return {"ok": false}
	if not _utf8(bytes):
		return {"ok": false}
	_text = bytes.get_string_from_utf8()
	if _text.to_utf8_buffer() != bytes:
		return {"ok": false}
	_at = 0
	_valid = true
	_value(0)
	_space()
	if not _valid or _at != _text.length():
		return {"ok": false}
	var parser = JSON.new()
	if parser.parse(_text) != OK:
		return {"ok": false}
	return {"ok": true, "value": parser.data}

func _utf8(bytes: PackedByteArray) -> bool:
	var i = 0
	while i < bytes.size():
		var first = bytes[i]
		if first < 128:
			i += 1
			continue
		var count = 2 if first >= 194 and first <= 223 else (3 if first >= 224 and first <= 239 else (4 if first >= 240 and first <= 244 else 0))
		if count == 0 or i + count > bytes.size():
			return false
		for j in range(1, count):
			if bytes[i + j] < 128 or bytes[i + j] > 191:
				return false
		var second = bytes[i + 1]
		if (first == 224 and second < 160) or (first == 237 and second >= 160) or (first == 240 and second < 144) or (first == 244 and second >= 144):
			return false
		i += count
	return true

func _space() -> void:
	while _at < _text.length() and _text[_at] in [" ", "\t", "\n", "\r"]:
		_at += 1

func _string() -> Variant:
	var start = _at
	_at += 1
	while _at < _text.length():
		var c = _text[_at]
		_at += 1
		if c == "\\":
			_at += 1
		elif c == '"':
			var parser = JSON.new()
			if parser.parse(_text.substr(start, _at - start)) == OK and parser.data is String:
				return parser.data
			break
	_valid = false
	return null

func _take(c: String) -> bool:
	_space()
	if _at >= _text.length() or _text[_at] != c:
		_valid = false
		return false
	_at += 1
	return true

func _value(depth: int) -> void:
	_space()
	if depth > 32 or _at >= _text.length():
		_valid = false
		return
	var c = _text[_at]
	if c == '"':
		_string()
	elif c == "{" or c == "[":
		_at += 1
		_space()
		var end = "}" if c == "{" else "]"
		var keys = {}
		if _at < _text.length() and _text[_at] == end:
			_at += 1
			return
		while _valid:
			if c == "{":
				_space()
				if _at >= _text.length() or _text[_at] != '"':
					_valid = false
					return
				var key = _string()
				if not _valid or keys.has(key):
					_valid = false
					return
				keys[key] = true
				if not _take(":"):
					return
			_value(depth + 1)
			_space()
			if _at < _text.length() and _text[_at] == end:
				_at += 1
				return
			if not _take(","):
				return
	else:
		var start = _at
		while _at < _text.length() and _text[_at] not in [",", "}", "]", " ", "\t", "\r", "\n"]:
			_at += 1
		if _at == start:
			_valid = false
		var token = _text.substr(start, _at - start).to_lower()
		if token.length() > 64:
			_valid = false
		if token.contains("e"):
			var exponent = token.get_slice("e", 1)
			if exponent.length() > 5 or (exponent.is_valid_int() and (int(exponent) > 308 or int(exponent) < -324)):
				_valid = false
