class_name ControlOverlay
extends CanvasLayer
## In-battle controls cheat sheet (presentation only: it reads bindings and never changes combat).
##
## One panel per LOCAL HUMAN seat, generated from the live bindings (ControlBindings) and the connected controller's
## own button names (ControllerGlyphs): Move, Light, Heavy, Block, Parry, Dodge, Ability (with the fighter's ability
## name), Sprint, Lock-on, Camera, Pause. White (P1) is on the left edge, Black (P2) on the right edge, so in
## split-screen each panel sits inside its player's half. AI seats get nothing; an online (PRESENTATION) arena passes only
## the local seat. Touch seats get a compact legend of the on-screen button names, placed away from TouchControls.
##
## States (global for the battle): FULL (the sheet), MIN (a small "F1 Controls" chip) and OFF (nothing; on touch only a
## '?' button so the sheet can be brought back). A battle starts in the state ControlOverlayPrefs says; a FULL sheet that
## nobody touched folds into the chip after AUTO_MINIMISE_SECONDS. Toggle: F1 (every scheme), Share / Back on any pad,
## the '?' on touch, or a click on the chip. The choice is remembered (control_overlay_prefs.gd).
##
## It never takes gameplay input: every Control ignores the mouse except the small chip (and that one ignores it while
## the mouse is captured for mouse-look), and F1 / Share are reserved keys that no scheme binds. Fades take FADE_SECONDS
## (instant under reduce-motion). Nodes are built once; steady-state frames allocate nothing (text, fonts and layout are
## recomputed only when bindings / controllers / viewport size / mode change).

signal toggled(mode: int)

enum Mode { OFF, FULL, MIN }

const LAYER := 12  # above the HUD (10), below the touch controls (20) and menus (50)
const AUTO_MINIMISE_SECONDS := 8.0
const FADE_SECONDS := 0.15
const MAX_ROWS := 12
## The HUD bars own the top 120 px (fixed size); panels start below that (or at 19% of the height on tall views).
const TOP_BAND_PX := 132.0
const TouchControls := preload("res://combat/presentation/touch_controls.gd")

## Seats to show: [{"id": String, "color": "w"|"b", "role": String, "scheme": "kb1"|"kb2"|"padN"|"touch", "mouse": bool}].
var seats: Array = []
## Private instances for tests; null = the process-wide ones.
var prefs: ControlOverlayPrefs = null
var bindings: ControlBindings = null
## Test hook: replaces the platform safe area (viewport coordinates).
var safe_area_override: Rect2 = Rect2()
## Fades become instant (tests; reduce-motion forces it too).
var instant: bool = false
var mode: int = Mode.OFF
var battle_active: bool = false
var finished: bool = false

var _root: Control
var _panels: Array[SeatPanel] = []
var _alpha: float = 0.0
var _goal: float = 0.0
var _pending: int = -1
var _age: float = 0.0
var _user_toggled: bool = false
var _dirty: bool = true
var _last_view: Vector2 = Vector2.ZERO
var _last_event_id: int = 0
var _chip_filter: int = -1
var _bindings_hooked: ControlBindings = null


func _init() -> void:
	layer = LAYER
	name = "ControlOverlay"


func _ready() -> void:
	_ensure_built()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _enter_tree() -> void:
	if not Input.joy_connection_changed.is_connected(_on_joy_changed):
		Input.joy_connection_changed.connect(_on_joy_changed)


## The pooled nodes: one root and two seat panels, created once (begin() may run before the node is in the tree).
func _ensure_built() -> void:
	if _root != null:
		return
	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	add_child(_root)
	for side in 2:
		var panel := SeatPanel.new()
		panel.name = "Panel%d" % side
		panel.side = side
		panel.overlay = self
		panel.build()
		panel.visible = false
		_root.add_child(panel)
		_panels.append(panel)


func _exit_tree() -> void:
	_unhook()
	if Input.joy_connection_changed.is_connected(_on_joy_changed):
		Input.joy_connection_changed.disconnect(_on_joy_changed)


# ---- content (pure, static: tests call these directly) ----------------------------------------------------------
## [[label, value], ...] for one seat, from the live bindings. `scheme` is kb1 / kb2 / padN / touch, `mouse` says whether
## the P1 mouse (LMB / RMB / MMB, mouse-look) is live for this keyboard seat.
static func rows(b: ControlBindings, scheme: String, role: String, mouse: bool = false) -> Array:
	var ability := FighterRoster.ability_name(role)
	if scheme == "touch":
		var t: Dictionary = TouchControls.LABELS
		return [["Move", "Left stick"], ["Sprint", "Push to the rim"], ["Attack", "%s / %s" % [t["light"], t["heavy"]]],
			["Defend", "%s (hold) / %s / %s" % [t["block"], t["parry"], t["dodge"]]], ["Ability", "%s (%s)" % [t["ability"], ability]],
			["Lock-on", t["lock"]], ["Camera", "Drag"], ["Pause", t["pause"]]]
	if scheme in ControlBindings.SCHEMES:
		return _keyboard_rows(b, scheme, ability, mouse)
	var device := int(scheme.substr(3)) if scheme.begins_with("pad") and scheme.substr(3).is_valid_int() else -1
	var family: int = ControllerGlyphs.family_of_device(device) if device >= 0 else ControllerGlyphs.Family.XBOX
	var lbl := func(a: String) -> String: return ControllerGlyphs.input_label(b.pad_input(a), family)
	var heavy: String = lbl.call("heavy")
	if not b.pad_input("heavy2").is_empty():
		heavy += " / " + String(lbl.call("heavy2"))
	return [["Move", "Left stick"], ["Light", lbl.call("light")], ["Heavy", heavy], ["Block", "%s (hold)" % lbl.call("block")],
		["Parry", lbl.call("parry")], ["Dodge", lbl.call("dodge")], ["Ability", "%s (%s)" % [lbl.call("ability"), ability]],
		["Sprint", "%s (hold)" % lbl.call("sprint")], ["Lock-on", lbl.call("lock")], ["Camera", "Right stick"],
		["Pause", ControllerGlyphs.button_label(JOY_BUTTON_START, family)]]


static func _keyboard_rows(b: ControlBindings, scheme: String, ability: String, mouse: bool) -> Array:
	var k: Dictionary = b.keys_for(scheme)
	var n := func(a: String) -> String: return ControlBindings.key_name(int(k.get(a, KEY_NONE)))
	var move := ""
	if k.get("up") == KEY_UP and k.get("down") == KEY_DOWN and k.get("left") == KEY_LEFT and k.get("right") == KEY_RIGHT:
		move = "Arrow keys"
	else:
		move = "%s %s %s %s" % [n.call("up"), n.call("left"), n.call("down"), n.call("right")]
	var light: String = ("LMB / " if mouse else "") + n.call("light")
	var heavy: String = ("RMB / " if mouse else "") + n.call("heavy")
	var lock: String = n.call("lock") + (" / MMB" if mouse else "")
	var cam: String = ("Mouse / " if mouse else "") + "%s %s" % [n.call("orbit_l"), n.call("orbit_r")]
	return [["Move", move], ["Light", light], ["Heavy", heavy], ["Block", "%s (hold)" % n.call("block")], ["Parry", n.call("parry")],
		["Dodge", n.call("dodge")], ["Ability", "%s (%s)" % [n.call("ability"), ability]], ["Sprint", "%s (hold)" % n.call("sprint")],
		["Lock-on", lock], ["Camera", cam], ["Pause", "Esc"]]


## "P1 White · Keyboard + mouse" / "P2 Black · PlayStation pad" / "P1 White · Touch".
static func title_for(seat: Dictionary) -> String:
	var who := "P1 White" if String(seat.get("color", "w")) == "w" else "P2 Black"
	var scheme := String(seat.get("scheme", "kb1"))
	var device := ""
	match scheme:
		"kb1":
			device = "Keyboard + mouse" if bool(seat.get("mouse", false)) else "Keyboard 1"
		"kb2":
			device = "Keyboard 2"
		"touch":
			device = "Touch"
		_:
			var id := int(scheme.substr(3)) if scheme.begins_with("pad") and scheme.substr(3).is_valid_int() else -1
			device = "%s pad" % ControllerGlyphs.family_name(ControllerGlyphs.family_of_device(id)) if id >= 0 else "Gamepad"
	return "%s · %s" % [who, device]


## Name of the toggle as the seat's device calls it: "F1", "F1 / Share", "F1 / View", "?" (touch).
static func toggle_key_text(scheme: String) -> String:
	if scheme == "touch":
		return "?"
	if scheme.begins_with("pad") and scheme.substr(3).is_valid_int():
		return "F1 / %s" % ControllerGlyphs.button_label(JOY_BUTTON_BACK, ControllerGlyphs.family_of_device(int(scheme.substr(3))))
	return "F1"


# ---- battle lifecycle -----------------------------------------------------------------------------------------------
## Starts a battle's overlay for `p_seats` (local human seats only). Counts the battle for the first-battles default.
func begin(p_seats: Array, count_battle: bool = true) -> void:
	_ensure_built()
	end()
	seats = p_seats.duplicate(true)
	finished = false
	_user_toggled = false
	_age = 0.0
	if seats.is_empty():
		battle_active = false
		_set_mode_now(Mode.OFF)
		_alpha = 0.0
		_goal = 0.0
		_sync_root()
		return
	battle_active = true
	var p := _prefs()
	var start: int = p.begin_battle() if count_battle else p.start_mode()
	_hook()
	_assign_panels()
	refresh()
	_set_mode_now(Mode.FULL if start == ControlOverlayPrefs.Start.FULL else (Mode.MIN if start == ControlOverlayPrefs.Start.MINIMISED else Mode.OFF))
	_alpha = _goal if _is_instant() else 0.0
	_sync_root()


## The battle is over (or torn down): nothing is shown and the toggles stop working until the next begin().
func end() -> void:
	battle_active = false
	seats = []
	_pending = -1
	_unhook()
	for panel in _panels:
		panel.seat = {}
		panel.visible = false
	_alpha = 0.0
	_goal = 0.0
	if _root != null:
		_sync_root()


## Result screen: fade out, hide, ignore the toggles.
func on_battle_finished() -> void:
	finished = true
	battle_active = false
	_pending = -1
	_goal = 0.0
	if _is_instant():
		_alpha = 0.0
	_sync_root()


## The same seat under another device (online: touch / pad / keyboard picked in the lobby, local seat only).
func set_seat_scheme(player_id: String, scheme: String, mouse: bool = false) -> void:
	for seat in seats:
		if String(seat["id"]) == player_id and (String(seat["scheme"]) != scheme or bool(seat.get("mouse", false)) != mouse):
			seat["scheme"] = scheme
			seat["mouse"] = mouse
			refresh()
			return


# ---- mode / toggle ----------------------------------------------------------------------------------------------------
## What a toggle does: OFF -> FULL, MIN -> FULL, FULL -> OFF. Remembered as the player's choice.
func toggle() -> int:
	if not battle_active or finished:
		return mode
	var current := target_mode()
	var next: int = Mode.OFF if current == Mode.FULL else Mode.FULL
	_user_toggled = true
	_prefs().set_enabled(next != Mode.OFF)
	request_mode(next)
	toggled.emit(next)
	return next


## The mode once any fade has finished.
func target_mode() -> int:
	return _pending if _pending >= 0 else mode


func request_mode(next: int) -> void:
	if finished or not battle_active or next == target_mode():
		return
	if _is_instant() or _alpha <= 0.001:
		_pending = -1
		_set_mode_now(next)
		if _is_instant():
			_alpha = _goal
		_sync_root()
	else:
		_pending = next
		_goal = 0.0


## F1 on a keyboard, Share / Back on any pad. Returns true when the event was a toggle (and was used).
func handle_event(event: InputEvent) -> bool:
	if not battle_active or finished or not visible:
		return false
	var id := event.get_instance_id()
	if id == _last_event_id:
		return false  # the same event reached us twice (own viewport and a host relay): one toggle only
	var hit := false
	if event is InputEventKey:
		hit = event.pressed and not event.echo and (event.physical_keycode == KEY_F1 or event.keycode == KEY_F1)
	elif event is InputEventJoypadButton:
		hit = event.pressed and event.button_index == JOY_BUTTON_BACK
	if not hit:
		return false
	_last_event_id = id
	toggle()
	return true


func _unhandled_input(event: InputEvent) -> void:
	if handle_event(event):
		get_viewport().set_input_as_handled()


# ---- bindings / device changes ----------------------------------------------------------------------------------------
func _hook() -> void:
	var b := _bindings()
	if _bindings_hooked != b:
		_unhook()
		b.changed.connect(_mark_dirty)
		_bindings_hooked = b


func _unhook() -> void:
	if _bindings_hooked != null and is_instance_valid(_bindings_hooked) and _bindings_hooked.changed.is_connected(_mark_dirty):
		_bindings_hooked.changed.disconnect(_mark_dirty)
	_bindings_hooked = null


func _mark_dirty() -> void:
	_dirty = true


func _on_joy_changed(_device: int, _connected: bool) -> void:
	_dirty = true


func _bindings() -> ControlBindings:
	return bindings if bindings != null else ControlBindings.shared()


func _prefs() -> ControlOverlayPrefs:
	return prefs if prefs != null else ControlOverlayPrefs.shared()


func _is_instant() -> bool:
	return instant or ThirdPersonCamera.reduce_motion


## Rebuilds every panel's text from the live bindings and controller names (also called by tests after changing
## ControllerGlyphs.fake_devices). Allocates; runs only when something changed.
func refresh() -> void:
	var b := _bindings()
	for panel in _panels:
		if panel.seat.is_empty():
			continue
		panel.set_content(title_for(panel.seat), rows(b, String(panel.seat["scheme"]), String(panel.seat["role"]), bool(panel.seat.get("mouse", false))),
				toggle_key_text(String(panel.seat["scheme"])))
	_apply_mode()
	_dirty = false
	_last_view = Vector2.ZERO  # force a relayout
	if _root != null and is_inside_tree():
		_relayout()


func _assign_panels() -> void:
	for panel in _panels:
		panel.seat = {}
	for seat in seats:
		var side := 0 if String(seat.get("color", "w")) == "w" else 1
		if not _panels[side].seat.is_empty():
			side = 1 - side
		_panels[side].seat = seat


func _set_mode_now(next: int) -> void:
	mode = next
	_apply_mode()
	_goal = 1.0 if (next != Mode.OFF or _has_touch_seat()) else 0.0


func _has_touch_seat() -> bool:
	for seat in seats:
		if String(seat["scheme"]) == "touch":
			return true
	return false


func _apply_mode() -> void:
	for panel in _panels:
		panel.apply_mode(mode)
	_dirty = true


# ---- layout -----------------------------------------------------------------------------------------------------------
func _view_size() -> Vector2:
	var vp := get_viewport()
	return vp.get_visible_rect().size if vp != null else Vector2.ZERO


func _safe_rect(view: Vector2) -> Rect2:
	if safe_area_override.size.x > 0.0:
		return safe_area_override
	if OS.has_feature("mobile"):
		var raw := Rect2(DisplayServer.get_display_safe_area())
		var win := Vector2(DisplayServer.window_get_size())
		if raw.size.x > 0.0 and win.x > 0.0 and win.y > 0.0:
			var k := view / win
			return Rect2(raw.position * k, raw.size * k).intersection(Rect2(Vector2.ZERO, view))
	return Rect2(Vector2.ZERO, view)


## Font size for a viewport height: 14 px at 720, 22 at 1080 (scaled from the viewport height, never below 12).
static func font_for_height(h: float) -> int:
	return clampi(roundi(h * 0.02), 12, 30)


func _relayout() -> void:
	var view := _view_size()
	if view.x < 8.0 or view.y < 8.0:
		return
	_last_view = view
	var fs := font_for_height(view.y)
	var safe := _safe_rect(view)
	var margin := maxf(10.0, view.y * 0.02)
	var top := maxf(TOP_BAND_PX, view.y * 0.19)
	var pause_right := 0.0
	var obstacles: Array[Rect2] = []  # visible touch controls (buttons + stick) a legend must stay clear of
	if _has_touch_seat():
		var lay := TouchControls.compute_layout(view, safe)
		for id in lay["buttons"]:
			var btn: Dictionary = lay["buttons"][id]
			var c: Vector2 = btn["center"]
			var r: float = btn["radius"]
			if id == "pause":
				pause_right = c.x + r
			else:
				obstacles.append(Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0))
		var stick: Dictionary = lay["stick"]
		var sc: Vector2 = stick["center"]
		var sr: float = stick["radius"]
		obstacles.append(Rect2(sc - Vector2(sr, sr), Vector2(sr, sr) * 2.0))
	for panel in _panels:
		if not panel.visible:
			panel.apply_metrics(fs)
			continue
		var size_fs := fs
		_place(panel, size_fs, safe, margin, top, pause_right)
		if String(panel.seat.get("scheme", "")) == "touch":
			# Shrink the legend (down to 10 px) until it clears the touch buttons: they take priority.
			while size_fs > 10 and _hits(Rect2(panel.position, panel.size).grow(margin * 0.5), obstacles):
				size_fs -= 1
				_place(panel, size_fs, safe, margin, top, pause_right)


func _place(panel: SeatPanel, fs: int, safe: Rect2, margin: float, top: float, pause_right: float) -> void:
	panel.apply_metrics(fs)
	panel.reset_size()
	var x := 0.0
	if panel.side == 0:
		x = safe.position.x + margin
		if String(panel.seat.get("scheme", "")) == "touch":
			x = maxf(x, pause_right + margin)  # keep clear of the PAUSE button
	else:
		x = safe.end.x - margin - panel.size.x
	panel.position = Vector2(x, maxf(top, safe.position.y))


static func _hits(rect: Rect2, obstacles: Array[Rect2]) -> bool:
	for o in obstacles:
		if rect.intersects(o):
			return true
	return false


func _sync_root() -> void:
	if _root == null:
		return
	_root.modulate.a = _alpha
	_root.visible = _alpha > 0.0


func _process(delta: float) -> void:
	if _root == null:
		return
	if _dirty and battle_active:
		refresh()
	elif _root.visible and _view_size() != _last_view:
		_relayout()
	var want := chip_filter_for(Input.mouse_mode)
	if want != _chip_filter:
		_chip_filter = want
		for panel in _panels:
			panel.chip.mouse_filter = want
	if battle_active and not finished and visible and mode == Mode.FULL and _pending < 0 and not _user_toggled:
		_age += delta
		if _age >= AUTO_MINIMISE_SECONDS:
			request_mode(Mode.MIN)
	if _is_instant():
		_alpha = _goal
	elif _alpha < _goal:
		_alpha = minf(_goal, _alpha + delta / FADE_SECONDS)
	elif _alpha > _goal:
		_alpha = maxf(_goal, _alpha - delta / FADE_SECONDS)
	if _alpha <= 0.0 and _pending >= 0:
		var next := _pending
		_pending = -1
		_set_mode_now(next)
	_sync_root()


## The chip is the only clickable part; a captured mouse (P1 mouse-look) must never be swallowed by it.
static func chip_filter_for(mouse_mode: int) -> int:
	return Control.MOUSE_FILTER_IGNORE if mouse_mode == Input.MOUSE_MODE_CAPTURED else Control.MOUSE_FILTER_STOP


# ---- test / inspection helpers --------------------------------------------------------------------------------------
func panel_at(side: int) -> SeatPanel:
	return _panels[side]


func alpha() -> float:
	return _alpha


## Every Control under this layer except the chips ignores the mouse.
func non_chip_controls_ignore_mouse() -> bool:
	for node in find_children("*", "Control", true, false):
		var c := node as Control
		var is_chip := false
		for panel in _panels:
			is_chip = is_chip or c == panel.chip
		if not is_chip and c.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			return false
	return true


## One side's panel: title, a two-column grid (pooled rows) and the toggle chip.
class SeatPanel extends PanelContainer:
	var side: int = 0
	var seat: Dictionary = {}
	var overlay: ControlOverlay
	var rows: Array = []
	var chip_text_full: String = ""
	var chip_text_min: String = ""
	var title: Label
	var grid: GridContainer
	var names: Array[Label] = []
	var values: Array[Label] = []
	var chip: Label
	var _box: VBoxContainer
	var _style: StyleBoxFlat
	var _chip_style: StyleBoxFlat
	var _fs: int = -1

	func build() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_style = StyleBoxFlat.new()
		_style.bg_color = Color(0.03, 0.04, 0.07, 0.58)
		_style.border_color = Color(1, 1, 1, 0.2)
		_style.set_border_width_all(1)
		_style.set_corner_radius_all(8)
		add_theme_stylebox_override("panel", _style)
		_box = VBoxContainer.new()
		_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_box)
		title = _label(Color(0.9, 0.78, 0.5))
		_box.add_child(title)
		grid = GridContainer.new()
		grid.columns = 2
		grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_box.add_child(grid)
		for _i in ControlOverlay.MAX_ROWS:
			var n := _label(Color(0.78, 0.82, 0.9))
			var v := _label(Color(1, 1, 1))
			grid.add_child(n)
			grid.add_child(v)
			names.append(n)
			values.append(v)
		chip = _label(Color(1, 0.95, 0.8))
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_chip_style = StyleBoxFlat.new()
		_chip_style.bg_color = Color(0.25, 0.2, 0.1, 0.7)
		_chip_style.border_color = Color(0.9, 0.75, 0.4, 0.6)
		_chip_style.set_border_width_all(1)
		_chip_style.set_corner_radius_all(6)
		chip.add_theme_stylebox_override("normal", _chip_style)
		chip.gui_input.connect(_on_chip_input)
		_box.add_child(chip)

	func _label(color: Color) -> Label:
		var l := Label.new()
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_theme_color_override("font_color", color)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		l.add_theme_constant_override("outline_size", 3)
		return l

	func _on_chip_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			chip.accept_event()
			overlay.toggle()

	func set_content(p_title: String, p_rows: Array, toggle_key: String) -> void:
		title.text = p_title
		rows = p_rows
		for i in ControlOverlay.MAX_ROWS:
			var used := i < p_rows.size()
			names[i].visible = used
			values[i].visible = used
			if used:
				names[i].text = String(p_rows[i][0])
				values[i].text = String(p_rows[i][1])
		chip_text_full = "%s · Hide" % toggle_key if toggle_key != "?" else "?  Hide"
		chip_text_min = "%s · Controls" % toggle_key if toggle_key != "?" else "?  Controls"

	func apply_mode(mode: int) -> void:
		var full: bool = mode == ControlOverlay.Mode.FULL
		var touch := String(seat.get("scheme", "")) == "touch"
		visible = not seat.is_empty() and (mode != ControlOverlay.Mode.OFF or touch)
		title.visible = full
		grid.visible = full
		chip.text = chip_text_full if full else (chip_text_min if mode == ControlOverlay.Mode.MIN else "?")

	func apply_metrics(fs: int) -> void:
		if fs == _fs:
			return
		_fs = fs
		var m := float(fs) * 0.6
		_style.content_margin_left = m
		_style.content_margin_right = m
		_style.content_margin_top = m * 0.8
		_style.content_margin_bottom = m * 0.8
		_chip_style.content_margin_left = m * 0.8
		_chip_style.content_margin_right = m * 0.8
		_chip_style.content_margin_top = 2.0
		_chip_style.content_margin_bottom = 2.0
		title.add_theme_font_size_override("font_size", fs + 1)
		for l in names:
			l.add_theme_font_size_override("font_size", fs)
		for l in values:
			l.add_theme_font_size_override("font_size", fs)
		chip.add_theme_font_size_override("font_size", maxi(11, fs - 1))
		_box.add_theme_constant_override("separation", maxi(3, roundi(fs * 0.3)))
		grid.add_theme_constant_override("h_separation", roundi(fs * 0.9))
		grid.add_theme_constant_override("v_separation", maxi(1, roundi(fs * 0.2)))
