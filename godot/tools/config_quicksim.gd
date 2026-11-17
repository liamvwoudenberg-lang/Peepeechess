extends SceneTree
## Fast bot check of the pairings you just tuned.
##
##   godot --headless --path godot --script res://tools/config_quicksim.gd -- pq [n=12] [seed=7000]
##   godot --headless --path godot --script res://tools/config_quicksim.gd -- pq,qp,rr n=24
##   godot --headless --path godot --script res://tools/config_quicksim.gd -- all n=8
##
## A pairing is two letters: the ATTACKING role then the DEFENDING role (p n b r q), e.g. `pq` = Pawn attacks Queen. For every
## pairing it plays `n` duels with a casual and a skilled bot (alternating seats) against the CURRENT tuning, including the
## attacker table, hit stun and pacing, and prints the attacker's win rate, the mean fight length and the tuning stamp.
## Use the debug override (docs/game/BALANCE_GUIDE.md) to try a number without touching the shipped file.
## BOT-measured: a quick signal while tuning, never a human playtest. Reuses combat/tools/attacker_duel.gd.
const Duel := preload("res://combat/tools/attacker_duel.gd")
const Balance := preload("res://combat/data/balance_data.gd")
const CONFIGS := [{"name": "casual", "style": "balanced", "skill": 0.6}, {"name": "skilled", "style": "duelist", "skill": 0.9}]


func _initialize() -> void:
	await process_frame
	var n := 12
	var seed_value := 7000
	var pairings: Array = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("n="):
			n = maxi(2, int(arg.substr(2)))
		elif arg.begins_with("seed="):
			seed_value = int(arg.substr(5))
		elif arg == "all":
			for a in "pnbrq":
				for d in "pnbrq":
					pairings.append(a + d)
		else:
			for part in arg.split(","):
				if part.length() == 2 and part[0] in "pnbrq" and part[1] in "pnbrq":
					pairings.append(part)
	if pairings.is_empty():
		print("usage: config_quicksim.gd -- <pairing[,pairing...]|all> [n=12] [seed=7000]   (pairing = attacker letter + defender letter, e.g. pq)")
		quit(1)
		return
	print("tuning %s%s, %d duels per bot" % [Balance.stamp(), " (OVERRIDE ACTIVE)" if Balance.is_overridden() else "", n])
	print("pair   attacker wins   (casual / skilled)   mean fight (s)")
	for pairing in pairings:
		var rates: Array = []
		var lengths: Array = []
		for cfg in CONFIGS:
			var series: Dictionary = await Duel.series(self, pairing[0], pairing[1], cfg, n, seed_value, {})
			rates.append(float(series["wins"]) / float(n))
			lengths.append(maxf(0.0, float(series["ticks"]) / float(n) - float(CombatConstants.COUNTDOWN_TICKS)) / 60.0)
		var mean: float = (rates[0] + rates[1]) / 2.0
		var seconds: float = (lengths[0] + lengths[1]) / 2.0
		print("%s     %3d%%            (%3d%% / %3d%%)       %.1f" % [pairing, int(round(mean * 100.0)), int(round(rates[0] * 100.0)), int(round(rates[1] * 100.0)), seconds])
	quit(0)
