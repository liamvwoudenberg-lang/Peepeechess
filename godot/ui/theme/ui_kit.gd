extends RefCounted
## Reusable building blocks for every screen: labels, section headers, cards, buttons (primary / secondary / danger),
## icon + label rows, segmented controls, slider rows, toasts, modals, banners, empty / loading / error states,
## responsive and safe-area containers.  All of them are plain static functions that add nodes to a parent and
## rely on the shared Theme (PeepeeTheme) for the look: they only pick type variations, never colours.
const T = preload("res://ui/theme/ui_tokens.gd")
const PeepeeTheme = preload("res://ui/theme/peepee_theme.gd")
const Icons = preload("res://ui/theme/ui_icons.gd")
const Motion = preload("res://ui/theme/ui_motion.gd")
const Prefs = preload("res://ui/theme/ui_prefs.gd")
const Interact = preload("res://ui/theme/ui_interact.gd")
const SafeMargin = preload("res://ui/theme/safe_margin.gd")
const ResponsiveBox = preload("res://ui/theme/responsive_box.gd")
## Tests override this to simulate a touch device.
static var force_touch: Variant = null
static var toast_seconds := 3.4
const MAX_TOASTS := 3

static func touch() -> bool:
	if force_touch != null:
		return bool(force_touch)
	return DisplayServer.is_touchscreen_available()

static func target_height() -> int:
	if not touch():
		return T.POINTER_MIN
	if DisplayServer.get_name() == "headless":
		return T.TOUCH_MIN
	var stretch := Prefs.base_stretch(Vector2(DisplayServer.window_get_size()))
	return Prefs.touch_target(DisplayServer.screen_get_dpi(), stretch * Prefs.effective_scale_factor())

## One-call screen setup: theme + preferences + press animation + UI sounds. Returns the Theme.
static func install(root: Control) -> Theme:
	var first := not Prefs.loaded
	Prefs.load_preferences()
	if first:
		Prefs.apply()
	var theme := PeepeeTheme.build()
	root.theme = theme
	if root.get_node_or_null("UiInteract") == null:
		var interact := Interact.new()
		interact.name = "UiInteract"
		interact.root = root
		root.add_child(interact)
	return theme

# ---------------------------------------------------------------- text
static func label(parent: Node, text: String, variant: String = "", wrap: bool = true) -> Label:
	var node := Label.new()
	node.text = text
	if variant != "":
		node.theme_type_variation = variant
	if wrap:
		node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		node.custom_minimum_size.x = 8.0   # lets an autowrapping label shrink inside narrow containers instead of forcing width
	parent.add_child(node)
	return node

static func muted(parent: Node, text: String) -> Label:
	return label(parent, text, "Muted")

static func heading(parent: Node, title: String, detail: String = "") -> Array:
	var title_label := label(parent, title, "H1")
	var detail_label: Label = null
	if detail != "":
		detail_label = label(parent, detail, "Muted")
		detail_label.add_theme_font_size_override("font_size", T.FS_LEAD)
	return [title_label, detail_label]

## Small gold caps header with an optional icon and a hairline that fills the rest of the row.
static func section_header(parent: Node, text: String, icon_kind: String = "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", T.S2)
	parent.add_child(row)
	if icon_kind != "":
		row.add_child(Icons.new(icon_kind, 18, T.GOLD))
	var caption := label(row, text.to_upper(), "Caption", false)
	caption.add_theme_color_override("font_color", T.GOLD)
	var line := HSeparator.new()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(line)
	return row

static func icon_label_row(parent: Node, icon_kind: String, text: String, variant: String = "", icon_color: Color = T.GOLD) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", T.S3)
	parent.add_child(row)
	var icon := Icons.new(icon_kind, 26, icon_color)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var text_label := label(row, text, variant)
	text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return row

# ---------------------------------------------------------------- containers
## Card: a themed PanelContainer in `parent`; returns the inner VBoxContainer (its parent is the panel).
static func card(parent: Node, variant: String = "CardPanel", spacing: int = 14) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = variant
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", spacing)
	panel.add_child(column)
	return column

static func flow(parent: Node, h: int = 10, v: int = 10) -> HFlowContainer:
	var node := HFlowContainer.new()
	node.add_theme_constant_override("h_separation", h)
	node.add_theme_constant_override("v_separation", v)
	parent.add_child(node)
	return node

static func responsive(parent: Node, break_width: float = 760.0, separation: int = T.S4) -> BoxContainer:
	var box: BoxContainer = ResponsiveBox.new()
	box.break_width = break_width
	box.add_theme_constant_override("separation", separation)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(box)
	return box

static func safe_frame(parent: Node, base: int = 24) -> MarginContainer:
	var frame: MarginContainer = SafeMargin.new()
	frame.base_margin = base
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(frame)
	return frame

# ---------------------------------------------------------------- buttons
static func button(parent: Node, text: String, on_press: Callable = Callable(), variant: String = "", icon_kind: String = "", tooltip: String = "") -> Button:
	var node := Button.new()
	node.text = text
	if variant != "":
		node.theme_type_variation = variant
	node.custom_minimum_size.y = target_height()
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.tooltip_text = tooltip
	if icon_kind != "":
		node.icon = Icons.texture(icon_kind, 22)
		node.expand_icon = false
	if on_press.is_valid():
		node.pressed.connect(on_press)
	parent.add_child(node)
	return node

static func primary(parent: Node, text: String, on_press: Callable = Callable(), icon_kind: String = "") -> Button:
	return button(parent, text, on_press, "PrimaryButton", icon_kind)

static func secondary(parent: Node, text: String, on_press: Callable = Callable(), icon_kind: String = "") -> Button:
	return button(parent, text, on_press, "", icon_kind)

static func danger(parent: Node, text: String, on_press: Callable = Callable(), icon_kind: String = "") -> Button:
	return button(parent, text, on_press, "DangerButton", icon_kind)

static func ghost(parent: Node, text: String, on_press: Callable = Callable(), icon_kind: String = "") -> Button:
	return button(parent, text, on_press, "GhostButton", icon_kind)

## Disabled buttons should say why. Sets the tooltip and (optionally) an inline Muted note under it.
static func disable_with_reason(node: Button, reason: String) -> void:
	node.disabled = true
	node.tooltip_text = reason

## Segmented control (radio-like row of toggle buttons). `options` = [[value, label], ...]. Returns the container;
## its "value" meta is the current value. on_change(value) fires only on user changes.
static func segmented(parent: Node, options: Array, selected: Variant, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.set_meta(&"value", selected)
	parent.add_child(row)
	var group := ButtonGroup.new()
	for option in options:
		var value = option[0]
		var segment := Button.new()
		segment.text = str(option[1])
		segment.theme_type_variation = "SegButton"
		segment.toggle_mode = true
		segment.button_group = group
		segment.button_pressed = value == selected
		segment.custom_minimum_size.y = target_height()
		segment.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		segment.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		segment.toggled.connect(func(on: bool):
			if on:
				row.set_meta(&"value", value)
				if on_change.is_valid():
					on_change.call(value))
		row.add_child(segment)
	return row

static func toggle_row(parent: Node, text: String, on: bool, on_toggle: Callable, hint: String = "") -> CheckButton:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	parent.add_child(box)
	var toggle := CheckButton.new()
	toggle.text = text
	toggle.button_pressed = on
	toggle.custom_minimum_size.y = target_height()
	toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toggle.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if on_toggle.is_valid():
		toggle.toggled.connect(on_toggle)
	box.add_child(toggle)
	if hint != "":
		var note := label(box, hint, "Muted")
		note.add_theme_font_size_override("font_size", T.FS_SMALL)
	return toggle

## Labelled slider with a live value read-out. `format` is a Callable(float) -> String (default: percent).
static func slider_row(parent: Node, title: String, value: float, min_value: float, max_value: float, step: float, on_change: Callable, format: Callable = Callable()) -> HSlider:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	parent.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var name_label := label(head, title, "", false)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var readout := label(head, "", "Accent", false)
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	readout.custom_minimum_size.x = 64
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(120, maxi(target_height(), 32))
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.tooltip_text = title
	var fmt := func(v: float) -> String: return format.call(v) if format.is_valid() else "%d%%" % roundi(v * 100.0)
	readout.text = fmt.call(value)
	slider.value_changed.connect(func(v: float):
		readout.text = fmt.call(v)
		if on_change.is_valid():
			on_change.call(v))
	slider.set_meta(&"readout", readout)
	box.add_child(slider)
	return slider

# ---------------------------------------------------------------- banners / states
## kind: info | success | warning | danger.  Returns the panel.
static func banner(parent: Node, text: String, kind: String = "info") -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "DangerPanel" if kind == "danger" else "BannerPanel"
	parent.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", T.S3)
	panel.add_child(row)
	var colors := {"info": T.INFO, "success": T.SUCCESS, "warning": T.WARNING, "danger": T.DANGER}
	var glyph := {"info": "info", "success": "check", "warning": "warning", "danger": "warning"}
	var tint: Color = colors.get(kind, T.INFO)
	var icon := Icons.new(glyph.get(kind, "info"), 22, tint)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var message := label(row, text)
	message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return panel

static func empty_state(parent: Node, icon_kind: String, title: String, detail: String = "", action_text: String = "", action: Callable = Callable()) -> VBoxContainer:
	var column := card(parent, "CardPanel", T.S3)
	var icon := Icons.new(icon_kind, 44, T.GOLD_LO)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(icon)
	var heading_label := label(column, title, "H3")
	heading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if detail != "":
		var detail_label := muted(column, detail)
		detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if action_text != "":
		var act := primary(column, action_text, action)
		act.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return column

static func loading_state(parent: Node, text: String = "Loading...") -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", T.S3)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(row)
	var icon := Icons.new("clock", 24, T.GOLD)
	row.add_child(icon)
	row.add_child(_inline_label(text))
	if Motion.enabled():
		var tween := row.create_tween().set_loops()
		tween.tween_property(icon, "modulate:a", 0.35, 0.7)
		tween.tween_property(icon, "modulate:a", 1.0, 0.7)
	return row

static func _inline_label(text: String) -> Label:
	var node := Label.new()
	node.text = text
	node.theme_type_variation = "Muted"
	return node

static func error_state(parent: Node, message: String, retry_text: String = "", retry: Callable = Callable()) -> VBoxContainer:
	var column := card(parent, "CardPanel", T.S3)
	var row := icon_label_row(column, "warning", message, "", T.DANGER)
	row.get_child(1).add_theme_color_override("font_color", T.TEXT)
	if retry_text != "":
		secondary(column, retry_text, retry)
	return column

# ---------------------------------------------------------------- toast
static func _toast_layer(host: Node) -> Control:
	var layer := host.get_node_or_null("ToastLayer") as Control
	if layer == null:
		layer = Control.new()
		layer.name = "ToastLayer"
		layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.z_index = 100
		host.add_child(layer)
		var anchor := MarginContainer.new()
		anchor.name = "Anchor"
		anchor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for side in ["left", "right", "bottom", "top"]:
			anchor.add_theme_constant_override("margin_" + side, 24)
		layer.add_child(anchor)
		var stack := VBoxContainer.new()
		stack.name = "Stack"
		stack.alignment = BoxContainer.ALIGNMENT_END
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_theme_constant_override("separation", 8)
		anchor.add_child(stack)
	else:
		host.move_child(layer, host.get_child_count() - 1)
	return layer

## Shows a short non-blocking message at the bottom of `host`. kind: info | success | warning | danger.
static func toast(host: Node, text: String, kind: String = "info") -> PanelContainer:
	if host == null or not is_instance_valid(host) or not host.is_inside_tree():
		return null
	var layer := _toast_layer(host)
	var stack := layer.get_node("Anchor/Stack") as VBoxContainer
	while stack.get_child_count() >= MAX_TOASTS:
		var oldest := stack.get_child(0)
		stack.remove_child(oldest)
		oldest.queue_free()
	var panel := PanelContainer.new()
	panel.theme_type_variation = "ToastPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.set_meta(&"kind", kind)
	stack.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", T.S3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	var colors := {"info": T.INFO, "success": T.SUCCESS, "warning": T.WARNING, "danger": T.DANGER}
	var glyph := {"info": "info", "success": "check", "warning": "warning", "danger": "warning"}
	row.add_child(Icons.new(glyph.get(kind, "info"), 20, colors.get(kind, T.INFO)))
	var message := label(row, text)
	message.custom_minimum_size.x = 0.0
	message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var width := clampf(host.get_viewport().get_visible_rect().size.x - 80.0, 200.0, 560.0) if host.get_viewport() != null else 480.0
	message.custom_minimum_size.x = minf(width - 90.0, 440.0)
	Motion.toast_in(panel)
	var lifetime := panel.create_tween()
	lifetime.tween_interval(toast_seconds)
	lifetime.tween_callback(func(): Motion.fade_out(panel, panel.queue_free))
	return panel

# ---------------------------------------------------------------- dialogs
## A dialog's first layout pass measures wrapping labels at (almost) zero width and can leave the window far taller
## than its content; one frame later the real minimum is known, so shrink to it and re-centre.
static func refit(dialog: Window, min_size: Vector2i = Vector2i.ZERO) -> void:
	if not is_instance_valid(dialog) or not dialog.is_inside_tree():
		return
	await dialog.get_tree().process_frame
	if not is_instance_valid(dialog) or not dialog.visible:
		return
	var wanted := Vector2i(dialog.get_contents_minimum_size())
	dialog.size = Vector2i(maxi(min_size.x, wanted.x), maxi(min_size.y, wanted.y))
	var parent_view := dialog.get_parent().get_viewport() if dialog.get_parent() != null else null
	dialog.position = centered_position(parent_view.get_visible_rect().size if parent_view != null else Vector2(dialog.size), dialog.size)

const TITLE_BAR := 48   # embedded dialogs draw their title bar above the content rect

## Top-left of the content rect that centres a window of `window_size` in a viewport of `view` (never negative,
## always leaving room for the title bar).
static func centered_position(view: Vector2, window_size: Vector2i) -> Vector2i:
	return Vector2i(maxi(0, int((view.x - window_size.x) * 0.5)), maxi(TITLE_BAR, int((view.y - window_size.y) * 0.5)))

## Opens `dialog` centred with an explicit Rect2i (popup_centered on a tiny headless root logs an invalid position).
static func popup_in(host: Node, dialog: Window, width: int, height: int) -> void:
	var view := host.get_viewport().get_visible_rect().size if host.get_viewport() != null else Vector2(1280, 720)
	var window_size := Vector2i(clampi(width, 1, maxi(1, int(view.x) - 32)), clampi(height, 1, maxi(1, int(view.y) - 32 - TITLE_BAR)))
	dialog.popup(Rect2i(centered_position(view, window_size), window_size))

static func _prepare_dialog(host: Node, dialog: AcceptDialog, width: int, height: int) -> void:
	host.add_child(dialog)
	dialog.theme = null   # inherit the host's theme
	popup_in(host, dialog, width, height)
	Motion.dialog_pop(dialog)
	refit(dialog)

## Confirmation dialog (cancelable). `danger` styles the confirm button red. Frees itself when closed.
static func confirm(host: Node, title: String, text: String, ok_text: String, on_ok: Callable, danger_style: bool = false, on_cancel: Callable = Callable(), cancel_text: String = "Cancel") -> ConfirmationDialog:
	var dialog := ConfirmationDialog.new()
	dialog.title = title
	dialog.dialog_text = text
	dialog.ok_button_text = ok_text
	dialog.cancel_button_text = cancel_text
	dialog.get_ok_button().theme_type_variation = "DangerButton" if danger_style else "PrimaryButton"
	dialog.get_ok_button().custom_minimum_size.y = target_height()
	dialog.get_cancel_button().custom_minimum_size.y = target_height()
	dialog.confirmed.connect(func():
		if on_ok.is_valid():
			on_ok.call()
		dialog.queue_free())
	dialog.canceled.connect(func():
		if on_cancel.is_valid():
			on_cancel.call()
		dialog.queue_free())
	_prepare_dialog(host, dialog, 460, 190)
	return dialog

## Information modal: `build` is a Callable(VBoxContainer) that fills the body. Closes with one button.
static func modal(host: Node, title: String, build: Callable, close_text: String = "Close", width: int = 460, height: int = 240) -> AcceptDialog:
	var dialog := AcceptDialog.new()
	dialog.title = title
	dialog.ok_button_text = close_text
	dialog.get_ok_button().theme_type_variation = "PrimaryButton"
	dialog.get_ok_button().custom_minimum_size.y = target_height()
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", T.S3)
	body.custom_minimum_size.x = clampf(width - 64.0, 200.0, 560.0)  # wrapping labels need a width to measure against
	dialog.add_child(body)
	if build.is_valid():
		build.call(body)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	_prepare_dialog(host, dialog, width, height)
	return dialog

## Status chip: small rounded label (e.g. "Ranked", "Online").
static func chip(parent: Node, text: String, tint: Color = T.GOLD) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := PeepeeTheme.flat(Color(tint.r, tint.g, tint.b, 0.14), tint, 1, 99, 10, 3)
	panel.add_theme_stylebox_override("panel", style)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER   # a chip is as tall as its text: inside a taller row it must not stretch into an oval
	parent.add_child(panel)
	var text_label := label(panel, text, "Caption", false)
	text_label.add_theme_color_override("font_color", tint)
	return panel
