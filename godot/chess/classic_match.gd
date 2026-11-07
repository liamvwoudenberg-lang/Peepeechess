class_name ClassicMatch
extends RefCounted
## Local authority and admission boundary; views never mutate the rules engine.
signal changed
signal move_committed(move: Dictionary)
signal rejected(message: String)
const Rules = preload("res://chess/chess_engine.gd")
const Codec = preload("res://contracts/codec.gd")
var engine = Rules.new()
var codec = Codec.new()
var match_id = "local-1"
var players = {"w": "local-white", "b": "local-black"}
var revision = 0
var server_tick = 0
var registry: Dictionary = {}
var _registry_undo: Array = []
var _clock_undo: Array = []
var _requests: Dictionary = {}
var remaining = {"w": 600000, "b": 600000}
var initial_ms = 600000
var increment_ms = 0
var timed = true
var started = false
var paused = false
var allow_undo = true
var authority_mode = "local"
var last_poll = -1
var _tick_remainder = 0.0

func _init() -> void:
	_reset_registry()

func _reset_registry() -> void:
	registry.clear()
	for at in range(64):
		var p: String = engine.board[at]
		if not p.is_empty():
			registry[at] = Rules.side(p) + "-" + p.to_lower() + "-" + Rules.square(at)

func new_game(base_ms: int = 600000, increment: int = 0, fen: String = Rules.START_FEN) -> Dictionary:
	var fresh = Rules.new()
	var loaded = fresh.load_fen(fen)
	if not loaded.ok:
		return loaded
	engine = fresh
	match_id = "local-" + str(Time.get_ticks_usec())
	revision = 0
	server_tick = 0
	_tick_remainder = 0.0
	initial_ms = maxi(0, base_ms)
	increment_ms = maxi(0, increment)
	timed = base_ms > 0
	remaining = {"w": initial_ms, "b": initial_ms}
	started = false
	paused = false
	last_poll = Time.get_ticks_msec()
	_registry_undo.clear()
	_clock_undo.clear()
	_requests.clear()
	_reset_registry()
	changed.emit()
	return {"ok": true}

func advance_msec(elapsed: int) -> void:
	if paused or not engine.result.is_empty():
		return
	_tick_remainder += maxf(0, elapsed) * 0.06
	var ticks = int(_tick_remainder)
	server_tick += ticks
	_tick_remainder -= ticks
	if timed and started:
		var color = engine.turn
		remaining[color] = maxi(0, remaining[color] - maxi(0, elapsed))
		if remaining[color] == 0:
			var winner = Rules.opposite(color)
			engine.result = ("1-0" if winner == "w" else "0-1") if engine.can_mate(winner) else "1/2-1/2"
			engine.reason = "Time expired" if engine.result != "1/2-1/2" else "Time expired · no mating material"
			changed.emit()

func poll_clock(now: int = -1) -> void:
	if now < 0:
		now = Time.get_ticks_msec()
	if last_poll >= 0:
		advance_msec(maxi(0, now - last_poll))
	last_poll = now

func set_paused(value: bool) -> bool:
	if authority_mode != "local" or not engine.result.is_empty():
		return false
	poll_clock()
	paused = value
	changed.emit()
	return true

func start_clock() -> void:
	started = true
	last_poll = Time.get_ticks_msec()
	changed.emit()

func _error(request_id: Variant, code: String, message: String) -> Dictionary:
	rejected.emit(message)
	return {"ok": false, "error": {"schemaVersion": 1, "requestId": request_id, "code": code, "message": message, "retryable": code in ["STALE_REVISION", "WRONG_PHASE"], "currentRevision": revision}}

func submit_request(request: Dictionary, authenticated_player_id: String, now: int = -1) -> Dictionary:
	poll_clock(now)
	if not codec.valid("ChessMoveRequest", request):
		return _error(null, "INVALID_PAYLOAD", "Invalid move request.")
	if request.playerId != authenticated_player_id or authenticated_player_id not in players.values():
		return _error(request.requestId, "FORBIDDEN", "This seat cannot play that move.")
	if request.matchId != match_id:
		return _error(request.requestId, "STALE_REVISION", "This match has changed.")
	var key: String = request.playerId + ":" + request.requestId
	var serialized = JSON.stringify(request, "", true, true)
	if _requests.has(key):
		if _requests[key].payload == serialized:
			return _requests[key].response.duplicate(true)
		return _error(request.requestId, "INVALID_PAYLOAD", "Request ID was already used for another move.")
	if request.expectedRevision != revision:
		return _error(request.requestId, "STALE_REVISION", "The board changed. Refresh and try again.")
	if paused or not engine.result.is_empty():
		return _error(request.requestId, "WRONG_PHASE", "Resume or start a new game first.")
	if players[engine.turn] != authenticated_player_id:
		return _error(request.requestId, "FORBIDDEN", "It is the other player's turn.")
	var before_registry = registry.duplicate()
	var before_clock = {"remaining": remaining.duplicate(), "started": started}
	var moving_color = engine.turn
	var outcome = engine.move(request.from, request.to, request.promotion if request.promotion != null else "q")
	if not outcome.ok:
		return _error(request.requestId, "ILLEGAL_MOVE", outcome.error)
	var m: Dictionary = outcome.move
	_registry_undo.append(before_registry)
	_clock_undo.append(before_clock)
	registry.erase(m.to)
	registry[m.to] = registry[m.from]
	registry.erase(m.from)
	if m.flag == "ep":
		registry.erase(m.to + (-8 if moving_color == "w" else 8))
	if m.flag == "castle":
		var rook_from = m.from + (3 if m.to > m.from else -4)
		var rook_to = m.from + (1 if m.to > m.from else -1)
		registry[rook_to] = registry[rook_from]
		registry.erase(rook_from)
	if timed:
		remaining[moving_color] += increment_ms
	started = true
	revision += 1
	var response = {"ok": true, "san": outcome.san, "revision": revision}
	_requests[key] = {"payload": serialized, "response": response}
	move_committed.emit(m)
	changed.emit()
	return response

func play(from: String, to: String, promotion: String = "q") -> Dictionary:
	if authority_mode != "local":
		return _error(null, "FORBIDDEN", "Use authenticated move admission for online seats.")
	return submit_request({"schemaVersion": 1, "matchId": match_id, "requestId": "ui-" + str(Time.get_ticks_usec()), "playerId": players[engine.turn], "expectedRevision": revision, "from": from, "to": to, "promotion": promotion if promotion in ["q", "r", "b", "n"] else null}, players[engine.turn])

func undo() -> bool:
	if not allow_undo or authority_mode != "local" or engine.history.is_empty():
		return false
	if not engine.undo():
		return false
	registry = _registry_undo.pop_back()
	var prior = _clock_undo.pop_back()
	remaining = prior.remaining
	started = prior.started
	last_poll = Time.get_ticks_msec()
	# Undo is a local analysis operation, not a standard forward-ply commit.
	# Keep a monotonic revision so no request from an abandoned line becomes valid.
	revision += 1
	changed.emit()
	return true

func claim_draw(kind: String, intended: Dictionary = {}) -> bool:
	poll_clock()
	if paused or not engine.claim_draw(kind, intended):
		return false
	changed.emit()
	return true

func agree_draw() -> void:
	poll_clock()
	if engine.result.is_empty() and authority_mode == "local":
		engine.result = "1/2-1/2"
		engine.reason = "Draw by agreement"
		changed.emit()

func clock_state() -> Dictionary:
	return {"whiteMs": remaining.w, "blackMs": remaining.b, "incrementMs": increment_ms, "initialMs": initial_ms, "running": started and not paused and engine.result.is_empty(), "timed": timed, "turn": engine.turn}

func resign() -> void:
	poll_clock()
	if engine.result.is_empty():
		engine.result = "0-1" if engine.turn == "w" else "1-0"
		engine.reason = "Resignation"
		changed.emit()

func chess_state() -> Dictionary:
	var pieces: Array = []
	for at in range(64):
		var p: String = engine.board[at]
		if not p.is_empty():
			pieces.append({"pieceId": registry[at], "square": Rules.square(at), "color": Rules.side(p), "role": p.to_lower(), "characterId": "royal." + p.to_lower()})
	var moves: Array = []
	for h in engine.history:
		var capture = not h.move.captured.is_empty() or h.move.flag == "ep"
		moves.append({"from": h.from, "to": h.to, "promotion": h.promotion if not h.promotion.is_empty() else null, "outcome": "attacker" if capture else "quiet", "fen": h.fen})
	return {"schemaVersion": 1, "matchId": match_id, "revision": revision, "ply": engine.history.size(), "initialFen": engine.initial_fen, "fen": engine.fen(), "pieces": pieces, "history": moves}

func match_state() -> Dictionary:
	return {"schemaVersion": 1, "matchId": match_id, "serverTick": server_tick, "mode": "classic", "rulesetId": "classic-v1", "phase": "complete" if not engine.result.is_empty() else "board", "players": players.duplicate(), "chess": chess_state(), "battle": null, "combat": null, "result": engine.result if not engine.result.is_empty() else null, "reason": engine.reason if not engine.reason.is_empty() else null}
