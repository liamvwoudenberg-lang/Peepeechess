extends RefCounted
## Network behaviour under simulated latency, loss, reordering and disconnects. Every scenario is
## deterministic (seeded channels and bots), runs the REAL server + client code through
## net/net_harness.gd, and asserts measured numbers.
##
## Latency convention: "N ms latency" means ROUND-TRIP N ms (so one-way ~N/2). Channels are integer
## ticks (1 tick = 16.667 ms), split up/down so the sums are exact:
##     0 ms : up 0 + down 0 =  0 ticks        50 ms : 1 + 2 = 3 ticks (50.0 ms)
##   100 ms : 3 + 3 = 6 ticks (100 ms)       150 ms : 4 + 5 = 9 ticks (150 ms)

const Harness := preload("res://combat/net/net_harness.gd")
const Bot := preload("res://combat/net/net_bot.gd")
const Client := preload("res://combat/net/combat_net_client.gd")
const Codec := preload("res://contracts/codec.gd")

const LATENCIES: Array = [
	{"name": "0 ms", "rtt_ms": 0, "up": 0, "down": 0},
	{"name": "50 ms", "rtt_ms": 50, "up": 1, "down": 2},
	{"name": "100 ms", "rtt_ms": 100, "up": 3, "down": 3},
	{"name": "150 ms", "rtt_ms": 150, "up": 4, "down": 5},
]
const LIVE := 180


class _Sturdy:
	static func apply(sim: CombatSimulation) -> void:
		for f in sim.fighters:
			f.health.maximum = 5000
			f.health.current = 5000


static func _cfg(l: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var cfg := {"up": [l["up"], l["up"]], "down": [l["down"], l["down"]], "seed": 1}
	cfg.merge(extra, true)
	return cfg


static func _new(tree: SceneTree, cfg: Dictionary, roles: Array = ["p", "p"], battle_id: String = "lat-1", seed_value: int = 5):
	var h = Harness.new()
	await h.setup(tree, FighterRoster.build_request(roles[0], roles[1], "w", battle_id, seed_value, 0), cfg)
	return h


static func _p95(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return float(sorted[int(float(sorted.size()) * 0.95)])


static func _mean(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for v in values:
		total += float(v)
	return total / float(values.size())


static func run(h, tree: SceneTree) -> void:
	print("  latency convention: N ms = round trip N ms; ticks up/down: 0=0/0  50=1/2  100=3/3  150=4/5")
	await _authority_independence(h, tree)
	await _prediction_error(h, tree)
	await _reconciliation(h, tree)
	await _interpolation(h, tree)
	await _parry_fairness(h, tree)
	await _simultaneous(h, tree)
	await _packet_loss(h, tree)
	await _reorder(h, tree)
	await _disconnect(h, tree)
	await _forgery(h, tree)


# ---- (a) the network layer adds no divergence to the authority -----------------------------------
static func _authority_independence(h, tree: SceneTree) -> void:
	for l in LATENCIES:
		h.begin("authority independent of the network: %s" % l["name"])
		var net = await _new(tree, _cfg(l, {"seed": 3}), ["p", "n"])
		net.bots[0] = Bot.new("fighter", 21)
		net.bots[1] = Bot.new("fighter", 22)
		net.run(LIVE + 700)
		var live_json := JSON.stringify(net.sim.snapshot(), "", true, true)
		var replayed: String = await net.replay_final_snapshot()
		h.check(live_json == replayed, "replaying the server's accepted inputs through a bare simulation gives byte-identical state (%d inputs)" % net.server.record.size())
		var damage := 0
		for e in net.events_of("hit"):
			damage += int(e["damage"])
		h.check(net.server.counters["accepted"] > 500 and net.sim.recent_events.size() >= 3, "the fight really ran (%d inputs accepted, %d events, result: %s)" % [net.server.counters["accepted"], net.sim.recent_events.size(), net.sim.result.get("reason", "none yet")])
		net.dispose()
	h.begin("authority independent of the network: 100 ms + 10% loss + reorder + duplicates")
	var rough = await _new(tree, _cfg(LATENCIES[2], {"loss": 0.1, "reorder": 0.2, "dup": 0.1, "jitter": 1, "seed": 8}), ["n", "p"])
	rough.bots[0] = Bot.new("fighter", 31)
	rough.bots[1] = Bot.new("fighter", 32)
	rough.run(LIVE + 700)
	h.check(JSON.stringify(rough.sim.snapshot(), "", true, true) == await rough.replay_final_snapshot(), "still identical under loss/reorder/duplication")
	rough.dispose()


# ---- (b) prediction error --------------------------------------------------------------------------
static func _prediction_error(h, tree: SceneTree) -> void:
	print("  prediction error of the local fighter (reconciliation correction, metres), walker bot, 900 live ticks:")
	print("    latency   n    mean     p95      max     hard_snaps")
	for l in LATENCIES:
		h.begin("prediction error: %s" % l["name"])
		var net = await _new(tree, _cfg(l, {"seed": 4}))
		net.place(Vector3(-1, 0, -1), Vector3(5.5, 0, 0.5))
		net.bots[0] = Bot.new("walker", 11)
		net.bots[0].leash = 5.5
		net.bots[1] = Bot.new("idle", 12)
		net.run(LIVE + 900)
		var c = net.clients[0]
		var mean := _mean(c.corrections)
		var p95 := _p95(c.corrections)
		print("    %-8s %3d  %.4f   %.4f   %.4f   %d" % [l["name"], c.corrections.size(), mean, p95, c.max_correction, c.stats["hard_snaps"]])
		h.check(c.corrections.size() > 100, "enough corrections measured (%d)" % c.corrections.size())
		h.check(mean < 0.01, "mean correction %.4f m < 0.01 m (the predictor reproduces the server's movement)" % mean)
		h.check(p95 < 0.03, "95th percentile %.4f m < 0.03 m" % p95)
		h.check(c.max_correction < 0.25, "worst correction %.4f m < 0.25 m (pillar/wall contact differs slightly between engine collision and the analytic model)" % c.max_correction)
		h.eq(c.stats["hard_snaps"], 0, "no hard snaps in ordinary movement")
		h.check(absf(net.server.rtt_ticks("player-white") - float(l["up"] + l["down"])) < 0.01, "the server's RTT estimate equals the configured %d ticks" % (l["up"] + l["down"]))
		net.dispose()


# ---- (c) reconciliation convergence -------------------------------------------------------------
static func _reconciliation(h, tree: SceneTree) -> void:
	h.begin("reconciliation: a server-side displacement is corrected smoothly and converges (100 ms)")
	var net = await _new(tree, _cfg(LATENCIES[2], {"seed": 6}))
	net.place(Vector3(-1, 0, -1), Vector3(5.5, 0, 0.5))
	net.bots[0] = Bot.new("walker", 41)
	net.bots[0].leash = 2.5
	net.bots[1] = Bot.new("idle", 42)
	net.run(LIVE + 100)
	var c = net.clients[0]
	var before_max: float = c.max_correction
	var pos: Vector3 = net.sim.fighters[0].global_position
	net.sim.fighters[0].teleport(pos + Vector3(0.6, 0.0, 0.0))  # an authoritative event the client could not predict
	var peak := 0.0
	var offsets: Array = []
	for _i in 40:
		net.step()
		peak = maxf(peak, c.render_offset().length())
		offsets.append(c.render_offset().length())
	h.check(peak > 0.4 and peak < 0.75, "the client sees the 0.6 m disagreement as a correction (peak offset %.2f m)" % peak)
	h.eq(c.stats["hard_snaps"], 0, "0.6 m is blended, not snapped")
	h.check(float(offsets[offsets.size() - 1]) < 0.03, "and it has converged 40 ticks later (offset %.3f m)" % float(offsets[offsets.size() - 1]))
	var monotone := true
	var seen_peak := false
	for i in range(1, offsets.size()):
		if seen_peak and float(offsets[i]) > float(offsets[i - 1]) + 0.02:
			monotone = false
		if float(offsets[i]) >= peak - 0.001:
			seen_peak = true
	h.check(monotone, "after the peak the error only shrinks")
	var pos2: Vector3 = net.sim.fighters[0].global_position
	net.sim.fighters[0].teleport(pos2 + Vector3(2.2, 0.0, 0.0))  # larger than HARD_SNAP_ABOVE
	net.run(30)
	h.check(c.stats["hard_snaps"] >= 1, "a 2.2 m disagreement is a hard snap (no 2 m slide through the arena)")
	net.dispose()


# ---- (d) remote interpolation ------------------------------------------------------------------
static func _interpolation(h, tree: SceneTree) -> void:
	print("  remote interpolation (observer's view of a sprinting opponent), 900 live ticks:")
	print("    case             max step   mean step  teleports  extrap<=6  frames extrapolated")
	var cases: Array = [
		{"name": "0 ms", "l": LATENCIES[0], "extra": {}},
		{"name": "50 ms", "l": LATENCIES[1], "extra": {}},
		{"name": "100 ms", "l": LATENCIES[2], "extra": {}},
		{"name": "150 ms", "l": LATENCIES[3], "extra": {}},
		{"name": "100 ms + 5% loss", "l": LATENCIES[2], "extra": {"loss": 0.05}},
		{"name": "100 ms + jitter 2", "l": LATENCIES[2], "extra": {"jitter": 2}},
	]
	for entry in cases:
		h.begin("remote interpolation: %s" % entry["name"])
		var net = await _new(tree, _cfg(entry["l"], entry["extra"].merged({"seed": 7})))
		net.place(Vector3(-5.5, 0, 0.5), Vector3(-1, 0, -1))
		net.bots[0] = Bot.new("idle", 51)
		net.bots[1] = Bot.new("walker", 52)
		net.bots[1].leash = 5.5
		net.run(LIVE + 20)
		var observer = net.clients[0]
		var previous: Vector3 = observer.view("player-black", float(net.tick))["position"]
		var steps: Array = []
		var teleports := 0
		var extrapolated := 0
		var extrap_ok := true
		for _i in 900:
			net.step()
			var view: Dictionary = observer.view("player-black", float(net.tick))
			var step: float = (view["position"] - previous).length()
			steps.append(step)
			if step > 0.5:
				teleports += 1
			previous = view["position"]
			if view.has("extrapolated_ticks"):
				extrapolated += 1
				extrap_ok = extrap_ok and float(view["extrapolated_ticks"]) <= 6.0
		var max_step: float = steps.max()
		print("    %-16s %.4f     %.4f     %d          %s        %d" % [entry["name"], max_step, _mean(steps), teleports, str(extrap_ok), extrapolated])
		h.eq(teleports, 0, "the remote fighter never jumps (> 0.5 m in one frame)")
		var allowed := 0.13 if not entry["extra"].has("loss") and not entry["extra"].has("jitter") else 0.22
		h.check(max_step <= allowed, "worst per-frame step %.4f m <= %.2f m (sprint speed is %.3f m per tick)" % [max_step, allowed, 5.856 / 60.0])
		h.check(extrap_ok, "extrapolation never exceeds %d ticks" % Client.EXTRAP_MAX_TICKS)
		h.check(Vector2(previous.x, previous.z).length() < 7.1, "the interpolated fighter stays inside the arena")
		net.dispose()


# ---- (e) parry timing fairness ----------------------------------------------------------------------
## A scripted attacker throws a heavy; a reactor bot parries `react` ticks after ITS VIEW first shows the
## attack. Returns true when the parry worked (no damage taken).
static func _parry_trial(tree: SceneTree, latency: Dictionary, react: int, grace: bool, extra: Dictionary = {}) -> bool:
	var cfg := _cfg(latency, extra)
	cfg["grace"] = grace
	var net = await _new(tree, cfg, ["p", "p"], "parry-%d" % react)
	net.place(Vector3(0, 0, -0.9), Vector3(0, 0, 0.9))
	var attacker = Bot.new("script", 1)
	attacker.hook = func(_bot, client, tick):
		client.set_intent(0.0, 0.0, 0.0, true, false, false)
		if tick == 200:
			client.press("heavy")
	var reactor = Bot.new("reactor", 2)
	reactor.react_ticks = react
	reactor.action = "parry"
	net.bots[0] = attacker
	net.bots[1] = reactor
	net.run(LIVE + 90)
	var parried: bool = net.events_of("parry").size() >= 1 and net.events_of("hit").size() == 0
	net.dispose()
	return parried


static func _successes(tree: SceneTree, latency: Dictionary, grace: bool, extra: Dictionary = {}) -> Array:
	var ok: Array = []
	for react in range(0, 40, 2):
		if await _parry_trial(tree, latency, react, grace, extra):
			ok.append(react)
	return ok


static func _span(values: Array) -> String:
	return "[%d..%d] n=%d" % [values[0], values[values.size() - 1], values.size()] if not values.is_empty() else "none"


static func _parry_fairness(h, tree: SceneTree) -> void:
	print("  parry fairness: heavy attack (hit on tick 27), reactor presses parry R ticks after its view shows the attack;")
	print("  successful R values (R scanned 0..38 step 2). Same bot, same timing, per latency, grace off vs on:")
	print("    latency   grace OFF                 grace ON")
	var sets_off := {}
	var sets_on := {}
	for l in LATENCIES:
		sets_off[l["name"]] = await _successes(tree, l, false)
		sets_on[l["name"]] = await _successes(tree, l, true)
		print("    %-8s %-25s %s" % [l["name"], _span(sets_off[l["name"]]), _span(sets_on[l["name"]])])
	h.begin("parry fairness: the parry window exists at 0 ms and early/late presses fail")
	var zero: Array = sets_on["0 ms"]
	h.check(zero.size() >= 4, "at 0 ms a range of reaction times parries (%s)" % _span(zero))
	var lo: int = zero[0]
	var hi: int = zero[zero.size() - 1]
	var ideal: int = zero[zero.size() / 2]
	h.check(not (lo - 4) in zero and not (hi + 4) in zero, "a press 4 ticks earlier or later than the window fails at 0 ms (no free parries)")
	h.eq(sets_off["0 ms"], sets_on["0 ms"], "grace changes nothing at 0 ms latency")

	h.begin("parry fairness: latency shifts the window; grace gives it back, but only up to the cap")
	var off150: Array = sets_off["150 ms"]
	var on150: Array = sets_on["150 ms"]
	h.check(not ideal in off150, "WITHOUT grace the 0 ms-ideal reaction (R=%d) FAILS at 150 ms" % ideal)
	h.check(ideal in on150, "WITH grace the same reaction (R=%d) succeeds at 150 ms" % ideal)
	h.check(on150.size() >= off150.size(), "grace never shrinks the set of working reactions (%d vs %d)" % [on150.size(), off150.size()])
	h.check(int(on150[on150.size() - 1]) - int(off150[off150.size() - 1]) <= CombatSimulation.HIT_GRACE_CAP + 2, "the window moves by at most the cap (+scan resolution): last good R %d -> %d" % [off150[off150.size() - 1], on150[on150.size() - 1]])
	var late: int = int(on150[on150.size() - 1]) + 6
	h.check(not late in on150, "pressing %d ticks after the extended window still fails" % 6)
	for l in LATENCIES:
		var on: Array = sets_on[l["name"]]
		h.check(not on.is_empty() and int(on[on.size() - 1]) - int(zero[zero.size() - 1]) <= CombatSimulation.HIT_GRACE_CAP + 2, "%s: grace-on window never extends later than the cap allows" % l["name"])
	h.begin("parry fairness: a client cannot widen its own window by lying (150 ms honest vs liar claiming 6)")
	var fair: Array = sets_on["150 ms"]
	var liar_extra: Array = await _liar_successes(tree, LATENCIES[0])
	print("    liar at 0 ms RTT claiming a 6-tick RTT: %s   (honest 0 ms: %s, honest 150 ms: %s)" % [_span(liar_extra), _span(zero), _span(fair)])
	h.check(liar_extra.size() <= fair.size() + 2, "a 0 ms liar's window (%d values) is no larger than an honest 150 ms player's (%d)" % [liar_extra.size(), fair.size()])
	h.check(int(liar_extra[liar_extra.size() - 1]) - int(zero[zero.size() - 1]) <= CombatSimulation.HIT_GRACE_CAP + 2, "the liar gains at most the cap")


static func _liar_successes(tree: SceneTree, latency: Dictionary) -> Array:
	var ok: Array = []
	for react in range(0, 40, 2):
		var net = await _new(tree, _cfg(latency), ["p", "p"], "liar-%d" % react)
		net.place(Vector3(0, 0, -0.9), Vector3(0, 0, 0.9))
		var attacker = Bot.new("script", 1)
		attacker.hook = func(_bot, client, tick):
			client.set_intent(0.0, 0.0, 0.0, true, false, false)
			if tick == 200:
				client.press("heavy")
		var reactor = Bot.new("reactor", 2)
		reactor.react_ticks = react
		net.bots[0] = attacker
		net.bots[1] = reactor
		var black = net.clients[1]
		black.send = func(packet):
			packet["clientTick"] = maxi(0, int(packet["clientTick"]) - 6)  # pretend a 6-tick round trip
			net.c2s[1].send(packet, net.tick)
		net.run(LIVE + 90)
		if net.events_of("parry").size() >= 1 and net.events_of("hit").size() == 0:
			ok.append(react)
		net.dispose()
	return ok


# ---- (f) simultaneous attacks ----------------------------------------------------------------------
static func _simultaneous_run(tree: SceneTree, up: Array, down: Array, both_low_hp: bool) -> Dictionary:
	var net = await _new(tree, {"up": up, "down": down, "seed": 2}, ["p", "p"], "sim-att")
	net.place(Vector3(0, 0, -0.9), Vector3(0, 0, 0.9))
	if both_low_hp:
		net.sim.fighters[0].health.current = 1
		net.sim.fighters[1].health.current = 1
	var white_press := 200
	var black_press: int = white_press + int(up[0]) - int(up[1])  # arrive on the same server tick
	var w = Bot.new("script", 1)
	w.hook = func(_bot, client, tick):
		client.set_intent(0.0, 0.0, 0.0, true, false, false)
		if tick == white_press:
			client.press("light")
	var b = Bot.new("script", 2)
	b.hook = func(_bot, client, tick):
		client.set_intent(0.0, 0.0, PI, true, false, false)
		if tick == black_press:
			client.press("light")
	net.bots[0] = w
	net.bots[1] = b
	net.run(LIVE + 80)
	var arrivals := {}
	for entry in net.server.record:
		if entry["k"] == "in" and int(entry["packet"]["light"]) > 0 and not arrivals.has(entry["p"]):
			arrivals[entry["p"]] = int(entry["t"])
	var out := {"hp": [net.sim.fighters[0].health.current, net.sim.fighters[1].health.current],
			"hits": net.events_of("hit").size(), "arrivals": arrivals, "result": net.sim.result.duplicate(true),
			"hit_ticks": net.events_of("hit").map(func(e): return int(e["tick"]))}
	net.dispose()
	return out


static func _simultaneous(h, tree: SceneTree) -> void:
	h.begin("simultaneous attacks: both hits resolve whatever the latency asymmetry")
	var base: Dictionary = await _simultaneous_run(tree, [0, 0], [0, 0], false)
	var skewed: Dictionary = await _simultaneous_run(tree, [0, 4], [0, 5], false)
	h.eq(base["arrivals"]["player-white"], base["arrivals"]["player-black"], "baseline: both presses applied on the same server tick")
	h.eq(skewed["arrivals"]["player-white"], skewed["arrivals"]["player-black"], "skewed (0 ms vs 150 ms): both presses still applied on the same server tick")
	h.eq(base["hp"], [68, 68], "0 ms: a clean trade, 12 damage each")
	h.eq(skewed["hp"], base["hp"], "150 ms vs 0 ms: identical outcome")
	h.eq(skewed["hits"], 2, "two hit events")
	var hit_ticks: Array = skewed["hit_ticks"]
	print("    trade timing: baseline hit ticks %s, 0 ms vs 150 ms %s (the slower seat's incoming hit is committed up to %d ticks later)" % [str(base["hit_ticks"]), str(hit_ticks), CombatSimulation.HIT_GRACE_CAP])
	h.check(absi(int(hit_ticks[0]) - int(hit_ticks[1])) <= CombatSimulation.HIT_GRACE_CAP, "the two commits are at most the cap apart")

	h.begin("simultaneous attacks: a double knockout is decided identically with and without latency")
	var ko_base: Dictionary = await _simultaneous_run(tree, [0, 0], [0, 0], true)
	var ko_skew: Dictionary = await _simultaneous_run(tree, [0, 4], [0, 5], true)
	h.eq(ko_base["result"]["reason"], "double_knockout", "0 ms: double knockout")
	h.eq(ko_skew["result"]["reason"], "double_knockout", "0 ms vs 150 ms: double knockout")
	h.eq(ko_skew["result"]["outcome"], ko_base["result"]["outcome"], "same outcome (defender holds)")
	h.eq(ko_skew["result"]["resolvedTick"], ko_base["result"]["resolvedTick"], "resolved on the same tick (the pending hit flushes with the knockout)")


# ---- (g) packet loss ------------------------------------------------------------------------------
static func _action_delays(net, index: int) -> Array:
	var player: String = net.ids[index]
	var delays: Array = []
	var start_tick: int = int(net.request["startTick"])
	for press in net.clients[index].press_log:
		var applied := -1
		for entry in net.server.record:
			if entry["k"] == "in" and entry["p"] == player and int(entry["packet"][press["action"]]) >= int(press["counter"]):
				applied = int(entry["t"])
				break
		if applied >= 0:
			delays.append(applied - (start_tick + int(press["tick"]) + 1 + int(net.c2s[index].latency_ticks)))
	return delays


static func _packet_loss(h, tree: SceneTree) -> void:
	print("  packet loss (both directions, 50 ms RTT), fighter bots, 900 live ticks:")
	print("    loss   accepted  stale  presses  extra delay mean/max (ticks)  counters in sync   hard_snaps  max correction")
	for loss in [0.05, 0.15]:
		h.begin("packet loss %d%%: fights stay valid, actions arrive a few ticks late at worst" % int(loss * 100.0))
		var net = await _new(tree, _cfg(LATENCIES[1], {"loss": loss, "seed": 12}), ["p", "n"])
		_sturdy(net)  # keep the fight going for the whole sample so there are many actions to measure
		net.bots[0] = Bot.new("fighter", 61)
		net.bots[1] = Bot.new("fighter", 62)
		net.run(LIVE + 900)
		var delays: Array = _action_delays(net, 0) + _action_delays(net, 1)
		var presses: int = net.clients[0].press_log.size() + net.clients[1].press_log.size()
		var in_sync := true
		for i in 2:
			for action in CombatInputState.ACTIONS:
				var seen: int = int(net.sim._inputs[net.ids[i]].seen[action])
				in_sync = in_sync and absi(int(net.clients[i].builder.counters[action]) - seen) <= 1
		var max_delay: int = int(delays.max()) if not delays.is_empty() else 0
		var max_corr: float = maxf(net.clients[0].max_correction, net.clients[1].max_correction)
		var hard: int = net.clients[0].stats["hard_snaps"] + net.clients[1].stats["hard_snaps"]
		print("    %3d%%   %5d     %3d    %3d      %.2f / %d                     %s            %d          %.3f" % [int(loss * 100.0), net.server.counters["accepted"], net.server.counters["stale"], presses, _mean(delays), max_delay, str(in_sync), hard, max_corr])
		h.eq(net.server.counters["invalid"], 0, "no corrupt packets were admitted")
		h.eq(net.server.counters["forbidden"], 0, "no seat errors")
		h.check(presses > 30, "the bots really pressed actions (%d)" % presses)
		h.check(in_sync, "server and client action counters agree to within 1 (lost packets are healed by the next one)")
		var limit := 8 if loss < 0.1 else 14
		h.check(max_delay <= limit, "no action was applied more than %d ticks later than loss-free timing (max %d)" % [limit, max_delay])
		h.check(net.sim.fighters[0].health.current >= 0 and net.sim.fighters[1].health.current >= 0, "HP stays valid")
		h.check(JSON.stringify(net.sim.snapshot(), "", true, true) == await net.replay_final_snapshot(Callable(_Sturdy, "apply")), "the authority is unaffected: replay identical")
		net.dispose()
	h.begin("packet loss 15%: a whole fight terminates with a valid BattleResult")
	var full = await _new(tree, _cfg(LATENCIES[1], {"loss": 0.15, "seed": 13}), ["p", "p"], "loss-finish")
	full.bots[0] = Bot.new("fighter", 71)
	full.bots[1] = Bot.new("fighter", 72)
	full.run_until(func(): return not full.sim.result.is_empty(), 6000)
	h.check(not full.sim.result.is_empty(), "the battle finished (tick %d)" % full.tick)
	h.check(Codec.new().valid("BattleResult", full.sim.result), "its result is a valid BattleResult")
	full.run(30)
	h.check(not full.clients[0].result.is_empty() and not full.clients[1].result.is_empty(), "both clients received the result")
	h.eq(JSON.stringify(full.clients[0].result), JSON.stringify(full.sim.result), "and it is the server's result (a client cannot author it)")
	full.dispose()


# ---- (h) reordered / delayed / duplicated input -------------------------------------------------
static func _reorder(h, tree: SceneTree) -> void:
	h.begin("reordered, delayed and duplicated packets (jitter 3, 30% reorder, 10% duplicates)")
	var net = await _new(tree, _cfg(LATENCIES[2], {"jitter": 3, "reorder": 0.3, "dup": 0.1, "seed": 14}), ["n", "p"])
	_sturdy(net)
	net.bots[0] = Bot.new("fighter", 81)
	net.bots[1] = Bot.new("fighter", 82)
	net.run(LIVE + 700)
	var stale: int = net.server.counters["stale"]
	print("    reorder: accepted %d, stale (late/duplicate) %d, channel reordered %d/%d, duplicated %d/%d" % [net.server.counters["accepted"], stale, net.c2s[0].reordered, net.c2s[1].reordered, net.c2s[0].duplicated, net.c2s[1].duplicated])
	h.check(stale > 20, "reordering/duplication really occurred (%d stale arrivals)" % stale)
	h.eq(net.server.counters["invalid"], 0, "none of it corrupted a packet")
	var in_sync := true
	for i in 2:
		for action in CombatInputState.ACTIONS:
			in_sync = in_sync and absi(int(net.clients[i].builder.counters[action]) - int(net.sim._inputs[net.ids[i]].seen[action])) <= 1
	h.check(in_sync, "no action was lost or double-fired: counters agree to within 1")
	h.check(JSON.stringify(net.sim.snapshot(), "", true, true) == await net.replay_final_snapshot(Callable(_Sturdy, "apply")), "the authoritative state is exactly what the accepted inputs produce")
	var last := {}
	var monotone := true
	for entry in net.server.record:
		if entry["k"] == "in":
			var seq := int(entry["packet"]["sequence"])
			if last.has(entry["p"]) and seq <= int(last[entry["p"]]):
				monotone = false
			last[entry["p"]] = seq
	h.check(monotone, "accepted sequences are strictly increasing per seat")
	net.dispose()


# ---- (i) disconnects ----------------------------------------------------------------------------
static func _sturdy_sim(sim: CombatSimulation) -> void:
	for f in sim.fighters:
		f.health.maximum = 5000
		f.health.current = 5000


static func _sturdy(net) -> void:
	_sturdy_sim(net.sim)


static func _last_input(net, player: String) -> int:
	var last := -1
	for entry in net.server.record:
		if entry["k"] == "in" and entry["p"] == player:
			last = int(entry["t"])
	return last


static func _disconnect(h, tree: SceneTree) -> void:
	h.begin("disconnect: a silent seat is neutralised, the other keeps fighting, it forfeits at exactly 600 server ticks")
	var net = await _new(tree, _cfg(LATENCIES[1], {"seed": 15}), ["p", "p"])
	_sturdy(net)
	var abandoned: Array = []
	net.server.seat_abandoned.connect(func(p): abandoned.append([p, net.sim.server_tick]))
	var drawn: Array = []
	net.server.battle_aborted_draw.connect(func(): drawn.append(net.sim.server_tick))
	net.bots[0] = Bot.new("walker", 91)
	net.bots[0].leash = 2.5
	net.bots[1] = Bot.new("fighter", 92)
	net.run(LIVE + 120)
	net.muted[0] = true  # white's client just stops (no transport notice)
	var hp_at_cut: int = net.sim.fighters[0].health.current
	net.run(40)
	var frozen: Vector3 = net.sim.fighters[0].global_position
	net.run(60)
	h.check(frozen.distance_to(net.sim.fighters[0].global_position) < 0.5, "the silent fighter stops (held controls neutralised after 15 ticks; it was walking)")
	h.check(net.sim.fighters[0].sm.state != CombatConstants.State.BLOCKING, "and is not stuck blocking")
	h.check(net.sim.fighters[1].health.current > 0 and net.sim.fighters[0].health.current <= hp_at_cut, "the other seat keeps playing the fight")
	var last: int = _last_input(net, "player-white")
	net.run_until(func(): return net.server.aborted, 900)
	h.eq(abandoned.size(), 1, "exactly one abandonment")
	h.eq(abandoned[0][0], "player-white", "for the silent seat")
	h.eq(int(abandoned[0][1]) - last, 600, "fired exactly 600 ticks (10.0 s) after its last accepted input (server clock)")
	h.eq(drawn.size(), 0, "not a draw: the other seat is present")
	h.check(net.sim.result.is_empty() and net.result.is_empty(), "NO BattleResult is produced for a forfeit (it bypasses BattleResult)")
	var frozen_tick: int = net.sim.server_tick
	net.run(30)
	h.eq(net.sim.server_tick, frozen_tick, "the aborted battle no longer ticks")
	net.dispose()

	h.begin("disconnect: a transport disconnect notice starts the clock at once and blocks stale packets")
	net = await _new(tree, _cfg(LATENCIES[1], {"seed": 16}))
	_sturdy(net)
	var abandoned2: Array = []
	net.server.seat_abandoned.connect(func(p): abandoned2.append([p, net.sim.server_tick]))
	net.bots[0] = Bot.new("idle", 1)
	net.bots[1] = Bot.new("idle", 2)
	net.run(LIVE + 50)
	var notice_tick: int = net.sim.server_tick
	net.server.set_seat_connected("player-black", false)
	net.run_until(func(): return net.server.aborted, 900)
	h.eq(abandoned2.size(), 1, "forfeit fired")
	h.eq(abandoned2[0][0], "player-black", "for the disconnected seat")
	h.eq(int(abandoned2[0][1]) - notice_tick, 600, "exactly 600 ticks after the notice")
	h.check(net.server.counters["forbidden"] > 100, "its still-arriving packets were refused meanwhile (%d)" % net.server.counters["forbidden"])
	net.dispose()

	h.begin("disconnect: both seats gone = draw; one gone for 5 s then back = no forfeit")
	net = await _new(tree, _cfg(LATENCIES[0], {"seed": 17}))
	_sturdy(net)
	var draws: Array = []
	net.server.battle_aborted_draw.connect(func(): draws.append(net.sim.server_tick))
	var forfeits: Array = []
	net.server.seat_abandoned.connect(func(p): forfeits.append(p))
	net.bots[0] = Bot.new("idle", 1)
	net.bots[1] = Bot.new("idle", 2)
	net.run(LIVE + 30)
	net.muted[0] = true
	net.run(200)
	net.muted[1] = true
	net.run_until(func(): return net.server.aborted, 900)
	h.eq(draws.size(), 1, "both seats gone -> one draw signal")
	h.eq(forfeits.size(), 0, "and no single-seat forfeit")
	h.check(net.sim.result.is_empty(), "no BattleResult")
	net.dispose()

	net = await _new(tree, _cfg(LATENCIES[1], {"seed": 18}))
	_sturdy(net)
	var forfeits2: Array = []
	net.server.seat_abandoned.connect(func(p): forfeits2.append(p))
	net.bots[0] = Bot.new("walker", 5)
	net.bots[0].leash = 2.5
	net.bots[1] = Bot.new("idle", 6)
	net.run(LIVE + 60)
	var accepted_before: int = net.server.counters["accepted"]
	net.muted[0] = true
	net.run(300)  # 5 s away
	var snapshot: Dictionary = net.server.reconnect_seat("player-white")
	h.check(not snapshot.is_empty(), "reconnecting inside the window returns a full snapshot")
	net.muted[0] = false
	net.clients[0].on_snapshot(snapshot, net.tick)
	net.run(120)
	h.check(not net.server.aborted and forfeits2.is_empty(), "no forfeit after returning at 5 s")
	h.check(net.server.counters["accepted"] > accepted_before + 100, "the seat's inputs flow again (%d -> %d accepted)" % [accepted_before, net.server.counters["accepted"]])
	h.eq(net.server.counters["stale"], 0, "the continuing sequence was never stale")
	net.run(700)
	h.check(not net.server.aborted, "and it stays in the fight")
	net.dispose()

	h.begin("disconnect: reconnecting after the window is refused; a restarted client resumes its sequence")
	net = await _new(tree, _cfg(LATENCIES[0], {"seed": 19}))
	_sturdy(net)
	net.bots[0] = Bot.new("walker", 3)
	net.bots[0].leash = 2.5
	net.bots[1] = Bot.new("idle", 4)
	net.run(LIVE + 60)
	var mid_snapshot: Dictionary = net.sim.snapshot()
	var restarted := Client.new(net.request, "player-white", func(p): net.c2s[0].send(p, net.tick))
	restarted.on_snapshot(mid_snapshot, net.tick)
	restarted.resume_after_restart(mid_snapshot)
	net.clients[0] = restarted  # the old process is gone; a new one takes over with fresh counters (none pressed yet)
	net.bots[0] = Bot.new("walker", 3)
	net.bots[0].leash = 2.5
	net.run(60)
	h.eq(net.server.counters["invalid"], 0, "a restarted client that never pressed an action resumes cleanly (sequence continues)")
	var before := int(net.server.counters["accepted"])
	net.run(30)
	h.check(int(net.server.counters["accepted"]) > before + 20, "its inputs are accepted")
	net.muted[0] = true
	net.run_until(func(): return net.server.aborted, 900)
	h.eq(net.server.reconnect_seat("player-white"), {}, "after the forfeit a reconnect is refused")
	net.dispose()

	h.begin("disconnect limitation: a restarted client that HAD pressed actions cannot resume (counters are not in any v1 message)")
	net = await _new(tree, _cfg(LATENCIES[0], {"seed": 20}))
	net.place(Vector3(0, 0, -0.9), Vector3(0, 0, 0.9))
	var pressing = Bot.new("script", 1)
	pressing.hook = func(_bot, client, tick):
		client.set_intent(0.0, 0.0, 0.0, true, false, false)
		if tick == 200:
			client.press("light")
	net.bots[0] = pressing
	net.bots[1] = Bot.new("idle", 2)
	net.run(LIVE + 60)
	var snap2: Dictionary = net.sim.snapshot()
	var fresh := Client.new(net.request, "player-white", func(p): net.c2s[0].send(p, net.tick))
	fresh.on_snapshot(snap2, net.tick)
	fresh.resume_after_restart(snap2)
	net.clients[0] = fresh
	net.bots[0] = Bot.new("idle", 1)
	net.run(30)
	h.check(net.server.counters["invalid"] >= 20, "the server rejects the restarted client's decreasing counters (%d rejected) - documented limitation" % net.server.counters["invalid"])
	net.dispose()


# ---- (j) forgery and lying clients ------------------------------------------------------------------
static func _forgery(h, tree: SceneTree) -> void:
	h.begin("forgery: damage/hp/result fields and lying ack claims gain nothing beyond the cap")
	var net = await _new(tree, _cfg(LATENCIES[0], {"seed": 21}))
	net.place(Vector3(0, 0, -0.9), Vector3(0, 0, 0.9))
	var attacker = Bot.new("script", 1)
	attacker.hook = func(_bot, client, tick):
		client.set_intent(0.0, 0.0, 0.0, true, false, false)
		if tick == 200:
			client.press("light")
	net.bots[0] = attacker
	net.bots[1] = Bot.new("idle", 2)
	var cheat = net.clients[0]
	var original_send: Callable = cheat.send
	cheat.send = func(packet):
		packet["damage"] = 9999
		packet["hp"] = 1000
		packet["result"] = {"winner": "player-white"}
		original_send.call(packet)
	net.run(LIVE + 80)
	h.check(net.server.counters["invalid"] > 50, "every packet carrying damage/hp/result fields was rejected (%d)" % net.server.counters["invalid"])
	h.eq(net.sim.fighters[1].health.current, 80, "the target's HP is untouched")
	h.check(net.sim.result.is_empty(), "no result was forged")
	h.eq(net.sim.fighters[0].sm.state, CombatConstants.State.IDLE, "and the cheater's attack never even started (its inputs were all refused)")
	net.dispose()

	h.begin("forgery: lying about the round trip is bounded by the cap and overridden by transport RTT")
	net = await _new(tree, _cfg(LATENCIES[0], {"seed": 22}))
	net.bots[0] = Bot.new("idle", 1)
	net.bots[1] = Bot.new("idle", 2)
	var liar = net.clients[1]
	var liar_send: Callable = liar.send
	liar.send = func(packet):
		packet["clientTick"] = maxi(0, int(packet["clientTick"]) - 40)  # claims a 40-tick RTT
		liar_send.call(packet)
	net.run(LIVE + 60)
	h.check(net.server.grace_for("player-black") <= CombatSimulation.HIT_GRACE_CAP, "a 40-tick claim yields at most the cap (%d)" % net.server.grace_for("player-black"))
	net.server.set_seat_rtt_ms("player-black", 0.0)
	h.eq(net.server.grace_for("player-black"), 0, "a transport-measured RTT of 0 overrides the claim entirely")
	net.dispose()
