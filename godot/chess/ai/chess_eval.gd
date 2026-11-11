class_name ChessEval
extends RefCounted
## Static evaluation: tapered material + piece-square tables (generated from simple formulas, not copied
## from any engine) plus pawn structure, bishop pair, rook files, king shelter and a mop-up term.
## Scores are centipawns from White's point of view; `for_side_to_move` flips them.
const INDEX = {"P": 0, "N": 1, "B": 2, "R": 3, "Q": 4, "K": 5, "p": 6, "n": 7, "b": 8, "r": 9, "q": 10, "k": 11}
const MATERIAL = [100, 320, 330, 500, 950, 0]
const PHASE_WEIGHT = [0, 1, 1, 2, 4, 0]
const PAWN_RANK_MG = [0, 0, 4, 10, 20, 36, 55, 0]
const PAWN_RANK_EG = [0, 0, 8, 18, 38, 68, 110, 0]
const PASSED = [0, 5, 10, 20, 40, 70, 110, 0]
static var table_mg := PackedInt32Array()
static var table_eg := PackedInt32Array()
static var phase_of := PackedInt32Array()
static var _built = false

static func _centrality(file: int, rank: int) -> int:
	# 0 (corner) .. 6 (centre) in half-squares.
	return 7 - (absi(2 * file - 7) + absi(2 * rank - 7)) / 2

static func _piece_square(role: int, file: int, rank: int, endgame: bool) -> int:
	var c = _centrality(file, rank)
	match role:
		0:
			var bonus = PAWN_RANK_EG[rank] if endgame else PAWN_RANK_MG[rank]
			if not endgame and rank <= 4:
				bonus += [-6, -2, 4, 10, 10, 4, -2, -6][file] * (1 if rank < 4 else 2)
			return bonus
		1:
			return 7 * c - 24 - (8 if rank == 0 else 0)
		2:
			return 4 * c - 12 - (6 if rank == 0 else 0)
		3:
			var v = (3 if file in [3, 4] else 0) + (14 if rank == 6 and not endgame else 0)
			return v
		4:
			return 2 * c - 6 - (6 if rank == 0 and file != 3 else 0)
		_:
			if endgame:
				return 9 * c - 24
			var shelter = 0
			if rank == 0:
				shelter = 34 if file in [1, 6] else (18 if file in [2, 7] else (-6 if file in [3, 4] else 0))
			return shelter - 14 * rank

static func ensure() -> void:
	if _built:
		return
	table_mg.resize(768)
	table_eg.resize(768)
	phase_of.resize(12)
	for piece in range(12):
		var role = piece % 6
		var sign = 1 if piece < 6 else -1
		phase_of[piece] = PHASE_WEIGHT[role]
		for sq in range(64):
			var file = sq % 8
			var rank = sq / 8
			# Black squares are mirrored vertically so the same table serves both colours.
			var table_rank = rank if sign == 1 else 7 - rank
			table_mg[piece * 64 + sq] = sign * (MATERIAL[role] + _piece_square(role, file, table_rank, false))
			table_eg[piece * 64 + sq] = sign * (MATERIAL[role] + _piece_square(role, file, table_rank, true))
	_built = true

static func evaluate(board: Array, turn: String, fight: bool = false) -> int:
	var mg = 0
	var eg = 0
	var phase = 0
	var white_pawns = PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0])
	var black_pawns = PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0])
	var white_front = PackedInt32Array([-1, -1, -1, -1, -1, -1, -1, -1])  # highest white pawn rank per file
	var black_front = PackedInt32Array([8, 8, 8, 8, 8, 8, 8, 8])         # lowest black pawn rank per file
	var white_min_pawn = PackedInt32Array([8, 8, 8, 8, 8, 8, 8, 8])
	var black_max_pawn = PackedInt32Array([-1, -1, -1, -1, -1, -1, -1, -1])
	var white_bishops = 0
	var black_bishops = 0
	var white_rooks: Array = []
	var black_rooks: Array = []
	var white_king = -1
	var black_king = -1
	var white_material = 0
	var black_material = 0
	for sq in range(64):
		var p: String = board[sq]
		if p == "":
			continue
		var idx: int = INDEX[p]
		mg += table_mg[idx * 64 + sq]
		eg += table_eg[idx * 64 + sq]
		phase += phase_of[idx]
		var file = sq % 8
		var rank = sq / 8
		match idx:
			0:
				white_pawns[file] += 1
				white_material += 100
				if rank > white_front[file]:
					white_front[file] = rank
				if rank < white_min_pawn[file]:
					white_min_pawn[file] = rank
			6:
				black_pawns[file] += 1
				black_material += 100
				if rank < black_front[file]:
					black_front[file] = rank
				if rank > black_max_pawn[file]:
					black_max_pawn[file] = rank
			1, 2:
				white_material += MATERIAL[idx]
				if idx == 2:
					white_bishops += 1
			7, 8:
				black_material += MATERIAL[idx - 6]
				if idx == 8:
					black_bishops += 1
			3:
				white_material += 500
				white_rooks.append(sq)
			9:
				black_material += 500
				black_rooks.append(sq)
			4:
				white_material += 950
			10:
				black_material += 950
			5:
				white_king = sq
			11:
				black_king = sq
	if phase > 24:
		phase = 24
	# Pawn structure (both colours, in centipawns that apply in all phases).
	var structure = 0
	for file in range(8):
		var wn = white_pawns[file]
		var bn = black_pawns[file]
		if wn > 1:
			structure -= 11 * (wn - 1)
		if bn > 1:
			structure += 11 * (bn - 1)
		if wn > 0:
			var left = white_pawns[file - 1] if file > 0 else 0
			var right = white_pawns[file + 1] if file < 7 else 0
			if left + right == 0:
				structure -= 9 * wn
			# Passed: no black pawn on this or an adjacent file at a higher rank.
			var blocked = false
			for f in range(maxi(0, file - 1), mini(7, file + 1) + 1):
				if black_max_pawn[f] > white_front[file]:
					blocked = true
					break
			if not blocked:
				structure += PASSED[white_front[file]]
		if bn > 0:
			var left_b = black_pawns[file - 1] if file > 0 else 0
			var right_b = black_pawns[file + 1] if file < 7 else 0
			if left_b + right_b == 0:
				structure += 9 * bn
			var blocked_b = false
			for f in range(maxi(0, file - 1), mini(7, file + 1) + 1):
				if white_min_pawn[f] < black_front[file]:
					blocked_b = true
					break
			if not blocked_b:
				structure -= PASSED[7 - black_front[file]]
	if white_bishops >= 2:
		structure += 28
	if black_bishops >= 2:
		structure -= 28
	for sq in white_rooks:
		var f = sq % 8
		if white_pawns[f] == 0:
			structure += 22 if black_pawns[f] == 0 else 11
	for sq in black_rooks:
		var f = sq % 8
		if black_pawns[f] == 0:
			structure -= 22 if white_pawns[f] == 0 else 11
	# King pawn shelter (middlegame only, scaled by phase below).
	var shelter = 0
	if white_king >= 0 and white_king / 8 <= 1:
		var kf = white_king % 8
		for f in range(maxi(0, kf - 1), mini(7, kf + 1) + 1):
			if white_pawns[f] == 0:
				shelter -= 14
			elif white_min_pawn[f] > 2:
				shelter -= 6
	if black_king >= 0 and black_king / 8 >= 6:
		var kb = black_king % 8
		for f in range(maxi(0, kb - 1), mini(7, kb + 1) + 1):
			if black_pawns[f] == 0:
				shelter += 14
			elif black_max_pawn[f] < 5:
				shelter += 6
	var score = (mg * phase + eg * (24 - phase)) / 24
	score += structure + (shelter * phase) / 24
	# Mop-up: drive a bare king to the edge when far ahead in material.
	if white_king >= 0 and black_king >= 0:
		var lead = white_material - black_material
		var weaker = black_material if lead > 0 else white_material
		if absi(lead) >= 300 and weaker <= 330:
			var winner_king = white_king if lead > 0 else black_king
			var loser_king = black_king if lead > 0 else white_king
			var edge = 6 - _centrality(loser_king % 8, loser_king / 8)
			var gap = absi(winner_king % 8 - loser_king % 8) + absi(winner_king / 8 - loser_king / 8)
			var bonus = ((edge * 9 + (14 - gap) * 4) * (24 - phase)) / 24
			score += bonus if lead > 0 else -bonus
	if fight:
		# Battle Chess: swap orthodox material for duel strength (see ChessBattleModel.FIGHT_VALUE).
		score += _fight_adjustment(board)
	return score + (8 if turn == "w" else -8)

static func _fight_adjustment(board: Array) -> int:
	var delta = 0
	for sq in range(64):
		var p: String = board[sq]
		if p == "" or p == "P" or p == "p" or p == "K" or p == "k":
			continue
		var role = p.to_lower()
		var orthodox: int = MATERIAL[["p", "n", "b", "r", "q", "k"].find(role)]
		var fighter: int = ChessBattleModel.FIGHT_VALUE[role]
		if p == p.to_upper():
			delta += fighter - orthodox
		else:
			delta -= fighter - orthodox
	return delta

static func for_side_to_move(score: int, turn: String) -> int:
	return score if turn == "w" else -score
