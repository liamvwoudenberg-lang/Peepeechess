class_name TrainingOpponent
extends RefCounted
## The fixed opponent of a lesson / Free Practice, playing through the same CombatInput channel as everybody else.
##   idle           stands still and faces the player (a training dummy)
##   passive_block  stands still, faces the player and keeps its guard up
##   attack_only    CombatAI "aggressive" with defences switched off (swings at the player, never blocks, parries or dodges)
##   normal         CombatAI at the chosen difficulty (AIDifficulty), the real duel opponent
## It only reads the public snapshot, exactly like CombatAI: it never sees the player's inputs or any future tick.

var behaviour: String = "idle"
var level: String = "normal"
var builder: CombatInputBuilder
var ai: CombatAI = null


func _init(p_behaviour: String, p_level: String, p_builder: CombatInputBuilder, my_stats: Dictionary, opp_stats: Dictionary, seed_value: int) -> void:
	behaviour = p_behaviour
	level = p_level
	builder = p_builder
	ai = AIDifficulty.make_behaviour_ai(behaviour, level, builder, my_stats, opp_stats, seed_value)


## One packet per tick from the public snapshot.
func packet(snapshot: Dictionary) -> Dictionary:
	if ai != null:
		return ai.think(snapshot)
	var fighters: Array = snapshot["fighters"]
	var me: Dictionary = fighters[0] if fighters[0]["playerId"] == builder.player_id else fighters[1]
	var other: Dictionary = fighters[1] if fighters[0]["playerId"] == builder.player_id else fighters[0]
	var to := Vector3(float(other["position"]["x"]) - float(me["position"]["x"]), 0.0, float(other["position"]["z"]) - float(me["position"]["z"]))
	var yaw := CombatConstants.yaw_of(to) if to.length() > 0.01 else float(me["yawRadians"])
	return builder.build(0.0, 0.0, yaw, true, false, behaviour == "passive_block")
