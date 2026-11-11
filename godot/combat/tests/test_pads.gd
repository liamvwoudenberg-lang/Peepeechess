extends RefCounted
## Gamepad / keyboard control layer. NO physical controller was available: every pad here is simulated with injected
## InputEventJoypadButton / InputEventJoypadMotion events (each carrying a `device` id) through Input.parse_input_event,
## i.e. the same path real hardware events take after SDL/Godot's mapping. What this proves: the logic (mapping,
## dead zone and trigger maths, per-device isolation, hot-plug, rebinding, persistence, board cursor, menu focus).
## What it cannot prove: real DS4 hardware, drivers (DS4Windows / Steam Input), Bluetooth, latency, stick feel.

const ARENA := "res://combat/arena.tscn"
const S := CombatConstants.State
const TMP_DIR := "user://pads_test"


static func run(h, tree: SceneTree) -> void:
	_pad_math(h)
	_glyphs(h)
	_bindings_defaults(h)
	_bindings_edit_and_conflicts(h)
	_bindings_persistence(h)
	_assignment(h)
	_hints(h)
	await _two_pad_fight(h, tree)
	await _hotplug_mid_fight(h, tree)
	await _custom_bindings_fight(h, tree)
	await _keyboard_fight(h, tree)
	await load("res://combat/tests/test_pads_ui.gd").run(h, tree)  # (load, not preload: that file preloads this one)


# ---- helpers ------------------------------------------------------------------------------------------
static func btn(device: int, button: int, pressed: bool = true) -> void:
	var e := InputEventJoypadButton.new()
	e.device = device
	e.button_index = button as JoyButton
	e.pressed = pressed
	Input.parse_input_event(e)


static func axis(device: int, axis_id: int, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = device
	e.axis = axis_id as JoyAxis
	e.axis_value = value
	Input.parse_input_event(e)


static func tap(device: int, button: int, tree: SceneTree) -> void:
	btn(device, button, true)
	Input.flush_buffered_events()
	btn(device, button, false)
	Input.flush_buffered_events()


static func key(code: int, pressed: bool = true) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code as Key
	e.keycode = code as Key
	e.pressed = pressed
	Input.parse_input_event(e)


static func ticks(tree: SceneTree, n: int) -> void:
	Input.flush_buffered_events()
	for _i in n:
		await tree.physics_frame


static func release_all(devices: Array = [0, 1]) -> void:
	for d in devices:
		for b in range(0, 21):
			btn(d, b, false)
		for a in range(0, 6):
			axis(d, a, 0.0)
	Input.flush_buffered_events()


static func fake_assignment(bindings: ControlBindings, pads: Array) -> InputAssignment:
	var a := InputAssignment.new(bindings)
	var holder := {"pads": pads}
	a.connected_provider = func(): return holder["pads"]
	a.set_meta("holder", holder)
	return a


static func set_pads(a: InputAssignment, pads: Array) -> void:
	a.get_meta("holder")["pads"] = pads


# ---- pure maths -----------------------------------------------------------------------------------------
static func _pad_math(h) -> void:
	h.begin("pad maths: radial dead zone with rescaling, outer zone, response curve, direction preserved")
	h.eq(PadMath.radial(Vector2(0.1, 0.1)), Vector2.ZERO, "inside the dead zone (len 0.14 < 0.18) -> exactly zero")
	h.eq(PadMath.radial(Vector2(0.18, 0.0)), Vector2.ZERO, "exactly on the dead zone edge -> zero")
	h.near(PadMath.radial(Vector2(0.18 + 0.78 * 0.5, 0.0)).x, 0.5, 0.001, "midway between inner (0.18) and outer (0.96) -> 0.5 (linear)")
	h.near(PadMath.radial(Vector2(0.96, 0.0)).length(), 1.0, 0.0001, "at the outer zone -> full deflection")
	h.near(PadMath.radial(Vector2(0.7, 0.7)).length(), 1.0, 0.0001, "a diagonal at |v| = 0.99 (a real stick's gate) reaches 1.0")
	h.near(PadMath.radial(Vector2(1.0, 1.0)).length(), 1.0, 0.0001, "never exceeds 1 (corner of the square raw range)")
	var d := PadMath.radial(Vector2(0.3, 0.6))
	h.near(d.angle(), Vector2(0.3, 0.6).angle(), 0.0001, "the direction of a deflected stick is preserved exactly")
	h.near(PadMath.radial(Vector2(0.5, 0.0), 0.2, 0.96, 2.0).x, pow((0.5 - 0.2) / 0.76, 2.0), 0.0001, "response exponent 2 shapes the ramp")
	h.check(PadMath.radial(Vector2(0.17, 0.0), 0.05, 0.96).length() > 0.0, "a smaller configured dead zone lets small deflections through")
	h.check(PadMath.radial(Vector2(0.5, 0.0), 2.0, -1.0).length() <= 1.0, "absurd settings are clamped, never produce > 1 or NaN")
	h.eq(PadMath.trigger_value(-1.0), 0.0, "a trigger resting at -1 (some drivers) reads as not pressed")
	h.eq(PadMath.trigger_value(1.4), 1.0, "a trigger is clamped to 1")

	h.begin("trigger hysteresis: press above 0.5, release below 0.35, no chatter in between")
	var t := PadMath.Schmitt.new()
	var edges := 0
	var seq := [0.0, 0.3, 0.49, 0.5, 0.51, 0.45, 0.40, 0.36, 0.5, 0.49, 0.34, 0.6, 0.2]
	var held_log: Array = []
	for v in seq:
		if t.update(v):
			edges += 1
		held_log.append(t.held)
	h.eq(held_log, [false, false, false, false, true, true, true, true, true, true, false, true, false], "held state follows the hysteresis band exactly")
	h.eq(edges, 2, "exactly two press edges in the sequence (0.51 and 0.6), none from wobbling in the band")
	var t2 := PadMath.Schmitt.new(0.5, 0.9)
	h.check(t2.release < t2.press, "a release threshold above the press threshold is repaired")


static func _glyphs(h) -> void:
	h.begin("glyphs: family detection from joy names / GUID / vendor id")
	var F := ControllerGlyphs.Family
	for name in ["PS4 Controller", "Sony DualSense", "DualSense Wireless Controller", "Wireless Controller", "DUALSHOCK 4 Wireless Controller", "PS5 Controller", "Sony Interactive Entertainment Wireless Controller"]:
		h.eq(ControllerGlyphs.family_from_name(name), F.PLAYSTATION, "'%s' is PlayStation" % name)
	for name in ["XInput Gamepad", "Xbox 360 Controller", "Xbox One Controller", "Xbox Series Controller", "Xbox Wireless Controller", "Microsoft X-Box 360 pad"]:
		h.eq(ControllerGlyphs.family_from_name(name), F.XBOX, "'%s' is Xbox" % name)
	for name in ["Nintendo Switch Pro Controller", "Switch Pro Controller", "Pro Controller", "Joy-Con (L)"]:
		h.eq(ControllerGlyphs.family_from_name(name), F.SWITCH, "'%s' is Switch" % name)
	h.eq(ControllerGlyphs.family_from_name("Generic USB Joystick"), F.GENERIC, "an unknown pad is generic")
	h.eq(ControllerGlyphs.family_from_name(""), F.GENERIC, "an empty name is generic")
	# Real SDL GUIDs: DS4 v2 (054c:09cc) and Xbox 360 (045e:028e), Switch Pro (057e:2009).
	h.eq(ControllerGlyphs.vendor_from_guid("030000004c050000cc09000000006800"), 0x054c, "vendor parsed from a DS4 GUID")
	h.eq(ControllerGlyphs.vendor_from_guid("030000005e0400008e02000000007200"), 0x045e, "vendor parsed from an Xbox 360 GUID")
	h.eq(ControllerGlyphs.vendor_from_guid("nonsense"), 0, "a malformed GUID yields 0")
	h.eq(ControllerGlyphs.family_from_name("Controller", "030000004c050000cc09000000006800"), F.PLAYSTATION, "unknown name + Sony GUID -> PlayStation")
	h.eq(ControllerGlyphs.family_from_name("Controller", "", 0x057e), F.SWITCH, "unknown name + Nintendo vendor id -> Switch")
	h.eq(ControllerGlyphs.family_from_name("XInput Gamepad", "030000004c050000cc09000000006800"), F.XBOX, "DS4Windows (XInput name, Sony GUID) is labelled as the OS shows it: Xbox")

	h.begin("glyphs: button labels per family (SDL positions: A bottom, B right, X left, Y top)")
	var ps := {JOY_BUTTON_A: "Cross", JOY_BUTTON_B: "Circle", JOY_BUTTON_X: "Square", JOY_BUTTON_Y: "Triangle", JOY_BUTTON_LEFT_SHOULDER: "L1",
		JOY_BUTTON_RIGHT_SHOULDER: "R1", JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3", JOY_BUTTON_START: "Options", JOY_BUTTON_BACK: "Share"}
	for b in ps:
		h.eq(ControllerGlyphs.button_label(b, F.PLAYSTATION), ps[b], "PlayStation button %d" % b)
	var xb := {JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y", JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
		JOY_BUTTON_LEFT_STICK: "LS", JOY_BUTTON_START: "Menu", JOY_BUTTON_BACK: "View"}
	for b in xb:
		h.eq(ControllerGlyphs.button_label(b, F.XBOX), xb[b], "Xbox button %d" % b)
	h.eq(ControllerGlyphs.axis_label(JOY_AXIS_TRIGGER_LEFT, F.PLAYSTATION), "L2", "PlayStation left trigger")
	h.eq(ControllerGlyphs.axis_label(JOY_AXIS_TRIGGER_RIGHT, F.PLAYSTATION), "R2", "PlayStation right trigger")
	h.eq(ControllerGlyphs.axis_label(JOY_AXIS_TRIGGER_LEFT, F.XBOX), "LT", "Xbox left trigger")
	h.eq(ControllerGlyphs.button_label(JOY_BUTTON_A, F.SWITCH), "B", "Switch prints B on the bottom button")
	h.eq(ControllerGlyphs.button_label(99, F.PLAYSTATION), "Button 99", "an unknown button gets a neutral name")
	h.eq(ControllerGlyphs.input_label({}, F.XBOX), "Unbound", "an unbound action")

	h.begin("glyphs: a device registered by name resolves its family (the path hints and menus use)")
	ControllerGlyphs.fake_devices = {0: {"name": "PS4 Controller", "guid": "030000004c050000cc09000000006800"}, 1: {"name": "XInput Gamepad"}}
	h.eq(ControllerGlyphs.family_of_device(0), F.PLAYSTATION, "device 0 (PS4 Controller)")
	h.eq(ControllerGlyphs.family_of_device(1), F.XBOX, "device 1 (XInput Gamepad)")
	h.eq(ControllerGlyphs.device_label(0), "PS4 Controller", "its label is the driver's name")
	ControllerGlyphs.fake_devices = {}


# ---- bindings --------------------------------------------------------------------------------------------
static func _bindings_defaults(h) -> void:
	h.begin("bindings: defaults reproduce the constants LocalInputSource used before (keyboard + pad)")
	var b := ControlBindings.new()
	var old_kb1 := {"up": KEY_W, "down": KEY_S, "left": KEY_A, "right": KEY_D, "sprint": KEY_SHIFT, "light": KEY_F, "heavy": KEY_G,
		"dodge": KEY_SPACE, "block": KEY_Q, "parry": KEY_E, "ability": KEY_R, "lock": KEY_TAB, "orbit_l": KEY_Z, "orbit_r": KEY_X}
	var old_kb2 := {"up": KEY_UP, "down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT, "sprint": KEY_CTRL, "light": KEY_J, "heavy": KEY_K,
		"dodge": KEY_L, "block": KEY_U, "parry": KEY_I, "ability": KEY_O, "lock": KEY_P, "orbit_l": KEY_COMMA, "orbit_r": KEY_PERIOD}
	h.eq(b.keys_for("kb1"), old_kb1, "kb1 = WASD / Shift / F G / Space / Q E / R / Tab / Z X")
	h.eq(b.keys_for("kb2"), old_kb2, "kb2 = arrows / Ctrl / J K / L / U I / O / P / , .")
	h.eq(b.pad_input("light"), {"type": "button", "index": JOY_BUTTON_X}, "Square = light")
	h.eq(b.pad_input("heavy"), {"type": "button", "index": JOY_BUTTON_Y}, "Triangle = heavy")
	h.eq(b.pad_input("dodge"), {"type": "button", "index": JOY_BUTTON_A}, "Cross = dodge")
	h.eq(b.pad_input("ability"), {"type": "button", "index": JOY_BUTTON_B}, "Circle = special")
	h.eq(b.pad_input("block"), {"type": "button", "index": JOY_BUTTON_LEFT_SHOULDER}, "L1 = block")
	h.eq(b.pad_input("parry"), {"type": "button", "index": JOY_BUTTON_RIGHT_SHOULDER}, "R1 = parry")
	h.eq(b.pad_input("lock"), {"type": "button", "index": JOY_BUTTON_LEFT_STICK}, "L3 = lock-on")
	h.eq(b.pad_input("sprint"), {"type": "axis", "index": JOY_AXIS_TRIGGER_LEFT}, "L2 = sprint")
	h.eq(b.pad_input("heavy2"), {"type": "axis", "index": JOY_AXIS_TRIGGER_RIGHT}, "R2 = heavy alias")
	h.eq(b.pad_setting("deadzone"), 0.18, "default dead zone is the old 0.18")
	h.check(b.find_conflicts().is_empty(), "the default map has no conflicts")
	h.check(b.is_default(), "is_default() is true for a fresh instance")
	h.eq(LocalInputSource.SCHEMES, ControlBindings.DEFAULT_KEYS, "LocalInputSource.SCHEMES still exposes the defaults")


static func _bindings_edit_and_conflicts(h) -> void:
	h.begin("bindings: editing, swap / reject / allow conflict policies, reserved keys, unbind")
	var b := ControlBindings.new()
	var r := b.set_key("kb1", "light", KEY_H)
	h.check(r["ok"] and r["conflicts"].is_empty() and not r["swapped"], "a free key binds cleanly")
	h.eq(b.key_for("kb1", "light"), KEY_H, "light is now H")
	r = b.set_key("kb1", "heavy", KEY_H)
	h.check(r["ok"] and r["swapped"], "binding an in-use key in the same set swaps")
	h.eq(b.key_for("kb1", "heavy"), KEY_H, "heavy took H")
	h.eq(b.key_for("kb1", "light"), KEY_G, "light received heavy's old key G")
	h.check(b.find_conflicts().is_empty(), "a swap leaves no duplicate")
	r = b.set_key("kb1", "dodge", KEY_J)  # J belongs to kb2/light
	h.check(not r["ok"] and r["conflicts"].size() == 1 and r["conflicts"][0]["scheme"] == "kb2", "a key used by the OTHER player's set is refused")
	h.eq(b.key_for("kb1", "dodge"), KEY_SPACE, "and nothing changed")
	r = b.set_key("kb1", "dodge", KEY_ESCAPE)
	h.check(not r["ok"], "Escape is reserved for menus")
	r = b.set_key("kb1", "dodge", KEY_F11)
	h.check(not r["ok"], "F11 is reserved (fullscreen)")
	r = b.set_key("kb1", "dodge", KEY_V, "reject")
	h.check(r["ok"], "reject policy still binds a free key")
	r = b.set_key("kb1", "parry", KEY_V, "reject")
	h.check(not r["ok"] and b.key_for("kb1", "parry") == KEY_E, "reject policy leaves a clash untouched")
	r = b.set_key("kb1", "parry", KEY_V, "allow")
	h.check(r["ok"] and r["conflicts"].size() == 1, "allow policy binds and reports the clash")
	h.eq(b.find_conflicts().size(), 1, "find_conflicts() reports exactly that duplicate")
	h.check(not b.set_key("kb3", "light", KEY_A)["ok"] and not b.set_key("kb1", "fly", KEY_A)["ok"], "unknown scheme / action refused")
	b.reset_defaults("kb1")
	h.eq(b.keys_for("kb1"), ControlBindings.DEFAULT_KEYS["kb1"], "reset_defaults('kb1') restores kb1")
	h.check(b.find_conflicts().is_empty(), "and clears the duplicate")

	h.begin("bindings: pad rebinding, swap, unbind, reserved Options, bindable axes only")
	b = ControlBindings.new()
	var square := {"type": "button", "index": JOY_BUTTON_X}
	r = b.set_pad("heavy", square)
	h.check(r["ok"] and r["swapped"], "Square is taken by light -> swap")
	h.eq(b.pad_input("heavy"), square, "heavy is Square")
	h.eq(b.pad_input("light"), {"type": "button", "index": JOY_BUTTON_Y}, "light received Triangle")
	h.check(not b.set_pad("light", {"type": "button", "index": JOY_BUTTON_START})["ok"], "Options/Start cannot be bound (it is the pause button)")
	h.check(not b.set_pad("light", {"type": "axis", "index": JOY_AXIS_LEFT_X})["ok"], "a stick axis cannot be bound")
	h.check(b.set_pad("light", {"type": "button", "index": JOY_BUTTON_TOUCHPAD})["ok"], "the DS4 touchpad click can be bound")
	h.check(b.set_pad("heavy2", {})["ok"] and b.pad_input("heavy2").is_empty(), "an action can be unbound")
	h.eq(ControlBindings.event_to_pad(_pad_button_event(0, JOY_BUTTON_Y)), {"type": "button", "index": JOY_BUTTON_Y}, "a captured pad button press")
	h.eq(ControlBindings.event_to_pad(_pad_button_event(0, JOY_BUTTON_START)), {}, "Options is never captured")
	var trig := InputEventJoypadMotion.new()
	trig.axis = JOY_AXIS_TRIGGER_RIGHT
	trig.axis_value = 0.9
	h.eq(ControlBindings.event_to_pad(trig), {"type": "axis", "index": JOY_AXIS_TRIGGER_RIGHT}, "a trigger pushed past 0.6 is captured")
	trig.axis_value = 0.3
	h.eq(ControlBindings.event_to_pad(trig), {}, "a light trigger touch is not")
	var stick := InputEventJoypadMotion.new()
	stick.axis = JOY_AXIS_LEFT_X
	stick.axis_value = 1.0
	h.eq(ControlBindings.event_to_pad(stick), {}, "a stick push is never captured")
	h.eq(ControlBindings.event_to_pad(_pad_button_event(0, JOY_BUTTON_A, false)), {}, "a release is not captured")

	h.begin("bindings: pad settings are validated and clamped")
	b = ControlBindings.new()
	h.check(b.set_pad_setting("deadzone", 0.3) and b.pad_setting("deadzone") == 0.3, "dead zone set")
	h.check(b.set_pad_setting("deadzone", 5.0) and b.pad_setting("deadzone") == 0.6, "out-of-range values are clamped (max 0.6)")
	h.check(not b.set_pad_setting("deadzone", "wide"), "a non-number is refused")
	h.check(not b.set_pad_setting("deadzone", NAN), "NaN is refused")
	h.check(not b.set_pad_setting("nonsense", 1.0), "an unknown setting is refused")
	h.check(b.set_pad_setting("invert_look_y", true) and b.pad_setting("invert_look_y") == true, "invert flag")
	h.check(not b.set_pad_setting("invert_look_y", 1), "a bool setting refuses a number")
	b.set_pad_setting("trigger_press", 0.4)
	b.set_pad_setting("trigger_release", 0.6)
	h.check(float(b.pad_setting("trigger_release")) <= float(b.pad_setting("trigger_press")) - 0.05, "the release threshold is always below the press threshold")
	h.check(b.set_seat_pref(0, "pad2") and b.seat_pref(0) == "pad2" and not b.set_seat_pref(0, "pad9") and not b.set_seat_pref(2, "kb1"), "seat preference validation")


static func _pad_button_event(device: int, button: int, pressed: bool = true) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.device = device
	e.button_index = button as JoyButton
	e.pressed = pressed
	return e


static func _bindings_persistence(h) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP_DIR))
	var path := TMP_DIR + "/controls.json"
	_rm(path)
	_rm(path + ".corrupt")
	h.begin("bindings persistence: save/load round trip, versioned file, missing file = defaults")
	var b := ControlBindings.new()
	h.check(not b.load_file(path) and b.is_default() and b.last_error.is_empty(), "no file -> defaults, no error")
	b.set_key("kb1", "light", KEY_H)
	b.set_key("kb2", "sprint", KEY_ALT)
	b.set_pad("light", {"type": "button", "index": JOY_BUTTON_TOUCHPAD})
	b.set_pad("heavy2", {})
	b.set_pad("sprint", {"type": "axis", "index": JOY_AXIS_TRIGGER_RIGHT})
	b.set_pad_setting("look_sensitivity", 1.75)
	b.set_pad_setting("invert_look_y", true)
	b.set_pad_setting("deadzone", 0.25)
	b.set_seat_pref(1, "pad1")
	h.eq(b.save_file(path), OK, "saved")
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	h.check(raw is Dictionary and int(raw["version"]) == 1 and raw.has("keyboard") and raw.has("pad") and raw.has("pad_settings"), "the file is versioned JSON with keyboard / pad / pad_settings")
	var c := ControlBindings.new()
	h.check(c.load_file(path), "loaded")
	h.eq(c.keys, b.keys, "keyboard bindings survived")
	h.eq(c.pad, b.pad, "pad bindings survived (including the unbound alias and the touchpad)")
	h.eq(c.pad_settings, b.pad_settings, "pad settings survived")
	h.eq(c.seat_pref(1), "pad1", "seat preference survived")
	h.check(c.warnings.is_empty() and c.last_error.is_empty(), "no warnings on a clean file")

	h.begin("bindings persistence: corrupt / hostile files never crash and never leave a broken map")
	for case in [["not json at all {{{", "garbage"], ["[1,2,3]", "array"], ["{\"version\": 99}", "future version"], ["{}", "no version"], ["null", "null"], ["{\"version\": \"1\"}", "string version"]]:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(case[0])
		f.close()
		var d := ControlBindings.new()
		d.set_key("kb1", "light", KEY_H)  # a dirty instance must be reset to defaults by a failed load
		h.check(not d.load_file(path), "%s: rejected" % case[1])
		h.check(d.is_default(), "%s: defaults loaded" % case[1])
		h.check(not d.last_error.is_empty(), "%s: the reason is reported" % case[1])
		h.check(FileAccess.file_exists(path + ".corrupt") and not FileAccess.file_exists(path), "%s: the bad file was moved to .corrupt" % case[1])
		_rm(path + ".corrupt")
	h.check(ControlBindings.new().save_file(path) == OK, "a clean save after a corrupt load works")

	h.begin("bindings persistence: partially invalid entries fall back per entry; duplicates restore the section")
	var partial := {"version": 1, "keyboard": {"kb1": {"light": KEY_H, "heavy": "banana", "dodge": -5, "parry": 4194305, "bogus": 3, "ability": 1.5}, "kb2": 7},
		"pad": {"light": "button:8", "heavy": "button:999", "dodge": 12, "sprint": "axis:0", "ability": "button:6"},
		"pad_settings": {"deadzone": 99, "response": "x", "invert_look_x": "yes", "look_sensitivity": 2.0}, "assignment": {"p1": "pad2", "p2": "nope"}}
	var e := ControlBindings.new()
	h.check(e.from_dict(partial), "an understood file loads")
	h.eq(e.key_for("kb1", "light"), KEY_H, "valid key kept")
	h.eq(e.key_for("kb1", "heavy"), KEY_G, "string key -> default")
	h.eq(e.key_for("kb1", "dodge"), KEY_SPACE, "negative key -> default")
	h.eq(e.key_for("kb1", "parry"), KEY_E, "reserved key (Escape) in a file -> default")
	h.eq(e.key_for("kb1", "ability"), KEY_R, "fractional key code -> default")
	h.eq(e.keys_for("kb2"), ControlBindings.DEFAULT_KEYS["kb2"], "a non-object section -> defaults")
	h.eq(e.pad_input("light"), {"type": "button", "index": 8}, "valid pad token kept (R3)")
	h.eq(e.pad_input("heavy"), ControlBindings.DEFAULT_PAD["heavy"], "out-of-range button -> default")
	h.eq(e.pad_input("dodge"), ControlBindings.DEFAULT_PAD["dodge"], "non-string token -> default")
	h.eq(e.pad_input("sprint"), ControlBindings.DEFAULT_PAD["sprint"], "a stick axis cannot be a binding -> default")
	h.eq(e.pad_input("ability"), ControlBindings.DEFAULT_PAD["ability"], "Options/Start (button 6) cannot be a binding -> default")
	h.eq(e.pad_setting("deadzone"), 0.6, "an absurd dead zone is clamped")
	h.eq(e.pad_setting("response"), 1.0, "a non-number setting -> default")
	h.eq(e.pad_setting("invert_look_x"), false, "a non-bool flag -> default")
	h.eq(e.pad_setting("look_sensitivity"), 2.0, "a valid setting kept")
	h.eq(e.seat_pref(0), "pad2", "valid seat preference kept")
	h.eq(e.seat_pref(1), "auto", "invalid seat preference -> auto")
	h.check(not e.warnings.is_empty(), "the replaced entries are reported in warnings")
	var dup := {"version": 1, "keyboard": {"kb1": {"light": KEY_H, "heavy": KEY_H}}, "pad": {"light": "button:0", "heavy": "button:0"}}
	var g := ControlBindings.new()
	h.check(g.from_dict(dup), "a file with duplicates still loads")
	h.eq(g.keys_for("kb1"), ControlBindings.DEFAULT_KEYS["kb1"], "kb1 with a duplicate key is restored to defaults")
	h.eq(g.pad, ControlBindings.DEFAULT_PAD, "a pad map with a duplicate button is restored to defaults")
	h.check(g.find_conflicts().is_empty(), "the result is conflict free")
	var cross := {"version": 1, "keyboard": {"kb1": {}, "kb2": {"light": KEY_F}}}  # kb2 steals kb1's default F
	g = ControlBindings.new()
	g.from_dict(cross)
	h.check(g.find_conflicts().is_empty(), "a cross-player clash is repaired as well")
	var big := FileAccess.open(path, FileAccess.WRITE)
	big.store_string("{\"version\":1,\"pad\":\"" + "x".repeat(70000) + "\"}")
	big.close()
	g = ControlBindings.new()
	h.check(not g.load_file(path) and g.is_default(), "an oversized file is refused")
	_rm(path + ".corrupt")
	_rm(path)

	h.begin("bindings persistence: shared() instance can be replaced (tests / reload)")
	var mine := ControlBindings.new()
	mine.set_key("kb1", "light", KEY_H)
	ControlBindings.set_shared(mine)
	h.eq(ControlBindings.shared().key_for("kb1", "light"), KEY_H, "shared() returns the injected instance")
	ControlBindings.set_shared(null)


static func _rm(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# ---- assignment ---------------------------------------------------------------------------------------------
static func _assignment(h) -> void:
	var b := ControlBindings.new()
	h.begin("assignment: no pads -> kb1 / kb2 (the pre-existing behaviour)")
	var a := fake_assignment(b, [])
	h.eq(a.scheme_for_slot(0), "kb1", "P1 keyboard 1")
	h.eq(a.scheme_for_slot(1), "kb2", "P2 keyboard 2")
	h.eq(a.scheme_for_color("w"), "kb1", "white = P1")
	h.eq(a.scheme_for_color("b"), "kb2", "black = P2")
	h.check(a.is_slot_ready(0) and a.is_slot_ready(1), "keyboard seats are always ready")

	h.begin("assignment: pads are assigned deterministically by ascending device id")
	set_pads(a, [3, 1])
	h.eq(a.connected_pads(), [1, 3] as Array[int], "pads are sorted")
	h.eq(a.scheme_for_slot(0), "pad1", "lowest id -> P1")
	h.eq(a.scheme_for_slot(1), "pad3", "next -> P2")
	set_pads(a, [5])
	h.eq(a.scheme_for_slot(0), "pad5", "one pad -> P1")
	h.eq(a.scheme_for_slot(1), "kb2", "P2 keeps the keyboard")
	set_pads(a, [0, 1, 2])
	h.eq([a.scheme_for_slot(0), a.scheme_for_slot(1)], ["pad0", "pad1"], "a third pad is ignored")
	h.eq(a.device_for_slot(0), 0, "device_for_slot")
	h.eq(a.device_for_slot(1), 1, "device_for_slot 2")
	set_pads(a, [])
	h.eq(a.device_for_slot(0), -1, "no pad -> -1")

	h.begin("assignment: seat preferences (keyboard for P1, pad for P2, ordinal pads)")
	set_pads(a, [4, 7])
	b.set_seat_pref(0, "kb1")
	h.eq([a.scheme_for_slot(0), a.scheme_for_slot(1)], ["kb1", "pad4"], "P1 forced to kb1 -> the first free pad goes to P2")
	b.set_seat_pref(0, "pad2")
	b.set_seat_pref(1, "pad1")
	h.eq([a.scheme_for_slot(0), a.scheme_for_slot(1)], ["pad7", "pad4"], "swapped ordinals")
	b.set_seat_pref(0, "pad1")
	b.set_seat_pref(1, "pad1")
	h.eq([a.scheme_for_slot(0), a.scheme_for_slot(1)], ["pad4", "pad7"], "both asking for the same pad: P1 wins, P2 gets the next")
	b.set_seat_pref(0, "kb1")
	b.set_seat_pref(1, "kb1")
	h.eq([a.scheme_for_slot(0), a.scheme_for_slot(1)], ["kb1", "pad4"], "both asking for kb1: P2 falls to a free pad")
	set_pads(a, [])
	h.eq([a.scheme_for_slot(0), a.scheme_for_slot(1)], ["kb1", "kb2"], "both kb1, no pads: P2 takes kb2")
	b.reset_defaults("all")

	h.begin("assignment: 'press any button to join' (two pads, then keyboard + pad, partial)")
	set_pads(a, [0, 1, 2])
	var joined: Array = []
	a.join_progress.connect(func(slot, scheme): joined.append([slot, scheme]))
	var done := [false]
	a.join_completed.connect(func(): done[0] = true)
	a.begin_join()
	h.check(a.joining, "joining")
	h.check(not a.handle_join_event(_pad_button_event(0, JOY_BUTTON_START)), "Options does not join")
	h.check(not a.handle_join_event(_pad_button_event(9, JOY_BUTTON_A)), "a pad that is not connected does not join")
	h.check(a.handle_join_event(_pad_button_event(2, JOY_BUTTON_B)), "the first press (device 2, Circle) joins")
	h.eq(a.scheme_for_slot(0), "pad2", "device 2 is Player 1 although it is not the lowest id")
	h.check(not a.handle_join_event(_pad_button_event(2, JOY_BUTTON_A)), "a second press by the same pad is not a join")
	h.eq(a.joined_count(), 1, "one joined")
	h.check(not done[0], "not complete")
	h.check(a.handle_join_event(_pad_button_event(0, JOY_BUTTON_X)), "device 0 joins")
	h.eq(a.scheme_for_slot(1), "pad0", "device 0 is Player 2")
	h.check(done[0] and not a.joining, "join_completed fired and joining ended")
	h.eq(joined, [[0, "pad2"], [1, "pad0"]], "join_progress reported each seat in order")
	h.check(not a.handle_join_event(_pad_button_event(1, JOY_BUTTON_A)), "a late press is ignored once complete")
	a.cancel_join()
	h.eq([a.scheme_for_slot(0), a.scheme_for_slot(1)], ["pad0", "pad1"], "cancel_join clears the claims -> automatic again")
	a.begin_join()
	var k := InputEventKey.new()
	k.physical_keycode = KEY_UP
	k.pressed = true
	h.check(a.handle_join_event(k), "an arrow key joins as keyboard 2 (first press = Player 1)")
	h.eq(a.scheme_for_slot(0), "kb2", "P1 on keyboard 2")
	h.check(a.handle_join_event(_pad_button_event(1, JOY_BUTTON_A)), "a pad joins as Player 2")
	h.eq(a.scheme_for_slot(1), "pad1", "P2 on pad 1")
	var k2 := InputEventKey.new()
	k2.physical_keycode = KEY_ENTER
	k2.pressed = true
	a.begin_join()
	h.check(not a.handle_join_event(k2), "Enter is not part of any combat set: it does not join")
	a.cancel_join()

	h.begin("assignment: disconnect / reconnect keeps the seat (lock), re-assignment to another pad")
	set_pads(a, [0, 1])
	a.lock_for_match()
	var events: Array = []
	a.device_lost.connect(func(slot, dev): events.append(["lost", slot, dev]))
	a.device_restored.connect(func(slot, dev): events.append(["back", slot, dev]))
	set_pads(a, [1])
	a.on_connection_changed(0, false)
	h.eq(events, [["lost", 0, 0]], "P1's pad 0 vanished -> device_lost(0, 0)")
	h.eq(a.scheme_for_slot(0), "pad0", "the seat STAYS on pad0 (it does not silently jump to the keyboard)")
	h.check(a.is_lost(0) and not a.is_slot_ready(0) and not a.is_lost(1) and a.is_slot_ready(1), "P1 lost, P2 fine")
	h.check(a.describe(0).contains("disconnected"), "the description says so")
	set_pads(a, [0, 1])
	a.on_connection_changed(0, true)
	h.eq(events, [["lost", 0, 0], ["back", 0, 0]], "the same pad id returned -> device_restored")
	h.check(not a.is_lost(0), "P1 ready again")
	set_pads(a, [1])
	a.on_connection_changed(0, false)
	set_pads(a, [1, 6])
	a.on_connection_changed(6, true)
	h.check(a.is_lost(0), "a different pad appearing does not heal the seat by itself")
	h.check(not a.reassign(0, 1), "P2's pad cannot be given to P1")
	h.check(not a.reassign(0, 9), "a pad that is not connected cannot be assigned")
	h.check(a.reassign(0, 6), "pad 6 takes over P1")
	h.eq(a.scheme_for_slot(0), "pad6", "P1 is on pad6 now")
	h.check(not a.is_lost(0), "no longer lost")
	h.eq(events.back(), ["back", 0, 6], "device_restored(0, 6)")
	a.unlock()
	h.eq(a.scheme_for_slot(0), "pad1", "after the match the seats re-resolve automatically (pad1 is first)")
	a.disconnect_hotplug()


# ---- hints ----------------------------------------------------------------------------------------------------
static func _hints(h) -> void:
	h.begin("hints: strings are generated from the bindings (keyboard, pad in the controller's own words, touch)")
	var b := ControlBindings.new()
	var kb1 := b.hint_text("kb1")
	for needle in ["WASD move", "Shift sprint", "LMB/F light", "RMB/G heavy", "Q hold block", "E parry", "Space dodge", "R ability", "Tab lock-on"]:
		h.check(kb1.contains(needle), "kb1 hint contains '%s'" % needle)
	var kb2 := b.hint_text("kb2")
	for needle in ["Arrows move", "Ctrl sprint", "J light", "K heavy", "U hold block", "I parry", "L dodge", "O ability", "P lock-on"]:
		h.check(kb2.contains(needle), "kb2 hint contains '%s'" % needle)
	ControllerGlyphs.fake_devices = {0: {"name": "PS4 Controller"}, 1: {"name": "XInput Gamepad"}}
	var ps := b.hint_text("pad0")
	for needle in ["Square light", "Triangle/R2 heavy", "L1 hold block", "R1 parry", "Cross dodge", "Circle ability", "L2 sprint", "L3 lock-on", "Options pause"]:
		h.check(ps.contains(needle), "pad0 (PS4) hint contains '%s'" % needle)
	var xb := b.hint_text("pad1")
	for needle in ["X light", "Y/RT heavy", "LB hold block", "RB parry", "A dodge", "B ability", "LT sprint", "LS lock-on", "Menu pause"]:
		h.check(xb.contains(needle), "pad1 (Xbox) hint contains '%s'" % needle)
	ControllerGlyphs.fake_devices = {}
	h.check(b.hint_text("touch").contains("Left stick"), "touch hint")
	b.set_key("kb1", "light", KEY_H)
	h.check(b.hint_text("kb1").contains("LMB/H light"), "a rebound key shows up in the hint")
	b.set_pad("light", {"type": "button", "index": JOY_BUTTON_B})
	ControllerGlyphs.fake_devices = {0: {"name": "PS4 Controller"}}
	h.check(b.hint_text("pad0").contains("Circle light"), "a rebound pad button shows up in the hint (Circle)")
	ControllerGlyphs.fake_devices = {}
	h.check(b.help_text(ControllerGlyphs.Family.PLAYSTATION).split("\n").size() == 3, "help_text is three lines (P1, P2, pad)")


# ---- real arena: two pads -------------------------------------------------------------------------------------
static func _make_arena(tree: SceneTree, schemes: Array, bindings: ControlBindings, request_seed: int = 5) -> CombatArena:
	var arena: CombatArena = (load(ARENA) as PackedScene).instantiate()
	tree.root.add_child(arena)
	arena.configure_seats({"player-white": {"type": "human", "scheme": schemes[0]}, "player-black": {"type": "human", "scheme": schemes[1]}})
	var reply := arena.start_battle(FighterRoster.build_request("n", "n", "w", "pads-%d" % request_seed, request_seed, 0))
	if not reply["ok"]:
		push_error("arena did not start: %s" % str(reply))
	return arena


static func _live(tree: SceneTree, arena: CombatArena) -> void:
	for _i in 200:
		await tree.physics_frame
	arena.sim.fighters[0].teleport(Vector3(-6.0, 0.0, 0.0))  # far apart: nobody gets hit while the test presses buttons
	arena.sim.fighters[1].teleport(Vector3(6.0, 0.0, 0.0))


static func _counts(arena: CombatArena, pid: String) -> Dictionary:
	var c: Dictionary = arena.sim.accepted_input(pid)
	return {"light": c["light"], "heavy": c["heavy"], "dodge": c["dodge"], "parry": c["parry"], "ability": c["ability"]}


static func _two_pad_fight(h, tree: SceneTree) -> void:
	h.begin("two pads: each fighter answers ONLY its own pad (real CombatArena, injected events on device 0 and 1)")
	var bindings := ControlBindings.new()
	var assignment := fake_assignment(bindings, [0, 1])
	var old_b := ControlBindings.shared()
	var old_a := InputAssignment.shared()
	ControlBindings.set_shared(bindings)
	InputAssignment.set_shared(assignment)
	ControllerGlyphs.fake_devices = {0: {"name": "PS4 Controller"}, 1: {"name": "PS4 Controller"}}
	var arena := _make_arena(tree, [assignment.scheme_for_slot(0), assignment.scheme_for_slot(1)], bindings)
	var sources := arena.find_children("*", "LocalInputSource", false, false)
	if not h.eq(sources.size(), 2, "two LocalInputSource nodes (P1 pad0, P2 pad1)"):
		arena.queue_free()
		ControlBindings.set_shared(old_b)
		InputAssignment.set_shared(old_a)
		return
	h.eq([sources[0].scheme, sources[1].scheme], ["pad0", "pad1"], "seats resolved to pad0 / pad1")
	await _live(tree, arena)
	var w: FighterController = arena.sim.fighters[0]
	var b: FighterController = arena.sim.fighters[1]
	h.eq(arena.sim.countdown_remaining, 0, "the countdown is over")
	h.eq(_counts(arena, "player-white"), {"light": 0, "heavy": 0, "dodge": 0, "parry": 0, "ability": 0}, "white starts at zero")
	h.eq(_counts(arena, "player-black"), {"light": 0, "heavy": 0, "dodge": 0, "parry": 0, "ability": 0}, "black starts at zero")

	# Every press action on pad 0 -> white only, exactly one counter each.
	var map := {"light": JOY_BUTTON_X, "heavy": JOY_BUTTON_Y, "dodge": JOY_BUTTON_A, "parry": JOY_BUTTON_RIGHT_SHOULDER, "ability": JOY_BUTTON_B}
	var expect_w := {"light": 0, "heavy": 0, "dodge": 0, "parry": 0, "ability": 0}
	for action in map:
		tap(0, map[action], tree)
		await ticks(tree, 3)
		expect_w[action] += 1
		h.eq(_counts(arena, "player-white"), expect_w, "pad 0 %s (button %d) -> white's %s counter, exactly +1" % [action, map[action], action])
		h.eq(_counts(arena, "player-black"), {"light": 0, "heavy": 0, "dodge": 0, "parry": 0, "ability": 0}, "...and black saw nothing")
		await ticks(tree, 70)  # let the action finish; cooldowns / stamina are irrelevant to the counter
	# R2 axis on pad 1 -> black heavy alias.
	axis(1, JOY_AXIS_TRIGGER_RIGHT, 0.2)
	axis(1, JOY_AXIS_TRIGGER_RIGHT, 0.55)
	axis(1, JOY_AXIS_TRIGGER_RIGHT, 0.7)
	axis(1, JOY_AXIS_TRIGGER_RIGHT, 0.45)  # inside the hysteresis band: still held, no new edge
	axis(1, JOY_AXIS_TRIGGER_RIGHT, 0.6)
	await ticks(tree, 3)
	h.eq(_counts(arena, "player-black")["heavy"], 1, "pad 1 R2 (pressed once through the hysteresis band) -> exactly ONE black heavy")
	axis(1, JOY_AXIS_TRIGGER_RIGHT, 0.1)
	await ticks(tree, 3)
	axis(1, JOY_AXIS_TRIGGER_RIGHT, 0.8)
	await ticks(tree, 3)
	h.eq(_counts(arena, "player-black")["heavy"], 2, "released below 0.35 and pressed again -> the second heavy")
	axis(1, JOY_AXIS_TRIGGER_RIGHT, 0.0)
	h.eq(_counts(arena, "player-white")["heavy"], 1, "white's heavy counter is unchanged by pad 1")
	await ticks(tree, 70)
	# Rapid double tap in one frame: two edges -> the builder counts two presses, the simulation accepts one per packet (documented contract).
	var before := _counts(arena, "player-black")
	tap(1, JOY_BUTTON_Y, tree)
	await ticks(tree, 2)
	h.eq(_counts(arena, "player-black")["heavy"], int(before["heavy"]) + 1, "pad 1 Triangle -> black heavy +1")
	h.eq(_counts(arena, "player-white")["heavy"], 1, "white still unaffected")
	await ticks(tree, 70)

	# Held: L1 block on pad 1 only; L2 sprint axis with hysteresis on pad 0 only.
	var si := sources[0]
	btn(1, JOY_BUTTON_LEFT_SHOULDER, true)
	await ticks(tree, 12)
	h.eq(b.sm.state, S.BLOCKING, "pad 1 L1 raises black's guard")
	h.check(w.sm.state != S.BLOCKING, "white's guard stays down")
	btn(1, JOY_BUTTON_LEFT_SHOULDER, false)
	await ticks(tree, 12)
	h.check(b.sm.state != S.BLOCKING, "releasing L1 lowers it")
	axis(0, JOY_AXIS_TRIGGER_LEFT, 0.7)
	await ticks(tree, 3)
	h.check(arena.sim._inputs["player-white"].sprint, "pad 0 L2 at 0.7 -> white sprint")
	h.check(not arena.sim._inputs["player-black"].sprint, "black does not sprint")
	axis(0, JOY_AXIS_TRIGGER_LEFT, 0.4)  # inside the band (0.35..0.5): still held
	await ticks(tree, 3)
	h.check(arena.sim._inputs["player-white"].sprint, "L2 at 0.4 (inside the hysteresis band) keeps sprinting")
	axis(0, JOY_AXIS_TRIGGER_LEFT, 0.3)
	await ticks(tree, 3)
	h.check(not arena.sim._inputs["player-white"].sprint, "L2 below 0.35 releases sprint")
	axis(0, JOY_AXIS_TRIGGER_LEFT, 0.0)

	# Sticks: pad 0's left stick walks white, pad 1's stick is separate.
	var wz0 := w.global_position
	var bz0 := b.global_position
	axis(0, JOY_AXIS_LEFT_Y, -1.0)  # up = forward (Godot: up is negative)
	await ticks(tree, 40)
	h.check(w.global_position.distance_to(wz0) > 0.5, "pad 0's left stick moved white (%.2f m)" % w.global_position.distance_to(wz0))
	h.near(b.global_position.distance_to(bz0), 0.0, 0.01, "black did not move")
	axis(0, JOY_AXIS_LEFT_Y, 0.0)
	axis(0, JOY_AXIS_LEFT_X, 0.1)  # inside the dead zone
	axis(0, JOY_AXIS_LEFT_Y, 0.1)
	await ticks(tree, 70)
	var rest := w.global_position
	await ticks(tree, 30)
	h.near(w.global_position.distance_to(rest), 0.0, 0.01, "a stick resting at (0.1, 0.1) (inside the dead zone) does not creep")
	axis(0, JOY_AXIS_LEFT_X, 0.0)
	axis(0, JOY_AXIS_LEFT_Y, 0.0)
	axis(1, JOY_AXIS_LEFT_X, 1.0)
	await ticks(tree, 40)
	h.check(b.global_position.distance_to(bz0) > 0.5, "pad 1's stick moved black")
	axis(1, JOY_AXIS_LEFT_X, 0.0)

	# Lock-on: L3 toggles ONLY the seat's own camera.
	var cams: Array = arena.cameras
	var locked := [cams[0].locked, cams[1].locked]
	tap(0, JOY_BUTTON_LEFT_STICK, tree)
	await ticks(tree, 2)
	h.check(cams[0].locked != locked[0] and cams[1].locked == locked[1], "pad 0 L3 toggles camera 0 only")
	tap(1, JOY_BUTTON_LEFT_STICK, tree)
	await ticks(tree, 2)
	h.check(cams[0].locked != locked[0] and cams[1].locked != locked[1], "pad 1 L3 toggles camera 1 only")
	# Right stick orbits the free camera of the same seat.
	var yaw1: float = cams[1].yaw
	var yaw0: float = cams[0].yaw
	axis(1, JOY_AXIS_RIGHT_X, 1.0)
	await ticks(tree, 20)
	h.check(absf(CombatConstants.angle_diff(yaw1, cams[1].yaw)) > 0.1, "pad 1's right stick orbits camera 1 (unlocked)")
	h.near(absf(CombatConstants.angle_diff(yaw0, cams[0].yaw)), 0.0, 0.0001, "camera 0 did not move")
	axis(1, JOY_AXIS_RIGHT_X, 0.0)

	# Foreign devices are ignored entirely.
	var snap_w := _counts(arena, "player-white")
	var snap_b := _counts(arena, "player-black")
	for dev in [2, 3, 7]:
		tap(dev, JOY_BUTTON_X, tree)
		tap(dev, JOY_BUTTON_Y, tree)
		tap(dev, JOY_BUTTON_A, tree)
	await ticks(tree, 3)
	h.eq(_counts(arena, "player-white"), snap_w, "buttons from unassigned devices 2/3/7 do nothing to white")
	h.eq(_counts(arena, "player-black"), snap_b, "...nor to black")
	# Keyboard keys do not drive a pad seat.
	key(KEY_F)
	key(KEY_F, false)
	key(KEY_J)
	key(KEY_J, false)
	await ticks(tree, 3)
	h.eq(_counts(arena, "player-white"), snap_w, "keyboard F does nothing to a pad seat")
	h.eq(_counts(arena, "player-black"), snap_b, "keyboard J does nothing to a pad seat")

	# Options asks to pause (both pads).
	var pauses := [0]
	for s in sources:
		s.pause_requested.connect(func(): pauses[0] += 1)
	tap(0, JOY_BUTTON_START, tree)
	tap(1, JOY_BUTTON_START, tree)
	h.eq(pauses[0], 2, "Options on each pad emits pause_requested once")
	h.eq(_counts(arena, "player-white"), snap_w, "...and is not an attack")

	release_all()
	arena.stop_battle()
	arena.queue_free()
	await tree.process_frame
	ControlBindings.set_shared(old_b)
	InputAssignment.set_shared(old_a)
	ControllerGlyphs.fake_devices = {}


# ---- hot-plug mid fight -----------------------------------------------------------------------------------------
static func _hotplug_mid_fight(h, tree: SceneTree) -> void:
	h.begin("hot-plug: P1's pad disconnects mid-fight -> neutral + paused, resumes on reconnect; another pad can take over")
	var bindings := ControlBindings.new()
	var assignment := fake_assignment(bindings, [0, 1])
	var old_b := ControlBindings.shared()
	var old_a := InputAssignment.shared()
	ControlBindings.set_shared(bindings)
	InputAssignment.set_shared(assignment)
	assignment.lock_for_match()
	var arena := _make_arena(tree, [assignment.scheme_for_slot(0), assignment.scheme_for_slot(1)], bindings, 6)
	var guard := PadHold.attach(arena, assignment)
	await _live(tree, arena)
	var sources := arena.find_children("*", "LocalInputSource", false, false)
	var w_source = sources[0]
	tap(0, JOY_BUTTON_X, tree)
	await ticks(tree, 3)
	h.eq(_counts(arena, "player-white")["light"], 1, "before the drop pad 0 attacks normally")
	axis(0, JOY_AXIS_LEFT_Y, -1.0)  # white is walking forward when the pad vanishes
	await ticks(tree, 20)
	var tick_before: int = arena.sim.server_tick
	h.check(not guard.holding, "no hold while everything is connected")

	set_pads(assignment, [1])
	assignment.on_connection_changed(0, false)
	await ticks(tree, 5)
	h.check(w_source.pad_lost, "P1's source reports pad_lost")
	h.check(guard.holding, "PadHold is holding")
	h.check(not arena.is_physics_processing(), "the arena's tick is frozen")
	h.eq(guard.lost_seats, [0] as Array[int], "seat 0 is the lost one")
	var frozen_tick: int = arena.sim.server_tick
	await ticks(tree, 40)
	h.eq(arena.sim.server_tick, frozen_tick, "the simulation did not advance during the hold (no free hits on a missing player)")
	h.check(frozen_tick - tick_before <= 8, "...and it stopped within a few ticks of the disconnect")
	tap(0, JOY_BUTTON_X, tree)  # a ghost event from the vanished device must be ignored
	await ticks(tree, 3)
	h.eq(_counts(arena, "player-white")["light"], 1, "events from the vanished device are ignored")
	h.check(guard._label != null and guard._label.text.contains("Player 1"), "a banner tells the players what happened")

	set_pads(assignment, [0, 1])
	assignment.on_connection_changed(0, true)
	await ticks(tree, 3)
	h.check(not guard.holding and arena.is_physics_processing(), "the same pad id returning resumes the fight")
	h.check(not w_source.pad_lost, "pad_lost cleared")
	var resumed: int = arena.sim.server_tick
	await ticks(tree, 10)
	h.check(arena.sim.server_tick > resumed, "the simulation runs again")
	axis(0, JOY_AXIS_LEFT_Y, 0.0)
	tap(0, JOY_BUTTON_X, tree)
	await ticks(tree, 3)
	h.eq(_counts(arena, "player-white")["light"], 2, "pad 0 attacks again after the reconnect (counter 1 -> 2, no phantom presses)")

	# Drop again; the controller comes back as a different device id: a button press on the new pad takes the seat.
	set_pads(assignment, [1])
	assignment.on_connection_changed(0, false)
	await ticks(tree, 4)
	h.check(guard.holding, "held again")
	set_pads(assignment, [1, 5])
	assignment.on_connection_changed(5, true)
	await ticks(tree, 2)
	h.check(guard.holding, "a new pad appearing is not enough by itself")
	btn(1, JOY_BUTTON_A, true)  # P2's own pad must not be able to steal P1's seat
	Input.flush_buffered_events()
	btn(1, JOY_BUTTON_A, false)
	await ticks(tree, 2)
	h.check(guard.holding, "P2's pad cannot take over P1's seat")
	btn(5, JOY_BUTTON_START, true)
	Input.flush_buffered_events()
	btn(5, JOY_BUTTON_START, false)
	await ticks(tree, 2)
	h.check(guard.holding, "Options on the new pad does not take over (it is the pause key)")
	btn(5, JOY_BUTTON_A, true)
	Input.flush_buffered_events()
	btn(5, JOY_BUTTON_A, false)
	await ticks(tree, 4)
	h.check(not guard.holding and arena.is_physics_processing(), "any other button on pad 5 takes P1's seat and the fight resumes")
	h.eq(w_source.scheme, "pad5", "P1 is now on pad5")
	h.eq(assignment.scheme_for_slot(0), "pad5", "the assignment agrees")
	var c: int = _counts(arena, "player-white")["light"]
	tap(5, JOY_BUTTON_X, tree)
	await ticks(tree, 3)
	h.eq(_counts(arena, "player-white")["light"], c + 1, "pad 5 now fights as P1")
	tap(0, JOY_BUTTON_X, tree)
	await ticks(tree, 3)
	h.eq(_counts(arena, "player-white")["light"], c + 1, "the old device 0 is ignored")

	# Both drop at once, then the arena is torn down while holding: no crash, the arena is left running.
	set_pads(assignment, [])
	assignment.on_connection_changed(5, false)
	assignment.on_connection_changed(1, false)
	await ticks(tree, 4)
	h.check(guard.holding and guard.lost_seats.size() == 2, "both seats lost -> still one hold")
	guard.queue_free()
	await tree.process_frame
	await tree.process_frame
	h.check(arena.is_physics_processing(), "removing the guard releases the freeze (nothing is ever left frozen)")
	release_all([0, 1, 5])
	arena.stop_battle()
	arena.queue_free()
	await tree.process_frame
	ControlBindings.set_shared(old_b)
	InputAssignment.set_shared(old_a)


# ---- rebound pad map + pad tuning in a real fight --------------------------------------------------------------------------
static func _custom_bindings_fight(h, tree: SceneTree) -> void:
	h.begin("rebinding: a custom pad map drives the real fight (Circle light, Square special, R2 sprint, no heavy alias, tuned stick)")
	var bindings := ControlBindings.new()
	h.check(bindings.set_pad("light", {"type": "button", "index": JOY_BUTTON_B})["ok"], "light -> Circle")      # swaps ability to Square? (ability held Circle)
	h.eq(bindings.pad_input("ability"), {"type": "button", "index": JOY_BUTTON_X}, "(the swap handed Square to the special)")
	h.check(bindings.set_pad("heavy2", {})["ok"], "R2 alias unbound")
	h.check(bindings.set_pad("sprint", {"type": "axis", "index": JOY_AXIS_TRIGGER_RIGHT})["ok"], "sprint -> R2")
	bindings.set_pad_setting("deadzone", 0.5)
	bindings.set_pad_setting("invert_look_y", true)
	var assignment := fake_assignment(bindings, [0, 1])
	var old_b := ControlBindings.shared()
	var old_a := InputAssignment.shared()
	ControlBindings.set_shared(bindings)
	InputAssignment.set_shared(assignment)
	var arena := _make_arena(tree, ["pad0", "pad1"], bindings, 7)
	await _live(tree, arena)
	var zero := {"light": 0, "heavy": 0, "dodge": 0, "parry": 0, "ability": 0}
	tap(0, JOY_BUTTON_B, tree)
	await ticks(tree, 3)
	var expect := zero.duplicate()
	expect["light"] = 1
	h.eq(_counts(arena, "player-white"), expect, "Circle is light now (and only light)")
	await ticks(tree, 70)
	tap(0, JOY_BUTTON_X, tree)
	await ticks(tree, 3)
	expect["ability"] = 1
	h.eq(_counts(arena, "player-white"), expect, "Square is the special now")
	await ticks(tree, 70)
	axis(0, JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await ticks(tree, 4)
	h.eq(_counts(arena, "player-white"), expect, "R2 no longer attacks (alias unbound)")
	h.check(arena.sim._inputs["player-white"].sprint, "R2 is sprint now")
	axis(0, JOY_AXIS_TRIGGER_RIGHT, 0.0)
	axis(0, JOY_AXIS_TRIGGER_LEFT, 1.0)
	await ticks(tree, 4)
	h.check(not arena.sim._inputs["player-white"].sprint, "L2 no longer sprints")
	axis(0, JOY_AXIS_TRIGGER_LEFT, 0.0)
	# Tuned dead zone: a 0.4 push (below the configured 0.5) does nothing; 0.9 walks.
	var p0: Vector3 = arena.sim.fighters[0].global_position
	axis(0, JOY_AXIS_LEFT_Y, -0.4)
	await ticks(tree, 30)
	h.near(arena.sim.fighters[0].global_position.distance_to(p0), 0.0, 0.01, "0.4 < the configured 0.5 dead zone: no movement")
	axis(0, JOY_AXIS_LEFT_Y, -0.9)
	await ticks(tree, 30)
	h.check(arena.sim.fighters[0].global_position.distance_to(p0) > 0.3, "0.9 walks")
	axis(0, JOY_AXIS_LEFT_Y, 0.0)
	# Inverted look: unlock the camera and push the stick up; pitch must move the other way versus the default.
	var cam: ThirdPersonCamera = arena.cameras[0]
	cam.locked = false
	var pitch0 := cam.pitch
	axis(0, JOY_AXIS_RIGHT_Y, 1.0)
	await ticks(tree, 10)
	var inverted_delta := cam.pitch - pitch0
	axis(0, JOY_AXIS_RIGHT_Y, 0.0)
	bindings.set_pad_setting("invert_look_y", false)
	pitch0 = cam.pitch
	axis(0, JOY_AXIS_RIGHT_Y, 1.0)
	await ticks(tree, 10)
	var normal_delta := cam.pitch - pitch0
	axis(0, JOY_AXIS_RIGHT_Y, 0.0)
	h.check(inverted_delta < -0.01 and normal_delta > 0.01, "invert_look_y flips the pitch direction (%.3f vs %.3f)" % [inverted_delta, normal_delta])
	var sens_ref := normal_delta
	bindings.set_pad_setting("look_sensitivity", 2.0)
	pitch0 = cam.pitch
	axis(0, JOY_AXIS_RIGHT_Y, -1.0)
	await ticks(tree, 10)
	var sens_delta := pitch0 - cam.pitch
	axis(0, JOY_AXIS_RIGHT_Y, 0.0)
	h.check(sens_delta > sens_ref * 1.5, "look_sensitivity 2.0 turns the camera about twice as fast (%.3f vs %.3f)" % [sens_delta, sens_ref])
	release_all()
	arena.stop_battle()
	arena.queue_free()
	await tree.process_frame
	ControlBindings.set_shared(old_b)
	InputAssignment.set_shared(old_a)


# ---- keyboard sets (kb1 vs kb2 at once, rebinding) ---------------------------------------------------------------------------
static func _keyboard_fight(h, tree: SceneTree) -> void:
	h.begin("keyboard: kb1 and kb2 drive their own fighters at the same time; a rebound key replaces the old one")
	var bindings := ControlBindings.new()
	var assignment := fake_assignment(bindings, [])
	var old_b := ControlBindings.shared()
	var old_a := InputAssignment.shared()
	ControlBindings.set_shared(bindings)
	InputAssignment.set_shared(assignment)
	var arena := _make_arena(tree, ["kb1", "kb2"], bindings, 8)
	await _live(tree, arena)
	var zero := {"light": 0, "heavy": 0, "dodge": 0, "parry": 0, "ability": 0}
	key(KEY_F)
	key(KEY_F, false)
	key(KEY_K)
	key(KEY_K, false)
	await ticks(tree, 3)
	h.eq(_counts(arena, "player-white")["light"], 1, "F -> white light")
	h.eq(_counts(arena, "player-white")["heavy"], 0, "K did not reach white")
	h.eq(_counts(arena, "player-black")["heavy"], 1, "K -> black heavy")
	h.eq(_counts(arena, "player-black")["light"], 0, "F did not reach black")
	await ticks(tree, 70)
	bindings.set_key("kb1", "light", KEY_H)
	key(KEY_F)
	key(KEY_F, false)
	await ticks(tree, 3)
	h.eq(_counts(arena, "player-white")["light"], 1, "after rebinding light to H, F does nothing")
	key(KEY_H)
	key(KEY_H, false)
	await ticks(tree, 3)
	h.eq(_counts(arena, "player-white")["light"], 2, "H attacks")
	await ticks(tree, 70)
	# Held keys: Q blocks white only, Ctrl sprints black only.
	key(KEY_Q)
	await ticks(tree, 12)
	h.eq(arena.sim.fighters[0].sm.state, S.BLOCKING, "Q holds white's guard")
	h.check(arena.sim.fighters[1].sm.state != S.BLOCKING, "black's guard is down")
	key(KEY_Q, false)
	key(KEY_CTRL)
	await ticks(tree, 3)
	h.check(arena.sim._inputs["player-black"].sprint and not arena.sim._inputs["player-white"].sprint, "Ctrl sprints black only")
	key(KEY_CTRL, false)
	h.check(zero.size() == 5, "sanity")
	arena.stop_battle()
	arena.queue_free()
	await tree.process_frame
	ControlBindings.set_shared(old_b)
	InputAssignment.set_shared(old_a)
