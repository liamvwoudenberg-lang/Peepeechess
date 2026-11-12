class_name ChessSearch
extends RefCounted
## Alpha-beta search over the repository's own rules engine (ClassicChess / BattleChessRules).
##
## The search never re-implements rules: pseudo-legal moves come from `pseudo_moves()`, moves are made with
## the engine's `_apply()` and undone with `_restore()`, legality is `in_check()` after the move (exactly how
## `legal_moves()` filters), and the root move list is the engine's own `legal_moves()`, so Battle Chess
## capture restrictions come from BattleChessRules. Techniques: iterative deepening, principal-variation
## search, Zobrist transposition table, MVV-LVA / killer / history move ordering, null-move pruning, late
## move reductions, futility and reverse-futility pruning, check extensions, quiescence search with delta
## and bad-capture pruning, repetition / fifty-move / insufficient-material draw scores, mate distance scores.
##
## Battle Chess: a capture is a chance node (see ChessBattleModel). The attacker-wins branch is searched
## normally; the defender-wins branch (attacker removed, defender stays, turn passes) is evaluated statically.
##
## A search can be run in one go (`run`) or sliced across frames (`begin` + repeated `step`). It touches only
## its own engine clone, so it is safe to run on a worker thread; `request_stop()` may be called from any thread.
const MATE = 30000
const INF = 32000
const MAX_PLY = 64
const TT_SIZE = 1 << 16
const PIECE_ORDER = {"P": 1, "N": 3, "B": 3, "R": 5, "Q": 9, "K": 20, "p": 1, "n": 3, "b": 3, "r": 5, "q": 9, "k": 20, "": 0}
const PIECE_CP = {"P": 100, "N": 320, "B": 330, "R": 500, "Q": 950, "K": 0, "p": 100, "n": 320, "b": 330, "r": 500, "q": 950, "k": 0, "": 0}
const PROMO_INDEX = {"": 0, "q": 1, "r": 2, "b": 3, "n": 4}
var engine
var battle = false
var tt_keys := PackedInt64Array()
var tt_data := PackedInt64Array()
var killers := PackedInt32Array()
var history := PackedInt32Array()
var path := PackedInt64Array()
var game_hashes: Dictionary = {}
var nodes = 0
var node_limit = 0
var deadline_us = 0
var slice_limit_us = 0
var stopped = false
var slice_hit = false
var max_depth = 4
var max_qply = 6
var root_margin = 0
var noise = 0
var blunder = 0.0
var promotion_slack = 60
var rng = RandomNumberGenerator.new()
var _stop_flag = false
var _mutex = Mutex.new()
var _root_moves: Array = []
var _root_scores: Dictionary = {}
var _iter_scores: Dictionary = {}
var _iter_best = {}
var _best_move: Dictionary = {}
var _best_score = 0
var _depth_done = 0
var _next_depth = 1
var _finished = false
var _start_us = 0
var _pv_text = ""
var _root_depth = 1

func _init() -> void:
	ChessZobrist.ensure()
	ChessEval.ensure()
	ChessBattleModel.ensure()
	tt_keys.resize(TT_SIZE)
	tt_data.resize(TT_SIZE)
	killers.resize(MAX_PLY * 2)
	history.resize(2 * 4096)
	path.resize(MAX_PLY + 8)

func clear_tables() -> void:
	tt_keys.fill(0)
	tt_data.fill(0)
	killers.fill(0)
	history.fill(0)

func request_stop() -> void:
	_mutex.lock()
	_stop_flag = true
	_mutex.unlock()

func _stop_requested() -> bool:
	_mutex.lock()
	var value = _stop_flag
	_mutex.unlock()
	return value

# ---- helpers ---------------------------------------------------------------------------------

static func encode(m: Dictionary) -> int:
	return m.from | (m.to << 6) | (PROMO_INDEX[m.promotion] << 12)

func _check_limits() -> void:
	if _stop_requested():
		stopped = true
		return
	if node_limit > 0 and nodes >= node_limit:
		stopped = true
		return
	var now = Time.get_ticks_usec()
	if deadline_us > 0 and now >= deadline_us:
		stopped = true
		return
	if slice_limit_us > 0 and now >= slice_limit_us:
		slice_hit = true
		stopped = true

func _eval_stm() -> int:
	var score = ChessEval.evaluate(engine.board, engine.turn, battle)
	return score if engine.turn == "w" else -score

static func _to_tt(score: int, ply: int) -> int:
	if score >= MATE - MAX_PLY:
		return score + ply
	if score <= -MATE + MAX_PLY:
		return score - ply
	return score

static func _from_tt(score: int, ply: int) -> int:
	if score >= MATE - MAX_PLY:
		return score - ply
	if score <= -MATE + MAX_PLY:
		return score + ply
	return score

func _repeated(h: int, ply: int) -> bool:
	var i = ply - 2
	var floor_ply = maxi(0, ply - engine.halfmove)
	while i >= floor_ply:
		if path[i] == h:
			return true
		i -= 2
	return game_hashes.has(h)

func _has_pieces(color: String) -> bool:
	var b: Array = engine.board
	if color == "w":
		return b.has("N") or b.has("B") or b.has("R") or b.has("Q")
	return b.has("n") or b.has("b") or b.has("r") or b.has("q")

func _is_capture(m: Dictionary) -> bool:
	return m.captured != "" or m.flag == "ep"

func _victim_role(m: Dictionary) -> String:
	return "p" if m.captured == "" else m.captured.to_lower()

func _order_score(m: Dictionary, tt_move: int, ply: int, side_index: int) -> int:
	var enc = encode(m)
	if enc == tt_move:
		return 1000000
	if m.captured != "" or m.flag == "ep":
		var victim = PIECE_ORDER[m.captured] if m.captured != "" else 1
		return 200000 + 100 * victim - PIECE_ORDER[m.piece]
	if m.promotion == "q":
		return 190000
	if m.promotion != "":
		return -1000
	if enc == killers[ply * 2]:
		return 90000
	if enc == killers[ply * 2 + 1]:
		return 80000
	return history[side_index * 4096 + m.from * 64 + m.to]

## Probability-weighted child value for a Battle capture; plain negamax otherwise.
func _child(depth: int, alpha: int, beta: int, ply: int, p: float, lose: int) -> int:
	if p < 0.0:
		return -negamax(depth, -beta, -alpha, ply + 1, true)
	var q = 1.0 - p
	var lo = clampi(int(floor((alpha - q * lose) / p)) - 1, -INF, INF)
	var hi = clampi(int(ceil((beta - q * lose) / p)) + 1, -INF, INF)
	var win_value = -negamax(depth, -hi, -lo, ply + 1, true)
	return int(p * win_value + q * lose)

# ---- main search -----------------------------------------------------------------------------

func negamax(depth: int, alpha: int, beta: int, ply: int, allow_null: bool) -> int:
	nodes += 1
	if (nodes & 63) == 0:
		_check_limits()
	if stopped:
		return 0
	var e = engine
	var turn: String = e.turn
	var h = ChessZobrist.hash_position(e.board, turn, e.castling, e.ep)
	path[ply] = h
	if ply > 0:
		if e.halfmove >= 100 or _repeated(h, ply):
			return 0
		if e.board.count("") >= 58 and e.insufficient_material():
			return 0
	var in_chk: bool = e.in_check(turn)
	if in_chk and ply < _root_depth * 2 + 2 and ply < MAX_PLY - 10:
		depth += 1
	if depth <= 0 or ply >= MAX_PLY - 4:
		return _quiesce(alpha, beta, ply, 0)
	var pv_node = beta - alpha > 1
	var tt_move = 0
	var idx = h & (TT_SIZE - 1)
	if tt_keys[idx] == h:
		var d = tt_data[idx]
		tt_move = (d >> 26) & 0x7FFF
		var tt_depth = (d >> 16) & 0xFF
		if tt_depth >= depth and not pv_node and ply > 0:
			var tt_score = _from_tt((d & 0xFFFF) - 32768, ply)
			var flag = (d >> 24) & 3
			if flag == 0 or (flag == 1 and tt_score >= beta) or (flag == 2 and tt_score <= alpha):
				return tt_score
	var static_eval = 0
	if not in_chk:
		static_eval = _eval_stm()
		if not pv_node and depth <= 3 and absi(beta) < MATE - 200 and static_eval - 95 * depth >= beta:
			return static_eval - 95 * depth
	var saved = e._position()
	if allow_null and not pv_node and not in_chk and depth >= 3 and static_eval >= beta and _has_pieces(turn):
		e.turn = "b" if turn == "w" else "w"
		e.ep = -1
		var reduction = 2 + (1 if depth >= 6 else 0)
		var null_score = -negamax(depth - 1 - reduction, -beta, -beta + 1, ply + 1, false)
		e._restore(saved)
		if stopped:
			return 0
		if null_score >= beta:
			return beta if null_score >= MATE - MAX_PLY else null_score
	var moves: Array = e.pseudo_moves()
	var count = moves.size()
	var scores := PackedInt32Array()
	scores.resize(count)
	var side_index = 0 if turn == "w" else 1
	for i in range(count):
		scores[i] = _order_score(moves[i], tt_move, ply, side_index)
	var alpha_start = alpha
	var best = -INF
	var best_enc = 0
	var legal = 0
	for i in range(count):
		var pick = i
		var top = scores[i]
		for k in range(i + 1, count):
			if scores[k] > top:
				top = scores[k]
				pick = k
		if pick != i:
			var swap_move = moves[pick]
			moves[pick] = moves[i]
			moves[i] = swap_move
			scores[pick] = scores[i]
			scores[i] = top
		var m: Dictionary = moves[i]
		var promotion: String = m.promotion
		if promotion == "r" or promotion == "b":
			continue
		var capture = m.captured != "" or m.flag == "ep"
		var chance_p = -1.0
		var lose = 0
		if battle and capture:
			if e.capture_restriction(m) != "":
				continue
			chance_p = ChessBattleModel.win_probability(m.piece.to_lower(), _victim_role(m))
			e._apply_defender_win(m)
			lose = -_eval_stm()
			e._restore(saved)
		e._apply(m)
		if e.in_check(turn):
			e._restore(saved)
			continue
		legal += 1
		var quiet = not capture and promotion == ""
		if quiet and depth <= 2 and not in_chk and legal > 1 and not pv_node and absi(alpha) < MATE - 200 and static_eval + 110 * depth + 40 <= alpha:
			if not e.in_check(e.turn):
				e._restore(saved)
				continue
		var score = 0
		var new_depth = depth - 1
		if legal == 1:
			score = _child(new_depth, alpha, beta, ply, chance_p, lose)
		else:
			var reduce = 0
			if depth >= 3 and quiet and not in_chk and legal > 4:
				reduce = 1 + (1 if legal > 10 and depth >= 5 else 0)
			score = _child(new_depth - reduce, alpha, alpha + 1, ply, chance_p, lose)
			if score > alpha and (reduce > 0 or score < beta) and not stopped:
				score = _child(new_depth, alpha, beta, ply, chance_p, lose)
		e._restore(saved)
		if stopped:
			return 0
		if score > best:
			best = score
			best_enc = encode(m)
			if score > alpha:
				alpha = score
				if alpha >= beta:
					if quiet:
						var enc = best_enc
						if killers[ply * 2] != enc:
							killers[ply * 2 + 1] = killers[ply * 2]
							killers[ply * 2] = enc
						var slot = side_index * 4096 + m.from * 64 + m.to
						history[slot] = mini(history[slot] + depth * depth, 60000)
					break
	if legal == 0:
		return -MATE + ply if in_chk else 0
	var flag_out = 2
	if best >= beta:
		flag_out = 1
	elif best > alpha_start:
		flag_out = 0
	tt_keys[idx] = h
	tt_data[idx] = (_to_tt(best, ply) + 32768) | (depth << 16) | (flag_out << 24) | (best_enc << 26)
	return best

func _quiesce(alpha: int, beta: int, ply: int, qd: int) -> int:
	nodes += 1
	if (nodes & 63) == 0:
		_check_limits()
	if stopped:
		return 0
	var e = engine
	var turn: String = e.turn
	var stand = _eval_stm()
	if ply >= MAX_PLY - 2 or battle:
		return stand  # Battle captures are duels: they are searched as chance nodes in negamax(), not here.
	var in_chk: bool = e.in_check(turn)
	if not in_chk:
		if stand >= beta:
			return stand
		if stand > alpha:
			alpha = stand
		if qd >= max_qply:
			return stand
	elif qd >= max_qply + 2:
		return stand
	var moves: Array = e.pseudo_moves()
	var list: Array = []
	var order := PackedInt32Array()
	var enemy = "b" if turn == "w" else "w"
	for m in moves:
		var capture = m.captured != "" or m.flag == "ep"
		var promotion: String = m.promotion
		if promotion != "" and promotion != "q":
			continue
		if not in_chk:
			if not capture and promotion == "":
				continue
			if promotion == "" and capture:
				var victim_cp = PIECE_CP[m.captured] if m.captured != "" else 100
				if stand + victim_cp + 180 < alpha:
					continue
				if m.captured != "" and PIECE_ORDER[m.piece] > PIECE_ORDER[m.captured] and e.attacked(m.to, enemy):
					continue
		list.append(m)
		var victim = PIECE_ORDER[m.captured] if m.captured != "" else (1 if m.flag == "ep" else 0)
		order.append(100 * victim - PIECE_ORDER[m.piece] + (900 if promotion == "q" else 0))
	var saved = e._position()
	var legal = 0
	var count = list.size()
	for i in range(count):
		var pick = i
		var top = order[i]
		for k in range(i + 1, count):
			if order[k] > top:
				top = order[k]
				pick = k
		if pick != i:
			var tmp = list[pick]
			list[pick] = list[i]
			list[i] = tmp
			order[pick] = order[i]
			order[i] = top
		e._apply(list[i])
		if e.in_check(turn):
			e._restore(saved)
			continue
		legal += 1
		var score = -_quiesce(-beta, -alpha, ply + 1, qd + 1)
		e._restore(saved)
		if stopped:
			return 0
		if score > alpha:
			alpha = score
			if alpha >= beta:
				return alpha
	if in_chk and legal == 0:
		return -MATE + ply
	return alpha

# ---- iterative deepening driver --------------------------------------------------------------

## Prepare a search of `source_engine`'s position. `config`: max_depth, node_limit, time_ms, q_ply,
## margin, noise, blunder, seed, history_hashes (Array of position hashes already seen in the game).
func begin(source_engine, config: Dictionary) -> void:
	engine = source_engine
	battle = engine.has_method("capture_restriction")
	max_depth = int(config.get("max_depth", 4))
	max_qply = int(config.get("q_ply", 6))
	node_limit = int(config.get("node_limit", 0))
	root_margin = int(config.get("margin", 0))
	noise = int(config.get("noise", 0))
	blunder = float(config.get("blunder", 0.0))
	promotion_slack = int(config.get("promotion_slack", 60))
	rng.seed = int(config.get("seed", 1))
	game_hashes.clear()
	for value in config.get("history_hashes", []):
		game_hashes[value] = true
	_start_us = Time.get_ticks_usec()
	var time_ms = int(config.get("time_ms", 0))
	deadline_us = _start_us + time_ms * 1000 if time_ms > 0 else 0
	slice_limit_us = 0
	nodes = 0
	stopped = false
	slice_hit = false
	_stop_flag = false
	_finished = false
	_next_depth = 1
	_depth_done = 0
	_best_move = {}
	_best_score = 0
	_root_scores.clear()
	_pv_text = ""
	_root_moves.clear()
	killers.fill(0)
	# Authoritative root move list: the rules engine's own legal moves (Battle Chess restrictions included).
	for m in engine.legal_moves():
		if m.promotion in ["", "q", "n"]:
			_root_moves.append(m)
	if _root_moves.is_empty():
		_finished = true
	elif _root_moves.size() == 1:
		_best_move = _root_moves[0]
		_finished = true

func is_finished() -> bool:
	return _finished

## Advance the search. `slice_us` > 0 bounds this call (frame slicing); 0 runs to completion.
func step(slice_us: int = 0) -> bool:
	if _finished:
		return true
	var slice_end = Time.get_ticks_usec() + slice_us if slice_us > 0 else 0
	while not _finished:
		slice_limit_us = slice_end
		slice_hit = false
		var completed = _iterate(_next_depth)
		if stopped and not slice_hit:
			_finished = true  # hard limit: time, nodes or cancellation
			break
		if stopped and slice_hit:
			stopped = false
			slice_hit = false
			slice_limit_us = 0
			return false  # resume next frame; the transposition table keeps finished work
		if completed:
			_depth_done = _next_depth
			_next_depth += 1
			if _next_depth > max_depth or absi(_best_score) >= MATE - 200:
				_finished = true
				break
		if slice_end > 0 and Time.get_ticks_usec() >= slice_end:
			slice_limit_us = 0
			return false
	slice_limit_us = 0
	return true

func run(source_engine, config: Dictionary) -> Dictionary:
	begin(source_engine, config)
	while not step(0):
		pass
	return result()

func _sort_root() -> void:
	var order: Array = []
	for m in _root_moves:
		var enc = encode(m)
		order.append([_root_scores.get(enc, -INF - 1), _order_score(m, encode(_best_move) if not _best_move.is_empty() else 0, 0, 0 if engine.turn == "w" else 1), m])
	order.sort_custom(func(a, b): return a[0] > b[0] or (a[0] == b[0] and a[1] > b[1]))
	_root_moves.clear()
	for entry in order:
		_root_moves.append(entry[2])

## One full-width iteration at `depth`. Returns true when every root move was searched.
func _iterate(depth: int) -> bool:
	_root_depth = depth
	_sort_root()
	var e = engine
	var turn: String = e.turn
	var saved = e._position()
	var best = -INF
	var best_move: Dictionary = {}
	var iter_scores: Dictionary = {}
	var first = true
	var side_index = 0 if turn == "w" else 1
	path[0] = ChessZobrist.hash_position(e.board, turn, e.castling, e.ep)
	for m in _root_moves:
		var capture = _is_capture(m)
		var chance_p = -1.0
		var lose = 0
		if battle and capture:
			chance_p = ChessBattleModel.win_probability(m.piece.to_lower(), _victim_role(m))
			e._apply_defender_win(m)
			lose = -_eval_stm()
			e._restore(saved)
		e._apply(m)
		var score = 0
		if first:
			score = _child(depth - 1, -INF, INF, 0, chance_p, lose)
		elif root_margin > 0:
			# Candidate scoring: exact values for moves within `root_margin` of the best, cheap fail-low otherwise.
			var low = maxi(-INF, best - root_margin - 1)
			score = _child(depth - 1, low, INF, 0, chance_p, lose)
		else:
			score = _child(depth - 1, best, best + 1, 0, chance_p, lose)
			if score > best and not stopped:
				score = _child(depth - 1, best, INF, 0, chance_p, lose)
		e._restore(saved)
		if stopped:
			break
		iter_scores[encode(m)] = score
		if score > best or first:
			best = score
			best_move = m
		first = false
	if stopped and not slice_hit and not iter_scores.is_empty():
		# Hard stop mid-iteration: moves finished so far are exact, keep them (the previous best was searched first).
		_merge_iteration(iter_scores, best, best_move, depth)
		return false
	if stopped:
		return false
	_merge_iteration(iter_scores, best, best_move, depth)
	return true

func _merge_iteration(iter_scores: Dictionary, best: int, best_move: Dictionary, _depth: int) -> void:
	for enc in iter_scores:
		_root_scores[enc] = iter_scores[enc]
	if not best_move.is_empty():
		_best_move = best_move
		_best_score = best

func result() -> Dictionary:
	var elapsed = (Time.get_ticks_usec() - _start_us) / 1000.0
	if _root_moves.is_empty():
		return {"ok": false, "error": "No legal moves.", "nodes": nodes, "elapsed_ms": elapsed}
	var chosen: Dictionary = _best_move
	if chosen.is_empty():
		chosen = _root_moves[0]
	var chosen_score = _best_score
	if _root_moves.size() > 1 and (noise > 0 or blunder > 0.0) and not _root_scores.is_empty():
		var candidates: Array = []
		var best_score = -INF
		for m in _root_moves:
			best_score = maxi(best_score, _root_scores.get(encode(m), -INF - 1))
		var window = root_margin
		for m in _root_moves:
			var s = _root_scores.get(encode(m), -INF - 1)
			if s > -INF and s >= best_score - window:
				candidates.append([s, m])
		if candidates.size() > 1:
			if blunder > 0.0 and rng.randf() < blunder:
				var pick = candidates[rng.randi_range(0, candidates.size() - 1)]
				chosen = pick[1]
				chosen_score = pick[0]
			elif noise > 0:
				var top = -INF * 4
				for c in candidates:
					var noisy = c[0] + rng.randi_range(-noise, noise)
					if noisy > top:
						top = noisy
						chosen = c[1]
						chosen_score = c[0]
	# Under-promotion only when it clearly beats the queen (mate, stalemate avoidance, a fork).
	if chosen.promotion == "n":
		for m in _root_moves:
			if m.from == chosen.from and m.to == chosen.to and m.promotion == "q":
				var queen_score = _root_scores.get(encode(m), -INF - 1)
				if queen_score + promotion_slack > _root_scores.get(encode(chosen), chosen_score):
					chosen = m
					chosen_score = queen_score
	return {"ok": true, "move": chosen, "from": ClassicChess.square(chosen.from), "to": ClassicChess.square(chosen.to), "promotion": chosen.promotion, "score": chosen_score, "depth": _depth_done, "nodes": nodes, "elapsed_ms": elapsed, "mate": absi(_best_score) >= MATE - 200, "legal_count": _root_moves.size()}
