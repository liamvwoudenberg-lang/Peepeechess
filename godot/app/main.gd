extends Control
const AppSettings = preload("res://ui/application_settings.gd")
const AppResults = preload("res://ui/results.gd")
var _result_key = ""
const Match = preload("res://chess/classic_match.gd")
const Interaction = preload("res://boards/board_interaction.gd")
const Board2D = preload("res://boards/board_2d.gd")
const BattleMatch = preload("res://chess/battle_match.gd")
const CombatAdapter = preload("res://app/battle_combat_adapter.gd")
const Flow = preload("res://app/battle_flow.gd")
const Board3D = preload("res://boards/board_3d.gd")
var mode_select: OptionButton
var mode_label: Label
var copy_notation_button: Button
var battle_flow: BattleFlow
var battle_adapter: Node
var battle_overlay: Control
var combat_host: SubViewport
var combat_container: SubViewportContainer
var battle_title: Label
var battle_detail: Label
var battle_card: PanelContainer
var fight_button: Button
var battle_cancel: Button
var battle_return: Button
var battle_resign: Button
var _return_tween: Tween
var game = Match.new()
var interaction = Interaction.new(game)
var board_2d: ChessBoard2D
var board_3d: ChessBoard3D
var body: BoxContainer
var board_panel: PanelContainer
var info_panel: PanelContainer
var clock_white: Label
var clock_black: Label
var status_label: Label
var history_text: RichTextLabel
var view_button: Button
var flip_button: Button
var pause_button: Button
var undo_button: Button
var claim_button: Button
var start_button: Button
var message_label: Label
var promotion_dialog: ConfirmationDialog
var fen_dialog: ConfirmationDialog
var fen_edit: TextEdit
var new_dialog: ConfirmationDialog
var time_select: OptionButton
var _promotion: Dictionary = {}
var _fen_revision = -1
var _fen_match_id = ""
var _view_3d = false
var _flipped = false
var _claims: Array = []
var draw_dialog: ConfirmationDialog
var intended_edit: LineEdit
const TIME_CONTROLS = [["Untimed", 0, 0], ["Bullet · 1 + 0", 60000, 0], ["Blitz · 3 + 2", 180000, 2000], ["Blitz · 5 + 0", 300000, 0], ["Rapid · 10 + 0", 600000, 0], ["Rapid · 15 + 10", 900000, 10000], ["Classical · 30 + 0", 1800000, 0]]

func _ready() -> void:
	AppSettings.load_preferences()
	AppSettings.ensure_platform(get_tree())
	_build_theme()
	_build_ui()
	_build_dialogs()
	_build_battle_overlay()
	game.changed.connect(_refresh)
	game.rejected.connect(_message)
	interaction.move_requested.connect(_request_move)
	resized.connect(_responsive)
	get_tree().auto_accept_quit = true
	_responsive()
	_refresh()
	var launch = AppSettings.take_launch()
	if launch.get("mode", "classic") == "battle":
		_switch_mode(1)
	if not launch.is_empty():
		game.new_game(int(launch.get("initialMs", 600000)), int(launch.get("incrementMs", 0)))
		game.start_clock()
	set_view(bool(launch.get("view3d", AppSettings.preferred_3d)))
	board_2d.animation_enabled = AppSettings.animations
	board_3d.animation_enabled = AppSettings.animations

func _panel(color: Color, radius: int = 12) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.set_border_width_all(1)
	style.border_color = Color("334c54")
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	return style

func _build_theme() -> void:
	theme = Theme.new()
	theme.default_font_size = 17
	theme.set_color("font_color", "Label", Color("e6eddf"))
	theme.set_color("font_color", "Button", Color("e6eddf"))
	theme.set_color("font_hover_color", "Button", Color("fff5ce"))
	theme.set_color("font_disabled_color", "Button", Color("71858a"))
	for type_name in ["Button", "OptionButton"]:
		theme.set_stylebox("normal", type_name, _panel(Color("263c45"), 8))
		theme.set_stylebox("hover", type_name, _panel(Color("35535b"), 8))
		theme.set_stylebox("pressed", type_name, _panel(Color("47655e"), 8))
		theme.set_stylebox("disabled", type_name, _panel(Color("1a2c33"), 8))
		for state_name in ["normal", "hover", "pressed", "disabled"]:
			var button_style = theme.get_stylebox(state_name, type_name)
			button_style.content_margin_top = 8
			button_style.content_margin_bottom = 8
			button_style.content_margin_left = 12
			button_style.content_margin_right = 12
		var focus = _panel(Color(0, 0, 0, 0), 8)
		focus.border_color = Color("e2bd6f")
		focus.set_border_width_all(2)
		theme.set_stylebox("focus", type_name, focus)
	theme.set_stylebox("panel", "PopupMenu", _panel(Color("20363e")))
	theme.set_stylebox("panel", "AcceptDialog", _panel(Color("20363e")))
	theme.set_stylebox("normal", "TextEdit", _panel(Color("14272f"), 6))
	theme.set_color("font_color", "TextEdit", Color("e6eddf"))

func _button(parent: Node, text: String, action: Callable, tip: String = "") -> Button:
	var button = Button.new()
	button.text = text
	button.custom_minimum_size.y = 44
	button.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	button.tooltip_text = tip
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _label(parent: Node, text: String, font_size: int = 17, color: Color = Color("e6eddf")) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _build_ui() -> void:
	var background = ColorRect.new()
	background.color = Color("101f27")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(background)
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 20)
	add_child(margin)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var heading = HBoxContainer.new()
	heading.add_theme_constant_override("separation", 12)
	column.add_child(heading)
	var brand = _label(heading, "PEEPEECHESS", 28, Color("f0d69c"))
	brand.size_flags_horizontal = SIZE_EXPAND_FILL
	mode_label = _label(heading, "CLASSIC", 13, Color("85b9ae"))
	_label(column, "One match. Two perspectives.", 16, Color("a2b7b8"))
	var toolbar = HFlowContainer.new()
	toolbar.add_theme_constant_override("h_separation", 8)
	toolbar.add_theme_constant_override("v_separation", 6)
	column.add_child(toolbar)
	mode_select = OptionButton.new()
	mode_select.custom_minimum_size.y = 44
	mode_select.add_item("Classic Chess")
	mode_select.add_item("Battle Chess · C0")
	mode_select.item_selected.connect(_switch_mode)
	toolbar.add_child(mode_select)
	_button(toolbar, "Main menu", _main_menu, "Return to the application menu.")
	_button(toolbar, "Online", func(): get_tree().change_scene_to_file("res://network/client/online_lobby.tscn"), "Connect to a dedicated ENet server.")
	_button(toolbar, "New game", _show_new, "Choose a time control and start a local two-player match.")
	view_button = _button(toolbar, "3D board", func(): set_view(not _view_3d), "Switch views without restarting the match.")
	flip_button = _button(toolbar, "Flip board", func(): set_flipped(not _flipped), "Change only your local perspective.")
	_button(toolbar, "FEN / PGN", _show_position, "Import a position, or copy FEN and PGN.")
	var settings = CheckButton.new()
	settings.text = "Animate"
	settings.button_pressed = AppSettings.animations
	settings.tooltip_text = "Turn off movement animations."
	settings.toggled.connect(func(on): board_2d.animation_enabled = on; board_3d.animation_enabled = on; AppSettings.animations = on; AppSettings.save_preferences())
	toolbar.add_child(settings)
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	body = BoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_horizontal = SIZE_EXPAND_FILL
	body.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.add_child(body)
	board_panel = PanelContainer.new()
	board_panel.add_theme_stylebox_override("panel", _panel(Color("182e36")))
	board_panel.size_flags_horizontal = SIZE_EXPAND_FILL
	board_panel.size_flags_vertical = SIZE_EXPAND_FILL
	body.add_child(board_panel)
	var host = Control.new()
	host.size_flags_horizontal = SIZE_EXPAND_FILL
	host.size_flags_vertical = SIZE_EXPAND_FILL
	board_panel.add_child(host)
	board_2d = Board2D.new()
	board_2d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(board_2d)
	board_2d.setup(game, interaction)
	board_3d = Board3D.new()
	board_3d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(board_3d)
	board_3d.setup(game, interaction)
	board_3d.hide()
	board_3d.viewport_3d.render_target_update_mode = SubViewport.UPDATE_DISABLED
	info_panel = PanelContainer.new()
	info_panel.add_theme_stylebox_override("panel", _panel(Color("1b3039")))
	info_panel.size_flags_vertical = SIZE_EXPAND_FILL
	body.add_child(info_panel)
	var info = VBoxContainer.new()
	info.add_theme_constant_override("separation", 12)
	info_panel.add_child(info)
	_label(info, "LOCAL TWO-PLAYER", 12, Color("8fb5ad"))
	var clocks = HBoxContainer.new()
	clocks.add_theme_constant_override("separation", 18)
	info.add_child(clocks)
	for color in ["w", "b"]:
		var card = VBoxContainer.new()
		card.size_flags_horizontal = SIZE_EXPAND_FILL
		clocks.add_child(card)
		_label(card, "WHITE" if color == "w" else "BLACK", 12, Color("a2b7b8"))
		var clock = _label(card, "10:00", 31)
		if color == "w":
			clock_white = clock
		else:
			clock_black = clock
	status_label = _label(info, "White to move", 21)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size.y = 52
	var actions = HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 6)
	actions.add_theme_constant_override("v_separation", 6)
	info.add_child(actions)
	start_button = _button(actions, "Start clock", func(): game.start_clock())
	pause_button = _button(actions, "Pause", func(): game.set_paused(not game.paused))
	undo_button = _button(actions, "Undo", func(): game.undo(), "Local practice only. Restores the previous move and clock checkpoint.")
	_button(actions, "Resign", _confirm_resign)
	claim_button = _button(info, "Draw options", _show_draw)
	_label(info, "MOVE HISTORY", 12, Color("8fb5ad"))
	history_text = RichTextLabel.new()
	history_text.bbcode_enabled = true
	history_text.selection_enabled = true
	history_text.size_flags_vertical = SIZE_EXPAND_FILL
	history_text.custom_minimum_size = Vector2(0, 100)
	history_text.add_theme_font_size_override("normal_font_size", 18)
	info.add_child(history_text)
	var hint = _label(info, "Select a piece to see legal moves.\nTouch: tap a piece, then a square.", 13, Color("a2b7b8"))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label = _label(column, "Ready · Choose New game for time controls. Undo is available in local play.", 13, Color("a2b7b8"))
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _responsive() -> void:
	if body == null:
		return
	var narrow = size.x < 850
	body.vertical = narrow
	board_panel.custom_minimum_size = Vector2(0, clampf(size.x - 50, 300, 560) if narrow else 430)
	info_panel.custom_minimum_size = Vector2(0 if narrow else 300, 350 if narrow else 430)

func _build_dialogs() -> void:
	promotion_dialog = ConfirmationDialog.new()
	promotion_dialog.title = "Choose your promotion"
	promotion_dialog.dialog_text = "Your pawn has reached the final rank."
	promotion_dialog.get_ok_button().hide()
	var grid = GridContainer.new()
	grid.columns = 2
	promotion_dialog.add_child(grid)
	for item in [["Queen", "q"], ["Rook", "r"], ["Bishop", "b"], ["Knight", "n"]]:
		var role: String = item[1]
		var button = _button(grid, item[0], func(): _choose_promotion(role))
		button.size_flags_horizontal = SIZE_EXPAND_FILL
		button.custom_minimum_size.x = 120
	promotion_dialog.canceled.connect(func(): _promotion.clear(); interaction.clear())
	add_child(promotion_dialog)
	fen_dialog = ConfirmationDialog.new()
	fen_dialog.title = "Position & notation"
	fen_dialog.ok_button_text = "Load FEN as new game"
	fen_dialog.get_cancel_button().text = "Close"
	var box = VBoxContainer.new()
	fen_dialog.add_child(box)
	var instructions = _label(box, "Paste a FEN to start a new local match.\nClocks and history reset.\nCopy the current game first.", 15)
	fen_edit = TextEdit.new()
	fen_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	fen_edit.custom_minimum_size = Vector2(280, 100)
	box.add_child(fen_edit)
	var row = HFlowContainer.new()
	box.add_child(row)
	_button(row, "Copy FEN", func(): DisplayServer.clipboard_set(game.engine.fen()); _message("FEN copied."))
	copy_notation_button = _button(row, "Copy PGN", func(): DisplayServer.clipboard_set(game.engine.pgn()); _message("Battle log copied." if game is BattleChessMatch else "PGN copied."))
	fen_dialog.confirmed.connect(_load_position)
	add_child(fen_dialog)
	new_dialog = ConfirmationDialog.new()
	new_dialog.title = "New Classic game"
	new_dialog.dialog_text = "Two players, one device.\nChoose a time control."
	new_dialog.ok_button_text = "Start game"
	time_select = OptionButton.new()
	time_select.custom_minimum_size = Vector2(270, 48)
	for control in TIME_CONTROLS:
		time_select.add_item(control[0])
	time_select.select(4)
	new_dialog.add_child(time_select)
	new_dialog.confirmed.connect(_start_game)
	add_child(new_dialog)
	draw_dialog = ConfirmationDialog.new()
	draw_dialog.title = "Draw options"
	draw_dialog.ok_button_text = "Claim draw"
	var draw_box = VBoxContainer.new()
	draw_dialog.add_child(draw_box)
	var draw_help = _label(draw_box, "Claim threefold or fifty moves.\nFor a claim before your move, enter\nits coordinates below (e.g. g1f3).\nLeave blank for the current position.", 14)
	intended_edit = LineEdit.new()
	intended_edit.placeholder_text = "Intended move (optional)"
	intended_edit.max_length = 5
	intended_edit.custom_minimum_size.y = 44
	draw_box.add_child(intended_edit)
	_button(draw_box, "Agree a draw", _offer_draw)
	draw_dialog.confirmed.connect(_claim_draw)
	add_child(draw_dialog)

func _request_move(from: String, to: String, needs_promotion: bool) -> void:
	if needs_promotion:
		_promotion = {"from": from, "to": to, "revision": game.revision, "matchId": game.match_id}
		promotion_dialog.popup_centered(Vector2i(mini(500, int(size.x) - 24), 160))
	else:
		game.play(from, to)

func _choose_promotion(role: String) -> void:
	promotion_dialog.hide()
	if _promotion.is_empty() or _promotion.revision != game.revision or _promotion.matchId != game.match_id:
		_message("The position changed. Select the move again.")
		return
	game.play(_promotion.from, _promotion.to, role)
	_promotion.clear()

func _show_new() -> void:
	new_dialog.title = "New Battle Chess game" if game is BattleChessMatch else "New Classic game"
	new_dialog.dialog_text = "C0 uses untimed chess.\nCaptures become two-player combat." if game is BattleChessMatch else "Two players, one device.\nChoose a time control."
	time_select.disabled = game is BattleChessMatch
	new_dialog.popup_centered(Vector2i(mini(440, int(size.x) - 24), 180))

func _start_game() -> void:
	var control: Array = TIME_CONTROLS[time_select.selected]
	game.new_game(control[1], control[2])
	game.start_clock()
	_message("New Battle C0 game · chess is untimed." if game is BattleChessMatch else "New game · " + control[0])

func _show_position() -> void:
	fen_edit.text = game.engine.fen()
	_fen_revision = game.revision
	_fen_match_id = game.match_id
	fen_dialog.popup_centered(Vector2i(mini(680, int(size.x) - 24), 270))

func _load_position() -> void:
	if _fen_revision != game.revision or _fen_match_id != game.match_id:
		_message("The position changed while the dialog was open. Open it again.")
		return
	var outcome = game.new_game(game.initial_ms, game.increment_ms, fen_edit.text)
	if not outcome.ok:
		_message(outcome.error)
		fen_dialog.call_deferred("popup_centered", Vector2i(mini(680, int(size.x) - 24), 270))
	else:
		_message("Battle position loaded." if game is BattleChessMatch else "Position loaded. Start the clock when ready.")

func _confirm_resign() -> void:
	if not game.engine.result.is_empty():
		return
	var dialog = ConfirmationDialog.new()
	dialog.title = "Resign game?"
	dialog.dialog_text = ("White" if game.engine.turn == "w" else "Black") + " resigns. The opponent wins."
	dialog.ok_button_text = "Resign"
	dialog.confirmed.connect(func(): game.resign(); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()

func _show_draw() -> void:
	if game is BattleChessMatch:
		if not game.board_input_allowed():
			return
		_offer_draw()
		return
	intended_edit.text = ""
	draw_dialog.popup_centered(Vector2i(mini(480, int(size.x) - 24), 270))

func _offer_draw() -> void:
	draw_dialog.hide()
	var dialog = ConfirmationDialog.new()
	dialog.title = "Accept draw?"
	dialog.dialog_text = "Pass to the opponent.\nAccept to agree a draw."
	dialog.ok_button_text = "Accept draw"
	dialog.confirmed.connect(func(): game.agree_draw(); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()

func _claim_draw() -> void:
	var intended: Dictionary = {}
	var text = intended_edit.text.strip_edges().to_lower()
	if not text.is_empty():
		if text.length() not in [4, 5]:
			_message("Enter a move such as g1f3 or a7a8q.")
			return
		intended = {"from": text.substr(0, 2), "to": text.substr(2, 2), "promotion": text[4] if text.length() == 5 else "q"}
	_claims = game.engine.claimable_draws(intended)
	if _claims.is_empty():
		_message("No draw can be claimed for that position or intended move.")
	else:
		game.claim_draw(_claims[0], intended)

func set_view(use_3d: bool) -> void:
	_view_3d = use_3d
	AppSettings.preferred_3d = use_3d
	AppSettings.save_preferences()
	board_2d.visible = not use_3d
	board_3d.visible = use_3d
	board_3d.viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS if use_3d else SubViewport.UPDATE_DISABLED
	view_button.text = "2D board" if use_3d else "3D board"
	_message("3D · Right-drag to orbit, scroll to zoom. Touch: swipe / pinch." if use_3d else "2D · Click or drag to move. Touch: tap or drag.")

func set_flipped(value: bool) -> void:
	_flipped = value
	board_2d.set_flipped(value)
	board_3d.set_flipped(value)

func _time_text(ms: int) -> String:
	if not game.timed:
		return "—"
	var seconds = maxi(0, ceili(ms / 1000.0))
	if ms < 10000:
		return "%d.%d" % [ms / 1000, (ms % 1000) / 100]
	return "%d:%02d" % [seconds / 60, seconds % 60]

func _process(_delta: float) -> void:
	game.poll_clock()
	if is_instance_valid(battle_flow) and battle_flow.phase == "countdown":
		var snapshot = game.combat_snapshot()
		if not snapshot.is_empty():
			battle_title.text = "Battle begins in %d" % ceili(snapshot.countdownTicksRemaining / 60.0)
	if clock_white != null:
		clock_white.text = _time_text(game.remaining.w)
		clock_black.text = _time_text(game.remaining.b)

func _refresh() -> void:
	if status_label == null:
		return
	var color = "White" if game.engine.turn == "w" else "Black"
	if not game.engine.result.is_empty():
		var outcome = "Draw" if game.engine.result == "1/2-1/2" else ("White wins" if game.engine.result == "1-0" else "Black wins")
		status_label.text = outcome + "\n" + game.engine.reason
		if _result_key != game.match_id + game.engine.result:
			_result_key = game.match_id + game.engine.result
			call_deferred("_show_game_result", game.match_id, game.engine.result)
	elif game.paused:
		status_label.text = "Game paused"
	else:
		status_label.text = ("Check · " if game.engine.in_check() else "") + color + " to move"
	if game is BattleChessMatch and game.phase != "board":
		status_label.text = "Capture battle pending"
	clock_white.add_theme_color_override("font_color", Color("f0d69c") if game.engine.turn == "w" else Color("a2b7b8"))
	clock_black.add_theme_color_override("font_color", Color("f0d69c") if game.engine.turn == "b" else Color("a2b7b8"))
	pause_button.text = "Resume" if game.paused else "Pause"
	pause_button.disabled = not game.engine.result.is_empty() or game.authority_mode != "local" or (game is BattleChessMatch and game.phase != "board")
	undo_button.disabled = game.engine.history.is_empty() or not game.allow_undo or game.authority_mode != "local"
	start_button.visible = game.timed and not game.started and game.engine.result.is_empty()
	claim_button.disabled = not game.board_input_allowed()
	claim_button.text = "Claim draw available" if not game.engine.claimable_draws().is_empty() else "Draw options"
	history_text.clear()
	if game.engine.history.is_empty():
		history_text.append_text("[color=#829c9f]Your moves will appear here.[/color]")
	else:
		var fields = game.engine.initial_fen.split(" ")
		var color_to_play = fields[1]
		var number = int(fields[5])
		for i in range(game.engine.history.size()):
			if color_to_play == "w":
				history_text.append_text("[color=#829c9f]%d.[/color]  " % number)
			elif i == 0:
				history_text.append_text("[color=#829c9f]%d...[/color]  " % number)
			history_text.add_text(game.engine.history[i].san + ("\n" if color_to_play == "b" else "     "))
			if color_to_play == "b":
				number += 1
			color_to_play = ClassicChess.opposite(color_to_play)
		history_text.scroll_to_line(maxi(0, history_text.get_line_count() - 1))

func _message(text: String) -> void:
	if message_label != null:
		message_label.text = text

func _exit_tree() -> void:
	if is_instance_valid(battle_flow):
		battle_flow.dispose()
	interaction.dispose()

func _build_battle_overlay() -> void:
	battle_overlay = Control.new()
	battle_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(battle_overlay)
	var bg = ColorRect.new()
	bg.color = Color("101f27")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	battle_overlay.add_child(bg)
	combat_container = SubViewportContainer.new()
	combat_container.stretch = true
	combat_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	combat_container.offset_top = 72
	combat_container.offset_bottom = -80
	battle_overlay.add_child(combat_container)
	combat_host = SubViewport.new()
	combat_host.size = Vector2i(900, 600)
	combat_host.own_world_3d = true
	combat_host.render_target_update_mode = SubViewport.UPDATE_DISABLED
	combat_container.add_child(combat_host)
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	battle_overlay.add_child(center)
	battle_card = PanelContainer.new()
	battle_card.add_theme_stylebox_override("panel", _panel(Color("1b3039")))
	center.add_child(battle_card)
	var column = VBoxContainer.new()
	column.custom_minimum_size.x = 280
	column.add_theme_constant_override("separation", 12)
	battle_card.add_child(column)
	battle_detail = _label(column, "", 16)
	battle_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	battle_detail.custom_minimum_size.x = 280
	fight_button = _button(column, "Start battle", func(): battle_flow.confirm_capture())
	battle_cancel = _button(column, "Cancel capture", _cancel_battle_transition)
	battle_return = _button(column, "Return to board", func(): battle_flow.return_to_board())
	var header = MarginContainer.new()
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_left = 20
	header.offset_top = 16
	header.offset_right = -20
	battle_overlay.add_child(header)
	battle_title = _label(header, "Capture battle", 24, Color("f0d69c"))
	var footer = HBoxContainer.new()
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_left = 20
	footer.offset_right = -20
	footer.offset_top = -64
	battle_overlay.add_child(footer)
	battle_resign = _button(footer, "Acting player resigns", _confirm_resign)
	battle_overlay.hide()

func _switch_mode(index: int) -> void:
	if _return_tween:
		_return_tween.kill()
	if (index == 1) == (game is BattleChessMatch):
		return
	if is_instance_valid(battle_flow):
		battle_flow.dispose()
		battle_flow.queue_free()
		battle_flow = null
	if is_instance_valid(battle_adapter):
		battle_adapter.queue_free()
		battle_adapter = null
	game.changed.disconnect(_refresh)
	game.rejected.disconnect(_message)
	interaction.dispose()
	var board_host = board_2d.get_parent()
	for old in [board_2d, board_3d]:
		old.hide()
		board_host.remove_child(old)
		old.queue_free()
	game = BattleMatch.new() if index == 1 else Match.new()
	interaction = Interaction.new(game)
	game.changed.connect(_refresh)
	game.rejected.connect(_message)
	interaction.move_requested.connect(_request_move)
	board_2d = Board2D.new()
	board_2d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board_host.add_child(board_2d)
	board_2d.setup(game, interaction)
	board_3d = Board3D.new()
	board_3d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board_host.add_child(board_3d)
	board_3d.setup(game, interaction)
	mode_label.text = "BATTLE · C0" if index == 1 else "CLASSIC"
	board_2d.animation_enabled = AppSettings.animations
	board_3d.animation_enabled = AppSettings.animations
	mode_select.select(index)
	copy_notation_button.text = "Copy battle log" if index == 1 else "Copy PGN"
	if index == 1:
		_configure_battle_flow(CombatAdapter.new())
	game.new_game(0 if index == 1 else 600000)
	set_view(_view_3d)
	set_flipped(_flipped)
	battle_overlay.hide()
	_refresh()
	if index == 1:
		_message("Battle C0: kings do not duel. Combat is unavailable in this build." if not battle_adapter.available() else "Battle C0 · captures trigger combat; chess is untimed.")

func _configure_battle_flow(adapter: Node) -> void:
	if is_instance_valid(battle_flow):
		battle_flow.dispose()
		battle_flow.queue_free()
	if is_instance_valid(battle_adapter):
		battle_adapter.queue_free()
	battle_adapter = adapter
	add_child(adapter)
	battle_flow = Flow.new()
	add_child(battle_flow)
	battle_flow.setup(game, adapter, combat_host)
	battle_flow.phase_changed.connect(_battle_phase)
	battle_flow.preview_requested.connect(_capture_preview)
	battle_flow.result_ready.connect(_battle_result)
	battle_flow.returning_to_board.connect(_animate_board_return)
	battle_flow.failed.connect(_message)

func _capture_preview(request: Dictionary) -> void:
	var roles = {"p": "Pawn", "n": "Knight", "b": "Bishop", "r": "Rook", "q": "Queen", "k": "King"}
	var a: Dictionary = request.attacker
	var d: Dictionary = request.defender
	battle_detail.text = "%s %s → %s %s\nAttacker: %s · %s HP\nDefender: %s · %s HP\n\nAttacker wins: captures on %s.\nDefender wins: attacker is removed;\ndefender stays on %s." % [roles[a.role], request.from, roles[d.role], d.square, "White" if a.color == "w" else "Black", a.stats.maxHp, "White" if d.color == "w" else "Black", d.stats.maxHp, request.to, d.square]
	var readiness = battle_adapter.check_request(request) if battle_adapter.has_method("check_request") else {"ok": battle_adapter.available(), "error": "Combat is unavailable in this build."}
	if not readiness.ok:
		battle_detail.text += "\n\n" + readiness.error
	fight_button.disabled = not readiness.ok

func _battle_phase(value: String) -> void:
	AppSettings.set_combat_input(value in ["countdown", "combat", "aftermath"])
	interaction.enabled = value == "board"
	board_2d.set_process_input(value == "board")
	board_3d.set_process_input(value == "board")
	battle_overlay.visible = value not in ["board", "returning"]
	combat_container.visible = value in ["countdown", "combat"]
	combat_host.render_target_update_mode = SubViewport.UPDATE_ALWAYS if combat_container.visible else SubViewport.UPDATE_DISABLED
	battle_card.visible = value in ["preview", "loading", "aftermath"]
	fight_button.visible = value == "preview"
	battle_cancel.visible = value in ["preview", "loading"]
	battle_cancel.text = "Cancel capture" if value == "preview" else "Cancel loading"
	battle_return.visible = value == "aftermath"
	battle_resign.visible = value in ["countdown", "combat"]
	battle_title.text = {"preview": "Capture preview", "loading": "Loading arena…", "countdown": "Get ready", "combat": "Battle Chess · capture duel", "aftermath": "Battle result"}.get(value, "Battle Chess")
	if value == "loading":
		battle_detail.text = "Preparing the arena and two fighters…\nThe chess position is frozen."

func _cancel_battle_transition() -> void:
	if battle_flow.phase == "preview":
		battle_flow.cancel_preview()
	elif battle_flow.phase == "loading":
		battle_flow.interrupt("Loading canceled.")

func _battle_result(value: Dictionary) -> void:
	battle_detail.text = "%s wins\n%s\n\nAttacker HP: %s\nDefender HP: %s" % ["Attacker" if value.outcome == "attacker" else "Defender", value.reason.replace("_", " "), value.attackerHp, value.defenderHp]

func _animate_board_return() -> void:
	if _return_tween:
		_return_tween.kill()
	_return_tween = create_tween().set_parallel(true)
	if _view_3d and board_3d.animation_enabled:
		var camera = board_3d.camera
		camera.v_offset = 0.6
		_return_tween.tween_property(camera, "v_offset", 0.0, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	elif board_2d.animation_enabled:
		board_2d.modulate.a = 0.4
		_return_tween.tween_property(board_2d, "modulate:a", 1.0, 0.35)

func _main_menu() -> void:
	if game.engine.history.is_empty() or not game.engine.result.is_empty():
		get_tree().change_scene_to_file("res://ui/application.tscn")
		return
	var dialog = ConfirmationDialog.new()
	dialog.title = "Leave local match?"
	dialog.dialog_text = "This local match is not saved. Return to the main menu?"
	dialog.ok_button_text = "Main menu"
	dialog.confirmed.connect(func(): get_tree().change_scene_to_file("res://ui/application.tscn"))
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()

func _show_game_result(expected_match: String, expected_result: String) -> void:
	if game.match_id != expected_match or game.engine.result != expected_result:
		return
	AppResults.show_dialog(self, {"result": expected_result, "reason": game.engine.reason, "mode": "battle" if game is BattleChessMatch else "classic", "plies": game.engine.history.size()}, func(): pass, func(): get_tree().change_scene_to_file("res://ui/application.tscn"))
