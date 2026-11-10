class_name FighterIntent
extends RefCounted
## One tick of already-validated control intent for a fighter. Built by the simulation from the
## latest accepted CombatInput; it never carries HP, damage or any trusted state.
## Action fields are one-tick *edges* (a press happened), derived from cumulative counters.

var move_x := 0.0
var move_z := 0.0
var yaw := 0.0
var lock_target := false
var sprint := false
var block_held := false
var light := false
var heavy := false
var dodge := false
var parry := false
var ability := false


func move_vector() -> Vector3:
	return Vector3(move_x, 0.0, move_z)


func has_move() -> bool:
	return move_x * move_x + move_z * move_z > 0.0025


func has_edge() -> bool:
	return light or heavy or dodge or parry or ability


## Highest-priority pressed action, or "" if none. Priority matches the state machine.
func edge_action() -> String:
	if ability:
		return "ability"
	if dodge:
		return "dodge"
	if parry:
		return "parry"
	if heavy:
		return "heavy"
	if light:
		return "light"
	return ""


static func neutral(facing_yaw: float = 0.0) -> FighterIntent:
	var intent := FighterIntent.new()
	intent.yaw = facing_yaw
	return intent
