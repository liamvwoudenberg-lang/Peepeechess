extends SceneTree
## Real startup/menu/local-scene lifecycle under the Compatibility renderer. Run using
## --rendering-driver opengl3_es for GLES validation; this is not a physical Android device test.
const Settings = preload("res://ui/application_settings.gd")
const App = preload("res://ui/application.tscn")
const Model = preload("res://paladins/paladin_model.gd")
const Prefs = preload("res://ui/theme/ui_prefs.gd")
var checks := 0
var failures: Array[String] = []

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)

func _initialize() -> void:
	call_deferred("run")

func settle(frames: int = 6) -> void:
	for frame in frames:
		await process_frame

func report_memory(phase: String) -> void:
	print("RESOURCE_BUDGET phase=%s textures=%d geometry=%d static=%d" % [phase,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED), OS.get_static_memory_usage()])

func run() -> void:
	expect(Settings.default_quality(true) == "low", "new mobile installs start with low graphics")
	expect(Settings.default_quality(false) == "balanced", "desktop retains balanced default")
	var config := ConfigFile.new()
	config.set_value("presentation", "quality", "high")
	expect(config.save("user://preferences.cfg") == OK, "test preference saved")
	Settings.loaded = false
	Settings.load_preferences()
	expect(Settings.quality == "high", "saved high quality is preserved")
	Settings.quality = "low"
	Settings.apply()
	Settings.loaded = true
	Settings.token = ""
	Settings.reset_intro()
	Prefs.loaded = true
	Prefs.reduce_motion = true
	root.size = Vector2i(1280, 720)
	var shell = App.instantiate()
	root.add_child(shell)
	current_scene = shell
	await settle()
	expect(shell.page == "home" and is_instance_valid(shell.scene3d), "real application opens its castle title")
	expect(Model._templates.is_empty(), "title does not allocate Meshy characters")
	report_memory("opening")
	if is_instance_valid(shell.intro):
		shell.intro.press()
	await settle()
	expect(shell.intro == null and shell.content.find_child("ClassicButton", true, false) != null, "opening advances into the real main menu")
	for cycle in 3:
		# The settings page deliberately previews two models. Visit it only after proving the first
		# 2D game remains completely free of Meshy allocations.
		var pages := ["play", "friends", "play"] if cycle == 0 else ["play", "settings", "friends", "play"]
		for page in pages:
			shell.navigate(page)
			await settle(2)
			expect(shell.page == page and not is_instance_valid(shell.scene3d), "menu navigation releases the castle background")
		shell.selected_mode = "classic"
		Settings.preferred_3d = false
		shell.start_local()
		await settle()
		var match_scene = current_scene
		expect(match_scene != shell and is_instance_valid(match_scene.board_2d), "real scene change enters Classic chess")
		expect(match_scene.board_2d.visible and not match_scene.board_3d.visible, "2D opens the actual illustrated board")
		expect(match_scene.board_3d.pieces.is_empty(), "opening 2D creates no hidden Meshy pieces")
		if cycle == 0:
			expect(Model._templates.is_empty() and Model._textures.is_empty(), "first 2D game never loads model templates or textures")
		match_scene.set_view(true)
		await settle()
		expect(match_scene.board_3d.pieces.size() == 32, "switching to 3D creates the complete opening position")
		expect(Model._templates.size() == 12 and Model._textures.size() == 12, "3D keeps a bounded shared model cache")
		report_memory("3d-cycle-%d" % cycle)
		var texture_memory := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)
		expect(texture_memory <= 160 * 1024 * 1024, "3D texture residency stays below the uncompressed 160MiB model ceiling")
		expect(match_scene.game.play("e2", "e4").ok, "the first move works after 2D to 3D transition")
		match_scene.set_view(false)
		await settle()
		expect(match_scene.board_2d.visible and match_scene.board_3d.viewport_3d.render_target_update_mode == SubViewport.UPDATE_DISABLED, "2D disables hidden 3D rendering")
		match_scene.game.new_game()
		match_scene._main_menu()
		await settle()
		shell = current_scene
		expect(is_instance_valid(shell.content) and shell.page == "home", "leaving a match returns to the real menu")
		report_memory("menu-cycle-%d" % cycle)
	root.remove_child(shell)
	shell.free()
	current_scene = null
	Model.release_all()
	await settle()
	# The generated score is asynchronous in rendered runs. Let it release its worker before exit.
	var director := root.get_node_or_null("MusicDirector")
	if director != null:
		director.queue_free()
	await settle()
	if failures.is_empty():
		print("PASS: Android-compatible startup/menu/2D/3D lifecycle (%d checks); physical device not tested" % checks)
	quit(0 if failures.is_empty() else 1)
