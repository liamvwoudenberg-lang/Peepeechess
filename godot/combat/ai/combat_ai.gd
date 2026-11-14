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
##
## STYLES (the balance matrix drives these; `balanced` is the default and the reference opponent):
##   balanced   - the original behaviour (random mix of everything).
##   aggressive - closes in, shorter gaps between attacks, more heavies, longer chains, rarely defends.
##   defensive  - waits just outside reach, parries/blocks most pokes and punishes recovery and stagger.
##   evasive    - kites: holds a gap, dodges, strikes only into the opponent's recovery or stagger.
##   patient    - duelist that almost never pokes: waits for the opponent to commit, then parries and punishes.
##   ability    - plays around its signature ability (uses it eagerly and in role-specific situations).
##   duelist    - the "skilled player" model: knows the opponent's published frame data (AttackLibrary), times a parry
##                for the first active tick of each incoming swing (dodges lunges), then punishes the stagger and the
##                recovery. It still sees only the public snapshot (no peeking at simulation internals).
## `skill` (0..1) scales reaction time and how often a defence is attempted. Everything is seeded.

const Balance := preload("res://combat/data/balance_data.gd")
const STYLE_NAMES := ["balanced", "aggressive", "defensive", "evasive", "ability", "duelist", "patient"]

## Neutral values reproduce the original behaviour exactly (no extra RNG draws), so existing seeded fights stay stable.
const NEUTRAL := {
	"heavy_chance": 0.18,       # chance an attack is a heavy
	"cooldown_scale": 1.0,      # scales the random gap between attacks
	"follow_max": 2,            # extra light links after the first (0..follow_max)
	"defence_scale": 1.0,       # scales how often an incoming attack is answered at all
	"parry_bias": 0.0,          # added to the parry chance
	"block_bias": 0.0,          # added to the block chance (0.35)
	"hold_extra": 0.0,          # preferred gap beyond own reach when not attacking (<0 = crowd)
	"kite": false,              # back away when the opponent is inside the preferred gap
	"punish": false,            # attack into the opponent's recovery / stagger immediately
	"poke": 1.0,                # scales the chance to start an attack when nothing special is happening
	"sprint_in": false,         # sprint to close any gap
	"ability_eager": 1.0,       # scales ability use probabilities
	"counter_eager": 0.55,      # King: chance to answer an attack start with Royal Counter
	"precise": false,           # frame-data parry/dodge timing (duelist)
}
const STYLE_OVERRIDES := {
	"balanced": {},
	"aggressive": {"heavy_chance": 0.3, "cooldown_scale": 0.5, "follow_max": 3, "defence_scale": 0.5,
			"hold_extra": -0.2, "sprint_in": true, "ability_eager": 1.5, "counter_eager": 0.3},
	"defensive": {"heavy_chance": 0.12, "cooldown_scale": 1.3, "follow_max": 1, "defence_scale": 1.6, "parry_bias": 0.3,
			"hold_extra": 0.5, "punish": true, "poke": 0.5, "ability_eager": 1.0, "counter_eager": 0.9},
	"evasive": {"heavy_chance": 0.08, "cooldown_scale": 1.0, "follow_max": 1, "defence_scale": 1.5, "parry_bias": -0.1,
			"block_bias": -0.35, "hold_extra": 1.1, "kite": true, "punish": true, "poke": 0.35, "ability_eager": 1.2,
			"counter_eager": 0.5},
	"duelist": {"heavy_chance": 0.2, "cooldown_scale": 0.9, "follow_max": 2, "defence_scale": 1.0, "hold_extra": 0.35,
			"punish": true, "poke": 0.6, "precise": true, "counter_eager": 0.9},
	"patient": {"heavy_chance": 0.25, "cooldown_scale": 1.0, "follow_max": 2, "defence_scale": 1.0, "hold_extra": 0.5,
			"punish": true, "poke": 0.15, "precise": true, "counter_eager": 0.9},
	"ability": {"heavy_chance": 0.18, "cooldown_scale": 0.9, "follow_max": 2, "defence_scale": 1.0,
			"ability_eager": 4.0, "poke": 1.0, "counter_eager": 1.0},
}

var builder: CombatInputBuilder
var rng := RandomNumberGenerator.new()
## 0..1: scales reaction speed and how often a defence is attempted.
var skill: float = 0.6
var style: String = "balanced"

var _my_id: String
var _my_stats: Dictionary
var _opp_stats: Dictionary
var _p: Dictionary = NEUTRAL

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
var _my_cooldown := 0
var _blink_evade := false
var _under_pressure := 0
var _counter_planned := false
# duelist bookkeeping
var _opp_prev_ticks := 0
var _opp_link := 0
var _opp_idle := 99
var _plan_action := ""
var _plan_tick := 0
var _opp_def: AttackDefinition = null
var _opp_total := 0
var _opp_prev_stamina := -1.0
var _opp_was_attacking := false
var _opp_counter_id := false
var _opp_speed := 1.0
var _opp_buff_left := 0


func _init(input_builder: CombatInputBuilder, my_stats: Dictionary, opponent_stats: Dictionary,
		seed: int = 1, p_skill: float = 0.6, p_style: String = "balanced") -> void:
	builder = input_builder
	_my_id = input_builder.player_id
	_my_stats = my_stats
	_opp_stats = opponent_stats
	skill = p_skill
	style = p_style if STYLE_OVERRIDES.has(p_style) else "balanced"
	_p = NEUTRAL.duplicate()
	_p.merge(STYLE_OVERRIDES[style], true)
	_opp_counter_id = String(opponent_stats.get("abilityId", "")) == "royal-counter"
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
	# Attacks have a narrow cone now (about 45-60 degrees): the computer aims before it swings, like a player has to.
	var aimed: bool = absf(CombatConstants.angle_diff(float(me["yawRadians"]), yaw_to)) < deg_to_rad(16.0)

	var live := int(snapshot["countdownTicksRemaining"]) == 0 and snapshot["result"] == null
	if not live:
		return builder.build(0.0, 0.0, yaw_to, true, false, false)

	var dir := to_opp.normalized() if dist > 0.01 else Vector3.FORWARD
	var side := Vector3(dir.z, 0.0, -dir.x)  # perpendicular, for circling
	var move := Vector3.ZERO
	var sprint := false
	var block := false
	var force_sidestep := false
	var my_state: String = me["state"]
	_my_cooldown = int(me["cooldownTicks"])
	if _under_pressure > 0:
		_under_pressure -= 1
	var free := my_state == "Idle" or my_state == "Moving" or my_state == "Blocking"
	var counter_id := String(_my_stats["abilityId"]) == "royal-counter"

	# ---- read the opponent's attack and schedule a defence ---------------------------------
	var opp_attacking: bool = opp["state"] == "Attacking" or opp["state"] == "AbilityCasting"
	if opp_attacking and not _prev_opp_attacking:
		_opp_lunge = opp["state"] == "AbilityCasting"
		_react_in = _reaction_ticks()
		if counter_id:
			_plan_counter(opp, dist)  # a King reads the wind-up directly instead of reacting late
	elif not opp_attacking:
		_react_in = -1
	_prev_opp_attacking = opp_attacking

	if bool(_p["precise"]):
		_react_in = -1
		_precise_defence(opp, dist, opp_attacking)

	if _react_in > 0:
		_react_in -= 1
	elif _react_in == 0:
		_react_in = -1
		if _counter_planned:
			_counter_planned = false  # already answering with the counter
		elif dist < (6.0 if _opp_lunge else 3.4) and rng.randf() < minf(0.95, (0.45 + 0.5 * skill) * float(_p["defence_scale"])):
			_choose_defence(opp, dist)

	if _scheduled_in > 0:
		_scheduled_in -= 1
		if _scheduled_in == 0 and _scheduled_action != "":
			builder.press(_scheduled_action)
			if _scheduled_action == "ability" and _blink_evade:
				force_sidestep = true  # Blink goes where the move vector points: sidestep the blow
				_blink_evade = false
			_scheduled_action = ""
	if _block_ticks > 0:
		_block_ticks -= 1
		block = true
	if _attack_cooldown > 0:
		_attack_cooldown -= 1

	# ---- opponent vulnerability (styles that punish) -----------------------------------------
	var opp_vulnerable := false
	if bool(_p["punish"]):
		if opp["state"] == "Staggered":
			opp_vulnerable = true
		elif opp["state"] == "Attacking" and not _opp_lunge:
			# past the active window of an ordinary swing: recovering
			var recover_from := int(float(_opp_stats["lightTicks"]) * 0.66)
			if bool(_p["precise"]) and _opp_def != null:
				recover_from = _opp_def.active_window(_opp_total).y
			opp_vulnerable = int(opp["stateTicks"]) > recover_from
		elif opp["state"] == "AbilityCasting" and _opp_counter_id:
			# Royal Counter: never swing into the stance; the whiff recovery after the window is the opening.
			opp_vulnerable = int(opp["stateTicks"]) >= int(Balance.ability("royal-counter")["counter_end"])
		elif opp["state"] == "AbilityCasting" and int(opp["stateTicks"]) > 40:
			opp_vulnerable = true

	# ---- positioning -------------------------------------------------------------------------
	var reach: float = float(_my_stats["reachM"]) + 0.3
	var low_stamina: bool = float(me["stamina"]) < 22.0
	_strafe_ticks -= 1
	if _strafe_ticks <= 0:
		_strafe_ticks = rng.randi_range(25, 70)
		_strafe_dir = 1.0 if rng.randf() < 0.5 else -1.0
	var hold := reach + float(_p["hold_extra"])
	var opp_reach: float = float(_opp_stats["reachM"]) + 0.3
	if low_stamina and dist < 3.0:
		move = -dir * 0.8 + side * _strafe_dir * 0.4
		block = block or (opp_attacking and dist < 3.0)
	elif opp_vulnerable and dist < reach + 2.6:
		move = dir  # step into the opening
		sprint = dist > reach + 0.8 and float(me["stamina"]) > 30.0
	elif bool(_p["kite"]) and dist < maxf(hold - 0.25, opp_reach + 0.35) and not opp_vulnerable:
		move = -dir * 0.9 + side * _strafe_dir * 0.35  # keep the gap
		sprint = dist < opp_reach and float(me["stamina"]) > 50.0
	elif dist > hold + 0.1:
		move = dir
		sprint = (dist > reach + 2.6 or bool(_p["sprint_in"]) and dist > reach + 1.0) and float(me["stamina"]) > 45.0
		if dist < reach + 1.4:
			move += side * _strafe_dir * 0.35
	elif dist > reach + 0.1:
		move = side * _strafe_dir * 0.45  # hold the gap and circle
	else:
		move = side * _strafe_dir * 0.45 + dir * 0.1

	# ---- offence -----------------------------------------------------------------------------
	var opp_in_stance: bool = _opp_counter_id and opp["state"] == "AbilityCasting" and not opp_vulnerable
	var threatened: bool = (bool(_p["precise"]) and (opp_attacking and not opp_vulnerable or _plan_action != "")) \
			or (bool(_p["punish"]) and opp_in_stance)
	if free and _block_ticks == 0 and _scheduled_in == 0 and not low_stamina and not threatened:
		if _follow_up_in > 0:
			_follow_up_in -= 1
		elif _follow_up_in == 0 and _follow_ups_left > 0 and dist <= reach + 0.5 and aimed:
			builder.press("light")
			_follow_ups_left -= 1
			_follow_up_in = int(round(float(_my_stats["lightTicks"]) * 0.78)) if _follow_ups_left > 0 else -1
		elif dist <= reach + 0.15 and aimed and my_state != "Blocking" and (_attack_cooldown <= 0 or opp_vulnerable and _attack_cooldown <= 10):
			var want := opp_vulnerable or float(_p["poke"]) >= 1.0 or rng.randf() < float(_p["poke"])
			if want:
				if rng.randf() < (float(_p["heavy_chance"]) + (0.25 if opp_vulnerable and opp["state"] == "Staggered" else 0.0)):
					builder.press("heavy")
					_attack_cooldown = int((int(_my_stats["heavyTicks"]) + rng.randi_range(18, 50)) * float(_p["cooldown_scale"]))
				else:
					builder.press("light")
					_follow_ups_left = rng.randi_range(0, int(_p["follow_max"]))
					_follow_up_in = int(round(float(_my_stats["lightTicks"]) * 0.78)) if _follow_ups_left > 0 else -1
					_attack_cooldown = int((int(_my_stats["lightTicks"]) + rng.randi_range(14, 45)) * float(_p["cooldown_scale"]))
		_maybe_use_ability(me, opp, dist)

	if force_sidestep:
		move = side * _strafe_dir
	return builder.build(move.x, move.z, yaw_to, true, sprint, block)


## Duelist: track the opponent's chain link, work out the first active tick of the swing from the published frame data
## and press parry so the middle of the parry window lands on it (a dodge for the Knight's lunge).
func _precise_defence(opp: Dictionary, dist: float, opp_attacking: bool) -> void:
	var ticks := int(opp["stateTicks"])
	var fresh := opp_attacking and (not _opp_was_attacking or ticks < _opp_prev_ticks)
	# Buffs the opponent has visibly cast (Last Stand, Royal Fury) shorten their swings: track the published numbers.
	if _opp_buff_left > 0:
		_opp_buff_left -= 1
		if _opp_buff_left == 0:
			_opp_speed = 1.0
	if opp["state"] == "AbilityCasting" and ticks == 1:
		var def: Dictionary = Balance.ability(String(_opp_stats["abilityId"]))
		if String(def.get("kind", "")) == "buff" and def.has("attack_speed_mult"):
			_opp_speed = float(def["attack_speed_mult"])
			_opp_buff_left = int(def["buff_ticks"])
	var stamina := float(opp["stamina"])
	if fresh:
		# Which swing is it? The opponent's stamina bar dropped by the swing's cost at its first tick (public HUD
		# information): pick the light link or heavy whose published cost matches best.
		var link := 0 if _opp_idle > 20 else _opp_link + 1
		_plan_action = ""
		_opp_def = null
		var opp_role := String(_opp_stats["role"])
		if opp["state"] == "AbilityCasting":
			_opp_def = AttackLibrary.ability_attack(opp_role, String(_opp_stats["abilityId"]))
		else:
			var spent := (_opp_prev_stamina - stamina + 0.45) if _opp_prev_stamina >= 0.0 else -1.0
			var table: Array = AttackLibrary.for_role(opp_role)["light"]
			link = mini(link, table.size() - 1)
			_opp_def = table[link]
			if spent >= 0.0:
				var best := absf(_opp_def.stamina_cost - spent)
				var heavy: AttackDefinition = AttackLibrary.heavy(opp_role)
				if absf(heavy.stamina_cost - spent) < best:
					_opp_def = heavy
					best = absf(heavy.stamina_cost - spent)
				for i in table.size():
					if absf(table[i].stamina_cost - spent) + 0.01 < best:
						best = absf(table[i].stamina_cost - spent)
						_opp_def = table[i]
						link = i
		_opp_link = link
		if _opp_def != null:
			_opp_total = _opp_def.total_ticks(_opp_stats, _opp_speed)
			var first_active := _opp_def.active_window(_opp_total).x
			var is_lunge := _opp_def.kind == AttackDefinition.Kind.ABILITY
			var in_range := dist < float(_opp_stats["reachM"]) * (1.2 if is_lunge else 1.0) + (4.4 if is_lunge else 0.6)
			if in_range and rng.randf() < 0.55 + 0.45 * skill:
				if is_lunge:
					_plan_action = "dodge"
					_plan_tick = first_active - 8
				else:
					_plan_action = "parry"
					_plan_tick = first_active - int(_my_stats["parryTicks"]) / 2
	if opp_attacking:
		_opp_idle = 0
	else:
		_opp_idle += 1
		_plan_action = ""
	_opp_prev_ticks = ticks
	_opp_prev_stamina = stamina
	_opp_was_attacking = opp_attacking
	if _plan_action != "" and ticks >= _plan_tick:
		var close_enough := dist < float(_opp_stats["reachM"]) + 1.0 or _plan_action == "dodge"
		if close_enough:
			builder.press(_plan_action)
			_follow_up_in = -1
			_follow_ups_left = 0
		_plan_action = ""


func _reaction_ticks() -> int:
	return int(lerpf(26.0, 6.0, skill)) + rng.randi_range(0, 4)


## Royal Counter (King): reads the opponent's wind-up when it starts and times the stance so the counter window
## (ticks 6..26 of the cast) is open when the blow lands. Light swings only; a heavy or an ability outlasts the
## window and punishes the whiff, exactly the risk the move is designed around.
func _plan_counter(opp: Dictionary, dist: float) -> void:
	if _my_cooldown > 0 or _scheduled_in > 0 or dist > float(_opp_stats["reachM"]) + 0.7 or _opp_lunge:
		return
	if rng.randf() >= float(_p["counter_eager"]) * (0.5 + 0.5 * skill):
		return
	var hit_in := int(round(float(_opp_stats["lightTicks"]) * 0.4)) - int(opp["stateTicks"])
	if hit_in < 7:
		return
	_scheduled_action = "ability"
	_scheduled_in = maxi(1, hit_in - 16)
	_counter_planned = true


func _choose_defence(opp: Dictionary, dist: float) -> void:
	var roll := rng.randf()
	var parry_chance := clampf(0.15 + 0.45 * skill + float(_p["parry_bias"]), 0.0, 0.95)
	var block_chance := clampf(0.35 + float(_p["block_bias"]), 0.0, 0.95)
	var startup_estimate: int = 32 if _opp_lunge else int(round(float(_opp_stats["lightTicks"]) * 0.4))
	var remaining: int = maxi(0, startup_estimate - int(opp["stateTicks"]))
	if roll < parry_chance:
		_scheduled_action = "parry"
		_scheduled_in = maxi(1, remaining - int(_my_stats["parryTicks"]) / 2)
	elif roll < parry_chance + block_chance:
		_block_ticks = rng.randi_range(26, 44)
	elif String(_my_stats["abilityId"]) == "blink" and _my_cooldown == 0 and rng.randf() < 0.7:
		_scheduled_action = "ability"  # vanish through the blow (i-frames cover the first 10 ticks)
		_scheduled_in = maxi(1, remaining - 4)
		_blink_evade = true
	else:
		_scheduled_action = "dodge"
		_scheduled_in = maxi(1, remaining - 6)
	_under_pressure = 180
	_follow_up_in = -1
	_follow_ups_left = 0


func _maybe_use_ability(me: Dictionary, opp: Dictionary, dist: float) -> void:
	if int(me["cooldownTicks"]) > 0:
		return
	var eager := float(_p["ability_eager"])
	var ability_style := style == "ability"
	match String(_my_stats["abilityId"]):
		"last-stand":
			if float(me["hp"]) <= float(_my_stats["maxHp"]) * 0.35:
				builder.press("ability")
		"lunging-strike":
			var lo := 2.0 if ability_style else 2.6
			if dist > lo and dist < 4.0 and rng.randf() < 0.04 * eager:
				builder.press("ability")
		"blink":
			# Close a gap, or disengage when hurt and crowded.
			if dist > 4.2 and rng.randf() < 0.03 * eager:
				builder.press("ability")
			elif dist < 1.6 and float(me["hp"]) < float(_my_stats["maxHp"]) * (0.7 if ability_style else 0.5) \
					and rng.randf() < 0.05 * eager:
				builder.press("ability")
		"fortress-guard":
			if (_under_pressure > 0 or ability_style) and dist < 3.2 and rng.randf() < 0.08 * eager:
				builder.press("ability")
		"royal-fury":
			if dist <= float(_my_stats["reachM"]) + 0.8 and rng.randf() < 0.06 * eager:
				builder.press("ability")
		"royal-counter":
			# Proactive bait: with an opponent in striking range and nothing planned, plant the stance and let them
			# walk into it. Rare, because a whiff leaves the King recovering for half a second.
			if _scheduled_in == 0 and dist <= float(_opp_stats["reachM"]) + 0.5 and rng.randf() < 0.012 * eager:
				builder.press("ability")


func _pos(fighter: Dictionary) -> Vector3:
	var p: Dictionary = fighter["position"]
	return Vector3(float(p["x"]), 0.0, float(p["z"]))
