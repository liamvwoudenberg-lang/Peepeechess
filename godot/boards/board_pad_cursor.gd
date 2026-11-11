class_name BoardPadCursor
extends Node
## Gamepad (and optional keyboard) cursor for the chess boards, built on the existing BoardInteraction API only:
## it moves a cursor over the 64 squares and calls `interaction.select()` / `interaction.click()` /
## `interaction.clear()`, exactly as a mouse click would. Nothing in the rules, the match or the views changes.
##
## Pad map (SDL names; DualShock 4 in brackets):
##   D-pad / left stick   move the cursor (screen-relative: up is up on screen in 2D, flipped and 3D views)
##   A (Cross)            select the piece under the cursor / confirm the move to the highlighted square
##   B (Circle)           cancel the selection (or the promotion picker)
##   Y (Triangle)         jump to the next piece of the side to move
##   LB / RB (L1 / R1)    with a piece selected: previous / next legal destination
##   Start (Options)      `menu_requested` (the host switches between board and menu focus)
## Whose pad? `strict_turns` = true: the pad assigned to the side to move (White = Player 1, Black = Player 2 via
## InputAssignment) is the only one that acts; with a single pad that pad plays both sides. `strict_turns` = false
## (Classic hot-seat): any connected pad may play whoever's turn it is. The keyboard (arrows, Enter/Space, Esc) is
## handled only when `keyboard` is true (the 2D board already has its own keyboard focus handling).
##
## Promotion: by default the host's dialog handles `move_requested(..., promotion_needed)` (the dialog is reachable
## with D-pad + Cross through PadUi). With `own_promotion_picker` the cursor instead shows a Queen/Rook/Bishop/Knight
## picker (D-pad left/right, Cross confirm, Circle cancel) and plays the move itself through `game.play`.

signal cursor_moved(square: int)
signal menu_requested
signal promotion_chosen(from: String, to: String, role: String)
## Fired whenever the cursor consumed a pad / key event (PadUi uses it to know a pad is in use).
signal input_used

const Rules = preload("res://chess/chess_engine.gd")
const Interaction = preload("res://boards/board_interaction.gd")
const REPEAT_DELAY := 0.32
const REPEAT_RATE := 0.14
const STICK_ON := 0.6
const STICK_OFF := 0.35
const PROMOTION_ROLES := ["q", "r", "b", "n"]
const PROMOTION_NAMES := {"q": "Queen", "r": "Rook", "b": "Bishop", "n": "Knight"}

var game
var interaction: BoardInteraction
var assignment: InputAssignment
var active: bool = true
var strict_turns: bool = true
var keyboard: bool = false
var own_promotion_picker: bool = false
var cursor: int = 12  # e2
var show_cursor: bool = false
## Quarter turns of the view (0 = White at the bottom). Set by the host (2D flipped = 2; 3D from its yaw).
var quarter_turns_provider: Callable = Callable()
## square -> Rect2 in the overlay's coordinates, or an empty Rect2 when unknown (the cursor then draws nothing).
var square_rect_provider: Callable = Callable()
var promoting: Dictionary = {}  # {"from","to","index"} while the picker is open
var last_message: String = ""

var _overlay: Control
var _stick: Dictionary = {}  # device -> {"dir": Vector2i, "t": float, "armed": bool}


static func create(p_game, p_interaction: BoardInteraction, p_assignment: InputAssignment = null) -> BoardPadCursor:
	var c := BoardPadCursor.new()
	c.name = "BoardPadCursor"
	c.game = p_game
	c.interaction = p_interaction
	c.assignment = p_assignment if p_assignment != null else InputAssignment.shared()
	p_game.changed.connect(c._on_game_changed)
	return c


func _on_game_changed() -> void:
	promoting.clear()
	_redraw()


func attach_overlay(host: Control) -> void:
	if _overlay != null:
		_overlay.queue_free()
	_overlay = _CursorOverlay.new()
	_overlay.cursor = self
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.name = "PadCursorOverlay"
	host.add_child(_overlay)


func _exit_tree() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_free()


# ---- who may act ---------------------------------------------------------------------------------------------
func allowed_device(device: int) -> bool:
	var pads := assignment.connected_pads()
	if not (device in pads):
		return false
	if not strict_turns or pads.size() < 2:
		return true
	var slot := 0 if game.engine.turn == "w" else 1
	return assignment.device_for_slot(slot) == device


func is_usable() -> bool:
	return active and game != null and interaction != null and interaction.enabled and game.board_input_allowed()


# ---- cursor movement ---------------------------------------------------------------------------------------
func _quarter_turns() -> int:
	var q: int = int(quarter_turns_provider.call()) if quarter_turns_provider.is_valid() else 0
	return posmod(q, 4)


## Screen direction (x right, y DOWN as on screen: up = (0,-1)) -> (file, rank) step for the current view.
func screen_to_board(direction: Vector2i) -> Vector2i:
	var up: Vector2i = [Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, 0)][_quarter_turns()]
	var right: Vector2i = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)][_quarter_turns()]
	return right * direction.x + up * -direction.y


func move_cursor(direction: Vector2i) -> void:
	var step := screen_to_board(direction)
	var file := clampi(cursor % 8 + step.x, 0, 7)
	var rank := clampi(cursor / 8 + step.y, 0, 7)
	set_cursor(file + rank * 8)


func set_cursor(square: int) -> void:
	square = clampi(square, 0, 63)
	show_cursor = true
	if square != cursor:
		cursor = square
		cursor_moved.emit(square)
	_redraw()


# ---- actions ------------------------------------------------------------------------------------------------
## Cross / Enter: select, or confirm the move to the cursor square.
func confirm() -> void:
	if not is_usable():
		return
	if not promoting.is_empty():
		_finish_promotion()
		return
	if own_promotion_picker and interaction.selected >= 0:
		for m in interaction.destinations:
			if m.to == cursor and not m.promotion.is_empty():
				promoting = {"from": Rules.square(interaction.selected), "to": Rules.square(cursor), "index": 0}
				last_message = "Choose a promotion piece"
				_redraw()
				return
	var before: int = interaction.selected
	interaction.click(cursor)
	if interaction.selected < 0 and before < 0:
		last_message = "Nothing to select there"
	else:
		last_message = ""
	_redraw()


## Circle / Esc: back out one step. Returns true if something was cancelled (so a host can fall through to "back").
func cancel() -> bool:
	if not promoting.is_empty():
		promoting.clear()
		interaction.clear()
		_redraw()
		return true
	if interaction != null and interaction.selected >= 0:
		interaction.clear()
		_redraw()
		return true
	return false


func jump_to_next_piece() -> void:
	if not is_usable():
		return
	var mine: Array[int] = []
	for at in 64:
		var p: String = game.engine.board[at]
		if not p.is_empty() and Rules.side(p) == game.engine.turn:
			mine.append(at)
	if mine.is_empty():
		return
	var next: int = mine[0]
	for at in mine:
		if at > cursor:
			next = at
			break
	set_cursor(next)


## With a piece selected: step the cursor through its legal destinations (L1 / R1).
func cycle_destination(step: int) -> void:
	if not is_usable() or interaction.destinations.is_empty():
		return
	var squares: Array[int] = []
	for m in interaction.destinations:
		if not (m.to in squares):
			squares.append(m.to)
	squares.sort()
	var index := squares.find(cursor)
	if index < 0:
		index = 0 if step > 0 else squares.size() - 1
	else:
		index = posmod(index + step, squares.size())
	set_cursor(squares[index])


func picker_move(step: int) -> void:
	if promoting.is_empty():
		return
	promoting["index"] = posmod(int(promoting["index"]) + step, PROMOTION_ROLES.size())
	_redraw()


func _finish_promotion() -> void:
	var role: String = PROMOTION_ROLES[int(promoting["index"])]
	var from: String = promoting["from"]
	var to: String = promoting["to"]
	promoting.clear()
	promotion_chosen.emit(from, to, role)
	game.play(from, to, role)
	_redraw()


# ---- input ----------------------------------------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and show_cursor and (event as InputEventMouseMotion).relative.length() > 2.0:
		show_cursor = false  # the mouse took over: hide the ring until the next pad / key press
		_redraw()
	if not is_usable() or _popup_open():
		return
	if event is InputEventJoypadButton:
		if event.pressed and allowed_device(int(event.device)) and _pad_button(int(event.button_index)):
			input_used.emit()
			get_viewport().set_input_as_handled()
	elif event is InputEventJoypadMotion:
		if int(event.axis) in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y] and allowed_device(int(event.device)):
			if absf(event.axis_value) > 0.5:
				input_used.emit()
			get_viewport().set_input_as_handled()  # the stick drives the cursor, not menu focus
	elif keyboard and event is InputEventKey and event.pressed and not event.echo and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
		if _key(int(event.keycode)):
			input_used.emit()
			get_viewport().set_input_as_handled()


func _pad_button(button: int) -> bool:
	if not promoting.is_empty():
		match button:
			JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_LEFT_SHOULDER:
				picker_move(-1)
			JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN:
				picker_move(1)
			JOY_BUTTON_A:
				confirm()
			JOY_BUTTON_B:
				cancel()
			_:
				return false
		return true
	match button:
		JOY_BUTTON_DPAD_UP:
			move_cursor(Vector2i(0, -1))
		JOY_BUTTON_DPAD_DOWN:
			move_cursor(Vector2i(0, 1))
		JOY_BUTTON_DPAD_LEFT:
			move_cursor(Vector2i(-1, 0))
		JOY_BUTTON_DPAD_RIGHT:
			move_cursor(Vector2i(1, 0))
		JOY_BUTTON_A:
			show_cursor = true
			confirm()
		JOY_BUTTON_B:
			if not cancel():
				return false  # nothing to cancel: let the host treat it as "back"
		JOY_BUTTON_Y:
			jump_to_next_piece()
		JOY_BUTTON_LEFT_SHOULDER:
			cycle_destination(-1)
		JOY_BUTTON_RIGHT_SHOULDER:
			cycle_destination(1)
		JOY_BUTTON_START:
			menu_requested.emit()
		_:
			return false
	return true


func _key(code: int) -> bool:
	if not promoting.is_empty():
		match code:
			KEY_LEFT:
				picker_move(-1)
			KEY_RIGHT, KEY_UP, KEY_DOWN:
				picker_move(1)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				confirm()
			KEY_ESCAPE:
				cancel()
			_:
				return false
		return true
	match code:
		KEY_UP:
			move_cursor(Vector2i(0, -1))
		KEY_DOWN:
			move_cursor(Vector2i(0, 1))
		KEY_LEFT:
			move_cursor(Vector2i(-1, 0))
		KEY_RIGHT:
			move_cursor(Vector2i(1, 0))
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			show_cursor = true
			confirm()
		KEY_ESCAPE:
			if not cancel():
				return false
		_:
			return false
	return true


## Left stick: digital steps with auto-repeat (8-way, dominant axis wins), per allowed device.
func _process(delta: float) -> void:
	if not is_usable() or _popup_open() or not promoting.is_empty():
		_stick.clear()
		return
	for device in assignment.connected_pads():
		if not allowed_device(device):
			_stick.erase(device)
			continue
		var v := Vector2(Input.get_joy_axis(device, JOY_AXIS_LEFT_X), Input.get_joy_axis(device, JOY_AXIS_LEFT_Y))
		var state: Dictionary = _stick.get(device, {"dir": Vector2i.ZERO, "t": 0.0})
		var dir := Vector2i.ZERO
		var threshold := STICK_OFF if state["dir"] != Vector2i.ZERO else STICK_ON
		if v.length() >= threshold:
			var major := maxf(absf(v.x), absf(v.y))
			dir = Vector2i(roundi(signf(v.x)) if absf(v.x) >= major * 0.5 else 0, roundi(signf(v.y)) if absf(v.y) >= major * 0.5 else 0)
		if dir == Vector2i.ZERO:
			_stick[device] = {"dir": Vector2i.ZERO, "t": 0.0}
			continue
		if dir != state["dir"]:
			move_cursor(dir)
			_stick[device] = {"dir": dir, "t": -REPEAT_DELAY}
		else:
			var t: float = float(state["t"]) + delta
			while t >= REPEAT_RATE:
				move_cursor(dir)
				t -= REPEAT_RATE
			_stick[device] = {"dir": dir, "t": t}


## A visible dialog (promotion, resign, FEN...) owns the pad.
func _popup_open() -> bool:
	if not is_inside_tree():
		return false
	for child in get_tree().root.get_children():
		if child is Window and child.visible:
			return true
	return false


func _redraw() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_redraw()


class _CursorOverlay:
	extends Control
	var cursor: BoardPadCursor

	func _draw() -> void:
		if cursor == null or not cursor.active or not cursor.show_cursor or not cursor.square_rect_provider.is_valid():
			return
		if cursor.interaction == null or not cursor.interaction.enabled:
			return
		var rect: Rect2 = cursor.square_rect_provider.call(cursor.cursor)
		if rect.size == Vector2.ZERO:
			return
		var ring := rect.grow(-rect.size.x * 0.04)
		draw_rect(ring, Color(0.35, 0.8, 1.0, 0.2), true)
		draw_rect(ring, Color(0.45, 0.88, 1.0, 0.95), false, maxf(3.0, rect.size.x * 0.06))
		var arm := rect.size.x * 0.18
		for corner in [ring.position, ring.position + Vector2(ring.size.x, 0), ring.position + Vector2(0, ring.size.y), ring.end]:
			draw_circle(corner, arm * 0.18, Color.WHITE)
		if not cursor.promoting.is_empty():
			_draw_picker(rect)

	func _draw_picker(anchor: Rect2) -> void:
		var font := ThemeDB.fallback_font
		var cell := Vector2(96, 44)
		var count: int = BoardPadCursor.PROMOTION_ROLES.size()
		var panel := Rect2(anchor.get_center() - Vector2(cell.x * count * 0.5, cell.y * 1.6), Vector2(cell.x * count, cell.y))
		panel.position = panel.position.clamp(Vector2(4, 4), (size - panel.size - Vector2(4, 4)).max(Vector2(4, 4)))
		draw_rect(panel.grow(6), Color(0.08, 0.14, 0.17, 0.96), true)
		draw_string(font, panel.position + Vector2(4, -10), "Promote to:", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.95, 0.85, 0.5))
		for i in count:
			var cell_rect := Rect2(panel.position + Vector2(cell.x * i, 0), cell)
			var chosen: bool = i == int(cursor.promoting["index"])
			draw_rect(cell_rect.grow(-2), Color(0.95, 0.78, 0.35, 0.9) if chosen else Color(0.2, 0.3, 0.34), true)
			draw_string(font, cell_rect.position + Vector2(8, 29), BoardPadCursor.PROMOTION_NAMES[BoardPadCursor.PROMOTION_ROLES[i]], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.05, 0.08, 0.1) if chosen else Color.WHITE)
