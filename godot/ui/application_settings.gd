extends RefCounted
## Presentation and launch data only. Competitive state never lives here.
const Platform = preload("res://ui/platform_input.gd")
const ScreenMode = preload("res://ui/screen_mode.gd")
static var _platform: Node
static var preferred_3d = false
static var animations = true
static var quality = "balanced"
static var volume = 0.8
static var touch_controls = false
## "windowed" or "fullscreen" (ui/screen_mode.gd). Desktop only; the choice is kept per device and applied once at start-up.
static var display_mode = "windowed"
static var api_url = "http://127.0.0.1:8787"
static var token = ""
static var account: Dictionary = {}
static var launch: Dictionary = {}
static var result: Dictionary = {}
static var loaded = false
## The 3D opening screen plays once per application run (process), not every time the player returns to the main menu.
## It is marked as seen the moment it starts. Tests reset it with reset_intro(); `--no-intro` on the command line skips it.
static var intro_seen = false

static func load_preferences() -> void:
	if loaded:
		return
	loaded = true
	touch_controls = DisplayServer.is_touchscreen_available()
	var config = ConfigFile.new()
	if config.load("user://preferences.cfg") == OK:
		preferred_3d = bool(config.get_value("presentation", "view3d", false))
		animations = bool(config.get_value("presentation", "animations", true))
		var saved_quality = str(config.get_value("presentation", "quality", "balanced"))
		quality = saved_quality if saved_quality in ["low", "balanced", "high"] else "balanced"
		volume = clampf(float(config.get_value("presentation", "volume", 0.8)), 0.0, 1.0)
		touch_controls = bool(config.get_value("presentation", "touch", touch_controls))
		display_mode = ScreenMode.normalise(config.get_value("presentation", "display", ScreenMode.WINDOWED))
		api_url = str(config.get_value("network", "apiUrl", api_url))
		BoardTheme.load_from(config)  # board theme, highlights, piece set (boards/board_theme.gd)
	apply()
	# Full screen is applied once, here (before the opening screen). It is deliberately not part of apply(), which runs on every
	# preference change: re-applying it there would pull the window back to full screen after the OS or the player left it.
	if display_mode == ScreenMode.FULLSCREEN:
		ScreenMode.apply(display_mode)

static func save_preferences() -> Error:
	var config = ConfigFile.new()
	config.set_value("presentation", "view3d", preferred_3d)
	config.set_value("presentation", "animations", animations)
	config.set_value("presentation", "quality", quality)
	config.set_value("presentation", "volume", volume)
	config.set_value("presentation", "touch", touch_controls)
	config.set_value("presentation", "display", display_mode)
	config.set_value("network", "apiUrl", api_url)
	BoardTheme.save_to(config)  # board theme, highlights, piece set (boards/board_theme.gd)
	apply()
	return config.save("user://preferences.cfg")

static func apply() -> void:
	if AudioServer.get_bus_count() > 0:
		AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
	Platform.set_quality(quality)

## The player's display choice (Settings page, F11, Alt+Enter): applies it and, unless `persist` is false, saves it. Where the window
## cannot change mode (headless, mobile, web) nothing happens and the stored value is left alone.
static func set_display_mode(value: String, persist: bool = true) -> void:
	if not ScreenMode.available():
		return
	display_mode = ScreenMode.normalise(value)
	ScreenMode.apply(display_mode)
	if persist:
		save_preferences()

static func ensure_platform(tree: SceneTree) -> void:
	ScreenMode.toggle_handler = func(target: String): set_display_mode(target)
	if not is_instance_valid(_platform):
		_platform = tree.root.get_node_or_null("PlatformInput")
		if _platform == null:
			_platform = Platform.new()
			_platform.name = "PlatformInput"
			tree.root.call_deferred("add_child", _platform)
	Platform.ensure_actions()
	Platform.set_quality(quality)
	set_combat_input(false)

static func set_combat_input(active: bool) -> void:
	if is_instance_valid(_platform):
		if _platform.is_node_ready():
			_platform.set_cursor_enabled(not active)
		else:
			_platform.call_deferred("set_cursor_enabled", not active)

static func reset_intro() -> void:
	intro_seen = false

## True while the opening screen is still due: the first time the home page is shown in this run.
static func wants_intro() -> bool:
	if intro_seen:
		return false
	return not ("--no-intro" in OS.get_cmdline_args() or "--no-intro" in OS.get_cmdline_user_args())

static func take_launch() -> Dictionary:
	var pending = launch.duplicate(true)
	launch.clear()
	return pending

static func sign_out() -> void:
	token = ""
	account.clear()
	launch.clear()
