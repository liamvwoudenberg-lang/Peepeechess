class_name CombatInputBuilder
extends RefCounted
## Client-side helper that produces contract-valid CombatInput dictionaries: increments the
## packet sequence, keeps the cumulative press counters, and clamps/wraps values into schema
## range. Used by the local keyboard/gamepad source, the AI and the tests. It can only express
## intent; there is no way to put HP, damage or results into an input.

var match_id: String
var battle_id: String
var player_id: String
var sequence: int = 0
var client_tick: int = 0
var counters: Dictionary = {"light": 0, "heavy": 0, "dodge": 0, "parry": 0, "ability": 0}


func _init(p_match_id: String, p_battle_id: String, p_player_id: String) -> void:
	match_id = p_match_id
	battle_id = p_battle_id
	player_id = p_player_id


## Records one press of an action ("light", "heavy", "dodge", "parry", "ability").
func press(action: String) -> void:
	counters[action] = int(counters[action]) + 1


func build(move_x: float, move_z: float, yaw: float, lock_target: bool, sprint: bool, block: bool) -> Dictionary:
	sequence += 1
	client_tick += 1
	var move := Vector2(move_x, move_z)
	if move.length() > 1.0:
		move = move.normalized()
	return {
		"schemaVersion": 1,
		"matchId": match_id,
		"battleId": battle_id,
		"playerId": player_id,
		"sequence": sequence,
		"clientTick": client_tick,
		"moveX": clampf(move.x, -1.0, 1.0),
		"moveZ": clampf(move.y, -1.0, 1.0),
		"yawRadians": clampf(CombatConstants.wrap_angle(yaw), -PI, PI),
		"lockTarget": lock_target,
		"sprint": sprint,
		"block": block,
		"light": int(counters["light"]),
		"heavy": int(counters["heavy"]),
		"dodge": int(counters["dodge"]),
		"parry": int(counters["parry"]),
		"ability": int(counters["ability"]),
	}
