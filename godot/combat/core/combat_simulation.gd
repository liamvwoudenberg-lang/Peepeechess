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
const Balance := preload("res://combat/data/balance_data.gd")
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

## The attacker's advantage (BALANCE.md "Attacker advantage"): damage multipliers for the seat that attacks and the seat that
## defends, from the data table for this pairing. 1.0 = neutral. Applied to every blow in _apply_hit before armour.
var edge_attacker: float = 1.0
var edge_defender: float = 1.0
## Duel length (BALANCE.md "Duel length"): every blow's HP damage is multiplied by this (< 1 = longer fights). 1.0 = raw frame data.
var damage_scale: float = 1.0

var _inputs: Dictionary = {}
var _grace: Dictionary = {}
var _pending: Array[Dictionary] = []
var _codec = null
var _next_event_id: int = 1
var _tick_count: int = 0


# ---- lifecycle -----------------------------------------------------------------------------
## Starts a battle. Returns {"ok": true} or {"ok": false, "code": ProtocolError code, "message": ...}.
##
## `options` (all optional, default = strict v1 behaviour):
##   "allow_experimental_roles": true  - lets a King (role "k", ability "royal-counter") fight. The v1 BattleRequest
##       schema forbids "k" as a Combatant role, so the schema check runs on a COPY whose king combatants carry
##       the placeholder role "q"; everything else (every other field, the seat rules, stats.role == role) is
##       validated unchanged on the real request. Nothing but the king role is relaxed. Intended for the offline
##       arena, tests and tools; a v1 server must not pass it (it never receives king requests under v1).
##   "attacker_edge": the attacker's advantage. Absent = the balance data's rule for this pairing (the game's rule: damage
##       multipliers and the stamina rule); false = none at all (raw frame data, for tests of attack numbers);
##       {"attacker": float, "defender": float} = explicit damage multipliers (the calibration tool).
##   "damage_scale": the duel-length scale on its own (float). Absent = the balance data's value, except that "attacker_edge": false
##       (raw frame data) also means 1.0, so the tests that assert exact blows keep measuring raw frame data. A King on either side
##       is always 1.0.
##   "stamina_edge": the stamina half of the advantage on its own: false = neutral, or {"attacker_cost", "defender_cost",
##       "defender_regen"} explicit (sweeps). A King on either side is always neutral.
##   "initial_hp" (int), "initial_stamina" (float), "initial_cooldown" (int ticks): the King seat starts with these
##       values instead of full HP / full stamina / ready ability (battle-royal-v1 "last stand": the King's resources
##       carry over from one duel to the next, docs/architecture/BATTLE_ROYAL_V1.md). They apply ONLY to the seat
##       whose role is "k" (so they require a king in the request), are range-checked against that seat's stats
##       (1..maxHp, 0..maxStamina, 0..cooldownTicks) and never touch the opponent. Zero stamina starts exhausted.
##       Everything else (poise, buffs, positions, the opponent's HP/stamina) starts fresh as always. The result
##       and snapshots stay plain v1 shapes; read the end values with fighter_state().
func start(req: Dictionary, options: Dictionary = {}) -> Dictionary:
	if phase == Phase.COUNTDOWN or phase == Phase.ACTIVE:
		return _error("WRONG_PHASE", "a battle is already running")
	if _codec == null:
		_codec = Codec.new()
	var experimental := bool(options.get("allow_experimental_roles", false))
	var checked := req
	if experimental and typeof(req.get("attacker")) == TYPE_DICTIONARY and typeof(req.get("defender")) == TYPE_DICTIONARY:
		checked = req.duplicate(true)
		for seat in ["attacker", "defender"]:
			if typeof(checked[seat]) == TYPE_DICTIONARY and checked[seat].get("role", "") == "k":
				checked[seat]["role"] = "q"
	if not _codec.valid("BattleRequest", checked):
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
		fighter.allow_experimental = experimental
		add_child(fighter)
		var problem := fighter.setup(data,
				Vector3(0.0, 0.0, -CombatConstants.SPAWN_DISTANCE if is_white else CombatConstants.SPAWN_DISTANCE),
				0.0 if is_white else PI)
		if problem != "":
			_reset()
			return _error("INVALID_PAYLOAD", problem)
		fighters[0 if is_white else 1] = fighter
		_inputs[fighter.player_id] = CombatInputState.new()

	var carried := _apply_initial_state(options)
	if carried != "":
		_reset()
		return _error("INVALID_PAYLOAD", carried)
	_apply_attacker_edge(options, str(attacker_data["role"]), str(defender_data["role"]))

	server_tick = int(req["startTick"])
	countdown_remaining = CombatConstants.COUNTDOWN_TICKS
	duration_remaining = CombatConstants.DURATION_TICKS
	for state in _inputs.values():
		state.last_accept_tick = server_tick
	phase = Phase.COUNTDOWN
	return {"ok": true}


## Sets the attacker's advantage and the duel-length scale for this duel (the "attacker_edge", "stamina_edge" and "damage_scale" start
## options): the damage multipliers, the per-seat stamina cost/regeneration rule and the HP damage scale. All default to the balance
## data's values for this pairing; a King on either side is always neutral (King's last stand keeps its own balance).
func _apply_attacker_edge(options: Dictionary, attacker_role: String, defender_role: String) -> void:
	edge_attacker = 1.0
	edge_defender = 1.0
	damage_scale = 1.0
	var attacker_fighter := attacker()
	var defender_fighter := defender()
	var rule := {"attacker_cost": 1.0, "defender_cost": 1.0, "defender_regen": 1.0}
	var neutral_pair := attacker_role == "k" or defender_role == "k"
	var damage_option = options.get("attacker_edge", null)
	var stamina_option = options.get("stamina_edge", null)
	var all_off: bool = damage_option is bool and not damage_option   # attacker_edge: false = raw frame data, both rules off
	if not neutral_pair:
		if damage_option is Dictionary:
			edge_attacker = maxf(0.01, float(damage_option.get("attacker", 1.0)))
			edge_defender = maxf(0.01, float(damage_option.get("defender", 1.0)))
		elif not all_off:
			var pair := Balance.attacker_edge(attacker_role, defender_role)
			edge_attacker = float(pair[0])
			edge_defender = float(pair[1])
		var scale_option = options.get("damage_scale", null)
		if scale_option is float or scale_option is int:
			damage_scale = clampf(float(scale_option), 0.01, 1.0)
		elif not all_off:
			damage_scale = Balance.damage_scale(attacker_role, defender_role)
		if stamina_option is Dictionary:
			rule.merge(stamina_option, true)
		elif not all_off and not (stamina_option is bool and not stamina_option):
			rule = Balance.stamina_edge()
	attacker_fighter.stamina.cost_multiplier = maxf(0.0, float(rule["attacker_cost"]))
	defender_fighter.stamina.cost_multiplier = maxf(0.0, float(rule["defender_cost"]))
	defender_fighter.stamina.seat_regen = maxf(0.0, float(rule["defender_regen"]))


## Applies the optional "initial_*" start options to the King seat. Returns "" or the reason the options are refused.
func _apply_initial_state(options: Dictionary) -> String:
	var wanted := ["initial_hp", "initial_stamina", "initial_cooldown"].filter(func(key): return options.has(key))
	if wanted.is_empty():
		return ""
	var king: FighterController = null
	for fighter in fighters:
		if fighter != null and fighter.role == "k":
			king = fighter
	if king == null or not bool(options.get("allow_experimental_roles", false)):
		return "initial_* start options need an experimental King seat"
	if options.has("initial_hp"):
		var hp = options["initial_hp"]
		if not (hp is int) or hp < 1 or hp > king.health.maximum:
			return "initial_hp must be an integer within 1..maxHp"
	if options.has("initial_stamina"):
		var stamina = options["initial_stamina"]
		if not (stamina is int or stamina is float) or not is_finite(float(stamina)) or float(stamina) < 0.0 or float(stamina) > king.stamina.maximum:
			return "initial_stamina must be within 0..maxStamina"
	if options.has("initial_cooldown"):
		var cooldown = options["initial_cooldown"]
		if not (cooldown is int) or cooldown < 0 or cooldown > king.ability.cooldown_total:
			return "initial_cooldown must be an integer within 0..cooldownTicks"
	if options.has("initial_hp"):
		king.health.current = int(options["initial_hp"])
	if options.has("initial_stamina"):
		king.stamina.current = float(options["initial_stamina"])
		king.stamina.exhausted = king.stamina.current <= 0.0
	if options.has("initial_cooldown"):
		king.ability.cooldown_remaining = int(options["initial_cooldown"])
	return ""


## End-of-fight (or current) resources of one seat in the units the next duel's start options take:
## {"hp": int, "stamina": float (snapped to 0.01, as snapshots report it), "cooldownTicks": int}. {} for an unknown seat.
func fighter_state(player_id: String) -> Dictionary:
	var fighter := fighter_by_id(player_id)
	if fighter == null:
		return {}
	return {"hp": fighter.health.current, "stamina": snappedf(fighter.stamina.current, 0.01),
			"cooldownTicks": fighter.ability.cooldown_remaining}


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
	edge_attacker = 1.0
	edge_defender = 1.0
	damage_scale = 1.0
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


## Accepted input bookkeeping for one seat: last accepted sequence and the cumulative press counters the
## simulation has seen. A transport embeds this in its resume message (Codex's InputResume).
func accepted_input(player_id: String) -> Dictionary:
	var state: CombatInputState = _inputs.get(player_id, null)
	if state == null:
		return {}
	return {"sequence": state.last_sequence, "light": int(state.seen["light"]), "heavy": int(state.seen["heavy"]),
			"dodge": int(state.seen["dodge"]), "parry": int(state.seen["parry"]), "ability": int(state.seen["ability"])}


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
	if d.sm.counter_window_open() and d.faces_toward(a.global_position, float(d.ability.definition["counter_arc_deg"])):
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
	# The attacker's advantage: the weaker side of this pairing hits harder (before armour, so it applies to chip damage too).
	var edge := edge_attacker if a.player_id == request["attacker"]["playerId"] else edge_defender
	if edge != 1.0:
		raw = maxi(1, roundi(float(raw) * edge))
	var away_from_attacker := CombatConstants.flat(d.global_position - a.global_position)

	# 1. Dodge invulnerability.
	if d.sm.iframes_active():
		_emit("dodge", a, d, 0)
		return

	# 2. Royal Counter (King): a frontal hit inside the counter window is negated, the attacker is staggered and
	# the King ripostes (an ordinary attack through this same path). Reported as a "parry" event (contract enum).
	if d.sm.counter_window_open() and d.faces_toward(a.global_position, float(d.ability.definition["counter_arc_deg"])):
		a.sm.enter_staggered(int(d.ability.definition["counter_stagger_ticks"]), "parried")
		a.add_knockback(-away_from_attacker, 0.6)
		d.sm.on_counter_success(a)
		_emit("parry", a, d, 0)
		return

	# 3. Perfect parry: the press landed inside the window and the attacker is in front.
	if d.sm.parry_window_open() and d.faces_toward(a.global_position, float(d.profile["parry_arc_deg"])):
		a.sm.enter_staggered(int(d.profile["parry_stagger_ticks"]), "parried")
		a.add_knockback(-away_from_attacker, 0.6)
		d.sm.on_parry_success()
		d.stamina.refund(float(d.profile["parry_refund"]))
		_emit("parry", a, d, 0)
		return

	# 4. Block: absorbs a frontal hit for stamina; not enough stamina breaks the guard.
	if d.sm.guard_up() and d.faces_toward(a.global_position, float(d.profile["block_arc_deg"])):
		var guard_cost := float(raw) * atk.guard_cost_mult * float(d.profile["block_cost_mult"])
		if d.stamina.can_afford(guard_cost):
			d.stamina.lose(guard_cost)
			d.add_knockback(away_from_attacker, atk.knockback_m * 0.5)
			_emit("block", a, d, 0)
		else:
			d.stamina.lose(d.stamina.current)  # drained to zero -> exhausted
			var chip := _deal_damage(d, raw, 0.5)
			d.sm.enter_staggered(int(d.profile["guardbreak_stun"]), "guardbreak")
			_emit("guardbreak", a, d, chip)
			_defeat_if_dead(d)
		return

	# 5. Clean hit.
	var dealt := _deal_damage(d, raw)
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


## The strength of a blow as the presentation should feel it: the HP it removed, scaled back by the duel-length scale, so the hit
## effects, hitstop, camera shake and sounds are those of the frame data whatever the duel's length (a Pawn's jab is a jab even when
## the fight is tuned to last longer). Events stay truthful: `damage` is the HP actually removed.
func felt_damage(damage: int) -> int:
	return roundi(float(damage) / maxf(damage_scale, 0.05))


func _after_armor(d: FighterController, raw: int) -> int:
	return maxi(1, roundi(float(raw) * (1.0 - float(d.profile["armor"]))))


## Takes the HP off `d` for a blow of `raw` damage (after the attacker's edge): armour, then the duel-length scale. `factor` is 0.5
## for the chip damage of a guard break. At scale 1.0 this is exactly the original whole-number rule; below 1.0 the fraction is carried
## (HealthComponent.apply_scaled), so a long fight keeps the exact relative strength of every blow instead of rounding it away.
func _deal_damage(d: FighterController, raw: int, factor: float = 1.0) -> int:
	if damage_scale == 1.0:
		var whole := _after_armor(d, raw)
		return d.health.apply_damage(whole if factor == 1.0 else maxi(1, roundi(float(whole) * factor)))
	return d.health.apply_scaled(float(raw) * (1.0 - float(d.profile["armor"])) * factor * damage_scale)


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
## `include_events` false skips the event copy (bots and tools that only need fighter state each tick).
func snapshot(include_events: bool = true) -> Dictionary:
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
		"events": recent_events.duplicate(true) if include_events else [],
		"result": result.duplicate(true) if phase == Phase.FINISHED else null,
	}


func _error(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}
