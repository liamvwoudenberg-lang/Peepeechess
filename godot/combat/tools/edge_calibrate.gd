extends SceneTree
## Finds, for every attacker/defender pairing, the attacker advantage (damage multiplier, see BALANCE.md "Attacker advantage")
## that makes the ATTACKER win about `target` of the duels. BOT-measured (a casual and a skilled bot, averaged), not a human claim.
##
##   godot --headless --path godot --script res://combat/tools/edge_calibrate.gd -- \
##       target=0.62 n=32 iterations=8 seed=20000 shard=0/4 out=/tmp/edge-0.json [roles=pnbrq] [pairs=pq,qp] [stamina=1,1,1] [scale=0.25]
##
## One scalar x per pairing: x > 0 boosts the attacker's damage by e^x, x < 0 boosts the defender's by e^-x (the weaker side of the
## pairing is boosted, nobody is nerfed). The attacker win rate rises with x, so it is found by bisection over [-X_MAX, X_MAX] with
## fixed seeds. `n` duels per bot per evaluation. Shard with `shard=i/k` and merge the JSON files with merge_edge.py.
## Verify afterwards on DIFFERENT seeds with attacker_matrix.gd (the calibration seeds are not a fair test of the result).
const Duel := preload("res://combat/tools/attacker_duel.gd")
const Balance := preload("res://combat/data/balance_data.gd")
const CONFIGS := [{"style": "balanced", "skill": 0.6}, {"style": "duelist", "skill": 0.9}]
const X_MAX := 1.8   # e^1.8 = 6.05: the table allows at most 8x, the search stops well short of it


var stamina_rule: Dictionary = {"attacker_cost": 1.0, "defender_cost": 1.0, "defender_regen": 1.0}
var damage_scale: float = -1.0   # scale=<x> overrides the data's duel-length scale for the whole calibration (-1 = use the data's)


func _options(x: float) -> Dictionary:
	var options := {"attacker_edge": {"attacker": exp(x) if x > 0.0 else 1.0, "defender": exp(-x) if x < 0.0 else 1.0}, "stamina_edge": stamina_rule}
	if damage_scale > 0.0:
		options["damage_scale"] = damage_scale
	return options


## Mean attacker win rate over both bots at advantage x, plus the per-bot rates.
func _rate(a: String, d: String, x: float, n: int, seed_value: int) -> Dictionary:
	var rates: Array = []
	for cfg in CONFIGS:
		var s: Dictionary = await Duel.series(self, a, d, cfg, n, seed_value, _options(x))
		rates.append(float(s["wins"]) / float(n))
	return {"mean": (rates[0] + rates[1]) / 2.0, "rates": rates}


func _initialize() -> void:
	await process_frame
	var args := {"target": "0.62", "n": "32", "iterations": "8", "seed": "20000", "out": "", "roles": "pnbrq", "shard": "0/1", "pairs": "", "stamina": "", "scale": "", "mode": "both", "floor": "0.30", "lift": "0.10", "min_mult": "1.12", "max_mult": "3.0"}
	for token in OS.get_cmdline_user_args():
		var kv: PackedStringArray = String(token).split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	if String(args["stamina"]) != "":
		var v: PackedStringArray = String(args["stamina"]).split(",")
		stamina_rule = {"attacker_cost": float(v[0]), "defender_cost": float(v[1]), "defender_regen": float(v[2])}
	if String(args["scale"]) != "":
		damage_scale = float(args["scale"])
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
	var out := {"stamina": stamina_rule, "target": target, "n": n, "iterations": iterations, "seed": base_seed, "tuning": Balance.stamp(), "scale": damage_scale if damage_scale > 0.0 else Balance.damage_scale(), "pairs": {}}
	var started := Time.get_ticks_msec()
	for i in pairs.size():
		if i % int(shard[1]) != int(shard[0]):
			continue
		var a: String = pairs[i][0]
		var d: String = pairs[i][1]
		var lo := -X_MAX
		var hi := X_MAX
		var capped := ""
		var x := 0.0
		if String(args["mode"]) == "attacker":
			# Attacker-initiative mode: NOBODY boosts the defender. The attacker gets at least `min_mult` damage (the initiative) and, when
			# the raw matchup favours the defender, as much more as it takes to lift the attacker's rate `lift` above its raw rate (never
			# below `floor` where reachable, capped at `max_mult`). A stronger piece therefore stays stronger, as a Queen should.
			var raw: Dictionary = await _rate(a, d, 0.0, n, base_seed)
			var want := clampf(float(raw["mean"]) + float(args["lift"]), float(args["floor"]), 0.92)
			lo = log(float(args["min_mult"]))
			hi = log(float(args["max_mult"]))
			var at_min: Dictionary = await _rate(a, d, lo, n, base_seed)
			var at_max: Dictionary = await _rate(a, d, hi, n, base_seed)
			if float(at_min["mean"]) >= want:
				x = lo
			elif float(at_max["mean"]) <= want:
				x = hi
				capped = "attacker still behind at the maximum attacker boost (raw %.0f%%)" % (100.0 * float(raw["mean"]))
			else:
				for _it in iterations:
					var mid2 := (lo + hi) / 2.0
					var at_mid2: Dictionary = await _rate(a, d, mid2, n, base_seed)
					if float(at_mid2["mean"]) < want:
						lo = mid2
					else:
						hi = mid2
				x = (lo + hi) / 2.0
			capped += (" " if capped != "" else "") + "[raw %.0f%% want %.0f%%]" % [100.0 * float(raw["mean"]), 100.0 * want]
		else:
			var at_lo: Dictionary = await _rate(a, d, lo, n, base_seed)
			var at_hi: Dictionary = await _rate(a, d, hi, n, base_seed)
			x = await _search_both(at_lo, at_hi, a, d, lo, hi, target, iterations, n, base_seed)
			capped = String(_last_capped)
		var final: Dictionary = await _rate(a, d, x, n, base_seed)
		var attacker_mult := exp(x) if x > 0.0 else 1.0
		var defender_mult := exp(-x) if x < 0.0 else 1.0
		out["pairs"][a + d] = {"x": snappedf(x, 0.001), "attacker_mult": snappedf(attacker_mult, 0.01), "defender_mult": snappedf(defender_mult, 0.01),
				"rate_mean": snappedf(float(final["mean"]), 0.001), "rate_casual": final["rates"][0], "rate_skilled": final["rates"][1], "capped": capped}
		print("%s attacks %s: attacker x%.2f / defender x%.2f -> %.0f%% (casual %.0f%%, skilled %.0f%%) %s [%d s]" % [a, d, attacker_mult, defender_mult,
				100.0 * float(final["mean"]), 100.0 * float(final["rates"][0]), 100.0 * float(final["rates"][1]), capped, (Time.get_ticks_msec() - started) / 1000])
		if String(args["out"]) != "":
			var file := FileAccess.open(String(args["out"]), FileAccess.WRITE)
			file.store_string(JSON.stringify(out, "\t", true))
	quit(0)


var _last_capped := ""

## The original two-sided search (the weaker side gets the boost): returns x, sets _last_capped.
func _search_both(at_lo: Dictionary, at_hi: Dictionary, a: String, d: String, lo: float, hi: float, target: float, iterations: int, n: int, base_seed: int) -> float:
	_last_capped = ""
	if float(at_lo["mean"]) >= target:
		_last_capped = "attacker already ahead at the maximum defender boost"
		return lo
	if float(at_hi["mean"]) <= target:
		_last_capped = "attacker still behind at the maximum attacker boost"
		return hi
	for _it in iterations:
		var mid := (lo + hi) / 2.0
		var at_mid: Dictionary = await _rate(a, d, mid, n, base_seed)
		if float(at_mid["mean"]) < target:
			lo = mid
		else:
			hi = mid
	return (lo + hi) / 2.0
