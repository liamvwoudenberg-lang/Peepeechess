extends RefCounted
## Network layer building blocks: the channel simulator, server input admission and latency
## estimation, client invariants (it can never change HP), cosmetic action prediction, event
## de-duplication, and the simulation's hit-commit grace rules.

const Support := preload("res://combat/tests/test_support.gd")
const Server := preload("res://combat/net/combat_net_server.gd")
const Client := preload("res://combat/net/combat_net_client.gd")
const Channel := preload("res://combat/net/sim_channel.gd")
const S := CombatConstants.State


static func run(h, tree: SceneTree) -> void:
	_channel(h)
	await _server_admission(h, tree)
	await _server_latency_estimate(h, tree)
	await _client_invariants(h, tree)
	await _client_actions(h, tree)
	await _event_dedupe(h, tree)
	await _hit_grace(h, tree)


# ---------------------------------------------------------------------------------------------
static func _channel(h) -> void:
	h.begin("channel: exact latency, ordering, deep copy")
	var ch := Channel.new()
	ch.configure(3)
	var msg := {"a": 1}
	ch.send(msg, 5)
	msg["a"] = 99
	h.eq(ch.poll(7).size(), 0, "nothing before the latency elapses")
	var got: Array = ch.poll(8)
	h.eq(got.size(), 1, "delivered exactly at send + latency")
	h.eq(got[0]["a"], 1, "the sender cannot mutate a packet already on the wire")
	ch.send(1, 10)
	ch.send(2, 10)
	ch.send(3, 11)
	h.eq(ch.poll(14), [1, 2, 3], "equal due ticks keep send order")
	var zero := Channel.new()
	zero.configure(0)
	zero.send("x", 4)
	h.eq(zero.poll(4), ["x"], "zero latency delivers within the same tick")
	h.eq(Channel.ms_to_ticks(50.0), 3, "50 ms is 3 ticks")
	h.eq(Channel.ms_to_ticks(150.0), 9, "150 ms is 9 ticks")

	h.begin("channel: loss, reorder, duplication and determinism")
	var lossy := Channel.new()
	lossy.configure(2, 0, 0.1, 0.0, 0.0, 5)
	for i in 20000:
		lossy.send(i, i)
	var drop_rate := float(lossy.dropped) / float(lossy.sent)
	h.near(drop_rate, 0.1, 0.01, "10%% configured loss measured at %.3f" % drop_rate)
	var reordering := Channel.new()
	reordering.configure(2, 0, 0.0, 0.3, 0.0, 9)
	var order: Array = []
	for i in 400:
		reordering.send(i, i)
		order.append_array(reordering.poll(i))
	order.append_array(reordering.poll(1000))
	h.eq(order.size(), 400, "reordering loses nothing")
	h.check(reordering.reordered > 20, "reordering really produces out-of-order delivery (%d)" % reordering.reordered)
	var duplicating := Channel.new()
	duplicating.configure(1, 0, 0.0, 0.0, 1.0, 3)
	duplicating.send("p", 0)
	h.eq(duplicating.poll(10).size(), 2, "duplicate_chance=1 delivers twice")
	var a := Channel.new()
	var b := Channel.new()
	var c := Channel.new()
	a.configure(2, 2, 0.2, 0.2, 0.1, 42)
	b.configure(2, 2, 0.2, 0.2, 0.1, 42)
	c.configure(2, 2, 0.2, 0.2, 0.1, 43)
	var out_a: Array = []
	var out_b: Array = []
	var out_c: Array = []
	for i in 300:
		a.send(i, i)
		b.send(i, i)
		c.send(i, i)
		out_a.append(a.poll(i))
		out_b.append(b.poll(i))
		out_c.append(c.poll(i))
	h.eq(out_a, out_b, "the same seed reproduces the same schedule")
	h.check(out_a != out_c, "a different seed gives a different schedule")


# ---------------------------------------------------------------------------------------------
static func _server_rig(tree: SceneTree, roles: Array = ["p", "p"], start_tick: int = 0) -> Dictionary:
	var sim := CombatSimulation.new()
	tree.root.add_child(sim)
	var server := Server.new(sim)
	var request := FighterRoster.build_request(roles[0], roles[1], "w", "net-1", 5, start_tick)
	var reply: Dictionary = server.start(request)
	assert(reply["ok"])
	await tree.physics_frame
	return {"sim": sim, "server": server, "request": request,
			"w": CombatInputBuilder.new(request["matchId"], "net-1", "player-white"),
			"b": CombatInputBuilder.new(request["matchId"], "net-1", "player-black")}


static func _dispose(rig: Dictionary) -> void:
	var sim: CombatSimulation = rig["sim"]
	sim.stop()
	if sim.get_parent() != null:
		sim.get_parent().remove_child(sim)
	sim.queue_free()


static func _go_live(rig: Dictionary) -> void:
	for _i in 181:
		rig["server"].step()


static func _server_admission(h, tree: SceneTree) -> void:
	h.begin("server: stale, duplicate, reordered and delayed packets never corrupt state or double-fire")
	var rig := await _server_rig(tree)
	var server = rig["server"]
	var sim: CombatSimulation = rig["sim"]
	sim.fighters[0].teleport(Vector3(0, 0, -0.9), 0.0)
	sim.fighters[1].teleport(Vector3(0, 0, 0.9), PI)
	_go_live(rig)
	var w: CombatInputBuilder = rig["w"]
	var p1 := w.build(0.0, 0.0, 0.0, true, false, false)
	w.press("light")
	var p2 := w.build(0.0, 0.0, 0.0, true, false, false)
	var p3 := w.build(0.0, 0.0, 0.0, true, false, false)
	# Arrive out of order: p3 (carries the press), then p1 and p2 (older -> stale), then p3 again (duplicate).
	h.check(server.receive_input("player-white", p3)["ok"], "newest packet accepted first")
	h.eq(server.receive_input("player-white", p1)["code"], "STALE_INPUT", "older packet arriving late is stale")
	h.eq(server.receive_input("player-white", p2)["code"], "STALE_INPUT", "so is the one between")
	h.eq(server.receive_input("player-white", p3)["code"], "STALE_INPUT", "a duplicate is stale")
	h.eq(server.counters["accepted"], 1, "exactly one packet accepted")
	h.eq(server.counters["stale"], 3, "three rejected as stale")
	server.step()
	h.eq(sim.fighters[0].sm.state, S.ATTACKING, "the press counter carried by the newest packet fired")
	h.near(sim.fighters[0].stamina.current, 110.0, 0.01, "exactly one swing was paid for")
	for _i in 60:
		var again := w.build(0.0, 0.0, 0.0, true, false, false)  # same counters, higher sequence
		server.receive_input("player-white", again)
		server.step()
	h.check(sim.fighters[0].sm.state != S.ATTACKING, "the swing ended; resent counters never re-triggered it")
	h.eq(server.counters["invalid"], 0, "nothing was corrupt")

	h.begin("server: seat authentication, forged fields and delayed held-controls")
	var forged := w.build(0.0, 0.0, 0.0, true, false, false)
	forged["damage"] = 9999
	h.eq(server.receive_input("player-white", forged)["code"], "INVALID_PAYLOAD", "a client cannot smuggle damage into an input")
	var black_builder: CombatInputBuilder = rig["b"]
	var other: Dictionary = black_builder.build(0.0, 0.0, 0.0, true, false, false)
	h.eq(server.receive_input("player-white", other)["code"], "FORBIDDEN", "black's packet submitted on white's authenticated seat is refused")
	h.eq(server.receive_input("player-mallory", w.build(0, 0, 0, true, false, false))["code"], "FORBIDDEN", "unknown seats are refused")
	black_builder.build(0.0, 0.0, PI, true, false, true)  # advance its sequence (a held-block packet that never arrives)
	var delayed: Dictionary = black_builder.build(0.0, 0.0, PI, true, false, true)
	for _i in 30:
		server.step()
	server.receive_input("player-black", delayed)
	server.step()
	h.eq(sim.fighters[1].sm.state, S.BLOCKING, "a fresh held-block packet is applied when it finally arrives")
	for _i in 20:
		server.step()  # 20 ticks of silence > 15
	h.check(sim.fighters[1].sm.state != S.BLOCKING, "held controls neutralise after 15 silent ticks (no phantom block)")
	_dispose(rig)


static func _server_latency_estimate(h, tree: SceneTree) -> void:
	h.begin("server: latency estimate is bounded, monotone-claim and overridable by the transport")
	var rig := await _server_rig(tree)
	var server = rig["server"]
	var w: CombatInputBuilder = rig["w"]
	_go_live(rig)
	var claim := func(age: int) -> void:
		var packet := w.build(0.0, 0.0, 0.0, true, false, false)
		packet["clientTick"] = maxi(0, server.applied_tick() - age)
		server.receive_input("player-white", packet)
		server.step()
	for _i in 12:
		claim.call(4)
	h.eq(server.grace_for("player-white"), 4, "an honest 4-tick round trip -> grace 4")
	for _i in 12:
		claim.call(10)
	h.eq(server.grace_for("player-white"), CombatSimulation.HIT_GRACE_CAP, "a 10-tick claim is capped at %d" % CombatSimulation.HIT_GRACE_CAP)
	for _i in 12:
		claim.call(200)  # absurd/stalled ack: ignored, never extends the window
	h.eq(server.grace_for("player-white"), CombatSimulation.HIT_GRACE_CAP, "a stalled ack does not push grace beyond the cap")
	for _i in 12:
		claim.call(0)
	h.eq(server.grace_for("player-white"), 0, "claiming a zero round trip gives zero grace")
	var future := w.build(0.0, 0.0, 0.0, true, false, false)
	future["clientTick"] = 2000000000
	server.receive_input("player-white", future)
	h.check(server.rtt_ticks("player-white") <= float(server.RTT_SAMPLE_MAX), "a tick from the future is clamped, not trusted")
	server.set_seat_rtt_ms("player-white", 50.0)
	h.eq(server.grace_for("player-white"), 3, "transport-measured 50 ms RTT -> 3 ticks, overriding client claims")
	server.set_seat_rtt_ms("player-white", 5000.0)
	h.eq(server.grace_for("player-white"), CombatSimulation.HIT_GRACE_CAP, "a huge measured RTT is still capped")
	server.grace_enabled = false
	h.eq(server.grace_for("player-white"), 0, "grace can be disabled outright")
	_dispose(rig)


# ---------------------------------------------------------------------------------------------
static func _client_for(rig: Dictionary, player_id: String, sink: Array):
	return Client.new(rig["request"], player_id, func(packet): sink.append(packet))


static func _client_invariants(h, tree: SceneTree) -> void:
	h.begin("client: HP, stamina and results come only from validated snapshots")
	var rig := await _server_rig(tree)
	var server = rig["server"]
	var sim: CombatSimulation = rig["sim"]
	_go_live(rig)
	var sent: Array = []
	var client = _client_for(rig, "player-white", sent)
	h.check(client.view("player-white", 0.0).is_empty(), "no view before the first snapshot")
	var snap: Dictionary = sim.snapshot()
	h.check(client.on_snapshot(snap, 0), "a valid snapshot is applied")
	var hp0: int = int(client.view("player-white", 0.0)["hp"])
	var stamina0: float = float(client.view("player-white", 0.0)["stamina"])
	for tick in range(1, 4001):
		client.set_intent(sin(float(tick) * 0.05), cos(float(tick) * 0.05), float(tick) * 0.01, true, tick % 90 < 20, tick % 150 < 30)
		if tick % 37 == 0:
			client.press("light")
		if tick % 61 == 0:
			client.press("dodge")
		client.tick(tick)
	var view: Dictionary = client.view("player-white", 4000.0)
	h.eq(int(view["hp"]), hp0, "4000 ticks of local play without snapshots leave HP untouched")
	h.near(float(view["stamina"]), stamina0, 0.0001, "and stamina untouched")
	h.check(client.result.is_empty(), "no result can be produced locally")
	h.eq(sent.size(), 4000, "one CombatInput per tick was produced")
	var names: Array = client.get_method_list().map(func(m): return String(m["name"]))
	var bad := names.filter(func(n): return n.contains("damage") or n.contains("set_hp") or n.contains("health") or n.contains("heal") or n.contains("set_result") or n.contains("apply_hit"))
	h.eq(bad, [], "the client class exposes no damage/HP/result mutators")
	var all_valid := true
	var codec = preload("res://contracts/codec.gd").new()
	for p in sent:
		all_valid = all_valid and codec.valid("CombatInput", p)
	h.check(all_valid, "every packet the client produced is a valid CombatInput (intent only)")

	h.begin("client: snapshot ordering, duplicates and invalid snapshots")
	var client2 = _client_for(rig, "player-white", [])
	var s1: Dictionary = sim.snapshot()
	var s0: Dictionary = s1.duplicate(true)
	s0["serverTick"] = int(s1["serverTick"]) - 4
	var s2: Dictionary = s1.duplicate(true)
	s2["serverTick"] = int(s1["serverTick"]) + 4
	h.check(client2.on_snapshot(s1, 0), "first snapshot")
	h.check(not client2.on_snapshot(s0, 1), "an older snapshot is discarded")
	h.check(not client2.on_snapshot(s1, 2), "a duplicate is discarded")
	h.check(client2.on_snapshot(s2, 3), "a newer snapshot advances")
	h.eq(client2.stats["dropped_old"], 2, "two dropped (older + duplicate)")
	var injected: Dictionary = s2.duplicate(true)
	injected["serverTick"] = int(s2["serverTick"]) + 4
	injected["bonusHp"] = 1000
	h.check(not client2.on_snapshot(injected, 4), "a snapshot with an unknown field is rejected")
	var wrong_battle: Dictionary = s2.duplicate(true)
	wrong_battle["serverTick"] = int(s2["serverTick"]) + 8
	wrong_battle["battleId"] = "someone-elses"
	h.check(not client2.on_snapshot(wrong_battle, 5), "a snapshot for another battle is rejected")
	h.eq(client2.stats["rejected"], 2, "two rejected")
	h.eq(int(client2.view("player-white", 5.0)["hp"]), 80, "rejected snapshots changed nothing")
	_dispose(rig)


static func _client_actions(h, tree: SceneTree) -> void:
	h.begin("client: cosmetic action prediction is confirmed, rejected or expires - never authoritative")
	var rig := await _server_rig(tree)
	var server = rig["server"]
	var sim: CombatSimulation = rig["sim"]
	sim.fighters[0].teleport(Vector3(0, 0, -0.9), 0.0)
	sim.fighters[1].teleport(Vector3(0, 0, 0.9), PI)
	_go_live(rig)
	var sent: Array = []
	var client = _client_for(rig, "player-white", sent)
	client.on_snapshot(sim.snapshot(), 0)
	client.set_intent(0, 0, 0, true, false, false)
	client.press("light")
	client.tick(1)
	var view: Dictionary = client.view("player-white", 1.0)
	h.eq(view["predicted_action"], "light", "a press the server would accept is shown at once")
	h.eq(view["state"], "Attacking", "as an Attacking pose")
	h.eq(client.stats["actions_predicted"], 1, "counted")
	# Server accepts it and reports the attack: confirmation.
	server.receive_input("player-white", sent[0])
	server.step()
	server.step()
	server.step()
	server.step()
	client.on_snapshot(sim.snapshot(), 5)
	h.eq(client.stats["actions_confirmed"], 1, "the authoritative snapshot confirms it")
	h.eq(client.view("player-white", 5.0)["predicted_action"], "", "and the prediction is dropped in favour of server state")

	# Not enough stamina: the client does not even predict.
	sim.fighters[1].stamina.lose(500.0)
	var poor_client = _client_for(rig, "player-black", [])
	poor_client.on_snapshot(sim.snapshot(), 0)
	poor_client.press("light")
	h.eq(poor_client.stats["actions_predicted"], 0, "no predicted action without the stamina for it")

	# Server rejects (cooldown/ability gate): acknowledged but still free -> cancelled.
	var sent2: Array = []
	var c3 = _client_for(rig, "player-white", sent2)
	for _i in 100:
		server.step()
	var snap_free: Dictionary = sim.snapshot()
	c3.on_snapshot(snap_free, 0)
	c3.builder.sequence = int(snap_free["fighters"][0]["lastInputSequence"])
	c3.press("ability")  # Last Stand at full HP: the client predicts (it cannot see the HP rule)? it can: hp > 35%
	h.eq(c3.stats["actions_predicted"], 0, "Last Stand is not predicted above its HP threshold")
	c3.press("dodge")
	h.eq(c3.stats["actions_predicted"], 1, "a dodge is predicted")
	c3.tick(1)
	var forged_ack: Dictionary = snap_free.duplicate(true)
	forged_ack["serverTick"] = int(snap_free["serverTick"]) + 4
	forged_ack["fighters"][0]["lastInputSequence"] = int(c3.builder.sequence)
	c3.on_snapshot(forged_ack, 4)
	h.eq(c3.stats["actions_rejected"], 1, "acknowledged while still free = the server refused it: cancelled")
	h.eq(c3.view("player-white", 4.0)["predicted_action"], "", "no lingering ghost action")
	var c4 = _client_for(rig, "player-white", [])
	c4.on_snapshot(snap_free, 0)
	c4.press("parry")
	for tick in range(1, 14):
		c4.tick(tick)
	h.eq(c4.stats["actions_expired"], 1, "an unconfirmed prediction expires after %d ticks" % Client.ACTION_PREDICT_TICKS)
	_dispose(rig)


static func _event_dedupe(h, tree: SceneTree) -> void:
	h.begin("client: events fire exactly once across repeats, reordering and reconnect")
	var rig := await _server_rig(tree)
	var sim: CombatSimulation = rig["sim"]
	_go_live(rig)
	var base: Dictionary = sim.snapshot()
	var fired: Array = []
	var client = _client_for(rig, "player-white", [])
	client.event_confirmed.connect(func(e): fired.append(int(e["eventId"])))
	var make := func(tick: int, ids: Array) -> Dictionary:
		var s: Dictionary = base.duplicate(true)
		s["serverTick"] = tick
		s["events"] = ids.map(func(i): return {"eventId": i, "tick": tick, "type": "hit", "actorPlayerId": "player-white", "targetPlayerId": "player-black", "damage": 12})
		return s
	client.on_snapshot(make.call(200, [1, 2]), 0)
	client.on_snapshot(make.call(204, [1, 2, 3]), 1)   # repeats 1,2 (the server repeats recent events)
	client.on_snapshot(make.call(208, [1, 2, 3, 4]), 2)
	client.on_snapshot(make.call(204, [1, 2, 3]), 3)   # a stale re-delivery
	client.on_snapshot(make.call(208, [1, 2, 3, 4]), 4)  # duplicate
	h.eq(fired, [1, 2, 3, 4], "each event fired once, in order")
	h.eq(client.stats["events"], 4, "four distinct events")
	h.check(client.stats["events_deduped"] >= 8, "repeats were suppressed (%d)" % client.stats["events_deduped"])
	var kept: Array = client.export_dedupe_state()
	var restored = _client_for(rig, "player-white", [])
	restored.import_dedupe_state(kept)
	var refired: Array = []
	restored.event_confirmed.connect(func(e): refired.append(int(e["eventId"])))
	restored.on_snapshot(make.call(212, [1, 2, 3, 4, 5]), 0)
	h.eq(refired, [5], "after a reconnect with saved state only the NEW event fires")
	_dispose(rig)


# ---------------------------------------------------------------------------------------------
## Pawn vs pawn at 1.8 m. White's light attack hits on its 7th active tick.
static func _grace_rig(tree: SceneTree, grace: int):
	var rig = await Support.make_rig(tree, "p", "p")
	rig.face_off()
	rig.to_live()
	rig.sim.set_hit_grace("player-black", grace)
	return rig


static func _hit_tick(rig) -> int:
	var hits: Array = rig.events_of("hit")
	return int(hits[0]["tick"]) if not hits.is_empty() else -1


static func _hit_grace(h, tree: SceneTree) -> void:
	h.begin("hit grace: default 0 is the original behaviour; the cap is enforced")
	var rig = await _grace_rig(tree, 0)
	h.eq(rig.sim.hit_grace("player-black"), 0, "default grace is 0")
	rig.w.press("light")
	rig.tick()
	var start: int = rig.sim.server_tick
	rig.until(func(): return rig.events_of("hit").size() > 0, 30)
	h.eq(_hit_tick(rig) - start, 7, "with grace 0 the hit lands on its detection tick (7)")
	h.eq(rig.sim.pending_hit_count(), 0, "nothing pending")
	rig.sim.set_hit_grace("player-black", 99)
	h.eq(rig.sim.hit_grace("player-black"), CombatSimulation.HIT_GRACE_CAP, "grace is clamped to the cap")
	rig.sim.set_hit_grace("player-black", -3)
	h.eq(rig.sim.hit_grace("player-black"), 0, "and cannot go negative")
	rig.dispose()

	h.begin("hit grace: a hit is held exactly g ticks and resolved once")
	rig = await _grace_rig(tree, 4)
	rig.w.press("light")
	rig.tick()
	start = rig.sim.server_tick
	rig.until(func(): return rig.sim.pending_hit_count() > 0, 30)
	h.eq(rig.sim.server_tick - start, 7, "the hit is DETECTED on tick 7")
	h.eq(rig.black().health.current, 80, "...but not applied yet (pending)")
	rig.until(func(): return rig.events_of("hit").size() > 0, 30)
	h.eq(_hit_tick(rig) - start, 11, "and committed 4 ticks later (7 + 4)")
	h.eq(rig.black().health.current, 68, "the full damage is applied then")
	h.eq(rig.sim.pending_hit_count(), 0, "nothing left pending")
	rig.tick(40)
	h.eq(rig.events_of("hit").size(), 1, "it resolved exactly once")
	rig.dispose()

	h.begin("hit grace: a parry that arrives late (within grace) turns the hit into a parry; beyond it, no")
	# hit detected at step 7; grace 4 -> commit at step 11. Parry window = 11 ticks from its press.
	var results := {}
	for press_step in [9, 11, 12, 15]:
		rig = await _grace_rig(tree, 4)
		for r in range(0, 26):
			if r == 0:
				rig.w.press("light")
			if r == press_step:
				rig.b.press("parry")
			rig.tick()
		results[press_step] = {"parry": rig.events_of("parry").size(), "hit": rig.events_of("hit").size(), "hp": rig.black().health.current}
		rig.dispose()
	h.eq(results[9]["parry"], 1, "parry pressed 2 ticks AFTER the hit was detected: still a parry (inside the grace)")
	h.eq(results[9]["hp"], 80, "no damage")
	h.eq(results[11]["parry"], 1, "pressed on the commit tick: a parry (think precedes resolution)")
	h.eq(results[12]["parry"], 0, "pressed one tick after the commit: too late")
	h.eq(results[12]["hp"], 68, "the hit landed")
	h.eq(results[15]["hit"], 1, "much later: a normal hit")

	h.begin("hit grace: geometry is fixed at detection; already-defended hits resolve at once")
	rig = await _grace_rig(tree, 4)
	for r in range(0, 20):
		if r == 0:
			rig.w.press("light")
		if r == 8:
			rig.black().teleport(Vector3(0.0, 0.0, 5.0), PI)  # steps out of reach while the hit is pending
		rig.tick()
	h.eq(rig.black().health.current, 68, "moving away during the grace does not evade a hit detected earlier")
	rig.dispose()
	rig = await _grace_rig(tree, 6)
	rig.b.block = true
	for r in range(0, 14):
		if r == 0:
			rig.w.press("light")
		rig.tick()
	var block_events: Array = rig.events_of("block")
	h.eq(block_events.size(), 1, "a raised guard resolves the hit immediately")
	h.eq(rig.sim.pending_hit_count(), 0, "nothing was held")
	rig.dispose()

	h.begin("hit grace: nothing stays in flight when the fight is decided or restarted")
	rig = await _grace_rig(tree, 6)
	rig.w.press("light")
	rig.tick()
	rig.until(func(): return rig.sim.pending_hit_count() > 0, 30)
	rig.sim.duration_remaining = 1  # the clock runs out while the hit is pending
	rig.tick()
	h.eq(rig.sim.pending_hit_count(), 0, "the pending hit is flushed before the result")
	h.eq(int(rig.sim.result["defenderHp"]), 68, "so the timeout result already includes it")
	rig.dispose()

	rig = await _grace_rig(tree, 6)
	rig.white().health.current = 1
	rig.w.press("light")
	rig.b.press("light")  # both swing on the same tick: black's hit kills white at once, white's hit on black is pending
	rig.tick()
	rig.until(func(): return rig.sim.phase == CombatSimulation.Phase.FINISHED, 40)
	h.eq(rig.sim.pending_hit_count(), 0, "a knockout flushes pending hits")
	h.eq(rig.black().health.current, 68, "the dying fighter's in-flight hit still landed (no free kills)")
	h.eq(rig.sim.result["reason"], "knockout", "result is a knockout")
	rig.dispose()

	rig = await _grace_rig(tree, 6)
	rig.w.press("light")
	rig.tick()
	rig.until(func(): return rig.sim.pending_hit_count() > 0, 30)
	var again: Dictionary = rig.sim.start(FighterRoster.build_request("p", "p", "w", "t-next", 3, 0))
	h.eq(again["code"], "WRONG_PHASE", "(a running battle cannot be restarted over)")
	rig.sim.stop()
	h.eq(rig.sim.pending_hit_count(), 0, "stop() discards pending hits")
	rig.sim.start(FighterRoster.build_request("p", "p", "w", "t-next", 3, 0))
	h.eq(rig.sim.pending_hit_count(), 0, "a new battle starts with none")
	h.eq(rig.sim.hit_grace("player-black"), 0, "and with grace reset to 0")
	rig.dispose()
