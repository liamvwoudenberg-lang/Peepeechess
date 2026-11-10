class_name PlatformInput
extends Node
## Device-independent presentation controls. Never changes clocks or simulation ticks.
## Add once under the SceneTree root. Disable the pointer while combat owns the pad.

const CURSOR_SPEED := 720.0
const DEADZONE := 0.22
var cursor_enabled := true
var cursor_position := Vector2(600, 400)
var _cursor_visible := false
var _layer: CanvasLayer
var _marker: Control
var _pressed := false
static var quality := "balanced"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ensure_actions()
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)
	_marker = Control.new()
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.draw.connect(_draw_pointer)
	_layer.add_child(_marker)
	_marker.hide()
	get_tree().node_added.connect(_quality_node_added)
	set_quality(quality)

static func ensure_actions() -> void:
	# Standard Godot UI actions already support d-pad, A/B, keyboard and mouse.
	# Explicit app actions are available without assuming a controller is present.
	for item in [["app_menu", JOY_BUTTON_START], ["app_back", JOY_BUTTON_B]]:
		if not InputMap.has_action(item[0]):
			InputMap.add_action(item[0])
			var button := InputEventJoypadButton.new()
			button.button_index = item[1]
			InputMap.action_add_event(item[0], button)

static func set_quality(level: String) -> void:
	quality = level if level in ["low", "balanced", "medium", "high"] else "balanced"
	if quality == "medium":
		quality = "balanced"
	# Presentation limits only: fixed physics/server ticks remain 60 Hz.
	Engine.max_fps = 30 if quality == "low" else (60 if quality == "balanced" else 0)
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		_apply_viewports(tree.root)

static func _apply_viewports(node: Node) -> void:
	if node is Viewport:
		node.msaa_3d = Viewport.MSAA_DISABLED if quality == "low" else (Viewport.MSAA_2X if quality == "balanced" else Viewport.MSAA_4X)
		node.positional_shadow_atlas_size = 1024 if quality == "low" else (2048 if quality == "balanced" else 4096)
	for child in node.get_children():
		_apply_viewports(child)

func _quality_node_added(node: Node) -> void:
	if node is Viewport:
		_apply_viewports(node)

func set_cursor_enabled(value: bool) -> void:
	if not value and _pressed:
		_emit_click(false)
	cursor_enabled = value
	if not value:
		_marker.hide()

func _draw_pointer() -> void:
	_marker.draw_circle(Vector2.ZERO, 9, Color(0.08, 0.12, 0.16, 0.9))
	_marker.draw_arc(Vector2.ZERO, 9, 0, TAU, 32, Color(1, 0.85, 0.46), 2, true)
	_marker.draw_line(Vector2(-4, 0), Vector2(4, 0), Color.WHITE, 1.5)
	_marker.draw_line(Vector2(0, -4), Vector2(0, 4), Color.WHITE, 1.5)

func _process(delta: float) -> void:
	if not cursor_enabled or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_marker.hide()
		return
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		_marker.hide()
		return
	var pad: int = pads[0]
	var axis := Vector2(Input.get_joy_axis(pad, JOY_AXIS_LEFT_X), Input.get_joy_axis(pad, JOY_AXIS_LEFT_Y))
	if axis.length() < DEADZONE:
		return
	axis = axis.normalized() * minf(1, (axis.length() - DEADZONE) / (1 - DEADZONE))
	var previous := cursor_position
	var extent := get_viewport().get_visible_rect().size
	cursor_position = (cursor_position + axis * CURSOR_SPEED * minf(delta, 0.05)).clamp(Vector2.ZERO, extent)
	_cursor_visible = true
	_marker.show()
	_marker.position = cursor_position
	var motion := InputEventMouseMotion.new()
	motion.position = cursor_position
	motion.global_position = cursor_position
	motion.relative = cursor_position - previous
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT if _pressed else 0
	Input.parse_input_event(motion)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.relative.length() > 0 and event.device != 0:
		_marker.hide()
	if not cursor_enabled or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventJoypadButton and event.button_index == JOY_BUTTON_A and _cursor_visible:
		_emit_click(event.pressed)
		get_viewport().set_input_as_handled()

func _emit_click(pressed: bool) -> void:
	_pressed = pressed
	var button := InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_LEFT
	button.pressed = pressed
	button.position = cursor_position
	button.global_position = cursor_position
	button.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(button)
