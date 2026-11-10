extends RefCounted
## Presentation and launch data only. Competitive state never lives here.
static var preferred_3d = false
static var animations = true
static var quality = "balanced"
static var volume = 0.8
static var touch_controls = false
static var api_url = "http://127.0.0.1:3100"
static var token = ""
static var account: Dictionary = {}
static var launch: Dictionary = {}
static var result: Dictionary = {}
static var loaded = false

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
		api_url = str(config.get_value("network", "apiUrl", api_url))
	apply()

static func save_preferences() -> Error:
	var config = ConfigFile.new()
	config.set_value("presentation", "view3d", preferred_3d)
	config.set_value("presentation", "animations", animations)
	config.set_value("presentation", "quality", quality)
	config.set_value("presentation", "volume", volume)
	config.set_value("presentation", "touch", touch_controls)
	config.set_value("network", "apiUrl", api_url)
	apply()
	return config.save("user://preferences.cfg")

static func apply() -> void:
	if AudioServer.get_bus_count() > 0:
		AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
	Engine.max_fps = 30 if quality == "low" else 60

static func take_launch() -> Dictionary:
	var pending = launch.duplicate(true)
	launch.clear()
	return pending

static func sign_out() -> void:
	token = ""
	account.clear()
	launch.clear()
