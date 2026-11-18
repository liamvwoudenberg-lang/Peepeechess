extends SceneTree
## Real-app smoke playthroughs (software GL under xvfb is fine). Each case asserts state and prints PASS/FAIL; exit code 1 on any failure.
##   xvfb-run -a godot --path godot --rendering-driver opengl3 --script res://combat/tools/qa_smoke.gd -- case=pages [shot=/tmp/qa]
## cases: pages | classic | battle2d | board_world | music_pref (comma-separated or `all`)
const Settings := preload("res://ui/application_settings.gd")
const AppScene := preload("res://ui/application.tscn")
const MainScene := preload("res://app/main.tscn")
const UiPrefs := preload("res://ui/theme/ui_prefs.gd")
const Interaction := preload("res://boards/board_interaction.gd")
const PAGES := ["play", "training", "campaign", "friends", "profile", "history", "leaderboard", "settings"]
const FEN_CAPTURE := "7k/8/8/4q3/3P4/8/8/7K w - - 0 1"
var failures := 0
var _shot := ""


func _initialize() -> void:
	await process_frame
	root.size = Vector2i(1280, 800)
	var wanted := "all"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("case="):
			wanted = arg.substr(5)
		elif arg.begins_with("shot="):
			_shot = arg.substr(5)
	var cases: Array = ["pages", "classic", "battle2d", "board_world", "music_pref", "online_ui"] if wanted == "all" else Array(wanted.split(","))
	for name in cases:
		await call("_case_" + name)
	print("%s: qa_smoke (%d failure(s))" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)


func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", label])


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _snap(name: String) -> void:
	if _shot != "":
		DirAccess.make_dir_recursive_absolute(_shot)
		root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_shot, name])


func _case_pages() -> void:
	Settings.loaded = true
	Settings.token = ""
	Settings.account.clear()
	Settings.launch.clear()
	var shell: Control = AppScene.instantiate()
	root.add_child(shell)
	await _frames(40)
	for page in PAGES:
		shell.navigate(page)
		await _frames(30)
		var visible_controls := 0
		for c in shell.content.find_children("*", "Control", true, false):
			if c.is_visible_in_tree():
				visible_controls += 1
		_check(shell.page == page and visible_controls > 3, "pages: %s opens with content (%d visible controls)" % [page, visible_controls])
		if page in ["play", "settings"]:
			await _snap("page_" + page)
	shell.queue_free()
	await _frames(5)


func _new_app() -> Node:
	Settings.loaded = true
	Settings.launch.clear()
	var app = MainScene.instantiate()
	root.add_child(app)
	await _frames(10)
	return app


func _case_classic() -> void:
	var app = await _new_app()
	app._switch_mode(0)
	app.game.new_game(600000)
	app.board_3d.animation_enabled = false
	await _frames(10)
	# e2e4 e7e5 g1f3 b8c6 f1c4 through the real picking interaction
	var moves := [[12, 28], [52, 36], [6, 21], [57, 42], [5, 26]]
	for m in moves:
		app.interaction.click(m[0])
		app.interaction.click(m[1])
		await _frames(3)
	var state: Dictionary = app.game.chess_state()
	_check(str(state.get("fen", "")).begins_with("r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b"), "classic: five moves played through the interaction (FEN %s)" % str(state.get("fen", "")).get_slice(" ", 0))
	app.queue_free()
	await _frames(5)


func _case_battle2d() -> void:
	var app = await _new_app()
	app._switch_mode(1)
	app.game.new_game(0, 0, FEN_CAPTURE)
	app.board_3d.animation_enabled = false
	app.set_view(false)
	await _frames(20)
	app.interaction.click(27)
	app.interaction.click(36)
	await _frames(30)
	_check(app.battle_flow.phase == "preview", "battle2d: capture from the 2D view opens the preview (phase %s)" % app.battle_flow.phase)
	app._start_battle_pressed()
	await _frames(60)
	_check(app.battle_flow.phase == "combat", "battle2d: start battle reaches combat (phase %s)" % app.battle_flow.phase)
	_check(app.board_3d.visible, "battle2d: the 3D pit world is shown during the duel")
	app.queue_free()
	await _frames(5)


func _case_board_world() -> void:
	var app = await _new_app()
	app._switch_mode(0)
	app.game.new_game(600000)
	app.board_3d.animation_enabled = false
	app.set_view(true)
	await _frames(40)
	var b = app.board_3d
	_check(b.world.find_child("MeshyBoardBase", true, false) != null, "board_world: Meshy board base present")
	var fortress = b.world.find_child("MeshyFortress", true, false)
	_check(fortress != null, "board_world: Meshy fortress present (quality %s)" % PlatformInput.quality)
	if fortress != null:
		var floor_y: float = fortress.global_position.y + (-0.181) * fortress.scale.y
		_check(floor_y <= -0.05 and floor_y >= -0.25, "board_world: fortress courtyard floor sits just under the tiles (y %.2f)" % floor_y)
	_check(b.pieces.size() == 32, "board_world: all 32 pieces are on the board (%d)" % b.pieces.size())
	# Every tile centre must pick its own square through the real camera (nothing covers the board).
	var mismatches := 0
	for at in 64:
		var world_point = b.scene.global_transform * (Interaction.world_position(at) + Vector3(0, 0.04, 0))
		if b.camera.is_position_behind(world_point):
			mismatches += 1
			continue
		var screen: Vector2 = b.camera.unproject_position(world_point)
		var picked: int = b.square_at(screen * b.size / Vector2(b.viewport_3d.size))
		if picked != at:
			mismatches += 1
	_check(mismatches <= 4, "board_world: tile centres pick their own square through the camera (%d/64 off, pieces may occlude)" % mismatches)
	await _snap("board_world")
	app.queue_free()
	await _frames(5)


func _case_music_pref() -> void:
	UiPrefs.path = "user://qa_ui_preferences.cfg"
	UiPrefs.loaded = false
	UiPrefs.load_preferences(true)
	UiPrefs.music_volume = 0.35
	UiPrefs.save_preferences()
	UiPrefs.music_volume = 1.0
	UiPrefs.load_preferences(true)
	_check(is_equal_approx(UiPrefs.music_volume, 0.35), "music_pref: the music slider value persists (%.2f)" % UiPrefs.music_volume)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://qa_ui_preferences.cfg"))
	UiPrefs.path = "user://ui_preferences.cfg"
	UiPrefs.loaded = false


func _texts(node: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for c in node.find_children("*", "Control", true, false):
		if not c.is_visible_in_tree():
			continue
		if c is Button or c is Label:
			out.append(str(c.text))
		elif c is LineEdit:
			out.append(str(c.placeholder_text) + "|" + str(c.text))
	return out


func _case_online_ui() -> void:
	Settings.loaded = true
	Settings.token = ""
	Settings.account.clear()
	Settings.launch.clear()
	var shell: Control = AppScene.instantiate()
	root.add_child(shell)
	await _frames(40)
	shell.online = true
	shell.navigate("play")
	await _frames(40)
	var play_text := " ".join(_texts(shell.content))
	_check(play_text.contains("Host a game on this PC"), "online_ui: Play -> Online shows the host card")
	_check(play_text.contains("Join with invite") or play_text.contains("invite"), "online_ui: Play -> Online shows the join-by-invite flow")
	_check(play_text.contains("relay") or play_text.contains("Relay"), "online_ui: the connection choice mentions the relay")
	await _snap("online_play")
	shell.navigate("settings")
	await _frames(40)
	var settings_text := " ".join(_texts(shell.content))
	_check(settings_text.to_lower().contains("relay"), "online_ui: Settings has the online relay field")
	_check(settings_text.contains("Music"), "online_ui: Settings has the music slider")
	shell.queue_free()
	await _frames(5)
