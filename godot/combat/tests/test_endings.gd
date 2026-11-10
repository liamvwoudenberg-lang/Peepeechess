extends RefCounted
## Defeat conditions and the BattleResult: knockouts, double knockout, timeout by HP percentage
## (exact cross-multiplication), tie-to-defender, tick accounting, restart.

const Support := preload("res://combat/tests/test_support.gd")
const Codec := preload("res://contracts/codec.gd")
const S := CombatConstants.State


static func run(h, tree: SceneTree) -> void:
	await _knockouts(h, tree)
	await _double_ko(h, tree)
	await _timeouts(h, tree)
	await _restart(h, tree)
	await _event_log(h, tree)


static func _knockouts(h, tree: SceneTree) -> void:
	var codec = Codec.new()
	h.begin("defeat: attacker knocks out the defender -> attacker wins by knockout")
	var rig = await Support.make_rig(tree, "p", "p", "w", 300)
	rig.face_off()
	rig.to_live()
	rig.black().health.current = 5
	rig.w.press("light")
	rig.tick()
	var finished_in: int = rig.until(func(): return rig.sim.phase == CombatSimulation.Phase.FINISHED, 60)
	h.check(finished_in >= 0, "the fight ends")
	var result: Dictionary = rig.sim.result
	h.eq(result["outcome"], "attacker", "outcome")
	h.eq(result["reason"], "knockout", "reason")
	h.eq(result["winnerPlayerId"], "player-white", "winner is the attacker's player")
	h.eq(result["attackerHp"], 80, "attacker HP in the result")
	h.eq(result["defenderHp"], 0, "defender HP in the result")
	h.eq(result["resolvedTick"], rig.sim.server_tick, "resolved on the knockout tick")
	h.eq(result["expectedRevision"], 1, "carries the request's expectedRevision")
	h.check(codec.valid("BattleResult", result), "the result is a valid BattleResult")
	h.eq(rig.black().sm.state, S.DEFEATED, "the loser is in the Defeated state")
	h.eq(rig.black().collision_layer, 0, "a defeated fighter is no longer solid")
	h.check(codec.valid("CombatSnapshot", rig.sim.snapshot()), "the final snapshot is valid")
	h.check(rig.sim.snapshot()["result"] != null, "and carries the terminal result")
	var stopped_at: int = rig.sim.server_tick
	rig.tick(30)
	h.eq(rig.sim.server_tick, stopped_at, "the clock stops once the battle is decided")
	h.eq(rig.sim.submit_input(rig.w.packet())["code"], "WRONG_PHASE", "inputs after the result are refused")
	rig.dispose()

	h.begin("defeat: defender knocks out the attacker -> defender wins")
	rig = await Support.make_rig(tree, "p", "p")
	rig.face_off()
	rig.to_live()
	rig.white().health.current = 5
	rig.b.press("light")
	rig.tick()
	rig.until(func(): return rig.sim.phase == CombatSimulation.Phase.FINISHED, 60)
	h.eq(rig.sim.result["outcome"], "defender", "outcome")
	h.eq(rig.sim.result["winnerPlayerId"], "player-black", "winner is the defender's player")
	h.eq(rig.sim.result["reason"], "knockout", "reason")
	rig.dispose()

	h.begin("defeat: attacker/defender are independent of White/Black")
	rig = await Support.make_rig(tree, "p", "n", "b")
	rig.face_off()
	rig.to_live()
	rig.white().health.current = 1  # White is the defender here
	rig.b.press("light")
	rig.tick()
	rig.until(func(): return rig.sim.phase == CombatSimulation.Phase.FINISHED, 80)
	h.eq(rig.sim.result["outcome"], "attacker", "the Black-seat attacker won")
	h.eq(rig.sim.result["winnerPlayerId"], "player-black", "winner id is the Black seat")
	h.eq(rig.sim.result["attackerHp"], 125, "attackerHp is the knight's (Black) HP")
	h.eq(rig.sim.result["defenderHp"], 0, "defenderHp is the pawn's (White) HP")
	rig.dispose()

	h.begin("defeat: a guard break that deals the last point of damage also ends the fight")
	rig = await Support.make_rig(tree, "p", "p")
	rig.face_off()
	rig.to_live()
	rig.black().health.current = 3
	rig.black().stamina.lose(118.0)
	rig.b.block = true
	rig.w.press("light")
	rig.tick()
	rig.until(func(): return rig.sim.phase == CombatSimulation.Phase.FINISHED, 60)
	h.eq(rig.sim.result["reason"], "knockout", "chip damage from a guard break can kill")
	h.eq(rig.sim.result["outcome"], "attacker", "attacker wins")
	rig.dispose()


static func _double_ko(h, tree: SceneTree) -> void:
	h.begin("defeat: both fighters landing a killing blow on the same tick is a double knockout")
	var codec = Codec.new()
	var rig = await Support.make_rig(tree, "p", "p")
	rig.face_off()
	rig.to_live()
	rig.white().health.current = 1
	rig.black().health.current = 1
	rig.w.press("light")
	rig.b.press("light")
	rig.tick()
	rig.until(func(): return rig.sim.phase == CombatSimulation.Phase.FINISHED, 60)
	h.eq(rig.sim.result["reason"], "double_knockout", "reason")
	h.eq(rig.sim.result["outcome"], "defender", "a double knockout goes to the defender (CONTRACTS.md rule 7)")
	h.eq(rig.sim.result["winnerPlayerId"], "player-black", "winner is the defender's player")
	h.eq(rig.sim.result["attackerHp"], 0, "attacker HP 0")
	h.eq(rig.sim.result["defenderHp"], 0, "defender HP 0")
	h.check(codec.valid("BattleResult", rig.sim.result), "valid BattleResult")
	rig.dispose()


static func _run_to_timeout(rig) -> void:
	rig.to_live()
	rig.tick(CombatConstants.DURATION_TICKS)


static func _timeouts(h, tree: SceneTree) -> void:
	var codec = Codec.new()
	h.begin("timeout: equal HP percentage is a tie that favours the defender; no randomness")
	var rig = await Support.make_rig(tree, "p", "p", "w", 300)
	rig.place(Vector3(-4.0, 0.0, 0.0), Vector3(4.0, 0.0, 0.0))
	await _run_to_timeout(rig)
	var result: Dictionary = rig.sim.result
	h.eq(rig.sim.phase, CombatSimulation.Phase.FINISHED, "the fight ended at the time limit")
	h.eq(result["reason"], "timeout_tie", "reason")
	h.eq(result["outcome"], "defender", "outcome")
	h.eq(result["resolvedTick"], 300 + 180 + 5400, "resolved exactly startTick + 180 countdown + 5400 active ticks")
	h.check(codec.valid("BattleResult", result), "valid BattleResult")
	h.eq(rig.sim.snapshot()["durationTicksRemaining"], 0, "no active time left")
	rig.dispose()

	h.begin("timeout: the higher remaining-HP percentage wins")
	rig = await Support.make_rig(tree, "p", "p")
	rig.place(Vector3(-4.0, 0.0, 0.0), Vector3(4.0, 0.0, 0.0))
	rig.white().health.current = 40
	rig.black().health.current = 30
	await _run_to_timeout(rig)
	h.eq(rig.sim.result["reason"], "timeout_hp", "reason")
	h.eq(rig.sim.result["outcome"], "attacker", "40/80 beats 30/80")
	h.eq(rig.sim.result["winnerPlayerId"], "player-white", "winner")
	rig.dispose()

	rig = await Support.make_rig(tree, "p", "p")
	rig.place(Vector3(-4.0, 0.0, 0.0), Vector3(4.0, 0.0, 0.0))
	rig.white().health.current = 79
	await _run_to_timeout(rig)
	h.eq(rig.sim.result["outcome"], "defender", "79/80 loses to a full-health defender")
	h.eq(rig.sim.result["reason"], "timeout_hp", "reason")
	rig.dispose()

	h.begin("timeout: percentages are compared exactly across different maximum HP")
	rig = await Support.make_rig(tree, "p", "n")  # pawn 80 max (attacker), knight 125 max
	rig.place(Vector3(-4.0, 0.0, 0.0), Vector3(4.0, 0.0, 0.0))
	rig.white().health.current = 16  # 20%
	rig.black().health.current = 25  # 20%: 16*125 == 25*80
	await _run_to_timeout(rig)
	h.eq(rig.sim.result["reason"], "timeout_tie", "16/80 == 25/125 exactly: a tie")
	h.eq(rig.sim.result["outcome"], "defender", "ties favour the defender")
	rig.dispose()

	rig = await Support.make_rig(tree, "p", "n")
	rig.place(Vector3(-4.0, 0.0, 0.0), Vector3(4.0, 0.0, 0.0))
	rig.white().health.current = 40  # 50.0%
	rig.black().health.current = 62  # 49.6%
	await _run_to_timeout(rig)
	h.eq(rig.sim.result["outcome"], "attacker", "50.0% beats 49.6%")
	rig.dispose()

	rig = await Support.make_rig(tree, "p", "n")
	rig.place(Vector3(-4.0, 0.0, 0.0), Vector3(4.0, 0.0, 0.0))
	rig.white().health.current = 40  # 50.0%
	rig.black().health.current = 63  # 50.4%
	await _run_to_timeout(rig)
	h.eq(rig.sim.result["outcome"], "defender", "50.4% beats 50.0%")
	h.eq(rig.sim.result["reason"], "timeout_hp", "decided by HP, not a tie")
	rig.dispose()

	h.begin("timeout: a knockout shortly before the time limit is decided as a knockout, not a timeout")
	rig = await Support.make_rig(tree, "p", "p")
	rig.face_off()
	rig.to_live()
	rig.tick(CombatConstants.DURATION_TICKS - 12)
	rig.black().health.current = 2
	rig.w.press("light")
	rig.tick(12)
	h.eq(rig.sim.result["reason"], "knockout", "HP reaching zero is decided as a knockout, not a timeout")
	rig.dispose()


static func _restart(h, tree: SceneTree) -> void:
	h.begin("restart: a finished fight can be started again from a fresh request")
	var rig = await Support.make_rig(tree, "p", "n", "w", 0, "round-1")
	rig.face_off()
	rig.to_live()
	rig.black().health.current = 1
	rig.w.press("light")
	rig.tick()
	rig.until(func(): return rig.sim.phase == CombatSimulation.Phase.FINISHED, 60)
	h.eq(rig.sim.result["battleId"], "round-1", "round 1 is decided")
	var old_packet: Dictionary = rig.w.packet()

	var reply: Dictionary = rig.sim.start(FighterRoster.build_request("p", "n", "w", "round-2", 99, 6000))
	h.check(reply["ok"], "a new battle starts after the old one finished")
	await tree.physics_frame
	h.eq(rig.sim.phase, CombatSimulation.Phase.COUNTDOWN, "countdown restarts")
	h.eq(rig.sim.server_tick, 6000, "serverTick follows the new request's startTick")
	h.check(rig.sim.result.is_empty(), "the old result is cleared")
	h.eq(rig.black().health.current, 125, "HP is fresh")
	h.near(rig.white().stamina.current, 120.0, 0.001, "stamina is fresh")
	h.eq(rig.white().ability.cooldown_remaining, 0, "cooldowns are fresh")
	h.eq(rig.sim.recent_events.size(), 0, "the event log starts empty")
	h.eq(rig.sim.submit_input(old_packet)["code"], "FORBIDDEN", "inputs addressed to the old battle are refused")
	h.near(rig.white().global_position.z, -2.6, 0.0001, "fighters are back at their spawns")
	h.eq(rig.sim.get_child_count(), 3, "the old fighters and arena were removed (arena + 2 fighters remain)")
	rig.dispose()


static func _event_log(h, tree: SceneTree) -> void:
	h.begin("events: ids are strictly increasing and the log stays bounded")
	var codec = Codec.new()
	var rig = await Support.make_rig(tree, "p", "p")
	rig.face_off()
	rig.to_live()
	for i in 40:
		rig.w.press("light")
		rig.tick(18)
	var last: int = 0
	var increasing := true
	for event in rig.sim.recent_events:
		if int(event["eventId"]) <= last:
			increasing = false
		last = int(event["eventId"])
	h.check(increasing, "eventId strictly increases")
	h.check(rig.sim.recent_events.size() <= CombatConstants.EVENT_HISTORY, "history is bounded")
	h.check(codec.valid("CombatSnapshot", rig.sim.snapshot()), "a snapshot full of events is still valid")
	rig.dispose()
