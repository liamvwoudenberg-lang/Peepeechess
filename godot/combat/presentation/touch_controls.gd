extends Control
## Landscape touch interface for combat (Android / any touchscreen). PRELOAD-ONLY (no class_name).
##
## Pure input device: it owns no gameplay. It turns raw multi-touch into intent that LocalInputSource (scheme
## "touch") or any other host forwards exactly like keyboard/pad input:
##   move_vector   (x = right, y = forward, length <= 1, camera/screen relative; the host converts to world space)
##   sprint        (stick pushed to the rim, with hysteresis)
##   block_held    (BLOCK button finger down)
## and one-shot signals: action_pressed(action) for light/heavy/dodge/parry/ability (exactly one per tap),
## lock_pressed, pause_pressed, look_delta(pixels) for the camera.
##
## FINGER RULES (every finger is tracked independently by its touch index):
##   * A touch that lands on a button (hit slop 12%, nearest centre wins) is BOUND to that button until it lifts.
##     Sliding off does not release it, so a held BLOCK stays up while the thumb slides.
##   * Action buttons fire once on press. BLOCK is held while its finger is down. LOCK toggles on press.
##   * A touch in the left stick zone (and not on a button) becomes the FLOATING JOYSTICK; its origin is where the
##     finger landed. Only one stick finger; a second finger in the stick zone is ignored.
##   * Any other touch becomes the CAMERA finger (drag = orbit). Only one camera finger.
##   * Lifting one finger never affects another. Cancelled touches and loss of window focus release everything.
## The emulated mouse events Godot synthesises from touch are NOT used here (only InputEventScreenTouch/Drag).
## Layout is a pure function (compute_layout) so it can be tested for overlap at any resolution.

signal action_pressed(action: String)
signal lock_pressed
signal pause_pressed
signal look_delta(delta: Vector2)

const ACTIONS: Array[String] = ["light", "heavy", "dodge", "parry", "ability"]
const LABELS := {"light": "LIGHT", "heavy": "HEAVY", "dodge": "DODGE", "parry": "PARRY", "ability": "SPECIAL",
		"block": "BLOCK", "lock": "LOCK", "pause": "II"}

const DEADZONE := 0.14
const RESPONSE_EXPONENT := 1.35
const SPRINT_ENTER := 0.92
const SPRINT_EXIT := 0.80
## Button unit d = BUTTON_FRACTION * screen height (clamped to [MIN_FRACTION, MAX_FRACTION] of height).
const BUTTON_FRACTION := 0.115
const MIN_FRACTION := 0.09
const MAX_FRACTION := 0.16
const MARGIN_FRACTION := 0.035
const HIT_SLOP := 1.12
const STICK_ZONE_WIDTH := 0.40      # fraction of screen width (lower part of the left side)
const HUD_BOTTOM := 0.175          # fraction of the safe height reserved at the top for the HUD bars (PAUSE sits below it, top-left, away from the combat thumb)
const STICK_ZONE_TOP := 0.34        # fraction of screen height where the stick zone begins

## Cluster layout in units of d, relative to the LIGHT button centre: [offset x, offset y, radius].
const CLUSTER := {
	"light": [0.0, 0.0, 0.65], "heavy": [0.0, -1.5, 0.58], "dodge": [-1.45, 0.1, 0.55], "parry": [-1.45, -1.35, 0.55],
	"ability": [-1.2, -3.0, 0.60], "block": [-2.7, -0.75, 0.62], "lock": [0.0, -3.0, 0.50],
}

## User-adjustable.
var ui_scale: float = 1.0
var opacity: float = 0.85
var haptics_enabled: bool = true
## Test hook: when non-empty it replaces the platform safe area (viewport coordinates).
var safe_area_override: Rect2 = Rect2()
## Optional read-only callback returning {"cooldown": int ticks, "total": int ticks, "active": bool}; cosmetic only.
var ability_state: Callable = Callable()
var lock_active: bool = false
var enabled: bool = true:
	set(value):
		enabled = value
		if not value:
			release_all()
		visible = value

var move_vector: Vector2 = Vector2.ZERO
var sprint: bool = false
var block_held: bool = false

var _fingers: Dictionary = {}      # touch index -> {"kind": "button"|"stick"|"look", "id": String, "origin": Vector2, "pos": Vector2}
var _layout: Dictionary = {}
var _layout_key: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_input(true)


# ---- layout (pure) --------------------------------------------------------------------------------------
## Returns {"d", "buttons": {id: {"center": Vector2, "radius": float}}, "stick": {"center", "radius", "zone": Rect2},
## "safe": Rect2}. All coordinates are viewport pixels. Visible controls stay inside `safe` minus a margin.
static func compute_layout(view: Vector2, safe: Rect2, scale: float = 1.0) -> Dictionary:
	var h := view.y
	var d := clampf(h * BUTTON_FRACTION * scale, h * MIN_FRACTION, h * MAX_FRACTION)
	var margin := h * MARGIN_FRACTION
	var s := safe if safe.size.x > 0.0 else Rect2(Vector2.ZERO, view)
	var left := s.position.x + margin
	var right := s.end.x - margin
	var bottom := s.end.y - margin
	var anchor := Vector2(right - 0.65 * d, bottom - 0.65 * d)
	var buttons := {}
	for id in CLUSTER:
		var c: Array = CLUSTER[id]
		buttons[id] = {"center": anchor + Vector2(float(c[0]), float(c[1])) * d, "radius": float(c[2]) * d}
	buttons["pause"] = {"center": Vector2(left + 0.5 * d, s.position.y + s.size.y * HUD_BOTTOM + 0.5 * d), "radius": 0.5 * d}
	var zone_left := s.position.x
	var zone_top := s.position.y + (s.size.y * STICK_ZONE_TOP)
	var zone := Rect2(Vector2(zone_left, zone_top), Vector2(s.size.x * STICK_ZONE_WIDTH, s.end.y - zone_top))
	var stick := {"center": Vector2(left + 1.5 * d, bottom - 1.5 * d), "radius": 1.1 * d, "zone": zone}
	return {"d": d, "buttons": buttons, "stick": stick, "safe": s}


func _safe_rect() -> Rect2:
	if safe_area_override.size.x > 0.0:
		return safe_area_override
	if OS.has_feature("mobile"):
		var raw := Rect2(DisplayServer.get_display_safe_area())
		var win := Vector2(DisplayServer.window_get_size())
		if raw.size.x > 0.0 and win.x > 0.0 and win.y > 0.0:
			var k := size / win
			return Rect2(raw.position * k, raw.size * k).intersection(Rect2(Vector2.ZERO, size))
	return Rect2(Vector2.ZERO, size)


func layout() -> Dictionary:
	var safe := _safe_rect()
	var key := "%s|%s|%s" % [str(size), str(safe), str(ui_scale)]
	if key != _layout_key:
		_layout_key = key
		_layout = compute_layout(size, safe, ui_scale)
	return _layout


## Button id under `pos`, or "". Overlapping hit areas resolve to the nearest centre (relative to its radius).
func button_at(pos: Vector2) -> String:
	var best := ""
	var best_score := INF
	var buttons: Dictionary = layout()["buttons"]
	for id in buttons:
		var b: Dictionary = buttons[id]
		var dist: float = pos.distance_to(b["center"])
		var radius: float = b["radius"]
		if dist <= radius * HIT_SLOP and dist / radius < best_score:
			best = id
			best_score = dist / radius
	return best


# ---- touch handling -------------------------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if not enabled or not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag:
		_on_drag(event)


func _local(position: Vector2) -> Vector2:
	return position - global_position


func _on_touch(event: InputEventScreenTouch) -> void:
	var cancelled: bool = bool(event.get("canceled"))
	if cancelled or not event.pressed:
		if _fingers.has(event.index):
			_end(event.index)
			_consume()
		return
	if _fingers.has(event.index):
		_end(event.index)  # a repeated press for a known index: treat as a fresh touch
	_begin(event.index, _local(event.position))


func _begin(index: int, pos: Vector2) -> void:
	var id := button_at(pos)
	if id != "":
		_fingers[index] = {"kind": "button", "id": id, "origin": pos, "pos": pos}
		match id:
			"block":
				block_held = true
			"lock":
				lock_pressed.emit()
			"pause":
				pause_pressed.emit()
			_:
				action_pressed.emit(id)
				_haptic(12)
		_consume()
		return
	var stick: Dictionary = layout()["stick"]
	if (stick["zone"] as Rect2).has_point(pos):
		if not _has_kind("stick"):
			_fingers[index] = {"kind": "stick", "id": "", "origin": pos, "pos": pos}
			_update_stick(_fingers[index])
		_consume()  # a second finger in the stick zone is ignored, never turned into a camera drag
		return
	if not _has_kind("look"):
		_fingers[index] = {"kind": "look", "id": "", "origin": pos, "pos": pos}
	_consume()


func _on_drag(event: InputEventScreenDrag) -> void:
	var f = _fingers.get(event.index, null)
	if f == null:
		return
	f["pos"] = _local(event.position)
	match String(f["kind"]):
		"stick":
			_update_stick(f)
		"look":
			look_delta.emit(event.relative)
	_consume()


func _end(index: int) -> void:
	var f = _fingers.get(index, null)
	if f == null:
		return
	_fingers.erase(index)
	match String(f["kind"]):
		"stick":
			move_vector = Vector2.ZERO
			sprint = false
		"button":
			if f["id"] == "block":
				block_held = _any_button("block")


func _has_kind(kind: String) -> bool:
	for f in _fingers.values():
		if f["kind"] == kind:
			return true
	return false


func _any_button(id: String) -> bool:
	for f in _fingers.values():
		if f["kind"] == "button" and f["id"] == id:
			return true
	return false


## Joystick: dead zone, smooth response curve, sprint at the rim with hysteresis.
func _update_stick(f: Dictionary) -> void:
	var radius: float = layout()["stick"]["radius"]
	var v: Vector2 = (f["pos"] - f["origin"]) / radius
	var length := minf(v.length(), 1.0)
	if length < DEADZONE:
		move_vector = Vector2.ZERO
		sprint = false
		return
	var magnitude := pow((length - DEADZONE) / (1.0 - DEADZONE), RESPONSE_EXPONENT)
	move_vector = Vector2(v.x, -v.y).normalized() * magnitude  # screen y points down; forward is up
	if sprint:
		sprint = length >= SPRINT_EXIT
	else:
		sprint = length >= SPRINT_ENTER


func release_all() -> void:
	_fingers.clear()
	move_vector = Vector2.ZERO
	sprint = false
	block_held = false


func finger_count() -> int:
	return _fingers.size()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT \
			or what == NOTIFICATION_APPLICATION_PAUSED:
		release_all()


func _consume() -> void:
	if is_inside_tree():
		get_viewport().set_input_as_handled()


func _haptic(ms: int) -> void:
	if haptics_enabled and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)


func haptic(ms: int) -> void:
	_haptic(ms)


# ---- state for display --------------------------------------------------------------------------------
## 0 = ready, 1 = just used. Purely cosmetic (the server decides whether an ability fires).
func ability_cooldown_fraction() -> float:
	if not ability_state.is_valid():
		return 0.0
	var s: Dictionary = ability_state.call()
	var total := float(s.get("total", 0))
	if total <= 0.0:
		return 0.0
	return clampf(float(s.get("cooldown", 0)) / total, 0.0, 1.0)


func pressed_ids() -> Array:
	var ids: Array = []
	for f in _fingers.values():
		if f["kind"] == "button":
			ids.append(f["id"])
	return ids


# ---- drawing ------------------------------------------------------------------------------------------
func _process(_delta: float) -> void:
	if enabled and is_visible_in_tree():
		queue_redraw()


func _draw() -> void:
	if not enabled:
		return
	var lay := layout()
	var d: float = lay["d"]
	var font := ThemeDB.fallback_font
	var pressed := pressed_ids()
	var line := maxf(2.0, d * 0.03)

	# Joystick: faint base where it will appear, live knob while a finger is on it.
	var stick: Dictionary = lay["stick"]
	var base_center: Vector2 = stick["center"]
	var knob := base_center
	var active := false
	for f in _fingers.values():
		if f["kind"] == "stick":
			active = true
			base_center = f["origin"]
			var offset: Vector2 = f["pos"] - f["origin"]
			knob = base_center + offset.limit_length(stick["radius"])
	var stick_alpha := (0.55 if active else 0.28) * opacity
	draw_circle(base_center, stick["radius"], Color(0.05, 0.08, 0.12, stick_alpha * 0.6))
	draw_arc(base_center, stick["radius"], 0.0, TAU, 48, Color(1, 1, 1, stick_alpha + 0.15), line)
	draw_circle(knob, d * 0.42, Color(0.95, 0.85, 0.5, (0.7 if active else 0.35) * opacity))
	if sprint:
		draw_arc(base_center, stick["radius"] + line * 2.0, 0.0, TAU, 48, Color(1.0, 0.6, 0.2, 0.9 * opacity), line * 1.5)

	var buttons: Dictionary = lay["buttons"]
	for id in buttons:
		var b: Dictionary = buttons[id]
		var center: Vector2 = b["center"]
		var radius: float = b["radius"]
		var down: bool = id in pressed
		var fill := Color(0.05, 0.08, 0.12, 0.42 * opacity)
		var ring := Color(1, 1, 1, 0.75 * opacity)
		if down:
			fill = Color(0.95, 0.78, 0.3, 0.6 * opacity)
			ring = Color(1, 1, 1, 0.95)
		elif id == "lock" and lock_active:
			fill = Color(0.3, 0.7, 1.0, 0.5 * opacity)
		if id == "ability":
			var cd := ability_cooldown_fraction()
			if cd > 0.0:
				fill = Color(0.12, 0.12, 0.14, 0.55 * opacity)
				ring = Color(0.6, 0.6, 0.65, 0.6 * opacity)
			else:
				ring = Color(0.45, 1.0, 0.55, 0.95 * opacity)
		draw_circle(center, radius, fill)
		if id == "ability":
			var cd2 := ability_cooldown_fraction()
			if cd2 > 0.0:
				draw_arc(center, radius * 0.82, -PI * 0.5, -PI * 0.5 + TAU * cd2, 40, Color(0.7, 0.5, 1.0, 0.85 * opacity), line * 2.5)
		draw_arc(center, radius, 0.0, TAU, 40, ring, line * (1.6 if down else 1.0))
		var text: String = LABELS[id]
		var font_size := int(maxf(11.0, radius * (0.36 if text.length() > 4 else 0.52)))
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		draw_string(font, center + Vector2(-text_size.x * 0.5, font_size * 0.34), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
				Color(1, 1, 1, 0.95 * opacity))
