class_name BoardTheme
extends RefCounted
const UiPrefs = preload("res://ui/theme/ui_prefs.gd")  # colour-blind-safe highlight option
## Board presentation settings (device-local, never part of match state): colour theme, move-highlight
## style, coordinates, piece set, animation speed and piece shadow quality. Persisted in the same
## `user://preferences.cfg` as the other presentation settings through `save_to` / `load_from`, which
## ApplicationSettings calls. Views read these statics and listen to `events().changed`.
class Events:
	extends RefCounted
	signal changed
const THEMES = {
	"slate": {"name": "Slate (default)", "light": "d3d5bf", "dark": "648788", "light_3d": "b7b9a5", "dark_3d": "496e70", "frame": "233a40", "frame_border": "476166", "label": "a9bfc0", "label_3d": "f1d69e", "plinth": "263b42", "trim": "c39c5d", "backdrop": "14272e"},
	"classic_wood": {"name": "Classic wood", "light": "ecd2a1", "dark": "ae7b4d", "light_3d": "e0c595", "dark_3d": "9b6a40", "frame": "4a2f1c", "frame_border": "7a5232", "label": "e6cfa4", "label_3d": "f1d69e", "plinth": "4a2f1c", "trim": "b98d45", "backdrop": "1c1410"},
	"marble": {"name": "Marble", "light": "ece9e2", "dark": "8c97a1", "light_3d": "e4e1d9", "dark_3d": "7d8993", "frame": "b5ad9c", "frame_border": "d9d1c0", "label": "5d5a52", "label_3d": "f4efe2", "plinth": "9b9486", "trim": "d4b66a", "backdrop": "1b2024"},
	"tournament_green": {"name": "Tournament green", "light": "eeeed2", "dark": "769656", "light_3d": "e6e6c8", "dark_3d": "6a8a4c", "frame": "2c3d22", "frame_border": "4f6b3a", "label": "c9d6b0", "label_3d": "e8f0cf", "plinth": "2c3d22", "trim": "b79c58", "backdrop": "141c11"},
	"midnight": {"name": "Midnight", "light": "8f9cc7", "dark": "33406b", "light_3d": "7f8cb8", "dark_3d": "2a3560", "frame": "161c36", "frame_border": "3a4677", "label": "a7b3dd", "label_3d": "c2cdf2", "plinth": "161c36", "trim": "8c97d1", "backdrop": "0a0d1c"},
}
const THEME_ORDER = ["slate", "classic_wood", "marble", "tournament_green", "midnight"]
const HIGHLIGHTS = {"dots": "Dots", "rings": "Rings", "tint": "Tile tint"}
const HIGHLIGHT_ORDER = ["dots", "rings", "tint"]
const PIECE_SETS = {"paladin": "Paladins (animated characters)", "procedural": "Procedural (built-in)", "carved": "Carved marble & basalt (GLB)"}
const PIECE_SET_ORDER = ["paladin", "procedural", "carved"]
const SPEEDS = {"off": 0.0, "normal": 1.0, "fast": 0.5}
const SPEED_ORDER = ["off", "normal", "fast"]
const SHADOW_ORDER = ["low", "high"]
static var theme_id = "slate"
static var highlight = "dots"
static var coordinates = true
static var piece_set = "paladin"
static var animation_speed = "normal"
static var shadows = "high"
static var _events: Events

static func events() -> Events:
	if _events == null:
		_events = Events.new()
	return _events

static func notify() -> void:
	events().changed.emit()

static func defaults() -> Dictionary:
	return {"theme": "slate", "highlight": "dots", "coordinates": true, "pieces": "paladin", "animation": "normal", "shadows": "high"}

static func current() -> Dictionary:
	return {"theme": theme_id, "highlight": highlight, "coordinates": coordinates, "pieces": piece_set, "animation": animation_speed, "shadows": shadows}

static func reset() -> void:
	apply(defaults())

## Set any subset of {theme, highlight, coordinates, pieces, animation, shadows}; invalid values are ignored.
static func apply(values: Dictionary) -> void:
	if values.get("theme", theme_id) in THEMES:
		theme_id = values.get("theme", theme_id)
	if values.get("highlight", highlight) in HIGHLIGHTS:
		highlight = values.get("highlight", highlight)
	if values.has("coordinates"):
		coordinates = bool(values.coordinates)
	if values.get("pieces", piece_set) in PIECE_SETS:
		piece_set = values.get("pieces", piece_set)
	if values.get("animation", animation_speed) in SPEEDS:
		animation_speed = values.get("animation", animation_speed)
	if values.get("shadows", shadows) in SHADOW_ORDER:
		shadows = values.get("shadows", shadows)
	notify()

static func save_to(config: ConfigFile) -> void:
	for key in current():
		config.set_value("board", key, current()[key])

static func load_from(config: ConfigFile) -> void:
	var values: Dictionary = {}
	for key in current():
		if config.has_section_key("board", key):
			values[key] = config.get_value("board", key)
	apply(values)

# ---- derived values --------------------------------------------------------------------------

static func palette() -> Dictionary:
	return THEMES[theme_id]

static func color(key: String) -> Color:
	return Color(THEMES[theme_id][key])

## The shipped look. Views leave their own materials untouched when this is active (keeps new board art intact).
static func is_default_look() -> bool:
	return theme_id == "slate"

static func tile_color(light: bool) -> Color:
	return color("light" if light else "dark")

## 0 = animations off, 1 = normal, 0.5 = fast (durations are multiplied by this).
static func anim_scale() -> float:
	return SPEEDS[animation_speed]

static func anim_seconds(base: float) -> float:
	return maxf(0.001, base * anim_scale())

## Where a legal destination mark goes: draws on a 2D canvas for the chosen highlight style.
static func draw_destination_2d(canvas: CanvasItem, tile: Rect2, capture: bool) -> void:
	var pitch = tile.size.x
	var center = tile.get_center()
	# Colours go through the UI colour-blind option (UiPrefs) so themed highlights stay readable for everyone.
	var move_c: Color = UiPrefs.move_highlight(Color(0.07, 0.24, 0.24))
	var cap_c: Color = UiPrefs.capture_highlight(Color("f4d78e"))
	match highlight:
		"rings":
			canvas.draw_arc(center, pitch * (0.43 if capture else 0.2), 0, TAU, 48, cap_c if capture else Color(move_c, 0.75), 3 if capture else 2.5, true)
		"tint":
			canvas.draw_rect(tile, Color(UiPrefs.capture_highlight(Color(0.95, 0.35, 0.3)), 0.38) if capture else Color(UiPrefs.move_highlight(Color(0.25, 0.85, 0.65)), 0.34))
		_:
			if capture:
				canvas.draw_arc(center, pitch * 0.43, 0, TAU, 48, cap_c, 3, true)
			else:
				canvas.draw_circle(center, pitch * 0.13, Color(move_c, 0.7 if UiPrefs.colorblind else 0.5))