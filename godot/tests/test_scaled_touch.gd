extends SceneTree
## Real OS touch coordinates must become logical Control coordinates under application scaling.
const Touch = preload("res://combat/presentation/touch_controls.gd")
var actions: Array = []
func _init() -> void:
	call_deferred("run")
func run() -> void:
	root.size = Vector2i(1920, 1080)
	var layer = CanvasLayer.new()
	root.add_child(layer)
	var touch = Touch.new()
	layer.add_child(touch)
	touch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	touch.action_pressed.connect(func(action): actions.append(action))
	await process_frame
	await process_frame
	var logical: Vector2 = touch.layout().buttons.light.center
	var transform = root.get_final_transform()
	var physical: Vector2 = transform * logical
	print("SCALED_TOUCH transform=", transform, " logical=", logical, " physical=", physical)
	for pressed in [true, false]:
		var event = InputEventScreenTouch.new()
		event.index = 1
		event.position = physical
		event.pressed = pressed
		Input.parse_input_event(event)
	await process_frame
	await process_frame
	if actions != ["light"]:
		printerr("FAIL scaled application touch: ", actions)
		quit(1)
		return
	layer.queue_free()
	await process_frame
	print("PASS scaled application touch: raw physical coordinates dispatch once to logical control")
	quit(0)
