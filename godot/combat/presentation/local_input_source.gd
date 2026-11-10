class_name LocalInputSource
extends Node
## Turns keyboard / mouse / gamepad into contract-valid CombatInput packets, one per physics
## tick, and hands them to `submit` (the local authority or, later, a network adapter).
## It sends INTENT only: world-space move vector, facing, held flags and cumulative press
## counters. Project input maps are not touched (project.godot is Codex-owned): bindings are read
## from raw keys/buttons here.
##
## Schemes: "kb1" WASD + mouse, "kb2" arrow keys, "pad0"/"pad1" gamepads. Left stick / keys move
## relative to the camera; the camera converts to the world-space vector the contract expects.

const SCHEMES := {
	"kb1": {"up": KEY_W, "down": KEY_S, "left": KEY_A, "right": KEY_D, "sprint": KEY_SHIFT, "light": KEY_F, "heavy": KEY_G,
		"dodge": KEY_SPACE, "block": KEY_Q, "parry": KEY_E, "ability": KEY_R, "lock": KEY_TAB, "orbit_l": KEY_Z, "orbit_r": KEY_X},
	"kb2": {"up": KEY_UP, "down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT, "sprint": KEY_CTRL, "light": KEY_J, "heavy": KEY_K,
		"dodge": KEY_L, "block": KEY_U, "parry": KEY_I, "ability": KEY_O, "lock": KEY_P, "orbit_l": KEY_COMMA, "orbit_r": KEY_PERIOD},
}
const MOUSE_SENSITIVITY := 0.0032
const STICK_DEADZONE := 0.18

var scheme: String = "kb1"
var builder: CombatInputBuilder
var camera: ThirdPersonCamera
var fighter: FighterController
var submit: Callable
var mouse_look: bool = false
var enabled: bool = true

var _attack_pressed_this_tick: bool = false
var _last_facing: float = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if not enabled or builder == null:
		return
	var keys: Dictionary = SCHEMES.get(scheme, {})
	if event is InputEventKey and event.pressed and not event.echo and not keys.is_empty():
		var code: int = event.physical_keycode
		if code == keys["light"]:
			_press("light")
		elif code == keys["heavy"]:
			_press("heavy")
		elif code == keys["dodge"]:
			builder.press("dodge")
		elif code == keys["parry"]:
			builder.press("parry")
		elif code == keys["ability"]:
			builder.press("ability")
		elif code == keys["lock"]:
			camera.toggle_lock()
	elif event is InputEventMouseButton and event.pressed and mouse_look and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_press("light")
			MOUSE_BUTTON_RIGHT:
				_press("heavy")
			MOUSE_BUTTON_MIDDLE:
				camera.toggle_lock()
			MOUSE_BUTTON_WHEEL_UP:
				camera.zoom(-0.4)
			MOUSE_BUTTON_WHEEL_DOWN:
				camera.zoom(0.4)
	elif event is InputEventMouseMotion and mouse_look and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera.add_look(event.relative.x * MOUSE_SENSITIVITY, event.relative.y * MOUSE_SENSITIVITY)
	elif event is InputEventJoypadButton and event.pressed and scheme.begins_with("pad") and event.device == _pad_device():
		match event.button_index:
			JOY_BUTTON_X:
				_press("light")
			JOY_BUTTON_Y:
				_press("heavy")
			JOY_BUTTON_A:
				builder.press("dodge")
			JOY_BUTTON_RIGHT_SHOULDER:
				builder.press("parry")
			JOY_BUTTON_B:
				builder.press("ability")
			JOY_BUTTON_LEFT_STICK:
				camera.toggle_lock()


func _press(action: String) -> void:
	builder.press(action)
	_attack_pressed_this_tick = true


func _pad_device() -> int:
	return int(scheme.substr(3))


func _physics_process(_delta: float) -> void:
	if not enabled or builder == null or fighter == null or not submit.is_valid():
		return
	var move := Vector2.ZERO  # x = right, y = forward (screen/camera relative)
	var sprint := false
	var block := false
	var keys: Dictionary = SCHEMES.get(scheme, {})
	if not keys.is_empty():
		move.x = float(Input.is_physical_key_pressed(keys["right"])) - float(Input.is_physical_key_pressed(keys["left"]))
		move.y = float(Input.is_physical_key_pressed(keys["up"])) - float(Input.is_physical_key_pressed(keys["down"]))
		sprint = Input.is_physical_key_pressed(keys["sprint"])
		block = Input.is_physical_key_pressed(keys["block"])
		var orbit := float(Input.is_physical_key_pressed(keys["orbit_r"])) - float(Input.is_physical_key_pressed(keys["orbit_l"]))
		if orbit != 0.0:
			camera.add_look(orbit * 0.035, 0.0)
	else:
		var dev := _pad_device()
		move = Vector2(Input.get_joy_axis(dev, JOY_AXIS_LEFT_X), -Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y))
		if move.length() < STICK_DEADZONE:
			move = Vector2.ZERO
		sprint = Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_LEFT) > 0.5
		block = Input.is_joy_button_pressed(dev, JOY_BUTTON_LEFT_SHOULDER)
		var look := Vector2(Input.get_joy_axis(dev, JOY_AXIS_RIGHT_X), Input.get_joy_axis(dev, JOY_AXIS_RIGHT_Y))
		if look.length() > STICK_DEADZONE:
			camera.add_look(look.x * 0.05, look.y * 0.03)
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

	var packet := builder.build(world.x, world.z, facing, camera.locked, sprint, block)
	submit.call(packet)
