extends RefCounted
## CombatArena adapter: the start_battle / submit_input / apply_snapshot / stop_battle API and
## signals planned for the Battle Chess integration, in AUTHORITY and PRESENTATION modes.

const Codec := preload("res://contracts/codec.gd")
const ARENA := "res://combat/arena.tscn"


static func _arena(tree: SceneTree, mode: int, presentation: bool) -> CombatArena:
	var arena: CombatArena = (load(ARENA) as PackedScene).instantiate()
	arena.mode = mode
	arena.presentation_enabled = presentation
	tree.root.add_child(arena)
	return arena


static func run(h, tree: SceneTree) -> void:
	await _authority(h, tree)
	await _presentation_mode(h, tree)
	await _with_presentation(h, tree)


static func _authority(h, tree: SceneTree) -> void:
	h.begin("adapter: headless authority arena runs a battle and emits snapshots")
	var codec = Codec.new()
	var arena := _arena(tree, CombatArena.Mode.AUTHORITY, false)
	var snapshots: Array = []
	arena.combat_snapshot.connect(func(s): snapshots.append(s))
	var started: Array = []
	arena.battle_started.connect(func(r): started.append(r))
	var reply: Dictionary = arena.start_battle(FighterRoster.build_request("p", "n", "w", "adapter-1", 5, 100))
	h.check(reply["ok"], "start_battle accepts a valid BattleRequest")
	h.eq(started.size(), 1, "battle_started is emitted")
	h.check(not arena.sim.fighters.is_empty(), "the simulation exists")
	for _i in 30:
		await tree.physics_frame
	h.check(snapshots.size() >= 5, "snapshots flow at ~15 Hz while ticking (%d in 30 frames)" % snapshots.size())
	if snapshots.size() > 0:
		h.check(codec.valid("CombatSnapshot", snapshots[0]), "emitted snapshots are valid CombatSnapshots")
	h.check(arena.sim.server_tick > 100, "the arena ticks the simulation from _physics_process (tick %d)" % arena.sim.server_tick)

	var builder := CombatInputBuilder.new("local-match", "adapter-1", "player-white")
	builder.sequence = 0
	h.check(arena.submit_input(builder.build(0.0, 1.0, 0.0, true, false, false))["ok"], "submit_input accepts a valid CombatInput")
	h.eq(arena.submit_input({"nonsense": true})["code"], "INVALID_PAYLOAD", "submit_input rejects malformed input")

	h.begin("adapter: restart replaces the battle; unsupported fighters are refused; stop leaves no result")
	var again: Dictionary = arena.start_battle(FighterRoster.build_request("n", "p", "w", "adapter-2", 6, 0))
	h.check(again["ok"], "start_battle again replaces the running battle")
	h.eq(arena.sim.request["battleId"], "adapter-2", "the new battle is active")
	h.eq(arena.sim.countdown_remaining, 180, "fresh countdown")
	var unimplemented := FighterRoster.build_request("p", "q")
	unimplemented["defender"]["stats"]["abilityId"] = "royal-counter"
	h.eq(arena.start_battle(unimplemented)["code"], "INVALID_PAYLOAD", "an unimplemented ability is refused through the adapter")
	arena.stop_battle()
	h.check(not arena.sim.is_running() and arena.sim.result.is_empty(), "stop_battle ends without fabricating a result")
	arena.queue_free()


static func _presentation_mode(h, tree: SceneTree) -> void:
	h.begin("adapter: presentation mode only draws authoritative snapshots")
	var codec = Codec.new()
	# The "server": a headless authority that produces the snapshots.
	var server := _arena(tree, CombatArena.Mode.AUTHORITY, false)
	server.start_battle(FighterRoster.build_request("p", "n", "w", "adapter-3", 9, 0))
	server.set_physics_process(false)
	var client := _arena(tree, CombatArena.Mode.PRESENTATION, false)
	var finished: Array = []
	client.battle_finished.connect(func(r): finished.append(r))
	h.check(client.start_battle(FighterRoster.build_request("p", "n", "w", "adapter-3", 9, 0))["ok"], "the client prepares the same battle")
	client.set_physics_process(false)
	h.eq(client.submit_input({})["code"], "FORBIDDEN", "a presentation arena refuses inputs (they go to the server)")
	var before_tick: int = client.sim.server_tick

	for _i in 200:
		server.sim.step_tick()
	server.sim.fighters[1].health.current = 90
	server.sim.fighters[1].teleport(Vector3(1.5, 0.0, 0.5), 1.0)
	var snap: Dictionary = server.sim.snapshot()
	client.apply_snapshot(snap)
	h.eq(client.sim.server_tick, snap["serverTick"], "the client adopts the snapshot's tick")
	h.eq(client.sim.fighters[1].health.current, 90, "HP comes from the snapshot")
	h.check(client.sim.server_tick > before_tick, "tick advanced")
	var stale_tick: int = client.sim.server_tick
	var old := snap.duplicate(true)
	old["serverTick"] = stale_tick - 50
	old["fighters"][1]["hp"] = 1
	client.apply_snapshot(old)
	h.eq(client.sim.fighters[1].health.current, 90, "an older snapshot is discarded")
	var bad := snap.duplicate(true)
	bad["serverTick"] = stale_tick + 10
	bad["fighters"][1]["hp"] = 5
	bad["injected"] = true
	client.apply_snapshot(bad)
	h.eq(client.sim.fighters[1].health.current, 90, "a snapshot with an unknown field is ignored")
	h.eq(finished.size(), 0, "no result yet")

	server.sim.fighters[0].health.current = 0
	server.sim.fighters[0].sm.enter_defeated()
	server.sim._check_end()
	client.apply_snapshot(server.sim.snapshot())
	h.eq(finished.size(), 1, "a terminal result in a snapshot emits battle_finished once")
	h.check(codec.valid("BattleResult", finished[0]), "and it is the server's BattleResult")
	client.apply_snapshot(server.sim.snapshot())
	h.eq(finished.size(), 1, "re-delivery does not emit it twice")
	server.queue_free()
	client.queue_free()


static func _with_presentation(h, tree: SceneTree) -> void:
	h.begin("adapter: full presentation (cameras, HUD, visuals, AI seats) builds and runs a fight")
	var arena := _arena(tree, CombatArena.Mode.AUTHORITY, true)
	arena.configure_seats({"player-white": {"type": "ai", "skill": 0.8}, "player-black": {"type": "ai", "skill": 0.6}})
	var results: Array = []
	arena.battle_finished.connect(func(r): results.append(r))
	h.check(arena.start_battle(FighterRoster.build_request("n", "p", "w", "adapter-4", 11, 0))["ok"], "starts with presentation enabled")
	h.eq(arena.cameras.size(), 1, "an AI-vs-AI fight gets one spectator camera")
	h.check(arena.hud != null, "a HUD exists")
	await tree.physics_frame
	await tree.process_frame
	for _i in 120:
		await tree.physics_frame
	h.check(arena.sim.server_tick > 100, "ticking")
	var fighter_visuals := arena.find_children("Visual_*", "", false, false)
	h.eq(fighter_visuals.size(), 2, "both fighters have visuals")
	h.check(not arena.cameras[0].camera.global_position.is_equal_approx(Vector3.ZERO), "the camera was placed")
	h.check(arena.cameras[0].camera.global_position.length() < CombatConstants.ARENA_WALL_RADIUS + 3.7, "the camera stays near the arena wall (the duel intro starts 3.2 m back)")
	arena.start_battle(FighterRoster.build_request("p", "p", "w", "adapter-5", 12, 0))
	await tree.process_frame
	h.eq(arena.find_children("Visual_*", "", false, false).size() + 0 >= 2, true, "a rematch builds fresh visuals")
	arena.stop_battle()
	arena.queue_free()
