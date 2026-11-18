extends Control
## Victory / defeat / draw overlay: a dimmed scene, a gilded (victory) or crimson (defeat) banner with a Cinzel title, a subtitle
## and a Continue button. Fades in over 0.25 s (instant with reduce motion or Cinematics off); the button (or any key / Enter) emits
## `continued`. Presentation only; it reports nothing back to the game except that the player pressed Continue.
##   var r = ResultScreen.new(); host.add_child(r); r.show_result("victory", "Checkmate", "White wins in 31 moves")
const T = preload("res://ui/theme/ui_tokens.gd")
const Common = preload("res://ui/cinematic/cine_common.gd")
const Frames = preload("res://ui/theme/ui_frames.gd")
const Kit = preload("res://ui/theme/ui_kit.gd")

signal continued

const FADE := 0.25
const TITLES := {"victory": "Victory", "defeat": "Defeat", "draw": "Draw"}
const TINTS := {"victory": Color("e0b45f"), "defeat": Color("e07a6c"), "draw": Color("b0b4bc")}

var kind := "victory"
var title_label: Label
var detail_label: Label
var button: Button
var panel: PanelContainer
var _done := false

func _init() -> void:
	name = "ResultScreen"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func show_result(result_kind: String, headline: String = "", detail: String = "", continue_text: String = "Continue") -> void:
	kind = result_kind if TITLES.has(result_kind) else "draw"
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.06, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	add_child(Common.make_vignette(0.55, Color(0.25, 0.04, 0.05) if kind == "defeat" else Color.BLACK))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	panel = PanelContainer.new()
	var fill: Color = Color("2a1514") if kind == "defeat" else T.SURFACE_GOLD
	panel.add_theme_stylebox_override("panel", Frames.gilded(fill, 40, 28) if kind != "draw" else Frames.stone(T.SURFACE_2, 40, 28))
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	column.custom_minimum_size.x = 320
	panel.add_child(column)
	title_label = Kit.label(column, TITLES[kind], "H1", false)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_color_override("font_color", TINTS[kind])
	if headline != "":
		var sub := Kit.label(column, headline, "H3", true)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if detail != "":
		detail_label = Kit.muted(column, detail)
		detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button = Kit.primary(column, continue_text, _press)
	button.name = "ContinueButton"
	if Common.cinematics_on() and not Common.reduce_motion():
		modulate.a = 0.0
		create_tween().tween_property(self, "modulate:a", 1.0, FADE).set_ease(Tween.EASE_OUT)
	button.grab_focus.call_deferred()

func _press() -> void:
	if _done:
		return
	_done = true
	continued.emit()
	queue_free()
