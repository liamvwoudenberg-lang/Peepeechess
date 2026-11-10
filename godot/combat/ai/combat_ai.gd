class_name CombatAI
extends RefCounted
## Simple opponent that plays through the SAME channel as a human: it reads only the public
## CombatSnapshot (positions, states, HP, stamina, tick counters) plus the public stats of both
## fighters, and answers with CombatInput packets built by CombatInputBuilder. It has no access
## to the simulation's internals, so it can neither cheat nor bypass admission rules.
##
## Behaviour: approach to spear/sword range, strafe, attack in light chains with occasional
## heavies, react to the opponent's attack start after a skill-dependent reaction delay by
## parrying, blocking or dodging, back off and guard when low on stamina, use its ability.

var builder: CombatInputBuilder
var rng := RandomNumberGenerator.new()
## 0..1: scales reaction speed and how often a defence is attempted.
var skill: float = 0.6

var _my_id: String
var _my_stats: Dictionary
var _opp_stats: Dictionary

var _prev_opp_attacking := false
var _react_in := -1
var _scheduled_action := ""
var _scheduled_in := 0
var _block_ticks := 0
var _attack_cooldown := 0
var _follow_up_in := -1
var _follow_ups_left := 0
var _strafe_dir := 1.0
var _strafe_ticks := 0
var _opp_lunge := false


func _init(input_builder: CombatInputBuilder, my_stats: Dictionary, opponent_stats: Dictionary,
		seed: int = 1, p_skill: float = 0.6) -> void:
	builder = input_builder
	_my_id = input_builder.player_id
	_my_stats = my_stats
	_opp_stats = opponent_stats
	skill = p_skill
	rng.seed = seed
	_strafe_dir = 1.0 if rng.randf() < 0.5 else -1.0


## One decision per simulation tick. Returns a contract-valid CombatInput.
func think(snapshot: Dictionary) -> Dictionary:
	var fighters: Array = snapshot["fighters"]
	var me: Dictionary = fighters[0] if fighters[0]["playerId"] == _my_id else fighters[1]
	var opp: Dictionary = fighters[1] if fighters[0]["playerId"] == _my_id else fighters[0]
	var my_pos := _pos(me)
	var to_opp := _pos(opp) - my_pos
	var dist := to_opp.length()
	var yaw_to := CombatConstants.yaw_of(to_opp) if dist > 0.01 else float(me["yawRadians"])

	var live := int(snapshot["countdownTicksRemaining"]) == 0 and snapshot["result"] == null
	if not live:
		return builder.build(0.0, 0.0, yaw_to, true, false, false)

	var dir := to_opp.normalized() if dist > 0.01 else Vector3.FORWARD
	var side := Vector3(dir.z, 0.0, -dir.x)  # perpendicular, for circling
	var move := Vector3.ZERO
	var sprint := false
	var block := false
	var my_state: String = me["state"]
	var free := my_state == "Idle" or my_state == "Moving" or my_state == "Blocking"

	# ---- read the opponent's attack and schedule a defence ---------------------------------
	var opp_attacking: bool = opp["state"] == "Attacking" or opp["state"] == "AbilityCasting"
	if opp_attacking and not _prev_opp_attacking:
		_opp_lunge = opp["state"] == "AbilityCasting"
		_react_in = _reaction_ticks()
	elif not opp_attacking:
		_react_in = -1
	_prev_opp_attacking = opp_attacking

	if _react_in > 0:
		_react_in -= 1
	elif _react_in == 0:
		_react_in = -1
		if dist < (6.0 if _opp_lunge else 3.4) and rng.randf() < 0.45 + 0.5 * skill:
			_choose_defence(opp, dist)

	if _scheduled_in > 0:
		_scheduled_in -= 1
		if _scheduled_in == 0 and _scheduled_action != "":
			builder.press(_scheduled_action)
			_scheduled_action = ""
	if _block_ticks > 0:
		_block_ticks -= 1
		block = true
	if _attack_cooldown > 0:
		_attack_cooldown -= 1

	# ---- positioning -------------------------------------------------------------------------
	var reach: float = float(_my_stats["reachM"]) + 0.3
	var low_stamina: bool = float(me["stamina"]) < 22.0
	_strafe_ticks -= 1
	if _strafe_ticks <= 0:
		_strafe_ticks = rng.randi_range(25, 70)
		_strafe_dir = 1.0 if rng.randf() < 0.5 else -1.0
	if low_stamina and dist < 3.0:
		move = -dir * 0.8 + side * _strafe_dir * 0.4
		block = block or (opp_attacking and dist < 3.0)
	elif dist > reach + 0.1:
		move = dir
		sprint = dist > reach + 2.6 and float(me["stamina"]) > 45.0
		if dist < reach + 1.4:
			move += side * _strafe_dir * 0.35
	else:
		move = side * _strafe_dir * 0.45 + dir * 0.1

	# ---- offence -----------------------------------------------------------------------------
	if free and _block_ticks == 0 and _scheduled_in == 0 and not low_stamina:
		if _follow_up_in > 0:
			_follow_up_in -= 1
		elif _follow_up_in == 0 and _follow_ups_left > 0 and dist <= reach + 0.5:
			builder.press("light")
			_follow_ups_left -= 1
			_follow_up_in = int(round(float(_my_stats["lightTicks"]) * 0.78)) if _follow_ups_left > 0 else -1
		elif dist <= reach + 0.15 and _attack_cooldown <= 0 and my_state != "Blocking":
			if rng.randf() < 0.18:
				builder.press("heavy")
				_attack_cooldown = int(_my_stats["heavyTicks"]) + rng.randi_range(18, 50)
			else:
				builder.press("light")
				_follow_ups_left = rng.randi_range(0, 2)
				_follow_up_in = int(round(float(_my_stats["lightTicks"]) * 0.78)) if _follow_ups_left > 0 else -1
				_attack_cooldown = int(_my_stats["lightTicks"]) + rng.randi_range(14, 45)
		_maybe_use_ability(me, dist)

	return builder.build(move.x, move.z, yaw_to, true, sprint, block)


func _reaction_ticks() -> int:
	return int(lerpf(26.0, 6.0, skill)) + rng.randi_range(0, 4)


func _choose_defence(opp: Dictionary, dist: float) -> void:
	var roll := rng.randf()
	var parry_chance := 0.15 + 0.45 * skill
	var startup_estimate: int = 32 if _opp_lunge else int(round(float(_opp_stats["lightTicks"]) * 0.4))
	var remaining: int = maxi(0, startup_estimate - int(opp["stateTicks"]))
	if roll < parry_chance:
		_scheduled_action = "parry"
		_scheduled_in = maxi(1, remaining - int(_my_stats["parryTicks"]) / 2)
	elif roll < parry_chance + 0.35:
		_block_ticks = rng.randi_range(26, 44)
	else:
		_scheduled_action = "dodge"
		_scheduled_in = maxi(1, remaining - 6)
	_follow_up_in = -1
	_follow_ups_left = 0


func _maybe_use_ability(me: Dictionary, dist: float) -> void:
	if int(me["cooldownTicks"]) > 0:
		return
	match String(_my_stats["abilityId"]):
		"last-stand":
			if float(me["hp"]) <= float(_my_stats["maxHp"]) * 0.35:
				builder.press("ability")
		"lunging-strike":
			if dist > 2.6 and dist < 4.0 and rng.randf() < 0.04:
				builder.press("ability")


func _pos(fighter: Dictionary) -> Vector3:
	var p: Dictionary = fighter["position"]
	return Vector3(float(p["x"]), 0.0, float(p["z"]))
