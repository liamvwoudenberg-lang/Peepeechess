extends RefCounted
## CombatArena in online PRESENTATION mode, driven by a real CombatNetServer over a simulated
## 100 ms RTT link (3 ticks each way): what the arena actually puts on its proxy fighters.
## The arena's own CombatNetClient replaces the harness's white client; everything else (server,
## channels, black client) is the harness.

const Harness := preload("res://combat/net/net_harness.gd")
const RemoteInference := preload("res://combat/presentation/remote_action_inference.gd")
const Codec := preload("res://contracts/codec.gd")
const ARENA := "res://combat/arena.tscn"
const S := CombatConstants.State


static func run(h, tree: SceneTree) -> void:
	await _wired(h, tree)
	await _inference(h, tree)
	await _presentation(h, tree)
	await _protocol(h, tree)


static func _make(tree: SceneTree, presentation: bool = false) -> Array:
	var request := FighterRoster.build_request("p", "n", "w", "arena-net-1", 5, 0)
	var net = Harness.new()
	await net.setup(tree, request, {"up": [3, 3], "down": [3, 3], "seed": 3})
	var arena: CombatArena = (load(ARENA) as PackedScene).instantiate()
	arena.mode = CombatArena.Mode.PRESENTATION
	arena.presentation_enabled = presentation
	tree.root.add_child(arena)
	arena.configure_network("player-white", func(packet): net.c2s[0].send(packet, net.tick))
	var reply: Dictionary = arena.start_battle(request)
	assert(reply["ok"], "arena start failed")
	await tree.physics_frame
	arena.set_physics_process(false)  # the test is the clock
	arena.set_process(false)
	net.clients[0] = arena.net_client
	return [net, arena]


static func _step(net, arena, n: int = 1) -> void:
	for _i in n:
		net.step()
		arena._refresh_net_views(float(net.tick))


static func _wired(h, tree: SceneTree) -> void:
	h.begin("arena online: proxy fighters show predicted local / interpolated remote; HP only from snapshots")
	var made: Array = await _make(tree)
	var net = made[0]
	var arena: CombatArena = made[1]
	h.check(arena.net_client != null, "configure_network created a net client")
	h.eq(arena.sim.fighters.size(), 2, "both proxy fighters exist")
	_step(net, arena, 200)  # past the 180-tick countdown
	var white: FighterController = arena.sim.fighters[0]
	var black: FighterController = arena.sim.fighters[1]
	h.eq(arena.sim.countdown_remaining, 0, "countdown state comes from the snapshots")
	h.check(arena.sim.server_tick >= 190, "server tick follows snapshots (%d)" % arena.sim.server_tick)

	arena.net_client.set_intent(0.0, 1.0, 0.0, true, false, false)
	var z0: float = white.global_position.z
	_step(net, arena, 30)
	var predicted_z: float = white.global_position.z
	var server_z: float = net.sim.fighters[0].global_position.z
	h.check(predicted_z - z0 > 0.5, "the local fighter moves immediately (+%.2f m)" % (predicted_z - z0))
	h.check(predicted_z >= server_z - 0.001, "prediction runs ahead of the lagging server position (%.3f vs %.3f)" % [predicted_z, server_z])
	h.check(absf(black.global_position.z - 2.6) < 0.2, "the idle remote fighter stays at its spawn")

	# A predicted action is cosmetic; HP/stamina stay exactly what the last snapshot said.
	var hp_before: int = white.health.current
	var stamina_before: float = white.stamina.current
	arena.net_client.press("light")
	arena._refresh_net_views(float(net.tick))
	h.eq(white.health.current, hp_before, "pressing an attack does not change HP")
	h.near(white.stamina.current, stamina_before, 0.001, "stamina stays as the snapshot said until the server confirms")
	h.eq(white.sm.state, S.ATTACKING, "...but the local animation state reacts at once (predicted)")
	_step(net, arena, 40)
	h.check(net.sim.fighters[0].health.current == white.health.current, "later, HP equals the server's value")

	# Events are de-duplicated even when the same snapshot is delivered repeatedly.
	var seen: Array = []
	arena.net_client.event_confirmed.connect(func(e): seen.append(int(e["eventId"])))
	var snap: Dictionary = net.sim.snapshot()
	snap["serverTick"] = int(snap["serverTick"]) + 100
	for _i in 5:
		arena.apply_snapshot(snap)
	var unique := {}
	for id in seen:
		unique[id] = true
	h.eq(seen.size(), unique.size(), "re-delivered snapshots do not re-fire events (%d events, %d unique)" % [seen.size(), unique.size()])

	var tampered: Dictionary = net.sim.snapshot()
	tampered["serverTick"] = int(tampered["serverTick"]) + 200
	tampered["fighters"][0]["hp"] = 1
	tampered["injected"] = "x"
	var hp_now: int = white.health.current
	arena.apply_snapshot(tampered)
	_step(net, arena, 2)
	h.eq(white.health.current, hp_now, "a snapshot with an unknown field is ignored")

	h.begin("arena online: the server's terminal result reaches the arena exactly once")
	var finished: Array = []
	arena.battle_finished.connect(func(r): finished.append(r))
	net.sim.fighters[1].health.current = 0
	net.sim.fighters[1].sm.enter_defeated()  # the server's own next tick detects the knockout and publishes it
	_step(net, arena, 20)
	h.eq(finished.size(), 1, "battle_finished fired once")
	if finished.size() == 1:
		h.check(Codec.new().valid("BattleResult", finished[0]), "and carries a valid BattleResult")
		h.eq(finished[0]["outcome"], "attacker", "decided by the server (attacker knocked out the defender)")
	_step(net, arena, 20)
	h.eq(finished.size(), 1, "later snapshots do not repeat it")
	net.dispose()
	arena.stop_battle()
	arena.queue_free()


static func _inference(h, tree: SceneTree) -> void:
	h.begin("remote action inference: chain links, heavy detection, ability/parry/dodge pacing")
	var sim := CombatSimulation.new()
	tree.root.add_child(sim)
	sim.start(FighterRoster.build_request("p", "n", "w", "inf-1", 1, 0))
	await tree.physics_frame
	var pawn: FighterController = sim.fighters[0]
	var inf = RemoteInference.new()
	inf.apply(pawn, S.IDLE, 5)
	inf.apply(pawn, S.ATTACKING, 2)
	h.eq(pawn.sm.combo_index, 0, "entering Attacking is light link 1")
	h.eq(pawn.sm.attack_total, 24, "paced to the light's 24 ticks")
	inf.apply(pawn, S.ATTACKING, 18)
	inf.apply(pawn, S.ATTACKING, 3)
	h.eq(pawn.sm.combo_index, 1, "stateTicks going backwards while Attacking = the chain continued (link 2)")
	inf.apply(pawn, S.ATTACKING, 20)
	inf.apply(pawn, S.ATTACKING, 4)
	h.eq(pawn.sm.combo_index, 2, "link 3")
	inf.apply(pawn, S.IDLE, 1)
	inf.apply(pawn, S.ATTACKING, 1)
	h.eq(pawn.sm.combo_index, 0, "after leaving Attacking the chain restarts")
	inf.apply(pawn, S.ATTACKING, 27)
	h.eq(pawn.sm.attack.kind, AttackDefinition.Kind.HEAVY, "running past a light's length means it was a heavy")
	h.eq(pawn.sm.attack_total, 53, "and the clip is re-paced to the heavy's 53 ticks")
	inf.apply(pawn, S.PARRYING, 4)
	h.eq(pawn.sm.parry_total, 11 + 16, "parry paced to window + recovery")
	inf.apply(pawn, S.DODGING, 4)
	h.eq(pawn.sm.dodge_total, 22, "dodge paced to the profile")
	inf.apply(pawn, S.ABILITY_CASTING, 3)
	h.eq(pawn.sm.cast_total, 12, "Last Stand cast paced to its 12 ticks")
	var knight: FighterController = sim.fighters[1]
	var inf2 = RemoteInference.new()
	inf2.apply(knight, S.ABILITY_CASTING, 10)
	h.eq(knight.sm.attack_total, 72, "Lunging Strike is an attack ability paced to 72 ticks")
	sim.stop()
	sim.queue_free()


static func _presentation(h, tree: SceneTree) -> void:
	h.begin("arena online: full presentation (models, HUD, camera, input source) runs under network control")
	var made: Array = await _make(tree, true)
	var net = made[0]
	var arena: CombatArena = made[1]
	h.eq(arena.cameras.size(), 1, "one camera for the local seat")
	var sources := arena.find_children("*", "LocalInputSource", false, false)
	h.eq(sources.size(), 1, "a local input source exists")
	if sources.size() == 1:
		h.check(sources[0].net_client == arena.net_client, "it forwards intent to the net client, not to a local authority")
	_step(net, arena, 200)
	arena.net_client.set_intent(0.3, 1.0, 0.2, true, false, false)
	arena.net_client.press("light")
	for _i in 90:
		_step(net, arena, 1)
		await tree.process_frame
	var visuals := arena.find_children("Visual_*", "", false, false)
	h.eq(visuals.size(), 2, "both fighters have visuals")
	var camera_pos: Vector3 = arena.cameras[0].camera.global_position
	h.check(camera_pos.length() < CombatConstants.ARENA_WALL_RADIUS + 0.5, "the camera follows the predicted fighter inside the arena")
	h.check(net.sim.fighters[1].global_position.distance_to(arena.sim.fighters[1].global_position) < 1.5, "the remote proxy tracks the server fighter (interpolated, %.2f m behind)" % net.sim.fighters[1].global_position.distance_to(arena.sim.fighters[1].global_position))
	net.dispose()
	arena.stop_battle()
	arena.queue_free()


static func _protocol(h, tree: SceneTree) -> void:
	h.begin("external builder: a transport-owned CombatInputBuilder is the single sequence source")
	var shared := CombatInputBuilder.new("m", "b", "player-white")
	shared.sequence = 40
	var req := FighterRoster.build_request("p", "n", "w", "b", 1, 0)
	req["matchId"] = "m"
	var sent: Array = []
	var ext = preload("res://combat/net/combat_net_client.gd").new(req, "player-white", func(packet): sent.append(packet), shared)
	h.check(ext.builder == shared, "the client uses the supplied builder")
	ext.press("light")
	ext.tick(1)
	ext.tick(2)
	h.eq(int(sent[0]["sequence"]), 41, "sequence continues from the transport's builder")
	h.eq(int(sent[0]["light"]), 1, "press counter lives in the shared builder")
	h.eq(int(shared.counters["light"]), 1, "and the transport sees it")

	h.begin("protocol mapping: InputResume lets a restarted client continue; ClockSync feeds the clock")
	var request := FighterRoster.build_request("p", "n", "w", "proto-1", 4, 0)
	var net = Harness.new()
	await net.setup(tree, request, {"up": [2, 2], "down": [2, 2], "seed": 5})
	net.place(Vector3(-4.0, 0.0, 0.0), Vector3(4.0, 0.0, 0.0))
	var resume0: Dictionary = net.server.input_resume("player-white")
	var required := ["battleId", "sequence", "clientTick", "light", "heavy", "dodge", "parry", "ability"]
	var keys: Array = resume0.keys()
	keys.sort()
	var want := required.duplicate()
	want.sort()
	h.eq(keys, want, "input_resume has exactly the fields of Codex's InputResume schema")
	h.eq(int(resume0["sequence"]), 0, "nothing accepted yet")
	net.run(200)
	net.clients[0].press("light")
	net.run(40)
	net.clients[0].press("light")
	net.run(40)
	var resume: Dictionary = net.server.input_resume("player-white")
	h.eq(int(resume["light"]), 2, "the server saw two light presses")
	h.check(int(resume["sequence"]) > 100, "and a long accepted sequence (%d)" % int(resume["sequence"]))
	var stamina_before: float = net.sim.fighters[0].stamina.current

	# The client "crashes": a brand-new client knows nothing (sequence 0, counters 0) until it resumes.
	var fresh = net.Client.new(request, "player-white", func(packet): net.c2s[0].send(packet, net.tick))
	net.clients[0] = fresh
	var rejected_before: int = int(net.server.counters["stale"]) + int(net.server.counters["invalid"])
	net.run(10)  # without resuming, its packets are stale (sequence restarts at 1)
	var rejected_blind: int = int(net.server.counters["stale"]) + int(net.server.counters["invalid"]) - rejected_before
	h.check(rejected_blind > 0, "without InputResume a restarted client is rejected as stale (%d packets)" % rejected_blind)
	h.check(fresh.resume_input(resume), "resume_input accepts this battle's InputResume")
	h.check(not fresh.resume_input({"battleId": "another-battle", "sequence": 1, "light": 0, "heavy": 0, "dodge": 0, "parry": 0, "ability": 0}), "...and refuses another battle's")
	net.run(6)  # packets the blind client sent BEFORE resuming are still in flight and arrive stale: let them drain
	var rejected_mark: int = int(net.server.counters["stale"]) + int(net.server.counters["invalid"])
	var accepted_mark: int = int(net.server.counters["accepted"])
	net.run(30)
	h.eq(int(net.server.counters["stale"]) + int(net.server.counters["invalid"]), rejected_mark, "after resuming nothing is rejected")
	h.check(int(net.server.counters["accepted"]) - accepted_mark >= 25, "its packets are accepted again")
	var after: Dictionary = net.server.input_resume("player-white")
	h.eq(int(after["light"]), 2, "no old press was replayed (counter still 2)")
	h.check(int(after["sequence"]) > int(resume["sequence"]), "sequence continues upward")
	h.check(net.sim.fighters[0].stamina.current >= stamina_before - 0.01, "and no phantom attack spent stamina (it only regenerated: %.1f -> %.1f)" % [stamina_before, net.sim.fighters[0].stamina.current])
	fresh.press("light")
	net.run(10)
	h.eq(int(net.server.input_resume("player-white")["light"]), 3, "a NEW press after resuming counts exactly once")

	var offset_before: float = fresh.clock_offset
	fresh.on_clock_sync(net.sim.server_tick + 50, net.tick)
	h.check(fresh.clock_offset != offset_before, "ClockSync adjusts the clock estimate")
	net.dispose()
