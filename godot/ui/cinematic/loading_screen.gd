extends Control
## Loading screen: dark stone backdrop, emblem, wordmark, a thin gilded progress bar and a rotating tip. Fades in/out over 0.2 s.
## Presentation only. Usage:
##   var l = LoadingScreen.new(); host.add_child(l); l.begin("Entering the pit"); l.set_progress(0.4); l.end()
## Because scene loads on this project are synchronous, call begin(), wait one frame (await get_tree().process_frame), then load.
const T = preload("res://ui/theme/ui_tokens.gd")
const Kit = preload("res://ui/theme/ui_kit.gd")
const Common = preload("res://ui/cinematic/cine_common.gd")
const Icons = preload("res://ui/theme/ui_icons.gd")

signal ended

const TIPS := [
	"Attacks are telegraphed. Read the glow before the strike.",
	"The attacker strikes first. Choose your captures with care.",
	"Hold the centre and the castle follows.",
	"Reduce motion and cinematics can be switched off in Settings.",
]
const FADE := 0.2

var bar: ProgressBar
var status: Label
var tip: Label

func _init() -> void:
	name = "LoadingScreen"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

func begin(text: String = "Loading") -> void:
	if status == null:
		_build()
	status.text = text
	bar.value = 0.0
	tip.text = TIPS[randi() % TIPS.size()]
	visible = true
	if Common.reduce_motion():
		modulate.a = 1.0
	else:
		modulate.a = 0.0
		create_tween().tween_property(self, "modulate:a", 1.0, FADE).set_ease(Tween.EASE_OUT)

func set_progress(value: float) -> void:
	if bar != null:
		bar.value = clampf(value, 0.0, 1.0)

func end() -> void:
	if Common.reduce_motion() or not is_inside_tree():
		_finish()
		return
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, FADE).set_ease(Tween.EASE_IN)
	tween.tween_callback(_finish)

func _finish() -> void:
	visible = false
	ended.emit()
	queue_free()

func _build() -> void:
	var back := ColorRect.new()
	back.color = T.BG_DEEP
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	add_child(Common.make_vignette(0.6))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 360
	column.add_theme_constant_override("separation", 14)
	center.add_child(column)
	var word := Kit.label(column, "PEEPEECHESS", "H1", false)
	word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status = Kit.label(column, "Loading", "H3", false)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar = ProgressBar.new()
	bar.max_value = 1.0
	bar.show_percentage = false
	bar.custom_minimum_size.y = 8
	column.add_child(bar)
	tip = Kit.muted(column, "")
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
