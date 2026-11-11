extends SceneTree
const Match = preload("res://chess/battle_match.gd")
const Rules = preload("res://chess/battle_rules.gd")
const Classic = preload("res://chess/chess_engine.gd")
const Codec = preload("res://contracts/codec.gd")
const FEN = "7k/8/8/4q3/3P4/8/8/7K w - - 0 1"
var checks = 0
var failures: Array = []
var authority = RefCounted.new()
var snapshots: Array = []
func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("FAIL: ", label)
func game(fen: String = FEN):
	var g = Match.new()
	g.bind_combat_authority(authority)
	expect(g.new_game(0, 0, fen).ok, "valid Battle position")
	return g
func result(g, outcome: String = "attacker", cause: String = "knockout") -> Dictionary:
	var p = g.pending_request()
	var a: float = p.attacker.stats.maxHp if outcome == "attacker" else 0
	var d: float = p.defender.stats.maxHp if outcome == "defender" else 0
	return {"schemaVersion": 1, "matchId": g.match_id, "battleId": p.battleId, "expectedRevision": g.revision, "resolvedTick": p.startTick + 181, "winnerPlayerId": p[outcome].playerId, "outcome": outcome, "reason": cause, "attackerHp": a, "defenderHp": d}
func finish(g, outcome: String) -> void:
	var r = result(g, outcome)
	expect(g.accept_result(r, authority).ok, "accept trusted " + outcome)
	expect(g.accept_result(r, authority).get("duplicate", false), "idempotent terminal signal")
	expect(g.commit_battle().ok, "commit " + outcome)
	expect(not g.commit_battle().ok, "settle once")
	expect(not g.accept_result(r, authority).ok, "ignore late result after commit")
	expect(Codec.new().valid("MatchState", g.match_state()), "committed state schema")
	snapshots.append({"type": "MatchState", "payload": g.match_state()})
func _init() -> void:
	for winner in ["attacker", "defender"]:
		var g = game()
		var before = g.chess_state()
		var ids = g.registry.duplicate()
		expect(g.play("d4", "e5").ok, "prepare capture")
		expect(g.chess_state() == before and not g.board_input_allowed(), "frozen board/revision/history")
		expect(Codec.new().valid("MatchState", g.match_state()), "pending state schema")
		expect(not g.play("h1", "h2").ok and not g.undo() and not g.set_paused(true), "no move/undo/pause during duel")
		var pending = g.pending_request()
		pending.attacker.stats.maxHp = 999
		expect(g.pending_request().attacker.stats.maxHp == 80, "request access cannot mutate authority")
		finish(g, winner)
		expect(g.engine.turn == "b" and g.engine.history.size() == 1 and g.revision == 1, "turn consumed once")
		expect(g.engine.board[Rules.index("d4")] == "", "attacker origin empty")
		expect(g.engine.board[Rules.index("e5")] == ("P" if winner == "attacker" else "q"), "correct survivor")
		expect(g.registry[Rules.index("e5")] == ids[Rules.index("d4" if winner == "attacker" else "e5")], "stable survivor identity")
		expect(g.chess_state().history[0].outcome == winner, "wire outcome")
		expect(not g.engine.in_check("w"), "moving king safe")
	# C0 restrictions remain distinct from Classic and from the future royal gauntlet.
	for case in [["4r2k/8/8/8/8/8/4R3/4K3 w - - 0 1", "e2", "e8"], ["7k/8/8/8/8/8/3Rr3/4K3 w - - 0 1", "d2", "e2"], ["7k/8/8/8/8/8/p7/K7 w - - 0 1", "a1", "a2"]]:
		var g = game(case[0])
		var before = g.chess_state()
		expect(not g.play(case[1], case[2]).ok and g.chess_state() == before, "reject unsafe/king duel")
		var classic = Classic.new()
		classic.load_fen(case[0])
		expect(classic.move(case[1], case[2]).ok, "Classic capture remains legal")
	for winner in ["attacker", "defender"]:
		var g = game("7k/8/8/3pP3/8/8/8/7K w - d6 0 1")
		g.play("e5", "d6")
		expect(g.pending_request().defender.square == "d5", "EP victim square")
		finish(g, winner)
		expect(g.engine.board[Rules.index("d5")] == ("p" if winner == "defender" else ""), "EP victim outcome")
		expect(g.engine.board[Rules.index("d6")] == ("P" if winner == "attacker" else ""), "EP destination outcome")
		expect(g.engine.ep == -1 and g.engine.halfmove == 0, "EP reset counters")
	for promotion in ["q", "r", "b", "n"]:
		for winner in ["attacker", "defender"]:
			var g = game("1r5k/P7/8/8/8/8/8/K7 w - - 0 1")
			g.play("a7", "b8", promotion)
			expect(g.pending_request().attacker.role == "p", "promotion fights as pawn")
			finish(g, winner)
			expect(g.engine.board[57] == (promotion.to_upper() if winner == "attacker" else "r"), "capture promotion " + promotion)
	for winner in ["attacker", "defender"]:
		var g = game("k7/7r/8/8/8/8/8/4K2R w K - 0 1")
		g.play("h1", "h7")
		finish(g, winner)
		expect(g.engine.castling.is_empty(), "attacking original rook loses rights")
		g = game("4k2r/8/8/8/8/8/7R/K7 w k - 0 1")
		g.play("h2", "h8")
		finish(g, winner)
		expect(g.engine.castling == ("k" if winner == "defender" else ""), "winning defending original rook retains rights")
	var g = game("k7/8/8/3p4/4N3/8/8/7K b - - 12 24")
	g.play("d5", "e4")
	finish(g, "defender")
	expect(g.engine.fullmove == 25 and g.engine.turn == "w" and g.engine.halfmove == 0, "Black failed capture counters")
	g = game("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
	expect(g.play("e1", "g1").ok and g.phase == "board" and g.engine.board[5] == "R", "castling quiet compound move")
	g = game("r3k2r/8/8/8/8/5r2/8/R3K2R w KQkq - 0 1")
	expect(not g.play("e1", "g1").ok, "no castling through check")
	g = game("1r5k/8/8/8/8/8/r7/K7 w - - 0 1")
	expect(g.engine.reason == "Checkmate", "C0 mate with no battle-legal escape")
	g = game("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")
	expect(g.engine.reason == "Stalemate", "stalemate")
	g = game("7k/8/8/8/8/8/R7/K7 w - - 99 1")
	g.play("a2", "a3")
	expect(g.engine.reason == "Fifty-move rule", "C0 fifty draw automatic")
	g = game(Rules.START_FEN)
	for cycle in range(2):
		for m in [["g1", "f3"], ["g8", "f6"], ["f3", "g1"], ["f6", "g8"]]:
			g.play(m[0], m[1])
	expect(g.engine.reason == "Threefold repetition", "C0 repetition automatic")
	g = game("7k/8/8/3pP3/4K3/8/8/8 w - d6 0 1")
	expect(g.engine.position_key().split(" ")[3] == "-", "C0 repetition ignores unsafe EP")
	# Forged IDs, causes, HP, ticks, seat, sender and board tampering never commit.
	g = game()
	g.play("d4", "e5")
	var good = result(g)
	var original = g.chess_state()
	var stranger = RefCounted.new()
	expect(not g.accept_result(good, stranger).ok, "reject unbound source")
	for mutation in [{"battleId": "other"}, {"matchId": "other"}, {"winnerPlayerId": g.players.b}, {"expectedRevision": 42}, {"attackerHp": 10000}, {"defenderHp": 1}, {"resolvedTick": 0}, {"reason": "timeout_hp"}, {"attackerHp": NAN}, {"attackerHp": INF}, {"resolvedTick": 1.5}]:
		var invalid = good.duplicate(true)
		invalid.merge(mutation, true)
		expect(not g.accept_result(invalid, authority).ok and g.chess_state() == original, "reject invalid result " + str(mutation))
	var snapshot = g.combat_snapshot()
	snapshot.fighters[1].playerId = snapshot.fighters[0].playerId
	expect(not g.accept_snapshot(snapshot, authority), "reject duplicate fighter identity")
	snapshot = g.combat_snapshot()
	snapshot.serverTick = good.resolvedTick
	snapshot.countdownTicksRemaining = 0
	snapshot.durationTicksRemaining = 5399
	snapshot.result = good
	expect(not g.accept_snapshot(snapshot, authority), "terminal snapshot HP must agree with result")
	for fighter in snapshot.fighters:
		if fighter.playerId == g.pending_request().defender.playerId:
			fighter.hp = 0
	snapshot.serverTick += 1
	snapshot.durationTicksRemaining -= 1
	expect(not g.accept_snapshot(snapshot, authority), "terminal snapshot tick must agree with result")
	g.engine.halfmove = 42
	expect(not g.accept_result(good, authority).ok, "reject changed frozen FEN")
	g.engine.halfmove = 0
	g.cancel_pending()
	expect(g.chess_state() == original and g.board_input_allowed(), "cancel restores unchanged board")
	g.play("d4", "e5")
	expect(g.pending_request().battleId != good.battleId and not g.accept_result(good, authority).ok, "late old generation cannot settle new battle")
	finish(g, "defender")
	# Deterministic tiebreaks and end timing.
	for cause in ["timeout_hp", "timeout_tie", "double_knockout"]:
		g = game()
		g.play("d4", "e5")
		var r = result(g, "defender", cause)
		if cause.begins_with("timeout"):
			r.resolvedTick = g.pending_request().startTick + 5580
		if cause == "timeout_hp":
			r.attackerHp = 40
		if cause == "timeout_tie":
			r.attackerHp = 80
			r.defenderHp = 135
		elif cause == "double_knockout":
			r.attackerHp = 0
			r.defenderHp = 0
		expect(g.accept_result(r, authority).ok and g.commit_battle().ok, "tie/timeout reason " + cause)
	g = game("7k/5Qr1/7K/8/8/8/8/8 w - - 0 1")
	g.play("f7", "g7")
	finish(g, "attacker")
	expect(g.engine.reason == "Checkmate" and g.engine.result == "1-0", "successful capture produces C0 mate")
	g = game("1b5k/P7/8/8/8/8/8/K7 w - - 0 1")
	g.play("a7", "b8", "q")
	finish(g, "defender")
	expect(g.engine.reason == "Insufficient material", "defender victory can produce material draw")
	g = game("7k/P7/8/8/8/8/8/K7 w - - 0 1")
	expect(g.play("a7", "a8", "q").ok and g.phase == "board" and g.engine.board[56] == "Q", "quiet promotion bypasses combat")
	g = game()
	g.play("d4", "e5")
	g.resign()
	expect(g.engine.result == "0-1" and g.pending_request().is_empty(), "resign clears unfinished duel")
	g = game()
	g.play("d4", "e5")
	g.accept_result(result(g), authority)
	g.cancel_pending()
	expect(g.revision == 1 and g.engine.history.size() == 1, "cancel cannot discard a validated result")
	g = game()
	g.play("d4", "e5")
	g.accept_result(result(g), authority)
	g.resign()
	expect(g.revision == 1 and g.engine.history.size() == 1 and g.engine.result == "0-1", "resign after result commits battle and preserves resigning seat")
	g = game("7k/5Qr1/7K/8/8/8/8/8 w - - 0 1")
	g.play("f7", "g7")
	g.accept_result(result(g), authority)
	g.resign()
	expect(g.engine.result == "1-0" and g.engine.reason == "Checkmate", "already validated mate takes precedence over late resignation")
	var args = OS.get_cmdline_user_args()
	if args.size() == 1:
		var file = FileAccess.open(args[0], FileAccess.WRITE)
		file.store_string(JSON.stringify(snapshots, "", true, true))
	print("BATTLE MATCH: ", checks, " checks; failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
