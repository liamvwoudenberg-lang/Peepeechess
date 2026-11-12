extends SceneTree
## Battle Chess: the computer plays a whole game against itself through BattleChessMatch. Duels are auto-resolved
## through the match's trusted-result path (the same fixture pattern as tests/battle/match_test.gd): the winner is
## drawn from the class matchup probability the AI itself uses, so both outcomes (attacker / defender) occur.
const Match = preload("res://chess/battle_match.gd")
const Codec = preload("res://contracts/codec.gd")
const Support = preload("res://tests/ai/ai_support.gd")
const MAX_PLIES = 90
var checks = 0
var failures: Array = []
var authority = RefCounted.new()
func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("FAIL: ", label)
func _init() -> void:
	call_deferred("run")
func duel_result(g, outcome: String) -> Dictionary:
	var p = g.pending_request()
	return {"schemaVersion": 1, "matchId": g.match_id, "battleId": p.battleId, "expectedRevision": g.revision, "resolvedTick": p.startTick + 181, "winnerPlayerId": p[outcome].playerId, "outcome": outcome, "reason": "knockout", "attackerHp": p.attacker.stats.maxHp if outcome == "attacker" else 0, "defenderHp": p.defender.stats.maxHp if outcome == "defender" else 0}
func play_battle_game(seed_value: int, white_level: int, black_level: int) -> Dictionary:
	var g = Match.new()
	g.bind_combat_authority(authority)
	g.new_game()
	var ais = {"w": ChessAI.new(white_level, seed_value), "b": ChessAI.new(black_level, seed_value + 1)}
	for color in ais:
		ais[color].deterministic = true
		ais[color].node_scale = 0.12
	var dice = RandomNumberGenerator.new()
	dice.seed = seed_value
	var stats = {"plies": 0, "captures": 0, "attacker_wins": 0, "defender_wins": 0, "illegal": 0, "rejected": 0}
	while g.engine.result.is_empty() and stats.plies < MAX_PLIES:
		var choice = ais[g.engine.turn].choose_move(g.engine)
		if not choice.ok:
			stats.illegal += 1
			break
		var legal = false
		for m in g.engine.legal_moves():
			legal = legal or (m.from == choice.move.from and m.to == choice.move.to and m.promotion == choice.move.promotion)
		if not legal:
			stats.illegal += 1
			break
		var response = g.play(choice.from, choice.to, choice.promotion if choice.promotion != "" else "q")
		if not response.ok:
			stats.rejected += 1
			break
		if g.phase == "combat":
			stats.captures += 1
			var request = g.pending_request()
			var p = ChessBattleModel.win_probability(request.attacker.role, request.defender.role)
			var outcome = "attacker" if dice.randf() < p and stats.captures % 4 != 0 else "defender"  # every 4th duel goes to the defender so both settlement paths run
			stats["attacker_wins" if outcome == "attacker" else "defender_wins"] += 1
			expect(g.accept_result(duel_result(g, outcome), authority).ok, "duel result accepted (game %d ply %d)" % [seed_value, stats.plies])
			expect(g.commit_battle().ok, "duel committed (game %d)" % seed_value)
		stats.plies += 1
	stats["result"] = g.engine.result
	stats["reason"] = g.engine.reason
	stats["state_valid"] = Codec.new().valid("MatchState", g.match_state())
	return stats
func run() -> void:
	var started = Time.get_ticks_msec()
	var totals = {"plies": 0, "captures": 0, "attacker_wins": 0, "defender_wins": 0}
	var games = [[11, 4, 4], [12, 6, 3], [13, 2, 5], [14, 3, 3]]
	for g in games:
		var s = play_battle_game(g[0], g[1], g[2])
		expect(s.illegal == 0 and s.rejected == 0, "Battle game %d: every move was Battle-legal and accepted" % g[0])
		expect(s.plies == MAX_PLIES or s.result != "", "Battle game %d ends by a rules result or the move cap" % g[0])
		expect(s.state_valid, "Battle game %d final MatchState matches the v1 schema" % g[0])
		print("battle game %d (L%d vs L%d): %d plies, %d duels (attacker %d / defender %d), result %s %s" % [g[0], g[1], g[2], s.plies, s.captures, s.attacker_wins, s.defender_wins, s.result if s.result != "" else "(move cap)", s.reason])
		for key in totals:
			totals[key] += s[key]
	expect(totals.captures >= 6, "the Battle games contain duels (%d)" % totals.captures)
	expect(totals.attacker_wins > 0 and totals.defender_wins > 0, "both duel outcomes were exercised")
	# --- Battle rules layer: no move when the Battle-legal move list is empty (documented Battle checkmate) ---
	var mated = ClassicChess.new()
	var battle_mate = BattleChessRules.new()
	expect(battle_mate.load_fen("1r5k/8/8/8/8/8/r7/K7 w - - 0 1").ok and battle_mate.legal_moves().is_empty(), "documented position is a Battle checkmate")
	expect(not ChessAI.new(6, 1).choose_move(battle_mate).ok, "no move is chosen without Battle-legal moves")
	expect(mated.load_fen("1r5k/8/8/8/8/8/r7/K7 w - - 0 1").ok and not mated.legal_moves().is_empty(), "the same position has a Classic escape (king takes a2)")
	# --- capture heuristic: a pawn taking a queen is a gamble in Battle Chess ---
	var fen = "4k3/8/8/3q4/4P3/8/PPP5/4K3 w - - 0 1"
	var classic = ClassicChess.new()
	classic.load_fen(fen)
	var battle = BattleChessRules.new()
	battle.load_fen(fen)
	var ai_classic = ChessAI.new(6, 1)
	ai_classic.deterministic = true
	var ai_battle = ChessAI.new(6, 1)
	ai_battle.deterministic = true
	var c = ai_classic.choose_move(classic, {"node_limit": 4000})
	var b = ai_battle.choose_move(battle, {"node_limit": 4000})
	expect(c.ok and c.from + c.to == "e4d5" and c.score > 100, "Classic: the pawn takes the queen (score %d)" % c.score)
	expect(b.ok and b.score < c.score - 300, "Battle: beating a queen with a pawn is a long shot, not a won queen (Battle score %d vs Classic %d)" % [b.score, c.score])
	expect(ChessBattleModel.win_probability("p", "q") < 0.2 and ChessBattleModel.win_probability("q", "p") > 0.8, "matchup table: queen beats pawn far more often than the reverse")
	var knight_takes = "4k3/p7/8/3p4/8/4N3/P7/4K3 w - - 0 1"
	battle.load_fen(knight_takes)
	var k = ChessAI.new(6, 1)
	k.deterministic = true
	var kr = k.choose_move(battle, {"node_limit": 3000})
	expect(kr.ok and kr.from + kr.to == "e3d5", "Battle: a knight (strong fighter) still takes a pawn")
	# --- no kings in duels: the AI never starts a king capture ---
	var near = BattleChessRules.new()
	near.load_fen("4k3/8/8/8/8/8/3p4/3K4 w - - 0 1")
	var kc = ChessAI.new(5, 1).choose_move(near, {"node_limit": 800})
	expect(kc.ok and kc.from + kc.to != "d1d2", "the AI never starts a king duel")
	print("AI BATTLE: %d plies total, %d duels, %.1f s" % [totals.plies, totals.captures, (Time.get_ticks_msec() - started) / 1000.0])
	print("AI BATTLE CHECKS: ", checks, " checks; failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
