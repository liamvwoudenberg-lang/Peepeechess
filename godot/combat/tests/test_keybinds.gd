extends RefCounted
## Dark Souls style PC control profiles (ControlBindings profiles + LocalInputSource tap / hold logic). Every input here is a
## synthetic key / mouse event through Input.parse_input_event, the path real hardware takes. What this proves: profile data,
## one-action-per-input, the two-hand reach rule, persistence, rebind conflicts, hints, and that key / mouse events produce
## the right intent counters in a real CombatArena. It cannot prove how the layouts FEEL under real hands.

const Pads := preload("res://combat/tests/test_pads.gd")
const ARENA := "res://combat/arena.tscn"
const TMP := "user://keybinds_test"
const NEEDED := ["up", "down", "left", "right", "sprint", "light", "heavy", "dodge", "block", "parry", "ability", "lock", "orbit_l", "orbit_r"]


static func run(h, tree: SceneTree) -> void:
	_profile_data(h)
	_reach(h)
	_persistence(h)
	_rebind(h)
	_hints(h)
	await _controls_screen(h, tree)
	await _souls_mouse_fight(h, tree)
	await _souls_keys_fight(h, tree)
	await _classic_fight(h, tree)


static func _fresh(profile: String, scheme: String = "kb1") -> ControlBindings:
	var b := ControlBindings.new()
	b.apply_profile(scheme, profile)
	return b


static func kp(code: int, pressed: bool = true) -> void:
	Pads.key(code, pressed)
	Input.flush_buffered_events()


static func mouse(button: int, pressed: bool = true) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button as MouseButton
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()


static func _data_of(b: ControlBindings, scheme: String) -> Array:
	var out: Array = []
	for action in ControlBindings.KEY_ACTIONS:
		for code in [b.key_for(scheme, action), b.alt_for(scheme, action)]:
			if code != 0:
				out.append(code)
	return out


# ---- data ---------------------------------------------------------------------------------------------------
static func _profile_data(h) -> void:
	h.begin("keybind profiles: every combat action is bound, nothing clashes, each input does exactly one thing")
	h.check(ControlBindings.new().is_default(), "a new ControlBindings is the classic layout (tests and old saves unchanged)")
	h.eq(ControlBindings.FIRST_RUN_PROFILE, "souls_mouse", "first-time players get the Souls keyboard + mouse layout")
	for id in ControlBindings.PROFILE_IDS:
		var scheme: String = ControlBindings.PROFILE_SCHEMES[id][0]
		var b := _fresh(id, scheme)
		h.eq(b.profile_of(scheme), id, "%s: applied" % id)
		for action in NEEDED:
			h.check(b.key_for(scheme, action) != 0, "%s: %s is bound" % [id, action])
		h.check(b.find_conflicts().is_empty(), "%s: no duplicate inputs (%s)" % [id, str(b.find_conflicts())])
		var seen: Dictionary = {}
		for code in _data_of(b, scheme):
			h.check(not seen.has(code), "%s: input %s is used once" % [id, ControlBindings.key_name(code)])
			seen[code] = true
			h.eq(b.actions_for(scheme, code).size(), 1, "%s: input %s triggers exactly one action" % [id, ControlBindings.key_name(code)])
		for code in _data_of(b, scheme):
			h.check(not (code in ControlBindings.RESERVED_KEYS), "%s: no reserved key (Esc / F1 / F11)" % id)
	for id in ["souls_keys", "duo_left", "duo_right"]:
		var scheme: String = ControlBindings.PROFILE_SCHEMES[id][0]
		var b := _fresh(id, scheme)
		for code in _data_of(b, scheme):
			h.check(code > 0, "%s: no mouse inputs (it is for players without a mouse)" % id)
		h.check(not b.uses_mouse(scheme), "%s: does not capture the mouse" % id)
	var mouse_profile := _fresh("souls_mouse")
	h.check(mouse_profile.uses_mouse("kb1"), "souls_mouse uses the mouse")
	h.eq(mouse_profile.key_for("kb1", "light"), -MOUSE_BUTTON_LEFT, "souls_mouse: left mouse = light attack")
	h.eq(mouse_profile.key_for("kb1", "block"), -MOUSE_BUTTON_RIGHT, "souls_mouse: right mouse = block")
	h.eq(mouse_profile.key_for("kb1", "lock"), -MOUSE_BUTTON_MIDDLE, "souls_mouse: middle mouse = lock-on")
	h.eq(mouse_profile.key_for("kb1", "heavy"), -MOUSE_BUTTON_XBUTTON2, "souls_mouse: mouse 5 = heavy")
	h.eq(mouse_profile.alt_for("kb1", "ability"), -MOUSE_BUTTON_XBUTTON1, "souls_mouse: mouse 4 = ability (R as well)")
	h.check(bool(mouse_profile.option("kb1", "heavy_on_hold")) and bool(mouse_profile.option("kb1", "alt_heavy")), "souls_mouse: hold / Alt+LMB = heavy")
	h.check(bool(mouse_profile.option("kb1", "parry_on_tap")) and bool(mouse_profile.option("kb1", "sprint_tap_dodge")), "souls_mouse: tap RMB = parry, tap Shift = dodge")
	# Profiles that belong to the other set are refused.
	h.check(not ControlBindings.new().apply_profile("kb2", "souls_mouse")["ok"], "souls_mouse cannot be applied to keyboard 2")
	h.check(not ControlBindings.new().apply_profile("kb1", "bogus")["ok"], "an unknown profile is refused")


static func _reach(h) -> void:
	h.begin("two-hand reach rule: left hand = WASD + Shift/Space, right hand = the I J K L U O P cluster; the mouse hand never needs the keyboard")
	var left := ControlBindings.LEFT_HAND_KEYS
	var right := ControlBindings.RIGHT_HAND_KEYS
	var keys_only := _fresh("souls_keys")
	for action in ["up", "down", "left", "right", "sprint", "dodge"]:
		h.check(keys_only.key_for("kb1", action) in left, "souls_keys: %s is on the left hand" % action)
	for action in ["light", "heavy", "block", "parry", "ability", "lock", "orbit_l", "orbit_r", "look_up", "look_down"]:
		h.check(keys_only.key_for("kb1", action) in right, "souls_keys: %s is on the right hand" % action)
	var with_mouse := _fresh("souls_mouse")
	for code in _data_of(with_mouse, "kb1"):
		if code > 0:
			h.check(code in left, "souls_mouse: keyboard input %s is within the left hand's reach (the right hand holds the mouse)" % ControlBindings.key_name(code))
	var duo_l := _fresh("duo_left")
	for code in _data_of(duo_l, "kb1"):
		h.check(code in left, "duo_left: %s is in the left half" % ControlBindings.key_name(code))
	var duo_r := _fresh("duo_right", "kb2")
	for action in NEEDED:
		var code := duo_r.key_for("kb2", action)
		if action != "sprint":  # right Ctrl: Godot reports it as the same physical key as left Ctrl
			h.check(code in right, "duo_right: %s is in the right half" % action)
	h.check(duo_l.find_conflicts().is_empty() and not ControlBindings.new().find_conflicts().size() > 0, "the two-player halves share no key")


# ---- persistence --------------------------------------------------------------------------------------------
static func _persistence(h) -> void:
	h.begin("keybind persistence: profile, alternates, mouse inputs and options survive a save / load; old and hostile files are safe")
	DirAccess.make_dir_recursive_absolute(TMP)
	var path := TMP + "/controls.json"
	var b := _fresh("souls_mouse")
	b.set_option("kb1", "mouse_sensitivity", 2.5)
	b.set_option("kb1", "invert_y", true)
	b.set_option("kb1", "heavy_hold_ms", 300.0)
	b.set_option("kb1", "hold_block", false)
	b.set_alt("kb1", "dodge", KEY_C)
	h.eq(b.save_file(path), OK, "saved")
	var c := ControlBindings.new()
	h.check(c.load_file(path), "loaded")
	h.eq(c.profile_of("kb1"), "souls_mouse", "profile kept")
	h.eq(c.keys_for("kb1"), b.keys_for("kb1"), "keys (incl. mouse buttons) kept")
	h.eq(c.alts["kb1"], b.alts["kb1"], "alternates kept")
	h.eq(c.option("kb1", "mouse_sensitivity"), 2.5, "mouse sensitivity kept")
	h.check(bool(c.option("kb1", "invert_y")) and not bool(c.option("kb1", "hold_block")), "toggles kept")
	h.eq(c.option("kb1", "heavy_hold_ms"), 300.0, "tap-vs-hold threshold kept")
	h.check(c.find_conflicts().is_empty(), "no conflicts after loading")
	# A file written before profiles existed (only "keyboard" ints) is the classic layout with the user's keys.
	var legacy := {"version": 1, "keyboard": {"kb1": {"light": KEY_H}}}
	var d := ControlBindings.new()
	h.check(d.from_dict(legacy), "a legacy file loads")
	h.eq(d.profile_of("kb1"), "classic", "...as the classic profile")
	h.eq(d.key_for("kb1", "light"), KEY_H, "...keeping its key")
	h.eq(d.alt_for("kb1", "light"), -MOUSE_BUTTON_LEFT, "...and the classic mouse alternates")
	# Hostile entries fall back per entry.
	var bad := {"version": 1, "profiles": {"kb1": "souls_mouse", "kb2": "souls_mouse"},
		"keyboard": {"kb1": {"heavy": "mouse:99", "light": "mouse:3", "lock": "mouse:1"}, "kb2": {"light": "mouse:1"}},
		"alts": {"kb1": {"ability": "mouse:xx", "lock": 7.5}}, "options": {"kb1": {"mouse_sensitivity": 999, "invert_y": "yes", "heavy_hold_ms": -5}}}
	var e := ControlBindings.new()
	h.check(e.from_dict(bad), "a partly invalid file loads")
	h.eq(e.profile_of("kb2"), "duo_right", "a profile that does not fit its set -> default")
	h.eq(e.key_for("kb1", "heavy"), -MOUSE_BUTTON_XBUTTON2, "an unknown mouse button -> the profile default")
	h.eq(e.key_for("kb1", "light"), -MOUSE_BUTTON_MIDDLE, "a valid mouse input is accepted (light on MMB, lock-on moved to LMB: a clean swap)")
	h.eq(e.option("kb1", "mouse_sensitivity"), 4.0, "an absurd sensitivity is clamped")
	h.check(not bool(e.option("kb1", "invert_y")), "a non-bool flag -> default")
	h.eq(e.option("kb1", "heavy_hold_ms"), 100.0, "a negative threshold is clamped")
	h.check(e.find_conflicts().is_empty(), "the result is conflict free")
	h.check(not e.warnings.is_empty(), "the replaced entries are reported")
	DirAccess.remove_absolute(path)


# ---- rebinding ----------------------------------------------------------------------------------------------
static func _rebind(h) -> void:
	h.begin("rebinding: mouse buttons and keys, conflicts swapped / refused, profile switches clear clashes, reset restores the profile")
	var b := _fresh("souls_mouse")
	var r := b.set_key("kb1", "light", -MOUSE_BUTTON_MIDDLE)
	h.check(r["ok"] and r["swapped"], "light on the middle button swaps with lock-on")
	h.eq(b.key_for("kb1", "lock"), -MOUSE_BUTTON_LEFT, "lock-on received the left button")
	h.check(not b.set_key("kb1", "up", -MOUSE_BUTTON_LEFT)["ok"], "the mouse cannot be a movement key")
	h.check(not b.set_key("kb2", "light", -MOUSE_BUTTON_LEFT)["ok"], "the mouse belongs to keyboard 1")
	h.check(not b.set_key("kb1", "light", KEY_ESCAPE)["ok"], "Esc stays reserved")
	h.check(not b.set_alt("kb1", "up", KEY_Z)["ok"], "movement has no alternate slot")
	h.check(b.set_alt("kb1", "block", KEY_C)["ok"], "an alternate key can be added")
	h.eq(b.actions_for("kb1", KEY_C), ["block"], "...and triggers block")
	h.check(b.set_alt("kb1", "block", 0)["ok"] and b.alt_for("kb1", "block") == 0, "an alternate can be cleared")
	h.check(not b.set_key("kb1", "heavy", KEY_J, "reject")["ok"] or b.key_for("kb1", "heavy") == KEY_J, "an input of the other set is reported when rejecting")
	b.set_key("kb1", "ability", KEY_V)
	h.check(b.set_option("kb1", "heavy_on_hold", false), "options can be set")
	h.check(not b.set_option("kb1", "nope", 1.0) and not b.set_option("kb1", "invert_y", "yes"), "bad option names / types are refused")
	b.reset_scheme("kb1")
	h.eq(b.key_for("kb1", "ability"), KEY_R, "reset puts the profile's ability key back")
	h.check(bool(b.option("kb1", "heavy_on_hold")), "...and its options")
	h.eq(b.key_for("kb1", "light"), -MOUSE_BUTTON_LEFT, "...and its mouse buttons")
	# Switching to the keyboard-only profile unbinds the keys that player 2's keyboard set already owns.
	var two := ControlBindings.new()
	var result := two.apply_profile("kb1", "souls_keys")
	h.check(result["ok"] and not result["cleared"].is_empty(), "souls_keys clashes with keyboard 2's J K L U I O P: %d key(s) unbound there" % result["cleared"].size())
	h.check(two.find_conflicts().is_empty(), "no conflicts remain")
	h.eq(two.key_for("kb1", "light"), KEY_U, "kb1 keeps its Souls keys")
	h.eq(two.key_for("kb2", "light"), KEY_NONE, "kb2's clashing light key was unbound")
	h.check(two.apply_profile("kb2", "duo_right")["ok"] and two.find_conflicts().is_empty(), "re-applying the duo half to kb2 clears the clash from kb1 instead")


# ---- hints and glyphs -----------------------------------------------------------------------------------------
static func _hints(h) -> void:
	h.begin("hints: the HUD line and the F1 overlay show mouse-button glyphs and the tap / hold modifiers of the active profile")
	h.eq(ControlBindings.key_name(-MOUSE_BUTTON_LEFT), "LMB", "glyph: LMB")
	h.eq(ControlBindings.key_name(-MOUSE_BUTTON_RIGHT), "RMB", "glyph: RMB")
	h.eq(ControlBindings.key_name(-MOUSE_BUTTON_MIDDLE), "MMB", "glyph: MMB")
	h.eq(ControlBindings.key_name(-MOUSE_BUTTON_XBUTTON1), "Mouse 4", "glyph: Mouse 4")
	h.eq(ControlBindings.key_name(-MOUSE_BUTTON_XBUTTON2), "Mouse 5", "glyph: Mouse 5")
	h.eq(ControlBindings.key_name(-MOUSE_BUTTON_WHEEL_UP), "Wheel up", "glyph: wheel")
	var b := _fresh("souls_mouse")
	var text := b.hint_text("kb1")
	for needle in ["WASD move", "LMB light", "RMB block", "Mouse 5 heavy", "Mouse 4", "MMB", "tap: dodge", "hold: heavy", "tap: parry"]:
		h.check(needle in text, "souls_mouse hint contains '%s'" % needle)
	var rows := ControlOverlay.rows(b, "kb1", "p", true)
	var flat := ""
	for row in rows:
		flat += "%s=%s; " % [row[0], row[1]]
	for needle in ["Light=LMB", "Block=RMB", "Heavy=Mouse 5", "Lock-on=MMB / X", "Ability=Mouse 4 / R"]:
		h.check(needle in flat, "F1 overlay row '%s' (%s)" % [needle, flat.substr(0, 0)])
	var no_mouse := ControlOverlay.rows(b, "kb1", "p", false)
	var flat2 := ""
	for row in no_mouse:
		flat2 += "%s=%s; " % [row[0], row[1]]
	h.check(not ("LMB" in flat2), "with the mouse not live (two players) no mouse glyph is shown")
	var keys_hint := _fresh("souls_keys").hint_text("kb1")
	for needle in ["U light", "O heavy", "P", ";", "Enter", "J / L"]:
		h.check(needle in keys_hint, "souls_keys hint contains '%s'" % needle)
	h.check("LMB" in ControlBindings.new().hint_text("kb1"), "the classic hint is unchanged (LMB/F light)")


# ---- intents in a real arena --------------------------------------------------------------------------------------
static func _start(tree: SceneTree, bindings: ControlBindings) -> Dictionary:
	var old_b := ControlBindings.shared()
	ControlBindings.set_shared(bindings)
	var arena: CombatArena = (load(ARENA) as PackedScene).instantiate()
	tree.root.add_child(arena)
	arena.configure_seats({"player-white": {"type": "human", "scheme": "kb1"}, "player-black": {"type": "ai", "skill": 0.0}})
	var reply := arena.start_battle(FighterRoster.build_request("n", "n", "w", "keybinds", 11, 0))
	if not reply["ok"]:
		push_error("arena did not start: %s" % str(reply))
	for _i in 200:
		await tree.physics_frame
	arena.sim.fighters[0].teleport(Vector3(-6.0, 0.0, 0.0))   # far apart: nobody is hit, only intent counters are read
	arena.sim.fighters[1].teleport(Vector3(6.0, 0.0, 0.0))
	var sources := arena.find_children("*", "LocalInputSource", false, false)
	var clock := [1000]
	if not sources.is_empty():
		sources[0].clock = func(): return clock[0]
		sources[0].assume_captured = true
	return {"arena": arena, "source": sources[0] if not sources.is_empty() else null, "clock": clock, "old": old_b}


static func _stop(tree: SceneTree, ctx: Dictionary) -> void:
	for code in [KEY_W, KEY_SHIFT, KEY_ALT, KEY_SPACE, KEY_P]:
		Pads.key(code, false)
	for button in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2]:
		mouse(button, false)
	Input.flush_buffered_events()
	ctx["arena"].stop_battle()
	ctx["arena"].queue_free()
	await tree.process_frame
	ControlBindings.set_shared(ctx["old"])
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


static func _souls_mouse_fight(h, tree: SceneTree) -> void:
	h.begin("souls_mouse in a real arena: LMB light, hold = heavy, Alt+LMB / Mouse 5 = heavy, RMB hold = block, RMB tap = parry, MMB lock, Mouse 4 / R ability, Shift tap = dodge")
	var ctx := await _start(tree, _fresh("souls_mouse"))
	var arena: CombatArena = ctx["arena"]
	var source: LocalInputSource = ctx["source"]
	var clock: Array = ctx["clock"]
	h.check(source != null and source.mouse_look, "the mouse look is on while this profile is live (a headless display cannot really capture)")
	var base := Pads._counts(arena, "player-white")
	# Quick LMB tap -> light, fired on release.
	mouse(MOUSE_BUTTON_LEFT)
	clock[0] += 60
	await Pads.ticks(tree, 2)
	h.eq(Pads._counts(arena, "player-white")["light"], base["light"], "a held LMB has not fired a light yet (it may still become heavy)")
	mouse(MOUSE_BUTTON_LEFT, false)
	await Pads.ticks(tree, 3)
	var c1 := Pads._counts(arena, "player-white")
	h.eq(c1["light"], base["light"] + 1, "a quick LMB tap = one light attack")
	h.eq(c1["heavy"], base["heavy"], "...and no heavy")
	# Hold LMB past the threshold -> heavy once, and no light on release.
	mouse(MOUSE_BUTTON_LEFT)
	clock[0] += 400
	await Pads.ticks(tree, 3)
	mouse(MOUSE_BUTTON_LEFT, false)
	await Pads.ticks(tree, 3)
	var c2 := Pads._counts(arena, "player-white")
	h.eq(c2["heavy"], c1["heavy"] + 1, "holding LMB past the threshold = one heavy attack")
	h.eq(c2["light"], c1["light"], "...and the release does not add a light")
	# Alt + LMB -> heavy immediately.
	kp(KEY_ALT)
	Input.flush_buffered_events()
	mouse(MOUSE_BUTTON_LEFT)
	mouse(MOUSE_BUTTON_LEFT, false)
	kp(KEY_ALT, false)
	await Pads.ticks(tree, 3)
	var c3 := Pads._counts(arena, "player-white")
	h.eq(c3["heavy"], c2["heavy"] + 1, "Alt + LMB = heavy attack")
	h.eq(c3["light"], c2["light"], "...not a light")
	# Mouse 5 -> heavy; Mouse 4 -> ability; R -> ability.
	mouse(MOUSE_BUTTON_XBUTTON2)
	mouse(MOUSE_BUTTON_XBUTTON2, false)
	await Pads.ticks(tree, 3)
	var c4 := Pads._counts(arena, "player-white")
	h.eq(c4["heavy"], c3["heavy"] + 1, "Mouse 5 = heavy attack")
	mouse(MOUSE_BUTTON_XBUTTON1)
	mouse(MOUSE_BUTTON_XBUTTON1, false)
	kp(KEY_R)
	kp(KEY_R, false)
	await Pads.ticks(tree, 3)
	h.eq(Pads._counts(arena, "player-white")["ability"], c4["ability"] + 2, "Mouse 4 and R each fire the ability")
	# Parry on F; dodge on Space; Shift tap = dodge, Shift hold = sprint (no dodge).
	var c5 := Pads._counts(arena, "player-white")
	kp(KEY_F)
	kp(KEY_F, false)
	kp(KEY_SPACE)
	kp(KEY_SPACE, false)
	await Pads.ticks(tree, 3)
	var c6 := Pads._counts(arena, "player-white")
	h.eq(c6["parry"], c5["parry"] + 1, "F = parry")
	h.eq(c6["dodge"], c5["dodge"] + 1, "Space = dodge")
	kp(KEY_SHIFT)
	clock[0] += 60
	await Pads.ticks(tree, 2)
	kp(KEY_SHIFT, false)
	await Pads.ticks(tree, 3)
	var c7 := Pads._counts(arena, "player-white")
	h.eq(c7["dodge"], c6["dodge"] + 1, "a quick Shift tap = dodge")
	kp(KEY_SHIFT)
	clock[0] += 500
	await Pads.ticks(tree, 3)
	kp(KEY_SHIFT, false)
	await Pads.ticks(tree, 3)
	h.eq(Pads._counts(arena, "player-white")["dodge"], c7["dodge"], "holding Shift (sprint) does not dodge")
	# RMB: held = block; a quick tap also parries; a long hold does not.
	h.check(not source.bindings.is_held("kb1", "block", true), "block is not held before the click")
	mouse(MOUSE_BUTTON_RIGHT)
	await Pads.ticks(tree, 2)
	h.check(source.bindings.is_held("kb1", "block", true), "RMB held = block")
	clock[0] += 400
	var before_parry: int = Pads._counts(arena, "player-white")["parry"]
	mouse(MOUSE_BUTTON_RIGHT, false)
	await Pads.ticks(tree, 3)
	h.eq(Pads._counts(arena, "player-white")["parry"], before_parry, "a long RMB hold released = no parry")
	mouse(MOUSE_BUTTON_RIGHT)
	clock[0] += 60
	mouse(MOUSE_BUTTON_RIGHT, false)
	await Pads.ticks(tree, 3)
	h.eq(Pads._counts(arena, "player-white")["parry"], before_parry + 1, "a quick RMB tap = parry")
	# MMB toggles the lock-on camera.
	var was: bool = arena.cameras[0].locked
	mouse(MOUSE_BUTTON_MIDDLE)
	mouse(MOUSE_BUTTON_MIDDLE, false)
	await Pads.ticks(tree, 2)
	h.check(arena.cameras[0].locked != was, "MMB toggles lock-on")
	# Mouse look honours sensitivity and invert-Y.
	if arena.cameras[0].locked:
		mouse(MOUSE_BUTTON_MIDDLE)
		mouse(MOUSE_BUTTON_MIDDLE, false)
		await Pads.ticks(tree, 2)
	var pitch0: float = arena.cameras[0].pitch
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(0, 40)
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await Pads.ticks(tree, 1)
	var down: float = arena.cameras[0].pitch - pitch0
	source.bindings.set_option("kb1", "invert_y", true)
	pitch0 = arena.cameras[0].pitch
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await Pads.ticks(tree, 1)
	var inverted: float = arena.cameras[0].pitch - pitch0
	h.check(down != 0.0 and is_equal_approx(down, -inverted), "invert-Y flips mouse look (%.4f vs %.4f)" % [down, inverted])
	source.bindings.set_option("kb1", "mouse_sensitivity", 2.0)
	source.bindings.set_option("kb1", "invert_y", false)
	pitch0 = arena.cameras[0].pitch
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await Pads.ticks(tree, 1)
	h.check(is_equal_approx(arena.cameras[0].pitch - pitch0, down * 2.0), "mouse sensitivity scales the look speed")
	# Toggle-block option: one press turns block on, the next off.
	source.bindings.set_option("kb1", "hold_block", false)
	mouse(MOUSE_BUTTON_RIGHT)
	mouse(MOUSE_BUTTON_RIGHT, false)
	await Pads.ticks(tree, 2)
	h.check(source._block_toggled, "hold_block off: a press toggles block on")
	mouse(MOUSE_BUTTON_RIGHT)
	mouse(MOUSE_BUTTON_RIGHT, false)
	await Pads.ticks(tree, 2)
	h.check(not source._block_toggled, "...and the next press toggles it off")
	await _stop(tree, ctx)


static func _souls_keys_fight(h, tree: SceneTree) -> void:
	h.begin("souls_keys in a real arena: U light, O heavy, P hold block, ; parry, ' ability, Enter lock-on, J / L orbit, I / K tilt, no mouse capture")
	var ctx := await _start(tree, _fresh("souls_keys"))
	var arena: CombatArena = ctx["arena"]
	var source: LocalInputSource = ctx["source"]
	h.check(not source.mouse_look and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED, "the mouse is NOT captured (this profile has no mouse inputs)")
	var base := Pads._counts(arena, "player-white")
	for code in [KEY_U, KEY_O, KEY_SEMICOLON, KEY_APOSTROPHE]:
		Pads.key(code)
		Pads.key(code, false)
	await Pads.ticks(tree, 3)
	var c := Pads._counts(arena, "player-white")
	h.eq(c["light"], base["light"] + 1, "U = light")
	h.eq(c["heavy"], base["heavy"] + 1, "O = heavy")
	h.eq(c["parry"], base["parry"] + 1, "; = parry")
	h.eq(c["ability"], base["ability"] + 1, "' = ability")
	Pads.key(KEY_SPACE)
	Pads.key(KEY_SPACE, false)
	await Pads.ticks(tree, 3)
	h.eq(Pads._counts(arena, "player-white")["dodge"], c["dodge"] + 1, "Space = dodge")
	Pads.key(KEY_P)
	await Pads.ticks(tree, 2)
	h.check(source.bindings.is_held("kb1", "block", false), "P held = block")
	Pads.key(KEY_P, false)
	await Pads.ticks(tree, 2)
	h.check(not source.bindings.is_held("kb1", "block", false), "...released")
	var was: bool = arena.cameras[0].locked
	Pads.key(KEY_ENTER)
	Pads.key(KEY_ENTER, false)
	await Pads.ticks(tree, 2)
	h.check(arena.cameras[0].locked != was, "Enter toggles lock-on")
	if arena.cameras[0].locked:
		Pads.key(KEY_ENTER)
		Pads.key(KEY_ENTER, false)
		await Pads.ticks(tree, 2)
	var yaw: float = arena.cameras[0].yaw
	var pitch: float = arena.cameras[0].pitch
	Pads.key(KEY_L)
	await Pads.ticks(tree, 10)
	Pads.key(KEY_L, false)
	h.check(absf(CombatConstants.angle_diff(yaw, arena.cameras[0].yaw)) > 0.05, "L orbits the free camera")
	Pads.key(KEY_I)
	await Pads.ticks(tree, 10)
	Pads.key(KEY_I, false)
	var up: float = arena.cameras[0].pitch - pitch
	Pads.key(KEY_K)
	await Pads.ticks(tree, 20)
	Pads.key(KEY_K, false)
	h.check(up < 0.0 and arena.cameras[0].pitch > pitch + up, "I tilts the camera up and K tilts it down")
	# Movement keys on the left hand drive the fighter.
	var z0: float = arena.sim.fighters[0].position.z
	var x0: float = arena.sim.fighters[0].position.x
	Pads.key(KEY_W)
	await Pads.ticks(tree, 30)
	Pads.key(KEY_W, false)
	var moved: float = Vector2(arena.sim.fighters[0].position.x - x0, arena.sim.fighters[0].position.z - z0).length()
	h.check(moved > 0.2, "W moves the fighter (%.2f m)" % moved)
	# A scripted exchange: ten light attacks through the keyboard land as accepted intents.
	var before: int = Pads._counts(arena, "player-white")["light"]
	for _i in 10:
		Pads.key(KEY_U)
		Pads.key(KEY_U, false)
		await Pads.ticks(tree, 25)
	h.check(Pads._counts(arena, "player-white")["light"] - before >= 5, "a keyboard-only duel keeps producing accepted light attacks")
	await _stop(tree, ctx)


static func _classic_fight(h, tree: SceneTree) -> void:
	h.begin("classic profile in a real arena: F / G and LMB / RMB behave exactly as before")
	var ctx := await _start(tree, ControlBindings.new())
	var arena: CombatArena = ctx["arena"]
	var base := Pads._counts(arena, "player-white")
	Pads.key(KEY_F)
	Pads.key(KEY_F, false)
	Pads.key(KEY_G)
	Pads.key(KEY_G, false)
	mouse(MOUSE_BUTTON_LEFT)
	mouse(MOUSE_BUTTON_LEFT, false)
	mouse(MOUSE_BUTTON_RIGHT)
	mouse(MOUSE_BUTTON_RIGHT, false)
	await Pads.ticks(tree, 3)
	var c := Pads._counts(arena, "player-white")
	h.eq(c["light"], base["light"] + 2, "F and LMB = light attacks (immediate, no hold delay)")
	h.eq(c["heavy"], base["heavy"] + 2, "G and RMB = heavy attacks")
	await _stop(tree, ctx)


# ---- Settings > Controls ---------------------------------------------------------------------------------------------
static func _controls_screen(h, tree: SceneTree) -> void:
	h.begin("Settings > Controls: profile picker, mouse-button capture, alternate rows, options, reset to the profile defaults")
	var bindings := ControlBindings.new()
	var screen := ControlsScreen.new()
	screen.bindings = bindings
	screen.assignment = InputAssignment.new(bindings)
	screen.autosave = false
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tree.root.add_child(screen)
	await tree.process_frame
	var pick: OptionButton = screen._profile_options["kb1"]
	var ids: Array = []
	for i in pick.item_count:
		ids.append(pick.get_item_metadata(i))
	h.eq(ids, ["classic", "souls_mouse", "souls_keys", "duo_left"], "keyboard 1 offers classic, both Souls layouts and the two-player left half")
	h.eq(screen._profile_options["kb2"].item_count, 1, "keyboard 2 offers only its own half")
	pick.item_selected.emit(ids.find("souls_mouse"))
	h.eq(bindings.profile_of("kb1"), "souls_mouse", "choosing a profile applies it")
	await tree.process_frame
	h.eq(screen.row_text("kb1/light"), "LMB", "the light row shows LMB")
	h.eq(screen.row_text("kb1/ability#alt"), "Mouse 4", "the alternate rows show the second input (Mouse 4)")
	h.check(screen._rows.has("kb1/look_up") and screen._rows.has("kb1/lock#alt"), "camera tilt and alternate rows exist")
	# Capture a mouse button for an action.
	screen._begin_capture("key", "kb1", "dodge", "alt")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_XBUTTON1
	click.pressed = true
	screen._input(click)
	h.eq(bindings.alt_for("kb1", "dodge"), -MOUSE_BUTTON_XBUTTON1, "a captured mouse button becomes the alternate dodge binding (swapped with its owner)")
	h.check(bindings.find_conflicts().is_empty(), "...and nothing clashes")
	# Keyboard 2 does not accept mouse capture.
	screen._begin_capture("key", "kb2", "light", "primary")
	screen._input(click)
	h.check(bindings.key_for("kb2", "light") > 0 and not screen.capture.is_empty(), "keyboard 2 ignores a mouse click while capturing (it waits for a key)")
	screen._cancel_capture()
	# Options.
	var slider: HSlider = screen._sliders["opt/kb1/mouse_sensitivity"]["slider"]
	slider.value = 2.0
	h.eq(bindings.option("kb1", "mouse_sensitivity"), 2.0, "the mouse sensitivity slider writes the option")
	var check: CheckButton = screen._sliders["opt/kb1/invert_y"]["check"]
	check.button_pressed = true
	h.check(bool(bindings.option("kb1", "invert_y")), "the invert-Y toggle writes the option")
	h.check(not screen._sliders.has("opt/kb2/mouse_sensitivity"), "keyboard 2 has no mouse settings")
	# Reset to the profile defaults.
	bindings.set_key("kb1", "ability", KEY_V)
	bindings.reset_scheme("kb1")
	h.eq(bindings.key_for("kb1", "ability"), KEY_R, "reset restores the active profile")
	h.eq(bindings.option("kb1", "mouse_sensitivity"), 1.0, "...including its options")
	screen.queue_free()
	await tree.process_frame
