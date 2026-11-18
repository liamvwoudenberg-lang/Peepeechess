extends Control
## Capture intro: letterbox bars slide in, a "versus" card shows attacker and defender, then everything leaves. Under 3 s
## (DURATION 2.2), skipped by any key / click / tap / pad button, instant when Settings > Cinematics is off, no slide with reduce
## motion (static card, shorter). Presentation only: it is a non-blocking overlay; it never pauses or scales any clock.
## Timing goes through advance(delta) so tests drive it with explicit steps.
##   var intro = CaptureIntro.new(); host.add_child(intro); intro.play("White Knight", "Black Pawn", attacker_tint, defender_tint)
const T = preload("res://ui/theme/ui_tokens.gd")
const Common = preload("res://ui/cinematic/cine_common.gd")
const Frames = preload("res://ui/theme/ui_frames.gd")

signal finished

const DURATION := 2.2
const BAR_IN := 0.3
const BAR_OUT := 0.3
const BAR_FRACTION := 0.11

var elapsed := 0.0
var duration := DURATION
var playing := false
var top_bar: ColorRect
var bottom_bar: ColorRect
var card: PanelContainer
var _bar := 0.0

func _init() -> void:
	name = "CaptureIntro"
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # never blocks the game underneath
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false

## Returns false (and emits finished) when cinematics are off.
func play(attacker: String, defender: String, attacker_tint: Color = T.GOLD, defender_tint: Color = T.DANGER) -> bool:
	if not Common.cinematics_on():
		finished.emit()
		queue_free()
		return false
	_build(attacker, defender, attacker_tint, defender_tint)
	duration = 1.2 if Common.reduce_motion() else DURATION
	elapsed = 0.0
	playing = true
	visible = true
	_apply()
	return true

func _build(attacker: String, defender: String, a_tint: Color, d_tint: Color) -> void:
	top_bar = _make_bar("TopBar")
	bottom_bar = _make_bar("BottomBar")
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	card = PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", Frames.gilded(Color(T.BG_DEEP.r, T.BG_DEEP.g, T.BG_DEEP.b, 1.0), 28, 18))
	center.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	_name_label(row, attacker, a_tint)
	var vs := Label.new()
	vs.text = "VS"
	vs.theme_type_variation = "H2"
	vs.add_theme_color_override("font_color", T.GOLD_HI)
	row.add_child(vs)
	_name_label(row, defender, d_tint)

func _make_bar(node_name: String) -> ColorRect:
	var bar := ColorRect.new()
	bar.name = node_name
	bar.color = Color.BLACK
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	return bar

func _name_label(parent: Node, text: String, tint: Color) -> void:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = "H2"
	label.add_theme_color_override("font_color", tint)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)

func advance(delta: float) -> void:
	if not playing:
		return
	elapsed += delta
	if elapsed >= duration:
		finish()
		return
	_apply()

func _apply() -> void:
	var u_in := clampf(elapsed / BAR_IN, 0.0, 1.0)
	var u_out := clampf((duration - elapsed) / BAR_OUT, 0.0, 1.0)
	_bar = 1.0 if Common.reduce_motion() else ease_out(minf(u_in, u_out))
	var h := size.y * BAR_FRACTION * _bar
	top_bar.position = Vector2.ZERO
	top_bar.size = Vector2(size.x, h)
	bottom_bar.size = Vector2(size.x, h)
	bottom_bar.position = Vector2(0.0, size.y - h)
	if card != null:
		card.modulate.a = minf(u_in, u_out)

static func ease_out(u: float) -> float:
	return 1.0 - pow(1.0 - u, 3.0)

func finish() -> void:
	if not playing:
		return
	playing = false
	visible = false
	finished.emit()
	queue_free()

func _process(delta: float) -> void:
	advance(delta)

func _input(event: InputEvent) -> void:
	if playing and elapsed >= Common.SKIP_GUARD and Common.is_skip(event):
		get_viewport().set_input_as_handled()
		finish()
