class_name BattleMeta
extends RefCounted
## The board-level half of the fairness pass ("chess decisions set up duels, duels reshape the board"). Pure rules, no nodes, no timing:
## it reads the chess position and the finished duel's summary and keeps the state that outlives one duel.
##
##   * persistent damage: a piece keeps its HP fraction after a duel (floored so it is never useless) and heals slowly each turn of its
##     side, faster on its rest ranks;
##   * support / position: a piece defended by a friend takes less damage, an isolated one more, a flanked one a little more; holding
##     most of the centre gives a small stamina-regen perk;
##   * Resolve: earned through chess play (protecting pieces, holding squares, giving check, holding the line) and through duels
##     (the simulation's own gains), spent inside duels (second wind, overcharge, extra dodge). Carried into a duel up to a cap;
##   * comeback: the side behind on material gets a little extra Resolve and takes a little less damage;
##   * decisive win: a duel won with most of the HP left heals the winner and grants Resolve (the "initiative" bonus).
##
## Every number is in balance_v1.json `meta` (BalanceData.meta()); nothing here is a magic number. All output is deterministic.
const Balance := preload("res://combat/data/balance_data.gd")
const ChessEngine := preload("res://chess/chess_engine.gd")

var hp: Dictionary = {}              # pieceId -> HP fraction 0..1 (absent = full)
var resolve: Dictionary = {"w": 0.0, "b": 0.0}
var notes: Array[String] = []          # newest last; the match chronicle / debug overlay show it
const LOG_CAP := 40


func reset() -> void:
	hp.clear()
	var start := float(Balance.meta().get("resolve", {}).get("start", 0.0))
	resolve = {"w": start, "b": start}
	notes.clear()


func _cfg(section: String) -> Dictionary:
	return Balance.meta().get(section, {})


func _note(line: String) -> void:
	notes.append(line)
	while notes.size() > LOG_CAP:
		notes.pop_front()


# ---- persistent damage -------------------------------------------------------------------------------------------
## HP fraction a piece enters its next duel with (never below the floor: a wounded piece is weaker, not useless).
func start_fraction(piece_id: String) -> float:
	return maxf(float(_cfg("persistence").get("min_start_hp_frac", 0.0)), float(hp.get(piece_id, 1.0)))


func start_hp(piece_id: String, max_hp: int) -> int:
	return clampi(roundi(start_fraction(piece_id) * float(max_hp)), 1, max_hp)


# ---- position reading --------------------------------------------------------------------------------------------
static func material(board: Array, color: String) -> int:
	var values: Dictionary = Balance.meta().get("material", {})
	var total := 0
	for piece in board:
		if not String(piece).is_empty() and ChessEngine.side(piece) == color:
			total += int(values.get(String(piece).to_lower(), 0))
	return total


## Material the side is behind by (0 when level or ahead).
func deficit(board: Array, color: String) -> int:
	return maxi(0, material(board, "w" if color == "b" else "b") - material(board, color))


func is_behind(board: Array, color: String) -> bool:
	return deficit(board, color) >= int(_cfg("comeback").get("material_gap", 99))


## Number of key squares (centre) the side holds: occupied by it or attacked by it.
func key_control(engine, color: String) -> int:
	var count := 0
	for name in _cfg("key_squares").get("squares", []):
		var at: int = ChessEngine.index(String(name))
		if at >= 0 and (ChessEngine.side(engine.board[at]) == color or engine.attacked(at, color)):
			count += 1
	return count


## A friend defends the piece on `at` (a friendly piece other than the one standing there attacks the square). `ignore` is a square whose
## piece is treated as absent (the attacker that is about to leave its square).
func defended(engine, at: int, color: String, ignore: int = -1) -> bool:
	var saved := ""
	if ignore >= 0:
		saved = engine.board[ignore]
		engine.board[ignore] = ""
	var result: bool = engine.attacked(at, color)
	if ignore >= 0:
		engine.board[ignore] = saved
	return result


func isolated(engine, at: int, color: String) -> bool:
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var x: int = at % 8 + dx
			var y: int = at / 8 + dy
			if x >= 0 and x < 8 and y >= 0 and y < 8 and ChessEngine.side(engine.board[y * 8 + x]) == color:
				return false
	return true


## Enemy pieces on two opposite neighbouring squares (left/right, above/below or diagonally opposite).
func flanked(engine, at: int, color: String) -> bool:
	var enemy := "b" if color == "w" else "w"
	for pair in [[Vector2i(-1, 0), Vector2i(1, 0)], [Vector2i(0, -1), Vector2i(0, 1)], [Vector2i(-1, -1), Vector2i(1, 1)], [Vector2i(-1, 1), Vector2i(1, -1)]]:
		var both := true
		for delta in pair:
			var x: int = at % 8 + delta.x
			var y: int = at / 8 + delta.y
			both = both and x >= 0 and x < 8 and y >= 0 and y < 8 and ChessEngine.side(engine.board[y * 8 + x]) == enemy
		if both:
			return true
	return false


# ---- duel start --------------------------------------------------------------------------------------------------
## The "seat_start" start option of CombatSimulation for the pending duel (see _apply_duel_rules): persistent HP, Resolve carried in, and the
## damage-taken / regen modifiers from support, isolation, flanking, key squares and the comeback. `from_at` is the attacker's square.
func seat_options(engine, request: Dictionary) -> Dictionary:
	var out := {}
	var support: Dictionary = _cfg("support")
	var comeback: Dictionary = _cfg("comeback")
	var key: Dictionary = _cfg("key_squares")
	var cap := float(_cfg("resolve").get("carry_cap", 0.0))
	var from_at: int = ChessEngine.index(String(request.from))
	var seats := {"attacker": {"combatant": request.attacker, "at": ChessEngine.index(String(request.to)), "ignore": from_at},
			"defender": {"combatant": request.defender, "at": ChessEngine.index(String(request.defender.square)), "ignore": -1}}
	for seat in seats:
		var c: Dictionary = seats[seat].combatant
		var color: String = c.color
		var at: int = seats[seat].at
		var ignore: int = seats[seat].ignore
		var take := 1.0
		var tags: Array = []
		# The attacker is judged where it would stand after the capture; the defender where it stands. Either must not count the mover.
		var board_at: int = at
		var friend_defended: bool = defended(engine, board_at, color, ignore)
		if friend_defended:
			take *= float(support.get("defended_take_mult", 1.0))
			tags.append("defended")
		elif isolated(engine, board_at if seat == "defender" else from_at, color):
			take *= float(support.get("isolated_take_mult", 1.0))
			tags.append("isolated")
		if flanked(engine, board_at if seat == "defender" else from_at, color):
			take *= float(support.get("flanked_take_mult", 1.0))
			tags.append("flanked")
		if is_behind(engine.board, color):
			take *= float(comeback.get("take_mult", 1.0))
			tags.append("comeback")
		var regen := 1.0
		var mine := key_control(engine, color)
		if mine >= int(key.get("control_needed", 99)) and mine > key_control(engine, "b" if color == "w" else "w"):
			regen = float(key.get("regen_mult", 1.0))
			tags.append("centre")
		out[seat] = {"hp": start_hp(String(c.pieceId), int(c.stats.maxHp)), "resolve": minf(float(resolve[color]), cap), "take_mult": take, "regen_mult": regen}
		_note("duel %s %s: HP %d/%d, Resolve %d, damage x%.2f%s" % [seat, String(c.role).to_upper(), out[seat].hp, int(c.stats.maxHp), int(out[seat].resolve), take, (" [" + ", ".join(tags) + "]") if not tags.is_empty() else ""])
	return out


# ---- board turns -------------------------------------------------------------------------------------------------
## Called after `color` completed a move (quiet or after a duel), with the position after it. `spared` is the pieceId that just fought
## (it does not heal that turn). Heals this side's wounded pieces and awards Resolve for the position it created.
func after_move(engine, registry: Dictionary, color: String, spared: String = "") -> void:
	var healing: Dictionary = _cfg("healing")
	var gain: Dictionary = _cfg("resolve").get("gain", {})
	var healed := 0
	for at in registry:
		var piece: String = engine.board[at]
		var id: String = registry[at]
		if piece.is_empty() or ChessEngine.side(piece) != color or id == spared or not hp.has(id) or float(hp[id]) >= 1.0:
			continue
		var rank: int = at / 8
		var home: bool = rank < int(healing.get("rest_ranks", 0)) if color == "w" else rank >= 8 - int(healing.get("rest_ranks", 0))
		hp[id] = minf(1.0, float(hp[id]) + float(healing.get("per_turn_frac", 0.0)) + (float(healing.get("rest_frac", 0.0)) if home else 0.0))
		healed += 1
	var earned := 0.0
	var protected := 0
	for at in registry:
		var piece: String = engine.board[at]
		if not piece.is_empty() and ChessEngine.side(piece) == color and String(piece).to_lower() != "k":
			var enemy := "b" if color == "w" else "w"
			if engine.attacked(at, enemy) and engine.attacked(at, color):
				protected += 1
	earned += float(gain.get("protect", 0.0)) * mini(protected, 3)
	earned += float(gain.get("control", 0.0)) * key_control(engine, color)
	if engine.in_check("b" if color == "w" else "w"):
		earned += float(gain.get("check", 0.0))
	_award(engine, color, earned, "position")
	if healed > 0:
		_note("%s: %d wounded piece(s) recover" % [color.to_upper(), healed])


func _award(engine, color: String, amount: float, why: String) -> void:
	if amount <= 0.0:
		return
	if is_behind(engine.board, color):
		amount *= float(_cfg("comeback").get("resolve_mult", 1.0))
	var cap := float(_cfg("resolve").get("max", 0.0))
	var before := float(resolve[color])
	resolve[color] = minf(cap, before + amount)
	if resolve[color] > before:
		_note("%s +%.1f Resolve (%s) -> %d" % [color.to_upper(), resolve[color] - before, why, int(resolve[color])])


# ---- duel end ----------------------------------------------------------------------------------------------------
## Folds a finished duel into the persistent state. `summary` is CombatSimulation.duel_summary() from the trusted authority, `request` the
## BattleRequest, `outcome` "attacker" | "defender". Call BEFORE the board commits the capture (positions are read as they were).
func after_duel(engine, request: Dictionary, summary: Dictionary, outcome: String) -> Dictionary:
	var gain: Dictionary = _cfg("resolve").get("gain", {})
	var decisive: Dictionary = _cfg("decisive")
	var report := {"outcome": outcome, "decisive": false}
	var winner_seat: String = outcome
	var loser_seat: String = "defender" if outcome == "attacker" else "attacker"
	for seat in ["attacker", "defender"]:
		var c: Dictionary = request[seat]
		var s: Dictionary = summary.get(seat, {})
		if s.is_empty():
			continue
		# Resolve: what the pool held before the duel minus what was carried in, plus what the duel left in the seat.
		var carried := float(s.get("resolve_start", 0.0))
		resolve[c.color] = clampf(float(resolve[c.color]) - carried + float(s.get("resolve", 0.0)), 0.0, float(_cfg("resolve").get("max", 0.0)))
		if seat == winner_seat:
			hp[c.pieceId] = clampf(float(s.hp) / float(s.max_hp), 0.0, 1.0)
		else:
			hp.erase(c.pieceId)
	var winner: Dictionary = request[winner_seat]
	var w: Dictionary = summary.get(winner_seat, {})
	if not w.is_empty():
		_award(engine, winner.color, float(gain.get("hold_line", 0.0)) if winner_seat == "defender" else float(gain.get("capture_win", 0.0)), "held the line" if winner_seat == "defender" else "won the capture")
		if float(w.hp) / float(w.max_hp) >= float(decisive.get("winner_hp_frac", 2.0)):
			report.decisive = true
			hp[winner.pieceId] = minf(1.0, float(hp[winner.pieceId]) + float(decisive.get("heal_frac", 0.0)))
			_award(engine, winner.color, float(decisive.get("resolve", 0.0)), "decisive win")
			_note("%s decisive win: initiative bonus (heal +%d%%)" % [winner.color.to_upper(), int(100.0 * float(decisive.get("heal_frac", 0.0)))])
	_note("duel result: %s wins (%s %d/%d, %s %d/%d)" % [String(winner.role).to_upper(), String(request.attacker.role).to_upper(), int(summary.get("attacker", {}).get("hp", 0)), int(summary.get("attacker", {}).get("max_hp", 0)), String(request.defender.role).to_upper(), int(summary.get("defender", {}).get("hp", 0)), int(summary.get("defender", {}).get("max_hp", 0))])
	report["loser_seat"] = loser_seat
	return report
