class_name CombatInputState
extends RefCounted
## Authority-side bookkeeping for one seat's CombatInput stream (CONTRACTS.md rule 5).
##  * `last_sequence` strictly increases; stale or replayed packets are rejected.
##  * Action fields are cumulative press counters. A rise since the last accepted packet is
##    at most ONE edge for that packet; counters never decrease or reset within a battle.
##  * Held controls (move, sprint, block, lock) come from the most recent packet and are
##    neutralised once no packet has been accepted for INPUT_NEUTRAL_AFTER_TICKS ticks. The
##    seen counters are retained so a replay can never retrigger an action.

const ACTIONS: Array[String] = ["light", "heavy", "dodge", "parry", "ability"]

var last_sequence: int = 0
var last_accept_tick: int = 0
var has_input: bool = false

var move_x: float = 0.0
var move_z: float = 0.0
var yaw: float = 0.0
var lock_target: bool = false
var sprint: bool = false
var block: bool = false

var seen: Dictionary = {"light": 0, "heavy": 0, "dodge": 0, "parry": 0, "ability": 0}
var edges: Dictionary = {"light": false, "heavy": false, "dodge": false, "parry": false, "ability": false}


func clear_edges() -> void:
	for action in ACTIONS:
		edges[action] = false


## Builds this tick's intent and consumes pending edges.
func consume_intent(current_tick: int, fallback_yaw: float, accept_actions: bool) -> FighterIntent:
	var intent := FighterIntent.new()
	var fresh := has_input and (current_tick - last_accept_tick) <= CombatConstants.INPUT_NEUTRAL_AFTER_TICKS
	if fresh:
		intent.move_x = move_x
		intent.move_z = move_z
		intent.yaw = yaw
		intent.lock_target = lock_target
		intent.sprint = sprint
		intent.block_held = block
	else:
		intent.yaw = fallback_yaw
	if accept_actions:
		intent.light = edges["light"]
		intent.heavy = edges["heavy"]
		intent.dodge = edges["dodge"]
		intent.parry = edges["parry"]
		intent.ability = edges["ability"]
	clear_edges()
	return intent
