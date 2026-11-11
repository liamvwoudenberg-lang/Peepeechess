class_name OpponentUI
extends RefCounted
## Opponent selector shared by the Play page and the New game dialog:
## Local two-player / Computer (level 1-6, colour White / Black / Random) / Online (Play page only).
## State is a plain Dictionary {kind: "local" | "computer", level: 1-6, color: "w" | "b" | "random"} owned by the caller;
## controls call `on_change` after editing it so the caller can rebuild its page.
const KINDS = ["local", "computer"]
const COLORS = [["w", "White"], ["b", "Black"], ["random", "Random"]]

static func default_state() -> Dictionary:
	return {"kind": "local", "level": 3, "color": "random"}

static func normalize(state: Dictionary) -> Dictionary:
	var clean = default_state()
	if str(state.get("kind", "local")) in KINDS:
		clean.kind = str(state.get("kind", "local"))
	clean.level = clampi(int(state.get("level", 3)), ChessAI.MIN_LEVEL, ChessAI.MAX_LEVEL)
	clean.color = str(state.get("color", "random")) if str(state.get("color", "random")) in ["w", "b", "random"] else "random"
	return clean

static func summary(state: Dictionary) -> String:
	if state.get("kind", "local") != "computer":
		return "Two players, one device"
	# Two short lines: the dialog label does not wrap, so long lines would widen the dialog on phones.
	return "Computer · level %d %s\n%s" % [state.level, ChessAI.level_name(state.level), {"w": "You play White", "b": "You play Black", "random": "Random colour"}[state.color]]

## Selected look for toggle buttons: readable in both the application theme and the game-screen theme.
static func style_toggle(button: Button) -> void:
	for state in ["pressed", "hover_pressed"]:
		var style = StyleBoxFlat.new()
		style.bg_color = Color("4f7352") if state == "pressed" else Color("5b8460")
		style.set_corner_radius_all(9)
		style.set_border_width_all(2)
		style.border_color = Color("e5c586")
		style.content_margin_left = 12
		style.content_margin_right = 12
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_pressed_color", Color("fff5ce"))
	button.add_theme_color_override("font_hover_pressed_color", Color("fff5ce"))

static func _toggle(parent: Node, text: String, pressed: bool, node_name: String, action: Callable) -> Button:
	var button = Button.new()
	button.name = node_name
	button.text = text
	button.toggle_mode = true
	button.button_pressed = pressed
	button.custom_minimum_size.y = 44
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	style_toggle(button)
	# `pressed` (not `toggled`) so a click always selects, never un-selects.
	button.pressed.connect(action)
	parent.add_child(button)
	return button

## Wrapping row on the Play page; with `columns` > 0 a fixed grid (dialogs: a flow container inside an auto-sizing
## dialog briefly measures a one-button-wide column and leaves the dialog far too tall).
static func _flow(parent: Node, columns: int = 0) -> Container:
	var flow: Container
	if columns > 0:
		flow = GridContainer.new()
		flow.columns = columns
	else:
		flow = HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	parent.add_child(flow)
	return flow

static func _caption(parent: Node, text: String, size_px: int = 14, color: Color = Color("b6c4b5")) -> Label:
	var label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

## Local / Computer toggle row (the Play page adds its own Online button next to these).
static func build_kind_row(parent: Node, state: Dictionary, on_change: Callable, columns: int = 0) -> Container:
	var row = _flow(parent, columns)
	row.name = "OpponentKind"
	_toggle(row, "Local · two players", state.kind == "local", "Opponent_Local", func(): state.kind = "local"; on_change.call())
	_toggle(row, "Computer", state.kind == "computer", "Opponent_Computer", func(): state.kind = "computer"; on_change.call())
	return row

## Level and colour pickers; only meaningful when state.kind == "computer".
static func build_computer_options(parent: Node, state: Dictionary, on_change: Callable, compact: bool = false) -> VBoxContainer:
	var box = VBoxContainer.new()
	box.name = "ComputerOptions"
	box.add_theme_constant_override("separation", 8)
	parent.add_child(box)
	_caption(box, "DIFFICULTY", 13, Color("e5c586"))
	var levels = _flow(box, 3 if compact else 0)
	for level in range(ChessAI.MIN_LEVEL, ChessAI.MAX_LEVEL + 1):
		var chosen: int = level
		_toggle(levels, str(level), state.level == level, "Level_%d" % level, func(): state.level = chosen; on_change.call())
	if compact:
		_caption(box, "Level %d · %s" % [state.level, ChessAI.level_name(state.level)]).autowrap_mode = TextServer.AUTOWRAP_OFF
	else:
		_caption(box, "Level %d · %s — %s" % [state.level, ChessAI.level_name(state.level), describe_level(state.level)])
	_caption(box, "YOU PLAY", 13, Color("e5c586"))
	var colors = _flow(box, 3 if compact else 0)
	for entry in COLORS:
		var value: String = entry[0]
		_toggle(colors, entry[1], state.color == value, "Color_" + value, func(): state.color = value; on_change.call())
	return box

static func describe_level(level: int) -> String:
	return {1: "plays quickly and makes many mistakes", 2: "sees one or two moves ahead", 3: "solid club player, rare blunders", 4: "calculates several moves, tactically alert", 5: "strong tactics, little forgiveness", 6: "strongest setting, uses the full time budget"}.get(level, "")

## Removes every child of `box` (queue_free) so a section can be rebuilt after a state change.
static func clear(box: Node) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
