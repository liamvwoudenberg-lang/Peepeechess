extends "res://combat/tests/test_runner.gd"
## Owner suites inject logical Control positions with Input.parse_input_event,
## whose public API expects physical window pixels. Give that fixture a 1:1
## window transform. The real scaled physical-input path is tested separately.
func _initialize() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	# The headless root window starts at 64x64 and, with the scale mode disabled, a dialog the pads suite centers in
	# it lands at a negative position (engine log: "Window 0 spawned at invalid position"). Use the project's
	# window size, applied after the first frame because the display server resets it before then.
	await process_frame
	root.size = Vector2i(1280, 800)
	super._initialize()
