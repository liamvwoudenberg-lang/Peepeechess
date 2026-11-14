extends SceneTree
const Server = preload("res://network/server/dedicated_server.gd")
const Scene = preload("res://network/client/online_lobby.tscn")
var checks = 0
var failures: Array = []
var errors: Array = []
var server
var white
var black
func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL: ", label)
func until(condition: Callable, label: String, seconds: int = 8) -> bool:
	var deadline = Time.get_ticks_msec() + seconds * 1000
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	var passed = condition.call()
	expect(passed, label)
	return passed
func _init() -> void:
	call_deferred("run")
func touch(index: int, position: Vector2, pressed: bool) -> void:
	var event = InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func run() -> void:
	root.size = Vector2i(1200, 850)
	server = Server.new()
	root.add_child(server)
	expect(server.start("127.0.0.1", 24993, "", "", true) == OK, "UI test server starts")
	white = Scene.instantiate()
	black = Scene.instantiate()
	root.add_child(white)
	root.add_child(black)
	for app in [white, black]:
		app.set_anchors_preset(Control.PRESET_TOP_LEFT)
		app.size = Vector2(600, 850)
		app.history.visible = false
		app.client.protocol_error.connect(func(error): errors.append(error.code + ": " + error.message))
	white.position = Vector2.ZERO
	black.position = Vector2(600, 0)
	white.set_view(false)
	black.set_view(true)
	black.set_flipped(true)
	white.client.connect_server("127.0.0.1", 24993, "", true)
	black.client.connect_server("127.0.0.1", 24993, "", true)
	if not await until(func(): return white.client.authenticated and black.client.authenticated, "two UI clients authenticate separately"):
		cleanup()
		return
	white.client.create_match("battle", 0)
	if not await until(func(): return not white.client.frame.is_empty(), "creator gets authoritative lobby"):
		cleanup()
		return
	black.client.join_match(white.client.frame.state.matchId)
	if not await until(func(): return not black.client.frame.is_empty(), "second UI joins private invite"):
		cleanup()
		return
	white.client.command("ready")
	black.client.command("ready")
	await until(func(): return white.client.frame.status == "active" and black.client.frame.status == "active", "both ready activates match")
	expect(white.game.board_input_allowed() and not black.game.board_input_allowed(), "UI only allows authenticated acting seat")
	white.game.play("e2", "e4")
	await until(func(): return white.game.revision == 1 and black.game.revision == 1, "first move synchronizes both projections")
	black.game.play("d7", "d5")
	await until(func(): return white.game.revision == 2 and black.game.revision == 2, "reply synchronizes both projections")
	var frozen = white.game.engine.fen()
	white._move("e4", "d5", "q")
	expect(white.capture_dialog.visible and white.game.engine.fen() == frozen, "online capture preview leaves server board unchanged")
	white._confirm_capture()
	if not await until(func(): return white.combat_view.arena != null and black.combat_view.arena != null, "both clients mount the real online combat presentation"):
		cleanup()
		return
	for app in [white, black]:
		var arena = app.combat_view.arena
		expect(arena.hud is CourtyardCombatHud, "online view installs compact read-only HUD")
		expect(not app._chess_chrome.visible and app.combat_container.get_parent() == app, "online fight hides all chess chrome and fills the window")
		expect(arena.mode == CombatArena.Mode.PRESENTATION and arena._ais.is_empty() and arena._inputs.is_empty(), "online arena cannot simulate authoritative attacks or install AI")
		var before = arena.sim.server_tick
		arena._physics_process(1.0 / 60.0)
		expect(arena.sim.server_tick == before, "client arena physics never advances authority")
		expect(arena.cameras.size() == 1 and arena.cameras[0].target.player_id == app.client.player_id, "each client independently views its own fighter")
		expect(not app.board_2d.is_processing_input() and not app.board_3d.is_processing_input(), "board handlers yield input during network combat")
		expect(not app.board_2d.visible and not app.board_3d.visible, "hidden board GUI cannot consume combat mouse input")
	white.touch_toggle.button_pressed = true
	white._set_touch(true)
	expect(not white.combat_view.source.enabled and white.touch_controls.enabled, "touch adapter replaces keyboard packet production")
	await until(func(): return not white.client.latest_combat.is_empty() and white.client.latest_combat.countdownTicksRemaining == 0, "server countdown reaches active combat")
	white.touch_controls._layout()
	var up: Rect2 = white.touch_controls._regions.up
	touch(0, white.touch_controls.global_position + up.get_center(), true)
	for _i in range(70):
		await physics_frame
	touch(0, white.touch_controls.global_position + up.get_center(), false)
	var mine = white.client.latest_combat.fighters.filter(func(f): return f.playerId == white.client.player_id)[0]
	expect(mine.position.z > -0.5, "virtual movement travels through network to authoritative fighter")
	var light: Rect2 = white.touch_controls._regions.light
	for _attack in range(90):  # duels last ~30 s now (BALANCE.md duel length): keep attacking until the fight is decided
		if white.client.frame.state.phase != "combat":
			break
		touch(1, white.touch_controls.global_position + light.get_center(), true)
		await physics_frame
		touch(1, white.touch_controls.global_position + light.get_center(), false)
		for _i in range(40):
			await physics_frame
	if not await until(func(): return white.game.revision == 3 and black.game.revision == 3, "real network touch duel commits once and returns to both boards", 12):
		cleanup()
		return
	expect(white.game.engine.fen() == black.game.engine.fen() and white.game.engine.board[ClassicChess.index("d5")] == "P", "clients agree on attacker victory and capture square")
	expect(not white.combat_container.visible and not black.combat_container.visible, "server settlement tears down both combat views")
	expect(not white._view_3d and black._view_3d and black._flipped, "board and perspective preferences stay independent after combat")
	expect(white.board_2d._current.size() == 31 and black.board_3d.pieces.size() == 31, "2D and 3D survivor registries match authority")
	expect(not white.game.board_input_allowed() and black.game.board_input_allowed(), "acting turn advances on both clients")
	expect(errors.is_empty(), "normal network presentation produces no error banners: " + str(errors))
	cleanup()
func cleanup() -> void:
	white.queue_free()
	black.queue_free()
	server.queue_free()
	await process_frame
	print("ONLINE UI: ", checks, " checks; failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
