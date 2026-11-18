class_name BoardSounds
extends Node
## Chess sounds for the board screens (local, hot-seat, computer and online): a move, a capture, castling, promotion, check, checkmate, and a
## "held the line" block when a Battle capture is defended. Listens to the match (`changed`) and reads the newest history entry; plays
## through a CombatAudio node on the SFX bus. Cosmetic only: it never writes to the match. Silent in headless runs and when UI sounds are off.
##
##   BoardSounds.attach(host, game, func(): return "w")   # viewer colour for win / lose (return "" for hot-seat: the winner is celebrated)
const CombatAudio = preload("res://combat/audio/combat_audio.gd")
const Prefs = preload("res://ui/theme/ui_prefs.gd")
const NODE_NAME := "BoardSounds"

var game
var viewer: Callable
var audio: Node
var _seen := 0
var _ended := false


static func attach(host: Node, match_game, viewer_color: Callable = Callable()) -> BoardSounds:
	if host == null or match_game == null or DisplayServer.get_name() == "headless":
		return null
	var existing := host.get_node_or_null(NODE_NAME) as BoardSounds
	if existing != null:
		existing.queue_free()   # a new match replaces the old listener
	var node := BoardSounds.new()
	node.name = NODE_NAME
	node.game = match_game
	node.viewer = viewer_color
	host.add_child(node)
	return node


func _ready() -> void:
	audio = CombatAudio.new()
	audio.name = "Audio"
	add_child(audio)
	_seen = game.engine.history.size()
	_ended = not game.engine.result.is_empty()
	game.changed.connect(_changed)


func _exit_tree() -> void:
	if game != null and is_instance_valid(game) and game.changed.is_connected(_changed):
		game.changed.disconnect(_changed)


## Which sound a history entry makes (pure, testable): checkmate > check > castle > promotion > capture / defended > plain move.
static func sound_for(entry: Dictionary) -> String:
	var san := String(entry.get("san", ""))
	if "#" in san:
		return "chess_checkmate"
	if "+" in san:
		return "chess_check"
	if san.begins_with("O-O"):
		return "chess_castle"
	if "=" in san:
		return "chess_promote"
	if "x" in san:
		return "block" if (String(entry.get("outcome", "")) == "defender" or "[defended]" in san) else "chess_capture"
	return "chess_move"


func _changed() -> void:
	var history: Array = game.engine.history
	if history.size() > _seen:
		_seen = history.size()
		if Prefs.ui_sounds:
			audio.play_sound(sound_for(history[history.size() - 1]))
	elif history.size() < _seen:
		_seen = history.size()   # undo / new game
	var over: bool = not game.engine.result.is_empty()
	if over and not _ended and Prefs.ui_sounds:
		var result := String(game.engine.result)
		var mate: bool = history.size() > 0 and "#" in String(history[history.size() - 1].get("san", ""))
		if not mate and result != "1/2-1/2":
			var mine: String = String(viewer.call()) if viewer.is_valid() else ""
			var white_won := result == "1-0"
			var won: bool = mine == "" or (mine == "w") == white_won
			audio.play_sound("chess_win" if won else "chess_lose")
	_ended = over
