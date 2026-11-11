extends SceneTree
## Bot-measured win-rate matrix for the six-class roster (NOT a human balance claim - see BALANCE.md).
##
##   godot --headless --path godot --script res://combat/tools/balance_matrix.gd -- \
##       n=8 seed=1000 out=/tmp/matrix_a.json pairs=pn,pb,pr      # pairs optional: all 36 ordered pairs when omitted
##
## For every ordered pair (A, B) it plays, per style/skill config of A, `n` seeded fights against the baseline AI of B
## (balanced, skill 0.6) and records wins/timeouts. "best" is the best config's win rate (>= 0.5 means the pair is
## winnable). It also records the mirror baseline (A balanced/0.6 vs B balanced/0.6) and the skilled mirror
## (A duelist/0.9 vs B duelist/0.9 and patient/0.9 vs patient/0.9). Split `pairs` over processes to
## use several cores; merge the per-shard JSON `pairs` objects by hand or with a short script.

const Runner := preload("res://combat/tests/matchup_runner.gd")


func _initialize() -> void:
	await process_frame
	var args := {"n": "8", "seed": "1000", "out": "", "pairs": "", "roles": "pnbrqk"}
	for token in OS.get_cmdline_user_args():
		var kv: PackedStringArray = String(token).split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var n := int(args["n"])
	var base_seed := int(args["seed"])
	var pairs: Array = []
	if String(args["pairs"]) != "":
		for p in String(args["pairs"]).split(","):
			pairs.append([p.substr(0, 1), p.substr(1, 1)])
	else:
		for a in String(args["roles"]):
			for b in String(args["roles"]):
				pairs.append([a, b])
	var out := {"n": n, "seed": base_seed, "tuning": preload("res://combat/data/balance_data.gd").stamp(), "pairs": {}}
	var started := Time.get_ticks_msec()
	for pair in pairs:
		var a: String = pair[0]
		var b: String = pair[1]
		var entry := {"mirror": {}, "configs": [], "best": {}}
		entry["mirror"] = await Runner.series(self, a, b, Runner.BASELINE, Runner.BASELINE, n, base_seed)
		# Skilled mirror: both sides play the same skilled style (the closest thing to a power ranking among experts).
		entry["skilled"] = {}
		for style in ["duelist", "patient"]:
			var cfg := {"style": style, "skill": 0.9}
			entry["skilled"][style] = await Runner.series(self, a, b, cfg, cfg, n, base_seed)
		var best := {"wins": -1}
		for skill in Runner.SKILLS:
			for style in Runner.STYLES:
				var cfg := {"style": style, "skill": skill}
				var s: Dictionary = await Runner.series(self, a, b, cfg, Runner.BASELINE, n, base_seed)
				var row := {"style": style, "skill": skill, "wins": s["wins"], "played": s["played"], "timeouts": s["timeouts"]}
				entry["configs"].append(row)
				if int(row["wins"]) > int(best["wins"]):
					best = row
		entry["best"] = best
		out["pairs"][a + b] = entry
		print("%s vs %s: best %s/%.1f %d/%d (mirror %d/%d) [%d s]" % [a, b, best["style"], best["skill"], best["wins"], n,
				entry["mirror"]["wins"], n, (Time.get_ticks_msec() - started) / 1000])
	if String(args["out"]) != "":
		var f := FileAccess.open(String(args["out"]), FileAccess.WRITE)
		f.store_string(JSON.stringify(out, "\t", true))
	quit(0)
