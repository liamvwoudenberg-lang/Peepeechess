extends SceneTree
## Integration through Claude's unchanged arena. Only legitimate input drives damage/results.
const Match = preload("res://chess/battle_match.gd")
const Flow = preload("res://app/battle_flow.gd")
const Adapter = preload("res://app/battle_combat_adapter.gd")
const Builder = preload("res://combat/core/combat_input_builder.gd")
const Main = preload("res://app/main.tscn")
var checks = 0
var failures: Array = []
var game
var adapter
var flow
var host
var errors: Array = []

func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("FAIL: ", label)

func _init() -> void:
	call_deferred("run")

func wait_for_load() -> void:
	var deadline = Time.get_ticks_msec() + 10000
	while flow.phase == "loading" and Time.get_ticks_msec() < deadline:
		await process_frame
	if is_instance_valid(adapter.arena):
		adapter.arena.set_physics_process(false)
	# Collision shapes must reach PhysicsServer before manually advancing ticks.
	await physics_frame
	await process_frame

func fight(from: String, to: String, outcome: String, promotion: String = "q") -> void:
	var before = game.engine.fen()
	var revision = game.revision
	expect(game.play(from, to, promotion).ok and flow.phase == "preview", "real capture preview " + from + to)
	var request = game.pending_request()
	expect(adapter.check_request(request).ok, "combat owner supports both requested roles")
	expect(flow.confirm_capture().ok, "real arena loading accepted")
	await wait_for_load()
	expect(flow.phase == "countdown" and is_instance_valid(adapter.arena), "real arena mounted")
	if not is_instance_valid(adapter.arena):
		return
	var arena = adapter.arena
	expect(arena.seats[game.players.w].scheme == "kb1" and arena.seats[game.players.b].scheme == "kb2", "color owns controls independently of attacker order")
	var winner: Dictionary = request.attacker if outcome == "attacker" else request.defender
	var builders = {}
	for participant in [request.attacker, request.defender]:
		builders[participant.playerId] = Builder.new(request.matchId, request.battleId, participant.playerId)
	var wrong_seat = builders[winner.playerId].build(0, 0, 0, true, false, false)
	expect(adapter.submit_input(wrong_seat, "not-this-seat").code == "FORBIDDEN", "hosting bridge binds input to authenticated seat")
	var bad_packet = wrong_seat.duplicate(true)
	bad_packet["hp"] = 0
	expect(adapter.submit_input(bad_packet, winner.playerId).code == "INVALID_PAYLOAD", "input cannot carry health/results")
	var submitted = true
	# One fighter deliberately attacks; the other sends neutral intent. No HP,
	# positioning, attack states, snapshots, result or simulation constants are edited.
	for tick in range(5580):
		if not arena.sim.is_running():
			break
		for fighter in arena.sim.fighters:
			var builder = builders[fighter.player_id]
			var opponent = arena.sim.opponent_of(fighter)
			var delta: Vector3 = opponent.global_position - fighter.global_position
			delta.y = 0
			var moving = delta.normalized() if fighter.player_id == winner.playerId and delta.length() > 1.15 else Vector3.ZERO
			if fighter.player_id == winner.playerId and tick >= 180 and tick % 40 == 0:
				builder.press("light")
			var reply = adapter.submit_input(builder.build(moving.x, moving.z, atan2(delta.x, delta.z), true, false, false), fighter.player_id)
			submitted = submitted and reply.ok
		arena._physics_process(1.0 / 60.0)
	expect(submitted, "real combat accepts sequential authenticated inputs")
	expect(not arena.sim.result.is_empty(), "real simulation produced terminal result")
	if arena.sim.result.is_empty():
		flow.interrupt()
		return
	expect(arena.sim.result.outcome == outcome and arena.sim.result.reason == "knockout", "input-driven " + outcome + " knockout")
	expect(flow.phase == "aftermath" and game.phase == "aftermath", "real terminal snapshot/result accepted by authority")
	expect(game.engine.fen() == before and game.revision == revision, "board remains frozen through result display")
	var result = arena.sim.result.duplicate(true)
	expect(flow.return_to_board().ok, "real result commits on return")
	flow.advance(1)
	expect(flow.phase == "board" and game.revision == revision + 1 and adapter.arena == null, "arena released and turn consumed once")
	adapter.result_received.emit(result)
	expect(game.revision == revision + 1, "late real result cannot replay settlement")
	await process_frame

func run() -> void:
	game = Match.new()
	adapter = Adapter.new()
	adapter.presentation_enabled = false
	flow = Flow.new()
	host = Node3D.new()
	root.add_child(host)
	root.add_child(adapter)
	root.add_child(flow)
	flow.set_process(false)
	flow.setup(game, adapter, host)
	flow.failed.connect(func(message): errors.append(message))
	game.new_game()
	expect(game.play("e2", "e4").ok and game.play("d7", "d5").ok, "opening uses shared rules")
	await fight("e4", "d5", "attacker")
	expect(game.engine.board[game.engine.index("d5")] == "P", "attacker occupies capture square")
	expect(game.play("g8", "f6").ok and game.play("d2", "d4").ok, "quiet moves between real duels")
	await fight("f6", "d5", "defender")
	expect(game.engine.board[game.engine.index("f6")] == "" and game.engine.board[game.engine.index("d5")] == "P", "defender stays; attacker removed at origin")
	expect(game.play("c2", "c4").ok and game.play("e7", "e5").ok, "prepare en passant in same continuous match")
	await fight("d5", "e6", "attacker")
	expect(game.engine.board[game.engine.index("e5")] == "" and game.engine.board[game.engine.index("e6")] == "P", "real en passant removes off-destination victim")
	expect(game.play("c7", "c6").ok and game.play("d4", "d5").ok, "match continues after special capture")
	await fight("c6", "d5", "attacker")
	expect(game.engine.board[game.engine.index("d5")] == "p" and game.engine.turn == "w", "Black capture advances turn")
	game.resign()
	expect(not game.engine.result.is_empty() and not game.board_input_allowed(), "continuous match reaches terminal condition after repeated real battles")
	game.new_game(0, 0, "7k/5Kpp/5P2/8/8/8/8/8 w - - 0 1")
	await fight("f6", "g7", "attacker")
	expect(game.engine.result == "1-0" and not game.board_input_allowed(), "real capture delivers Battle-legal checkmate without king removal")
	for outcome in ["attacker", "defender"]:
		game.new_game(0, 0, "1n5k/P7/8/8/8/8/8/K7 w - - 0 1")
		await fight("a7", "b8", outcome, "r")
		expect(game.engine.board[game.engine.index("b8")] == ("R" if outcome == "attacker" else "n"), "capture promotion only on attacker win")
	# Real scene accepts mount but refuses malformed stats: message -> error normalization.
	game.new_game(0, 0, "7k/8/8/4p3/3P4/8/8/7K w - - 0 1")
	game.play("d4", "e5")
	flow.confirm_capture()
	await wait_for_load()
	var malformed = game.pending_request()
	malformed.attacker.stats.role = "n"
	var rejected = adapter.start(malformed)
	expect(not rejected.ok and "stats.role" in rejected.error, "combat rejection normalizes its message without script error")
	flow.interrupt()
	expect(game.revision == 0 and game.board_input_allowed(), "interrupted live scene restores board without invented outcome")
	game.new_game(0, 0, "7k/8/8/4q3/3P4/8/8/7K w - - 0 1")
	game.play("d4", "e5")
	var supported = adapter.check_request(game.pending_request())
	expect(supported.ok, "Claude's full C0 roster is available without substitute fighters")
	flow.cancel_preview()
	expect(errors.is_empty(), "no snapshot/result validation failures from real combat: " + str(errors))
	flow.dispose()
	flow.queue_free()
	adapter.queue_free()
	host.queue_free()
	await process_frame
	await presentation(false)
	await presentation(true)
	print("REAL COMBAT INTEGRATION: ", checks, " checks; failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func presentation(use_3d: bool) -> void:
	root.size = Vector2i(1200, 800)
	var app = Main.instantiate()
	root.add_child(app)
	await process_frame
	app.set_world_mode(false)  # legacy full-screen overlay path; the pit-world path is covered by suite "world"
	app._switch_mode(1)
	app.set_view(use_3d)
	app.set_flipped(true)
	app.game.new_game(0, 0, "7k/8/8/4p3/3P4/8/8/7K w - - 0 1")
	app.game.play("d4", "e5")
	app.battle_flow.confirm_capture()
	var deadline = Time.get_ticks_msec() + 10000
	while app.battle_flow.phase == "loading" and Time.get_ticks_msec() < deadline:
		await process_frame
	await process_frame
	await process_frame
	var arena = app.battle_adapter.arena
	expect(is_instance_valid(arena) and app.combat_container.visible, "real arena displays inside application's combat viewport")
	if is_instance_valid(arena):
		expect(arena.cameras.size() == 2 and arena._inputs.size() == 2 and arena._ais.is_empty(), "two real human cameras/controllers; no unintended AI seats")
		expect(arena._visuals.uses_generated_arena, "application mounts Claude's generated arena")
		expect(arena._fighter_visuals.size() == 2 and arena._fighter_visuals.all(func(visual): return visual is CharacterModel and visual.has_clip("light_1") and visual.has_clip("defeat")), "application uses imported animated fighter models")
		var counts = []
		for source in arena._inputs:
			counts.append(source.builder.counters.light)
		for key in [KEY_F, KEY_J]:
			for pressed in [true, false]:
				var event = InputEventKey.new()
				event.physical_keycode = key
				event.keycode = key
				event.pressed = pressed
				Input.parse_input_event(event)
				Input.flush_buffered_events()
				await process_frame
		for index in range(arena._inputs.size()):
			expect(arena._inputs[index].builder.counters.light == counts[index] + 1, "combat keyboard input crosses nested viewport for seat " + str(index))
	app.battle_flow.interrupt()
	expect(app._view_3d == use_3d and app._flipped and app.interaction.enabled, "real scene interruption preserves local board perspective")
	app._switch_mode(0)
	expect(app.game.play("e2", "e4").ok, "Classic remains playable after real combat teardown")
	app.queue_free()
	await process_frame
