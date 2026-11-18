class_name HudMinimal
extends RefCounted
## Minimal game-screen layout (UiStyle "minimal", the default). The 3D scene fills the whole screen; what remains is
##   * a small Menu button (top-left)           * two compact translucent player plates (far side top-right, near side bottom-left)
##   * a turn / check / result toast that fades by itself
##   * ONE overlay menu (Menu button, Esc, controller Start) holding everything the old toolbar and side panel had
##   * a slim move-history drawer (H, or the menu), hidden by default
## Idle chrome fades to low opacity after a few seconds and returns on mouse move / touch / key / button.
## It re-parents the controls game_hud.gd built (so main.gd's references stay valid) instead of duplicating them; cosmetic only.
const T = preload("res://ui/theme/ui_tokens.gd")
const Kit = preload("res://ui/theme/ui_kit.gd")
const Prefs = preload("res://ui/theme/ui_prefs.gd")
const Backdrop = preload("res://ui/theme/backdrop.gd")
const IDLE_SECONDS := 4.0
const IDLE_ALPHA := 0.32
const TOAST_SECONDS := 2.4

class Controller:
	extends Node
	var m: Control
	var overlay: Control
	var menu: Control
	var drawer: Control
	var chrome: Array[Control] = []
	var idle := 0.0
	var drawer_open := false

	func _input(event: InputEvent) -> void:
		if event is InputEventMouseMotion or event is InputEventKey or event is InputEventScreenTouch or event is InputEventMouseButton or event is InputEventJoypadButton:
			idle = 0.0

	func _unhandled_key_input(event: InputEvent) -> void:
		if not (event is InputEventKey and event.pressed and not event.echo):
			return
		if event.keycode == KEY_ESCAPE:
			toggle_menu()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_H and not menu.visible:
			toggle_drawer()
			get_viewport().set_input_as_handled()

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START:
			toggle_menu()
			get_viewport().set_input_as_handled()

	func toggle_menu() -> void:
		menu.visible = not menu.visible
		if menu.visible:
			idle = 0.0
			var first := menu.find_child("MenuFirst", true, false) as Control
			if first != null:
				first.grab_focus()

	func toggle_drawer() -> void:
		drawer_open = not drawer_open
		var width: float = 250.0
		drawer.visible = true
		var target := -width - 12.0 if drawer_open else 40.0
		if Prefs.reduce_motion or not is_inside_tree():
			drawer.offset_left = target
			drawer.offset_right = target + width
			drawer.visible = drawer_open
			return
		var tween := create_tween().set_parallel(true).set_ease(Tween.EASE_OUT)
		tween.tween_property(drawer, "offset_left", target, 0.2)
		tween.tween_property(drawer, "offset_right", target + width, 0.2)
		if not drawer_open:
			tween.chain().tween_callback(func(): drawer.visible = false)

	func _process(delta: float) -> void:
		idle += delta
		var busy := menu.visible or drawer_open
		var target := 1.0 if (idle < IDLE_SECONDS or busy) else IDLE_ALPHA
		for node in chrome:
			if is_instance_valid(node):
				node.modulate.a = target if Prefs.reduce_motion else move_toward(node.modulate.a, target, delta * 2.5)

static func apply(m: Control, frame: Control, column: Control) -> void:
	m.hud["minimal"] = true
	for child in m.get_children():
		if child is Backdrop:
			child.visible = false   # no solid backdrop: the 3D scene is the background
	if frame is MarginContainer and "base_margin" in frame:
		frame.base_margin = 0
	m.message_label.visible = false
	m.board_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var overlay := Control.new()
	overlay.name = "MinimalOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(overlay)
	var controller := Controller.new()
	controller.name = "MinimalController"
	controller.m = m
	controller.overlay = overlay
	overlay.add_child(controller)
	# --- plates: the two player cards, compact and translucent
	for side in ["w", "b"]:
		var card: PanelContainer = m.hud["card_" + side]
		card.get_parent().remove_child(card)
		overlay.add_child(card)
		card.custom_minimum_size = Vector2(190, 0)
		(m.hud["name_" + side] as Label).add_theme_font_size_override("font_size", 17)
		var clock: Label = m.clock_white if side == "w" else m.clock_black
		clock.add_theme_font_size_override("font_size", 24)
		clock.custom_minimum_size.x = 70
		controller.chrome.append(card)
	# --- toast: the turn / check / result banner
	var banner: PanelContainer = m.hud["banner"]
	banner.get_parent().remove_child(banner)
	overlay.add_child(banner)
	m.status_label.autowrap_mode = TextServer.AUTOWRAP_OFF   # a wrapping label in a narrow toast grew tall (413 px) and read as a big dark block
	m.status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.custom_minimum_size = Vector2(280, 0)
	banner.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	pin(banner, Control.PRESET_CENTER_TOP, 78.0)   # just under the far player's plate
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.modulate.a = 0.0
	banner.visible = false
	# --- menu button
	var menu_button := Kit.button(overlay, "Menu", func(): controller.toggle_menu(), "GhostButton", "list", "Menu (Esc)")
	menu_button.name = "MenuButton"
	pin(menu_button, Control.PRESET_TOP_LEFT, 12.0)
	controller.chrome.append(menu_button)
	# --- overlay menu: everything else
	var menu := Control.new()
	menu.name = "MinimalMenu"
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.visible = false
	overlay.add_child(menu)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			controller.toggle_menu())
	menu.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "GlassMenu"
	panel.custom_minimum_size = Vector2(minf(560.0, 480.0), 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var toolbar := m.find_child("Toolbar", true, false) as Control
	if toolbar != null:
		toolbar.get_parent().remove_child(toolbar)
		box.add_child(toolbar)
		var brand := toolbar.get_child(0) as Button
		if brand != null:
			brand.text = "Main menu and settings"
			brand.name = "MenuFirst"
	var actions: Control = m.start_button.get_parent()
	actions.get_parent().remove_child(actions)
	box.add_child(actions)
	m.claim_button.get_parent().remove_child(m.claim_button)
	box.add_child(m.claim_button)
	Kit.button(box, "Move history (H)", func():
		controller.toggle_menu()
		controller.toggle_drawer(), "", "list")
	Kit.button(box, "Close", func(): controller.toggle_menu(), "GhostButton")
	controller.menu = menu
	m.info_panel.visible = false
	# --- move-history drawer
	var drawer := PanelContainer.new()
	drawer.name = "HistoryDrawer"
	drawer.theme_type_variation = "GlassDrawer"
	drawer.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE, Control.PRESET_MODE_MINSIZE, 0)
	drawer.custom_minimum_size = Vector2(250, 0)
	drawer.offset_top = 72
	drawer.offset_bottom = -72
	drawer.offset_left = 40      # hidden: just past the right edge; open: -262 .. -12
	drawer.offset_right = 290
	drawer.visible = false
	overlay.add_child(drawer)
	var drawer_box := VBoxContainer.new()
	drawer_box.add_theme_constant_override("separation", 8)
	drawer.add_child(drawer_box)
	Kit.section_header(drawer_box, "Moves", "list")
	var history_frame: Control = m.history_text.get_parent()
	history_frame.get_parent().remove_child(history_frame)
	drawer_box.add_child(history_frame)
	controller.drawer = drawer
	place_plates(m, false)

## Far side plate top-center, near side plate bottom-center (the side the board faces is "near"), pinned with pin() below.
## Anchors a HUD element to an edge with ZERO-size offsets: the container then sizes itself from its own content on every layout pass
## (growing away from the edge), so a stale cached minimum size can never freeze a wrong height or width into the offsets.
static func pin(c: Control, preset: int, margin: float) -> void:
	c.set_anchors_preset(preset, true)
	c.offset_left = 0.0
	c.offset_right = 0.0
	c.offset_top = 0.0
	c.offset_bottom = 0.0
	match preset:
		Control.PRESET_CENTER_TOP:
			c.grow_horizontal = Control.GROW_DIRECTION_BOTH
			c.grow_vertical = Control.GROW_DIRECTION_END
			c.offset_top = margin
			c.offset_bottom = margin
		Control.PRESET_CENTER_BOTTOM:
			c.grow_horizontal = Control.GROW_DIRECTION_BOTH
			c.grow_vertical = Control.GROW_DIRECTION_BEGIN
			c.offset_top = -margin
			c.offset_bottom = -margin
		Control.PRESET_TOP_LEFT:
			c.grow_horizontal = Control.GROW_DIRECTION_END
			c.grow_vertical = Control.GROW_DIRECTION_END
			c.offset_left = margin
			c.offset_right = margin
			c.offset_top = margin
			c.offset_bottom = margin

static func place_plates(m: Control, flipped: bool) -> void:
	if not m.hud.get("minimal", false):
		return
	var near := "b" if flipped else "w"
	var far := "w" if flipped else "b"
	pin(m.hud["card_" + near], Control.PRESET_CENTER_BOTTOM, 8.0)
	pin(m.hud["card_" + far], Control.PRESET_CENTER_TOP, 8.0)

## After Hud.refresh: glass plates (the active one glows) and the self-fading toast.
static func after_refresh(m: Control) -> void:
	for side in ["w", "b"]:
		var card: PanelContainer = m.hud["card_" + side]
		card.theme_type_variation = "GlassPlateActive" if card.theme_type_variation == "PlayerCardActive" else "GlassPlate"
	var banner: PanelContainer = m.hud["banner"]
	var text: String = m.status_label.text
	if text == str(m.hud.get("toast_text", "")):
		return
	m.hud["toast_text"] = text
	banner.theme_type_variation = "GlassToast"
	banner.visible = true
	banner.modulate.a = 1.0
	var previous = banner.get_meta(&"toast") if banner.has_meta(&"toast") else null
	if previous is Tween and (previous as Tween).is_valid():
		(previous as Tween).kill()
	if not banner.is_inside_tree():
		return
	var tween := banner.create_tween()
	banner.set_meta(&"toast", tween)
	tween.tween_interval(TOAST_SECONDS)
	tween.tween_property(banner, "modulate:a", 0.0, 0.2 if Prefs.reduce_motion else 0.6)
	tween.tween_callback(func(): banner.visible = false)
