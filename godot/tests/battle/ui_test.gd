extends SceneTree
const Main = preload("res://app/main.tscn")
const Double = preload("res://tests/battle/test_combat_adapter.gd")
const FEN = "7k/8/8/4q3/3P4/8/8/7K w - - 0 1"
var checks = 0
var failures: Array = []
func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("FAIL: ", label)
func _init() -> void:
	call_deferred("run")
func run() -> void:
	root.size = Vector2i(1200, 800)
	var app = Main.instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	# Legacy overlay path regression test; the pit-world path is covered by suite "world".
	app.set_world_mode(false)
	expect(not app.game is BattleChessMatch, "Classic remains the default")
	for use_3d in [false, true]:
		app._switch_mode(1)
		app.battle_adapter.scene_path = "res://tests/battle/not_installed.tscn"
		app.set_view(use_3d)
		app.set_flipped(true)
		app.game.new_game(0, 0, FEN)
		app.game.play("d4", "e5")
		await process_frame
		expect(app.battle_overlay.visible and app.fight_button.disabled, "missing combat scene is disclosed without fallback")
		expect("unavailable" in app.battle_detail.text, "missing combat message")
		app.battle_flow.cancel_preview()
		var fake = Double.new()
		app._configure_battle_flow(fake)
		app.battle_flow.set_process(false)
		app.game.play("d4", "e5")
		await process_frame
		expect(app.battle_overlay.visible and not app.interaction.enabled, "preview locks input")
		expect(not app.fight_button.disabled and "stays on e5" in app.battle_detail.text, "capture preview explains both outcomes")
		if not use_3d:
			await process_frame
			var point = app.fight_button.global_position + app.fight_button.size * 0.5
			for pressed in [true, false]:
				var touch = InputEventScreenTouch.new()
				touch.index = 0
				touch.position = point
				touch.pressed = pressed
				Input.parse_input_event(touch)
				Input.flush_buffered_events()
				await process_frame
			expect(app.battle_flow.phase == "loading", "touch Start battle button")
		else:
			app.battle_flow.confirm_capture()
		expect(not app.board_2d.is_processing_input() and not app.board_3d.is_processing_input(), "board touch handlers cannot consume combat input")
		expect(app.battle_title.text == "Loading arena…", "loading UI")
		fake.complete_load()
		fake.snapshot_received.emit(fake.snapshot(60))
		await process_frame
		expect("2" in app.battle_title.text and app.combat_container.visible, "countdown UI")
		fake.snapshot_received.emit(fake.snapshot(180))
		expect(app.battle_flow.phase == "combat" and not app.battle_card.visible, "combat scene view")
		fake.result_received.emit(fake.winner("defender"))
		expect("Defender wins" in app.battle_detail.text and app.battle_return.visible, "result display")
		app.battle_flow.return_to_board()
		expect(not app.battle_overlay.visible and not app.interaction.enabled, "return animation retains input barrier")
		app.battle_flow.advance(1)
		expect(app._view_3d == use_3d and app.board_2d.flipped and app._flipped, "view and perspective preserved")
		expect(app.interaction.enabled and app.game.revision == 1, "return re-enables board once")
		# Hidden 3D boards synchronise on demand to keep illustrated play lightweight on Android.
		app.set_view(true)
		expect(app.board_2d._current.size() == 3 and app.board_3d.pieces.size() == 3, "both boards show same surviving pieces after on-demand 3D sync")
		app.set_view(use_3d)
		app._switch_mode(0)
		await process_frame
		expect(not app.game is BattleChessMatch and app.game.play("e2", "e4").ok, "Classic remains playable after mode switch")
	app._switch_mode(1)
	app.game.new_game(0, 0, FEN)
	app.size = Vector2(360, 800)
	app._responsive()
	app.game.play("d4", "e5")
	await process_frame
	await process_frame
	expect(app.battle_card.size.x < 360 and app.battle_card.size.y < 720, "preview fits narrow screen")
	app.battle_flow.cancel_preview()
	app.queue_free()
	await process_frame
	print("BATTLE UI: ", checks, " checks; failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
