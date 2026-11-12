extends MarginContainer
## A MarginContainer that keeps its content inside the display safe area (notches, punch-holes, rounded corners,
## gesture bars) plus a base margin. Re-evaluates on resize and when the window changes. Headless / desktop windows
## that are not full-screen get no extra inset.
const BASE_DEFAULT := 24
var base_margin := BASE_DEFAULT:
	set(value):
		base_margin = value
		apply_margins()
## Tests inject {left, top, right, bottom} in logical px instead of asking the display server.
var inset_override: Variant = null
var compact_base := 12

## Pure helper: safe rect (physical px, screen space) + screen size + window size (physical px) + logical size
## -> insets in logical px. Covered by tests with simulated notches.
static func insets_from(safe: Rect2i, screen: Vector2i, window_px: Vector2i, logical: Vector2) -> Dictionary:
	var result := {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
	if screen.x <= 0 or screen.y <= 0 or window_px.x <= 0 or window_px.y <= 0 or safe.size.x <= 0 or safe.size.y <= 0:
		return result
	var to_logical := Vector2(logical.x / window_px.x, logical.y / window_px.y)
	result.left = maxf(0.0, safe.position.x) * to_logical.x
	result.top = maxf(0.0, safe.position.y) * to_logical.y
	result.right = maxf(0.0, screen.x - safe.end.x) * to_logical.x
	result.bottom = maxf(0.0, screen.y - safe.end.y) * to_logical.y
	return result

func current_insets() -> Dictionary:
	if inset_override is Dictionary:
		return inset_override
	if DisplayServer.get_name() == "headless" or not is_inside_tree():
		return {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
	var window := get_window()
	var screen := DisplayServer.window_get_current_screen(window.get_window_id())
	var screen_size := DisplayServer.screen_get_size(screen)
	var window_px := window.size
	# only trust the safe area when the window covers the screen (phones / full-screen)
	if absi(window_px.x - screen_size.x) > 4 or absi(window_px.y - screen_size.y) > 4:
		return {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
	return insets_from(DisplayServer.get_display_safe_area(), screen_size, window_px, get_viewport_rect().size)

func _ready() -> void:
	resized.connect(apply_margins)
	apply_margins()

func apply_margins() -> void:
	var inset := current_insets()
	var base := compact_base if size.x < 700.0 else base_margin
	add_theme_constant_override("margin_left", base + roundi(inset.left))
	add_theme_constant_override("margin_right", base + roundi(inset.right))
	add_theme_constant_override("margin_top", base + roundi(inset.top))
	add_theme_constant_override("margin_bottom", base + roundi(inset.bottom))
