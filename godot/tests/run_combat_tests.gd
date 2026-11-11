extends "res://combat/tests/test_runner.gd"
## Owner suites inject logical Control positions with Input.parse_input_event,
## whose public API expects physical window pixels. Give that fixture a 1:1
## window transform. The real scaled physical-input path is tested separately.
func _initialize() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	super._initialize()
