class_name BoardInteraction
extends RefCounted
signal selection_changed
signal move_requested(from: String, to: String, promotion_needed: bool)
const Rules = preload("res://chess/chess_engine.gd")
var game: ClassicMatch
var enabled = true
var selected = -1
var destinations: Array = []

func _init(match_game: ClassicMatch) -> void:
	game = match_game
	game.changed.connect(clear)

func dispose() -> void:
	if game.changed.is_connected(clear):
		game.changed.disconnect(clear)

func clear() -> void:
	selected = -1
	destinations.clear()
	selection_changed.emit()

func select(at: int) -> void:
	if not enabled or at < 0 or at >= 64 or not game.board_input_allowed():
		clear()
		return
	if Rules.side(game.engine.board[at]) != game.engine.turn:
		clear()
		return
	selected = at
	destinations = game.engine.legal_moves(at)
	selection_changed.emit()

func click(at: int) -> void:
	if not enabled or not game.board_input_allowed():
		return
	if at < 0:
		clear()
		return
	if selected >= 0 and at != selected:
		for m in destinations:
			if m.to == at:
				move_requested.emit(Rules.square(selected), Rules.square(at), not m.promotion.is_empty())
				return
	if at == selected:
		clear()
	else:
		select(at)

static func world_position(at: int) -> Vector3:
	return Vector3(at % 8 - 3.5, 0, 3.5 - at / 8)

static func cell(at: int, flipped: bool) -> Vector2i:
	return Vector2i(7 - at % 8, at / 8) if flipped else Vector2i(at % 8, 7 - at / 8)

static func from_cell(value: Vector2i, flipped: bool) -> int:
	if value.x < 0 or value.x > 7 or value.y < 0 or value.y > 7:
		return -1
	return (7 - value.x) + value.y * 8 if flipped else value.x + (7 - value.y) * 8
