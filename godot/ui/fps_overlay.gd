class_name FpsOverlay
extends CanvasLayer
## Small FPS / frame-time readout in the top-left corner. Toggled by Settings (GraphicsSettings.show_fps) or F3. Costs nothing when hidden.
var _label: Label
var _accum := 0.0

static func ensure(tree: SceneTree) -> void:
	if tree.root.get_node_or_null("FpsOverlay") == null:
		var overlay := FpsOverlay.new()
		overlay.name = "FpsOverlay"
		tree.root.call_deferred("add_child", overlay)

func _init() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(10, 6)
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color("f6dfa6"))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 4)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	visible = GraphicsSettings.show_fps
	GraphicsSettings.events().changed.connect(func(): visible = GraphicsSettings.show_fps)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		GraphicsSettings.set_value("show_fps", not GraphicsSettings.show_fps)

func _process(delta: float) -> void:
	if not visible:
		return
	_accum += delta
	if _accum < 0.25:
		return
	_accum = 0.0
	var ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_label.text = "%d FPS  %.1f ms   %s  %dx%d  draw %d" % [Engine.get_frames_per_second(), 1000.0 / maxf(1.0, Engine.get_frames_per_second()), GraphicsSettings.PRESET_NAMES[GraphicsSettings.preset], get_viewport().size.x, get_viewport().size.y, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))]
