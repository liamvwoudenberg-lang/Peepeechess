extends SceneTree
## Bot-measured balance of the battle-royal-v1 "last stand" (NOT a human balance claim - see BALANCE.md / BATTLE_ROYAL_V1.md).
##
##   godot --headless --path godot --script res://combat/tools/royal_matrix.gd -- n=8 seed=7000 out=/tmp/royal.json \
##       groups=p,n,b,r,q,pb,nb,br,nr,qn,rq checkers=balanced:0.6 king=balanced:0.6,duelist:0.9,patient:0.9
##
## Each cell plays `n` seeded sequences (the King's colour alternates with the seed): the King (given style/skill) fights the
## group's pieces in order with HP/stamina/cooldown carried over, each checker playing the `checkers` style. `fresh` repeats
## the same first duels with a full-HP King per duel (no carry) so the cost of attrition is visible.

const Runner := preload("res://combat/tests/royal_runner.gd")


func _cfg(text: String) -> Dictionary:
	var parts := text.split(":")
	return {"style": parts[0], "skill": float(parts[1]) if parts.size() > 1 else 0.6}


func _initialize() -> void:
	await process_frame
	var args := {"n": "8", "seed": "7000", "out": "", "groups": "p,n,b,r,q,pb,nb,br,nr,qn,rq", "checkers": "balanced:0.6", "king": "balanced:0.6,duelist:0.9,patient:0.9"}
	for token in OS.get_cmdline_user_args():
		var kv: PackedStringArray = String(token).split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var n := int(args["n"])
	var checker_cfg := _cfg(String(args["checkers"]))
	var out := {"n": n, "seed": int(args["seed"]), "checkers": checker_cfg, "tuning": preload("res://combat/data/balance_data.gd").stamp(), "cells": {}}
	var started := Time.get_ticks_msec()
	for group in String(args["groups"]).split(","):
		var roles: Array = []
		for ch in group:
			roles.append(ch)
		for king_text in String(args["king"]).split(","):
			var king_cfg := _cfg(king_text)
			var cell := {"wins": 0, "fresh_wins": 0, "first_duel_wins": 0, "hp_after_first": 0, "timeouts": 0, "ticks": 0, "n": n}
			for i in n:
				var seed_value: int = int(args["seed"]) + i
				var color := "w" if i % 2 == 0 else "b"
				var carried: Dictionary = await Runner.sequence(self, color, roles, king_cfg, checker_cfg, seed_value, true)
				if carried["king_wins"]:
					cell["wins"] += 1
				var first: Dictionary = carried["duels"][0] if not carried["duels"].is_empty() else {}
				if not first.is_empty():
					cell["hp_after_first"] += int(first["hp_end"])
					if first["outcome"] == "attacker" and int(first["hp_end"]) > 0:
						cell["first_duel_wins"] += 1
				for d in carried["duels"]:
					cell["ticks"] += int(d["ticks"])
					if String(d["reason"]).begins_with("timeout"):
						cell["timeouts"] += 1
				if roles.size() > 1:
					var fresh: Dictionary = await Runner.sequence(self, color, roles, king_cfg, checker_cfg, seed_value, false)
					if fresh["king_wins"]:
						cell["fresh_wins"] += 1
				else:
					cell["fresh_wins"] = cell["wins"]
			out["cells"]["%s|%s:%.1f" % [group, king_cfg["style"], king_cfg["skill"]]] = cell
			print("%-3s king %-9s/%.1f: wins %d/%d  (full-HP-each-duel %d/%d, first-duel wins %d, avg HP after duel 1 %.0f, timeouts %d) [%d s]" % [group, king_cfg["style"], king_cfg["skill"], cell["wins"], n, cell["fresh_wins"], n, cell["first_duel_wins"], float(cell["hp_after_first"]) / n, cell["timeouts"], (Time.get_ticks_msec() - started) / 1000])
	if String(args["out"]) != "":
		var f := FileAccess.open(String(args["out"]), FileAccess.WRITE)
		f.store_string(JSON.stringify(out, "\t", true))
		f.close()
	for child in root.get_children():
		child.queue_free()
	await process_frame
	await process_frame
	load("res://combat/audio/combat_audio.gd").clear_library()
	await create_timer(0.5).timeout
	quit(0)
