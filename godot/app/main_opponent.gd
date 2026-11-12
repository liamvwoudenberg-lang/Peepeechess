class_name MainOpponent
extends Node
## Glue between the local game screen (app/main.gd) and the ComputerOpponent controller. main.gd only calls the
## small hooks below (install, apply_launch, start_selected, prepare_new_dialog, rebind, undo, resign_*, handle_draw_offer,
## decorate); all behaviour lives here and in chess/ai/computer_opponent.gd.
var main: Control
var computer: ComputerOpponent
var selection: Dictionary = OpponentUI.default_state()
var _section: VBoxContainer
var _caption: Label
var _dialog_box: VBoxContainer

static func install(host: Control) -> MainOpponent:
	var glue = MainOpponent.new()
	glue.name = "MainOpponent"
	host.add_child(glue)
	glue._setup(host)
	return glue

func _setup(host: Control) -> void:
	main = host
	computer = ComputerOpponent.new()
	computer.name = "ComputerOpponent"
	add_child(computer)
	computer.animation_busy = _board_busy
	computer.thinking_changed.connect(func(_thinking): main._refresh())
	computer.message.connect(func(text): main._message(text))
	_build_new_dialog_section()
	rebind()

func _board_busy() -> bool:
	if not is_instance_valid(main):
		return false
	var flat = main.board_2d
	if is_instance_valid(flat) and flat.visible and "_animation" in flat and flat._animation < 1.0:
		return true
	var solid = main.board_3d
	if is_instance_valid(solid) and solid.visible and "_moves" in solid:
		for tween in solid._moves:
			if tween.is_valid() and tween.is_running():
				return true
	return false

## Put the opponent picker above the time-control selector of the New game dialog. The dialog's box (built in main.gd,
## holding the caption label and the selector) is reused: the picker is inserted above the selector.
func _build_new_dialog_section() -> void:
	var dialog: ConfirmationDialog = main.new_dialog
	var selector: Control = main.time_select
	_dialog_box = selector.get_parent()
	_dialog_box.name = "NewGameBox"
	dialog.get_label().hide()  # the dialog's own label is sized to fill the window and left the dialog far taller than its content
	_section = VBoxContainer.new()
	_section.name = "OpponentSection"
	_section.add_theme_constant_override("separation", 8)
	_dialog_box.add_child(_section)
	_dialog_box.move_child(_section, selector.get_index())
	_caption = main.new_text  # main owns the caption label above the picker; this glue only sets its text
	_rebuild_section()

func _rebuild_section() -> void:
	OpponentUI.clear(_section)
	OpponentUI.build_kind_row(_section, selection, _rebuild_section, 1)
	if selection.kind == "computer":
		OpponentUI.build_computer_options(_section, selection, _rebuild_section, true)
	_update_dialog_text()

func _update_dialog_text() -> void:
	var battle = main.game is BattleChessMatch
	main.new_dialog.dialog_text = ""
	_caption.text = ("C0: untimed chess,\ncaptures become combat.\n" if battle else "Choose an opponent\nand a time control.\n") + OpponentUI.summary(selection)
	var width = mini(460, int(main.size.x) - 24)
	main.new_dialog.min_size = Vector2i(width, 120)
	main.new_dialog.size = Vector2i(width, 120)  # start small: the dialog grows to its content, never shrinks
	_settle_dialog.call_deferred()


## The dialog is first laid out far taller than its content (AcceptDialog fills the window on its first popup); shrink it
## a few frames later and it settles at exactly the content height.
func _settle_dialog() -> void:
	for i in 3:
		await get_tree().process_frame
	var dialog: ConfirmationDialog = main.new_dialog
	if is_instance_valid(dialog) and dialog.visible:
		dialog.size = Vector2i(dialog.size.x, 10)
		await get_tree().process_frame
		dialog.move_to_center()

## Called by main._show_new before the dialog is shown.
func prepare_new_dialog() -> void:
	_rebuild_section()

## Called by main._start_game after the new match exists.
func start_selected() -> void:
	if selection.kind == "computer":
		start_computer(selection)
	else:
		computer.end()
		main.interaction.allowed_side = ""

func start_computer(state: Dictionary) -> void:
	selection = OpponentUI.normalize(state)
	computer.bind(main.game, main.battle_adapter if "battle_adapter" in main else null)
	computer.begin({"level": selection.level, "color": selection.color})
	main.interaction.allowed_side = computer.human_color
	main.set_flipped(computer.human_color == "b")

## Called by main._ready with the launch dictionary from the Play page.
func apply_launch(launch: Dictionary) -> void:
	if launch.get("opponent", {}) is Dictionary and launch.get("opponent", {}).get("kind", "") == "computer":
		start_computer(launch.opponent)

## Called after the match object is replaced (Classic <-> Battle switch): rebind, and restart the computer game if one was running.
func rebind() -> void:
	var was_active = computer.active
	var state = {"level": computer.level, "color": computer.human_color}
	computer.bind(main.game, main.battle_adapter if "battle_adapter" in main else null)
	if was_active:
		computer.begin(state)
	main.interaction.allowed_side = computer.human_color if computer.active else ""

func undo() -> void:
	if computer.active:
		computer.undo()
	else:
		main.game.undo()

func resign_text(default_text: String) -> String:
	if not computer.active:
		return default_text
	return "You resign. The computer wins."

func resign() -> void:
	if computer.active:
		computer.human_resign()
	else:
		main.game.resign()

## Returns true when the computer handled a draw offer (the main screen then skips its own pass-the-device dialog).
func handle_draw_offer() -> bool:
	if not computer.active or not main.game.engine.result.is_empty():
		return false
	var answer = computer.respond_to_draw_offer()
	main._message(answer.text)
	return true

## Called at the end of main._refresh: opponent caption and "thinking" status.
func decorate() -> void:
	if not is_instance_valid(computer) or not is_instance_valid(main.info_panel):
		return
	if computer.is_thinking() and main.game.engine.result.is_empty():
		main.status_label.text += "\n" + computer.status_text()
	for label in main.info_panel.find_children("*", "Label", true, false):
		if label.text.begins_with("LOCAL TWO-PLAYER") or label.text.begins_with("VS COMPUTER"):
			label.text = "VS COMPUTER · LEVEL %d · YOU PLAY %s" % [computer.level, "WHITE" if computer.human_color == "w" else "BLACK"] if computer.active else "LOCAL TWO-PLAYER"
