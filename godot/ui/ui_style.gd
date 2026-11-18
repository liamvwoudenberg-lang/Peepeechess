class_name UiStyle
extends RefCounted
## "UI style" setting: Minimal (default: the 3D scene fills the screen, small translucent plates, one overlay menu) or Full (the
## classic toolbar + side panel). Own file (user://ui_style.cfg); read when a game screen is built. Presentation only.
const PATH := "user://ui_style.cfg"
const OPTIONS := [["minimal", "Minimal"], ["full", "Full"]]
static var style := "minimal"
static var loaded := false

static func load_preferences() -> void:
	if loaded:
		return
	loaded = true
	var config := ConfigFile.new()
	if config.load(PATH) == OK:
		var value := str(config.get_value("ui", "style", "minimal"))
		style = value if value in ["minimal", "full"] else "minimal"

static func is_minimal() -> bool:
	load_preferences()
	return style == "minimal"

static func set_style(value: String) -> void:
	load_preferences()
	style = value if value in ["minimal", "full"] else "minimal"
	var config := ConfigFile.new()
	config.set_value("ui", "style", style)
	config.save(PATH)
