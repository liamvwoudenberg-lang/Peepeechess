extends SceneTree
## Anti-mash acceptance harness (BOT-measured, see BALANCE.md "Anti-mash"). One process, deterministic seeds, compact output.
##
##   godot --headless --path godot --script res://combat/tools/anti_mash.gd -- mode=skill n=40 roles=pnbrq [seed=7000] [am=off] [out=/tmp/x.json]
##   godot --headless --path godot --script res://combat/tools/anti_mash.gd -- mode=matrix n=20 skill=0.9 style=duelist [pairs=pq,np] [am=off]
##
## mode=skill : the timing bot (skill 0.9) against the masher on EQUAL stats (same role both sides); the attacker seat alternates
##              with the seed. Prints the timing bot's win rate per role.
## mode=matrix: equal-skill bots (same style/skill both seats), role A vs role B over both attacker seats; prints A's win rate, the
##              attacker's win rate, median duel length (s) and timeouts. With no pairs= it plays every unordered role pair + mirrors.
## am=off switches the anti-mash rules off (the before-numbers for the notes).
const Balance := preload("res://combat/data/balance_data.gd")
const Duel := preload("res://combat/tools/attacker_duel.gd")


func _initialize() -> void:
	await process_frame
	var args := {"mode": "skill", "n": "40", "seed": "7000", "roles": "pnbrq", "skill": "0.9", "style": "duelist", "pairs": "", "am": "on", "out": "", "shard": "0/1"}
	for token in OS.get_cmdline_user_args():
		var kv: PackedStringArray = String(token).split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var n := int(args["n"])
	var base := int(args["seed"])
	var options := {"anti_mash": String(args["am"]) != "off"}   # explicit: the balance flag is OFF by default
	var out := {"tuning": Balance.stamp(), "mode": args["mode"], "n": n, "rows": {}}
	if String(args["mode"]) == "skill":
		var timing := {"style": "timing", "skill": 0.9}
		var masher := {"style": "masher", "skill": 0.6}
		for role in String(args["roles"]):
			var wins := 0
			var timeouts := 0
			var lengths: Array = []
			for i in n:
				var timing_attacks := i % 2 == 0
				var r: Dictionary = await Duel.duel(self, role, role, timing if timing_attacks else masher, base + i, options, masher if timing_attacks else timing)
				var attacker_won: bool = r["outcome"] == "attacker"
				if attacker_won == timing_attacks and r["outcome"] != "unfinished":
					wins += 1
				if String(r["reason"]).begins_with("timeout"):
					timeouts += 1
				lengths.append(float(r["active_ticks"]) / 60.0)
			lengths.sort()
			out["rows"][role] = {"timing_wins": wins, "timeouts": timeouts, "median_s": snappedf(float(lengths[n / 2]), 0.1)}
			print("timing vs masher (%s mirror): %d/%d = %.0f%%, timeouts %d, median %.1f s" % [role, wins, n, 100.0 * wins / n, timeouts, float(lengths[n / 2])])
	else:
		var cfg := {"style": String(args["style"]), "skill": float(args["skill"])}
		var pairs: Array = []
		if String(args["pairs"]) != "":
			for p in String(args["pairs"]).split(","):
				pairs.append([p.substr(0, 1), p.substr(1, 1)])
		else:
			var roles: String = args["roles"]
			for i in roles.length():
				for j in range(i, roles.length()):
					pairs.append([roles[i], roles[j]])
		var shard := String(args["shard"]).split("/")
		var totals := {"att": 0, "games": 0, "timeouts": 0}
		for idx in pairs.size():
			if idx % int(shard[1]) != int(shard[0]):
				continue
			var pair: Array = pairs[idx]
			var a_wins := 0
			var att_wins := 0
			var timeouts := 0
			var lengths: Array = []
			for i in n:
				var a_attacks := i % 2 == 0
				var r: Dictionary = await Duel.duel(self, pair[0] if a_attacks else pair[1], pair[1] if a_attacks else pair[0], cfg, base + i, options)
				var attacker_won: bool = r["outcome"] == "attacker"
				if attacker_won:
					att_wins += 1
				if attacker_won == a_attacks and r["outcome"] != "unfinished":
					a_wins += 1
				if String(r["reason"]).begins_with("timeout"):
					timeouts += 1
				lengths.append(float(r["active_ticks"]) / 60.0)
			lengths.sort()
			totals["att"] += att_wins
			totals["games"] += n
			totals["timeouts"] += timeouts
			out["rows"][pair[0] + pair[1]] = {"a_wins": a_wins, "attacker_wins": att_wins, "timeouts": timeouts, "median_s": snappedf(float(lengths[n / 2]), 0.1)}
			print("%s vs %s: %s wins %.0f%%, attacker %.0f%%, timeouts %d, median %.1f s" % [pair[0], pair[1], pair[0], 100.0 * a_wins / n, 100.0 * att_wins / n, timeouts, float(lengths[n / 2])])
		print("TOTAL attacker %.1f%% of %d, timeouts %.1f%%" % [100.0 * totals["att"] / maxi(1, totals["games"]), totals["games"], 100.0 * totals["timeouts"] / maxi(1, totals["games"])])
	if String(args["out"]) != "":
		var file := FileAccess.open(String(args["out"]), FileAccess.WRITE)
		file.store_string(JSON.stringify(out, "\t", true))
	quit(0)
