class_name NetworkWireCodec
extends "res://contracts/codec.gd"
const GAME_ID = "https://peepeechess.invalid/contracts/v1/schema.json#/$defs/"
const GAME_TYPES = ["ChessMoveRequest", "CombatInput", "CombatSnapshot", "BattleResult", "ProtocolError", "MatchState"]
const CLIENT_TYPES = ["Hello", "CreateMatch", "JoinMatch", "MatchCommand", "Ping", "ChessMoveRequest", "CombatInput"]
const SERVER_TYPES = ["Welcome", "Ack", "ProtocolError", "MatchFrame", "Pong", "CombatSnapshot", "ClockSync"]
const MAX_CLIENT_BYTES = 65536
const MAX_SERVER_BYTES = 1048576
var _game = preload("res://contracts/codec.gd").new()
var _strict = preload("res://network/strict_json.gd").new()

func _init() -> void:
	schema = JSON.parse_string(FileAccess.get_file_as_string("res://contracts/network/v1/schema.json"))

func _check(rule: Dictionary, value: Variant) -> bool:
	if rule.get("$ref", "").begins_with(GAME_ID):
		return _game.valid(rule["$ref"].trim_prefix(GAME_ID), value)
	return super._check(rule, value)

func valid(type_name: String, value: Variant) -> bool:
	return _game.valid(type_name, value) if type_name in GAME_TYPES else super.valid(type_name, value)

func unpack(bytes: PackedByteArray, maximum: int) -> Dictionary:
	var parsed = _strict.decode(bytes, maximum)
	if not parsed.ok or not parsed.value is Dictionary:
		return {"ok": false, "code": "INVALID_PAYLOAD"}
	var frame: Dictionary = parsed.value
	if frame.size() != 2 or not frame.get("type") is String or not frame.get("payload") is Dictionary:
		return {"ok": false, "code": "INVALID_PAYLOAD"}
	if frame.payload.get("schemaVersion") != 1 or (frame.type == "Hello" and frame.payload.get("protocol") != "peepeechess-enet-v1"):
		return {"ok": false, "code": "UNSUPPORTED_VERSION"}
	if not valid(frame.type, frame.payload):
		return {"ok": false, "code": "INVALID_PAYLOAD"}
	return {"ok": true, "type": frame.type, "payload": frame.payload}

func pack(type_name: String, payload: Dictionary) -> PackedByteArray:
	if not valid(type_name, payload):
		return PackedByteArray()
	return JSON.stringify({"type": type_name, "payload": payload}, "", true, true).to_utf8_buffer()
