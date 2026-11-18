class_name LocalInputSource
extends Node
## Turns keyboard / mouse / gamepad into contract-valid CombatInput packets, one per physics
## tick, and hands them to `submit` (the local authority or, later, a network adapter).
## It sends INTENT only: world-space move vector, facing, held flags and cumulative press
## counters. Project input maps are not touched (project.godot is Codex-owned): bindings are read
## from raw keys/buttons here, through `bindings` (ControlBindings; defaults = the old constants).
##
## Schemes: "kb1" WASD + mouse (or any other control profile, see ControlBindings.PROFILE_IDS), "kb2" arrow keys, "pad<device id>" gamepads (each pad is its own device: events
## and polling carry the device id, so two pads never cross-talk), "touch" virtual controls
## (presentation/touch_controls.gd, landscape multi-touch). Left stick / keys move
## relative to the camera; the camera converts to the world-space vector the contract expects.
## Mouse events synthesised from touch (device == DEVICE_ID_EMULATION) are always ignored here.
##
## Gamepad (SDL layout, DualShock 4 names): left stick move (radial dead zone), right stick camera, L2 sprint
## (hysteresis), L1 hold block, R1 parry, Cross dodge, Circle special, Square light, Triangle heavy, R2 heavy
## alias, L3 lock-on, Options pause (`pause_requested`). A pad that disconnects goes neutral (`pad_lost`).

## Defaults only; the live bindings come from `bindings` (ControlBindings, user://controls.json).
const SCHEMES := ControlBindings.DEFAULT_KEYS
const TouchControls := preload("res://combat/presentation/touch_controls.gd")
const MOUSE_SENSITIVITY := 0.0032
## Camera orbit for touch drags: radians per screen-height of finger travel.
const TOUCH_LOOK_RADIANS_PER_SCREEN := 4.5
const TOUCH_LAYER := 20  # above the HUD (10), below menus (50)

signal pause_requested
## Fired when this seat's pad vanishes (true) or comes back (false). The arena guard (PadHold) pauses on it.
signal pad_lost_changed(lost: bool)
const STICK_DEADZONE := PadMath.DEFAULT_INNER  # kept for old callers; the live value is bindings.pad_setting("deadzone")
const PAD_GROUP := "pad_combat_input"
const LOOK_YAW_PER_TICK := 0.05
const LOOK_PITCH_PER_TICK := 0.03

var scheme: String = "kb1"
var builder: CombatInputBuilder
var camera: ThirdPersonCamera
var fighter: FighterController
var submit: Callable
var mouse_look: bool = false
## Tests only: a headless display server cannot capture the mouse, so a test can declare it captured.
var assume_captured: bool = false
## Key/button map and pad tuning. Tests may give a private instance; the default is the process-wide one.
var bindings: ControlBindings = ControlBindings.shared()
## Source of "is this pad connected" (hot-plug). Default: the shared InputAssignment.
var assignment: InputAssignment = InputAssignment.shared()
## True while this seat's pad is disconnected: input is neutral and ignored (see PadHold).
var pad_lost: bool = false
## Online mode: intent and presses go to the CombatNetClient (which owns sequencing) instead of `builder`/`submit`.
var net_client = null
var enabled: bool = true:
	set(value):
		enabled = value
		if touch != null:
			touch.enabled = value  # also releases every held finger when disabled
## The virtual controls when scheme == "touch" (null otherwise).
var touch = null
var _touch_layer: CanvasLayer = null

## Millisecond clock for tap / hold decisions; tests inject their own (default: Time.get_ticks_msec).
var clock: Callable = Callable()
var _press_t: Dictionary = {}       # binding code -> msec of the press that is still down (tap / hold decisions)
var _pending_heavy: Dictionary = {} # binding code -> true while a light-attack press waits to become heavy (hold) or light (release)
var _block_toggled: bool = false    # hold_block == false: a press toggles block
var _attack_pressed_this_tick: bool = false
var _last_facing: float = 0.0
var _held_state: Dictionary = {}   # held action -> PadMath.Schmitt (axis-bound sprint/block)
var _edge_state: Dictionary = {}   # press action -> PadMath.Schmitt (axis-bound, e.g. R2 heavy alias)


func _ready() -> void:
	if scheme.begins_with("pad"):
		add_to_group(PAD_GROUP)  # PadUi stays out of the way of menus' focus while a pad fights (Cross is dodge there)
	if scheme != "touch":
		return
	_touch_layer = CanvasLayer.new()
	_touch_layer.layer = TOUCH_LAYER
	_touch_layer.name = "TouchLayer"
	touch = TouchControls.new()
	touch.name = "TouchControls"
	touch.enabled = enabled
	touch.ability_state = Callable(self, "_ability_state")
	touch.action_pressed.connect(_on_touch_action)
	touch.lock_pressed.connect(func(): if camera != null: camera.toggle_lock())
	touch.pause_pressed.connect(func(): pause_requested.emit())
	touch.look_delta.connect(_on_touch_look)
	_touch_layer.add_child(touch)
	add_child(_touch_layer)
	touch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)  # needs to be in the tree to resolve against the viewport
	# Haptics: in offline/authority mode the fighter's parent is the simulation, which emits combat events.
	if fighter != null and fighter.get_parent() != null and fighter.get_parent().has_signal("event_emitted"):
		fighter.get_parent().event_emitted.connect(_on_sim_event)


func _on_touch_action(action: String) -> void:
	if action == "light" or action == "heavy":
		_press(action)
	else:
		_do_press(action)


func _on_touch_look(delta: Vector2) -> void:
	if camera == null:
		return
	var h := maxf(float(get_viewport().get_visible_rect().size.y), 1.0)
	var k := TOUCH_LOOK_RADIANS_PER_SCREEN / h
	camera.add_look(delta.x * k, delta.y * k)


## Cosmetic ability state for the SPECIAL button (read-only).
func _ability_state() -> Dictionary:
	if fighter == null or not is_instance_valid(fighter):
		return {}
	return {"cooldown": fighter.ability.cooldown_remaining, "total": fighter.ability.cooldown_total, "active": fighter.ability.buff_active()}


func _on_sim_event(event: Dictionary) -> void:
	if touch == null or fighter == null or String(event.get("targetPlayerId", "")) != fighter.player_id:
		return
	match String(event.get("type", "")):
		"parry":
			touch.haptic(35)
		"guardbreak":
			touch.haptic(80)
		"hit":
			touch.haptic(20)


func _unhandled_input(event: InputEvent) -> void:
	# Godot turns touches into mouse events (emulate_mouse_from_touch). Those are never real mouse input.
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if scheme == "touch":
		return  # the virtual controls consume raw touch themselves
	if not enabled or (builder == null and net_client == null):
		return
	var keys: Dictionary = bindings.keys_for(scheme)
	var mouse_live := _mouse_live()
	if not keys.is_empty() and ((event is InputEventKey and not event.echo) or (event is InputEventMouseButton and mouse_live)):
		var code := _binding_code(event)
		if code != 0:
			if event.pressed:
				if not _code_pressed(code) and code < 0:
					match -code:   # unbound wheel = camera zoom (as before)
						MOUSE_BUTTON_WHEEL_UP:
							camera.zoom(-0.4)
						MOUSE_BUTTON_WHEEL_DOWN:
							camera.zoom(0.4)
			else:
				_code_released(code)
	elif event is InputEventMouseMotion and mouse_live:
		var k: float = MOUSE_SENSITIVITY * float(bindings.option(scheme, "mouse_sensitivity")) * float(bindings.option(scheme, "camera_sensitivity"))
		camera.add_look(event.relative.x * k * (-1.0 if bindings.option(scheme, "invert_x") else 1.0),
				event.relative.y * k * (-1.0 if bindings.option(scheme, "invert_y") else 1.0))
	elif event is InputEventJoypadButton and scheme.begins_with("pad") and event.device == _pad_device():
		if pad_lost:
			return
		if event.pressed:
			_pad_button_pressed(int(event.button_index))
	elif event is InputEventJoypadMotion and scheme.begins_with("pad") and event.device == _pad_device():
		if not pad_lost:
			_pad_axis_moved(int(event.axis), float(event.axis_value))


## Mouse buttons / motion count only while the mouse is captured for mouse-look (the cursor never fights the UI).
func _mouse_live() -> bool:
	return mouse_look and (assume_captured or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)


func _now() -> int:
	return int(clock.call()) if clock.is_valid() else Time.get_ticks_msec()


## Signed binding code of a key (physical, > 0) or mouse button event (-button, < 0).
func _binding_code(event: InputEvent) -> int:
	if event is InputEventKey:
		return int(event.physical_keycode)
	if event is InputEventMouseButton:
		return -int(event.button_index)
	return 0


## A bound input went down. Returns false if nothing is bound to it. Tap / hold options decide when the press becomes an intent.
func _code_pressed(code: int) -> bool:
	var actions := bindings.actions_for(scheme, code)
	if actions.is_empty():
		return false
	_press_t[code] = _now()
	for action in actions:
		match action:
			"light":
				if bool(bindings.option(scheme, "alt_heavy")) and Input.is_physical_key_pressed(KEY_ALT):
					_press("heavy")
				elif bool(bindings.option(scheme, "heavy_on_hold")):
					_pending_heavy[code] = true   # becomes light on a quick release, heavy once held long enough
				else:
					_press("light")
			"heavy":
				_press("heavy")
			"dodge", "parry", "ability":
				_do_press(action)
			"lock":
				if bool(bindings.option(scheme, "lock_hold")):
					if camera.locked:
						camera.toggle_lock()   # holding frees the camera
				else:
					camera.toggle_lock()
			"block":
				if not bool(bindings.option(scheme, "hold_block")):
					_block_toggled = not _block_toggled
				if bool(bindings.option(scheme, "parry_on_tap")) and Input.is_physical_key_pressed(KEY_SHIFT) and code < 0:
					_do_press("parry")   # Shift + block button = parry straight away
	return true


func _code_released(code: int) -> void:
	var held_ms := _now() - int(_press_t.get(code, _now()))
	_press_t.erase(code)
	if _pending_heavy.has(code):
		_pending_heavy.erase(code)
		_press("light")   # released before the hold threshold: it was a tap
	for action in bindings.actions_for(scheme, code):
		match action:
			"block":
				if bool(bindings.option(scheme, "parry_on_tap")) and held_ms < int(bindings.option(scheme, "parry_tap_ms")):
					_do_press("parry")
			"sprint":
				if bool(bindings.option(scheme, "sprint_tap_dodge")) and held_ms < int(bindings.option(scheme, "sprint_tap_ms")):
					_do_press("dodge")
			"lock":
				if bool(bindings.option(scheme, "lock_hold")) and not camera.locked:
					camera.toggle_lock()


## Turns holds into heavy attacks and releases lost to focus changes into releases; once per physics tick.
func _update_holds() -> void:
	var mouse_live := _mouse_live()
	for code in _press_t.keys():
		var down := Input.is_physical_key_pressed(code as Key) if code > 0 else (mouse_live and Input.is_mouse_button_pressed((-code) as MouseButton))
		if not down and not (code < 0 and (-code in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN])):
			_code_released(code)
	var hold_ms := int(bindings.option(scheme, "heavy_hold_ms"))
	for code in _pending_heavy.keys():
		if _now() - int(_press_t.get(code, _now())) >= hold_ms:
			_pending_heavy.erase(code)
			_press("heavy")


## One press edge from a pad button, routed through the binding map (several actions may share a button).
func _pad_button_pressed(button: int) -> void:
	if button == JOY_BUTTON_START:
		pause_requested.emit()
		return
	for action in ControlBindings.PAD_ACTIONS:
		var bound: Dictionary = bindings.pad_input(action)
		if bound.get("type", "") == "button" and int(bound["index"]) == button:
			_fire_pad_action(action)


## Axis-bound press actions (the R2 heavy alias, or whatever the player bound to a trigger) fire on the Schmitt edge.
func _pad_axis_moved(axis: int, value: float) -> void:
	for action in ControlBindings.PAD_ACTIONS:
		if action in ControlBindings.HELD_ACTIONS:
			continue
		var bound: Dictionary = bindings.pad_input(action)
		if bound.get("type", "") == "axis" and int(bound["index"]) == axis:
			if _schmitt(_edge_state, action).update(PadMath.trigger_value(value)):
				_fire_pad_action(action)


func _fire_pad_action(action: String) -> void:
	match action:
		"light":
			_press("light")
		"heavy", "heavy2":
			_press("heavy")
		"dodge", "parry", "ability":
			_do_press(action)
		"lock":
			if camera != null:
				camera.toggle_lock()


func _schmitt(store: Dictionary, action: String) -> PadMath.Schmitt:
	if not store.has(action):
		store[action] = PadMath.Schmitt.new(float(bindings.pad_setting("trigger_press")), float(bindings.pad_setting("trigger_release")))
	var state: PadMath.Schmitt = store[action]
	state.set_thresholds(float(bindings.pad_setting("trigger_press")), float(bindings.pad_setting("trigger_release")))
	return state


## Is the held action (sprint / block) active on this pad right now?
func _pad_held(device: int, action: String) -> bool:
	var bound: Dictionary = bindings.pad_input(action)
	if bound.is_empty():
		return false
	var index := int(bound["index"])
	if bound["type"] == "button":
		return Input.is_joy_button_pressed(device, index as JoyButton)
	var value := PadMath.trigger_value(Input.get_joy_axis(device, index as JoyAxis))
	_schmitt(_held_state, action).update(value)
	return _schmitt(_held_state, action).held


func _press(action: String) -> void:
	_do_press(action)
	_attack_pressed_this_tick = true


func _do_press(action: String) -> void:
	if net_client != null:
		net_client.press(action)
	elif builder != null:
		builder.press(action)


func _key_down(code: int) -> bool:
	return code > 0 and Input.is_physical_key_pressed(code as Key)


func _pad_device() -> int:
	return int(scheme.substr(3))


func _update_pad_presence() -> void:
	if not scheme.begins_with("pad"):
		return
	var lost := not assignment.is_pad_connected(_pad_device())
	if lost != pad_lost:
		pad_lost = lost
		_held_state.clear()
		_edge_state.clear()
		pad_lost_changed.emit(lost)


func _physics_process(_delta: float) -> void:
	_update_pad_presence()
	if not enabled or fighter == null or (net_client == null and (builder == null or not submit.is_valid())):
		return
	var move := Vector2.ZERO  # x = right, y = forward (screen/camera relative)
	var sprint := false
	var block := false
	var keys: Dictionary = bindings.keys_for(scheme)
	if not keys.is_empty():
		var mouse_live := _mouse_live()
		_update_holds()
		move.x = float(_key_down(keys.get("right", 0))) - float(_key_down(keys.get("left", 0)))
		move.y = float(_key_down(keys.get("up", 0))) - float(_key_down(keys.get("down", 0)))
		sprint = bindings.is_held(scheme, "sprint", mouse_live)
		block = bindings.is_held(scheme, "block", mouse_live) if bool(bindings.option(scheme, "hold_block")) else _block_toggled
		var cam_sens := float(bindings.option(scheme, "camera_sensitivity"))
		var orbit := float(_key_down(keys.get("orbit_r", 0))) - float(_key_down(keys.get("orbit_l", 0)))
		var tilt := float(_key_down(keys.get("look_down", 0))) - float(_key_down(keys.get("look_up", 0)))
		if orbit != 0.0 or tilt != 0.0:
			camera.add_look(orbit * 0.035 * cam_sens * (-1.0 if bindings.option(scheme, "invert_x") else 1.0),
					tilt * 0.02 * cam_sens * (-1.0 if bindings.option(scheme, "invert_y") else 1.0))
	elif scheme == "touch":
		if touch != null:
			move = touch.move_vector
			sprint = touch.sprint
			block = touch.block_held
			touch.lock_active = camera.locked
	elif not pad_lost:
		var dev := _pad_device()
		var inner := float(bindings.pad_setting("deadzone"))
		var outer := float(bindings.pad_setting("outer_deadzone"))
		var response := float(bindings.pad_setting("response"))
		move = PadMath.radial(Vector2(Input.get_joy_axis(dev, JOY_AXIS_LEFT_X), -Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y)), inner, outer, response)
		sprint = _pad_held(dev, "sprint")
		block = _pad_held(dev, "block")
		var look := PadMath.radial(Vector2(Input.get_joy_axis(dev, JOY_AXIS_RIGHT_X), Input.get_joy_axis(dev, JOY_AXIS_RIGHT_Y)), inner, outer, response)
		if look != Vector2.ZERO:
			var sens := float(bindings.pad_setting("look_sensitivity"))
			camera.add_look(look.x * LOOK_YAW_PER_TICK * sens * (-1.0 if bindings.pad_setting("invert_look_x") else 1.0),
					look.y * LOOK_PITCH_PER_TICK * sens * (-1.0 if bindings.pad_setting("invert_look_y") else 1.0))
	if move.length() > 1.0:
		move = move.normalized()

	# Camera-relative -> world-space (CONTRACTS.md: clients convert before submission).
	var heading := CombatConstants.heading(camera.view_heading())
	var right := Vector3(-heading.z, 0.0, heading.x)
	var world := heading * move.y + right * move.x

	var facing := fighter.yaw
	if move.length() > 0.1:
		facing = CombatConstants.yaw_of(world)
	elif _attack_pressed_this_tick and not camera.locked:
		facing = camera.view_heading()
	_last_facing = facing
	_attack_pressed_this_tick = false

	if net_client != null:
		net_client.set_intent(world.x, world.z, facing, camera.locked, sprint, block)
		return
	var packet := builder.build(world.x, world.z, facing, camera.locked, sprint, block)
	submit.call(packet)
