class_name RemoteChessMatch
extends "res://chess/classic_match.gd"
## Read-only board projection. Local legal moves are hints; the server alone commits.
const BattleRules = preload("res://chess/battle_rules.gd")
var client: OnlineChessClient
var frame: Dictionary = {}
var _last_chess: Dictionary = {}
var _can_play = false

func bind(network_client: OnlineChessClient) -> void:
	client = network_client
	authority_mode = "remote"
	allow_undo = false
	client.frame_received.connect(apply_frame)
	client.connection_changed.connect(func(_connected): changed.emit())
	client.clocks_received.connect(func(sync): remaining = {"w": sync.clocks.whiteMs, "b": sync.clocks.blackMs})

func apply_frame(value: Dictionary) -> void:
	var state: Dictionary = value.state
	var previous_allowed = board_input_allowed()
	var structural = frame.is_empty() or frame.state.phase != state.phase or _last_chess != state.chess or frame.status != value.status
	if _last_chess != state.chess:
		var fresh = BattleRules.new() if state.mode == "battle" else Rules.new()
		if not fresh.load_fen(state.chess.fen).ok:
			return
		var positions = {}
		var ids = {}
		for piece in state.chess.pieces:
			var at = Rules.index(piece.square)
			if at < 0 or positions.has(at) or ids.has(piece.pieceId) or fresh.board[at].to_lower() != piece.role or Rules.side(fresh.board[at]) != piece.color or piece.characterId.get_slice(".", 1) != piece.role:
				return
			positions[at] = piece.pieceId
			ids[piece.pieceId] = true
		var occupied = fresh.board.filter(func(piece): return not piece.is_empty()).size()
		if occupied != positions.size() or state.chess.history.size() != state.chess.ply:
			return
		fresh.initial_fen = state.chess.initialFen
		fresh.history = state.chess.history.duplicate(true)
		engine = fresh
		registry = positions
		_last_chess = state.chess.duplicate(true)
	frame = value.duplicate(true)
	match_id = state.matchId
	players = state.players.duplicate()
	revision = state.chess.revision
	server_tick = state.serverTick
	engine.result = state.result if state.result != null else ""
	engine.reason = state.reason if state.reason != null else ""
	remaining = {"w": value.clocks.whiteMs, "b": value.clocks.blackMs}
	initial_ms = value.clocks.initialMs
	increment_ms = value.clocks.incrementMs
	timed = value.clocks.timed
	started = value.clocks.running
	if structural or previous_allowed != board_input_allowed():
		changed.emit()

func board_input_allowed() -> bool:
	return client != null and client.authenticated and not frame.is_empty() and frame.status == "active" and frame.state.phase == "board" and frame.state.result == null and frame.state.players[engine.turn] == client.player_id

func chess_state() -> Dictionary:
	return _last_chess.duplicate(true) if not _last_chess.is_empty() else super.chess_state()

func play(from: String, to: String, promotion: String = "q") -> Dictionary:
	if not board_input_allowed():
		return {"ok": false, "error": "Wait for your server-authorized turn."}
	return {"ok": not client.chess_move(from, to, promotion).is_empty()}

func poll_clock(_now: int = -1) -> void:
	pass # Rendering a clock can never mutate or adjudicate the match.

func new_game(_base_ms: int = 600000, _increment: int = 0, _fen: String = Rules.START_FEN) -> Dictionary:
	return {"ok": false, "error": "Online positions are owned by the server."}

func resign() -> void:
	if client != null:
		client.command("resign")

func claim_draw(kind: String, intended: Dictionary = {}) -> bool:
	return client != null and not client.command("claim_draw", kind, intended if not intended.is_empty() else null).is_empty()
