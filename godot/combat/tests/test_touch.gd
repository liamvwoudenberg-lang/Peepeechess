extends RefCounted
## Landscape touch controls: layout, joystick, multi-touch correctness, cancel/focus loss, emulated-mouse
## filtering and a touch-driven fight through a real CombatArena. No physical Android device was available:
## everything here uses injected Godot touch events.

const TouchControls := preload("res://combat/presentation/touch_controls.gd")
const ARENA := "res://combat/arena.tscn"
const S := CombatConstants.State
const RESOLUTIONS: Array = [Vector2(1280, 720), Vector2(1920, 1080), Vector2(2400, 1080), Vector2(2560, 1080), Vector2(1600, 720)]


static func run(h, tree: SceneTree) -> void:
	_layout(h)
	await _joystick(h, tree)
	await _buttons(h, tree)
	await _simultaneous(h, tree)
	await _cancel_and_focus(h, tree)
	await _many_fingers(h, tree)
	await _ability_display(h, tree)
	await _arena_integration(h, tree)


# ---- helpers --------------------------------------------------------------------------------------------
static func _make(tree: SceneTree, view: Vector2, scale: float = 1.0, safe: Rect2 = Rect2()):
	var c = TouchControls.new()
	tree.root.add_child(c)
	c.set_anchors_preset(Control.PRESET_TOP_LEFT)
	c.position = Vector2.ZERO
	c.size = view
	c.ui_scale = scale
	c.safe_area_override = safe
	return c


static func _tap(c, index: int, pos: Vector2, pressed: bool = true, canceled: bool = false) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	e.canceled = canceled
	c._input(e)


static func _drag(c, index: int, pos: Vector2, relative: Vector2 = Vector2.ZERO) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	e.relative = relative
	c._input(e)


static func _center(c, id: String) -> Vector2:
	return c.layout()["buttons"][id]["center"]


static func _stick_start(c) -> Vector2:
	var zone: Rect2 = c.layout()["stick"]["zone"]
	return zone.position + zone.size * Vector2(0.5, 0.6)


static func _circles_overlap(a: Dictionary, b: Dictionary) -> bool:
	return (a["center"] as Vector2).distance_to(b["center"]) < float(a["radius"]) + float(b["radius"]) - 0.01


# ---- layout ---------------------------------------------------------------------------------------------
static func _layout(h) -> void:
	h.begin("touch layout: no overlap, inside the safe area, big enough, centre clear (5 resolutions x insets x scales)")
	var overlaps := 0
	var outside := 0
	var too_small := 0
	var centre_blocked := 0
	var zone_clash := 0
	var configs := 0
	for view in RESOLUTIONS:
		var safes: Array = [Rect2(Vector2.ZERO, view), Rect2(Vector2(view.x * 0.04, 0.0), Vector2(view.x * 0.92, view.y - 48.0))]
		for safe in safes:
			for scale in [0.8, 1.0, 1.15, 1.3]:
				configs += 1
				var lay: Dictionary = TouchControls.compute_layout(view, safe, scale)
				var buttons: Dictionary = lay["buttons"]
				var ids: Array = buttons.keys()
				var stick: Dictionary = lay["stick"]
				var stick_circle := {"center": stick["center"], "radius": stick["radius"]}
				for i in ids.size():
					var a: Dictionary = buttons[ids[i]]
					if float(a["radius"]) * 2.0 < view.y * 0.09 - 0.01:
						too_small += 1
					var box := Rect2((a["center"] as Vector2) - Vector2.ONE * float(a["radius"]), Vector2.ONE * float(a["radius"]) * 2.0)
					if not (safe as Rect2).grow(0.5).encloses(box):
						outside += 1
					if _circles_overlap(a, stick_circle):
						overlaps += 1
					if (stick["zone"] as Rect2).intersects(box):
						zone_clash += 1
					if scale <= 1.0 and Rect2(view * Vector2(0.35, 0.2), view * Vector2(0.30, 0.6)).intersects(box):
						centre_blocked += 1
					for j in range(i + 1, ids.size()):
						if _circles_overlap(a, buttons[ids[j]]):
							overlaps += 1
				var stick_box := Rect2((stick["center"] as Vector2) - Vector2.ONE * float(stick["radius"]), Vector2.ONE * float(stick["radius"]) * 2.0)
				if not (safe as Rect2).grow(0.5).encloses(stick_box):
					outside += 1
				if scale <= 1.0 and Rect2(view * Vector2(0.35, 0.2), view * Vector2(0.30, 0.6)).intersects(stick_box):
					centre_blocked += 1
	h.check(configs == 40, "%d layouts evaluated" % configs)
	h.eq(overlaps, 0, "no two controls (incl. the stick base) overlap")
	h.eq(outside, 0, "every control stays inside the safe area")
	h.eq(too_small, 0, "every button is at least 9% of the screen height across")
	h.eq(zone_clash, 0, "buttons never sit inside the joystick zone")
	h.eq(centre_blocked, 0, "the central 30% x 60% of the screen is free of visible controls (scale <= 1.0)")

	h.begin("touch layout: sizes scale with screen height and the user scale, within the clamps")
	var lay720: Dictionary = TouchControls.compute_layout(Vector2(1280, 720), Rect2(), 1.0)
	var lay1080: Dictionary = TouchControls.compute_layout(Vector2(2400, 1080), Rect2(), 1.0)
	h.near(float(lay720["d"]) / 720.0, TouchControls.BUTTON_FRACTION, 0.0005, "unit = 11.5% of the height at 720p")
	h.near(float(lay1080["d"]) / 1080.0, TouchControls.BUTTON_FRACTION, 0.0005, "...and at 1080p")
	h.near(float(TouchControls.compute_layout(Vector2(1280, 720), Rect2(), 0.1)["d"]) / 720.0, TouchControls.MIN_FRACTION, 0.0005, "user scale is clamped at the 9% minimum")
	h.near(float(TouchControls.compute_layout(Vector2(1280, 720), Rect2(), 9.0)["d"]) / 720.0, TouchControls.MAX_FRACTION, 0.0005, "...and at the 16% maximum")
	var light: Dictionary = lay1080["buttons"]["light"]
	h.check(float(light["radius"]) * 2.0 / 1080.0 >= 0.11, "the primary LIGHT button is at least 11% of the height")
	h.check((light["center"] as Vector2).x > 2400.0 * 0.8 and (light["center"] as Vector2).y > 1080.0 * 0.7, "LIGHT sits in the bottom-right thumb corner")
	var stick: Dictionary = lay1080["stick"]
	h.check((stick["center"] as Vector2).x < 2400.0 * 0.25 and (stick["center"] as Vector2).y > 1080.0 * 0.6, "the stick rests bottom-left")
	h.check(lay1080["buttons"].has("pause") and lay1080["buttons"].has("lock") and lay1080["buttons"].has("block") and lay1080["buttons"].has("ability"), "pause, lock, block and special all exist")


# ---- joystick -------------------------------------------------------------------------------------------
static func _joystick(h, tree: SceneTree) -> void:
	h.begin("joystick: dead zone, smooth curve, sprint at the rim with hysteresis, floating origin")
	var c = _make(tree, Vector2(1920, 1080))
	var origin: Vector2 = _stick_start(c)
	var radius: float = c.layout()["stick"]["radius"]
	_tap(c, 0, origin)
	h.eq(c.finger_count(), 1, "a touch in the stick zone becomes the joystick finger")
	h.eq(c.move_vector, Vector2.ZERO, "no movement at the touch point")
	_drag(c, 0, origin + Vector2(radius * 0.10, 0.0))
	h.eq(c.move_vector, Vector2.ZERO, "inside the dead zone (10% throw) nothing moves")
	_drag(c, 0, origin + Vector2(radius * 0.5, 0.0))
	var expected := pow((0.5 - TouchControls.DEADZONE) / (1.0 - TouchControls.DEADZONE), TouchControls.RESPONSE_EXPONENT)
	h.near(c.move_vector.x, expected, 0.005, "50%% throw right -> smooth curve value %.3f" % expected)
	h.near(c.move_vector.y, 0.0, 0.001, "no forward component")
	_drag(c, 0, origin + Vector2(0.0, -radius * 0.7))
	h.check(c.move_vector.y > 0.0 and absf(c.move_vector.x) < 0.001, "dragging UP is forward (+y)")
	_drag(c, 0, origin + Vector2(0.0, radius * 0.7))
	h.check(c.move_vector.y < 0.0, "dragging down is backward")
	var a := origin + Vector2(radius * 0.7, 0.0)
	var b := origin + Vector2(radius * 0.7, -radius * 0.7)
	_drag(c, 0, a)
	var mid: float = c.move_vector.length()
	_drag(c, 0, origin + Vector2(radius * 3.0, 0.0))
	h.near(c.move_vector.length(), 1.0, 0.001, "pulled far beyond the rim: full speed, never above 1")
	h.check(c.move_vector.length() > mid, "the response is monotonic")
	_drag(c, 0, origin + Vector2(0.0, -radius * 0.95))
	h.check(c.sprint, "95% throw sprints")
	_drag(c, 0, origin + Vector2(0.0, -radius * 0.85))
	h.check(c.sprint, "85% throw keeps sprinting (hysteresis)")
	_drag(c, 0, origin + Vector2(0.0, -radius * 0.7))
	h.check(not c.sprint, "70% throw stops sprinting")
	_drag(c, 0, origin + Vector2(0.0, -radius * 0.85))
	h.check(not c.sprint, "85% does NOT restart sprint (needs 92%)")
	_tap(c, 0, origin, false)
	h.eq(c.move_vector, Vector2.ZERO, "lifting the finger stops")
	h.check(not c.sprint, "and clears sprint")
	h.eq(c.finger_count(), 0, "no fingers left")
	# Floating: a second touch elsewhere in the zone gets its own origin.
	var other: Vector2 = origin + Vector2(60.0, 30.0)
	_tap(c, 1, other)
	_drag(c, 1, other + Vector2(radius * 0.6, 0.0))
	h.check(c.move_vector.x > 0.2, "the stick origin floats to wherever the finger lands")
	_tap(c, 2, other + Vector2(30, 10))
	h.eq(c.finger_count(), 1, "a second finger in the stick zone is ignored (not turned into a camera drag)")
	c.queue_free()


# ---- buttons --------------------------------------------------------------------------------------------
static func _buttons(h, tree: SceneTree) -> void:
	h.begin("buttons: one action per tap, block holds, lock/pause fire once, camera drag emits deltas")
	var c = _make(tree, Vector2(1920, 1080))
	var actions: Array = []
	var locks := [0]
	var pauses := [0]
	var looks: Array = []
	c.action_pressed.connect(func(a): actions.append(a))
	c.lock_pressed.connect(func(): locks[0] += 1)
	c.pause_pressed.connect(func(): pauses[0] += 1)
	c.look_delta.connect(func(d): looks.append(d))
	for id in ["light", "heavy", "dodge", "parry", "ability"]:
		_tap(c, 0, _center(c, id))
		_tap(c, 0, _center(c, id), false)
	h.eq(actions, ["light", "heavy", "dodge", "parry", "ability"], "each action button fires exactly once per tap (press only, not release)")
	_tap(c, 0, _center(c, "light"))
	_drag(c, 0, _center(c, "light") + Vector2(40, 40))
	_drag(c, 0, _center(c, "light") + Vector2(80, 80))
	_tap(c, 0, _center(c, "light"), false)
	h.eq(actions.size(), 6, "dragging a held action finger does not repeat it")
	h.check(not c.block_held, "block is up by default")
	_tap(c, 0, _center(c, "block"))
	h.check(c.block_held, "touching BLOCK holds it")
	_drag(c, 0, Vector2(900, 500))
	h.check(c.block_held, "sliding the thumb OFF the button keeps the guard up (finger stays bound)")
	_tap(c, 0, Vector2(900, 500), false)
	h.check(not c.block_held, "lifting that finger lowers it")
	_tap(c, 0, _center(c, "lock"))
	_tap(c, 0, _center(c, "lock"), false)
	h.eq(locks[0], 1, "LOCK toggles once per tap")
	_tap(c, 0, _center(c, "pause"))
	_tap(c, 0, _center(c, "pause"), false)
	h.eq(pauses[0], 1, "PAUSE fires once")
	_tap(c, 3, Vector2(1000, 300))
	_drag(c, 3, Vector2(1010, 305), Vector2(10, 5))
	_drag(c, 3, Vector2(1030, 300), Vector2(20, -5))
	_tap(c, 3, Vector2(1030, 300), false)
	h.eq(looks.size(), 2, "the camera finger emits one delta per drag")
	h.eq(looks[0] + looks[1], Vector2(30, 0), "...with the exact relative motion")
	h.eq(actions.size(), 6, "camera drags never press buttons")

	h.begin("buttons: hit areas have slop and overlapping touches go to the nearest centre")
	var light_b: Dictionary = c.layout()["buttons"]["light"]
	var just_outside: Vector2 = (light_b["center"] as Vector2) + Vector2(float(light_b["radius"]) * 1.08, 0.0)
	h.eq(c.button_at(just_outside), "light", "8% outside the circle still hits (forgiving)")
	h.eq(c.button_at((light_b["center"] as Vector2) + Vector2(float(light_b["radius"]) * 1.4, 0.0)), "", "far outside hits nothing")
	h.eq(c.button_at(Vector2(960, 540)), "", "the screen centre is not a button")
	c.queue_free()


# ---- simultaneous ---------------------------------------------------------------------------------------
static func _simultaneous(h, tree: SceneTree) -> void:
	h.begin("simultaneous: move + block-hold + camera drag + attack taps all work together")
	var c = _make(tree, Vector2(2400, 1080))
	var actions: Array = []
	var look_total := [Vector2.ZERO]
	c.action_pressed.connect(func(a): actions.append(a))
	c.look_delta.connect(func(d): look_total[0] += d)
	var origin: Vector2 = _stick_start(c)
	var radius: float = c.layout()["stick"]["radius"]
	_tap(c, 0, origin)
	_drag(c, 0, origin + Vector2(0.0, -radius * 0.8))
	_tap(c, 1, _center(c, "block"))
	_tap(c, 2, Vector2(1300, 400))
	_drag(c, 2, Vector2(1340, 410), Vector2(40, 10))
	_tap(c, 3, _center(c, "light"))
	_tap(c, 3, _center(c, "light"), false)
	_tap(c, 3, _center(c, "heavy"))
	_tap(c, 3, _center(c, "heavy"), false)
	h.check(c.move_vector.y > 0.5, "the stick still drives movement")
	h.check(c.block_held, "block is still held")
	h.eq(look_total[0], Vector2(40, 10), "the camera drag was delivered")
	h.eq(actions, ["light", "heavy"], "both taps registered, once each")
	h.eq(c.finger_count(), 3, "three fingers remain down")
	_drag(c, 0, origin + Vector2(0.0, -radius * 0.82))
	_drag(c, 2, Vector2(1350, 412), Vector2(10, 2))
	h.eq(look_total[0], Vector2(50, 12), "the camera finger keeps working after the taps")
	c.queue_free()

	h.begin("simultaneous: any release order leaves the other fingers untouched and ends clean (6 permutations)")
	var perms: Array = [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]
	var failures := 0
	for perm in perms:
		var d = _make(tree, Vector2(1920, 1080))
		var o: Vector2 = _stick_start(d)
		var r: float = d.layout()["stick"]["radius"]
		_tap(d, 10, o)
		_drag(d, 10, o + Vector2(0.0, -r * 0.9))
		_tap(d, 11, _center(d, "block"))
		_tap(d, 12, Vector2(1100, 350))
		var alive := {"stick": true, "block": true, "look": true}
		var fingers := {0: ["stick", 10], 1: ["block", 11], 2: ["look", 12]}
		for step in perm:
			var kind: String = fingers[step][0]
			_tap(d, int(fingers[step][1]), Vector2(500, 500), false)
			alive[kind] = false
			if (d.move_vector.y > 0.1) != alive["stick"]:
				failures += 1
			if d.block_held != alive["block"]:
				failures += 1
			var expected_fingers := int(alive["stick"]) + int(alive["block"]) + int(alive["look"])
			if d.finger_count() != expected_fingers:
				failures += 1
		if d.finger_count() != 0 or d.move_vector != Vector2.ZERO or d.block_held or d.sprint:
			failures += 1
		d.queue_free()
	h.eq(failures, 0, "no permutation cancelled another finger or left anything stuck")


# ---- cancel / focus -------------------------------------------------------------------------------------
static func _cancel_and_focus(h, tree: SceneTree) -> void:
	h.begin("cancelled touches, window focus loss and disabling release exactly what they should")
	var c = _make(tree, Vector2(1920, 1080))
	var origin: Vector2 = _stick_start(c)
	var radius: float = c.layout()["stick"]["radius"]
	_tap(c, 0, origin)
	_drag(c, 0, origin + Vector2(radius * 0.9, 0.0))
	_tap(c, 1, _center(c, "block"))
	h.check(c.block_held and c.move_vector.x > 0.3, "stick + block active")
	_tap(c, 1, _center(c, "block"), false, true)  # the system cancelled the block finger
	h.check(not c.block_held, "a cancelled touch releases its button")
	h.check(c.move_vector.x > 0.3, "...without touching the stick finger")
	_tap(c, 1, _center(c, "block"))
	c.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	h.check(not c.block_held and c.move_vector == Vector2.ZERO and c.finger_count() == 0 and not c.sprint, "losing application focus releases everything (no stuck block or stick)")
	_tap(c, 0, origin)
	_drag(c, 0, origin + Vector2(radius, 0.0))
	c.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	h.check(c.move_vector == Vector2.ZERO and c.finger_count() == 0, "window focus loss does too")
	_tap(c, 5, _center(c, "block"))
	c.enabled = false
	h.check(not c.block_held and c.finger_count() == 0 and not c.visible, "disabling the control releases and hides it")
	var actions: Array = []
	c.action_pressed.connect(func(a): actions.append(a))
	_tap(c, 6, _center(c, "light"))
	h.eq(actions.size(), 0, "a disabled control ignores touches")
	c.enabled = true
	_tap(c, 6, _center(c, "light"))
	h.eq(actions, ["light"], "and works again once re-enabled")
	c.queue_free()


# ---- many fingers ---------------------------------------------------------------------------------------
static func _many_fingers(h, tree: SceneTree) -> void:
	h.begin("ten fingers: random presses, drags and releases never crash or leave state behind")
	var c = _make(tree, Vector2(2400, 1080))
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var taps := [0]
	c.action_pressed.connect(func(_a): taps[0] += 1)
	for round in 5:
		for i in 10:
			_tap(c, i, Vector2(rng.randf() * 2400.0, rng.randf() * 1080.0))
		for i in 10:
			_drag(c, i, Vector2(rng.randf() * 2400.0, rng.randf() * 1080.0), Vector2(rng.randf_range(-20, 20), rng.randf_range(-20, 20)))
		h.check(c.finger_count() <= 10, "never more tracked fingers than touches (%d)" % c.finger_count())
		h.check(c.move_vector.length() <= 1.0001, "move vector stays within the unit disc")
		var order := range(10)
		order.shuffle()
		for i in order:
			_tap(c, i, Vector2.ZERO, false)
	h.eq(c.finger_count(), 0, "all released")
	h.check(c.move_vector == Vector2.ZERO and not c.block_held and not c.sprint, "nothing stuck after 50 random touches")
	_tap(c, 0, _center(c, "light"))
	_tap(c, 0, _center(c, "light"), false)
	var before: int = taps[0]
	_tap(c, 0, _center(c, "light"))
	_tap(c, 0, _center(c, "light"), false)
	h.eq(taps[0], before + 1, "and a fresh tap still counts exactly once")
	c.queue_free()


# ---- ability display ------------------------------------------------------------------------------------
static func _ability_display(h, tree: SceneTree) -> void:
	h.begin("SPECIAL button: cooldown display is cosmetic and read-only")
	var c = _make(tree, Vector2(1920, 1080))
	h.near(c.ability_cooldown_fraction(), 0.0, 0.0001, "no callback -> ready")
	var state := {"cooldown": 300, "total": 900, "active": false}
	c.ability_state = func(): return state
	h.near(c.ability_cooldown_fraction(), 300.0 / 900.0, 0.0001, "300/900 ticks left -> 0.333")
	state["cooldown"] = 0
	h.near(c.ability_cooldown_fraction(), 0.0, 0.0001, "ready when the cooldown is 0")
	state["total"] = 0
	h.near(c.ability_cooldown_fraction(), 0.0, 0.0001, "a zero total never divides by zero")
	var actions: Array = []
	c.action_pressed.connect(func(a): actions.append(a))
	state["cooldown"] = 500
	state["total"] = 900
	_tap(c, 0, _center(c, "ability"))
	h.eq(actions, ["ability"], "a greyed button still sends the press: the server alone decides (and refuses)")
	c.queue_free()


# ---- integration ----------------------------------------------------------------------------------------
static func _arena_integration(h, tree: SceneTree) -> void:
	h.begin("integration: a touch-driven fight through a real CombatArena (stick, tap, block, camera), real input pipeline")
	var old_size: Vector2i = tree.root.size
	tree.root.size = Vector2i(1920, 1080)  # a headless root window is tiny; give the control a realistic landscape viewport
	var arena: CombatArena = (load(ARENA) as PackedScene).instantiate()
	tree.root.add_child(arena)
	arena.configure_seats({"player-white": {"type": "human", "scheme": "touch"}, "player-black": {"type": "ai", "skill": 0.0}})
	h.check(arena.start_battle(FighterRoster.build_request("n", "p", "w", "touch-1", 3, 0))["ok"], "the battle starts with a touch seat")
	var sources := arena.find_children("*", "LocalInputSource", false, false)
	if not h.eq(sources.size(), 1, "one LocalInputSource exists"):
		arena.queue_free()
		tree.root.size = old_size
		return
	var source = sources[0]
	var touch = source.touch
	h.check(touch != null and touch.get_parent() is CanvasLayer, "it owns a touch control on a CanvasLayer")
	h.eq((touch.get_parent() as CanvasLayer).layer, 20, "above the HUD (10), below menus (50)")
	for _i in 4:
		await tree.process_frame
	h.check(touch.size.x > 400.0 and touch.size.y > 200.0, "the control fills the viewport (%s)" % str(touch.size))
	var white: FighterController = arena.sim.fighters[0]
	for _i in 200:
		await tree.physics_frame
	h.eq(arena.sim.countdown_remaining, 0, "the countdown is over")
	arena.sim.fighters[1].teleport(Vector3(5.0, 0.0, 4.0))  # keep the AI out of the way for the first moments
	var start_pos: Vector3 = white.global_position

	# Real pipeline: events go through Input.parse_input_event -> viewport -> the control.
	var o: Vector2 = _stick_start(touch)
	var r: float = touch.layout()["stick"]["radius"]
	_pipe_touch(0, o, true)
	_pipe_drag(0, o + Vector2(0.0, -r * 0.9), Vector2(0.0, -r * 0.9))
	await _settle(tree)
	h.check(touch.move_vector.y > 0.5, "the injected stick drag reached the control through the viewport")
	var saw := {"moving": false, "attacking": false, "blocking": false}
	for _i in 40:
		await tree.physics_frame
		if white.sm.state == S.MOVING:
			saw["moving"] = true
	h.check(saw["moving"], "the fighter walked (state Moving)")
	h.check(white.global_position.distance_to(start_pos) > 0.5, "...and actually moved (%.2f m)" % white.global_position.distance_to(start_pos))

	# Tap LIGHT while still holding the stick (two simultaneous fingers).
	_pipe_touch(1, _center(touch, "light"), true)
	_pipe_touch(1, _center(touch, "light"), false)
	for _i in 12:
		await tree.physics_frame
		if white.sm.state == S.ATTACKING:
			saw["attacking"] = true
	h.check(saw["attacking"], "the light-attack tap started an attack while the stick was held")
	h.eq(int(arena.sim.accepted_input("player-white")["light"]), 1, "the server counted exactly ONE light press (emulated mouse events were not double-counted)")

	# Release the stick, wait out the attack, then hold BLOCK.
	_pipe_touch(0, o, false)
	for _i in 60:
		await tree.physics_frame
	_pipe_touch(2, _center(touch, "block"), true)
	for _i in 15:
		await tree.physics_frame
		if white.sm.state == S.BLOCKING:
			saw["blocking"] = true
	h.check(saw["blocking"], "holding BLOCK raised the guard")
	h.check(touch.block_held, "and the control reports it held")
	_pipe_touch(2, _center(touch, "block"), false)
	for _i in 8:
		await tree.physics_frame
	h.check(white.sm.state != S.BLOCKING, "releasing BLOCK lowers it")

	# Camera drag changes the free-look yaw only when unlocked.
	var cam: ThirdPersonCamera = arena.cameras[0]
	var lock_before: bool = cam.locked
	_pipe_touch(3, _center(touch, "lock"), true)
	_pipe_touch(3, _center(touch, "lock"), false)
	await _settle(tree)
	h.check(cam.locked != lock_before, "the LOCK button toggled the camera lock")
	var yaw_before: float = cam.yaw
	_pipe_touch(4, Vector2(touch.size.x * 0.55, touch.size.y * 0.3), true)
	_pipe_drag(4, Vector2(touch.size.x * 0.55 + 120.0, touch.size.y * 0.3), Vector2(120.0, 0.0))
	_pipe_touch(4, Vector2.ZERO, false)
	await _settle(tree)
	h.check(absf(CombatConstants.angle_diff(yaw_before, cam.yaw)) > 0.05, "a camera-finger drag orbited the free camera (%.2f rad)" % absf(CombatConstants.angle_diff(yaw_before, cam.yaw)))

	# Emulated mouse events (what Godot synthesises from touch) are ignored.
	var counter_before: int = int(arena.sim.accepted_input("player-white")["light"])
	var fake := InputEventMouseButton.new()
	fake.button_index = MOUSE_BUTTON_LEFT
	fake.pressed = true
	fake.device = InputEvent.DEVICE_ID_EMULATION
	source._unhandled_input(fake)
	for _i in 6:
		await tree.physics_frame
	h.eq(int(arena.sim.accepted_input("player-white")["light"]), counter_before, "an emulated mouse click does not attack")

	# Disabling the source (Codex's online view does this outside combat) hides and releases.
	source.enabled = false
	h.check(not touch.visible and touch.finger_count() == 0, "enabled=false hides the touch UI and releases it")
	arena.stop_battle()
	arena.queue_free()
	tree.root.size = old_size


## Parsed input is buffered and dispatched on the next frame(s); wait for it before asserting.
static func _settle(tree: SceneTree) -> void:
	await tree.process_frame
	await tree.process_frame


static func _pipe_touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	Input.parse_input_event(e)


static func _pipe_drag(index: int, pos: Vector2, relative: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	e.relative = relative
	Input.parse_input_event(e)
