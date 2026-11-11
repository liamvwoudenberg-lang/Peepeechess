class_name BattleChessMatch
extends "res://chess/classic_match.gd"
## Owns frozen capture transactions. Only the bound combat authority may resolve them.
signal battle_prepared(request: Dictionary)
const BattleRules = preload("res://chess/battle_rules.gd")
var phase = "board"
var _pending: Dictionary = {}
var _combat: Dictionary = {}
var _intent: Dictionary = {}
var _frozen: Dictionary = {}
var _terminal: Dictionary = {}
var _serial = 0
var _authority: Object
var _profiles: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://chess/battle_stats.json"))

## Subclasses (battle-royal-v1) swap the rules engine here; the default is the preserved C0 / battle-checkmate-v1 rules.
func _new_engine():
	return BattleRules.new()

func _init() -> void:
	engine = _new_engine()
	initial_ms = 0
	remaining = {"w": 0, "b": 0}
	timed = false
	allow_undo = false
	_reset_registry()

func new_game(_base_ms: int = 0, _increment: int = 0, fen: String = BattleRules.START_FEN) -> Dictionary:
	var fresh = _new_engine()
	var loaded = fresh.load_fen(fen)
	if not loaded.ok:
		return loaded
	engine = fresh
	match_id = "battle-" + str(Time.get_ticks_usec())
	revision = 0
	server_tick = 0
	_tick_remainder = 0.0
	initial_ms = 0
	increment_ms = 0
	remaining = {"w": 0, "b": 0}
	timed = false
	started = false
	paused = false
	allow_undo = false
	last_poll = Time.get_ticks_msec()
	_requests.clear()
	_registry_undo.clear()
	_clock_undo.clear()
	_clear_pending()
	_reset_registry()
	changed.emit()
	return {"ok": true}

func board_input_allowed() -> bool:
	return phase == "board" and not paused and engine.result.is_empty()

func bind_combat_authority(source: Object) -> void:
	_authority = source

func pending_request() -> Dictionary:
	return _pending.duplicate(true)

func combat_snapshot() -> Dictionary:
	return _combat.duplicate(true)

## Options the combat host must pass to CombatSimulation.start for the PENDING battle. Empty for every ordinary capture
## (strict v1 behaviour); the royal ruleset supplies the King's carried HP/stamina/cooldown.
func combat_options() -> Dictionary:
	return {}

## Drops a pending transaction without a result because the match ends some other way (forfeit, abort).
func abandon_pending() -> void:
	cancel_pending()

# Starting resources of a fighter in the pending battle: full by default; the royal ruleset overrides these for the king.
func _start_hp(participant: Dictionary):
	return participant.stats.maxHp

func _start_stamina(participant: Dictionary):
	return participant.stats.maxStamina

func _start_cooldown(_participant: Dictionary) -> int:
	return 0

func advance_msec(elapsed: int) -> void:
	# During a duel the trusted fixed-tick simulation owns the match tick.
	if _pending.is_empty():
		super.advance_msec(elapsed)

func _clear_pending() -> void:
	phase = "board"
	_pending.clear()
	_combat.clear()
	_intent.clear()
	_frozen.clear()
	_terminal.clear()

func cancel_pending() -> void:
	if phase == "aftermath":
		commit_battle()
		return
	_clear_pending()
	changed.emit()

func _combatant(at: int) -> Dictionary:
	var piece: String = engine.board[at]
	var color = BattleRules.side(piece)
	var role = piece.to_lower()
	return {"playerId": players[color], "pieceId": registry[at], "characterId": "royal." + role, "color": color, "role": role, "square": BattleRules.square(at), "stats": _profiles[role].duplicate(true)}

func _initial_snapshot(request: Dictionary) -> Dictionary:
	var fighters: Array = []
	for participant in [request.attacker, request.defender]:
		var white = participant.color == "w"
		fighters.append({"playerId": participant.playerId, "pieceId": participant.pieceId, "position": {"x": 0, "y": 0, "z": -2.6 if white else 2.6}, "velocity": {"x": 0, "y": 0, "z": 0}, "yawRadians": 0 if white else PI, "hp": _start_hp(participant), "stamina": _start_stamina(participant), "state": "Idle", "stateTicks": 0, "cooldownTicks": _start_cooldown(participant), "lastInputSequence": 0})
	return {"schemaVersion": 1, "matchId": match_id, "battleId": request.battleId, "serverTick": request.startTick, "countdownTicksRemaining": 180, "durationTicksRemaining": 5400, "fighters": fighters, "events": [], "result": null}

func submit_request(request: Dictionary, authenticated_player_id: String, now: int = -1) -> Dictionary:
	poll_clock(now)
	if not codec.valid("ChessMoveRequest", request):
		return _error(null, "INVALID_PAYLOAD", "Invalid move request.")
	if request.playerId != authenticated_player_id or authenticated_player_id not in players.values():
		return _error(request.requestId, "FORBIDDEN", "This seat cannot play that move.")
	if request.matchId != match_id:
		return _error(request.requestId, "STALE_REVISION", "This match has changed.")
	var key: String = request.playerId + ":" + request.requestId
	var payload = JSON.stringify(request, "", true, true)
	if _requests.has(key):
		if _requests[key].payload == payload:
			return _requests[key].response.duplicate(true)
		return _error(request.requestId, "INVALID_PAYLOAD", "Request ID already used for another move.")
	if request.expectedRevision != revision:
		return _error(request.requestId, "STALE_REVISION", "The board changed.")
	if not board_input_allowed():
		return _error(request.requestId, "WRONG_PHASE", "Wait for the battle and return to the board.")
	if players[engine.turn] != authenticated_player_id:
		return _error(request.requestId, "FORBIDDEN", "It is the other player's turn.")
	var inspected = engine.inspect_move(request.from, request.to, request.promotion if request.promotion != null else "q")
	if not inspected.ok:
		return _error(request.requestId, inspected.code, inspected.error)
	var m: Dictionary = inspected.move
	if not engine.is_capture(m):
		return super.submit_request(request, authenticated_player_id, now)
	var victim: int = m.to + (-8 if engine.turn == "w" else 8) if m.flag == "ep" else m.to
	_serial += 1
	var battle_id = match_id + ":duel:" + str(_serial)
	var prepared = {"schemaVersion": 1, "matchId": match_id, "battleId": battle_id, "expectedRevision": revision, "beforeFen": engine.fen(), "from": request.from, "to": request.to, "promotion": m.promotion if not m.promotion.is_empty() else null, "attacker": _combatant(m.from), "defender": _combatant(victim), "arenaId": "stone-v1", "startTick": server_tick, "countdownTicks": 180, "durationTicks": 5400, "seed": absi(battle_id.hash()) % 2147483647}
	if not codec.valid("BattleRequest", prepared):
		return _error(request.requestId, "INTERNAL", "The battle request could not be constructed.")
	_frozen = chess_state().duplicate(true)
	_pending = prepared
	_intent = m.duplicate(true)
	_combat = _initial_snapshot(prepared)
	phase = "combat"
	var response = {"ok": true, "battleId": battle_id, "revision": revision}
	_requests[key] = {"payload": payload, "response": response}
	changed.emit()
	battle_prepared.emit(_pending.duplicate(true))
	return response

func _trusted(source: Object) -> bool:
	return is_instance_valid(source) and is_instance_valid(_authority) and source == _authority

func _still_frozen() -> bool:
	return not _pending.is_empty() and chess_state() == _frozen and players[_pending.attacker.color] == _pending.attacker.playerId and players[_pending.defender.color] == _pending.defender.playerId

func _result_valid(value: Dictionary) -> bool:
	if not codec.valid("BattleResult", value) or _pending.is_empty():
		return false
	var r = _pending
	if value.matchId != match_id or value.battleId != r.battleId or value.expectedRevision != revision:
		return false
	var active_start: int = r.startTick + r.countdownTicks
	var end: int = active_start + r.durationTicks
	if value.resolvedTick < active_start or value.resolvedTick > end or value.resolvedTick < _combat.serverTick:
		return false
	if value.winnerPlayerId != r[value.outcome].playerId or value.attackerHp > r.attacker.stats.maxHp or value.defenderHp > r.defender.stats.maxHp:
		return false
	var winner_hp = value.attackerHp if value.outcome == "attacker" else value.defenderHp
	var loser_hp = value.defenderHp if value.outcome == "attacker" else value.attackerHp
	match value.reason:
		"knockout": return loser_hp == 0 and winner_hp > 0
		"double_knockout": return value.outcome == "defender" and winner_hp == 0 and loser_hp == 0
		"timeout_hp", "timeout_tie":
			if value.resolvedTick != end or winner_hp <= 0 or loser_hp <= 0:
				return false
			var a = value.attackerHp * r.defender.stats.maxHp
			var d = value.defenderHp * r.attacker.stats.maxHp
			if value.reason == "timeout_tie":
				return a == d and value.outcome == "defender"
			return a > d if value.outcome == "attacker" else d > a
	return false

func accept_snapshot(value: Dictionary, source: Object) -> bool:
	if not _trusted(source) or phase != "combat" or not _still_frozen() or not codec.valid("CombatSnapshot", value):
		return false
	var r = _pending
	var end: int = r.startTick + 180 + 5400
	if value.matchId != match_id or value.battleId != r.battleId or value.serverTick < _combat.serverTick or value.serverTick > end:
		return false
	if value.countdownTicksRemaining != maxi(0, r.startTick + 180 - value.serverTick) or value.durationTicksRemaining != end - maxi(r.startTick + 180, value.serverTick):
		return false
	var seen: Array = []
	for f in value.fighters:
		var participant: Dictionary = r.attacker if f.playerId == r.attacker.playerId else r.defender
		if f.playerId != participant.playerId or f.playerId in seen or f.pieceId != participant.pieceId or f.hp > participant.stats.maxHp or f.stamina > participant.stats.maxStamina:
			return false
		for previous in _combat.fighters:
			if previous.playerId == f.playerId and f.lastInputSequence < previous.lastInputSequence:
				return false
		if value.countdownTicksRemaining > 0 and (f.hp != _start_hp(participant) or f.stamina != _start_stamina(participant)):
			return false
		seen.append(f.playerId)
	for event in value.events:
		if event.tick > value.serverTick or event.tick < r.startTick or event.actorPlayerId not in players.values() or event.targetPlayerId not in players.values():
			return false
	if value.result != null:
		if value.result.resolvedTick != value.serverTick or not _result_valid(value.result):
			return false
		for f in value.fighters:
			if f.hp != (value.result.attackerHp if f.playerId == r.attacker.playerId else value.result.defenderHp):
				return false
	_combat = value.duplicate(true)
	server_tick = value.serverTick
	return true

func accept_result(value: Dictionary, source: Object) -> Dictionary:
	if not _trusted(source):
		return {"ok": false, "error": "Combat result did not come from the bound authority."}
	if phase == "aftermath" and value == _terminal and _still_frozen():
		return {"ok": true, "duplicate": true}
	if phase != "combat" or not _still_frozen() or not _result_valid(value) or (_combat.result != null and _combat.result != value):
		return {"ok": false, "error": "Invalid or stale combat result."}
	_terminal = value.duplicate(true)
	_combat.result = value.duplicate(true)
	_combat.serverTick = value.resolvedTick
	_combat.countdownTicksRemaining = 0
	_combat.durationTicksRemaining = _pending.startTick + 180 + 5400 - value.resolvedTick
	for f in _combat.fighters:
		f.hp = value.attackerHp if f.playerId == _pending.attacker.playerId else value.defenderHp
		if f.hp == 0:
			f.state = "Defeated"
	server_tick = value.resolvedTick
	phase = "aftermath"
	changed.emit()
	return {"ok": true, "duplicate": false}

func commit_battle() -> Dictionary:
	if phase != "aftermath" or _terminal.is_empty() or not _still_frozen():
		return {"ok": false, "error": "No validated battle can be committed."}
	var m = _intent.duplicate(true)
	var winner: String = _terminal.outcome
	var victim: int = BattleRules.index(_pending.defender.square)
	var committed = engine.settle_capture(m, winner)
	if not committed.ok:
		return committed
	if winner == "attacker":
		registry.erase(victim)
		registry[m.to] = registry[m.from]
	registry.erase(m.from)
	revision += 1
	_clear_pending()
	move_committed.emit(m)
	changed.emit()
	return {"ok": true, "revision": revision, "outcome": winner}

func undo() -> bool:
	return false

func set_paused(value: bool) -> bool:
	if phase != "board":
		return false
	return super.set_paused(value)

func resign() -> void:
	poll_clock()
	var resigning_color = engine.turn
	if phase == "aftermath":
		var committed = commit_battle()
		if not committed.ok:
			return
	if engine.result.is_empty():
		engine.result = "0-1" if resigning_color == "w" else "1-0"
		engine.reason = "Resignation"
	_clear_pending()
	changed.emit()

func agree_draw() -> void:
	if phase == "board":
		super.agree_draw()

func chess_state() -> Dictionary:
	var state = super.chess_state()
	for i in range(engine.history.size()):
		state.history[i].outcome = engine.history[i].get("outcome", state.history[i].outcome)
	return state

func match_state() -> Dictionary:
	var state = super.match_state()
	state.mode = "battle"
	state.rulesetId = "battle-checkmate-v1"
	state.phase = "complete" if not engine.result.is_empty() else phase
	state.battle = _pending.duplicate(true) if not _pending.is_empty() else null
	state.combat = _combat.duplicate(true) if not _combat.is_empty() else null
	return state
