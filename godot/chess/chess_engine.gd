class_name ClassicChess
extends RefCounted
## Original native standard-chess rules. No scenes, clocks, networking or combat.
const START_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
const FILES = "abcdefgh"
const KNIGHT = [Vector2i(1, 2), Vector2i(2, 1), Vector2i(2, -1), Vector2i(1, -2), Vector2i(-1, -2), Vector2i(-2, -1), Vector2i(-2, 1), Vector2i(-1, 2)]
const DIAGONALS = [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
const STRAIGHTS = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
var board: Array = []
var turn = "w"
var castling = "KQkq"
var ep = -1
var halfmove = 0
var fullmove = 1
var initial_fen = START_FEN
var history: Array = []
var positions: Array = []
var keys: Array = []
var result = ""
var reason = ""

func _init() -> void:
	load_fen(START_FEN)

static func square(index: int) -> String:
	return FILES[index % 8] + str(index / 8 + 1) if index >= 0 and index < 64 else "-"

static func index(name: String) -> int:
	if name.length() != 2 or FILES.find(name[0]) < 0 or not "12345678".contains(name[1]):
		return -1
	return FILES.find(name[0]) + (int(name[1]) - 1) * 8

static func side(piece: String) -> String:
	if piece.is_empty():
		return ""
	return "w" if piece == piece.to_upper() else "b"

static func opposite(color: String) -> String:
	return "b" if color == "w" else "w"

func _position() -> Dictionary:
	return {"board": board.duplicate(), "turn": turn, "castling": castling, "ep": ep, "halfmove": halfmove, "fullmove": fullmove}

func _restore(p: Dictionary) -> void:
	board = p.board.duplicate()
	turn = p.turn
	castling = p.castling
	ep = p.ep
	halfmove = p.halfmove
	fullmove = p.fullmove

func load_fen(text: String) -> Dictionary:
	# Validate transactionally: a rejected import leaves all match state unchanged.
	var parts = text.strip_edges().split(" ", false)
	if parts.size() != 6:
		return {"ok": false, "error": "FEN needs six fields."}
	var rows = parts[0].split("/")
	if rows.size() != 8 or parts[1] not in ["w", "b"]:
		return {"ok": false, "error": "Invalid board or active color."}
	var next: Array = []
	next.resize(64)
	next.fill("")
	for row in range(8):
		var file = 0
		for ch in rows[row]:
			if "12345678".contains(ch):
				file += int(ch)
			elif "prnbqkPRNBQK".contains(ch):
				if file >= 8 or (ch.to_lower() == "p" and row in [0, 7]):
					return {"ok": false, "error": "Invalid pawn rank or row length."}
				next[(7 - row) * 8 + file] = ch
				file += 1
			else:
				return {"ok": false, "error": "Unknown FEN piece."}
		if file != 8:
			return {"ok": false, "error": "Each FEN rank must have eight squares."}
	if next.count("K") != 1 or next.count("k") != 1:
		return {"ok": false, "error": "Exactly one king of each color is required."}
	for color in ["w", "b"]:
		var count_pieces = 0
		var count_pawns = 0
		for p in next:
			if side(p) == color:
				count_pieces += 1
				if p.to_lower() == "p":
					count_pawns += 1
		if count_pieces > 16 or count_pawns > 8:
			return {"ok": false, "error": "Too many pieces or pawns."}
	var rights = "" if parts[2] == "-" else parts[2]
	var canonical = ""
	for right in "KQkq":
		if right in rights:
			canonical += right
	if canonical != rights:
		return {"ok": false, "error": "Invalid or duplicate castling rights."}
	for right in rights:
		var king_at = 4 if right == right.to_upper() else 60
		var rook_at = {"K": 7, "Q": 0, "k": 63, "q": 56}[right]
		if next[king_at] != ("K" if king_at == 4 else "k") or next[rook_at] != ("R" if king_at == 4 else "r"):
			return {"ok": false, "error": "Castling rights require the original king and rook."}
	var ep_next = -1 if parts[3] == "-" else index(parts[3])
	if parts[3] != "-":
		var rank_needed = 5 if parts[1] == "w" else 2
		var pawn_at = ep_next - 8 if parts[1] == "w" else ep_next + 8
		var origin = ep_next + 8 if parts[1] == "w" else ep_next - 8
		if ep_next < 0 or ep_next / 8 != rank_needed or not next[ep_next].is_empty() or next[pawn_at] != ("p" if parts[1] == "w" else "P") or not next[origin].is_empty():
			return {"ok": false, "error": "Invalid en passant target."}
	for field in [parts[4], parts[5]]:
		if not field.is_valid_int() or field.begins_with("-") or field.begins_with("+") or int(field) > 2147483647:
			return {"ok": false, "error": "Invalid move counters."}
	if int(parts[5]) < 1:
		return {"ok": false, "error": "Fullmove number must be positive."}
	var old = _position() if board.size() == 64 else {}
	board = next
	turn = parts[1]
	castling = rights
	ep = ep_next
	halfmove = int(parts[4])
	fullmove = int(parts[5])
	if in_check(opposite(turn)):
		if not old.is_empty():
			_restore(old)
		return {"ok": false, "error": "The side that just moved cannot be in check."}
	history.clear()
	positions.clear()
	keys.clear()
	result = ""
	reason = ""
	initial_fen = fen()
	keys.append(position_key())
	_adjudicate()
	return {"ok": true}

func fen() -> String:
	var ranks: Array[String] = []
	for rank in range(7, -1, -1):
		var row = ""
		var empty = 0
		for file in range(8):
			var p: String = board[rank * 8 + file]
			if p.is_empty():
				empty += 1
			else:
				if empty:
					row += str(empty)
					empty = 0
				row += p
		if empty:
			row += str(empty)
		ranks.append(row)
	return "/".join(ranks) + " " + turn + " " + (castling if not castling.is_empty() else "-") + " " + square(ep) + " " + str(halfmove) + " " + str(fullmove)

func attacked(target: int, by: String) -> bool:
	var tx = target % 8
	var ty = target / 8
	var pawn_y = ty - (1 if by == "w" else -1)
	for dx in [-1, 1]:
		if tx + dx >= 0 and tx + dx < 8 and pawn_y >= 0 and pawn_y < 8:
			if board[pawn_y * 8 + tx + dx] == ("P" if by == "w" else "p"):
				return true
	for delta in KNIGHT:
		var x = tx + delta.x
		var y = ty + delta.y
		if x >= 0 and x < 8 and y >= 0 and y < 8 and board[y * 8 + x] == ("N" if by == "w" else "n"):
			return true
	for delta in DIAGONALS + STRAIGHTS:
		var x = tx + delta.x
		var y = ty + delta.y
		var distance = 1
		while x >= 0 and x < 8 and y >= 0 and y < 8:
			var p: String = board[y * 8 + x]
			if not p.is_empty():
				if side(p) == by:
					var role = p.to_lower()
					if role == "q" or (role == "k" and distance == 1) or (role == "b" and delta in DIAGONALS) or (role == "r" and delta in STRAIGHTS):
						return true
				break
			x += delta.x
			y += delta.y
			distance += 1
	return false

func in_check(color: String = turn) -> bool:
	var king_at = board.find("K" if color == "w" else "k")
	return king_at < 0 or attacked(king_at, opposite(color))

func _add(moves: Array, from: int, to: int, flag: String = "") -> void:
	var p: String = board[from]
	if p.to_lower() == "p" and to / 8 in [0, 7]:
		for promotion in ["q", "r", "b", "n"]:
			moves.append({"from": from, "to": to, "piece": p, "captured": board[to], "promotion": promotion, "flag": flag})
	else:
		moves.append({"from": from, "to": to, "piece": p, "captured": board[to], "promotion": "", "flag": flag})

func pseudo_moves() -> Array:
	var moves: Array = []
	for from in range(64):
		var p: String = board[from]
		if side(p) != turn:
			continue
		var role = p.to_lower()
		var fx = from % 8
		var fy = from / 8
		if role == "p":
			var dy = 1 if turn == "w" else -1
			var next = from + dy * 8
			if next >= 0 and next < 64 and board[next].is_empty():
				_add(moves, from, next)
				if fy == (1 if turn == "w" else 6) and board[from + dy * 16].is_empty():
					_add(moves, from, from + dy * 16, "double")
			for dx in [-1, 1]:
				var to = next + dx
				if fx + dx < 0 or fx + dx > 7 or to < 0 or to >= 64:
					continue
				if side(board[to]) == opposite(turn) and board[to].to_lower() != "k":
					_add(moves, from, to)
				elif to == ep:
					_add(moves, from, to, "ep")
		else:
			var directions: Array = KNIGHT if role == "n" else (DIAGONALS if role == "b" else (STRAIGHTS if role == "r" else DIAGONALS + STRAIGHTS))
			for delta in directions:
				var x = fx + delta.x
				var y = fy + delta.y
				while x >= 0 and x < 8 and y >= 0 and y < 8:
					var to = y * 8 + x
					if side(board[to]) == turn or board[to].to_lower() == "k":
						break
					_add(moves, from, to)
					if not board[to].is_empty() or role in ["n", "k"]:
						break
					x += delta.x
					y += delta.y
			if role == "k" and from == (4 if turn == "w" else 60) and not in_check():
				var enemy = opposite(turn)
				var short = "K" if turn == "w" else "k"
				var long = "Q" if turn == "w" else "q"
				if short in castling and board[from + 1].is_empty() and board[from + 2].is_empty() and not attacked(from + 1, enemy) and not attacked(from + 2, enemy):
					_add(moves, from, from + 2, "castle")
				if long in castling and board[from - 1].is_empty() and board[from - 2].is_empty() and board[from - 3].is_empty() and not attacked(from - 1, enemy) and not attacked(from - 2, enemy):
					_add(moves, from, from - 2, "castle")
	return moves

func _apply(m: Dictionary) -> void:
	var p: String = board[m.from]
	var color = side(p)
	board[m.from] = ""
	board[m.to] = (m.promotion.to_upper() if color == "w" else m.promotion) if not m.promotion.is_empty() else p
	if m.flag == "ep":
		board[m.to + (-8 if color == "w" else 8)] = ""
	if m.flag == "castle":
		var rook_from = m.from + (3 if m.to > m.from else -4)
		var rook_to = m.from + (1 if m.to > m.from else -1)
		board[rook_to] = board[rook_from]
		board[rook_from] = ""
	if p.to_lower() == "k":
		castling = castling.replace("K" if color == "w" else "k", "").replace("Q" if color == "w" else "q", "")
	for at in [m.from, m.to]:
		if at in [0, 7, 56, 63]:
			castling = castling.replace({0: "Q", 7: "K", 56: "q", 63: "k"}[at], "")
	ep = (m.from + m.to) / 2 if m.flag == "double" else -1
	halfmove = 0 if p.to_lower() == "p" or not m.captured.is_empty() or m.flag == "ep" else halfmove + 1
	fullmove += 1 if turn == "b" else 0
	turn = opposite(turn)

func legal_moves(from: int = -1) -> Array:
	var saved = _position()
	var color = turn
	var moves: Array = []
	for m in pseudo_moves():
		if from >= 0 and m.from != from:
			continue
		_apply(m)
		if not in_check(color):
			moves.append(m)
		_restore(saved)
	return moves

func perft(depth: int) -> int:
	if depth == 0:
		return 1
	var moves = legal_moves()
	if depth == 1:
		return moves.size()
	var saved = _position()
	var count = 0
	for m in moves:
		_apply(m)
		count += perft(depth - 1)
		_restore(saved)
	return count

func position_key() -> String:
	var fields = fen().split(" ")
	if ep >= 0:
		var available = false
		for m in legal_moves():
			if m.flag == "ep":
				available = true
		if not available:
			fields[3] = "-"
	return " ".join(fields.slice(0, 4))

func _san(m: Dictionary, legal: Array) -> String:
	if m.flag == "castle":
		return "O-O" if m.to > m.from else "O-O-O"
	var role: String = m.piece.to_lower()
	var text = "" if role == "p" else role.to_upper()
	if role != "p":
		var alternatives: Array = []
		for other in legal:
			if other.to == m.to and other.piece == m.piece and other.from != m.from:
				alternatives.append(other)
		if not alternatives.is_empty():
			var same_file = false
			var same_rank = false
			for other in alternatives:
				same_file = same_file or other.from % 8 == m.from % 8
				same_rank = same_rank or other.from / 8 == m.from / 8
			if not same_file:
				text += square(m.from)[0]
			elif not same_rank:
				text += square(m.from)[1]
			else:
				text += square(m.from)
	if not m.captured.is_empty() or m.flag == "ep":
		if role == "p":
			text += square(m.from)[0]
		text += "x"
	text += square(m.to)
	if not m.promotion.is_empty():
		text += "=" + m.promotion.to_upper()
	return text

func move(from: String, to: String, promotion: String = "q") -> Dictionary:
	if not result.is_empty():
		return {"ok": false, "error": "The game has ended."}
	var all = legal_moves()
	for m in all:
		if m.from == index(from) and m.to == index(to) and (m.promotion.is_empty() or m.promotion == promotion):
			var san = _san(m, all)
			positions.append(_position())
			_apply(m)
			if in_check():
				san += "#" if legal_moves().is_empty() else "+"
			history.append({"from": from, "to": to, "promotion": m.promotion, "san": san, "fen": fen(), "move": m.duplicate()})
			keys.append(position_key())
			_adjudicate()
			return {"ok": true, "san": san, "move": m}
	return {"ok": false, "error": "That move is not legal."}

func undo() -> bool:
	if positions.is_empty():
		return false
	_restore(positions.pop_back())
	history.pop_back()
	keys.pop_back()
	result = ""
	reason = ""
	_adjudicate()
	return true

func insufficient_material() -> bool:
	var minors: Array = []
	var bishop_colors: Array = []
	for at in range(64):
		var role: String = board[at].to_lower()
		if role in ["p", "r", "q"]:
			return false
		if role in ["n", "b"]:
			minors.append(role)
			if role == "b":
				bishop_colors.append((at % 8 + at / 8) % 2)
	if minors.size() <= 1:
		return true
	return minors.count("b") == minors.size() and (bishop_colors.count(0) == bishop_colors.size() or bishop_colors.count(1) == bishop_colors.size())

func can_mate(color: String) -> bool:
	# Timeout asks whether mate is possible by ANY legal series, not forceable.
	var own: Array = []
	var enemy: Array = []
	var bishop_colors: Array = []
	var has_pawn_or_knight = false
	for at in range(64):
		var piece: String = board[at]
		var role = piece.to_lower()
		if role in ["p", "n"]:
			has_pawn_or_knight = true
		if role == "b":
			bishop_colors.append((at % 8 + at / 8) % 2)
		if not piece.is_empty() and role != "k":
			(own if side(piece) == color else enemy).append(role)
	if own.is_empty():
		return false
	for role in ["p", "r", "q"]:
		if role in own:
			return true
	if "n" in own:
		if own.size() > 1:
			return true
		# A lone knight cannot mate a bare king or a king with only queens.
		for role in enemy:
			if role != "q":
				return true
		return false
	# Bishops confined to one color cannot mate without pawn/knight help;
	# heavy enemy pieces alone cannot supply a mating construction.
	return has_pawn_or_knight or (0 in bishop_colors and 1 in bishop_colors)

func claimable_draws(intended: Dictionary = {}) -> Array:
	if not result.is_empty():
		return []
	var claims: Array = []
	var half = halfmove
	var repetitions = keys.count(position_key())
	if not intended.is_empty():
		var selected: Dictionary = {}
		for m in legal_moves():
			if square(m.from) == intended.get("from", "") and square(m.to) == intended.get("to", "") and (m.promotion.is_empty() or m.promotion == intended.get("promotion", "q")):
				selected = m
		if selected.is_empty():
			return []
		var saved = _position()
		_apply(selected)
		half = halfmove
		repetitions = keys.count(position_key()) + 1
		_restore(saved)
	if half >= 100:
		claims.append("Fifty-move rule")
	if repetitions >= 3:
		claims.append("Threefold repetition")
	return claims

func claim_draw(kind: String, intended: Dictionary = {}) -> bool:
	if kind not in claimable_draws(intended):
		return false
	result = "1/2-1/2"
	reason = kind
	return true

func _adjudicate() -> void:
	if legal_moves().is_empty():
		reason = "Checkmate" if in_check() else "Stalemate"
		result = ("0-1" if turn == "w" else "1-0") if in_check() else "1/2-1/2"
	elif insufficient_material():
		result = "1/2-1/2"
		reason = "Insufficient material"
	elif halfmove >= 150:
		result = "1/2-1/2"
		reason = "Seventy-five-move rule"
	elif keys.count(position_key()) >= 5:
		result = "1/2-1/2"
		reason = "Fivefold repetition"

func pgn() -> String:
	var text = '[Event "Peepeechess Classic"]\n[Result "%s"]\n' % (result if not result.is_empty() else "*")
	if initial_fen != START_FEN:
		text += '[SetUp "1"]\n[FEN "%s"]\n' % initial_fen
	text += "\n"
	var fields = initial_fen.split(" ")
	var number = int(fields[5])
	var color = fields[1]
	for i in range(history.size()):
		if color == "w":
			text += str(number) + ". "
		elif i == 0:
			text += str(number) + "... "
		text += history[i].san + " "
		if color == "b":
			number += 1
		color = opposite(color)
	return text + (result if not result.is_empty() else "*")
