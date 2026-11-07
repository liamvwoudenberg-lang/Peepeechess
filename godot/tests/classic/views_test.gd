extends SceneTree
const Rules = preload("res://chess/chess_engine.gd")
const Main = preload("res://app/main.tscn")
const Interaction = preload("res://boards/board_interaction.gd")
const Board2D = preload("res://boards/board_2d.gd")
var failures: Array = []
var checks = 0
var app: Control
func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL: ", label)
func _init() -> void:
	call_deferred("run")
func touch(at: Vector2, pressed: bool, finger: int = 0) -> void:
	var event = InputEventScreenTouch.new()
	event.position = at
	event.pressed = pressed
	event.index = finger
	Input.parse_input_event(event)
func tap2d(square: String) -> void:
	var at = app.board_2d.global_position + app.board_2d.square_center(Rules.index(square))
	touch(at, true)
	touch(at, false)
func run() -> void:
	root.size = Vector2i(1200, 800)
	app = Main.instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	app.game.new_game(0)
	app.board_2d.animation_enabled = false
	app.board_3d.animation_enabled = false
	expect(app.board_2d.game == app.game and app.board_3d.game == app.game, "both views share authority")
	for at in range(64):
		for flipped in [false, true]:
			app.board_2d.set_flipped(flipped)
			expect(app.board_2d.square_at(app.board_2d.square_center(at)) == at, "2D square roundtrip")
			expect(Interaction.from_cell(Interaction.cell(at, flipped), flipped) == at, "shared coordinate roundtrip")
	app.set_flipped(false)
	tap2d("e2")
	await process_frame
	expect(app.interaction.selected == Rules.index("e2"), "touch selects piece")
	tap2d("e4")
	await process_frame
	expect(app.game.engine.history.size() == 1 and app.game.engine.history[0].san == "e4", "touch commits legal move")
	var state = app.game.match_state()
	app.set_view(true)
	app.set_flipped(true)
	app.board_3d._orbit(Vector2(50, 20))
	expect(app.game.match_state() == state, "view/flip/orbit never mutate shared state")
	await physics_frame
	await physics_frame
	await process_frame
	# Actual physics rays select square collision geometry, not fake coordinate lookup.
	for square in ["e7", "e5", "a1", "h8", "d4"]:
		var at = Rules.index(square)
		var screen = app.board_3d.camera.unproject_position(Interaction.world_position(at) + Vector3(0, 0.04, 0))
		var local = screen * app.board_3d.size / Vector2(app.board_3d.viewport_3d.size)
		expect(app.board_3d.square_at(local) == at, "3D raycast " + square)
	var source = app.board_3d.camera.unproject_position(Interaction.world_position(Rules.index("e7"))) * app.board_3d.size / Vector2(app.board_3d.viewport_3d.size)
	var target = app.board_3d.camera.unproject_position(Interaction.world_position(Rules.index("e5"))) * app.board_3d.size / Vector2(app.board_3d.viewport_3d.size)
	for point in [source, target]:
		var event = InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = true
		app.board_3d._gui_input(event)
		event.pressed = false
		app.board_3d._gui_input(event)
	expect(app.game.engine.history.size() == 2 and app.game.engine.history[-1].san == "e5", "3D ray input commits move")
	for p in app.game.chess_state().pieces:
		var at = Rules.index(p.square)
		expect(app.board_2d._current[p.pieceId] == at, "2D registry consistency")
		expect(app.board_3d.pieces[p.pieceId].position.is_equal_approx(Interaction.world_position(at)), "3D registry consistency")
	# Touch selection in the 3D SubViewport uses screen coordinates and physics rays.
	for name in ["g1", "f3"]:
		var at = Rules.index(name)
		var local = app.board_3d.camera.unproject_position(Interaction.world_position(at)) * app.board_3d.size / Vector2(app.board_3d.viewport_3d.size)
		touch(app.board_3d.global_position + local, true)
		touch(app.board_3d.global_position + local, false)
		await process_frame
	expect(app.game.engine.history.size() == 3 and app.game.engine.history[-1].san == "Nf3", "3D touch move")
	var before_orbit = app.board_3d.camera.position
	var before_touch_state = app.game.match_state()
	var touch_origin = app.board_3d.global_position + app.board_3d.size * 0.5
	touch(touch_origin, true)
	var drag = InputEventScreenDrag.new()
	drag.index = 0
	drag.position = touch_origin + Vector2(40, 25)
	drag.relative = Vector2(40, 25)
	Input.parse_input_event(drag)
	Input.flush_buffered_events()
	touch(drag.position, false)
	expect(not app.board_3d.camera.position.is_equal_approx(before_orbit) and app.game.match_state() == before_touch_state, "3D touch orbit is local")
	var before_zoom = app.board_3d.distance
	touch(touch_origin, true, 0)
	touch(touch_origin + Vector2(50, 0), true, 1)
	drag = InputEventScreenDrag.new()
	drag.index = 1
	drag.position = touch_origin + Vector2(100, 0)
	drag.relative = Vector2(50, 0)
	Input.parse_input_event(drag)
	Input.flush_buffered_events()
	touch(touch_origin, false, 0)
	touch(drag.position, false, 1)
	expect(app.board_3d.distance < before_zoom, "3D pinch zoom")
	# A second client view has independent orientation; only its state reference is shared.
	var second = Board2D.new()
	root.add_child(second)
	second.size = Vector2(400, 400)
	second.setup(app.game, Interaction.new(app.game))
	second.set_flipped(false)
	app.set_flipped(true)
	expect(not second.flipped and app.board_2d.flipped, "per-client perspective")
	second.interaction.dispose()
	second.queue_free()
	app.set_view(false)
	app.set_flipped(false)
	# Drag and drop through the same pointer handlers as mouse input.
	var b = app.board_2d
	b._pointer_press(b.square_center(Rules.index("g8")))
	b._pointer_move(b.square_center(Rules.index("f6")))
	b._pointer_release(b.square_center(Rules.index("f6")))
	expect(app.game.engine.history[-1].san == "Nf6", "2D drag/drop")
	app.game.new_game(0, 0, "7k/P7/8/8/8/8/8/K7 w - - 0 1")
	tap2d("a7")
	tap2d("a8")
	await process_frame
	expect(app.promotion_dialog.visible and app.game.engine.board[Rules.index("a7")] == "P", "promotion waits for UI choice")
	app._choose_promotion("n")
	expect(app.game.engine.board[56] == "N", "underpromotion UI")
	app.game.new_game(0)
	app.size = Vector2(440, 900)
	app._responsive()
	await process_frame
	await process_frame
	expect(app.body.vertical and app.board_panel.size.x <= 440, "portrait layout")
	var portrait_rect = app.board_2d.board_rect()
	expect(portrait_rect.size.x > 240 and portrait_rect.end.x <= app.board_2d.size.x, "portrait board fits")
	app.size = Vector2(1200, 800)
	app._responsive()
	await process_frame
	await process_frame
	expect(not app.body.vertical, "landscape layout")
	for button in app.mode_select.get_parent().get_children():
		if button is Button and button.text == "New game":
			var point = button.global_position + button.size * 0.5
			touch(point, true)
			touch(point, false)
			Input.flush_buffered_events()
			await process_frame
			expect(app.new_dialog.visible, "Classic new-game button responds to touch")
			app.new_dialog.hide()
	app._show_position()
	await process_frame
	await process_frame
	expect(app.fen_dialog.size.y < 500 and app.fen_dialog.size.x < 750, "FEN dialog fits desktop")
	app.fen_dialog.hide()
	app.size = Vector2(360, 800)
	app._responsive()
	await process_frame
	app._show_position()
	await process_frame
	await process_frame
	expect(app.fen_dialog.size.x <= 360 and app.fen_dialog.size.y < 500, "FEN dialog fits narrow window")
	app.fen_dialog.hide()
	app._show_draw()
	await process_frame
	await process_frame
	expect(app.draw_dialog.size.x <= 360 and app.draw_dialog.size.y < 500, "draw dialog fits narrow window")
	app.draw_dialog.hide()
	app._show_new()
	await process_frame
	await process_frame
	expect(app.new_dialog.size.x <= 360 and app.new_dialog.size.y < 500, "new game dialog fits narrow window")
	app.new_dialog.hide()
	print("VIEWS: ", checks, " checks; failures=", failures.size())
	app.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
