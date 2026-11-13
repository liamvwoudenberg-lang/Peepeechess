extends SceneTree
## Does reading the opponent beat button mashing? BOT-measured (see BALANCE.md "Pacing"): bot style A against bot style B in the same
## role pairings, and how often A wins. The attacker seat alternates with the seed so the attacker's advantage cancels out; roles are
## mirrored by default (Pawn vs Pawn ...) so that what is measured is the STYLE, not the class.
##
##   godot --headless --path godot --script res://combat/tools/style_matchup.gd -- \
##       a=aggressive:0.9 b=duelist:0.9 n=24 seed=70000 out=/tmp/sm.json [roles=pnbrq] [edge=off] [scale=1.0]
##
## `a` and `b` are style:skill. The output is A's win rate over all roles and seeds, and per role.
const Duel := preload("res://combat/tools/attacker_duel.gd")
const Balance := preload("res://combat/data/balance_data.gd")


func _parse(text: String) -> Dictionary:
	var parts := text.split(":")
	return {"style": parts[0], "skill": float(parts[1]) if parts.size() > 1 else 0.6}


func _initialize() -> void:
	await process_frame
	var args := {"a": "aggressive:0.9", "b": "duelist:0.9", "n": "24", "seed": "70000", "out": "", "roles": "pnbrq", "edge": "data", "scale": "", "shard": "0/1"}
	for token in OS.get_cmdline_user_args():
		var kv: PackedStringArray = String(token).split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var cfg_a := _parse(String(args["a"]))
	var cfg_b := _parse(String(args["b"]))
	var n := int(args["n"])
	var options := {"attacker_edge": false} if String(args["edge"]) == "off" else {}
	if String(args["scale"]) != "":
		options["damage_scale"] = float(args["scale"])
	var shard := String(args["shard"]).split("/")
	var out := {"a": args["a"], "b": args["b"], "n": n, "seed": int(args["seed"]), "tuning": Balance.stamp(), "roles": {}}
	var wins_total := 0
	var duels_total := 0
	var timeouts := 0
	var started := Time.get_ticks_msec()
	var index := 0
	for role in String(args["roles"]):
		index += 1
		if (index - 1) % int(shard[1]) != int(shard[0]):
			continue
		var wins := 0
		var ticks := 0
		for i in n:
			var seed_value := int(args["seed"]) + i
			# A plays the attacker's seat on even seeds and the defender's on odd ones (the seat is chosen by the seed's parity inside
			# Duel.duel, so the bots are swapped explicitly here to keep A and B on the same colours across the pair of seats).
			var swap := i % 2 == 1
			var r: Dictionary
			if swap:
				r = await Duel.duel(self, role, role, cfg_b, seed_value, options, cfg_a)   # B attacks, A defends
			else:
				r = await Duel.duel(self, role, role, cfg_a, seed_value, options, cfg_b)   # A attacks, B defends
			var attacker_won: bool = r["outcome"] == "attacker"
			if attacker_won != swap:
				wins += 1
			ticks += int(r["active_ticks"])
			if String(r["reason"]).begins_with("timeout"):
				timeouts += 1
		out["roles"][role] = {"a_wins": wins, "n": n, "avg_fight_s": snappedf(float(ticks) / n / 60.0, 0.1)}
		wins_total += wins
		duels_total += n
		print("%s: %s wins %d/%d against %s (%d%%), average fight %.1f s [%d s]" % [role, args["a"], wins, n, args["b"], 100 * wins / n, float(ticks) / n / 60.0, (Time.get_ticks_msec() - started) / 1000])
	out["a_wins"] = wins_total
	out["duels"] = duels_total
	out["timeouts"] = timeouts
	print("TOTAL: %s wins %d/%d (%.0f%%) against %s, %d timeouts" % [args["a"], wins_total, duels_total, 100.0 * wins_total / maxi(1, duels_total), args["b"], timeouts])
	if String(args["out"]) != "":
		var file := FileAccess.open(String(args["out"]), FileAccess.WRITE)
		file.store_string(JSON.stringify(out, "\t", true))
	quit(0)
