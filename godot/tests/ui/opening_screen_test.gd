extends SceneTree
## The 3D opening screen: first state, every kind of "any button", the glide into the menu, reduce motion, quality tiers, "once per
## run", leaks and cleanup. Headless and deterministic: the intro and the scene are advanced with explicit steps (advance(dt)),
## never with the wall clock. Run: godot --headless --path godot --script res://tests/ui/opening_screen_test.gd
const AppScene = preload("res://ui/application.tscn")
const MainScene = preload("res://app/main.tscn")
const Settings = preload("res://ui/application_settings.gd")
const Prefs = preload("res://ui/theme/ui_prefs.gd")
const Kit = preload("res://ui/theme/ui_kit.gd")
const Screen = preload("res://ui/opening/opening_screen.gd")
const OpeningScene = preload("res://ui/opening/opening_scene.gd")
var checks := 0
var failures: Array = []

func expect(value: bool, label: String) -> void:
	checks += 1
	if value and "--verbose" in OS.get_cmdline_user_args():
		print("ok   ", label)
	if not value:
		failures.append(label)
		printerr("FAIL: ", label)

func _initialize() -> void:
	call_deferred("run")

func settle(frames: int = 2) -> void:
	for i in frames:
		await process_frame

# ---------------------------------------------------------------- helpers
func key_event(code: int = KEY_SPACE, pressed: bool = true, echo: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code as Key
	event.pressed = pressed
	event.echo = echo
	return event

func mouse_button(index: int = MOUSE_BUTTON_LEFT, pressed: bool = true) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = index as MouseButton
	event.pressed = pressed
	event.position = Vector2(400, 300)
	return event

func touch(pressed: bool = true) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.pressed = pressed
	event.index = 0
	event.position = Vector2(400, 300)
	return event

func pad_button(index: int = JOY_BUTTON_A, pressed: bool = true) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = index as JoyButton
	event.pressed = pressed
	return event

## A fresh application shell on a fresh run (the intro is due). The intro and the scene are driven by hand.
func fresh_shell(size: Vector2i = Vector2i(1280, 800), manual: bool = true) -> Control:
	Settings.reset_intro()
	root.size = size
	var shell: Control = AppScene.instantiate()
	root.add_child(shell)
	await settle(2)
	if manual:
		if shell.intro != null:
			shell.intro.set_process(false)
		if shell.scene3d != null:
			shell.scene3d.set_process(false)
	return shell

func drop(shell: Control) -> void:
	shell.queue_free()
	await settle(2)

func has_menu(shell: Control) -> bool:
	return shell.content.find_child("ClassicButton", true, false) != null

func camera_position(shell: Control) -> Vector3:
	return shell.scene3d.camera.position

func finish_by_stepping(shell: Control, step: float = 0.4) -> void:
	for i in 12:
		if shell.intro == null:
			return
		shell.intro.advance(step)

func run() -> void:
	Settings.loaded = true
	Settings.token = ""
	Settings.account.clear()
	Settings.launch.clear()
	Settings.quality = "balanced"
	Prefs.path = "user://opening_screen_test.cfg"
	Prefs.loaded = true
	Prefs.reset_defaults()
	Prefs.reduce_motion = false
	Kit.force_touch = false
	pure_checks()
	await first_state_checks()
	await any_button_checks()
	await ignored_input_checks()
	await transition_checks()
	await reduce_motion_checks()
	await quality_checks()
	await once_per_run_checks()
	await navigation_checks()
	await layout_checks()
	await leak_checks()
	await cleanup_checks()
	Kit.force_touch = null
	Prefs.reset_defaults()
	Settings.quality = "balanced"
	Settings.reset_intro()
	var file := "user://opening_screen_test.cfg"
	if FileAccess.file_exists(file):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
	print("Opening screen: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

# ---------------------------------------------------------------- pure logic
func pure_checks() -> void:
	expect(Screen.is_any_button(key_event()), "a key press is an 'any button' event")
	expect(not Screen.is_any_button(key_event(KEY_SPACE, false)), "a key release is not")
	expect(not Screen.is_any_button(key_event(KEY_SPACE, true, true)), "a key repeat (echo) is not")
	expect(Screen.is_any_button(mouse_button(MOUSE_BUTTON_LEFT)) and Screen.is_any_button(mouse_button(MOUSE_BUTTON_RIGHT)), "left and right mouse buttons count")
	expect(not Screen.is_any_button(mouse_button(MOUSE_BUTTON_WHEEL_UP)) and not Screen.is_any_button(mouse_button(MOUSE_BUTTON_WHEEL_DOWN)), "the mouse wheel does not count")
	expect(not Screen.is_any_button(mouse_button(MOUSE_BUTTON_LEFT, false)), "a mouse button release does not count")
	expect(Screen.is_any_button(touch()) and not Screen.is_any_button(touch(false)), "a touch press counts, its release does not")
	expect(Screen.is_any_button(pad_button()) and Screen.is_any_button(pad_button(JOY_BUTTON_START)) and not Screen.is_any_button(pad_button(JOY_BUTTON_A, false)), "any gamepad button press counts")
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(40, 30)
	motion.position = Vector2(300, 300)
	expect(not Screen.is_any_button(motion), "mouse motion never counts")
	var axis := InputEventJoypadMotion.new()
	axis.axis = JOY_AXIS_LEFT_X
	axis.axis_value = 1.0
	expect(not Screen.is_any_button(axis), "a stick / trigger axis never counts")
	expect(is_equal_approx(Screen.ease_glide(0.0), 0.0) and is_equal_approx(Screen.ease_glide(1.0), 1.0) and is_equal_approx(Screen.ease_glide(0.5), 0.5), "the glide easing leaves, passes the middle and arrives exactly")
	var monotonic := true
	var previous := -1.0
	for i in 21:
		var value := Screen.ease_glide(float(i) / 20.0)
		monotonic = monotonic and value >= previous
		previous = value
	expect(monotonic, "the glide easing never goes backwards")
	expect(Screen.ease_glide(0.02) < 0.01 and Screen.ease_glide(0.98) > 0.99, "the glide starts and ends at rest")
	expect(Settings.wants_intro(), "a fresh run wants the intro")
	Settings.intro_seen = true
	expect(not Settings.wants_intro(), "the intro is not wanted again once it was shown")
	Settings.reset_intro()
	expect(Settings.wants_intro(), "tests can reset the once-per-run flag")

# ---------------------------------------------------------------- first state
func first_state_checks() -> void:
	var shell: Control = await fresh_shell()
	expect(shell.page == "home" and shell.intro != null and shell.intro.state == Screen.State.WAITING, "the application's first state is the opening screen (waiting)")
	expect(shell.scene3d != null and shell.scene3d.is_inside_tree() and shell.scene3d.camera != null and shell.scene3d.camera.current, "the 3D scene exists and its camera is current")
	expect(not has_menu(shell), "the main menu is not built before a button is pressed")
	expect(shell.intro.wordmark.text == "PEEPEECHESS" and shell.intro.prompt.text == "Press any button to start", "title and the 'Press any button to start' prompt are shown")
	expect(Settings.intro_seen and not Settings.wants_intro(), "the intro is marked as shown the moment it starts")
	expect(shell._backdrop.mode == "scene", "the flat backdrop gives way to the 3D scene")
	expect(shell.scene3d.blend == 0.0, "the camera starts on the opening shot")
	# the opening is alive: the camera drifts while waiting
	var start: Vector3 = camera_position(shell)
	for i in 10:
		shell.scene3d.advance(1.0)
	expect(camera_position(shell).distance_to(start) > 0.5, "the camera drifts slowly while the screen waits")
	expect(camera_position(shell).distance_to(OpeningScene.CAM_A) < 8.0, "...and stays near the opening shot")
	# prompt pulses
	var low := 2.0
	var high := 0.0
	for i in 24:
		shell.intro.advance(0.1)
		low = minf(low, shell.intro.prompt.modulate.a)
		high = maxf(high, shell.intro.prompt.modulate.a)
	expect(high - low > 0.25 and low >= 0.5 and high <= 1.001, "the prompt pulses between a dim and a full alpha (%.2f..%.2f)" % [low, high])
	expect(shell.intro.state == Screen.State.WAITING, "waiting never ends on its own")
	await drop(shell)

# ---------------------------------------------------------------- any button
func any_button_checks() -> void:
	var kinds := {
		"key": key_event(KEY_SPACE), "enter": key_event(KEY_ENTER), "escape": key_event(KEY_ESCAPE),
		"left mouse button": mouse_button(MOUSE_BUTTON_LEFT), "right mouse button": mouse_button(MOUSE_BUTTON_RIGHT),
		"touch": touch(), "gamepad A": pad_button(JOY_BUTTON_A), "gamepad Start": pad_button(JOY_BUTTON_START), "gamepad shoulder": pad_button(JOY_BUTTON_LEFT_SHOULDER),
	}
	for label in kinds:
		var shell: Control = await fresh_shell()
		root.push_input(kinds[label])
		expect(shell.intro != null and shell.intro.state == Screen.State.TRANSITION, label + " starts the transition")
		expect(shell.page == "home" and not has_menu(shell), label + ": the menu is not there yet (it fades in during the glide)")
		finish_by_stepping(shell)
		expect(shell.intro == null and has_menu(shell) and shell.page == "home", label + ": the transition ends on the main menu")
		expect(is_equal_approx(shell.content.modulate.a, 1.0) and shell.scene3d != null and is_equal_approx(shell.scene3d.blend, 1.0), label + ": menu fully visible over the 3D scene at the menu vantage")
		await drop(shell)

func ignored_input_checks() -> void:
	# the very first frame is ignored: nothing happens before the screen has processed a frame
	Settings.reset_intro()
	root.size = Vector2i(1280, 800)
	var shell: Control = AppScene.instantiate()
	root.add_child(shell)
	root.push_input(key_event(KEY_SPACE))
	expect(shell.intro.state == Screen.State.WAITING, "a press on the very first frame is ignored")
	await settle(2)
	shell.intro.set_process(false)
	shell.scene3d.set_process(false)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(60, 20)
	motion.position = Vector2(500, 400)
	root.push_input(motion)
	expect(shell.intro.state == Screen.State.WAITING, "mouse motion alone does not start the transition")
	var hover := InputEventMouseMotion.new()
	hover.relative = Vector2(5, 0)
	hover.position = Vector2(520, 400)
	hover.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(hover)
	expect(shell.intro.state == Screen.State.WAITING, "dragging the mouse does not either")
	var axis := InputEventJoypadMotion.new()
	axis.axis = JOY_AXIS_LEFT_Y
	axis.axis_value = -1.0
	root.push_input(axis)
	expect(shell.intro.state == Screen.State.WAITING, "a stick deflection does not start it")
	root.push_input(mouse_button(MOUSE_BUTTON_WHEEL_DOWN))
	expect(shell.intro.state == Screen.State.WAITING, "scrolling the wheel does not start it")
	root.push_input(key_event(KEY_A, false))
	root.push_input(key_event(KEY_A, true, true))
	root.push_input(mouse_button(MOUSE_BUTTON_LEFT, false))
	root.push_input(touch(false))
	root.push_input(pad_button(JOY_BUTTON_A, false))
	expect(shell.intro.state == Screen.State.WAITING, "releases and key repeats do not start it")
	root.push_input(key_event(KEY_A))
	expect(shell.intro.state == Screen.State.TRANSITION, "a real key press after all of that does")
	await drop(shell)

# ---------------------------------------------------------------- the glide
func transition_checks() -> void:
	var shell: Control = await fresh_shell()
	var scene = shell.scene3d
	var intro = shell.intro
	var a: Vector3 = camera_position(shell)
	root.push_input(key_event())
	expect(intro.state == Screen.State.TRANSITION and intro.glide == 0.0, "pressing a key begins a glide at t = 0")
	var seen: Array = []
	var blends: Array = []
	for i in 6:
		intro.advance(0.4)
		if intro.state != Screen.State.TRANSITION:
			break
		seen.append(camera_position(shell))
		blends.append(scene.blend)
	var rising := true
	for i in range(1, blends.size()):
		rising = rising and blends[i] >= blends[i - 1]
	expect(blends.size() >= 4 and rising and blends[0] > 0.0 and blends[-1] < 1.0 + 0.0001, "the camera blend rises steadily through the glide")
	expect(seen[0].distance_to(a) > 1.0 and seen[1].distance_to(seen[0]) > 1.0 and seen[2].distance_to(seen[1]) > 1.0, "the camera really travels between samples")
	expect(intro.title_frame.modulate.a < 0.05, "the title has faded out by the middle of the glide")
	expect(has_menu(shell), "the menu was built during the glide")
	# title fades quickly, menu later
	var shell2: Control = await fresh_shell()
	var intro2 = shell2.intro
	root.push_input(key_event())
	intro2.advance(0.2)
	expect(intro2.title_frame.modulate.a > 0.1 and intro2.title_frame.modulate.a < 0.95, "the title is part-way through its fade 0.2 s after the press")
	expect(not intro2.menu_built(), "the menu has not been built that early")
	intro2.advance(0.7)   # 0.9 s
	expect(not intro2.menu_built(), "the menu is held back until the camera is nearly through the gate (0.9 s)")
	intro2.advance(0.9)   # 1.8 s
	expect(intro2.menu_built() and shell2.content.modulate.a > 0.2 and shell2.content.modulate.a < 1.0, "the menu is fading in at 1.8 s while the 3D scene keeps rendering")
	expect(shell2.scene3d.is_inside_tree() and shell2.scene3d.visible, "the scene stays in the tree behind the menu")
	# pressing during the transition must not break anything
	root.push_input(pad_button(JOY_BUTTON_A))   # 1.8 s in: skips to the end
	expect(shell2.intro == null and has_menu(shell2) and shell2.page == "home", "a press late in the glide skips to the finished menu and is not applied to the menu underneath")
	expect(is_equal_approx(shell2.scene3d.blend, 1.0) and is_equal_approx(shell2.content.modulate.a, 1.0), "...with the camera at the menu vantage and the menu fully visible")
	await drop(shell2)
	# a touch also produces an emulated click: the second press right after the first must not skip the glide
	var shell3: Control = await fresh_shell()
	root.push_input(touch())
	root.push_input(mouse_button(MOUSE_BUTTON_LEFT))
	expect(shell3.intro != null and shell3.intro.state == Screen.State.TRANSITION, "a touch plus its emulated click is one press (the glide is not skipped)")
	root.push_input(key_event(KEY_A))
	root.push_input(pad_button(JOY_BUTTON_B))
	expect(shell3.intro != null and shell3.intro.state == Screen.State.TRANSITION, "presses in the first moments of the glide are ignored")
	shell3.intro.advance(0.5)
	root.push_input(key_event(KEY_A, true, true))
	expect(shell3.intro != null, "a key repeat never skips the glide")
	root.push_input(mouse_button(MOUSE_BUTTON_LEFT))
	expect(shell3.intro == null and has_menu(shell3), "a deliberate press after the guard time skips to the menu")
	await drop(shell3)
	# the menu on a finished intro works like the old title page
	var shell4: Control = await fresh_shell()
	root.push_input(key_event())
	finish_by_stepping(shell4)
	var classic: Button = shell4.content.find_child("ClassicButton", true, false)
	classic.pressed.emit()
	expect(shell4.page == "play" and shell4.selected_mode == "classic", "Classic Chess leads to the play page after the intro")
	expect(shell4.scene3d == null, "leaving home frees the 3D scene")
	expect(shell4._backdrop.mode == "page", "...and restores the flat page backdrop")
	await drop(shell4)
	await drop(shell)

# ---------------------------------------------------------------- reduce motion
func reduce_motion_checks() -> void:
	Prefs.reduce_motion = true
	var shell: Control = await fresh_shell()
	expect(shell.intro != null and not shell.scene3d.animated, "reduce motion: the scene is static (no drift, wind, flicker)")
	var before: Vector3 = camera_position(shell)
	shell.scene3d.advance(5.0)
	expect(camera_position(shell).is_equal_approx(before), "reduce motion: the camera does not drift while waiting")
	expect(shell.scene3d.get_node("Embers").visible == false and shell.scene3d.get_node("Crows").visible == false, "reduce motion: embers and crows (pure motion) are hidden")
	shell.intro.advance(0.5)
	expect(is_equal_approx(shell.intro.prompt.modulate.a, 1.0), "reduce motion: the prompt does not pulse")
	root.push_input(key_event())
	expect(shell.intro == null and has_menu(shell), "reduce motion: a press cuts straight to the menu (no glide)")
	expect(is_equal_approx(shell.scene3d.blend, 1.0) and is_equal_approx(shell.content.modulate.a, 1.0), "reduce motion: the camera is already at the menu vantage and the menu fully visible")
	expect(camera_position(shell).distance_to(OpeningScene.CAM_B) < 0.01, "reduce motion: the camera cut lands exactly on the menu pose")
	await drop(shell)
	# a static scene still follows the window: landscape -> portrait switches the camera's fov axis
	var resized: Control = await fresh_shell(Vector2i(1280, 800))
	expect(resized.scene3d.camera.keep_aspect == Camera3D.KEEP_HEIGHT, "landscape window: the camera's fov is vertical")
	root.size = Vector2i(390, 844)
	await settle(2)
	expect(resized.scene3d.camera.keep_aspect == Camera3D.KEEP_WIDTH, "resizing to a portrait window re-frames a static scene (fov becomes horizontal)")
	await drop(resized)
	root.size = Vector2i(1280, 800)
	Prefs.reduce_motion = false

# ---------------------------------------------------------------- quality tiers
func quality_checks() -> void:
	var results := {}
	for level in ["low", "balanced", "high"]:
		Settings.quality = level
		var shell: Control = await fresh_shell()
		var stats: Dictionary = shell.scene3d.stats()
		results[level] = stats
		expect(stats.quality == level, level + ": the scene is built for the quality setting")
		expect(stats.draw_nodes <= 26, level + ": merged geometry keeps the draw-node count low (%d)" % stats.draw_nodes)
		await drop(shell)
	Settings.quality = "balanced"
	expect(results.low.lights < results.balanced.lights and results.balanced.lights <= results.high.lights, "fewer real lights on lower quality (%d / %d / %d)" % [results.low.lights, results.balanced.lights, results.high.lights])
	expect(results.low.lights <= 6 and results.high.lights <= 10, "the real light budget stays small")
	expect(results.low.triangles < results.balanced.triangles and results.balanced.triangles < results.high.triangles, "low quality is a simplified scene (%d / %d / %d triangles)" % [results.low.triangles, results.balanced.triangles, results.high.triangles])
	expect(results.low.embers <= 24 and results.balanced.embers <= 72 and results.high.embers <= 144, "ember particles are capped per quality (%d / %d / %d)" % [results.low.embers, results.balanced.embers, results.high.embers])
	expect(results.low.embers < results.balanced.embers, "low quality uses fewer embers")
	Settings.quality = "low"
	var shell_low: Control = await fresh_shell()
	var scene_low = shell_low.scene3d
	expect(not scene_low.environment.glow_enabled and not scene_low.sun.shadow_enabled, "low quality: no glow post-process and no shadows")
	expect(scene_low.get_node_or_null("Mist") != null and scene_low.get_node("Mist").get_child_count() <= 3, "low quality: only a few mist cards")
	await drop(shell_low)
	Settings.quality = "high"
	var shell_high: Control = await fresh_shell()
	expect(shell_high.scene3d.sun.shadow_enabled and shell_high.scene3d.environment.glow_enabled, "high quality: moon shadows and glow")
	await drop(shell_high)
	Settings.quality = "balanced"
	var shell_mid: Control = await fresh_shell()
	expect(not shell_mid.scene3d.sun.shadow_enabled and not shell_mid.scene3d.environment.glow_enabled, "balanced quality: no shadows, no glow pass (halos are plain additive quads)")
	expect(shell_mid.scene3d.build_msec < 3000.0, "the scene builds lazily in a fraction of a second (%.0f ms, headless)" % shell_mid.scene3d.build_msec)
	await drop(shell_mid)

# ---------------------------------------------------------------- once per run
func once_per_run_checks() -> void:
	var shell: Control = await fresh_shell()
	root.push_input(key_event())
	finish_by_stepping(shell)
	expect(has_menu(shell), "first visit: the intro led to the menu")
	shell.navigate("play")
	await settle(1)
	expect(shell.scene3d == null, "another page replaces the scene")
	shell.navigate("home")
	await settle(2)
	expect(shell.intro == null and has_menu(shell), "returning to home does not replay the intro; the menu is simply there")
	expect(shell.scene3d != null and is_equal_approx(shell.scene3d.blend, 1.0), "...over the 3D castle at the menu vantage")
	expect(shell._backdrop.mode == "scene" and shell._backdrop.center_dim > 0.99, "the backdrop is the scrim over the scene, dimmed behind the menu")
	await drop(shell)
	# coming back from a match builds a new application shell: still no intro
	var again: Control = AppScene.instantiate()
	root.add_child(again)
	await settle(2)
	expect(again.intro == null and has_menu(again) and again.scene3d != null, "a new shell later in the same run (back from a match) shows the menu, not the intro")
	await drop(again)
	# the player who starts directly on the online page never sees it either
	Settings.reset_intro()
	Settings.launch = {"menu": "online", "mode": "classic"}
	var online: Control = AppScene.instantiate()
	root.add_child(online)
	await settle(2)
	expect(online.page == "play" and online.intro == null and online.scene3d == null, "starting on the Play page (online launch) shows no intro and builds no 3D scene")
	expect(not Settings.wants_intro(), "...and counts the title as passed")
	await drop(online)
	Settings.launch.clear()

# ---------------------------------------------------------------- navigation during the intro
func navigation_checks() -> void:
	var shell: Control = await fresh_shell()
	shell.navigate("settings")
	await settle(1)
	expect(shell.intro == null and shell.page == "settings" and shell.scene3d == null, "navigating away during the intro cancels it and frees the scene")
	expect(shell.get_node_or_null("OpeningScreen") == null and shell.get_node_or_null("OpeningScene") == null, "no opening nodes are left behind")
	shell.navigate("home")
	await settle(1)
	expect(shell.intro == null and has_menu(shell), "home afterwards is the menu, never the intro")
	await drop(shell)
	# navigate("home") while the intro waits cuts straight to the menu
	var cut: Control = await fresh_shell()
	cut.navigate("home")
	await settle(1)
	expect(cut.intro == null and has_menu(cut) and cut.scene3d != null and is_equal_approx(cut.scene3d.blend, 1.0), "an explicit navigate('home') during the intro shows the menu at once")
	await drop(cut)
	# the menu on screen: the pad focus helper and settings keep working
	var menu: Control = await fresh_shell()
	root.push_input(key_event())
	finish_by_stepping(menu)
	expect(menu.get_node_or_null("PadUi") != null, "the controller helper is installed alongside the opening screen")
	menu.navigate("settings")
	await settle(1)
	expect(menu.page == "settings" and menu.scene3d == null, "settings page after the intro has no 3D scene")
	await drop(menu)

# ---------------------------------------------------------------- layout
func title_problems(shell: Control, safe: Rect2) -> Array:
	var problems: Array = []
	var intro = shell.intro
	for control in [intro.wordmark, intro.tagline, intro.prompt, intro.caption]:
		var label := control as Label
		var rect := label.get_global_rect()
		if rect.position.x < safe.position.x - 1.0 or rect.end.x > safe.end.x + 1.0 or rect.position.y < safe.position.y - 1.0 or rect.end.y > safe.end.y + 1.0:
			problems.append("%s outside safe area %s vs %s" % [label.name, rect, safe])
		var minimum := label.get_combined_minimum_size()
		if label.size.x + 0.5 < minimum.x or label.size.y + 0.5 < minimum.y:
			problems.append("%s clipped %s < %s" % [label.name, label.size, minimum])
	if intro.wordmark.get_global_rect().intersects(intro.prompt.get_global_rect()) or intro.tagline.get_global_rect().intersects(intro.prompt.get_global_rect()):
		problems.append("title overlaps the prompt")
	if intro.prompt.get_global_rect().intersects(intro.caption.get_global_rect()):
		problems.append("prompt overlaps the caption")
	return problems

func layout_checks() -> void:
	for size in [Vector2i(1280, 800), Vector2i(1280, 720), Vector2i(800, 600), Vector2i(2400, 1080), Vector2i(390, 844), Vector2i(844, 390)]:
		var shell: Control = await fresh_shell(size)
		var view := root.get_visible_rect().size
		var problems := title_problems(shell, Rect2(Vector2.ZERO, view))
		for p in problems:
			printerr("  ", p, " at ", size)
		expect(problems.is_empty(), "the title, tagline, prompt and caption fit without clipping or overlap at %dx%d" % [size.x, size.y])
		expect(shell.scene3d.camera.keep_aspect == (Camera3D.KEEP_HEIGHT if view.x / view.y >= 1.15 else Camera3D.KEEP_WIDTH), "the camera keeps the castle framed at %dx%d (fov axis follows the aspect)" % [size.x, size.y])
		await drop(shell)
	# a notch and a gesture bar: the title stays inside the safe area
	root.size = Vector2i(2400, 1080)
	Settings.reset_intro()
	var shell2: Control = AppScene.instantiate()
	root.add_child(shell2)
	await settle(1)
	var frame: MarginContainer = shell2.intro.title_frame
	frame.inset_override = {"left": 90.0, "top": 30.0, "right": 60.0, "bottom": 40.0}
	frame.apply_margins()
	await settle(2)
	var view2 := root.get_visible_rect().size
	var safe := Rect2(Vector2(90, 30), view2 - Vector2(150, 70))
	var notch_problems := title_problems(shell2, safe)
	expect(notch_problems.is_empty(), "the opening screen respects a simulated notch and gesture-bar inset " + str(notch_problems))
	await drop(shell2)
	# touch devices are told to tap
	Kit.force_touch = true
	var touch_shell: Control = await fresh_shell()
	expect(touch_shell.intro.prompt.text == "Tap to start", "touch devices see 'Tap to start'")
	await drop(touch_shell)
	Kit.force_touch = false
	root.size = Vector2i(1280, 800)

# ---------------------------------------------------------------- leaks and cleanup
func cycle() -> void:
	var shell: Control = await fresh_shell()
	root.push_input(key_event())
	finish_by_stepping(shell)
	shell.navigate("play")
	await settle(1)
	shell.navigate("home")
	await settle(1)
	await drop(shell)

func leak_checks() -> void:
	await cycle()
	await cycle()   # warm-up: caches, the persistent controller adapter
	var nodes := get_node_count()
	var objects := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	for i in 5:
		await cycle()
	var nodes_after := get_node_count()
	var objects_after := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	expect(nodes_after == nodes, "the node count is stable across repeated intro / home cycles (%d -> %d)" % [nodes, nodes_after])
	expect(objects_after - objects < 60, "no resources accumulate across repeated cycles (%d -> %d objects)" % [objects, objects_after])
	expect(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) <= orphans, "no orphaned nodes accumulate")
	expect(root.find_children("*", "Camera3D", true, false).is_empty(), "no 3D camera is left after the application is freed")

func cleanup_checks() -> void:
	var shell: Control = await fresh_shell()
	var scene_ref: WeakRef = weakref(shell.scene3d)
	var intro_ref: WeakRef = weakref(shell.intro)
	expect(scene_ref.get_ref() != null and root.find_children("OpeningScene*", "", true, false).size() == 1, "the scene is part of the application")
	shell.queue_free()
	await settle(2)
	expect(scene_ref.get_ref() == null and intro_ref.get_ref() == null, "freeing the application frees the 3D scene and the opening screen")
	expect(root.find_children("*", "Camera3D", true, false).is_empty() and root.find_children("*", "MeshInstance3D", true, false).is_empty() and root.find_children("*", "Light3D", true, false).is_empty(), "no 3D nodes remain in the tree to keep rendering")
	expect(root.get_camera_3d() == null, "the viewport has no current 3D camera left")
	# a match scene replacing the application scene: nothing of the castle survives
	Settings.reset_intro()
	var shell2: Control = AppScene.instantiate()
	root.add_child(shell2)
	await settle(2)
	root.push_input(key_event())
	finish_by_stepping(shell2)
	Settings.launch = {"mode": "classic", "initialMs": 0, "incrementMs": 0, "view3d": false}
	shell2.queue_free()
	var local = MainScene.instantiate()
	root.add_child(local)
	await settle(3)
	expect(root.find_children("OpeningScene*", "", true, false).is_empty() and root.find_children("OpeningScreen*", "", true, false).is_empty(), "starting a match leaves no opening scene or screen behind")
	local.queue_free()
	await settle(2)
	Settings.launch.clear()
