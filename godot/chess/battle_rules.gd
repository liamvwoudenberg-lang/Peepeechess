class_name BattleChessRules
extends "res://chess/chess_engine.gd"
## C0 / battle-checkmate-v1. Combat never mutates this board directly.

func is_capture(m: Dictionary) -> bool:
	return not m.captured.is_empty() or m.flag == "ep"

func _apply_defender_win(m: Dictionary) -> void:
	var color = turn
	board[m.from] = ""
	if m.from in [0, 7, 56, 63]:
		castling = castling.replace({0: "Q", 7: "K", 56: "q", 63: "k"}[m.from], "")
	ep = -1
	halfmove = 0
	fullmove += 1 if color == "b" else 0
	turn = opposite(color)

func capture_restriction(m: Dictionary) -> String:
	if not is_capture(m):
		return ""
	if m.piece.to_lower() == "k" or m.captured.to_lower() == "k":
		return "C0 kings use checkmate and cannot enter capture duels."
	var saved = _position()
	var moving_color = turn
	_apply_defender_win(m)
	var unsafe = in_check(moving_color)
	_restore(saved)
	return "Losing this battle would leave your king in check." if unsafe else ""

func legal_moves(from: int = -1) -> Array:
	var admitted: Array = []
	for m in super.legal_moves(from):
		if capture_restriction(m).is_empty():
			admitted.append(m)
	return admitted

func inspect_move(from: String, to: String, promotion: String = "q") -> Dictionary:
	for m in super.legal_moves(index(from)):
		if m.from == index(from) and m.to == index(to) and (m.promotion.is_empty() or m.promotion == promotion):
			var restriction = capture_restriction(m)
			if not restriction.is_empty():
				return {"ok": false, "code": "UNSAFE_OUTCOME", "error": restriction}
			return {"ok": true, "move": m}
	return {"ok": false, "code": "ILLEGAL_MOVE", "error": "That move is not legal."}

func move(from: String, to: String, promotion: String = "q") -> Dictionary:
	var inspected = inspect_move(from, to, promotion)
	if not inspected.ok:
		return inspected
	if is_capture(inspected.move):
		return {"ok": false, "error": "Capture requires an authoritative battle result."}
	return super.move(from, to, promotion)

func settle_capture(intent: Dictionary, outcome: String) -> Dictionary:
	if not result.is_empty() or outcome not in ["attacker", "defender"]:
		return {"ok": false, "error": "Invalid capture resolution."}
	var inspected = inspect_move(square(intent.from), square(intent.to), intent.promotion if not intent.promotion.is_empty() else "q")
	if not inspected.ok or inspected.move != intent or not is_capture(intent):
		return {"ok": false, "error": "The pending capture no longer matches the board."}
	var san = _san(intent, legal_moves())
	positions.append(_position())
	if outcome == "attacker":
		_apply(intent)
	else:
		_apply_defender_win(intent)
		san += " [defended]"
	if in_check():
		san += "#" if legal_moves().is_empty() else "+"
	history.append({"from": square(intent.from), "to": square(intent.to), "promotion": intent.promotion, "san": san, "fen": fen(), "move": intent.duplicate(true), "outcome": outcome})
	keys.append(position_key())
	_adjudicate()
	return {"ok": true, "san": san, "move": intent}

func _adjudicate() -> void:
	if legal_moves().is_empty():
		reason = "Checkmate" if in_check() else "Stalemate"
		result = ("0-1" if turn == "w" else "1-0") if in_check() else "1/2-1/2"
	elif insufficient_material():
		result = "1/2-1/2"
		reason = "Insufficient material"
	elif halfmove >= 100:
		result = "1/2-1/2"
		reason = "Fifty-move rule"
	elif keys.count(position_key()) >= 3:
		result = "1/2-1/2"
		reason = "Threefold repetition"

func claimable_draws(_intended: Dictionary = {}) -> Array:
	return [] # C0 draws are automatic, unlike Classic claims.

func pgn() -> String:
	# A defended capture is not legal SAN/PGN. Export a custom chronicle instead.
	var entries: Array = []
	for h in history:
		entries.append({"from": h.from, "to": h.to, "promotion": h.promotion, "notation": h.san, "outcome": h.get("outcome", "quiet"), "fen": h.fen})
	return JSON.stringify({"rulesetId": "battle-checkmate-v1", "initialFen": initial_fen, "history": entries, "result": result, "reason": reason}, "  ", true, true)
