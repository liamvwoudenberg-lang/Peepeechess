extends SceneTree
## Raw duel records for the fairness report: every attacker/defender pairing (Pawn..Queen), seat colour alternating, with a chosen bot on both
## seats (equal skill). `summarize_duels.py` turns the JSON into piece-vs-piece, white-vs-black and attacker-vs-defender tables and flags every
## cell outside 35..65% (the Pawn <-> Queen pairing is the one intended exception: the underdog should win about 15..25%).
##
##   godot --headless --path godot --script res://combat/tools/duel_report.gd -- n=24 seed=50000 style=duelist skill=0.9 shard=0/4 out=/tmp/dr-0.json
const Duel := preload("res://combat/tools/attacker_duel.gd")
const Balance := preload("res://combat/data/balance_data.gd")


func _initialize() -> void:
	await process_frame
	var args := {"n": "24", "seed": "50000", "style": "duelist", "skill": "0.9", "roles": "pnbrq", "shard": "0/1", "out": "", "rules": "on"}
	for token in OS.get_cmdline_user_args():
		var kv: PackedStringArray = String(token).split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var cfg := {"style": String(args["style"]), "skill": float(args["skill"])}
	var options := {} if String(args["rules"]) == "on" else {"attacker_edge": false}
	var shard := String(args["shard"]).split("/")
	var records: Array = []
	var index := 0
	var started := Time.get_ticks_msec()
	for a in String(args["roles"]):
		for d in String(args["roles"]):
			index += 1
			if (index - 1) % int(shard[1]) != int(shard[0]):
				continue
			for i in int(args["n"]):
				var seed_value := int(args["seed"]) + i
				var r: Dictionary = await Duel.duel(self, a, d, cfg, seed_value, options)
				records.append({"a": a, "d": d, "attacker_white": seed_value % 2 == 0, "outcome": r["outcome"], "reason": r["reason"], "fight_ticks": r["active_ticks"], "hits": r["hits"], "attacker_hp": r["attacker_hp"], "defender_hp": r["defender_hp"]})
			print("%s attacks %s done [%d s]" % [a, d, (Time.get_ticks_msec() - started) / 1000])
	var file := FileAccess.open(String(args["out"]), FileAccess.WRITE)
	file.store_string(JSON.stringify({"cfg": cfg, "n": int(args["n"]), "tuning": Balance.stamp(), "rules": String(args["rules"]), "records": records}))
	quit(0)
