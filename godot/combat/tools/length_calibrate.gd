extends SceneTree
## Finds, for every attacker/defender pairing, the duel-length scale (the multiplier on HP damage, see BALANCE.md "Duel length") that
## makes a duel last about `target` seconds of actual fighting (the 3 s countdown is not counted). BOT-measured: a casual and a skilled
## bot play the pairing and the score is the geometric mean of their MEDIAN fight lengths (so neither bot's very long or very short
## duels decide it alone). The attacker's edge table is whatever the loaded balance data holds; the stamina rule is the data's too.
##
##   godot --headless --path godot --script res://combat/tools/length_calibrate.gd -- \
##       target=25 n=12 iterations=5 seed=30000 shard=0/2 out=/tmp/len-0.json [roles=pnbrq] [pairs=pq,qp]
##
## The length falls roughly like 1/scale (a bit steeper: a longer fight gives both seats time to regain stamina), so it is found with a
## secant search on log(scale) with fixed seeds. A scale never goes above 1.0 (this tool lengthens duels, it never shortens them below
## the raw frame data) and never below 0.05. Merge the shard files with merge_length.py, then re-check the attacker win rates with
## attacker_matrix.gd on DIFFERENT seeds.
const Duel := preload("res://combat/tools/attacker_duel.gd")
const Balance := preload("res://combat/data/balance_data.gd")
const CONFIGS := [{"style": "balanced", "skill": 0.6}, {"style": "duelist", "skill": 0.9}]
const S_MIN := 0.05
const S_MAX := 1.0
const TOLERANCE := 0.08   # stop when the score is within 8% of the target


## {score, medians: [casual, skilled], timeouts: [casual, skilled]} for scale s.
func _measure(a: String, d: String, s: float, n: int, seed_value: int) -> Dictionary:
	var medians: Array = []
	var timeouts: Array = []
	for cfg in CONFIGS:
		var lengths: Array = []
		var timed_out := 0
		for i in n:
			var r: Dictionary = await Duel.duel(self, a, d, cfg, seed_value + i, {"damage_scale": s})
			lengths.append(float(r["active_ticks"]) / 60.0)
			if String(r["reason"]).begins_with("timeout"):
				timed_out += 1
		lengths.sort()
		medians.append(float(lengths[n / 2]) if n % 2 == 1 else (float(lengths[n / 2 - 1]) + float(lengths[n / 2])) / 2.0)
		timeouts.append(timed_out)
	return {"score": sqrt(maxf(0.01, float(medians[0])) * maxf(0.01, float(medians[1]))), "medians": medians, "timeouts": timeouts}


func _initialize() -> void:
	await process_frame
	var args := {"target": "25", "n": "12", "iterations": "5", "seed": "30000", "out": "", "roles": "pnbrq", "shard": "0/1", "pairs": "", "start": "0.3"}
	for token in OS.get_cmdline_user_args():
		var kv: PackedStringArray = String(token).split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var target := float(args["target"])
	var n := int(args["n"])
	var iterations := int(args["iterations"])
	var base_seed := int(args["seed"])
	var pairs: Array = []
	if String(args["pairs"]) != "":
		for pair in String(args["pairs"]).split(","):
			pairs.append([pair.substr(0, 1), pair.substr(1, 1)])
	else:
		for a in String(args["roles"]):
			for d in String(args["roles"]):
				pairs.append([a, d])
	var shard := String(args["shard"]).split("/")
	var out := {"target": target, "n": n, "iterations": iterations, "seed": base_seed, "tuning": Balance.stamp(), "pairs": {}}
	var started := Time.get_ticks_msec()
	for i in pairs.size():
		if i % int(shard[1]) != int(shard[0]):
			continue
		var a: String = pairs[i][0]
		var d: String = pairs[i][1]
		var s := clampf(float(args["start"]), S_MIN, S_MAX)
		var best := {}
		var best_err := 1e9
		var prev_s := -1.0
		var prev_score := -1.0
		var used := 0
		var note := ""
		for it in iterations:
			var m: Dictionary = await _measure(a, d, s, n, base_seed)
			used += 1
			var err := absf(log(float(m["score"]) / target))
			if err < best_err:
				best_err = err
				best = m.duplicate()
				best["scale"] = s
			if err <= TOLERANCE:
				break
			# slope of ln(length) against ln(scale): about -1; measured when two points exist, kept within a sane range
			var slope := -1.0
			if prev_s > 0.0 and absf(log(s / prev_s)) > 0.02:
				slope = clampf((log(float(m["score"])) - log(prev_score)) / (log(s) - log(prev_s)), -1.8, -0.35)
			prev_s = s
			prev_score = float(m["score"])
			var next_s := clampf(exp(log(s) + (log(target) - log(float(m["score"]))) / slope), S_MIN, S_MAX)
			if is_equal_approx(next_s, s):
				note = "scale limit reached (length %.1f s at scale %.2f)" % [float(m["score"]), s]
				break
			s = next_s
		out["pairs"][a + d] = {"scale": snappedf(float(best["scale"]), 0.001), "score": snappedf(float(best["score"]), 0.1),
				"median_casual": snappedf(float(best["medians"][0]), 0.1), "median_skilled": snappedf(float(best["medians"][1]), 0.1),
				"timeouts_casual": best["timeouts"][0], "timeouts_skilled": best["timeouts"][1], "evaluations": used,
				"within_tolerance": best_err <= TOLERANCE, "note": note}
		print("%s attacks %s: scale %.3f -> %.1f s (casual %.1f, skilled %.1f; timeouts %d/%d) after %d evaluations %s[%d s]" % [a, d, float(best["scale"]),
				float(best["score"]), float(best["medians"][0]), float(best["medians"][1]), best["timeouts"][0], best["timeouts"][1], used,
				("(target missed) " if best_err > TOLERANCE else ""), (Time.get_ticks_msec() - started) / 1000])
	if String(args["out"]) != "":
		var file := FileAccess.open(String(args["out"]), FileAccess.WRITE)
		file.store_string(JSON.stringify(out, "\t", true))
	quit(0)
