extends SceneTree
## Headless combat performance profile (CPU cost per 60 Hz tick, wall-clock microseconds).
##   godot --headless --path godot --script res://combat/tools/profile.gd [-- ticks=3000 roles=pn,rq,bb]
## Measures the code a SERVER or CLIENT runs every tick; it says nothing about GPU/rendering cost (see
## PERFORMANCE.md for the rendering budget and what was and was not measured). Budget: one tick = 16 667 us.

const Harness := preload("res://combat/net/net_harness.gd")
const Codec := preload("res://contracts/codec.gd")
const BUDGET_US := 16667.0


static func _stats(samples: Array) -> Dictionary:
	if samples.is_empty():
		return {"mean": 0.0, "p95": 0.0, "max": 0.0}
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0.0
	for v in samples:
		total += float(v)
	return {"mean": total / samples.size(), "p95": float(sorted[int(sorted.size() * 0.95)]), "max": float(sorted[-1])}


func _initialize() -> void:
	await process_frame
	var ticks := 3000
	var pairs: Array = ["pn", "rq", "bb", "nr", "qp"]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("ticks="):
			ticks = int(arg.substr(6))
		elif arg.begins_with("roles="):
			pairs = arg.substr(6).split(",")
	print("# Combat CPU profile (headless, %d active ticks per pairing, %s)" % [ticks, Engine.get_version_info()["string"]])
	print("| pairing | AI think x2 | submit x2 (schema) | step_tick | snapshot build | snapshot JSON | tick total mean / p95 / max | % of 16.7 ms |")
	print("| --- | ---: | ---: | ---: | ---: | ---: | --- | ---: |")
	var worst := 0.0
	for pair in pairs:
		var row := await _profile_pair(String(pair)[0], String(pair)[1], ticks)
		worst = maxf(worst, row["total"]["p95"])
	await _profile_client(ticks)
	print("\nworst pairing p95 tick cost: %.0f us = %.1f%% of the 60 Hz budget" % [worst, worst / BUDGET_US * 100.0])
	quit()


func _profile_pair(white: String, black: String, ticks: int) -> Dictionary:
	var sim := CombatSimulation.new()
	root.add_child(sim)
	var request := FighterRoster.build_request(white, black, "w", "prof-%s%s" % [white, black], 3, 0)
	var started: Dictionary = sim.start(request)
	assert(started["ok"], "profile start failed: " + str(started))
	await physics_frame
	var wb := CombatInputBuilder.new(request["matchId"], request["battleId"], "player-white")
	var bb := CombatInputBuilder.new(request["matchId"], request["battleId"], "player-black")
	var ws: Dictionary = request["attacker"]["stats"] if request["attacker"]["color"] == "w" else request["defender"]["stats"]
	var bs: Dictionary = request["defender"]["stats"] if request["attacker"]["color"] == "w" else request["attacker"]["stats"]
	var ai_w := CombatAI.new(wb, ws, bs, 11, 0.75)
	var ai_b := CombatAI.new(bb, bs, ws, 12, 0.6)
	var think: Array = []
	var submit: Array = []
	var step: Array = []
	var snap: Array = []
	var json: Array = []
	var total: Array = []
	var snapshot_bytes := 0
	var n := 0
	while sim.is_running() and n < 180 + ticks:
		var t0 := Time.get_ticks_usec()
		var view := sim.snapshot()
		var pw := ai_w.think(view)
		var pb := ai_b.think(view)
		var t1 := Time.get_ticks_usec()
		sim.submit_input(pw)
		sim.submit_input(pb)
		var t2 := Time.get_ticks_usec()
		sim.step_tick()
		var t3 := Time.get_ticks_usec()
		n += 1
		if n > 180:
			think.append(t1 - t0)
			submit.append(t2 - t1)
			step.append(t3 - t2)
			total.append(t3 - t0)
			if n % 4 == 0:
				var s0 := Time.get_ticks_usec()
				var shot := sim.snapshot()
				var s1 := Time.get_ticks_usec()
				var text := JSON.stringify(shot, "", true, true)
				var s2 := Time.get_ticks_usec()
				snap.append(s1 - s0)
				json.append(s2 - s1)
				snapshot_bytes = maxi(snapshot_bytes, text.length())
	var st := {"think": _stats(think), "submit": _stats(submit), "step": _stats(step), "snap": _stats(snap), "json": _stats(json), "total": _stats(total)}
	print("| %s vs %s | %.0f us | %.0f us | %.0f us | %.0f us | %.0f us, %d B | %.0f / %.0f / %.0f us | %.1f%% |" % [
			FighterRoster.display_name(white), FighterRoster.display_name(black), st["think"]["mean"], st["submit"]["mean"],
			st["step"]["mean"], st["snap"]["mean"], st["json"]["mean"], snapshot_bytes, st["total"]["mean"], st["total"]["p95"],
			st["total"]["max"], st["total"]["p95"] / BUDGET_US * 100.0])
	sim.stop()
	root.remove_child(sim)
	sim.queue_free()
	return st


func _profile_client(ticks: int) -> void:
	var request := FighterRoster.build_request("p", "n", "w", "prof-net", 4, 0)
	var net = Harness.new()
	await net.setup(self, request, {"up": [3, 3], "down": [3, 3], "seed": 7})
	net.run(200)
	var tick_cost: Array = []
	var snap_cost: Array = []
	var view_cost: Array = []
	var client = net.clients[0]
	for i in mini(ticks, 1200):
		var t0 := Time.get_ticks_usec()
		client.set_intent(0.4, 0.9, 0.2, true, false, false)
		client.tick(net.tick)
		tick_cost.append(Time.get_ticks_usec() - t0)
		var v0 := Time.get_ticks_usec()
		client.view("player-white", float(net.tick))
		client.view("player-black", float(net.tick))
		view_cost.append(Time.get_ticks_usec() - v0)
		net.step()
	var latest: Dictionary = client.latest
	if not latest.is_empty():
		var c0 := Time.get_ticks_usec()
		for _i in 50:
			Codec.new().valid("CombatSnapshot", latest)
		snap_cost.append((Time.get_ticks_usec() - c0) / 50)
	var a := _stats(tick_cost)
	var b := _stats(view_cost)
	print("\n| client cost (prediction + send) per tick | view() x2 per frame | schema-validate one snapshot (incl. building the codec) |")
	print("| ---: | ---: | ---: |")
	print("| %.0f us mean, %.0f us p95 | %.0f us mean, %.0f us p95 | %.0f us |" % [a["mean"], a["p95"], b["mean"], b["p95"], snap_cost[0] if not snap_cost.is_empty() else 0.0])
	net.dispose()
