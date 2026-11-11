extends SceneTree
## The server session owns battle-royal-v1 authoritatively: the real CombatSimulation runs each duel, the SERVER carries the
## King's HP/stamina/cooldown into the next duel, and a client can neither supply nor alter it. Seats are driven by CombatAI
## bots through OnlineMatchSession.input, exactly like network clients (deterministic per seed).
const Session = preload("res://network/server/match_session.gd")
const BACK_RANK = "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1"
const BOTH = "R3k3/3p1p2/8/8/8/8/8/4R1K1 b - - 0 1"
var checks = 0
var failures: Array = []
var now = 1000

class Bots extends RefCounted:
	var ais: Dictionary = {}
	var builders: Dictionary = {}
	var battle_id = ""
	var cfg: Dictionary

	func feed(session, king_cfg: Dictionary, checker_cfg: Dictionary) -> void:
		var sim: CombatSimulation = session.sim
		if sim == null or not sim.is_running():
			return
		var req = sim.request
		if req.battleId != battle_id:
			battle_id = req.battleId
			ais.clear()
			for seat in [req.attacker, req.defender]:
				var builder = CombatInputBuilder.new(req.matchId, req.battleId, seat.playerId)
				var other = req.defender if seat == req.attacker else req.attacker
				var config = king_cfg if seat.role == "k" else checker_cfg
				ais[seat.playerId] = CombatAI.new(builder, seat.stats, other.stats, int(req.seed) * 2 + (1 if seat == req.attacker else 2), float(config.skill), String(config.style))
		var snap = sim.snapshot(false)
		for player_id in ais:
			session.input(ais[player_id].think(snap), player_id)

func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("FAIL: ", label)

func _init() -> void:
	call_deferred("run")

func room(fen: String, ruleset: String = "battle-royal-v1"):
	var s = Session.new()
	root.add_child(s)
	s.configure("royal-room", "battle", "alice", 0, 0, now, ruleset)
	expect(s.join("bob", now).ok, "bob joins")
	s.game.new_game(0, 0, fen) # after the seats are known: a loaded mate binds its duels to the real player ids
	s.game.last_poll = now
	s.command({"action": "ready"}, "alice", now)
	s.command({"action": "ready"}, "bob", now)
	expect(s.status == "active", "both seats ready")
	return s

func mover(s, from: String, to: String, player: String = "alice") -> Dictionary:
	return s.move({"schemaVersion": 1, "matchId": s.game.match_id, "requestId": "m-%s%s" % [from, to], "playerId": player, "expectedRevision": s.game.revision, "from": from, "to": to, "promotion": null}, player, now)

func run_until_idle(s, king_cfg: Dictionary, checker_cfg: Dictionary, limit: int = 20000) -> int:
	var bots = Bots.new()
	var steps = 0
	while steps < limit and s.status == "active" and (s.game.royal_active() or s.game.phase != "board"):
		bots.feed(s, king_cfg, checker_cfg)
		now += 17
		s.step(now)
		steps += 1
	return steps

func run() -> void:
	var skilled = {"style": "duelist", "skill": 0.9}
	var plain = {"style": "balanced", "skill": 0.6}
	# Opt-in: the flag selects the royal match; every other room keeps the legacy match.
	var legacy = Session.new()
	root.add_child(legacy)
	legacy.configure("legacy", "battle", "alice", 0, 0, now)
	expect(not (legacy.game is BattleRoyalMatch) and legacy.game is BattleChessMatch, "default battle rooms stay battle-checkmate-v1")
	var classic = Session.new()
	root.add_child(classic)
	classic.configure("classic", "classic", "alice", 600000, 0, now, "battle-royal-v1")
	expect(not (classic.game is BattleChessMatch), "Classic ignores the ruleset flag and never fights")
	for node in [legacy, classic]:
		node.queue_free()

	# 1. The mating move opens the sequence; the server starts the simulation with the King's options.
	var s = room(BACK_RANK)
	var reply = mover(s, "a1", "a8")
	expect(reply.ok and s.game.royal_active() and s.sim != null and s.sim.is_running(), "the server starts the King duel after the mating move")
	var king_id = s.game.pending_request().attacker.playerId
	expect(king_id == "bob" and s.sim.fighter_state("bob").hp == 160, "the mated seat's King opens at full HP")
	var wrong_phase = mover(s, "g1", "h1")
	expect(not wrong_phase.ok and wrong_phase.error.code == "WRONG_PHASE", "board moves are refused during the sequence")
	var frame = s.frame("alice")
	expect(frame.state.rulesetId == "battle-royal-v1" and frame.state.royal.duelCount == 1 and s.game.royal_codec.valid("RoyalMatchState", frame.state), "the frame state is a RoyalMatchState with progress")
	var forged = CombatInputBuilder.new(s.game.match_id, s.sim.request.battleId, "bob").build(0.0, 0.0, 0.0, true, false, false)
	forged["hp"] = 160
	expect(not s.input(forged, "bob").ok, "a client packet cannot carry health or carried state")
	var steps = run_until_idle(s, skilled, plain)
	expect(steps < 20000, "the duel finishes (%d server ticks)" % steps)
	expect(s.status == "active" and not s.game.royal_active() and s.game.royal_log.size() == 1, "the sequence ran to its end on the server")
	var outcome = s.game.royal_log[0].outcome
	expect(outcome in ["king_survived", "king_fell"] and s.receipts.size() == 1 and s.receipts[0].outcome == ("attacker" if outcome == "king_survived" else "defender"), "one authoritative receipt, consistent with the sequence outcome (%s)" % outcome)
	if outcome == "king_survived":
		expect(s.game.engine.result.is_empty() and s.game.engine.turn == "b" and s.sim == null, "a surviving King: board continues with black to move")
	else:
		expect(s.status == "complete" and s.game.engine.result == "1-0", "a fallen King: checkmate")
	s.queue_free()

	# 2. Two checkers: the SERVER carries the King's state into duel 2 (balanced bot King usually falls, attrition is visible).
	s = room(BOTH)
	expect(s.game.royal_active(), "a loaded mate is fought once the match is live")
	# new_game began the sequence before the seats were live; the first step starts its simulation.
	s.step(now)
	steps = run_until_idle(s, skilled, plain, 30000)
	var log = s.game.royal_log
	expect(log.size() == 1 and log[0].duels.size() >= 1, "the double-check sequence was played (%d ticks)" % steps)
	if log[0].duels.size() == 2:
		expect(log[0].duels[1].kingEnd.hp <= log[0].duels[0].kingEnd.hp, "the King kept its HP between the two server-run duels")
		expect(s.receipts.size() == 2, "a BattleResult receipt per duel")
	expect(s.game.royal_codec.valid("RoyalSequenceResult", log[0]), "the result satisfies the royal contract")
	s.queue_free()

	# 3. Disconnect inside the sequence: the disconnecting seat loses (existing abandonment rules).
	for case in [["bob", "1-0"], ["alice", "0-1"]]:
		s = room(BOTH)
		s.step(now)
		s.set_connected(case[0], false, now)
		s.step(now + 10001)
		expect(s.status == "complete" and s.game.engine.result == case[1] and s.game.engine.reason == "Disconnect timeout", "%s disconnecting during the last stand loses (%s)" % [case[0], case[1]])
		expect(not s.game.royal_active() and s.sim == null and s.game.engine.mate_pending.is_empty(), "the sequence and its simulation are gone")
		expect(s.game.royal_log.size() == 1 and s.game.royal_log[0].outcome == "abandoned", "logged as abandoned")
		s.queue_free()
	# Both gone: a draw. Resignation is the resigner's loss.
	s = room(BOTH)
	s.step(now)
	s.set_connected("alice", false, now)
	s.set_connected("bob", false, now)
	s.step(now + 10001)
	expect(s.game.engine.result == "1/2-1/2" and s.game.engine.reason == "Both players disconnected", "both seats gone: a draw")
	s.queue_free()
	s = room(BOTH)
	s.step(now)
	expect(s.command({"action": "resign"}, "bob", now).ok and s.game.engine.result == "1-0" and s.game.engine.reason == "Resignation", "the mated King's player resigning loses")
	s.queue_free()

	# 4. Missing inputs: a seat that never sends input forfeits through the combat host's abandonment rule.
	s = room(BACK_RANK)
	mover(s, "a1", "a8")
	var idle_steps = 0
	while s.status == "active" and idle_steps < 2000:
		now += 17
		s.step(now)
		idle_steps += 1
	expect(s.status == "complete" and s.game.engine.reason == "Both combat seats abandoned", "no input from either seat: both abandoned, a draw (%d ticks)" % idle_steps)
	s.queue_free()

	await process_frame
	await process_frame
	if failures.is_empty():
		print("PASS: %d royal session checks" % checks)
		quit(0)
	else:
		printerr("FAILED: %d of %d royal session checks" % [failures.size(), checks])
		quit(1)
