extends Node
## Debug-only installed-app smoke test. The normal application mounts this only
## for a private user:// request (adb run-as) or an explicit desktop test flag.
## Android input comes from adb through the real OS input path. Desktop/headless
## checks inject equivalent events and report their platform honestly.
const Settings = preload("res://ui/application_settings.gd")
const Prefs = preload("res://ui/theme/ui_prefs.gd")
const Rules = preload("res://chess/chess_engine.gd")
const Interaction = preload("res://boards/board_interaction.gd")
const REQUEST = "user://playability-smoke.request"
var run_id = ""
var external_input = false
var checks = 0
var failures: Array = []
var stages: Array = []
var _finished = false
var _light_presses = 0
var _receipt: Dictionary = {}

func _ready() -> void:
	call_deferred("run")

func emit_record(event: String, data: Dictionary = {}) -> void:
	var record = data.duplicate(true)
	record["event"] = event
	record["runId"] = run_id
	print("PEEPEECHESS_SMOKE " + JSON.stringify(record, "", true, true))

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures.append(label)
	emit_record("check", {"ok": ok, "label": label})
	return ok

func settle(frames: int = 4) -> void:
	for _i in frames:
		await get_tree().process_frame

func until(condition: Callable, label: String, seconds: float = 12.0) -> bool:
	var deadline = Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return check(condition.call(), label)

func stage(label: String) -> void:
	stages.append(label)
	if external_input:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://playability-smoke.ack"))
	await settle(3)
	emit_record("stage", {"name": label, "staticMemoryBytes": OS.get_static_memory_usage(), "rendered": DisplayServer.get_name() != "headless"})
	if external_input:
		await until(func(): return FileAccess.file_exists("user://playability-smoke.ack"), label + " screenshot captured", 20)

func tap(control: Control, local: Vector2, label: String) -> void:
	var point = control.get_viewport().get_screen_transform() * (control.get_global_transform_with_canvas() * local)
	if external_input:
		emit_record("input", {"action": "tap", "x": roundi(point.x), "y": roundi(point.y), "label": label})
	else:
		for pressed in [true, false]:
			var event = InputEventScreenTouch.new()
			event.index = 0
			event.position = point
			event.pressed = pressed
			Input.parse_input_event(event)
		Input.flush_buffered_events()
	await settle()

func tap_button(button: Button, label: String) -> void:
	await tap(button, button.size * 0.5, label)

func tap_square(screen, square: String) -> void:
	var at = Rules.index(square)
	if screen.board_2d.visible:
		await tap(screen.board_2d, screen.board_2d.square_center(at), square)
	else:
		var board = screen.board_3d
		var point = board.camera.unproject_position(Interaction.world_position(at) + Vector3(0, 0.04, 0)) * board.size / Vector2(board.viewport_3d.size)
		await tap(board, point, square)

func start_match(shell, mode: String, computer: bool):
	shell.selected_mode = mode
	shell.online = false
	shell.ruleset.royal = false
	shell.opponent = {"kind": "computer" if computer else "local", "level": 6, "color": "w"}
	Settings.preferred_3d = mode == "battle"
	var old_id = shell.get_instance_id()
	shell.navigate("play")
	await settle(6)
	var start = null
	for button in shell.find_children("*", "Button", true, false):
		if button.text.begins_with("Play the computer · ") or button.text.begins_with("Start local "):
			start = button
	if not check(start != null and not start.disabled, mode + " start button is available"):
		return null
	shell.page_scroll.ensure_control_visible(start)
	await settle(6)
	await tap_button(start, "start-" + mode)
	if not await until(func(): return get_tree().current_scene != null and get_tree().current_scene.get_instance_id() != old_id, mode + " scene opens"):
		return null
	await settle(8)
	return get_tree().current_scene

func return_menu(screen):
	var old_id = screen.get_instance_id()
	screen._main_menu()
	await settle()
	if get_tree().current_scene != null and get_tree().current_scene.get_instance_id() == old_id:
		var confirmation = null
		for window in screen.find_children("*", "ConfirmationDialog", true, false):
			if window.visible and window.title == "Leave local match?":
				confirmation = window
		if not check(confirmation != null, "leaving an unfinished match asks for confirmation"):
			return null
		await tap_button(confirmation.get_ok_button(), "leave-match")
	if not await until(func(): return get_tree().current_scene != null and get_tree().current_scene.get_instance_id() != old_id, "return to real menu"):
		return null
	await settle(6)
	return get_tree().current_scene

func run() -> void:
	var request = {}
	if FileAccess.file_exists(REQUEST):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(REQUEST))
		if parsed is Dictionary:
			request = parsed
		DirAccess.remove_absolute(ProjectSettings.globalize_path(REQUEST))
	run_id = str(request.get("runId", "desktop-" + str(Time.get_ticks_usec())))
	external_input = request.get("input", "in-process") == "adb"
	emit_record("start", {"platform": OS.get_name(), "version": Engine.get_version_info().string, "rendered": DisplayServer.get_name() != "headless"})
	if not check(OS.is_debug_build(), "smoke runner is debug-only"):
		finish()
		return
	if external_input and not check(OS.get_name() == "Android", "ADB mode runs inside Android"):
		finish()
		return
	# The verifier requires a fresh test install. Never load an account or contact
	# production services; all matches below use the normal local authority.
	Settings.token = ""
	Settings.account.clear()
	Settings.quality = "low"
	Settings.apply()
	await settle(8)
	var shell = get_tree().current_scene
	if not check(shell != null and "intro" in shell, "normal application scene is running"):
		finish()
		return
	await stage("opening")
	if is_instance_valid(shell.intro):
		await tap(shell.intro, shell.intro.size * 0.5, "opening")
		if not await until(func(): return not is_instance_valid(shell.intro), "opening accepts OS input and reaches menu"):
			finish()
			return
	check(shell.page == "home", "home menu is visible")
	await stage("menu")
	var screen = await start_match(shell, "classic", false)
	if screen == null:
		finish()
		return
	check(not screen.game is BattleChessMatch and screen.game.engine.history.is_empty(), "Classic starts from a clean position")
	await get_tree().physics_frame
	await get_tree().physics_frame
	await tap_square(screen, "e2")
	if not await until(func(): return screen.interaction.selected == Rules.index("e2"), "OS touch selects a chess piece"):
		finish()
		return
	await tap_square(screen, "e4")
	if not await until(func(): return screen.game.engine.history.size() == 1, "OS touch commits a legal chess move"):
		finish()
		return
	check(screen.game.engine.history[0].san == "e4", "touch produced the intended move")
	screen.set_view(true)
	await settle(8)
	check(screen.board_3d.visible and screen.board_3d.pieces.size() == 32, "3D renders a complete board")
	await stage("classic-3d")
	shell = await return_menu(screen)
	if shell == null:
		finish()
		return
	screen = await start_match(shell, "battle", true)
	if screen == null:
		finish()
		return
	check(screen.game is BattleChessMatch and screen.opponent.computer.active, "Battle starts against the computer")
	# A small legal fixture reaches a real capture quickly; no winner, HP or result
	# is injected. The actual combat simulation and chess settlement decide it.
	check(screen.game.new_game(0, 0, "7k/8/8/3p4/4P3/8/8/7K b - - 0 1").ok, "capture fixture loads through match admission")
	screen.opponent.computer.cancel_search()
	screen.battle_adapter.prefer_touch = true
	var before_fen = screen.game.engine.fen()
	var revision = screen.game.revision
	screen.battle_flow.phase_changed.connect(func(value): emit_record("battle-phase", {"phase": value}))
	screen.battle_flow.failed.connect(func(message): emit_record("battle-failure", {"message": message}))
	screen.battle_adapter.result_received.connect(func(value): _receipt = value.duplicate(true))
	check(screen.game.play("d5", "e4").ok, "computer capture is admitted")
	check(screen.game.engine.fen() == before_fen and screen.game.revision == revision, "pending capture freezes the board")
	if not await until(func(): return screen.battle_flow.phase == "combat", "computer capture enters real combat automatically", 40):
		emit_record("diagnostic", {"flow": screen.battle_flow.phase, "gamePhase": screen.game.phase, "paused": screen.game.paused, "computerActive": screen.opponent.computer.active, "captureId": screen.opponent._capture_id, "captureRemaining": screen.opponent._capture_remaining, "notice": screen.battle_detail.text, "status": screen.status_label.text, "receipt": _receipt, "fen": screen.game.engine.fen(), "history": screen.game.engine.history.size()})
		finish()
		return
	var arena = screen.battle_adapter.arena
	check(is_instance_valid(arena) and arena.sim.fighters.size() == 2, "two authoritative fighters are running")
	var touch = null
	for source in arena._inputs:
		if source.touch != null:
			touch = source.touch
	if not check(touch != null, "human fighter has actual touch controls"):
		finish()
		return
	touch.action_pressed.connect(func(action): if action == "light": _light_presses += 1)
	await stage("combat")
	await tap(touch, touch.layout().buttons.light.center, "light-attack")
	if not await until(func(): return _light_presses > 0, "OS touch dispatches a combat attack"):
		finish()
		return
	if not await until(func(): return not _receipt.is_empty(), "real combat produces a terminal result", 110):
		finish()
		return
	check(_receipt.reason in ["knockout", "double_knockout", "timeout_hp", "timeout_tie"], "result has a legitimate combat reason")
	check(_receipt.attackerHp == 0 or _receipt.defenderHp == 0 or _receipt.reason.begins_with("timeout"), "combat actually changes health")
	await stage("battle-result")
	if not await until(func(): return screen.battle_flow.phase == "board" and not screen.bridge.is_presenting(), "winner returns through the pit to the board", 35):
		finish()
		return
	check(screen.game.revision == revision + 1 and screen.game.engine.history.size() == 1, "duel commits exactly one chess ply")
	check(screen.game.pending_request().is_empty() and screen.game.registry.size() == 3, "loser is removed and no pending duel remains")
	check(screen.game.play("h1", "h2").ok, "chess continues after the battle")
	screen.opponent.computer.end()
	await stage("returned-board")
	screen.game.resign()
	await settle(6)
	var result_dialog = null
	for window in screen.find_children("*", "AcceptDialog", true, false):
		if window.visible and window.get_ok_button().text == "Review board":
			result_dialog = window
	if not check(result_dialog != null, "finished game displays its result"):
		finish()
		return
	await tap_button(result_dialog.get_ok_button(), "review-result")
	var previous_match = screen.game.match_id
	screen._show_new()
	await settle(6)
	await tap_button(screen.new_dialog.get_ok_button(), "new-game")
	if not await until(func(): return screen.game.match_id != previous_match, "new-game dialog starts another match"):
		finish()
		return
	check(screen.game.engine.history.is_empty() and screen.game.registry.size() == 32, "rematch restores a complete clean board")
	await stage("rematch")
	shell = await return_menu(screen)
	if shell != null:
		check(shell.page == "home", "menu survives a completed play session")
		await stage("final-menu")
	finish()

func finish() -> void:
	if _finished:
		return
	_finished = true
	var result = {"passed": failures.is_empty(), "checks": checks, "failures": failures, "stages": stages, "platform": OS.get_name(), "rendered": DisplayServer.get_name() != "headless"}
	var file = FileAccess.open("user://playability-smoke-result.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result, "", true, true))
		file.close()
	emit_record("result", result)
	get_tree().quit(0 if failures.is_empty() else 1)
