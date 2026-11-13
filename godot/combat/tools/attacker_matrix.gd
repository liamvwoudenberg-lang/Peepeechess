extends SceneTree
## Attacker-versus-defender win rates, BOT-measured (not a human balance claim, see BALANCE.md).
##
##   godot --headless --path godot --script res://combat/tools/attacker_matrix.gd -- \
##       n=24 seed=9000 style=balanced skill=0.6 out=/tmp/att.json [roles=pnbrq] [shard=0/4] [pairs=pq,qp] [edge=off] [stamina=0,1.5,0.6]
##
## For every ordered pair (A attacks D) it plays `n` seeded fights between the SAME bot config on both sides (so skill cancels
## out and what is left is the roles and the attacker/defender rules). Role A is always the attacker; the seat colour alternates
## with the seed so a positional bias cancels. It records how often the attacker wins, how often the defender holds, timeouts,
## the average length and the average HP fraction the winner had left (a fight decided by 5 HP is not a decisive fight).
## `shard=i/k` plays every k-th pair, so several processes can share the work and the JSON files can be merged.
## `tuning=` is printed from the loaded balance data so every number is traceable to the data it was measured against.

const Balance := preload("res://combat/data/balance_data.gd")
const Duel := preload("res://combat/tools/attacker_duel.gd")


func _initialize() -> void:
	await process_frame
	var args := {"n": "24", "seed": "9000", "style": "balanced", "skill": "0.6", "out": "", "roles": "pnbrq", "shard": "0/1", "pairs": "", "edge": "data", "stamina": ""}
	for token in OS.get_cmdline_user_args():
		var kv: PackedStringArray = String(token).split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var n := int(args["n"])
	var base_seed := int(args["seed"])
	var cfg := {"style": String(args["style"]), "skill": float(args["skill"])}
	var pairs: Array = []
	if String(args["pairs"]) != "":
		for pair in String(args["pairs"]).split(","):
			pairs.append([pair.substr(0, 1), pair.substr(1, 1)])
	else:
		for a in String(args["roles"]):
			for d in String(args["roles"]):
				pairs.append([a, d])
	var shard := String(args["shard"]).split("/")
	var kept: Array = []
	for i in pairs.size():
		if i % int(shard[1]) == int(shard[0]):
			kept.append(pairs[i])
	# edge=data (default): the game's rule, the balance data's attacker advantage. edge=off: raw frame data, no advantage.
	var options := {"attacker_edge": false} if String(args["edge"]) == "off" else {}
	if String(args["stamina"]) != "":
		# stamina=<attacker cost>,<defender cost>,<defender regen>: stamina rule on its own (damage multipliers off), for sweeps
		var v: PackedStringArray = String(args["stamina"]).split(",")
		options = {"attacker_edge": {"attacker": 1.0, "defender": 1.0}, "stamina_edge": {"attacker_cost": float(v[0]), "defender_cost": float(v[1]), "defender_regen": float(v[2])}}
	var out := {"n": n, "seed": base_seed, "cfg": cfg, "edge": String(args["edge"]), "stamina": String(args["stamina"]), "tuning": Balance.stamp(), "pairs": {}}
	var started := Time.get_ticks_msec()
	for pair in kept:
		var attacker_wins := 0
		var timeouts := 0
		var ticks := 0
		var winner_hp := 0.0
		for i in n:
			var r: Dictionary = await Duel.duel(self, pair[0], pair[1], cfg, base_seed + i, options)
			ticks += int(r["ticks"])
			if String(r["reason"]).begins_with("timeout"):
				timeouts += 1
			if r["outcome"] == "attacker":
				attacker_wins += 1
				winner_hp += float(r["attacker_hp"])
			else:
				winner_hp += float(r["defender_hp"])
		out["pairs"][pair[0] + pair[1]] = {"attacker_wins": attacker_wins, "n": n, "timeouts": timeouts, "avg_ticks": ticks / n, "avg_winner_hp": snappedf(winner_hp / n, 0.01)}
		print("%s attacks %s: attacker %d/%d, timeouts %d, avg %d ticks, winner keeps %.0f%% HP [%d s]" % [pair[0], pair[1], attacker_wins, n, timeouts, ticks / n, 100.0 * winner_hp / n, (Time.get_ticks_msec() - started) / 1000])
	if String(args["out"]) != "":
		var file := FileAccess.open(String(args["out"]), FileAccess.WRITE)
		file.store_string(JSON.stringify(out, "\t", true))
	quit(0)
