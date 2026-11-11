extends RefCounted
## Accessibility and presentation preferences owned by the UI layer (kept in their own file so they never collide
## with res://ui/application_settings.gd): UI scale, reduce motion, colour-blind-safe highlights, and the extra
## audio mix levels. Persisted to user://ui_preferences.cfg and applied immediately.
const MIN_SCALE := 0.8
const MAX_SCALE := 1.5
static var path := "user://ui_preferences.cfg"
static var loaded := false
static var ui_scale := 1.0
## When true on a touch device the scale follows recommended_scale() (readable text and >= 44 dp targets).
static var scale_auto := true
static var reduce_motion := false
static var colorblind := false
static var ui_sounds := true
static var sfx_volume := 1.0
static var ui_volume := 1.0
static var music_volume := 1.0
## Emitted-by-poll style hook: pages register a callable that is invoked when scale/motion/colour-blind change.
static var _listeners: Array[Callable] = []

static func reset_defaults() -> void:
	ui_scale = 1.0
	scale_auto = true
	reduce_motion = false
	colorblind = false
	ui_sounds = true
	sfx_volume = 1.0
	ui_volume = 1.0
	music_volume = 1.0

static func load_preferences(force: bool = false) -> void:
	if loaded and not force:
		return
	loaded = true
	reset_defaults()
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return
	ui_scale = clampf(float(config.get_value("ui", "scale", 1.0)), MIN_SCALE, MAX_SCALE)
	scale_auto = bool(config.get_value("ui", "scale_auto", true))
	reduce_motion = bool(config.get_value("ui", "reduce_motion", false))
	colorblind = bool(config.get_value("ui", "colorblind", false))
	ui_sounds = bool(config.get_value("audio", "ui_sounds", true))
	sfx_volume = clampf(float(config.get_value("audio", "sfx", 1.0)), 0.0, 1.0)
	ui_volume = clampf(float(config.get_value("audio", "ui", 1.0)), 0.0, 1.0)
	music_volume = clampf(float(config.get_value("audio", "music", 1.0)), 0.0, 1.0)

static func save_preferences() -> Error:
	var config := ConfigFile.new()
	config.set_value("ui", "scale", ui_scale)
	config.set_value("ui", "scale_auto", scale_auto)
	config.set_value("ui", "reduce_motion", reduce_motion)
	config.set_value("ui", "colorblind", colorblind)
	config.set_value("audio", "ui_sounds", ui_sounds)
	config.set_value("audio", "sfx", sfx_volume)
	config.set_value("audio", "ui", ui_volume)
	config.set_value("audio", "music", music_volume)
	return config.save(path)

static func set_ui_scale(value: float) -> void:
	ui_scale = clampf(snappedf(value, 0.05), MIN_SCALE, MAX_SCALE)
	apply()

static func set_reduce_motion(value: bool) -> void:
	reduce_motion = value
	apply()

static func set_colorblind(value: bool) -> void:
	colorblind = value
	apply()

static func add_listener(callback: Callable) -> void:
	if not _listeners.has(callback):
		_listeners.append(callback)

static func remove_listener(callback: Callable) -> void:
	_listeners.erase(callback)

## Window stretch of the project's 1200 x 800 base (canvas_items / expand) for a window of `window_px`.
static func base_stretch(window_px: Vector2) -> float:
	return minf(window_px.x / 1200.0, window_px.y / 800.0)

## Scale that makes body text about 13 dp and keeps targets reachable on a phone of `dpi` showing `window_px`.
static func recommended_scale(dpi: float, window_px: Vector2) -> float:
	var stretch := base_stretch(window_px)
	if stretch <= 0.0 or dpi <= 0.0:
		return 1.0
	return clampf(snappedf(13.0 * dpi / 160.0 / (16.0 * stretch), 0.05), 1.0, MAX_SCALE)

## Minimum logical size of a touch target so it measures at least 44 dp at `effective_scale` (stretch * ui scale).
static func touch_target(dpi: float, effective_scale: float) -> int:
	if dpi <= 0.0 or effective_scale <= 0.0:
		return 48
	return clampi(ceili(44.0 * dpi / 160.0 / effective_scale), 48, 96)

static func effective_scale_factor() -> float:
	var touch := DisplayServer.is_touchscreen_available()
	if scale_auto and touch and DisplayServer.get_name() != "headless":
		return recommended_scale(DisplayServer.screen_get_dpi(), Vector2(DisplayServer.window_get_size()))
	return ui_scale

static func apply() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		tree.root.content_scale_factor = effective_scale_factor()
	_apply_buses()
	for callback in _listeners.duplicate():
		if callback.is_valid():
			callback.call()
		else:
			_listeners.erase(callback)

## Extra mix levels go to the buses the combat audio layer creates (SFX, UI) and to Music if a bus of that name exists.
static func _apply_buses() -> void:
	Engine.set_meta("ui_mix", {"sfx": sfx_volume, "ui": ui_volume})   # read by CombatAudio when it (re)applies its levels
	for pair in [["SFX", sfx_volume], ["UI", ui_volume], ["Music", music_volume]]:
		var index := AudioServer.get_bus_index(pair[0])
		if index != -1:
			AudioServer.set_bus_volume_db(index, linear_to_db(maxf(float(pair[1]), 0.0001)))

## Highlight colours used by boards that opt in. Cheap to call.
static func move_highlight(default_color: Color) -> Color:
	return preload("res://ui/theme/ui_tokens.gd").CB_MOVE if colorblind else default_color

static func capture_highlight(default_color: Color) -> Color:
	return preload("res://ui/theme/ui_tokens.gd").CB_CAPTURE if colorblind else default_color
