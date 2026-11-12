extends Control
## The opening screen: the title and a pulsing "Press any button to start" over the 3D castle. Any key, mouse button, touch or
## gamepad button (never mouse motion, wheel or axes, and nothing on the very first frame) starts a cinematic camera glide through
## the gate; while it runs the title fades out and the application's main menu fades in over the still-rendering scene.
##
##   state WAITING     title + prompt, camera drifting
##   state TRANSITION  eased glide (GLIDE seconds); a second press skips to the end once SKIP_GUARD has passed, earlier presses
##                     (a touch also produces an emulated click) are swallowed
##   state DONE        menu is up; the node frees itself (the scene stays behind the menu)
##
## All timing goes through advance(delta) so tests drive it with explicit steps instead of the wall clock. Reduce motion cuts
## straight to the menu (no glide, no pulse).
const T = preload("res://ui/theme/ui_tokens.gd")
const Kit = preload("res://ui/theme/ui_kit.gd")
const Motion = preload("res://ui/theme/ui_motion.gd")
const Prefs = preload("res://ui/theme/ui_prefs.gd")
const Title = preload("res://ui/theme/title_screen.gd")

enum State { WAITING, TRANSITION, DONE, CANCELLED }

signal transition_started
signal finished

const GLIDE := 2.4          ## seconds of camera travel
const TITLE_FADE := 0.55    ## the title is gone this long after the press
const MENU_START := 1.5     ## the menu starts to fade in here ...
const MENU_FADE := 0.8      ## ... over this long
const SKIP_GUARD := 0.4     ## presses earlier than this into the glide are ignored
const PULSE_PERIOD := 2.2
const PROMPT_TEXT := "Press any button to start"
const PROMPT_TOUCH := "Tap to start"

var state: int = State.WAITING
var elapsed := 0.0            ## seconds since the screen was shown
var glide := 0.0              ## seconds since the press
var scene: Node3D             ## OpeningScene (may be null in tests of the pure state machine)
var backdrop: Control         ## the application's Backdrop (for the scrim); optional
var menu_root: CanvasItem     ## what fades in (the application's page container)
var build_menu: Callable      ## builds the main menu into the page container
var title_frame: Control
var wordmark: Label
var tagline: Label
var prompt: Label
var caption: Label
var _armed := false
var _menu_built := false
var _brand_box: VBoxContainer

## Whether `event` counts as "any button": a key press (not a repeat), a mouse button (not the wheel), a touch or a gamepad button.
static func is_any_button(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.echo
	if event is InputEventMouseButton:
		return event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2]
	if event is InputEventScreenTouch:
		return event.pressed
	if event is InputEventJoypadButton:
		return event.pressed
	return false

func _init() -> void:
	name = "OpeningScreen"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func setup(scene_3d: Node3D, page_container: CanvasItem, menu_builder: Callable, scrim: Control = null) -> void:
	scene = scene_3d
	menu_root = page_container
	build_menu = menu_builder
	backdrop = scrim
	_build_title()
	_layout()
	_apply(0.0)

func _build_title() -> void:
	title_frame = Kit.safe_frame(self)
	title_frame.name = "TitleFrame"
	title_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", T.S3)
	title_frame.add_child(column)
	var top_pad := Control.new()
	top_pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top_pad.size_flags_stretch_ratio = 0.35
	top_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(top_pad)
	_brand_box = VBoxContainer.new()
	_brand_box.name = "Brand"
	_brand_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_brand_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_brand_box.add_theme_constant_override("separation", T.S2)
	column.add_child(_brand_box)
	var emblem := Title.Emblem.new(104)
	emblem.name = "Emblem"
	emblem.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_brand_box.add_child(emblem)
	wordmark = Kit.label(_brand_box, "PEEPEECHESS", "Wordmark", false)
	wordmark.name = "Wordmark"
	wordmark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline = Kit.label(_brand_box, "Your board. Your perspective. One shared game.", "", false)
	tagline.name = "Tagline"
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(gap)
	prompt = Kit.label(column, PROMPT_TOUCH if Kit.touch() else PROMPT_TEXT, "Accent", false)
	prompt.name = "Prompt"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var bottom_pad := Control.new()
	bottom_pad.custom_minimum_size.y = T.S5
	bottom_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(bottom_pad)
	caption = Kit.label(column, Title.version_text() + "  ·  Windows and Android crossplay", "Caption", false)
	caption.name = "Version"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_color_override("font_color", T.TEXT_MUTED)
	for label in [wordmark, tagline, prompt, caption]:
		(label as Label).add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.08, 0.92))
		(label as Label).mouse_filter = Control.MOUSE_FILTER_IGNORE
	wordmark.add_theme_constant_override("outline_size", 14)
	tagline.add_theme_constant_override("outline_size", 8)
	tagline.add_theme_font_size_override("font_size", T.FS_LEAD)
	tagline.add_theme_color_override("font_color", T.TEXT)
	prompt.add_theme_constant_override("outline_size", 8)
	caption.add_theme_constant_override("outline_size", 5)
	resized.connect(_layout)

## Type scales with the visible area (the project stretches a 1200 x 800 base; tall windows get a bigger title).
func _layout() -> void:
	if wordmark == null:
		return
	var view := get_viewport_rect().size if is_inside_tree() else Vector2(1280, 800)
	var portrait := view.y > view.x * 1.1
	var size_px := view.x * 0.085 if portrait else minf(view.x * 0.058, view.y * 0.095)
	size_px = clampf(size_px, 38.0, 110.0)
	wordmark.add_theme_font_size_override("font_size", roundi(size_px))
	tagline.add_theme_font_size_override("font_size", roundi(clampf(size_px * 0.30, 16.0, 34.0)))
	prompt.add_theme_font_size_override("font_size", roundi(clampf(size_px * 0.36, 19.0, 40.0)))
	caption.add_theme_font_size_override("font_size", roundi(clampf(size_px * 0.19, 12.0, 22.0)))
	title_frame.pivot_offset = title_frame.size * 0.5

func _ready() -> void:
	set_process(true)

func _process(delta: float) -> void:
	advance(delta)

func _input(event: InputEvent) -> void:
	if state == State.DONE or state == State.CANCELLED:
		return
	if not is_any_button(event):
		return
	if not _armed:
		return   # the very first frame: ignore (a key that launched the app, a click-through from the window manager)
	if press():
		get_viewport().set_input_as_handled()

## A button press. Returns true when it was consumed (it never reaches the controls underneath while the intro runs).
func press() -> bool:
	match state:
		State.WAITING:
			begin()
			return true
		State.TRANSITION:
			if glide >= SKIP_GUARD:
				finish()
			return true
	return false

## Start the camera glide (or cut, when motion is reduced).
func begin() -> void:
	if state != State.WAITING:
		return
	state = State.TRANSITION
	glide = 0.0
	transition_started.emit()
	if Prefs.reduce_motion:
		finish()
		return
	if is_instance_valid(menu_root):
		Motion.settle(menu_root as CanvasItem)
	_apply(0.0)

## Jump to the end: camera at the menu vantage, menu fully visible, title gone, this node freed.
func finish() -> void:
	if state == State.DONE or state == State.CANCELLED:
		return
	if state == State.WAITING:
		state = State.TRANSITION
	glide = GLIDE + 0.001
	_apply(glide)
	state = State.DONE
	_set_menu_alpha(1.0)
	finished.emit()
	queue_free()

## The player navigated elsewhere before or during the intro: drop it without building anything more.
func cancel() -> void:
	if state == State.DONE or state == State.CANCELLED:
		return
	state = State.CANCELLED
	if is_instance_valid(menu_root):
		Motion.settle(menu_root as CanvasItem)
	queue_free()

func advance(delta: float) -> void:
	elapsed += delta
	if not _armed:
		_armed = true
		_pulse()
		return
	match state:
		State.WAITING:
			_pulse()
		State.TRANSITION:
			glide += delta
			if glide >= GLIDE + 0.1:
				finish()
			else:
				_apply(glide)

static func ease_glide(u: float) -> float:
	var x := clampf(u, 0.0, 1.0)
	return x * x * x * (x * (x * 6.0 - 15.0) + 10.0)   # smootherstep: leaves and arrives at rest

func _pulse() -> void:
	if prompt == null:
		return
	if Prefs.reduce_motion:
		prompt.modulate.a = 1.0
		return
	prompt.modulate.a = 0.55 + 0.45 * (0.5 + 0.5 * sin(elapsed * TAU / PULSE_PERIOD))

func _set_menu_alpha(alpha: float) -> void:
	if is_instance_valid(menu_root):
		(menu_root as CanvasItem).modulate.a = alpha

## Poses everything for `t` seconds into the glide.
func _apply(t: float) -> void:
	var progress := clampf(t / GLIDE, 0.0, 1.0) if state != State.WAITING else 0.0
	if is_instance_valid(scene) and scene.has_method("set_blend"):
		scene.call("set_blend", ease_glide(progress))
	var title_alpha := 1.0 - smoothstep(0.0, TITLE_FADE, t) if state != State.WAITING else 1.0
	if title_frame != null:
		title_frame.modulate.a = title_alpha
		title_frame.visible = title_alpha > 0.002
		var lift := smoothstep(0.0, TITLE_FADE * 1.4, t) if state != State.WAITING else 0.0
		title_frame.scale = Vector2.ONE * (1.0 + 0.05 * lift)
	if state == State.WAITING:
		return
	var menu_alpha := smoothstep(MENU_START, MENU_START + MENU_FADE, t)
	if menu_alpha > 0.0 and not _menu_built:
		_menu_built = true
		if build_menu.is_valid():
			build_menu.call()
	if _menu_built or state == State.DONE:
		_set_menu_alpha(menu_alpha)
	if backdrop != null and is_instance_valid(backdrop):
		backdrop.set("center_dim", menu_alpha)

## Test hook: has the menu been built yet?
func menu_built() -> bool:
	return _menu_built
