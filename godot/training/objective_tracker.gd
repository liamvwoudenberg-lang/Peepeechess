class_name ObjectiveTracker
extends RefCounted
## Detects lesson objectives ONLY from what the real combat simulation does: its `event_emitted` stream (hit, block, parry, dodge,
## guardbreak, whiff, ability, defeat) plus the public fighter state after every tick (positions, state machine, stamina, HP).
## Pressing a button counts for nothing: a "three-hit combo" is three hits that connected, chained, with nothing in between.
##
## Drive it with `update()` once per simulation tick (after `sim.step_tick()`); TrainingSession does that for you. It can also be attached
## to the sim of a CombatArena (`ObjectiveTracker.new(arena.sim, player_id, lesson)`; the arena steps the sim itself, call update() from
## the arena's physics tick or the UI's _physics_process).
##
## Signals (all the UI needs):
##   objective_progress(id, current, target)   objective_completed(id)
##   combo_changed(count)                      combo_failed(count)        (a chain of >= 2 hits ended / was interrupted)
##   feedback(kind, text)                      short coaching lines ("Parried!", "Hit while they recover: punish!")
##   lesson_completed(stats)                   lesson_failed(reason, stats)
##
## Objective types (lesson JSON `objectives[].type`):
##   move_distance{meters}  hit_count{count}  hit_at_range{count,min_distance}  combo{count}  block_n{count}  parry_n{count}
##   dodge_n{count}  counter_after{after:"block"|"parry"|"dodge",count,window_ticks}  punish{count}  ability_use{count}
##   cancel{count}  stamina_cycle{drain_below,recover_above}  hold_distance{min,max,seconds}  survive{seconds}
##   stun{count}  stun_followup{count}  (hit stun: a hit that leaves the opponent staggered; a follow-up hit while they are still stunned)
##   win{}  win_clean{max_hits_taken}

signal objective_progress(id: String, current: float, target: float)
signal objective_completed(id: String)
signal combo_changed(count: int)
signal combo_failed(count: int)
signal feedback(kind: String, text: String)
signal lesson_completed(stats: Dictionary)
signal lesson_failed(reason: String, stats: Dictionary)

const S := CombatConstants.State
## Longest gap (ticks) between two hits that still counts as one chain: a light swing (24-32 ticks) plus the engine's chain grace.
const COMBO_WINDOW_TICKS := 78
const DEFAULT_COUNTER_WINDOW := 90
## A hit this soon after the opponent whiffed also counts as a punish.
const WHIFF_PUNISH_WINDOW := 70

var lesson: Dictionary = {}
var sim: CombatSimulation
var player_id: String = ""
var opponent_id: String = ""
var objectives: Array = []          # [{def, value, target, done}]
var stats := {"hits": 0, "hits_taken": 0, "damage_taken": 0, "blocks": 0, "parries": 0, "dodges": 0, "abilities": 0, "punishes": 0,
		"cancels": 0, "stuns": 0, "followups": 0, "best_combo": 0, "distance": 0.0, "active_ticks": 0}
var combo: int = 0
var finished: bool = false
var failed: bool = false
var fail_reason: String = ""
var _combo_last_tick := -9999
var _last_defence := {"block": -9999, "parry": -9999, "dodge": -9999}
var _opp_whiff_tick := -9999
var _prev_opp_recovering := false
var _prev_opp_hit_stunned := false
var _prev_player_state := -1
var _prev_pos := Vector3.ZERO
var _have_prev_pos := false
var _drained := false
var _hold_ticks := 0
var _player_max_hp := 1
var _hit_this_tick_distance := 0.0


func _init(p_sim: CombatSimulation, p_player_id: String, p_lesson: Dictionary) -> void:
	sim = p_sim
	player_id = p_player_id
	lesson = p_lesson
	for fighter in sim.fighters:
		if fighter.player_id != player_id:
			opponent_id = fighter.player_id
	var me: FighterController = sim.fighter_by_id(player_id)
	_player_max_hp = me.health.maximum if me != null else 1
	for def in lesson.get("objectives", []):
		objectives.append({"def": def, "value": 0.0, "target": _target_of(def), "done": false})
	sim.event_emitted.connect(_on_event)


static func _target_of(def: Dictionary) -> float:
	match String(def.get("type", "")):
		"move_distance": return float(def.get("meters", 1.0))
		"hold_distance", "survive": return float(def.get("seconds", 1.0))
		"stamina_cycle", "win", "win_clean": return 1.0
	return float(def.get("count", 1))


func completed_count() -> int:
	var n := 0
	for o in objectives:
		if o["done"]:
			n += 1
	return n


func required_count() -> int:
	var n := 0
	for o in objectives:
		if not bool(o["def"].get("optional", false)):
			n += 1
	return n


func objective_state(id: String) -> Dictionary:
	for o in objectives:
		if String(o["def"].get("id", "")) == id:
			return {"value": o["value"], "target": o["target"], "done": o["done"]}
	return {}


# ---- events ------------------------------------------------------------------------------------------------------------
func _on_event(event: Dictionary) -> void:
	if finished or failed:
		return
	var type := String(event.get("type", ""))
	var actor := String(event.get("actorPlayerId", ""))
	var target := String(event.get("targetPlayerId", ""))
	var tick := sim.server_tick
	match type:
		"hit", "guardbreak":
			if actor == player_id:
				_player_hit(tick)
			elif target == player_id:
				stats["hits_taken"] += 1
				stats["damage_taken"] += int(event.get("damage", 0))
				_break_combo()
				feedback.emit("hurt", "You were hit.")
		"block":
			if target == player_id:
				stats["blocks"] += 1
				_last_defence["block"] = tick
				_bump("block_n", 1.0)
				feedback.emit("block", "Blocked!")
			elif actor == player_id:
				_break_combo()
				feedback.emit("blocked", "They blocked: change the rhythm.")
		"parry":
			if target == player_id:
				stats["parries"] += 1
				_last_defence["parry"] = tick
				_bump("parry_n", 1.0)
				feedback.emit("parry", "Parried! Strike now.")
			elif actor == player_id:
				_break_combo()
				feedback.emit("parried", "You were parried.")
		"dodge":
			if target == player_id:
				stats["dodges"] += 1
				_last_defence["dodge"] = tick
				_bump("dodge_n", 1.0)
				feedback.emit("dodge", "Dodged!")
			elif actor == player_id:
				_break_combo()
		"ability":
			if actor == player_id:
				stats["abilities"] += 1
				_bump("ability_use", 1.0)
		"whiff":
			if actor == opponent_id:
				_opp_whiff_tick = tick
				feedback.emit("whiff", "They missed: punish!")


func _player_hit(tick: int) -> void:
	stats["hits"] += 1
	var chained := combo > 0 and tick - _combo_last_tick <= COMBO_WINDOW_TICKS
	combo = combo + 1 if chained else 1
	_combo_last_tick = tick
	stats["best_combo"] = maxi(int(stats["best_combo"]), combo)
	combo_changed.emit(combo)
	if combo >= 2:
		feedback.emit("combo", "%d-hit combo!" % combo)
	_bump("hit_count", 1.0)
	# combo objectives track the best chain
	for o in objectives:
		if not o["done"] and String(o["def"]["type"]) == "combo":
			_put(o, float(stats["best_combo"]))
	# hit from range
	var distance := _distance()
	for o in objectives:
		if not o["done"] and String(o["def"]["type"]) == "hit_at_range" and distance >= float(o["def"].get("min_distance", 0.0)):
			_put(o, o["value"] + 1.0)
	# counter after a defence
	for o in objectives:
		if not o["done"] and String(o["def"]["type"]) == "counter_after":
			var after := String(o["def"].get("after", "parry"))
			var window := int(o["def"].get("window_ticks", DEFAULT_COUNTER_WINDOW))
			if tick - int(_last_defence.get(after, -9999)) <= window:
				_last_defence[after] = -9999   # one counter per defence
				_put(o, o["value"] + 1.0)
				feedback.emit("counter", "Counter-attack!")
	# follow-up: another hit while the previous hit's stun is still running
	if _prev_opp_hit_stunned:
		stats["followups"] += 1
		_bump("stun_followup", 1.0)
		feedback.emit("followup", "Follow-up while they are stunned!")
	# punish: the opponent was recovering from a swing / staggered, or whiffed a moment ago
	if _prev_opp_recovering or tick - _opp_whiff_tick <= WHIFF_PUNISH_WINDOW:
		stats["punishes"] += 1
		_bump("punish", 1.0)
		feedback.emit("punish", "Punished the recovery!")


func _break_combo() -> void:
	if combo >= 2:
		combo_failed.emit(combo)
	if combo != 0:
		combo = 0
		combo_changed.emit(0)


# ---- per tick ----------------------------------------------------------------------------------------------------------
## Call once per simulation tick, after step_tick().
func update() -> void:
	if finished or failed:
		return
	var me: FighterController = sim.fighter_by_id(player_id)
	var opp: FighterController = sim.fighter_by_id(opponent_id)
	if me == null or opp == null:
		return
	var live := sim.phase == CombatSimulation.Phase.ACTIVE
	if live:
		stats["active_ticks"] += 1
		if combo > 0 and sim.server_tick - _combo_last_tick > COMBO_WINDOW_TICKS:
			_break_combo()
		# distance travelled
		var pos := Vector3(me.global_position.x, 0.0, me.global_position.z)
		if _have_prev_pos:
			var step := pos.distance_to(_prev_pos)
			if step < 2.0:   # a teleport (test setup) is not walking
				stats["distance"] += step
				_bump("move_distance", step)
		_prev_pos = pos
		_have_prev_pos = true
		# cancels: an attack's recovery cut short by a dodge / parry / ability
		var state := int(me.sm.state)
		if _prev_player_state == S.ATTACKING and state in [S.DODGING, S.PARRYING, S.ABILITY_CASTING]:
			stats["cancels"] += 1
			_bump("cancel", 1.0)
			feedback.emit("cancel", "Animation cancel!")
		_prev_player_state = state
		# state-based objectives
		var distance := _distance()
		for o in objectives:
			if o["done"]:
				continue
			match String(o["def"]["type"]):
				"stamina_cycle":
					var frac := me.stamina.current / maxf(me.stamina.maximum, 1.0)
					if not _drained and frac <= float(o["def"].get("drain_below", 0.3)):
						_drained = true
						_put(o, 0.5)
						feedback.emit("stamina", "Stamina is low: back off and let it recover.")
					elif _drained and frac >= float(o["def"].get("recover_above", 0.9)):
						_put(o, 1.0)
				"hold_distance":
					if distance >= float(o["def"].get("min", 0.0)) and distance <= float(o["def"].get("max", 99.0)):
						_hold_ticks += 1
						_put(o, float(_hold_ticks) / 60.0)
				"survive":
					if me.health.is_alive():
						_put(o, float(stats["active_ticks"]) / 60.0)
		# hit stun: the opponent has just entered a stagger caused by a hit
		var stunned_now := int(opp.sm.state) == S.STAGGERED and opp.sm.stun_kind == "hit"
		if stunned_now and not _prev_opp_hit_stunned and sim.server_tick - _combo_last_tick <= 2:
			stats["stuns"] += 1
			_bump("stun", 1.0)
			feedback.emit("stun", "Stunned them!")
		_prev_opp_hit_stunned = stunned_now
		# opponent recovering? (read for the NEXT tick's hits)
		_prev_opp_recovering = _is_recovering(opp)
	_check_failures(me)
	if not failed and sim.phase == CombatSimulation.Phase.FINISHED:
		_on_finished(me)
	_check_complete()


func _is_recovering(fighter: FighterController) -> bool:
	var state := int(fighter.sm.state)
	if state == S.STAGGERED:
		return true
	if state == S.ATTACKING and fighter.sm.attack != null:
		return fighter.sm.state_ticks >= fighter.sm.attack.active_window(fighter.sm.attack_total).y
	return false


func _distance() -> float:
	var a := sim.fighter_by_id(player_id)
	var b := sim.fighter_by_id(opponent_id)
	if a == null or b == null:
		return 0.0
	return Vector2(a.global_position.x - b.global_position.x, a.global_position.z - b.global_position.z).length()


func _on_finished(me: FighterController) -> void:
	var won := String(sim.result.get("winnerPlayerId", "")) == player_id
	for o in objectives:
		if o["done"]:
			continue
		var type := String(o["def"]["type"])
		if type == "win" and won:
			_put(o, 1.0)
		elif type == "win_clean" and won and int(stats["hits_taken"]) <= int(o["def"].get("max_hits_taken", 0)):
			_put(o, 1.0)
	_check_complete()
	if not finished:
		_fail("defeated" if not won else "objectives_incomplete")


func _check_failures(me: FighterController) -> void:
	if failed or finished:
		return
	for rule in lesson.get("fail", []):
		match String(rule.get("type", "")):
			"time_limit":
				if float(stats["active_ticks"]) / 60.0 > float(rule.get("seconds", 999.0)):
					_fail("time_limit")
			"hits_taken":
				if int(stats["hits_taken"]) > int(rule.get("count", 0)):
					_fail("too_many_hits")
			"damage_fraction":
				if float(stats["damage_taken"]) / float(_player_max_hp) > float(rule.get("fraction", 1.0)):
					_fail("too_much_damage")
	if not failed and not me.health.is_alive():
		_fail("defeated")


func _fail(reason: String) -> void:
	if failed or finished:
		return
	failed = true
	fail_reason = reason
	lesson_failed.emit(reason, summary())


func _check_complete() -> void:
	if finished or failed or objectives.is_empty():
		return
	for o in objectives:
		if not o["done"] and not bool(o["def"].get("optional", false)):
			return
	finished = true
	lesson_completed.emit(summary())


func summary() -> Dictionary:
	var out: Dictionary = stats.duplicate()
	out["seconds"] = float(stats["active_ticks"]) / 60.0
	out["damage_fraction"] = float(stats["damage_taken"]) / float(_player_max_hp)
	out["completed"] = finished
	out["failed"] = failed
	out["fail_reason"] = fail_reason
	return out


## "bronze" for a completed lesson, "silver" / "gold" when the lesson's rating thresholds are met (see LessonSchema).
func rating() -> String:
	return ObjectiveTracker.rate(lesson, summary())


static func rate(lesson_data: Dictionary, result: Dictionary) -> String:
	if not bool(result.get("completed", false)):
		return ""
	var thresholds: Dictionary = lesson_data.get("rating", {})
	for tier in ["gold", "silver"]:
		var t: Dictionary = thresholds.get(tier, {})
		if t.is_empty():
			continue
		if t.has("max_seconds") and float(result.get("seconds", 999.0)) > float(t["max_seconds"]):
			continue
		if t.has("max_hits_taken") and int(result.get("hits_taken", 99)) > int(t["max_hits_taken"]):
			continue
		if t.has("min_combo") and int(result.get("best_combo", 0)) < int(t["min_combo"]):
			continue
		if t.has("min_parries") and int(result.get("parries", 0)) < int(t["min_parries"]):
			continue
		if t.has("max_damage_fraction") and float(result.get("damage_fraction", 1.0)) > float(t["max_damage_fraction"]):
			continue
		return tier
	return "bronze"


# ---- objective helpers -------------------------------------------------------------------------------------------------
func _bump(type: String, amount: float) -> void:
	for o in objectives:
		if not o["done"] and String(o["def"]["type"]) == type:
			_put(o, o["value"] + amount)


func _put(o: Dictionary, value: float) -> void:
	var id := String(o["def"].get("id", o["def"]["type"]))
	var previous: float = o["value"]
	o["value"] = minf(value, o["target"]) if o["target"] > 0 else value
	if o["value"] != previous:
		objective_progress.emit(id, o["value"], o["target"])
	if not o["done"] and o["value"] >= o["target"] - 0.0001:
		o["done"] = true
		objective_completed.emit(id)
		feedback.emit("objective", "%s done" % String(o["def"].get("text", id)))
