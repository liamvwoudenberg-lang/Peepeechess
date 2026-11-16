extends SceneTree
## Measures the four AI difficulty levels with bot-vs-bot duels through the real CombatSimulation (BOT-measured, not a human claim).
##   godot --headless --fixed-fps 60 --path godot --script res://combat/tools/ai_levels.gd -- n=8 roles=pnr seed=5000 [ref_skill=0.6] [out=file.json]
## For every level: win rate against a fixed reference bot (CombatAI `balanced`, skill ref_skill) over mirror matchups of `roles`, the
## level playing White on even seeds and Black on odd seeds, so seat and attacker bias cancel. A timeout counts as half a win.
## Also: head-to-head Expert vs Easy, Hard vs Normal.

const MAX_TICKS := 6000


## One duel between two AI configs ({level or style/skill/params}); returns 1.0 / 0.0 / 0.5 for config `a`.
static func duel(tree: SceneTree, role: String, a: Variant, b: Variant, seed_value: int) -> float:
	var a_white := seed_value % 2 == 0
	var request := FighterRoster.build_request(role, role, "w" if seed_value % 4 < 2 else "b", "lv-%d" % seed_value, seed_value, 0)
	var sim := CombatSimulation.new()
	tree.root.add_child(sim)
	var started: Dictionary = sim.start(request, {"allow_experimental_roles": true})
	if not started["ok"]:
		sim.get_parent().remove_child(sim)
		sim.queue_free()
		return 0.5
	await tree.physics_frame
	var white_builder := CombatInputBuilder.new(request["matchId"], request["battleId"], "player-white")
	var black_builder := CombatInputBuilder.new(request["matchId"], request["battleId"], "player-black")
	var stats := FighterRoster.stats_for(role)
	var ai_white := AIDifficulty.make_ai(a if a_white else b, white_builder, stats, stats, seed_value * 2 + 1)
	var ai_black := AIDifficulty.make_ai(b if a_white else a, black_builder, stats, stats, seed_value * 2 + 2)
	var guard := 0
	while sim.is_running() and guard < MAX_TICKS:
		var snapshot := sim.snapshot(false)
		sim.submit_input(ai_white.think(snapshot))
		sim.submit_input(ai_black.think(snapshot))
		sim.step_tick()
		guard += 1
	var winner := String(sim.result.get("winnerPlayerId", ""))
	var reason := String(sim.result.get("reason", ""))
	sim.stop()
	sim.get_parent().remove_child(sim)
	sim.queue_free()
	if winner == "" or reason.begins_with("timeout"):
		return 0.5
	return 1.0 if (winner == "player-white") == a_white else 0.0


## Mean score of `a` against `b` over `roles` x `n` seeds.
static func rate(tree: SceneTree, a: Variant, b: Variant, roles: String, n: int, base_seed: int) -> float:
	var total := 0.0
	var count := 0
	for role in roles:
		for i in n:
			total += await duel(tree, String(role), a, b, base_seed + i)
			count += 1
	return total / float(maxi(count, 1))


func _initialize() -> void:
	await process_frame
	var args := {"n": "8", "roles": "pnr", "seed": "5000", "ref_skill": "0.6", "out": ""}
	for token in OS.get_cmdline_user_args():
		var kv := String(token).split("=")
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var reference := {"style": "balanced", "skill": float(args["ref_skill"]), "params": {}}
	var report := {"n": int(args["n"]), "roles": args["roles"], "seed": int(args["seed"]), "reference": reference, "levels": {}}
	for level in AIDifficulty.LEVELS:
		var r: float = await rate(self, level, reference, String(args["roles"]), int(args["n"]), int(args["seed"]))
		report["levels"][level] = r
		print("%-7s vs reference (balanced %.2f): %.0f%%" % [level, float(args["ref_skill"]), r * 100.0])
	report["expert_vs_easy"] = await rate(self, "expert", "easy", String(args["roles"]), int(args["n"]), int(args["seed"]) + 900)
	report["hard_vs_normal"] = await rate(self, "hard", "normal", String(args["roles"]), int(args["n"]), int(args["seed"]) + 1800)
	print("expert vs easy: %.0f%%   hard vs normal: %.0f%%" % [report["expert_vs_easy"] * 100.0, report["hard_vs_normal"] * 100.0])
	if String(args["out"]) != "":
		var file := FileAccess.open(String(args["out"]), FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	quit()
