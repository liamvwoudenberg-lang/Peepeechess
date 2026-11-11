extends SceneTree
## battle-royal-v1 rules scenarios (docs/architecture/BATTLE_ROYAL_V1.md) with scripted combat results.
## The King's end resources come from a fake trusted authority (`Auth.fighter_state`), exactly like the real simulation.
const Royal = preload("res://chess/battle_royal_match.gd")
const RoyalRules = preload("res://chess/battle_royal_rules.gd")
const Legacy = preload("res://chess/battle_match.gd")
const Classic = preload("res://chess/classic_match.gd")
const Codec = preload("res://contracts/codec.gd")
const BOTH = "R3k3/3p1p2/8/8/8/8/8/4R1K1 b - - 0 1" # double check Re1 + Ra8, king boxed in
const TRIPLE = "3rkr2/5p2/3N4/1B6/8/8/8/4R1K1 b - - 0 1" # triple check Bb5, Nd6, Re1; every escape covered or own piece
const BACK_RANK = "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1" # Ra8# is mate
const FULL = {"hp": 160, "stamina": 100.0, "cooldownTicks": 0}
var checks = 0
var failures: Array = []
var royal_codec = load("res://contracts/royal/v1/codec.gd").new()
var v1 = Codec.new()

class Auth extends RefCounted:
	var state = {"hp": 160, "stamina": 100.0, "cooldownTicks": 0}
	func fighter_state(_player_id): return state

class Silent extends RefCounted:
	pass

func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("FAIL: ", label)

func _init() -> void:
	call_deferred("run")

func fresh(fen: String, authority: Object = null):
	var g = Royal.new()
	g.bind_combat_authority(authority if authority != null else Auth.new())
	expect(g.new_game(0, 0, fen).ok, "royal position loads: " + fen)
	return g

func result_of(g, king_wins: bool, king_hp: int, checker_hp: int = 0, reason: String = "knockout", outcome: String = "") -> Dictionary:
	var p = g.pending_request()
	var out = outcome if not outcome.is_empty() else ("attacker" if king_wins else "defender")
	return {"schemaVersion": 1, "matchId": g.match_id, "battleId": p.battleId, "expectedRevision": g.revision, "resolvedTick": p.startTick + 181 + 600, "winnerPlayerId": p[out].playerId, "outcome": out, "reason": reason, "attackerHp": king_hp, "defenderHp": checker_hp}

## Resolves the pending duel through the trusted-authority path. `end` is what the authority reports for the King.
func duel(g, a, king_wins: bool, end: Dictionary, checker_hp: int = 0) -> Dictionary:
	a.state = end
	var r = result_of(g, king_wins, int(end.hp), 0 if king_wins else maxi(1, checker_hp))
	var accepted = g.accept_result(r, a)
	if not accepted.ok:
		return accepted
	return g.commit_battle()

func squares(group: Array) -> Array:
	return group.map(func(e): return RoyalRules.square(e.square))

func engine(fen: String):
	var e = RoyalRules.new()
	expect(e.load_fen(fen).ok, "engine loads " + fen)
	return e

func run() -> void:
	group_rules()
	entry_rules()
	sequence_rules()
	failure_rules()
	authority_rules()
	end_of_sequence_rules()
	repeated_and_edge_rules()
	legacy_and_serialization()
	if failures.is_empty():
		print("PASS: %d royal rules checks" % checks)
		quit(0)
	else:
		printerr("FAILED: %d of %d royal rules checks" % [failures.size(), checks])
		quit(1)

# ---- (a) the mating group ---------------------------------------------------------------------------------------------
func group_rules() -> void:
	var e = engine("6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1")
	expect(e.mating_group().is_empty(), "no check, no group")
	e = engine("R5k1/5ppp/8/8/8/8/5PPP/6K1 b - - 0 1")
	expect(squares(e.mating_group()) == ["a8"] and e.mate_pending.mated == "b", "single check: the checker is the group; mated side is recorded")
	e = engine(BOTH)
	expect(squares(e.mating_group()) == ["e1", "a8"], "double check by equal pieces: ascending square (a1..h8) order")
	expect(e.mate_pending.group.size() == 2 and e.result.is_empty(), "mate is pending, not a result")
	e = engine("4k3/8/8/1B6/8/8/8/4R1K1 b - - 0 1")
	expect(squares(e.mating_group()) == ["b5", "e1"], "ascending material first: bishop (3) before rook (5) although e1 < b5")
	e = engine("4k3/8/3N2B1/8/8/8/8/6K1 b - - 0 1")
	expect(squares(e.mating_group()) == ["d6", "g6"], "knight and bishop tie on value: square decides")
	e = engine("4k3/3P4/8/8/4Q3/8/8/6K1 b - - 0 1")
	expect(squares(e.mating_group()) == ["d7", "e4"], "pawn (1) before queen (9)")
	e = engine("4k3/8/8/3B4/8/8/8/4R1K1 b - - 0 1")
	expect(squares(e.mating_group()) == ["e1"], "a piece that merely moved (discovered check) is not a checker; the revealed one is")
	e = engine("R5k1/5ppp/8/8/8/8/5PPP/1B4K1 b - - 0 1")
	expect(squares(e.mating_group()) == ["a8"], "a piece covering escape squares is not in the group")
	e = engine(TRIPLE)
	expect(squares(e.mating_group()) == ["b5", "d6", "e1"], "three checkers: value then square")
	var before = e.board.duplicate()
	e.mating_group()
	expect(e.board == before, "computing the group does not touch the board")
	expect(e.piece_attacks(RoyalRules.index("e1"), RoyalRules.index("e8")) and not e.piece_attacks(RoyalRules.index("d6"), RoyalRules.index("d8")), "attack geometry helper")

# ---- entry: quiet mate, capture mate, loaded mate, non-mates ----------------------------------------------------------
func entry_rules() -> void:
	var g = fresh(BACK_RANK)
	expect(not g.royal_active() and g.board_input_allowed(), "no sequence before a mate")
	var started: Array = []
	var signals: Array = []
	g.sequence_started.connect(func(info): started.append(info))
	g.duel_started.connect(func(index, total, hp): signals.append([index, total, hp]))
	var move = g.play("a1", "a8")
	expect(move.ok and move.san == "Ra8#", "the quiet mating move is accepted")
	expect(g.royal_active() and g.phase == "combat" and g.engine.result.is_empty(), "checkmate opens a last stand, not a result")
	expect(g.revision == 1 and g.engine.history.size() == 1, "the mating move consumed one ply")
	expect(started.size() == 1 and signals == [[0, 1, 160]], "sequence_started / duel_started(index,total,king_hp) fired once")
	var p = g.pending_request()
	expect(p.attacker.role == "k" and p.attacker.color == "b" and p.defender.role == "r" and p.defender.square == "a8", "the mated King attacks the checking rook")
	expect(p.beforeFen == g.engine.fen() and p.from == "g8" and p.to == "a8", "frozen mating position and squares")
	expect(not g.board_input_allowed() and not g.play("g1", "h1").ok, "the board is frozen during the sequence")
	expect(g.combat_options() == {"allow_experimental_roles": true, "initial_hp": 160, "initial_stamina": 100.0, "initial_cooldown": 0}, "combat options carry the full King")
	expect(g.royal_duel_request().kingStart == FULL and g.royal_codec.valid("RoyalDuelRequest", g.royal_duel_request()), "duel envelope valid")
	expect(g.royal_progress().remaining == ["w-r-a1"] and g.royal_progress().defeated == [], "progress lists the remaining checker")
	# A capture that settles into mate also opens the last stand.
	var c = fresh("r5k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1")
	expect(c.play("a1", "a8").ok and c.phase == "combat" and not c.royal_active(), "Rxa8 is an ordinary capture duel first")
	var auth = Auth.new()
	c.bind_combat_authority(auth)
	var ordinary = c.pending_request()
	expect(ordinary.attacker.role == "r" and ordinary.defender.role == "r", "the capture duel is the normal Rook vs Rook fight")
	auth.state = FULL
	var r = {"schemaVersion": 1, "matchId": c.match_id, "battleId": ordinary.battleId, "expectedRevision": c.revision, "resolvedTick": ordinary.startTick + 181, "winnerPlayerId": ordinary.attacker.playerId, "outcome": "attacker", "reason": "knockout", "attackerHp": 190, "defenderHp": 0}
	expect(c.accept_result(r, auth).ok and c.commit_battle().ok, "the capture settles normally")
	expect(c.royal_active() and c.pending_request().attacker.role == "k" and c.pending_request().defender.pieceId == "w-r-a1", "the capture that mates opens the last stand against the capturing rook")
	# A losing capture does not mate.
	var d = fresh("r5k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1")
	var d_auth = Auth.new()
	d.bind_combat_authority(d_auth)
	d.play("a1", "a8")
	var req = d.pending_request()
	var lost = {"schemaVersion": 1, "matchId": d.match_id, "battleId": req.battleId, "expectedRevision": d.revision, "resolvedTick": req.startTick + 181, "winnerPlayerId": req.defender.playerId, "outcome": "defender", "reason": "knockout", "attackerHp": 0, "defenderHp": 100}
	expect(d.accept_result(lost, d_auth).ok and d.commit_battle().ok and not d.royal_active() and d.phase == "board" and d.engine.result.is_empty(), "a defended capture is not mate: play continues")
	# A position that is already checkmate fights at once.
	var loaded = fresh(BOTH)
	expect(loaded.royal_active() and loaded.royal_request().attackers.size() == 2, "a loaded checkmate position fights its last stand immediately")
	# Stalemate is not mate.
	var stale = fresh("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")
	expect(stale.engine.result == "1/2-1/2" and stale.engine.reason == "Stalemate" and not stale.royal_active(), "stalemate is a draw, never a sequence")
	# En passant is an ordinary capture duel under royal rules too.
	var ep = fresh("7k/8/8/3pP3/8/8/8/K7 w - d6 0 1")
	var ep_auth = Auth.new()
	ep.bind_combat_authority(ep_auth)
	ep.play("e5", "d6")
	expect(ep.pending_request().defender.square == "d5" and not ep.royal_active(), "en passant: the victim square fights, no sequence")

# ---- the sequence: persistence, order, board effects ----------------------------------------------------------------------
func sequence_rules() -> void:
	var a = Auth.new()
	var g = fresh(BOTH, a)
	var mid = g.match_id
	var group = g.royal_request().attackers
	expect(group.map(func(x): return x.square) == ["e1", "a8"], "ordered participants in the request")
	expect(group.all(func(x): return x.role == "r" and x.stats.maxHp == 190), "every checker carries its own full stats")
	var first = g.pending_request()
	expect(first.defender.square == "e1" and first.attacker.role == "k", "duel 1 is against the first checker")
	expect(g.combat_snapshot().fighters.filter(func(f): return f.pieceId == "b-k-e8")[0].hp == 160, "the King opens duel 1 at full HP")
	var carried = {"hp": 112, "stamina": 61.5, "cooldownTicks": 340}
	var step = duel(g, a, true, carried)
	expect(step.ok and step.sequence == "active" and g.royal_active() and g.phase == "combat", "winning duel 1 opens duel 2")
	var second = g.pending_request()
	expect(second.defender.square == "a8" and second.battleId != first.battleId and second.startTick >= first.startTick + 180, "duel 2 faces the next checker with a new battle id")
	expect(g.royal_duel_request().kingStart == carried and g.royal_duel_request().duelIndex == 1 and g.royal_duel_request().duelCount == 2, "the King's HP/stamina/cooldown carry into duel 2")
	expect(g.combat_options() == {"allow_experimental_roles": true, "initial_hp": 112, "initial_stamina": 61.5, "initial_cooldown": 340}, "combat options reflect the carried state")
	var king_seat = g.combat_snapshot().fighters.filter(func(f): return f.pieceId == "b-k-e8")[0]
	var checker_seat = g.combat_snapshot().fighters.filter(func(f): return f.pieceId != "b-k-e8")[0]
	expect(king_seat.hp == 112 and king_seat.stamina == 61.5 and king_seat.cooldownTicks == 340, "the opening snapshot of duel 2 shows the carried values")
	expect(checker_seat.hp == 190 and checker_seat.stamina == 90, "the second checker starts at full HP and stamina")
	expect(g.royal_progress().defeated == ["w-r-e1"] and g.royal_progress().remaining == ["w-r-a8"], "progress: first checker defeated, one remaining")
	expect(not g.board_input_allowed() and g.chess_state().revision == 0, "the board stays frozen and the revision unchanged mid-sequence")
	var third_state = {"hp": 31, "stamina": 0.0, "cooldownTicks": 20}
	var done = duel(g, a, true, third_state)
	expect(done.ok and done.outcome == "king_survived" and not g.royal_active(), "winning every duel ends the sequence with the King alive")
	# Board after: the whole group is gone; same side to move; no ply consumed.
	expect(g.engine.board[RoyalRules.index("a8")] == "" and g.engine.board[RoyalRules.index("e1")] == "", "both checkers left the board")
	expect(g.engine.board[RoyalRules.index("e8")] == "k" and g.engine.board[RoyalRules.index("g1")] == "K", "the Kings stand where they stood")
	expect(g.engine.turn == "b" and g.engine.result.is_empty() and g.phase == "board", "play resumes with the mated side to move")
	expect(g.engine.history.size() == 0 and g.revision == 1, "history is not extended by the removal; revision advanced once for the sequence")
	expect(g.registry.values().has("w-r-e1") == false and g.registry.values().has("w-r-a8") == false and g.registry.has(RoyalRules.index("e8")), "registry lost exactly the defeated checkers")
	expect(g.engine.ep == -1 and g.engine.halfmove == 0 and g.engine.fullmove == 1, "ep cleared, halfmove reset, fullmove unchanged")
	expect(g.engine.keys.size() == 1, "repetition history restarts at the irreversible removal")
	expect(g.board_input_allowed() and g.play("e8", "e7").ok, "the King can play on")
	expect(g.royal_log.size() == 1 and g.royal_log[0].outcome == "king_survived" and g.royal_log[0].kingEnd == third_state and g.royal_log[0].defeated == ["w-r-e1", "w-r-a8"], "the royal log records the sequence")
	expect(g.royal_log[0].duels.size() == 2 and g.royal_log[0].duels[0].kingEnd == carried and g.royal_log[0].duels[1].kingSurvived, "per-duel results persist the trail")
	expect(royal_codec.valid("RoyalSequenceResult", g.royal_log[0]) and g.engine.pgn().contains("lastStands") and g.engine.pgn().contains("battle-royal-v1"), "result valid; the chronicle names the ruleset and the last stand")
	expect(g.royal_log[0].battleId.begins_with(mid), "ids derive from the match id")

# ---- losing the sequence --------------------------------------------------------------------------------------------------
func failure_rules() -> void:
	# The King loses the FIRST duel of three.
	var a = Auth.new()
	var g = fresh(TRIPLE, a)
	var before = g.engine.fen()
	expect(g.royal_request().attackers.map(func(x): return x.square) == ["b5", "d6", "e1"], "three checkers ordered bishop, knight, rook")
	var end = duel(g, a, false, {"hp": 0, "stamina": 40.0, "cooldownTicks": 100}, 77)
	expect(end.ok and end.outcome == "king_fell" and not g.royal_active(), "losing duel 1 ends the whole sequence")
	expect(g.engine.result == "1-0" and g.engine.reason == "Checkmate" and g.engine.fen() == before, "the match ends as checkmate for the other side; the board is untouched")
	expect(g.royal_log[0].duels.size() == 1 and g.royal_log[0].defeated == [] and g.royal_log[0].matchResult == "1-0", "the other checkers never fought")
	expect(g.match_state().phase == "complete" and royal_codec.valid("RoyalMatchState", g.match_state()), "complete state is valid")
	# The King loses the MIDDLE duel.
	a = Auth.new()
	g = fresh(TRIPLE, a)
	duel(g, a, true, {"hp": 120, "stamina": 70.0, "cooldownTicks": 300})
	var mid = duel(g, a, false, {"hp": 0, "stamina": 10.0, "cooldownTicks": 200}, 60)
	expect(mid.outcome == "king_fell" and g.engine.result == "1-0", "losing the middle duel ends as checkmate")
	expect(g.royal_log[0].duels.size() == 2 and g.royal_log[0].defeated == ["w-b-b5"] and g.royal_log[0].kingEnd.hp == 0, "log: one defeated checker, King at 0")
	# The King loses the LAST duel.
	a = Auth.new()
	g = fresh(TRIPLE, a)
	duel(g, a, true, {"hp": 100, "stamina": 50.0, "cooldownTicks": 400})
	duel(g, a, true, {"hp": 55, "stamina": 20.0, "cooldownTicks": 100})
	expect(g.royal_duel_request().duelIndex == 2 and g.royal_duel_request().kingStart == {"hp": 55, "stamina": 20.0, "cooldownTicks": 100}, "duel 3 starts from the attrition state")
	var last = duel(g, a, false, {"hp": 0, "stamina": 0.0, "cooldownTicks": 0}, 190)
	expect(last.outcome == "king_fell" and g.engine.result == "1-0" and g.royal_log[0].defeated.size() == 2, "losing the last duel still ends as checkmate")
	# A black checker mating a white King: the result flips.
	a = Auth.new()
	g = fresh("6k1/8/8/8/8/8/5PPP/r5K1 w - - 0 1", a)
	expect(g.royal_active() and g.pending_request().attacker.color == "w" and g.royal_request().mated == "w", "a white King can be the mated side")
	duel(g, a, false, {"hp": 0, "stamina": 5.0, "cooldownTicks": 0}, 30)
	expect(g.engine.result == "0-1", "white mated: black wins")
	# Result shapes that cost the King the duel although the result names a winner.
	for case in [["timeout_hp", 40, 190], ["timeout_tie", 80, 95], ["double_knockout", 0, 0]]: # 25% vs 100%; 50% vs 50%; both at 0
		var t = Auth.new()
		var m = fresh(BACK_RANK, t)
		m.play("a1", "a8")
		var p = m.pending_request()
		var kind = case[0]
		var attacker_hp = case[1]
		var defender_hp = case[2]
		t.state = {"hp": attacker_hp, "stamina": 50.0, "cooldownTicks": 10}
		var res = {"schemaVersion": 1, "matchId": m.match_id, "battleId": p.battleId, "expectedRevision": m.revision, "resolvedTick": p.startTick + 180 + 5400, "winnerPlayerId": p.defender.playerId, "outcome": "defender", "reason": kind, "attackerHp": attacker_hp, "defenderHp": defender_hp}
		if kind == "double_knockout":
			res.resolvedTick = p.startTick + 181
		expect(m.accept_result(res, t).ok and m.commit_battle().outcome == "king_fell", kind + ": a defender win (ties and double KO favour the checker) ends the sequence")
	# A timeout the King wins on percentage survives the duel; the checker was not knocked out.
	a = Auth.new()
	g = fresh(BACK_RANK, a)
	g.play("a1", "a8")
	a.state = {"hp": 150, "stamina": 33.0, "cooldownTicks": 80}
	var p = g.pending_request()
	var win = {"schemaVersion": 1, "matchId": g.match_id, "battleId": p.battleId, "expectedRevision": g.revision, "resolvedTick": p.startTick + 180 + 5400, "winnerPlayerId": p.attacker.playerId, "outcome": "attacker", "reason": "timeout_hp", "attackerHp": 150, "defenderHp": 40}
	expect(g.accept_result(win, a).ok and g.commit_battle().outcome == "king_survived", "a timeout won on HP percentage counts as a win; the checker is removed")
	# Disconnect / abandon / resign inside the sequence.
	a = Auth.new()
	g = fresh(BOTH, a)
	duel(g, a, true, {"hp": 90, "stamina": 40.0, "cooldownTicks": 10})
	g.abandon_pending()
	expect(not g.royal_active() and g.phase == "board" and g.royal_log[0].outcome == "abandoned" and g.royal_log[0].duels.size() == 1, "abandon drops the sequence without inventing an outcome")
	expect(g.engine.result.is_empty() and g.engine.mate_pending.is_empty() and royal_codec.valid("RoyalSequenceResult", g.royal_log[0]), "the caller decides the match result (the server awards the forfeit)")
	g = fresh(BOTH, Auth.new())
	g.resign()
	expect(g.engine.result == "1-0" and g.engine.reason == "Resignation" and not g.royal_active(), "the mated side resigning inside its last stand loses")

# ---- authority boundary ------------------------------------------------------------------------------------------------------
func authority_rules() -> void:
	var a = Auth.new()
	var g = fresh(BACK_RANK, a)
	g.play("a1", "a8")
	var p = g.pending_request()
	var r = result_of(g, true, 120)
	var intruder = Auth.new()
	expect(not g.accept_result(r, intruder).ok, "a result from an unbound source is refused")
	var silent = Silent.new()
	g.bind_combat_authority(silent)
	expect(not g.accept_result(r, silent).ok, "an authority without fighter_state cannot settle a king duel")
	g.bind_combat_authority(a)
	a.state = {"hp": 119, "stamina": 50.0, "cooldownTicks": 0}
	expect(not g.accept_result(r, a).ok, "King HP must equal the result's attackerHp")
	for bad in [{"hp": 120, "stamina": -1.0, "cooldownTicks": 0}, {"hp": 120, "stamina": 100.5, "cooldownTicks": 0}, {"hp": 120, "stamina": 5.0, "cooldownTicks": 601}, {"hp": 120, "stamina": 5.0, "cooldownTicks": -1}, {"hp": 120, "stamina": 5.0}, {"hp": 161, "stamina": 5.0, "cooldownTicks": 0}]:
		a.state = bad
		var rr = r.duplicate()
		rr.attackerHp = bad.hp
		expect(not g.accept_result(rr, a).ok, "out-of-range King state refused: " + str(bad))
	a.state = {"hp": 120, "stamina": 5.0, "cooldownTicks": 0}
	var forged = r.duplicate()
	forged["kingEnd"] = {"hp": 160, "stamina": 100.0, "cooldownTicks": 0}
	expect(not g.accept_result(forged, a).ok and not royal_codec.valid("BattleResult", forged), "a client cannot smuggle carried state in a result payload")
	var stale = r.duplicate()
	stale.battleId = "other:duel:0"
	expect(not g.accept_result(stale, a).ok, "a result for another battle is refused")
	expect(g.accept_result(r, a).ok and g.phase == "aftermath", "the genuine result is accepted")
	expect(g.accept_result(r, a).get("duplicate", false), "a repeated terminal signal is idempotent")
	expect(g.commit_battle().ok and not g.commit_battle().ok, "settled once")
	expect(not g.accept_result(r, a).ok, "a late result after the commit is ignored")
	# Snapshots validate the carried countdown values.
	var b = Auth.new()
	var s = fresh(BOTH, b)
	duel(s, b, true, {"hp": 100, "stamina": 55.5, "cooldownTicks": 200})
	var snap = s.combat_snapshot()
	snap.fighters = snap.fighters.duplicate(true)
	expect(s.accept_snapshot(snap, b), "the opening snapshot with the carried King state is accepted")
	var wrong = snap.duplicate(true)
	for f in wrong.fighters:
		if f.pieceId == "b-k-e8":
			f.hp = 160
	expect(not s.accept_snapshot(wrong, b), "a countdown snapshot that resets the King's HP is refused")
	var wrong_stamina = snap.duplicate(true)
	for f in wrong_stamina.fighters:
		if f.pieceId == "b-k-e8":
			f.stamina = 100.0
	expect(not s.accept_snapshot(wrong_stamina, b), "a countdown snapshot that refills the King's stamina is refused")
	# Interrupted duels are retried from the unchanged start state; then checkmate stands.
	var t = Auth.new()
	var m = fresh(BOTH, t)
	duel(m, t, true, {"hp": 88, "stamina": 44.0, "cooldownTicks": 160})
	var id0 = m.pending_request().battleId
	m.cancel_pending()
	expect(m.royal_active() and m.pending_request().battleId == id0 + ":retry1" and m.royal_duel_request().kingStart == {"hp": 88, "stamina": 44.0, "cooldownTicks": 160}, "retry 1: same duel, same King start state, new id")
	m.cancel_pending()
	expect(m.pending_request().battleId == id0 + ":retry2", "retry 2")
	m.cancel_pending()
	expect(not m.royal_active() and m.engine.result == "1-0" and m.royal_log[0].outcome == "unplayable" and m.engine.reason.begins_with("Checkmate"), "after the retries the sequence is unplayable and checkmate stands")
	# A validated result is never discarded by an interruption.
	var u = Auth.new()
	var n = fresh(BACK_RANK, u)
	n.play("a1", "a8")
	u.state = {"hp": 77, "stamina": 1.0, "cooldownTicks": 5}
	n.accept_result(result_of(n, true, 77), u)
	n.cancel_pending()
	expect(not n.royal_active() and n.engine.result.is_empty() and n.royal_log[0].outcome == "king_survived", "cancel after a validated result commits it")

# ---- after a won sequence: re-evaluation -------------------------------------------------------------------------------------
func end_of_sequence_rules() -> void:
	# Still mated by an x-ray piece that was hidden behind the removed checker: checkmate stands, no second sequence.
	var a = Auth.new()
	var g = fresh("3rkr2/3p1p2/8/4Q3/8/8/8/4R1K1 b - - 0 1", a)
	expect(g.royal_active() and g.royal_request().attackers.size() == 1 and g.royal_request().attackers[0].role == "q", "the queen is the only direct checker; the rook behind her is not")
	duel(g, a, true, {"hp": 90, "stamina": 30.0, "cooldownTicks": 0})
	expect(g.engine.result == "1-0" and g.engine.reason == "Checkmate" and not g.royal_active(), "still mated by the revealed rook: checkmate stands")
	expect(g.royal_log.size() == 1 and g.royal_log[0].outcome == "king_survived" and g.royal_log[0].matchResult == "1-0", "no infinite loop: one sequence, recorded, the match is over")
	expect(g.engine.board[RoyalRules.index("e5")] == "" , "the defeated queen is gone even though checkmate stands")
	# Revealed check that still has a legal reply: not mate, so the game continues with the mated side to move, in check.
	var e = RoyalRules.new()
	e.load_fen("4k3/8/8/4Q3/8/8/8/4R1K1 b - - 0 1")
	e.mate_pending = {"mated": "b"}
	e.resolve_king_survived([RoyalRules.index("e5")])
	expect(e.result.is_empty() and e.in_check("b") and e.turn == "b" and not e.legal_moves().is_empty(), "revealed check with an escape square: play continues, black to move in check")
	expect(e.mate_pending.is_empty() and e.keys.size() == 1 and e.halfmove == 0, "the pending mate is cleared and the repetition record restarted")
	# The removal leaves bare Kings: insufficient material is adjudicated by the ordinary rules.
	a = Auth.new()
	g = fresh("k6R/8/1K6/8/8/8/8/8 b - - 0 1", a)
	expect(g.royal_active(), "corner mate by the rook with the king helping")
	duel(g, a, true, {"hp": 10, "stamina": 0.0, "cooldownTicks": 0})
	expect(g.engine.result == "1/2-1/2" and g.engine.reason == "Insufficient material", "after the removal only Kings remain: draw by the ordinary rule")
	# Removing the rook that held a castling right removes the right with it.
	var rights = RoyalRules.new()
	rights.load_fen("r3k3/8/8/8/8/8/8/R3K3 w Qq - 0 1")
	rights.board[RoyalRules.index("a8")] = ""
	expect(rights._castling_on_board() == "Q", "castling rights follow the rooks that remain on their corners")

# ---- repeated sequences, promotion, determinism ---------------------------------------------------------------------------------
func repeated_and_edge_rules() -> void:
	var a = Auth.new()
	var g = fresh("6k1/2p2ppp/8/8/8/8/5PPP/RR4K1 w - - 0 1", a)
	g.play("a1", "a8")
	expect(g.royal_active() and g.royal_request().attackers.map(func(x): return x.pieceId) == ["w-r-a1"], "first mate: Ra8")
	var first_id = g.royal_request().battleId
	duel(g, a, true, {"hp": 40, "stamina": 3.0, "cooldownTicks": 500})
	expect(not g.royal_active() and g.engine.turn == "b" and g.engine.result.is_empty(), "the King survived the first last stand")
	expect(g.play("c7", "c6").ok, "black plays on")
	expect(g.play("b1", "b8").ok and g.royal_active(), "the second back-rank mate opens a second last stand")
	expect(g.royal_duel_request().kingStart == FULL, "a new sequence starts with a full, rested King (HP does not persist across sequences)")
	expect(g.royal_request().battleId != first_id and g.royal_request().battleId.ends_with(":royal:2"), "sequence ids are distinct")
	duel(g, a, false, {"hp": 0, "stamina": 20.0, "cooldownTicks": 0}, 99)
	expect(g.engine.result == "1-0" and g.royal_log.size() == 2 and g.royal_log[0].outcome == "king_survived" and g.royal_log[1].outcome == "king_fell", "the second sequence ends the match; both are logged")
	# Promotion: the checker is the promoted queen and keeps the pawn's stable id.
	a = Auth.new()
	g = fresh("6k1/P4ppp/8/8/8/8/5PP1/6K1 w - - 0 1", a)
	expect(g.play("a7", "a8", "q").ok and g.royal_active(), "the quiet promotion mates")
	var checker = g.royal_request().attackers[0]
	expect(checker.role == "q" and checker.characterId == "royal.q" and checker.pieceId == "w-p-a7" and checker.square == "a8", "the promoted queen fights as a queen under the pawn's stable id")
	# Determinism: identical positions give identical requests (modulo the match id).
	var one = fresh(BOTH).royal_request()
	var two = fresh(BOTH).royal_request()
	var strip = func(x): return JSON.stringify(x).replace(x.matchId, "M")
	expect(strip.call(one) == strip.call(two), "same position, same ordered request")
	# Draw machinery stays out of the way during the sequence.
	var d = fresh(BOTH)
	d.agree_draw()
	expect(d.engine.result.is_empty() and d.royal_active(), "no draw by agreement mid-sequence")
	expect(not d.set_paused(true) and not d.undo(), "no pause or undo mid-sequence")
	var kind = d.play("g1", "h1")
	expect(not kind.ok and kind.error.code == "WRONG_PHASE", "board moves are refused with WRONG_PHASE")

func legacy_and_serialization() -> void:
	# Legacy Battle (C0) and Classic never start a sequence and keep their identity.
	var c0 = Legacy.new()
	c0.new_game(0, 0, BOTH)
	expect(c0.engine.result == "1-0" and c0.engine.reason == "Checkmate" and c0.match_state().phase == "complete", "battle-checkmate-v1: the same position is plain checkmate")
	expect(c0.match_state().rulesetId == "battle-checkmate-v1" and v1.valid("MatchState", c0.match_state()) and c0.combat_options() == {}, "legacy state stays a valid v1 MatchState with no combat options")
	expect(not c0.has_signal("sequence_started"), "legacy match has no sequence signals")
	var classic = Classic.new()
	classic.new_game(0, 0, BOTH)
	expect(classic.engine.result == "1-0" and classic.match_state().battle == null and classic.match_state().rulesetId == "classic-v1", "Classic ends at once at checkmate and never starts a duel")
	# Serialization under the royal contract; v1 stays closed to royal payloads.
	var a = Auth.new()
	var g = fresh(BOTH, a)
	expect(royal_codec.valid("RoyalSequenceRequest", g.royal_request()) and royal_codec.valid("RoyalDuelRequest", g.royal_duel_request()) and royal_codec.valid("RoyalSequenceProgress", g.royal_progress()), "request, duel and progress are valid royal payloads")
	var state = g.match_state()
	expect(royal_codec.valid("RoyalMatchState", state) and not v1.valid("MatchState", state) and state.rulesetId == "battle-royal-v1" and state.royal.duelCount == 2, "match state is a RoyalMatchState and not a v1 MatchState")
	expect(not v1.valid("BattleRequest", g.pending_request()) and royal_codec.valid("RoyalBattleRequest", g.pending_request()), "the king duel is a RoyalBattleRequest, never a v1 BattleRequest")
	var round = royal_codec.decode("RoyalMatchState", JSON.stringify(state, "", true, true))
	expect(round.ok and JSON.stringify(round.value, "", true, true) == JSON.stringify(JSON.parse_string(JSON.stringify(state, "", true, true)), "", true, true), "wire round trip of the pending state")
	duel(g, a, true, {"hp": 70, "stamina": 12.5, "cooldownTicks": 90})
	var snap = g.match_state()
	expect(snap.royal.duelIndex == 1 and snap.royal.king == {"hp": 70, "stamina": 12.5, "cooldownTicks": 90} and royal_codec.valid("RoyalMatchState", snap), "mid-sequence state reports the carried King")
	duel(g, a, true, {"hp": 60, "stamina": 2.0, "cooldownTicks": 10})
	var final = g.match_state()
	expect(final.royal == null and final.phase == "board" and royal_codec.valid("RoyalMatchState", final), "after the sequence the state is a plain board state")
	var restart = g.new_game(0, 0, BACK_RANK)
	expect(restart.ok and g.royal_log.is_empty() and not g.royal_active(), "a new game forgets the old sequence log")
