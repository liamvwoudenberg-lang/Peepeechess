class_name CombatSimulation
extends Node3D
## Headless combat authority for ONE battle.
##
## Consumes a validated BattleRequest, accepts CombatInput packets (intent only), advances a
## fixed 60 Hz tick, and produces CombatSnapshot / BattleResult dictionaries that conform to
## the shared v1 contracts. It has no dependency on cameras, audio, meshes or UI, so it can run
## inside a dedicated server process (`godot --headless`) as well as inside the client for
## offline play. Whoever hosts it decides who may call submit_input; this class only enforces
## the data rules (see CONTRACTS.md "Admission, ordering and cross-field invariants").
##
## Tick order (step_tick): build intents -> state-machine think -> movement -> hit detection for
## BOTH fighters (so trades are possible) -> hit resolution -> end of tick -> events -> end check.
##
## Not implemented here (belongs to the hosting adapter): credentials, seat binding, rate
## limiting, reconnect, abandonment timers, persistence, and settling the chess result.

enum Phase { IDLE, COUNTDOWN, ACTIVE, FINISHED }

signal event_emitted(event: Dictionary)
signal finished(result: Dictionary)

const Codec := preload("res://contracts/codec.gd")
const S := CombatConstants.State

var phase: int = Phase.IDLE
var request: Dictionary = {}
## Index 0 is the White seat, index 1 the Black seat (matches spawn layout and snapshots).
var fighters: Array[FighterController] = []
var world: StoneArena = null
var server_tick: int = 0
var countdown_remaining: int = 0
var duration_remaining: int = 0
var result: Dictionary = {}
var recent_events: Array[Dictionary] = []

## Hit-commit grace (the ONLY latency compensation, see godot/combat/NETWORKING.md). A hit detected at
## tick T against a defender who has a grace of g ticks (and who is not already defended at T) is held
## PENDING and resolved at T+g against the defender's state at that moment, so a parry/dodge input that
## arrives late (network delay) can still turn it into a parry/dodge. No rewinding, no client hit claims:
## the geometry was fixed at T on the server, the rule is symmetric, and g is capped.
const HIT_GRACE_CAP := 6

var _inputs: Dictionary = {}
var _grace: Dictionary = {}
var _pending: Array[Dictionary] = []
var _codec = null
var _next_event_id: int = 1
var _tick_count: int = 0


# ---- lifecycle -----------------------------------------------------------------------------
## Starts a battle. Returns {"ok": true} or {"ok": false, "code": ProtocolError code, "message": ...}.
func start(req: Dictionary) -> Dictionary:
	if phase == Phase.COUNTDOWN or phase == Phase.ACTIVE:
		return _error("WRONG_PHASE", "a battle is already running")
	if _codec == null:
		_codec = Codec.new()
	if not _codec.valid("BattleRequest", req):
		return _error("INVALID_PAYLOAD", "BattleRequest failed schema validation")
	var attacker_data: Dictionary = req["attacker"]
	var defender_data: Dictionary = req["defender"]
	if attacker_data["playerId"] == defender_data["playerId"] or attacker_data["color"] == defender_data["color"]:
		return _error("INVALID_PAYLOAD", "attacker and defender must be different seats")
	for data in [attacker_data, defender_data]:
		if data["stats"]["role"] != data["role"]:
			return _error("INVALID_PAYLOAD", "stats.role does not match combatant role")

	_reset()
	request = req.duplicate(true)
	world = StoneArena.new()
	world.name = "Arena"
	add_child(world)
	world.build_colliders()

	fighters.resize(2)
	for data in [attacker_data, defender_data]:
		var is_white: bool = data["color"] == "w"
		var fighter := FighterController.new()
		add_child(fighter)
		var problem := fighter.setup(data,
				Vector3(0.0, 0.0, -CombatConstants.SPAWN_DISTANCE if is_white else CombatConstants.SPAWN_DISTANCE),
				0.0 if is_white else PI)
		if problem != "":
			_reset()
			return _error("INVALID_PAYLOAD", problem)
		fighters[0 if is_white else 1] = fighter
		_inputs[fighter.player_id] = CombatInputState.new()

	server_tick = int(req["startTick"])
	countdown_remaining = CombatConstants.COUNTDOWN_TICKS
	duration_remaining = CombatConstants.DURATION_TICKS
	for state in _inputs.values():
		state.last_accept_tick = server_tick
	phase = Phase.COUNTDOWN
	return {"ok": true}


## Aborts without producing a result. A result is never fabricated.
func stop() -> void:
	_reset()


func _reset() -> void:
	for node in get_children():
		remove_child(node)
		node.queue_free()
	fighters.clear()
	world = null
	request = {}
	result = {}
	recent_events.clear()
	_inputs.clear()
	_grace.clear()
	_pending.clear()
	_next_event_id = 1
	_tick_count = 0
	server_tick = 0
	countdown_remaining = 0
	duration_remaining = 0
	phase = Phase.IDLE


func is_running() -> bool:
	return phase == Phase.COUNTDOWN or phase == Phase.ACTIVE


func attacker() -> FighterController:
	return fighter_by_id(request["attacker"]["playerId"])


func defender() -> FighterController:
	return fighter_by_id(request["defender"]["playerId"])


func fighter_by_id(player_id: String) -> FighterController:
	for fighter in fighters:
		if fighter != null and fighter.player_id == player_id:
			return fighter
	return null


func opponent_of(fighter: FighterController) -> FighterController:
	return fighters[1] if fighter == fighters[0] else fighters[0]


## Sets the hit-commit grace (ticks, clamped to 0..HIT_GRACE_CAP) for hits AGAINST this player.
## Default 0 = hits resolve on the tick they are detected (the original behaviour).
func set_hit_grace(player_id: String, ticks: int) -> void:
	_grace[player_id] = clampi(ticks, 0, HIT_GRACE_CAP)


func hit_grace(player_id: String) -> int:
	return int(_grace.get(player_id, 0))


func pending_hit_count() -> int:
	return _pending.size()


# ---- input ---------------------------------------------------------------------------------
## Admits one CombatInput. Returns {"ok": true} or {"ok": false, "code": ..., "message": ...}.
## Seat authentication is the caller's job; this validates shape, battle and ordering.
func submit_input(input: Dictionary) -> Dictionary:
	if not is_running():
		return _error("WRONG_PHASE", "no battle is running")
	if not _codec.valid("CombatInput", input):
		return _error("INVALID_PAYLOAD", "CombatInput failed schema validation")
	if input["matchId"] != request["matchId"] or input["battleId"] != request["battleId"]:
		return _error("FORBIDDEN", "input is for another battle")
	var state: CombatInputState = _inputs.get(input["playerId"], null)
	if state == null:
		return _error("FORBIDDEN", "unknown seat")
	var sequence := int(input["sequence"])
	if sequence <= state.last_sequence:
		return _error("STALE_INPUT", "sequence must strictly increase")
	for action in CombatInputState.ACTIONS:
		if int(input[action]) < int(state.seen[action]):
			return _error("INVALID_PAYLOAD", "action counters must never decrease")

	state.last_sequence = sequence
	state.last_accept_tick = server_tick
	state.has_input = true
	var move := Vector2(float(input["moveX"]), float(input["moveZ"]))
	if move.length() > 1.0:
		move = move.normalized()
	state.move_x = move.x
	state.move_z = move.y
	state.yaw = float(input["yawRadians"])
	state.lock_target = bool(input["lockTarget"])
	state.sprint = bool(input["sprint"])
	state.block = bool(input["block"])
	for action in CombatInputState.ACTIONS:
		var count := int(input[action])
		if count > int(state.seen[action]):
			state.edges[action] = true  # at most one edge per accepted packet
			state.seen[action] = count
	fighter_by_id(input["playerId"]).last_input_sequence = sequence
	return {"ok": true}


# ---- tick ----------------------------------------------------------------------------------
func step_tick() -> void:
	if not is_running():
		return
	server_tick += 1
	_tick_count += 1
	for fighter in fighters:
		fighter.prev_position = fighter.global_position
		fighter.prev_yaw = fighter.yaw

	if phase == Phase.COUNTDOWN:
		for fighter in fighters:
			_inputs[fighter.player_id].clear_edges()  # nothing is buffered into the fight
		countdown_remaining -= 1
		if countdown_remaining <= 0:
			countdown_remaining = 0
			phase = Phase.ACTIVE
		return

	duration_remaining -= 1
	# Alternate who moves first so the other fighter's body never has a permanent advantage.
	var order: Array = [0, 1] if _tick_count % 2 == 0 else [1, 0]
	var intents: Array = [null, null]
	for i in order:
		intents[i] = _inputs[fighters[i].player_id].consume_intent(server_tick, fighters[i].yaw, true)
	for i in order:
		fighters[i].think(intents[i])
	for i in order:
		fighters[i].move(intents[i], fighters[1 - i])
	_resolve_hits()
	if _fight_ending():
		_flush_pending()  # nothing may stay in flight when the result is decided
	for i in order:
		fighters[i].end_tick()
	_flush_fighter_events()
	_check_end()


# ---- hit resolution ------------------------------------------------------------------------
func _resolve_hits() -> void:
	# 1) Pending hits that fall due this tick resolve first, against the defender's CURRENT state.
	if not _pending.is_empty():
		var still: Array[Dictionary] = []
		for hit in _pending:
			if int(hit["due"]) <= server_tick:
				_apply_hit(hit["a"], hit["d"], hit["atk"], int(hit["dmg"]))
			else:
				still.append(hit)
		_pending = still
	# 2) Detect first, apply afterwards: a fighter whose hit is already "in flight" still lands it
	# even if they were hit on the same tick (trades and double knock-outs are possible).
	var landed: Array[Dictionary] = []
	for i in 2:
		var a := fighters[i]
		var d := fighters[1 - i]
		if a.hitbox.try_hit(a, d):
			var atk := a.sm.attack
			landed.append({"a": a, "d": d, "atk": atk, "dmg": a.compute_damage(atk)})
			a.sm.riposte_ticks = 0
	for hit in landed:
		var defender_grace := hit_grace(hit["d"].player_id)
		if defender_grace > 0 and not _resolves_now(hit["d"], hit["a"]):
			hit["due"] = server_tick + defender_grace
			_pending.append(hit)
		else:
			_apply_hit(hit["a"], hit["d"], hit["atk"], int(hit["dmg"]))


## A hit resolves immediately when the defender is already defending (dodge i-frames, an open parry
## window or a raised guard facing the attacker) or cannot defend at all (staggered / defeated).
func _resolves_now(d: FighterController, a: FighterController) -> bool:
	if d.sm.state == S.STAGGERED or d.sm.state == S.DEFEATED:
		return true
	if d.sm.iframes_active():
		return true
	if d.sm.parry_window_open() and d.faces_toward(a.global_position, float(d.profile["parry_arc_deg"])):
		return true
	return d.sm.guard_up() and d.faces_toward(a.global_position, float(d.profile["block_arc_deg"]))


func _fight_ending() -> bool:
	if duration_remaining <= 0:
		return true
	for fighter in fighters:
		if not fighter.health.is_alive():
			return true
	return false


func _flush_pending() -> void:
	var hits := _pending
	_pending = []
	for hit in hits:
		_apply_hit(hit["a"], hit["d"], hit["atk"], int(hit["dmg"]))


func _apply_hit(a: FighterController, d: FighterController, atk: AttackDefinition, raw: int) -> void:
	if not d.health.is_alive():
		return
	var away_from_attacker := CombatConstants.flat(d.global_position - a.global_position)

	# 1. Dodge invulnerability.
	if d.sm.iframes_active():
		_emit("dodge", a, d, 0)
		return

	# 2. Perfect parry: the press landed inside the window and the attacker is in front.
	if d.sm.parry_window_open() and d.faces_toward(a.global_position, float(d.profile["parry_arc_deg"])):
		a.sm.enter_staggered(int(d.profile["parry_stagger_ticks"]), "parried")
		a.add_knockback(-away_from_attacker, 0.6)
		d.sm.on_parry_success()
		d.stamina.refund(float(d.profile["parry_refund"]))
		_emit("parry", a, d, 0)
		return

	# 3. Block: absorbs a frontal hit for stamina; not enough stamina breaks the guard.
	if d.sm.guard_up() and d.faces_toward(a.global_position, float(d.profile["block_arc_deg"])):
		var guard_cost := float(raw) * atk.guard_cost_mult * float(d.profile["block_cost_mult"])
		if d.stamina.can_afford(guard_cost):
			d.stamina.lose(guard_cost)
			d.add_knockback(away_from_attacker, atk.knockback_m * 0.5)
			_emit("block", a, d, 0)
		else:
			d.stamina.lose(d.stamina.current)  # drained to zero -> exhausted
			var chip := d.health.apply_damage(maxi(1, roundi(float(_after_armor(d, raw)) * 0.5)))
			d.sm.enter_staggered(int(d.profile["guardbreak_stun"]), "guardbreak")
			_emit("guardbreak", a, d, chip)
			_defeat_if_dead(d)
		return

	# 4. Clean hit.
	var dealt := d.health.apply_damage(_after_armor(d, raw))
	d.add_knockback(away_from_attacker, atk.knockback_m)
	_emit("hit", a, d, dealt)
	if _defeat_if_dead(d):
		return
	d.hit_react_ticks = int(d.profile["hit_react_ticks"])
	if d.sm.has_armor() or d.sm.state == S.STAGGERED or d.sm.stagger_immunity > 0:
		return  # armoured, already staggered, or briefly immune: damage only
	d.poise -= atk.poise_damage
	d.poise_delay = int(d.profile["poise_regen_delay"])
	if d.poise <= 0.0:
		d.poise = float(d.profile["poise"])
		d.sm.enter_staggered(atk.hitstun_ticks, "hit")


func _after_armor(d: FighterController, raw: int) -> int:
	return maxi(1, roundi(float(raw) * (1.0 - float(d.profile["armor"]))))


func _defeat_if_dead(d: FighterController) -> bool:
	if d.health.is_alive():
		return false
	d.sm.enter_defeated()
	d.collision_layer = 0
	return true


# ---- events, end of battle -----------------------------------------------------------------
func _emit(type: String, actor: FighterController, target: FighterController, damage: int) -> void:
	## `actor` is always the initiator (the attacker / ability user); `target` is the other seat.
	var event := {
		"eventId": _next_event_id, "tick": server_tick, "type": type,
		"actorPlayerId": actor.player_id, "targetPlayerId": target.player_id, "damage": damage,
	}
	_next_event_id += 1
	recent_events.append(event)
	while recent_events.size() > CombatConstants.EVENT_HISTORY:
		recent_events.pop_front()
	event_emitted.emit(event)


func _flush_fighter_events() -> void:
	for fighter in fighters:
		for type in fighter.drain_events():
			_emit(type, fighter, opponent_of(fighter), 0)


func _check_end() -> void:
	var a := attacker()
	var d := defender()
	var a_down := not a.health.is_alive()
	var d_down := not d.health.is_alive()
	if a_down and d_down:
		_finish("defender", "double_knockout")
	elif a_down:
		_finish("defender", "knockout")
	elif d_down:
		_finish("attacker", "knockout")
	elif duration_remaining <= 0:
		# Higher remaining-HP percentage wins; compare by cross multiplication (exact integers).
		var left := a.health.current * d.health.maximum
		var right := d.health.current * a.health.maximum
		if left > right:
			_finish("attacker", "timeout_hp")
		elif right > left:
			_finish("defender", "timeout_hp")
		else:
			_finish("defender", "timeout_tie")  # exact ties favour the defender; no randomness


func _finish(outcome: String, reason: String) -> void:
	var a := attacker()
	var d := defender()
	result = {
		"schemaVersion": 1,
		"matchId": request["matchId"],
		"battleId": request["battleId"],
		"expectedRevision": int(request["expectedRevision"]),
		"resolvedTick": server_tick,
		"winnerPlayerId": a.player_id if outcome == "attacker" else d.player_id,
		"outcome": outcome,
		"reason": reason,
		"attackerHp": a.health.current,
		"defenderHp": d.health.current,
	}
	_pending.clear()
	phase = Phase.FINISHED
	finished.emit(result)


# ---- snapshot ------------------------------------------------------------------------------
## CombatSnapshot (contract v1). Presentation data only - never a checkpoint of hidden state.
func snapshot() -> Dictionary:
	if request.is_empty():
		return {}
	return {
		"schemaVersion": 1,
		"matchId": request["matchId"],
		"battleId": request["battleId"],
		"serverTick": server_tick,
		"countdownTicksRemaining": countdown_remaining,
		"durationTicksRemaining": duration_remaining,
		"fighters": [fighters[0].snapshot(), fighters[1].snapshot()],
		"events": recent_events.duplicate(true),
		"result": result.duplicate(true) if phase == Phase.FINISHED else null,
	}


func _error(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}
