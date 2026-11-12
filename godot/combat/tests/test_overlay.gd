extends RefCounted
## Controls overlay (presentation/control_overlay.gd + control_overlay_prefs.gd): content for every scheme and fighter class,
## layout (two seats, split halves, touch non-overlap at several resolutions, safe area), the F1 / Share / chip toggle,
## fades and auto-minimise, persistence (round trip, first-3-battles default, corrupt files), live updates on rebinding and
## controller changes, AI / online seat rules, the arena hooks (countdown shown, result hides), input never swallowed
## and the simulation being byte-identical with or without toggling the overlay. Headless; everything is freed.

const TouchControls := preload("res://combat/presentation/touch_controls.gd")
const WorldTests := preload("res://combat/tests/test_world.gd")  # its fixtures: the pit world with a Battle Chess capture
const ARENA := "res://combat/arena.tscn"
const TMP := "user://overlay_test_prefs.json"
const PS4 := {"name": "PS4 Controller"}
const XBOX := {"name": "XInput Gamepad"}
const GENERIC := {"name": "Generic USB Joystick"}
const RESOLUTIONS: Array = [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2400, 1080), Vector2i(1600, 720), Vector2i(1200, 800)]


static func run(h, tree: SceneTree) -> void:
	_reserved(h)
	_content(h)
	await _layout(h, tree)
	await _touch_layout(h, tree)
	await _toggle(h, tree)
	await _fade_and_minimise(h, tree)
	_persistence(h)
	await _live_updates(h, tree)
	await _no_swallow(h, tree)
	await _settings_hook(h, tree)
	await _arena_hooks(h, tree)
	await _simulation_unaffected(h, tree)
	await _pit_world(h, tree)


# ---- helpers -----------------------------------------------------------------------------------------------------
static func _seat(id: String, color: String, scheme: String, role: String = "b", mouse: bool = false) -> Dictionary:
	return {"id": id, "color": color, "role": role, "scheme": scheme, "mouse": mouse}


static func _prefs() -> ControlOverlayPrefs:
	var p := ControlOverlayPrefs.new()
	p.autosave = false
	return p


## An overlay in its own SubViewport of `size` (so the layout sees that viewport), instant fades.
static func _mount(tree: SceneTree, size: Vector2i, seats: Array, prefs: ControlOverlayPrefs = null, b: ControlBindings = null) -> ControlOverlay:
	var vp := SubViewport.new()
	vp.size = size
	vp.disable_3d = true
	tree.root.add_child(vp)
	var ov := ControlOverlay.new()
	ov.instant = true
	ov.prefs = prefs if prefs != null else _prefs()
	ov.bindings = b if b != null else ControlBindings.new()
	vp.add_child(ov)
	ov.begin(seats)
	return ov


static func _drop(ov: ControlOverlay) -> void:
	var vp := ov.get_parent()
	vp.get_parent().remove_child(vp)
	vp.free()


static func _key(code: int, pressed: bool = true, echo: bool = false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code as Key
	e.physical_keycode = code as Key
	e.pressed = pressed
	e.echo = echo
	return e


static func _pad(button: int, device: int = 0, pressed: bool = true) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.device = device
	e.button_index = button as JoyButton
	e.pressed = pressed
	return e


static func _values(ov: ControlOverlay, side: int) -> Dictionary:
	var out := {}
	for row in ov.panel_at(side).rows:
		out[String(row[0])] = String(row[1])
	return out


static func _rect(ov: ControlOverlay, side: int) -> Rect2:
	var p := ov.panel_at(side)
	return Rect2(p.position, p.size)


static func _circle(center: Vector2, radius: float) -> Rect2:
	return Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0)


static func _rm(path: String) -> void:
	for suffix in ["", ".tmp", ".corrupt"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))


# ---- reserved keys ------------------------------------------------------------------------------------------------------
static func _reserved(h) -> void:
	h.begin("overlay: F1 and Share/Back are reserved, so rebinding can never steal them")
	h.check(KEY_F1 in ControlBindings.RESERVED_KEYS and KEY_ESCAPE in ControlBindings.RESERVED_KEYS and KEY_F11 in ControlBindings.RESERVED_KEYS, "F1 joins Esc and F11 in the reserved keys")
	h.check(JOY_BUTTON_BACK in ControlBindings.RESERVED_PAD_BUTTONS and JOY_BUTTON_START in ControlBindings.RESERVED_PAD_BUTTONS, "Back/Share joins Start/Options in the reserved pad buttons")
	var b := ControlBindings.new()
	var r := b.set_key("kb1", "light", KEY_F1)
	h.check(not r["ok"], "set_key refuses F1")
	h.eq(b.key_for("kb1", "light"), KEY_F, "the light binding is untouched")
	h.check(not b.set_pad("light", {"type": "button", "index": JOY_BUTTON_BACK})["ok"], "set_pad refuses Share/Back")
	h.check(ControlBindings.event_to_pad(_pad(JOY_BUTTON_BACK)).is_empty(), "a captured Back press never becomes a binding")
	for scheme in ControlBindings.SCHEMES:
		for action in ControlBindings.KEY_ACTIONS:
			h.check(not (b.key_for(scheme, action) in ControlBindings.RESERVED_KEYS), "default %s/%s is not a reserved key" % [scheme, action])
	for action in ControlBindings.PAD_ACTIONS:
		var input: Dictionary = b.pad_input(action)
		h.check(not (input.get("type", "") == "button" and int(input["index"]) in ControlBindings.RESERVED_PAD_BUTTONS), "default pad/%s is not a reserved button" % action)
	# A hand-edited controls.json that binds F1 / Back falls back to the defaults instead of stealing them.
	var data := b.to_dict()
	data["keyboard"]["kb1"]["light"] = KEY_F1
	data["pad"]["light"] = "button:%d" % JOY_BUTTON_BACK
	var fresh := ControlBindings.new()
	h.check(fresh.from_dict(data), "a file with reserved bindings still loads")
	h.eq(fresh.key_for("kb1", "light"), KEY_F, "F1 in the file is replaced by the default")
	h.eq(fresh.pad_input("light"), ControlBindings.DEFAULT_PAD["light"], "Back in the file is replaced by the default")


# ---- content ------------------------------------------------------------------------------------------------------------
static func _content(h) -> void:
	h.begin("overlay: rows for every scheme come from the live bindings and the controller's own names")
	var b := ControlBindings.new()
	var labels := ["Move", "Light", "Heavy", "Block", "Parry", "Dodge", "Ability", "Sprint", "Lock-on", "Camera", "Pause"]
	var rows := ControlOverlay.rows(b, "kb1", "b", true)
	var got: Array = []
	for row in rows:
		got.append(row[0])
	h.eq(got, labels, "kb1 lists Move, Light, Heavy, Block, Parry, Dodge, Ability, Sprint, Lock-on, Camera, Pause in that order")
	var v := {}
	for row in rows:
		v[row[0]] = row[1]
	h.eq(v["Move"], "W A S D", "kb1 move")
	h.eq(v["Light"], "LMB / F", "kb1 light (mouse live)")
	h.eq(v["Heavy"], "RMB / G", "kb1 heavy (mouse live)")
	h.eq(v["Block"], "Q (hold)", "kb1 block")
	h.eq(v["Parry"], "E", "kb1 parry")
	h.eq(v["Dodge"], "Space", "kb1 dodge")
	h.eq(v["Ability"], "R (Blink)", "kb1 ability with the fighter's ability name")
	h.eq(v["Sprint"], "Shift (hold)", "kb1 sprint")
	h.eq(v["Lock-on"], "Tab / MMB", "kb1 lock-on")
	h.eq(v["Camera"], "Mouse / Z X", "kb1 camera")
	h.eq(v["Pause"], "Esc", "kb1 pause")
	var shared := {}
	for row in ControlOverlay.rows(b, "kb1", "b", false):
		shared[row[0]] = row[1]
	h.eq(shared["Light"], "F", "without the mouse (hot-seat) kb1 shows keys only")
	h.eq(shared["Lock-on"], "Tab", "no MMB when the mouse is not live")
	h.eq(shared["Camera"], "Z X", "camera keys only")
	var k2 := {}
	for row in ControlOverlay.rows(b, "kb2", "n"):
		k2[row[0]] = row[1]
	h.eq(k2["Move"], "Arrow keys", "kb2 move")
	h.eq(k2["Light"], "J", "kb2 light")
	h.eq(k2["Heavy"], "K", "kb2 heavy")
	h.eq(k2["Block"], "U (hold)", "kb2 block")
	h.eq(k2["Ability"], "O (Lunging Strike)", "kb2 ability (knight)")
	h.eq(k2["Sprint"], "Ctrl (hold)", "kb2 sprint")
	h.eq(k2["Camera"], ", .", "kb2 camera")

	ControllerGlyphs.fake_devices = {0: PS4, 1: XBOX, 2: GENERIC}
	var ps := {}
	for row in ControlOverlay.rows(b, "pad0", "r"):
		ps[row[0]] = row[1]
	h.eq(ps["Move"], "Left stick", "PS4 move")
	h.eq(ps["Light"], "Square", "PS4 light")
	h.eq(ps["Heavy"], "Triangle / R2", "PS4 heavy (R2 alias)")
	h.eq(ps["Block"], "L1 (hold)", "PS4 block")
	h.eq(ps["Parry"], "R1", "PS4 parry")
	h.eq(ps["Dodge"], "Cross", "PS4 dodge")
	h.eq(ps["Ability"], "Circle (Fortress Guard)", "PS4 ability (rook)")
	h.eq(ps["Sprint"], "L2 (hold)", "PS4 sprint")
	h.eq(ps["Lock-on"], "L3", "PS4 lock-on")
	h.eq(ps["Camera"], "Right stick", "PS4 camera")
	h.eq(ps["Pause"], "Options", "PS4 pause")
	var xb := {}
	for row in ControlOverlay.rows(b, "pad1", "q"):
		xb[row[0]] = row[1]
	h.eq(xb["Light"], "X", "Xbox light")
	h.eq(xb["Heavy"], "Y / RT", "Xbox heavy")
	h.eq(xb["Block"], "LB (hold)", "Xbox block")
	h.eq(xb["Parry"], "RB", "Xbox parry")
	h.eq(xb["Dodge"], "A", "Xbox dodge")
	h.eq(xb["Ability"], "B (Royal Fury)", "Xbox ability (queen)")
	h.eq(xb["Sprint"], "LT (hold)", "Xbox sprint")
	h.eq(xb["Pause"], "Menu", "Xbox pause")
	var gen := {}
	for row in ControlOverlay.rows(b, "pad2", "p"):
		gen[row[0]] = row[1]
	h.eq(gen["Dodge"], "A", "an unknown pad falls back to the Xbox-style names")
	h.eq(gen["Sprint"], "LT (hold)", "unknown pad triggers read LT")
	h.eq(gen["Ability"], "B (Last Stand)", "unknown pad ability (pawn)")
	h.eq(ControlOverlay.toggle_key_text("pad0"), "F1 / Share", "PS4 toggle is F1 / Share")
	h.eq(ControlOverlay.toggle_key_text("pad1"), "F1 / View", "Xbox toggle is F1 / View")
	h.eq(ControlOverlay.toggle_key_text("kb1"), "F1", "keyboard toggle is F1")
	h.eq(ControlOverlay.toggle_key_text("touch"), "?", "touch toggle is the ? button")
	h.check(ControlOverlay.title_for(_seat("w", "w", "pad0")).contains("PlayStation"), "the PS4 title names the controller family")
	h.check(ControlOverlay.title_for(_seat("b", "b", "pad1")).begins_with("P2 Black"), "Black is P2")
	ControllerGlyphs.fake_devices = {}

	var touch := {}
	for row in ControlOverlay.rows(b, "touch", "b"):
		touch[row[0]] = row[1]
	h.eq(touch["Attack"], "LIGHT / HEAVY", "touch shows the on-screen button names")
	h.eq(touch["Defend"], "BLOCK (hold) / PARRY / DODGE", "touch defend buttons")
	h.eq(touch["Ability"], "SPECIAL (Blink)", "touch special button + ability name")
	h.eq(touch["Lock-on"], "LOCK", "touch lock")
	h.eq(touch["Pause"], "II", "touch pause button")

	h.begin("overlay: every fighter class shows its own ability name")
	var expected := {"p": "Last Stand", "n": "Lunging Strike", "b": "Blink", "r": "Fortress Guard", "q": "Royal Fury", "k": "Royal Counter"}
	h.eq(FighterRoster.ALL_ROLES.size(), 6, "six fighter classes")
	for role in FighterRoster.ALL_ROLES:
		for scheme in ["kb1", "kb2", "pad0", "touch"]:
			var found := ""
			for row in ControlOverlay.rows(b, scheme, role, scheme == "kb1"):
				if row[0] == "Ability":
					found = String(row[1])
			h.check(found.contains(expected[role]), "%s / %s ability row says %s (got %s)" % [role, scheme, expected[role], found])


# ---- layout --------------------------------------------------------------------------------------------------------------
static func _layout(h, tree: SceneTree) -> void:
	h.begin("overlay: two local seats get one panel each (P1 left, P2 right), readable, off the centre and the HUD bars")
	var scales: Array = []
	for size in RESOLUTIONS:
		var view := Vector2(size)
		var ov := _mount(tree, size, [_seat("player-white", "w", "kb1", "q"), _seat("player-black", "b", "kb2", "r")])
		await tree.process_frame
		await tree.process_frame
		var left := _rect(ov, 0)
		var right := _rect(ov, 1)
		h.check(ov.panel_at(0).visible and ov.panel_at(1).visible, "%s: both panels shown" % str(size))
		h.check(left.size.x > 80.0 and left.size.y > 100.0, "%s: the left panel has a real size %s" % [str(size), str(left.size)])
		h.check(left.end.x <= view.x * 0.5, "%s: P1's panel sits inside the left half (ends at %.0f of %.0f)" % [str(size), left.end.x, view.x * 0.5])
		h.check(right.position.x >= view.x * 0.5, "%s: P2's panel sits inside the right half" % str(size))
		h.check(left.position.x < right.position.x, "%s: P1 left of P2" % str(size))
		h.check(Rect2(Vector2.ZERO, view).encloses(left) and Rect2(Vector2.ZERO, view).encloses(right), "%s: both panels are fully on screen" % str(size))
		var centre := Rect2(view * 0.5 - view * Vector2(0.15, 0.2), view * Vector2(0.3, 0.4))
		h.check(not left.intersects(centre) and not right.intersects(centre), "%s: nothing covers the centre of the screen" % str(size))
		var bars := Rect2(Vector2.ZERO, Vector2(view.x, 124.0))  # the HUD's health / stamina / ability bars
		h.check(not left.intersects(bars) and not right.intersects(bars), "%s: nothing covers the health bars" % str(size))
		h.check(left.end.y <= view.y - 100.0 and right.end.y <= view.y - 100.0, "%s: the HUD hint line at the bottom is clear" % str(size))
		var fs: int = ov.panel_at(0).values[0].get_theme_font_size("font_size")
		h.check(fs >= 12, "%s: font %d px is readable" % [str(size), fs])
		scales.append(float(fs))
		h.check(ov.panel_at(0).title.text.begins_with("P1 White") and ov.panel_at(1).title.text.begins_with("P2 Black"), "%s: titles name the player" % str(size))
		h.eq(_values(ov, 1)["Move"], "Arrow keys", "%s: the right panel is Player 2's keyboard" % str(size))
		var shown_a := ov.panel_at(0).values[6].text
		h.eq(shown_a, "R (Royal Fury)", "%s: the labels hold the text (queen ability)" % str(size))
		_drop(ov)
	h.check(scales[2] >= scales[0] * 1.4, "the font scales with the viewport height (%d px at 720, %d px at 1080)" % [int(scales[0]), int(scales[2])])

	h.begin("overlay: a single local seat sits on its own side; an AI seat gets no panel")
	var white := _mount(tree, Vector2i(1280, 720), [_seat("player-white", "w", "kb1", "p", true)])
	await tree.process_frame
	h.check(white.panel_at(0).visible and not white.panel_at(1).visible, "White alone -> left panel only")
	_drop(white)
	var black := _mount(tree, Vector2i(1280, 720), [_seat("player-black", "b", "pad0", "n")])
	await tree.process_frame
	h.check(black.panel_at(1).visible and not black.panel_at(0).visible, "Black alone -> right panel only")
	h.check(_rect(black, 1).end.x <= 1280.0, "and it stays on screen")
	_drop(black)
	var none := _mount(tree, Vector2i(1280, 720), [])
	await tree.process_frame
	h.check(not none.panel_at(0).visible and not none.panel_at(1).visible and not none.get_child(0).visible, "no local human seat (AI vs AI) -> nothing is shown")
	_drop(none)

	h.begin("overlay: panels respect the safe area")
	var safe := Rect2(Vector2(60, 24), Vector2(2400 - 120, 1080 - 48))
	var notch := _mount(tree, Vector2i(2400, 1080), [_seat("a", "w", "kb1"), _seat("b", "b", "kb2")])
	notch.safe_area_override = safe
	notch.refresh()
	await tree.process_frame
	h.check(safe.encloses(_rect(notch, 0)) and safe.encloses(_rect(notch, 1)), "both panels are inside a notched safe area (%s, %s)" % [str(_rect(notch, 0)), str(_rect(notch, 1))])
	h.check(_rect(notch, 0).position.x > safe.position.x, "the left panel keeps a margin from the notch")
	_drop(notch)


static func _touch_layout(h, tree: SceneTree) -> void:
	h.begin("overlay: the touch legend never overlaps the touch controls (any resolution, either side, with a notch)")
	for size in RESOLUTIONS:
		for color in ["w", "b"]:
			for notch in [false, true]:
				var view := Vector2(size)
				var safe := Rect2(Vector2(70, 20), view - Vector2(140, 40)) if notch else Rect2(Vector2.ZERO, view)
				var ov := _mount(tree, size, [_seat("t", color, "touch", "q")])
				ov.safe_area_override = safe if notch else Rect2()
				ov.refresh()
				await tree.process_frame
				var side := 0 if color == "w" else 1
				var rect := _rect(ov, side)
				var lay := TouchControls.compute_layout(view, safe)
				var tag := "%s %s%s" % [str(size), color, " notch" if notch else ""]
				var clear := true
				for id in lay["buttons"]:
					var btn: Dictionary = lay["buttons"][id]
					if rect.intersects(_circle(btn["center"], btn["radius"])):
						clear = false
				var stick: Dictionary = lay["stick"]
				if rect.intersects(_circle(stick["center"], stick["radius"])):
					clear = false
				h.check(clear, "%s: the legend (%s) avoids every touch button and the stick" % [tag, str(rect)])
				h.check(safe.encloses(rect), "%s: the legend is inside the safe area" % tag)
				h.check(rect.position.y >= 124.0, "%s: the legend is below the HUD bars" % tag)
				h.eq(ov.panel_at(side).rows.size(), 8, "%s: the compact legend has 8 rows" % tag)
				_drop(ov)
	h.begin("overlay: toggled off, touch keeps only a small ? button (there is no keyboard to bring it back)")
	var ov := _mount(tree, Vector2i(1280, 720), [_seat("t", "w", "touch")])
	ov.toggle()
	await tree.process_frame
	h.eq(ov.mode, ControlOverlay.Mode.OFF, "toggled off")
	h.check(ov.panel_at(0).visible and ov.panel_at(0).chip.text == "?" and not ov.panel_at(0).grid.visible, "only the ? chip remains")
	var chip := ov.panel_at(0).chip
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.device = InputEvent.DEVICE_ID_EMULATION  # what a tap turns into
	ov.panel_at(0)._on_chip_input(click)
	h.eq(ov.mode, ControlOverlay.Mode.FULL, "tapping ? brings the legend back")
	h.check(chip.mouse_filter == Control.MOUSE_FILTER_STOP or chip.mouse_filter == Control.MOUSE_FILTER_IGNORE, "chip has a defined mouse filter")
	_drop(ov)


# ---- toggle --------------------------------------------------------------------------------------------------------------
static func _toggle(h, tree: SceneTree) -> void:
	h.begin("overlay: F1 toggles on every scheme; Share/Back toggles from any pad; the chip click toggles; the choice is remembered")
	for scheme in ["kb1", "kb2", "pad0", "touch"]:
		var prefs := _prefs()
		var ov := _mount(tree, Vector2i(1280, 720), [_seat("s", "w", scheme)], prefs)
		h.eq(ov.mode, ControlOverlay.Mode.FULL, "%s: a fresh profile starts with the sheet" % scheme)
		h.check(ov.handle_event(_key(KEY_F1)), "%s: F1 is used as the toggle" % scheme)
		h.eq(ov.mode, ControlOverlay.Mode.OFF, "%s: F1 switches it off" % scheme)
		h.check(not prefs.enabled and prefs.chosen, "%s: the choice is remembered" % scheme)
		h.check(ov.handle_event(_key(KEY_F1)), "%s: F1 again" % scheme)
		h.eq(ov.mode, ControlOverlay.Mode.FULL, "%s: back on" % scheme)
		h.check(prefs.enabled, "%s: remembered as on" % scheme)
		_drop(ov)
	var prefs := _prefs()
	var ov := _mount(tree, Vector2i(1280, 720), [_seat("w", "w", "pad0"), _seat("b", "b", "pad1")], prefs)
	h.check(ov.handle_event(_pad(JOY_BUTTON_BACK, 0)), "Share on pad 0 toggles")
	h.eq(ov.mode, ControlOverlay.Mode.OFF, "off")
	h.check(ov.handle_event(_pad(JOY_BUTTON_BACK, 1)), "Back on pad 1 toggles too (any device id)")
	h.eq(ov.mode, ControlOverlay.Mode.FULL, "on")
	h.check(not ov.handle_event(_pad(JOY_BUTTON_BACK, 0, false)), "a release is ignored")
	h.check(not ov.handle_event(_key(KEY_F1, true, true)), "a key echo is ignored")
	h.check(not ov.handle_event(_key(KEY_F1, false)), "a key release is ignored")
	h.check(not ov.handle_event(_pad(JOY_BUTTON_START, 0)), "Options/Start is not the overlay toggle (it pauses)")
	h.eq(ov.mode, ControlOverlay.Mode.FULL, "nothing changed")
	var e := _key(KEY_F1)
	h.check(ov.handle_event(e) and not ov.handle_event(e), "the very same event (own viewport + host relay) toggles only once")
	h.eq(ov.mode, ControlOverlay.Mode.OFF, "off after one toggle")
	h.eq(ov.toggle(), ControlOverlay.Mode.FULL, "toggle() again -> on")
	# The chip on the panel
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	ov.panel_at(0)._on_chip_input(click)
	h.eq(ov.mode, ControlOverlay.Mode.OFF, "clicking the chip hides the sheet")
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	ov.panel_at(0)._on_chip_input(right_click)
	h.eq(ov.mode, ControlOverlay.Mode.OFF, "a right click on the chip does nothing")
	h.check(not ov.panel_at(0).visible and not ov.panel_at(1).visible, "when toggled off (keyboard / pad seats) nothing is shown")
	ov.on_battle_finished()
	h.check(not ov.handle_event(_key(KEY_F1)), "after the battle ended the toggles are ignored")
	_drop(ov)

	h.begin("overlay: the toggle is ignored while the overlay layer is hidden (pit-world drop / climb)")
	var hidden := _mount(tree, Vector2i(1280, 720), [_seat("w", "w", "kb1")])
	hidden.visible = false
	h.check(not hidden.handle_event(_key(KEY_F1)), "a hidden layer does not toggle")
	h.eq(hidden.mode, ControlOverlay.Mode.FULL, "state unchanged")
	_drop(hidden)


# ---- fades / auto-minimise ---------------------------------------------------------------------------------------------------
static func _fade_and_minimise(h, tree: SceneTree) -> void:
	h.begin("overlay: 150 ms fades, instant under reduce-motion")
	var ov := _mount(tree, Vector2i(1280, 720), [_seat("w", "w", "kb1")])
	ov.instant = false
	ov.begin([_seat("w", "w", "kb1")])
	h.near(ov.alpha(), 0.0, 0.001, "fades in from 0")
	ov._process(0.075)
	h.near(ov.alpha(), 0.5, 0.01, "half way after 75 ms")
	ov._process(0.08)
	h.near(ov.alpha(), 1.0, 0.001, "fully visible after 150 ms")
	ov.toggle()
	h.eq(ov.target_mode(), ControlOverlay.Mode.OFF, "toggled off: the target mode is OFF")
	h.eq(ov.mode, ControlOverlay.Mode.FULL, "the sheet is still drawn while it fades")
	ov._process(0.075)
	h.near(ov.alpha(), 0.5, 0.01, "fading out")
	ov._process(0.08)
	h.near(ov.alpha(), 0.0, 0.001, "gone after 150 ms")
	h.eq(ov.mode, ControlOverlay.Mode.OFF, "now OFF")
	h.check(not ov.get_child(0).visible, "the root is hidden when faded out")
	ov.toggle()
	h.eq(ov.mode, ControlOverlay.Mode.FULL, "switching on from OFF shows the sheet at once and fades it in")
	ov._process(0.15)
	h.near(ov.alpha(), 1.0, 0.001, "fully back")
	ThirdPersonCamera.reduce_motion = true
	ov.toggle()
	h.eq(ov.mode, ControlOverlay.Mode.OFF, "reduce-motion: instant off")
	h.near(ov.alpha(), 0.0, 0.001, "no fade")
	ov.toggle()
	h.near(ov.alpha(), 1.0, 0.001, "reduce-motion: instant on")
	ThirdPersonCamera.reduce_motion = false
	_drop(ov)

	h.begin("overlay: a sheet nobody touched folds into the 'F1 Controls' chip after 8 s; toggling off shows nothing")
	var prefs := _prefs()
	var m := _mount(tree, Vector2i(1280, 720), [_seat("w", "w", "kb1")], prefs)
	for _i in 479:
		m._process(1.0 / 60.0)
	h.eq(m.mode, ControlOverlay.Mode.FULL, "still the full sheet just before 8 s")
	for _i in 6:
		m._process(1.0 / 60.0)
	h.eq(m.mode, ControlOverlay.Mode.MIN, "folded into the chip after 8 s")
	h.check(m.panel_at(0).visible and not m.panel_at(0).grid.visible, "the chip stays visible, never fully disappearing")
	h.eq(m.panel_at(0).chip.text, "F1 · Controls", "the chip reads 'F1 Controls'")
	h.check(prefs.enabled and not prefs.chosen, "auto-minimising is not the player's choice and is not remembered as one")
	h.eq(m.toggle(), ControlOverlay.Mode.FULL, "F1 on the chip brings the sheet back")
	for _i in 700:
		m._process(1.0 / 60.0)
	h.eq(m.mode, ControlOverlay.Mode.FULL, "once the player toggled, the sheet stays (no more auto-minimise)")
	m.toggle()
	h.eq(m.mode, ControlOverlay.Mode.OFF, "toggle off")
	h.check(not m.panel_at(0).visible, "toggled off shows nothing")
	_drop(m)
	var p2 := ControlOverlayPrefs.new()
	p2.autosave = false
	p2.battles = 5
	var late := _mount(tree, Vector2i(1280, 720), [_seat("w", "w", "kb1")], p2)
	h.eq(late.mode, ControlOverlay.Mode.MIN, "after the first battles a profile that never chose starts with the chip")
	_drop(late)


# ---- persistence ------------------------------------------------------------------------------------------------------------
static func _persistence(h) -> void:
	h.begin("overlay prefs: defaults, the first 3 battles, last choice remembered, round trip")
	var p := ControlOverlayPrefs.new()
	p.autosave = false
	h.check(p.enabled and not p.chosen and p.battles == 0, "fresh profile: on, never chosen, no battles")
	h.eq(p.begin_battle(), ControlOverlayPrefs.Start.FULL, "battle 1: full sheet")
	h.eq(p.begin_battle(), ControlOverlayPrefs.Start.FULL, "battle 2: full sheet")
	h.eq(p.begin_battle(), ControlOverlayPrefs.Start.FULL, "battle 3: full sheet")
	h.eq(p.begin_battle(), ControlOverlayPrefs.Start.MINIMISED, "battle 4 without a choice: the small chip")
	h.eq(p.battles, 4, "four battles counted")
	p.set_enabled(true)
	h.eq(p.start_mode(), ControlOverlayPrefs.Start.FULL, "an explicit 'on' keeps the full sheet")
	p.set_enabled(false)
	h.eq(p.start_mode(), ControlOverlayPrefs.Start.OFF, "an explicit 'off' stays off")
	var q := ControlOverlayPrefs.new()
	q.autosave = false
	q.begin_battle()
	q.set_enabled(false)  # the player switched it off during battle 1
	h.eq(q.begin_battle(), ControlOverlayPrefs.Start.OFF, "a choice made inside the first 3 battles is honoured from the next one")
	_rm(TMP)
	var a := ControlOverlayPrefs.new()
	a.path = TMP
	h.eq(a.save_file(), OK, "saves")
	a.begin_battle()  # autosave writes
	a.begin_battle()
	a.set_enabled(false)
	var b := ControlOverlayPrefs.new()
	b.path = TMP
	h.check(b.load_file(), "the file loads")
	h.check(not b.enabled and b.chosen and b.battles == 2, "round trip: off, chosen, 2 battles (got %s)" % str(b.to_dict()))
	h.eq(b.to_dict()["version"], ControlOverlayPrefs.VERSION, "versioned")
	h.check(b.last_error.is_empty(), "no error")
	_rm(TMP)
	var missing := ControlOverlayPrefs.new()
	missing.path = TMP
	h.check(not missing.load_file() and missing.enabled and missing.battles == 0 and missing.last_error.is_empty(), "a missing file is not an error: defaults")

	h.begin("overlay prefs: corrupt, hostile and foreign files load defaults, are quarantined and never raise")
	var bad := {
		"garbage": "this is not json {{{",
		"array": "[1, 2, 3]",
		"wrong version": '{"version": 2, "enabled": false, "chosen": true, "battles": 4}',
		"no version": '{"enabled": false, "chosen": true, "battles": 4}',
		"wrong type": '{"version": 1, "enabled": "no", "chosen": true, "battles": 4}',
		"missing field": '{"version": 1, "enabled": false}',
		"negative battles": '{"version": 1, "enabled": false, "chosen": true, "battles": -3}',
		"huge battles": '{"version": 1, "enabled": false, "chosen": true, "battles": 1e12}',
		"fractional battles": '{"version": 1, "enabled": false, "chosen": true, "battles": 2.5}',
		"null": "null",
		"empty": "",
		"oversize": '{"version": 1, "enabled": false, "chosen": true, "battles": 1, "pad": "%s"}' % "x".repeat(ControlOverlayPrefs.MAX_BYTES + 10),
	}
	for label in bad:
		_rm(TMP)
		var f := FileAccess.open(TMP, FileAccess.WRITE)
		f.store_string(bad[label])
		f.close()
		var c := ControlOverlayPrefs.new()
		c.path = TMP
		c.enabled = false  # prove the defaults come back, not a leftover
		c.battles = 9
		var ok := c.load_file()
		h.check(not ok, "%s: rejected" % label)
		h.check(c.enabled and not c.chosen and c.battles == 0, "%s: defaults loaded" % label)
		h.check(not c.last_error.is_empty(), "%s: the reason is recorded" % label)
		h.check(FileAccess.file_exists(TMP + ".corrupt") and not FileAccess.file_exists(TMP), "%s: moved aside to .corrupt" % label)
		h.eq(c.save_file(), OK, "%s: the next save writes a clean file" % label)
		var again := ControlOverlayPrefs.new()
		again.path = TMP
		h.check(again.load_file(), "%s: and that file loads" % label)
	_rm(TMP)


# ---- live updates ----------------------------------------------------------------------------------------------------------
static func _live_updates(h, tree: SceneTree) -> void:
	h.begin("overlay: rebinding and controller (dis)connects update the text live")
	var b := ControlBindings.new()
	var ov := _mount(tree, Vector2i(1280, 720), [_seat("w", "w", "kb1", "b", true)], null, b)
	await tree.process_frame
	h.eq(ov.panel_at(0).values[6].text, "R (Blink)", "before: R")
	h.check(b.set_key("kb1", "ability", KEY_T)["ok"], "rebind ability to T")
	await tree.process_frame
	h.eq(ov.panel_at(0).values[6].text, "T (Blink)", "the sheet shows T after the next frame")
	b.set_key("kb1", "light", KEY_H)
	await tree.process_frame
	h.eq(ov.panel_at(0).values[1].text, "LMB / H", "light shows H")
	b.reset_defaults("kb1")
	await tree.process_frame
	h.eq(ov.panel_at(0).values[1].text, "LMB / F", "reset restores F")
	_drop(ov)

	ControllerGlyphs.fake_devices = {0: PS4}
	var pb := ControlBindings.new()
	var pad := _mount(tree, Vector2i(1280, 720), [_seat("w", "w", "pad0", "n")], null, pb)
	await tree.process_frame
	h.eq(_values(pad, 0)["Dodge"], "Cross", "PS4 pad: Cross")
	h.eq(pad.panel_at(0).chip.text, "F1 / Share · Hide", "PS4 pad chip names Share")
	ControllerGlyphs.fake_devices = {0: XBOX}
	Input.joy_connection_changed.emit(0, true)  # another controller took device 0 (what hot-plug emits)
	await tree.process_frame
	h.eq(_values(pad, 0)["Dodge"], "A", "after the controller changed: A")
	h.eq(pad.panel_at(0).chip.text, "F1 / View · Hide", "and the chip names View")
	h.check(pb.set_pad("ability", {"type": "button", "index": JOY_BUTTON_X})["ok"], "rebind the pad ability to the X button")
	await tree.process_frame
	h.eq(_values(pad, 0)["Ability"], "X (Lunging Strike)", "pad rebinding shows up")
	ControllerGlyphs.fake_devices = {}
	_drop(pad)

	h.begin("overlay: set_seat_scheme (online lobby switches device)")
	var online := _mount(tree, Vector2i(1280, 720), [_seat("player-black", "b", "kb1", "q", true)])
	online.set_seat_scheme("player-black", "touch")
	h.eq(online.panel_at(1).rows.size(), 8, "the local seat now shows the touch legend")
	online.set_seat_scheme("player-black", "kb1", false)
	h.eq(_values(online, 1)["Light"], "F", "and back to the keyboard without the mouse")
	online.set_seat_scheme("someone-else", "touch")
	h.eq(_values(online, 1)["Light"], "F", "an unknown seat id is ignored")
	_drop(online)


# ---- input is never swallowed ------------------------------------------------------------------------------------------
class _Probe extends Node:
	var seen: Array = []

	func _unhandled_input(event: InputEvent) -> void:
		seen.append(event)


static func _no_swallow(h, tree: SceneTree) -> void:
	h.begin("overlay: it never takes gameplay input (mouse filters, key events pass through, F1 is the only key it eats)")
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.disable_3d = true
	tree.root.add_child(vp)
	var probe := _Probe.new()
	vp.add_child(probe)  # first child = processed last: it only sees what the overlay leaves
	var ov := ControlOverlay.new()
	ov.instant = true
	ov.prefs = _prefs()
	ov.bindings = ControlBindings.new()
	vp.add_child(ov)
	ov.begin([_seat("w", "w", "kb1", "b", true), _seat("b", "b", "pad0", "n")])
	await tree.process_frame
	await tree.process_frame
	h.check(ov.non_chip_controls_ignore_mouse(), "every control except the chip ignores the mouse")
	for panel in [ov.panel_at(0), ov.panel_at(1)]:
		h.eq(panel.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the panel itself ignores the mouse")
		h.eq(panel.chip.mouse_filter, Control.MOUSE_FILTER_STOP, "the chip is the one clickable part")
	# (A headless display server keeps the mouse mode VISIBLE, so the rule itself is tested, and the live wiring below.)
	h.eq(ControlOverlay.chip_filter_for(Input.MOUSE_MODE_CAPTURED), Control.MOUSE_FILTER_IGNORE, "while the mouse is captured for mouse-look even the chip lets clicks through")
	h.eq(ControlOverlay.chip_filter_for(Input.MOUSE_MODE_VISIBLE), Control.MOUSE_FILTER_STOP, "the chip is clickable with a visible mouse")
	h.eq(ControlOverlay.chip_filter_for(Input.MOUSE_MODE_CONFINED), Control.MOUSE_FILTER_STOP, "and with a confined one")
	ov._process(0.016)
	h.eq(ov.panel_at(0).chip.mouse_filter, ControlOverlay.chip_filter_for(Input.mouse_mode), "the chips follow the live mouse mode")
	var passed := 0
	var gameplay: Array = []
	for code in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_F, KEY_G, KEY_Q, KEY_E, KEY_R, KEY_SPACE, KEY_SHIFT, KEY_TAB, KEY_Z, KEY_X, KEY_J, KEY_K, KEY_L, KEY_U, KEY_I, KEY_O, KEY_P, KEY_UP, KEY_CTRL, KEY_ESCAPE, KEY_F11, KEY_F2, KEY_ENTER]:
		gameplay.append(_key(code))
	for button in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_LEFT_STICK, JOY_BUTTON_START, JOY_BUTTON_DPAD_UP]:
		gameplay.append(_pad(button))
	var motion := InputEventJoypadMotion.new()
	motion.axis = JOY_AXIS_TRIGGER_LEFT
	motion.axis_value = 1.0
	gameplay.append(motion)
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	gameplay.append(mouse)
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	gameplay.append(touch)
	for event in gameplay:
		vp.push_input(event)
	passed = probe.seen.size()
	h.eq(passed, gameplay.size(), "all %d gameplay / menu events reached the nodes behind the overlay" % gameplay.size())
	h.eq(ov.mode, ControlOverlay.Mode.FULL, "none of them toggled anything")
	probe.seen.clear()
	vp.push_input(_key(KEY_F1))
	h.eq(probe.seen.size(), 0, "F1 is consumed (it is the toggle)")
	h.eq(ov.mode, ControlOverlay.Mode.OFF, "and it toggled through the real viewport path")
	vp.push_input(_pad(JOY_BUTTON_BACK, 1))
	h.eq(probe.seen.size(), 0, "Share is consumed")
	h.eq(ov.mode, ControlOverlay.Mode.FULL, "and toggled")
	vp.get_parent().remove_child(vp)
	vp.free()


# ---- settings screen / menu hook ---------------------------------------------------------------------------------------------
static func _settings_hook(h, tree: SceneTree) -> void:
	h.begin("overlay: 'Show controls overlay in battles' in the controls screen is the same remembered choice")
	var prefs := _prefs()
	ControlOverlayPrefs.set_shared(prefs)
	var b := ControlBindings.new()
	var screen := ControlsScreen.open(tree.root, b, InputAssignment.new(b))
	screen.autosave = false
	await tree.process_frame
	await tree.process_frame
	var check: CheckButton = null
	for node in screen.find_children("*", "CheckButton", true, false):
		if (node as CheckButton).text == "Show controls overlay in battles":
			check = node
	if h.check(check != null, "the controls screen has the checkbox"):
		h.check(check.button_pressed, "it starts checked on a fresh profile")
		check.button_pressed = false
		check.toggled.emit(false)
		h.check(not prefs.enabled and prefs.chosen, "unchecking stores 'off' as the player's choice")
		check.button_pressed = true
		check.toggled.emit(true)
		h.check(prefs.enabled, "checking stores 'on'")
	for _i in 4:
		await tree.process_frame  # let the screen's own deferred focus coroutine finish before it is freed
	screen.get_parent().remove_child(screen)
	screen.free()
	ControlOverlayPrefs.set_shared(null)


# ---- arena hooks ------------------------------------------------------------------------------------------------------------
static func _arena(tree: SceneTree, seats: Dictionary, seed: int, id: String, white: String = "q", black: String = "r", mode: int = CombatArena.Mode.AUTHORITY, local_id: String = "") -> CombatArena:
	var arena: CombatArena = (load(ARENA) as PackedScene).instantiate()
	arena.mode = mode as CombatArena.Mode
	tree.root.add_child(arena)
	if local_id != "":
		arena.configure_network(local_id, func(_packet): pass)
	else:
		arena.configure_seats(seats)
	var reply: Dictionary = arena.start_battle(FighterRoster.build_request(white, black, "w", id, seed, 0))
	if not reply["ok"]:
		push_error("overlay test: battle did not start: %s" % str(reply))
	return arena


static func _free_arena(tree: SceneTree, arena: CombatArena) -> void:
	arena.stop_battle()
	arena.get_parent().remove_child(arena)
	arena.free()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


static func _arena_hooks(h, tree: SceneTree) -> void:
	var old_bindings := ControlBindings.shared()
	var shared_bindings := ControlBindings.new()
	ControlBindings.set_shared(shared_bindings)
	var prefs := _prefs()
	prefs.chosen = true  # no auto-minimise surprises while we look
	ControlOverlayPrefs.set_shared(prefs)

	h.begin("overlay: a CombatArena shows the sheet during the countdown for its human seat only, and hides it on the result screen")
	var arena := _arena(tree, {"player-white": {"type": "human", "scheme": "kb1"}, "player-black": {"type": "ai", "skill": 0.4}}, 11, "ov-pve")
	var overlay: ControlOverlay = arena.overlay
	if not h.check(overlay != null, "the arena owns a ControlOverlay"):
		_free_arena(tree, arena)
		return
	overlay.instant = true
	await tree.process_frame
	h.check(arena.sim.phase == CombatSimulation.Phase.COUNTDOWN, "the battle is in its countdown")
	h.check(overlay.battle_active and overlay.mode == ControlOverlay.Mode.FULL, "the sheet is up during the countdown")
	h.check(overlay.panel_at(0).visible and not overlay.panel_at(1).visible, "only the human seat (white, left) has a panel; the AI seat shows nothing")
	h.eq(_values(overlay, 0)["Ability"], "R (Royal Fury)", "the arena passed the queen's ability name")
	h.eq(_values(overlay, 0)["Light"], "LMB / F", "the mouse is live for a lone kb1 seat")
	h.check(overlay.get_parent() == arena and overlay.layer > arena.hud.layer, "it is a CanvasLayer above the HUD")
	arena.sim.defender().health.apply_damage(100000)
	for _i in 400:
		if arena.sim.phase == CombatSimulation.Phase.FINISHED:
			break
		arena.sim.step_tick()
	h.check(arena.sim.phase == CombatSimulation.Phase.FINISHED and not arena.sim.result.is_empty(), "the fight ended")
	h.check(overlay.finished and not overlay.get_child(0).visible, "the result screen hides the overlay")
	h.check(not overlay.handle_event(_key(KEY_F1)), "and the toggle is dead until the next battle")
	arena.start_battle(FighterRoster.build_request("q", "r", "w", "ov-pve-2", 12, 0))
	h.check(overlay == arena.overlay and not overlay.finished and overlay.battle_active, "the next battle reuses the same overlay node")
	h.check(prefs.battles >= 2, "both battles were counted (%d)" % prefs.battles)
	_free_arena(tree, arena)

	h.begin("overlay: hot-seat (two local humans, split screen) gives each player a panel inside their half")
	var hot := _arena(tree, {"player-white": {"type": "human", "scheme": "kb1"}, "player-black": {"type": "human", "scheme": "kb2"}}, 13, "ov-pvp", "n", "b")
	var ho: ControlOverlay = hot.overlay
	ho.instant = true
	await tree.process_frame
	await tree.process_frame
	var view := Vector2(tree.root.get_visible_rect().size)
	h.check(hot._split_layer != null, "split screen is active")
	h.check(ho.panel_at(0).visible and ho.panel_at(1).visible, "two panels")
	h.eq(_values(ho, 0)["Light"], "F", "P1 shares the keyboard (no mouse in hot-seat)")
	h.eq(_values(ho, 1)["Light"], "J", "P2's light is J")
	h.eq(_values(ho, 0)["Ability"], "R (Lunging Strike)", "white knight ability")
	h.eq(_values(ho, 1)["Ability"], "O (Blink)", "black bishop ability")
	h.check(_rect(ho, 0).end.x <= view.x * 0.5 and _rect(ho, 1).position.x >= view.x * 0.5, "each panel is inside its player's half of %s" % str(view))
	_free_arena(tree, hot)

	h.begin("overlay: AI vs AI shows nothing and does not count as a battle")
	var before := prefs.battles
	var demo := _arena(tree, {"player-white": {"type": "ai", "skill": 0.7}, "player-black": {"type": "ai", "skill": 0.6}}, 14, "ov-demo")
	await tree.process_frame
	h.check(not demo.overlay.panel_at(0).visible and not demo.overlay.panel_at(1).visible and not demo.overlay.battle_active, "no panels, inactive")
	h.eq(prefs.battles, before, "a demonstration does not use up the first-battles default")
	_free_arena(tree, demo)

	h.begin("overlay: an online (PRESENTATION) arena shows only the local seat")
	var online := _arena(tree, {}, 15, "ov-online", "q", "r", CombatArena.Mode.PRESENTATION, "player-black")
	await tree.process_frame
	var oo: ControlOverlay = online.overlay
	h.check(oo != null and oo.battle_active, "the presentation arena has an active overlay")
	h.check(oo.panel_at(1).visible and not oo.panel_at(0).visible, "only the local (black) seat, on the right")
	h.eq(_values(oo, 1)["Ability"], "R (Fortress Guard)", "its fighter's ability name (rook)")
	oo.instant = true
	h.check(oo.handle_event(_key(KEY_F1)) and oo.mode == ControlOverlay.Mode.OFF, "F1 relayed by the host (the arena viewport gets no input) toggles it")
	_free_arena(tree, online)
	prefs.enabled = true  # the F1 above was a real choice; start the next battle from "on" again
	var online_w := _arena(tree, {}, 16, "ov-online-w", "q", "r", CombatArena.Mode.PRESENTATION, "player-white")
	await tree.process_frame
	h.check(online_w.overlay.panel_at(0).visible and not online_w.overlay.panel_at(1).visible, "the local white seat gets the left panel only")
	_free_arena(tree, online_w)

	h.begin("overlay: a presentation-less (server style) arena builds no overlay")
	var headless: CombatArena = (load(ARENA) as PackedScene).instantiate()
	headless.presentation_enabled = false
	tree.root.add_child(headless)
	headless.start_battle(FighterRoster.build_request("n", "p", "w", "ov-headless", 17, 0))
	h.check(headless.overlay == null, "no overlay without presentation")
	_free_arena(tree, headless)

	ControlOverlayPrefs.set_shared(null)
	ControlBindings.set_shared(old_bindings)


# ---- the simulation never notices the overlay ---------------------------------------------------------------------------------
static func _digest(sim: CombatSimulation) -> Array:
	var out: Array = [sim.server_tick, sim.result.get("winnerPlayerId", ""), sim.result.get("reason", "")]
	for entry in sim.snapshot(false)["fighters"]:
		out.append([entry["hp"], entry["state"], entry["stateTicks"], snappedf(float(entry["position"]["x"]), 0.0001), snappedf(float(entry["position"]["z"]), 0.0001), snappedf(float(entry["stamina"]), 0.0001)])
	return out


static func _run_fight(tree: SceneTree, toggling: bool, id: String) -> Array:
	var arena := _arena(tree, {"player-white": {"type": "human", "scheme": "kb1"}, "player-black": {"type": "ai", "skill": 0.8}}, 777, id, "n", "q")
	arena.set_physics_process(false)  # driven by hand below: identical tick sequence in both runs
	var overlay: ControlOverlay = arena.overlay
	overlay.instant = false
	var trace: Array = []
	for t in 900:
		if toggling:
			if t % 37 == 0:
				overlay.handle_event(_key(KEY_F1))
			if t % 53 == 0:
				overlay.handle_event(_pad(JOY_BUTTON_BACK, 1))
			overlay._process(1.0 / 60.0)
		arena._physics_process(1.0 / 60.0)
		if t % 150 == 0:
			trace.append(_digest(arena.sim))
	trace.append(_digest(arena.sim))
	_free_arena(tree, arena)
	return trace


static func _simulation_unaffected(h, tree: SceneTree) -> void:
	h.begin("overlay: toggling the overlay mid-fight does not change the simulation (seeded fight, identical digests)")
	var prefs := _prefs()
	ControlOverlayPrefs.set_shared(prefs)
	var old := ControlBindings.shared()
	ControlBindings.set_shared(ControlBindings.new())
	var plain := _run_fight(tree, false, "ov-sim-a")
	var toggled := _run_fight(tree, true, "ov-sim-b")
	h.eq(plain.size(), toggled.size(), "same number of samples")
	h.check(plain == toggled, "the sampled simulation state is identical with and without toggling")
	h.check(plain.size() > 3 and (plain[plain.size() - 1][2] != "" or int(plain[plain.size() - 1][0]) >= 900), "the fight actually ran (tick %s)" % str(plain[plain.size() - 1][0]))
	ControlBindings.set_shared(old)
	ControlOverlayPrefs.set_shared(null)


# ---- the arena mounted in the pit world (local Battle Chess) --------------------------------------------------------------
static func _pit_world(h, tree: SceneTree) -> void:
	h.begin("overlay: in the pit-world board panel it stays hidden during the drop, shows in COMBAT for both local seats, hides for the climb")
	var prefs := _prefs()
	prefs.chosen = true
	ControlOverlayPrefs.set_shared(prefs)
	var old := ControlBindings.shared()
	ControlBindings.set_shared(ControlBindings.new())
	var fx: Dictionary = await WorldTests._fixture(tree)
	var world: BattleWorld = fx["world"]
	var pit := world.pit
	pit.require_arena = true
	var request: Dictionary = WorldTests._capture_request(fx)
	var arena: CombatArena = (load(ARENA) as PackedScene).instantiate()
	# What BattleCombatAdapter configures for local Battle Chess: both seats human (White kb1, Black kb2 when no pads).
	arena.configure_seats({request.attacker.playerId: {"type": "human", "scheme": "kb1"}, request.defender.playerId: {"type": "human", "scheme": "kb2"}})
	h.check(pit.begin(request), "the capture begins")
	arena.battle_finished.connect(func(result: Dictionary): pit.present_result(result))
	world.chamber.arena_mount.add_child(arena)
	h.check(arena.start_battle(request)["ok"], "the embedded arena starts")
	pit.attach_arena(arena)
	var ov: ControlOverlay = arena.overlay
	if not h.check(ov != null and ov.battle_active, "the embedded arena built its overlay"):
		await WorldTests._free(fx, tree)
		return
	ov.instant = true
	h.check(not ov.visible, "hidden before COMBAT (the pit hides every arena CanvasLayer during the drop)")
	h.check(not ov.handle_event(_key(KEY_F1)), "and F1 does nothing while it is hidden")
	h.check(WorldTests._run_to(world, PitSequence.Phase.COMBAT, 0.2), "the sequence reaches COMBAT")
	await tree.process_frame
	await tree.process_frame
	var vp_size := Vector2(ov.get_viewport().get_visible_rect().size)
	h.check(ov.visible and ov.panel_at(0).visible and ov.panel_at(1).visible, "shown in COMBAT: one panel per local human seat")
	h.check(ov.get_viewport() == arena.hud.get_viewport(), "it lives in the same viewport as the HUD (the board panel, %s)" % str(vp_size))
	h.check(_rect(ov, 0).end.x <= vp_size.x * 0.5 and _rect(ov, 1).position.x >= vp_size.x * 0.5, "each panel is inside its half of the board panel")
	h.check(Rect2(Vector2.ZERO, vp_size).encloses(_rect(ov, 0)) and Rect2(Vector2.ZERO, vp_size).encloses(_rect(ov, 1)), "and fully inside the panel")
	h.check(ov.handle_event(_key(KEY_F1)) and ov.mode == ControlOverlay.Mode.OFF, "F1 toggles it in COMBAT")
	ov.toggle()
	arena.sim.defender().health.apply_damage(100000)
	var guard := 0
	while pit.phase != PitSequence.Phase.CLIMB and guard < 3000:
		world.advance(1.0 / 60.0)
		await tree.process_frame
		guard += 1
	h.check(pit.phase == PitSequence.Phase.CLIMB, "the sequence reaches CLIMB")
	h.check(ov.finished and not ov.visible, "hidden after the result / during the climb")
	while not pit.is_idle() and guard < 6000:
		if pit.phase == PitSequence.Phase.RETURN and pit._return_ready_sent and is_instance_valid(arena) and arena.get_parent() != null:
			arena.stop_battle()
			arena.get_parent().remove_child(arena)
			arena.queue_free()
		world.advance(1.0 / 60.0)
		await tree.process_frame
		guard += 1
	h.check(pit.is_idle(), "the sequence finished")
	fx["game"].cancel_pending()
	await WorldTests._free(fx, tree)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ControlBindings.set_shared(old)
	ControlOverlayPrefs.set_shared(null)
