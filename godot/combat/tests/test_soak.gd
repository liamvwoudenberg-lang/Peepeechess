extends RefCounted
## Soak: AI-vs-AI full-length matches through the real input channel. Checks that whole fights
## terminate with a valid BattleResult, that every sampled snapshot stays schema-valid and in
## bounds, that no input is rejected, and that the same inputs always give the same fight.
## Outcome statistics are printed for information; they are NOT a balance claim.

const Codec := preload("res://contracts/codec.gd")

const MATCHES: Array = [
	# white role, black role, attacker, seed
	["p", "p", "w", 1], ["p", "n", "w", 2], ["n", "p", "b", 3], ["n", "n", "w", 4],
	["p", "n", "b", 5], ["n", "p", "w", 6],
]


static func run(h, tree: SceneTree) -> void:
	await _soak(h, tree)
	await _determinism(h, tree)


static func _play(tree: SceneTree, white: String, black: String, attacker: String, seed_value: int) -> Dictionary:
	var codec = Codec.new()
	var sim := CombatSimulation.new()
	tree.root.add_child(sim)
	var battle_id := "soak-%d" % seed_value
	var request := FighterRoster.build_request(white, black, attacker, battle_id, seed_value, 0)
	var started: Dictionary = sim.start(request)
	await tree.physics_frame
	var white_builder := CombatInputBuilder.new(request["matchId"], battle_id, "player-white")
	var black_builder := CombatInputBuilder.new(request["matchId"], battle_id, "player-black")
	var ai_white := CombatAI.new(white_builder, FighterRoster.stats_for(white), FighterRoster.stats_for(black), seed_value * 2 + 1, 0.7)
	var ai_black := CombatAI.new(black_builder, FighterRoster.stats_for(black), FighterRoster.stats_for(white), seed_value * 2 + 2, 0.6)

	var report := {"started": started["ok"], "rejected": 0, "invalid_snapshots": 0, "out_of_bounds": 0,
			"ticks": 0, "counts": {}, "max_radius": 0.0, "min_gap": 99.0}
	var guard := 0
	while sim.is_running() and guard < 6000:
		var snap := sim.snapshot()
		for pair in [[ai_white, "player-white"], [ai_black, "player-black"]]:
			var reply: Dictionary = sim.submit_input(pair[0].think(snap))
			if not reply["ok"]:
				report["rejected"] += 1
		sim.step_tick()
		guard += 1
		if guard % 45 == 0 and not codec.valid("CombatSnapshot", sim.snapshot()):
			report["invalid_snapshots"] += 1
		for fighter in sim.fighters:
			var p: Vector3 = fighter.global_position
			report["max_radius"] = maxf(report["max_radius"], Vector2(p.x, p.z).length())
			if fighter.health.current < 0 or fighter.health.current > fighter.health.maximum \
					or fighter.stamina.current < 0.0 or fighter.stamina.current > fighter.stamina.maximum + 0.001 \
					or Vector2(p.x, p.z).length() > CombatConstants.ARENA_WALK_RADIUS + 0.001:
				report["out_of_bounds"] += 1
		var gap: float = sim.fighters[0].global_position.distance_to(sim.fighters[1].global_position)
		if sim.phase == CombatSimulation.Phase.ACTIVE:
			report["min_gap"] = minf(report["min_gap"], gap)
	for event in sim.recent_events:
		report["counts"][event["type"]] = int(report["counts"].get(event["type"], 0)) + 1
	report["ticks"] = guard
	report["result"] = sim.result.duplicate(true)
	report["final_snapshot"] = JSON.stringify(sim.snapshot(), "", true, true)
	report["result_valid"] = codec.valid("BattleResult", sim.result) if not sim.result.is_empty() else false
	report["total_events"] = sim._next_event_id - 1
	sim.stop()
	sim.get_parent().remove_child(sim)
	sim.queue_free()
	return report


static func _soak(h, tree: SceneTree) -> void:
	var wins := {"attacker": 0, "defender": 0}
	var reasons := {}
	for spec in MATCHES:
		var label := "%s(w) vs %s(b), attacker %s, seed %d" % [spec[0], spec[1], spec[2], spec[3]]
		h.begin("soak: " + label)
		var r: Dictionary = await _play(tree, spec[0], spec[1], spec[2], spec[3])
		h.check(r["started"], "battle started")
		h.check(not r["result"].is_empty(), "the fight terminated with a result")
		h.check(r["result_valid"], "the BattleResult is schema-valid")
		h.eq(r["rejected"], 0, "the AI never had an input rejected")
		h.eq(r["invalid_snapshots"], 0, "every sampled snapshot is schema-valid")
		h.eq(r["out_of_bounds"], 0, "HP, stamina and positions stayed in bounds")
		# The 24-sided wall's inner faces are tangent to the 7.1 m circle, so a fighter can legitimately stand in a corner up to
		# 7.1 / cos(pi / 24) from the centre minus their radius (test_roles.gd uses the same bound). The original bound 7.1 - 0.37 was only
		# ever met because the short duels never reached a corner; the longer duels (BALANCE.md "Duel length") do, at 6.78 m.
		h.check(float(r["max_radius"]) <= CombatConstants.ARENA_WALL_RADIUS / 0.99144486 - 0.37, "nobody ever got through the arena wall (max radius %.2f)" % float(r["max_radius"]))
		h.check(float(r["min_gap"]) >= 0.74, "fighters never overlapped (closest %.2f m)" % float(r["min_gap"]))
		h.check(int(r["ticks"]) <= 180 + 5400, "ended within the time limit (%d ticks)" % int(r["ticks"]))
		# More than a single event: with the attacker's advantage a Pawn can end a Knight in two hits (3 events). The invariants above
		# (no rejected input, bounds, a valid result) are what this soak is for.
		h.check(int(r["total_events"]) > 1, "the fight actually happened (%d events)" % int(r["total_events"]))
		if not r["result"].is_empty():
			wins[r["result"]["outcome"]] += 1
			reasons[r["result"]["reason"]] = int(reasons.get(r["result"]["reason"], 0)) + 1
			print("  %s -> %s wins by %s at tick %d (HP %d vs %d)" % [label, r["result"]["outcome"], r["result"]["reason"],
					int(r["result"]["resolvedTick"]), int(r["result"]["attackerHp"]), int(r["result"]["defenderHp"])])
	print("  soak summary (informational, not a balance claim): outcomes %s, reasons %s" % [str(wins), str(reasons)])


static func _determinism(h, tree: SceneTree) -> void:
	h.begin("determinism: identical inputs reproduce the identical fight")
	var a: Dictionary = await _play(tree, "p", "n", "w", 21)
	var b: Dictionary = await _play(tree, "p", "n", "w", 21)
	h.eq(a["final_snapshot"], b["final_snapshot"], "final snapshots are byte-identical")
	h.eq(JSON.stringify(a["result"]), JSON.stringify(b["result"]), "results are identical")
	h.eq(a["total_events"], b["total_events"], "event counts are identical")
	var c: Dictionary = await _play(tree, "p", "n", "w", 22)
	h.check(a["final_snapshot"] != c["final_snapshot"], "a different seed gives a different fight (the check is not vacuous)")
