extends RefCounted
## Shared helpers for the computer-opponent test suites (no scenes, no class_name).
const Classic = preload("res://chess/chess_engine.gd")

static func uci(m: Dictionary) -> String:
	return Classic.square(m.from) + Classic.square(m.to) + m.promotion

## Plays a whole game of ChessAI against ChessAI on the repository engine. Every chosen move is checked against
## `legal_moves()` before it is played. Returns {moves, result, reason, plies, illegal, capped, engine}.
static func play_game(white_level: int, black_level: int, seed_value: int, max_plies: int, node_scale: float, fen: String = Classic.START_FEN) -> Dictionary:
	var engine = Classic.new()
	engine.load_fen(fen)
	var ais = {"w": ChessAI.new(white_level, seed_value * 2 + 1), "b": ChessAI.new(black_level, seed_value * 2 + 2)}
	for color in ais:
		ais[color].deterministic = true
		ais[color].node_scale = node_scale
	var moves: Array = []
	var illegal = 0
	while engine.result.is_empty() and moves.size() < max_plies:
		var choice = ais[engine.turn].choose_move(engine)
		if not choice.ok:
			illegal += 1
			break
		var is_legal = false
		for m in engine.legal_moves():
			if m.from == choice.move.from and m.to == choice.move.to and m.promotion == choice.move.promotion:
				is_legal = true
		if not is_legal:
			illegal += 1
			break
		var played = engine.move(choice.from, choice.to, choice.promotion if choice.promotion != "" else "q")
		if not played.ok:
			illegal += 1
			break
		moves.append(choice.from + choice.to + choice.promotion)
	return {"moves": moves, "result": engine.result, "reason": engine.reason, "plies": moves.size(), "illegal": illegal, "capped": engine.result.is_empty(), "engine": engine}

static func material(board: Array) -> int:
	var values = {"p": 1, "n": 3, "b": 3, "r": 5, "q": 9}
	var total = 0
	for p in board:
		if p != "" and values.has(p.to_lower()):
			total += values[p.to_lower()] * (1 if p == p.to_upper() else -1)
	return total
