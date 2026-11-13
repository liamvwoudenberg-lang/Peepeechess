extends SceneTree
## Full screen mode (ui/screen_mode.gd): default, persistence, invalid stored values, the F11 / Alt+Enter shortcut, the Settings control
## and the places where the window cannot change mode (headless, mobile). A fake window backend stands in for the DisplayServer, so
## everything runs without a window. Every suite gets its own user:// (scripts/test-ui.mjs), so the preferences file starts empty.
const Settings = preload("res://ui/application_settings.gd")
const ScreenMode = preload("res://ui/screen_mode.gd")
const AppScene = preload("res://ui/application.tscn")
const Prefs = preload("res://ui/theme/ui_prefs.gd")
const SettingsPage = preload("res://ui/settings_page.gd")
const CONFIG := "user://preferences.cfg"
var checks := 0
var failures: Array = []
var window_mode := ScreenMode.WINDOWED   # the fake window
var calls: Array = []                    # every mode the fake window was asked for

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL: ", label)

func _initialize() -> void:
	call_deferred("run")

func fake_window() -> void:
	window_mode = ScreenMode.WINDOWED
	calls.clear()
	ScreenMode.backend_set = func(mode: String):
		window_mode = mode
		calls.append(mode)
	ScreenMode.backend_get = func(): return window_mode
	ScreenMode.available_override = 1

func key(code: Key, alt: bool = false, pressed: bool = true, echo: bool = false, ctrl: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	event.alt_pressed = alt
	event.ctrl_pressed = ctrl
	return event

func stored_display() -> String:
	var config := ConfigFile.new()
	return str(config.get_value("presentation", "display", "<missing>")) if config.load(CONFIG) == OK else "<no file>"

func write_config(value: Variant) -> void:
	var config := ConfigFile.new()
	config.set_value("presentation", "display", value)
	config.save(CONFIG)

func reload() -> void:
	Settings.loaded = false
	Settings.display_mode = ScreenMode.WINDOWED
	Settings.load_preferences()

func run() -> void:
	Settings.loaded = true
	Settings.intro_seen = true
	Prefs.path = "user://screen_mode_test_ui.cfg"
	Prefs.loaded = true
	Prefs.reduce_motion = true
	_pure()
	_persistence()
	_unavailable()
	await _shortcut()
	await _settings_page()
	ScreenMode.backend_set = Callable()
	ScreenMode.backend_get = Callable()
	ScreenMode.available_override = -1
	ScreenMode.toggle_handler = Callable()
	print("Screen mode: %d checks, %d failures" % [checks, failures.size()])
	quit(1 if not failures.is_empty() else 0)

# --- the pure rules --------------------------------------------------------------------------------------------------------------
func _pure() -> void:
	expect(ScreenMode.normalise("fullscreen") == "fullscreen" and ScreenMode.normalise("windowed") == "windowed", "known modes are kept")
	for bad in ["", "FULLSCREEN", "Fullscreen", "exclusive", "borderless", "1", "true", " fullscreen"]:
		expect(ScreenMode.normalise(bad) == "windowed", "stored value '%s' falls back to windowed" % bad)
	expect(ScreenMode.normalise(1) == "windowed" and ScreenMode.normalise(true) == "windowed" and ScreenMode.normalise(null) == "windowed" and ScreenMode.normalise([]) == "windowed", "non-string stored values fall back to windowed")
	expect(ScreenMode.is_toggle_event(key(KEY_F11)), "F11 is the shortcut")
	expect(ScreenMode.is_toggle_event(key(KEY_ENTER, true)) and ScreenMode.is_toggle_event(key(KEY_KP_ENTER, true)), "Alt+Enter is the shortcut")
	expect(not ScreenMode.is_toggle_event(key(KEY_ENTER)), "a plain Enter is not the shortcut")
	expect(not ScreenMode.is_toggle_event(key(KEY_ESCAPE)) and not ScreenMode.is_toggle_event(key(KEY_ESCAPE, true)), "Esc is never the shortcut (it releases the combat mouse)")
	expect(not ScreenMode.is_toggle_event(key(KEY_F1)), "F1 stays the controls overlay")
	expect(not ScreenMode.is_toggle_event(key(KEY_F11, false, false)), "a key release does not toggle")
	expect(not ScreenMode.is_toggle_event(key(KEY_F11, false, true, true)), "key auto-repeat does not toggle again")
	expect(not ScreenMode.is_toggle_event(key(KEY_F11, true)) and not ScreenMode.is_toggle_event(key(KEY_F11, false, true, false, true)), "F11 with Alt or Ctrl is left to the OS")
	expect(not ScreenMode.is_toggle_event(InputEventMouseButton.new()) and not ScreenMode.is_toggle_event(InputEventJoypadButton.new()), "only keys toggle")
	var physical := InputEventKey.new()   # a layout where keycode is not reported: the physical key still counts
	physical.physical_keycode = KEY_F11
	physical.pressed = true
	expect(ScreenMode.is_toggle_event(physical), "F11 is recognised by its physical key too")

# --- default, persistence, invalid files -----------------------------------------------------------------------------------------
func _persistence() -> void:
	fake_window()
	reload()   # no preferences file yet
	expect(Settings.display_mode == "windowed", "the default is windowed")
	expect(calls.is_empty(), "start-up in windowed mode does not touch the window (a --fullscreen command line stays in charge)")
	Settings.set_display_mode("fullscreen")
	expect(window_mode == "fullscreen" and calls == ["fullscreen"], "choosing full screen puts the window there")
	expect(stored_display() == "fullscreen", "and saves the choice (presentation/display)")
	calls.clear()
	reload()
	expect(Settings.display_mode == "fullscreen", "the stored choice is read back")
	expect(calls == ["fullscreen"], "start-up applies a stored full screen choice, before anything is shown")
	Settings.quality = "low"
	calls.clear()
	Settings.save_preferences()
	expect(calls.is_empty(), "saving an unrelated preference does not re-apply the window mode (the OS may have left full screen)")
	Settings.set_display_mode("windowed")
	expect(window_mode == "windowed" and stored_display() == "windowed", "back to windowed is applied and saved")
	Settings.quality = "balanced"
	for bad in ["exclusive", "FULLSCREEN", 7, true, ""]:
		write_config(bad)
		calls.clear()
		reload()
		expect(Settings.display_mode == "windowed" and calls.is_empty(), "an invalid stored value (%s) starts windowed and leaves the window alone" % str(bad))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CONFIG))
	reload()
	expect(Settings.display_mode == "windowed", "a missing preferences file starts windowed")
	write_config("fullscreen")
	reload()
	expect(Settings.display_mode == "fullscreen" and window_mode == "fullscreen", "a stored full screen choice survives a restart")
	# reset to defaults returns to windowed
	SettingsPage.reset_defaults()
	expect(Settings.display_mode == "windowed" and window_mode == "windowed" and stored_display() == "windowed", "Reset to defaults leaves full screen")

# --- where the window cannot change mode ---------------------------------------------------------------------------------------------
func _unavailable() -> void:
	fake_window()
	ScreenMode.available_override = 0
	Settings.display_mode = "windowed"
	calls.clear()
	Settings.set_display_mode("fullscreen")
	expect(calls.is_empty() and Settings.display_mode == "windowed", "no window changes where full screen is unavailable (mobile, web, headless)")
	expect(not ScreenMode.toggle() and not ScreenMode.apply("fullscreen") and calls.is_empty(), "toggle and apply report 'not possible' and do nothing")
	ScreenMode.available_override = -1
	expect(DisplayServer.get_name() != "headless" or ScreenMode.available() == false, "this headless process: unavailable")
	# the real backend must not crash headless
	ScreenMode.backend_set = Callable()
	ScreenMode.backend_get = Callable()
	expect(ScreenMode.current() == "windowed", "the real getter is windowed headless")
	expect(not ScreenMode.apply("fullscreen") and not ScreenMode.toggle(), "the real backend is a no-op headless")
	fake_window()

# --- F11 / Alt+Enter through the real input path -------------------------------------------------------------------------------------
func _shortcut() -> void:
	fake_window()
	Settings.display_mode = "windowed"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CONFIG))
	var shell = AppScene.instantiate()   # registers the persistence handler and the PlatformInput node (application_settings.ensure_platform)
	root.add_child(shell)
	for i in 4:
		await process_frame
	var platform = root.get_node_or_null("PlatformInput")
	expect(platform != null, "the shell adds the PlatformInput node that owns the shortcut")
	if platform == null:
		return
	root.set_input_as_handled()
	root.push_input(key(KEY_F11))
	expect(window_mode == "fullscreen" and calls == ["fullscreen"], "F11 enters full screen (delivered through the viewport)")
	expect(Settings.display_mode == "fullscreen" and stored_display() == "fullscreen", "F11 persists the choice")
	root.push_input(key(KEY_F11, false, true, true))
	expect(calls == ["fullscreen"], "a held F11 does not flip it back")
	root.push_input(key(KEY_F11, false, false))
	expect(calls == ["fullscreen"], "releasing F11 does nothing")
	root.push_input(key(KEY_ESCAPE))
	expect(calls == ["fullscreen"] and window_mode == "fullscreen", "Esc does not leave full screen")
	root.push_input(key(KEY_F11))
	expect(window_mode == "windowed" and calls == ["fullscreen", "windowed"] and stored_display() == "windowed", "F11 again returns to windowed and saves it")
	root.push_input(key(KEY_ENTER, true))
	expect(window_mode == "fullscreen" and stored_display() == "fullscreen", "Alt+Enter toggles as well")
	root.push_input(key(KEY_ENTER))
	expect(calls.size() == 3, "plain Enter does not toggle")
	# the event is consumed when it toggles, and left alone where the window cannot change mode
	root.set_input_as_handled()
	platform._input(key(KEY_F11))
	expect(root.is_input_handled(), "a toggling F11 is consumed (nothing else sees it)")
	ScreenMode.available_override = 0
	var before := calls.size()
	var gui_flag_probe := InputEventKey.new()
	gui_flag_probe.keycode = KEY_F11
	gui_flag_probe.pressed = true
	platform._input(gui_flag_probe)
	expect(calls.size() == before, "F11 does nothing where full screen is unavailable")
	ScreenMode.available_override = 1
	shell.queue_free()
	await process_frame

# --- the Settings page ------------------------------------------------------------------------------------------------------------------
func _settings_page() -> void:
	fake_window()
	Settings.display_mode = "windowed"
	var shell = AppScene.instantiate()
	root.add_child(shell)
	for i in 3:
		await process_frame
	shell.navigate("settings")
	for i in 3:
		await process_frame
	var row := shell.find_child("DisplayMode", true, false) as HBoxContainer
	expect(row != null, "Settings has a Display control where full screen is available")
	if row == null:
		shell.queue_free()
		return
	var buttons := row.get_children()
	expect(buttons.size() == 2 and (buttons[0] as Button).text == "Windowed" and (buttons[1] as Button).text == "Full screen", "it offers Windowed and Full screen")
	expect((buttons[0] as Button).button_pressed and not (buttons[1] as Button).button_pressed, "it starts on the real window state (windowed)")
	expect((buttons[0] as Button).focus_mode == Control.FOCUS_ALL and (buttons[1] as Button).focus_mode == Control.FOCUS_ALL, "both choices are focusable (keyboard, D-pad)")
	expect(shell.find_child("DisplayHint", true, false) != null, "the F11 hint is shown")
	(buttons[0] as Button).grab_focus()
	var focus_chain: Array = []
	var current: Control = buttons[0]
	for i in 80:
		focus_chain.append(current)
		current = current.find_next_valid_focus()
		if current == null or current == buttons[0]:
			break
	expect(buttons[1] in focus_chain, "the focus chain of the page reaches Full screen")
	(buttons[1] as Button).button_pressed = true   # what a click or the pad's accept button does
	expect(window_mode == "fullscreen" and Settings.display_mode == "fullscreen" and stored_display() == "fullscreen", "choosing Full screen applies and saves it")
	# F11 while the page is open moves the control with it
	root.push_input(key(KEY_F11))
	expect(window_mode == "windowed" and (buttons[0] as Button).button_pressed and not (buttons[1] as Button).button_pressed and row.get_meta(&"value") == "windowed", "F11 while Settings is open updates the control")
	# a rebuilt page reads the real window, not the stored preference
	window_mode = "fullscreen"
	Settings.display_mode = "windowed"
	shell.navigate("home")
	for i in 3:
		await process_frame
	shell.navigate("settings")
	for i in 3:
		await process_frame
	var rebuilt := shell.find_child("DisplayMode", true, false) as HBoxContainer
	expect(rebuilt != null and (rebuilt.get_child(1) as Button).button_pressed, "a rebuilt page reflects a window that the OS put into full screen")
	# unavailable platform: the control is not offered at all
	ScreenMode.available_override = 0
	shell.navigate("home")
	for i in 3:
		await process_frame
	shell.navigate("settings")
	for i in 3:
		await process_frame
	expect(shell.find_child("DisplayMode", true, false) == null and shell.find_child("DisplayHint", true, false) == null, "no Display control on platforms without window modes (mobile, web)")
	ScreenMode.available_override = 1
	shell.queue_free()
	await process_frame
