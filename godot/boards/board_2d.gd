class_name ChessBoard2D
extends Control
const UiPrefs = preload("res://ui/theme/ui_prefs.gd")  # colour-blind-safe highlight option
const Rules = preload("res://chess/chess_engine.gd")
const Interaction = preload("res://boards/board_interaction.gd")
const ATLAS = preload("res://assets/board/legions-drawn.png")
const ROLES = "pnbrqk"
var game: ClassicMatch
var interaction: BoardInteraction
var flipped = false
var animation_enabled = true
var _animation = 1.0
var _tween: Tween
var _prior: Dictionary = {}
var _current: Dictionary = {}
var _pressed = false
var _dragging = false
var _press_at = -1
var _pointer = Vector2.ZERO
var _press_position = Vector2.ZERO
var _finger = -1
var _font: Font
var _last_match_id = ""
var focused_square = 12

func setup(match_game: ClassicMatch, controls: BoardInteraction) -> void:
	game = match_game
	interaction = controls
	_font = ThemeDB.fallback_font
	interaction.selection_changed.connect(queue_redraw)
	game.changed.connect(sync_state)
	resized.connect(queue_redraw)
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Click or drag a piece. Tap a piece, then its destination on touch screens."
	sync_state()

func sync_state() -> void:
	var updated: Dictionary = {}
	for p in game.chess_state().pieces:
		updated[p.pieceId] = Rules.index(p.square)
	_prior = _current.duplicate() if _last_match_id == game.match_id else {}
	_last_match_id = game.match_id
	_current = updated
	if _tween:
		_tween.kill()
	_animation = 0.0 if animation_enabled and not _prior.is_empty() else 1.0
	_tween = create_tween()
	_tween.tween_method(_set_animation, _animation, 1.0, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	queue_redraw()

func _set_animation(value: float) -> void:
	_animation = value
	queue_redraw()

func board_rect() -> Rect2:
	var extent = maxf(8, minf(size.x, size.y) - 36)
	return Rect2((size - Vector2.ONE * extent) * 0.5, Vector2.ONE * extent)

func square_center(at: int) -> Vector2:
	var rect = board_rect()
	return rect.position + (Vector2(Interaction.cell(at, flipped)) + Vector2.ONE * 0.5) * rect.size.x / 8

func square_at(point: Vector2) -> int:
	var rect = board_rect()
	if not rect.has_point(point):
		return -1
	return Interaction.from_cell(Vector2i((point - rect.position) / (rect.size.x / 8)), flipped)

func set_flipped(value: bool) -> void:
	flipped = value
	queue_redraw()

func _piece(at: int, center: Vector2, scale_factor: float = 1.0) -> void:
	var p: String = game.engine.board[at]
	if p.is_empty():
		return
	var extent = board_rect().size.x / 8 * 0.98 * scale_factor
	var source = Rect2(ROLES.find(p.to_lower()) * 192, (0 if Rules.side(p) == "w" else 1) * 192, 192, 192)
	draw_texture_rect_region(ATLAS, Rect2(center - Vector2.ONE * extent * 0.5, Vector2.ONE * extent), source)

func _draw() -> void:
	if game == null:
		return
	var rect = board_rect()
	var pitch = rect.size.x / 8
	var frame = StyleBoxFlat.new()
	frame.bg_color = Color("233a40")
	frame.set_corner_radius_all(9)
	frame.set_border_width_all(1)
	frame.border_color = Color("476166")
	draw_style_box(frame, rect.grow(5))
	var last: Dictionary = game.engine.history[-1] if not game.engine.history.is_empty() else {}
	for at in range(64):
		var cell = Interaction.cell(at, flipped)
		var tile = Rect2(rect.position + Vector2(cell) * pitch, Vector2.ONE * pitch)
		var light = (at % 8 + at / 8) % 2 == 1
		draw_rect(tile, Color("d3d5bf") if light else Color("648788"))
		if not last.is_empty() and Rules.square(at) in [last.from, last.to]:
			draw_rect(tile, Color(0.93, 0.73, 0.28, 0.35))
		if at == interaction.selected:
			draw_rect(tile, Color(0.96, 0.79, 0.37, 0.65))
		if game.engine.board[at] == ("K" if game.engine.turn == "w" else "k") and game.engine.in_check():
			draw_circle(tile.get_center(), pitch * 0.48, Color(UiPrefs.capture_highlight(Color(0.9, 0.25, 0.25)), 0.75))
		for m in interaction.destinations:
			if m.to == at:
				if game.engine.board[at].is_empty() and m.flag != "ep":
					draw_circle(tile.get_center(), pitch * 0.13, Color(UiPrefs.move_highlight(Color(0.07, 0.24, 0.24)), 0.7 if UiPrefs.colorblind else 0.5))
				else:
					draw_arc(tile.get_center(), pitch * 0.43, 0, TAU, 48, UiPrefs.capture_highlight(Color("f4d78e")), 3, true)
	# Existing illustrated pieces, preserving stable IDs when animating promotions/castles.
	for id in _current:
		var at: int = _current[id]
		if _dragging and at == _press_at:
			continue
		var center = square_center(at)
		if _prior.has(id):
			center = square_center(_prior[id]).lerp(center, _animation)
		_piece(at, center)
	if _dragging and _press_at >= 0:
		_piece(_press_at, _pointer, 1.12)
	if has_focus():
		draw_rect(Rect2(square_center(focused_square) - Vector2.ONE * pitch * 0.47, Vector2.ONE * pitch * 0.94), Color("f4d78e"), false, 2)
	var font_size = clampi(int(pitch * 0.17), 10, 16)
	for file in range(8):
		var label = Rules.FILES[7 - file if flipped else file]
		draw_string(_font, Vector2(rect.position.x + pitch * (file + 0.5) - 4, rect.end.y + 17), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("a9bfc0"))
	for rank in range(8):
		draw_string(_font, Vector2(rect.position.x - 17, rect.position.y + pitch * (rank + 0.5) + 5), str(rank + 1 if flipped else 8 - rank), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("a9bfc0"))

func _pointer_press(point: Vector2) -> void:
	if not interaction.enabled or not game.board_input_allowed():
		return
	grab_focus()
	_pressed = true
	_dragging = false
	_press_position = point
	_pointer = point
	_press_at = square_at(point)
	if _press_at >= 0:
		focused_square = _press_at

func _pointer_move(point: Vector2) -> void:
	_pointer = point
	if _pressed and _press_at >= 0 and point.distance_to(_press_position) > 8 and Rules.side(game.engine.board[_press_at]) == game.engine.turn:
		if not _dragging:
			interaction.select(_press_at)
		_dragging = true
	queue_redraw()

func _pointer_release(point: Vector2) -> void:
	if not _pressed:
		return
	var at = square_at(point)
	if _dragging:
		if at >= 0 and at != _press_at:
			interaction.click(at)
	else:
		interaction.click(at)
	_pressed = false
	_dragging = false
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	# Touch has its own gesture path; avoid replaying its emulated mouse events.
	if (event is InputEventMouseButton or event is InputEventMouseMotion) and event.device == -1:
		return
	if event is InputEventKey and event.pressed:
		var cell = Interaction.cell(focused_square, flipped)
		match event.keycode:
			KEY_LEFT: cell.x = maxi(0, cell.x - 1)
			KEY_RIGHT: cell.x = mini(7, cell.x + 1)
			KEY_UP: cell.y = maxi(0, cell.y - 1)
			KEY_DOWN: cell.y = mini(7, cell.y + 1)
			KEY_ENTER, KEY_SPACE: interaction.click(focused_square)
			KEY_ESCAPE: interaction.clear()
			_: return
		focused_square = Interaction.from_cell(cell, flipped)
		queue_redraw()
		accept_event()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pointer_press(event.position)
		else:
			_pointer_release(event.position)
		accept_event()
	elif event is InputEventMouseMotion and _pressed:
		_pointer_move(event.position)
		accept_event()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or game == null:
		return
	if event is InputEventScreenTouch:
		if event.pressed and _finger == -1 and get_global_rect().has_point(event.position):
			_finger = event.index
			_pointer_press(event.position - global_position)
			get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == _finger:
			_pointer_release(event.position - global_position)
			_finger = -1
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == _finger:
		_pointer_move(event.position - global_position)
		get_viewport().set_input_as_handled()
