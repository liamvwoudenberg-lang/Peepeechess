extends Control
const Music = preload("res://audio/music_director.gd")
const AppSettings = preload("res://ui/application_settings.gd")
const AppResults = preload("res://ui/results.gd")
const Hud = preload("res://ui/game_hud.gd")
const Balance = preload("res://combat/data/balance_data.gd")
const Kit = preload("res://ui/theme/ui_kit.gd")
const Tokens = preload("res://ui/theme/ui_tokens.gd")
const UiIcons = preload("res://ui/theme/ui_icons.gd")
const PeepeeTheme = preload("res://ui/theme/peepee_theme.gd")
var hud: Dictionary = {}  # nodes owned by the HUD (res://ui/game_hud.gd)
var _result_key = ""
const Match = preload("res://chess/classic_match.gd")
const Interaction = preload("res://boards/board_interaction.gd")
const Board2D = preload("res://boards/board_2d.gd")
const BattleMatch = preload("res://chess/battle_match.gd")
const BattleRoyalMatch = preload("res://chess/battle_royal_match.gd")  # king's last stand (battle-royal-v1), opt-in: see "king's last stand" blocks below
const RoyalPresenter = preload("res://app/royal_presenter.gd")
const CombatAdapter = preload("res://app/battle_combat_adapter.gd")
const Flow = preload("res://app/battle_flow.gd")
const Board3D = preload("res://boards/board_3d.gd")
const Bridge = preload("res://world/battle_bridge.gd")
const MainOpp = preload("res://app/main_opponent.gd")  # computer opponent glue (chess/ai); hooks marked "computer opponent" below
var opponent: MainOpponent
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
var battle_skip: Button
var battle_bg: ColorRect
var battle_scrim: ColorRect  # pit-world mode: dims the board and HUD behind the capture card (and blocks clicks on them)
var battle_footer: HBoxContainer  # "Acting player resigns" / "Skip animation"; see _place_battle_footer()
## pit world: both chess views are the same 3D board (top-down camera = "2D"); battles are presented
## inside it (trapdoor, chamber, ladder). false = the original Board2D + full-screen combat overlay.
var use_world = true
var bridge: WorldBattleBridge
var royal_presenter: RoyalPresenter  # king's last stand: banner / HUD context / result note (null unless the match is a BattleRoyalMatch)
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
var new_text: Label
var time_select: OptionButton
var _promotion: Dictionary = {}
var _fen_revision = -1
var _fen_match_id = ""
var _view_3d = false
var _overhead = false
var _flipped = false
var _claims: Array = []
var draw_dialog: ConfirmationDialog
var intended_edit: LineEdit
const TIME_CONTROLS = [["Untimed", 0, 0], ["Bullet · 1 + 0", 60000, 0], ["Blitz · 3 + 2", 180000, 2000], ["Blitz · 5 + 0", 300000, 0], ["Rapid · 10 + 0", 600000, 0], ["Rapid · 15 + 10", 900000, 10000], ["Classical · 30 + 0", 1800000, 0]]

func _ready() -> void:
	Music.go(get_tree(), "board")
	AppSettings.load_preferences()
	AppSettings.ensure_platform(get_tree())
	_build_theme()
	_build_ui()
	_build_dialogs()
	_build_battle_overlay()
	game.changed.connect(_refresh)
	game.rejected.connect(_reject)
	interaction.move_requested.connect(_request_move)
	resized.connect(_responsive)
	get_tree().auto_accept_quit = true
	_responsive()
	_refresh()
	var launch = AppSettings.take_launch()
	if launch.get("mode", "classic") == "battle":
		_switch_mode(1, bool(launch.get("royal", false)))  # king's last stand: the Play page's ruleset choice
	if not launch.is_empty():
		game.new_game(int(launch.get("initialMs", 600000)), int(launch.get("incrementMs", 0)))
		game.start_clock()
		opponent.apply_launch(launch)  # computer opponent
	set_view(bool(launch.get("view3d", AppSettings.preferred_3d)))
	board_2d.animation_enabled = AppSettings.animations
	board_3d.animation_enabled = AppSettings.animations
	PadUi.install(self, {"board": true, "scopes": ["battle_overlay"]})  # pad board cursor + menu focus (claude/pads-input)

func _panel(_color: Color = Tokens.SURFACE, _radius: int = 12) -> StyleBoxFlat:
	return PeepeeTheme.flat(Tokens.SURFACE_2, Tokens.GOLD_LO, 2, Tokens.R_LG, 20, 18)

func _build_theme() -> void:
	Kit.install(self)  # shared design-system theme (godot/ui/theme)

func _button(parent: Node, text: String, action: Callable, tip: String = "") -> Button:
	return Kit.button(parent, text, action, "", "", tip)

func _label(parent: Node, text: String, font_size: int = 17, color: Color = Tokens.TEXT) -> Label:
	var label = Kit.label(parent, text, "", false)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _build_ui() -> void:
	var host = Hud.build(self)  # toolbar, player cards, move list... (godot/ui/game_hud.gd); returns the board host
	board_2d = Board2D.new()
	board_2d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(board_2d)
	board_2d.setup(game, interaction)
	board_3d = Board3D.new()
	board_3d.hide()  # Hidden boards initialise on demand, avoiding 32 model allocations on Android.
	board_3d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(board_3d)
	board_3d.setup(game, interaction)
	board_2d.tooltip_text = ""
	board_3d.tooltip_text = ""
	board_3d.hide()
	board_3d.viewport_3d.render_target_update_mode = SubViewport.UPDATE_DISABLED

func _responsive() -> void:
	if body == null:
		return
	# Keep orientation as a public presentation property; the board never shares its width with a sidebar.
	body.vertical = size.x < 850
	board_panel.custom_minimum_size = Vector2.ZERO
	info_panel.custom_minimum_size = Vector2.ZERO
	Hud.layout(self)
	if is_instance_valid(board_2d):
		# The illustrated board gets clear space for the floating controls. The 3D world is edge to edge.
		board_2d.offset_top = 60
		board_2d.offset_bottom = -120

func _build_dialogs() -> void:
	promotion_dialog = ConfirmationDialog.new()
	promotion_dialog.title = "Choose your promotion"
	promotion_dialog.get_ok_button().hide()
	var promotion_box = VBoxContainer.new()  # text above the buttons: children added straight to a dialog are laid over its built-in text
	promotion_box.add_theme_constant_override("separation", 12)
	promotion_dialog.add_child(promotion_box)
	Kit.label(promotion_box, "Your pawn has reached the final rank.", "", false)
	var grid = GridContainer.new()
	grid.columns = 2
	promotion_box.add_child(grid)
	for item in [["Queen", "q"], ["Rook", "r"], ["Bishop", "b"], ["Knight", "n"]]:
		var role: String = item[1]
		var button = _button(grid, item[0], func(): _choose_promotion(role))
		button.icon = UiIcons.texture(Hud.ICON[role], 28)
		button.size_flags_horizontal = SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(150, 56)
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
	new_dialog.ok_button_text = "Start game"
	var new_box = VBoxContainer.new()  # text above the selector (children of a dialog are otherwise laid over its text)
	new_box.add_theme_constant_override("separation", 12)
	new_dialog.add_child(new_box)
	new_text = Kit.label(new_box, "Two players, one device.\nChoose a time control.", "", false)
	time_select = OptionButton.new()
	time_select.custom_minimum_size = Vector2(270, Kit.target_height())
	for control in TIME_CONTROLS:
		time_select.add_item(control[0])
	time_select.select(4)
	new_box.add_child(time_select)
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
	opponent = MainOpp.install(self)  # computer opponent: adds the opponent picker to the New game dialog

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
	new_text.text = "C0 uses untimed chess.\nCaptures become two-player combat." if game is BattleChessMatch else "Two players, one device.\nChoose a time control."
	time_select.disabled = game is BattleChessMatch
	opponent.prepare_new_dialog()  # computer opponent
	new_dialog.popup_centered(Vector2i(mini(440, int(size.x) - 24), 180))

func _start_game() -> void:
	opponent.apply_ruleset()  # king's last stand: swaps BattleMatch <-> BattleRoyalMatch when the dialog's toggle changed
	var control: Array = TIME_CONTROLS[time_select.selected]
	game.new_game(control[1], control[2])
	game.start_clock()
	_message(("New King's last stand game · chess is untimed." if game is BattleRoyalMatch else "New Battle C0 game · chess is untimed.") if game is BattleChessMatch else "New game · " + control[0])
	opponent.start_selected()  # computer opponent

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
	var who = "White" if game.engine.turn == "w" else "Black"
	Kit.confirm(self, "Resign game?", opponent.resign_text(who + " resigns. The opponent wins."), "Resign", func(): opponent.resign(), true)  # computer opponent

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
	if opponent.handle_draw_offer():  # computer opponent answers draw offers itself
		return
	Kit.confirm(self, "Accept draw?", "Pass to the opponent.\nAccept to agree a draw.", "Accept draw", func(): game.agree_draw())

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

## Pit-world mode: the footer buttons sit in the bottom-left corner of the BOARD panel (where the battle is shown), inside the part of
## it that is visible, so they never cover the player cards, toggles or status line around the board (in a portrait layout the player
## panel runs to the bottom of the screen). The legacy full-screen overlay keeps them at the bottom of the screen.
func _place_battle_footer() -> void:
	if battle_footer == null or not is_instance_valid(battle_overlay):
		return
	var view = battle_overlay.get_global_rect()
	var area = Rect2(view.position + Vector2(20, view.size.y - 80), Vector2(view.size.x - 40, 40))   # legacy overlay: bottom of the screen
	if use_world and is_instance_valid(board_panel) and board_panel.is_visible_in_tree():
		area = board_panel.get_global_rect()
		var scroller = body.get_parent() as Control if body != null else null
		if scroller != null:
			area = area.intersection(scroller.get_global_rect())   # the board panel can be taller than what is on screen
		if area.size.x <= 0.0 or area.size.y <= 0.0:
			return
		area = area.grow(-12.0)
	battle_footer.offset_left = area.position.x - view.position.x
	battle_footer.offset_right = area.end.x - view.end.x
	battle_footer.offset_bottom = area.end.y - view.end.y
	battle_footer.offset_top = battle_footer.offset_bottom - 52.0

func set_world_mode(value: bool) -> void:
	use_world = value
	call_deferred("_place_battle_footer")
	battle_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE if value else Control.MOUSE_FILTER_STOP
	battle_bg.visible = not value
	if is_instance_valid(battle_flow) and is_instance_valid(battle_adapter):
		_configure_battle_flow(battle_adapter)
	set_view(_view_3d)

func set_view(use_3d: bool) -> void:
	_view_3d = use_3d
	AppSettings.preferred_3d = use_3d
	AppSettings.save_preferences()
	# Illustrated 2D remains the original board projection, sharing the exact same match and interaction.
	# True overhead is an independent option on the 3D view, rather than silently replacing Classic 2D.
	board_2d.visible = not use_3d
	board_3d.visible = use_3d
	board_3d.set_top_down(_overhead)
	board_3d.viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS if use_3d else SubViewport.UPDATE_DISABLED
	view_button.text = "2D" if use_3d else "3D"
	Hud.layout(self)

func _toggle_overhead() -> void:
	_overhead = not _overhead
	if not _view_3d:
		set_view(true)
	else:
		board_3d.set_top_down(_overhead)
	if hud.has("overhead"):
		hud.overhead.text = "Angle" if _overhead else "Top"

func _toggle_fullscreen() -> void:
	preload("res://ui/screen_mode.gd").toggle()

func _unhandled_input(event: InputEvent) -> void:
	if hud.get("combat", false) or not event is InputEventKey or not event.pressed or event.echo:
		return  # the combat input source and its existing F1 overlay own these keys during duels
	var code: int = event.keycode if event.keycode != KEY_NONE else event.physical_keycode
	if code == KEY_F1:
		Hud.toggle_help(self)
		get_viewport().set_input_as_handled()
	elif code == KEY_ESCAPE:
		Hud.toggle_drawer(self)
		get_viewport().set_input_as_handled()

func set_flipped(value: bool) -> void:
	_flipped = value
	Hud.arrange(self, value)
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
	if not use_world and is_instance_valid(battle_flow) and battle_flow.phase == "countdown":
		var snapshot = game.combat_snapshot()
		if not snapshot.is_empty():
			battle_title.text = "Battle begins in %d" % ceili(snapshot.countdownTicksRemaining / 60.0)
	Hud.update_clocks(self)

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
	pause_button.text = "Resume" if game.paused else "Pause"
	pause_button.disabled = not game.engine.result.is_empty() or game.authority_mode != "local" or (game is BattleChessMatch and game.phase != "board")
	undo_button.disabled = game.engine.history.is_empty() or not game.allow_undo or game.authority_mode != "local"
	if undo_button.disabled:
		undo_button.tooltip_text = "Undo is available in local play once a move has been made."
	start_button.visible = game.timed and not game.started and game.engine.result.is_empty()
	claim_button.disabled = not game.board_input_allowed()
	claim_button.tooltip_text = "Draw options are available on your turn." if claim_button.disabled else ""
	claim_button.text = "Claim draw available" if not game.engine.claimable_draws().is_empty() else "Draw options"
	Hud.refresh(self)  # turn / check / result banner, captured material, move list
	if opponent != null:
		opponent.decorate()  # computer opponent: caption + "thinking" status

func _message(text: String) -> void:
	if message_label != null:
		message_label.text = text

## Rejected input (illegal move, wrong turn...): the status line AND a toast, so it is never a silent failure.
func _reject(text: String) -> void:
	Music.error_cue(get_tree())
	_message(text)
	Kit.toast(self, text, "warning")

func _exit_tree() -> void:
	if is_instance_valid(bridge):
		bridge.dispose()
	if is_instance_valid(royal_presenter):
		royal_presenter.dispose()  # king's last stand
	if is_instance_valid(battle_flow):
		battle_flow.dispose()
	interaction.dispose()

func _build_battle_overlay() -> void:
	battle_overlay = Control.new()
	battle_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(battle_overlay)
	var bg = ColorRect.new()
	bg.color = Tokens.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	battle_overlay.add_child(bg)
	battle_bg = bg
	battle_scrim = ColorRect.new()
	battle_scrim.name = "PreviewScrim"
	battle_scrim.color = Color(Tokens.BG, 0.6)
	battle_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	battle_scrim.visible = false
	battle_overlay.add_child(battle_scrim)
	combat_container = SubViewportContainer.new()
	combat_container.stretch = true
	combat_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	combat_container.offset_top = 0
	combat_container.offset_bottom = 0   # the combat viewport fills the available display
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
	battle_card.theme_type_variation = "RaisedPanel"
	center.add_child(battle_card)
	var column = VBoxContainer.new()
	column.custom_minimum_size.x = 280
	column.add_theme_constant_override("separation", 14)
	battle_card.add_child(column)
	battle_detail = _label(column, "", 16)
	battle_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	battle_detail.custom_minimum_size.x = 260
	battle_detail.theme_type_variation = "Muted"
	fight_button = Kit.primary(column, "Start battle", _start_battle_pressed, "sword")
	battle_cancel = _button(column, "Cancel capture", _cancel_battle_transition)
	battle_return = Kit.primary(column, "Return to board", func(): battle_flow.return_to_board())
	var header = MarginContainer.new()
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_left = 20
	header.offset_top = 16
	header.offset_right = -20
	battle_overlay.add_child(header)
	battle_title = Kit.label(header, "Capture battle", "H2", false)
	var footer = HBoxContainer.new()
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_left = 20
	footer.offset_right = -20
	footer.offset_top = -80
	footer.offset_bottom = -40   # above the status line at the very bottom of the screen: the buttons must not cover that text
	battle_footer = footer
	battle_overlay.add_child(footer)
	battle_resign = Kit.danger(footer, "Acting player resigns", _confirm_resign, "flag")
	battle_skip = _button(footer, "Skip animation", func(): if is_instance_valid(bridge): bridge.skip_to_board(), "Commit the result now and return to the board.")
	for footer_button in [battle_resign, battle_skip]:
		footer_button.size_flags_vertical = Control.SIZE_SHRINK_END   # natural height, not stretched to the footer's
	battle_skip.hide()
	battle_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE if use_world else Control.MOUSE_FILTER_STOP
	battle_bg.visible = not use_world
	battle_overlay.hide()

func _switch_mode(index: int, royal: bool = false) -> void:
	if _return_tween:
		_return_tween.kill()
	# king's last stand: the same mode with a different ruleset (royal) rebuilds the match object too
	if (index == 1) == (game is BattleChessMatch) and (index != 1 or royal == (game is BattleRoyalMatch)):
		return
	if is_instance_valid(bridge):
		bridge.dispose()
		bridge.queue_free()
		bridge = null
	if is_instance_valid(royal_presenter):  # king's last stand
		royal_presenter.dispose()
		royal_presenter.queue_free()
		royal_presenter = null
	if is_instance_valid(battle_flow):
		battle_flow.dispose()
		battle_flow.queue_free()
		battle_flow = null
	if is_instance_valid(battle_adapter):
		battle_adapter.queue_free()
		battle_adapter = null
	game.changed.disconnect(_refresh)
	game.rejected.disconnect(_reject)
	interaction.dispose()
	var board_host = board_2d.get_parent()
	for old in [board_2d, board_3d]:
		old.hide()
		board_host.remove_child(old)
		old.queue_free()
	game = (BattleRoyalMatch.new() if royal else BattleMatch.new()) if index == 1 else Match.new()
	interaction = Interaction.new(game)
	game.changed.connect(_refresh)
	game.rejected.connect(_reject)
	interaction.move_requested.connect(_request_move)
	board_2d = Board2D.new()
	board_2d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board_host.add_child(board_2d)
	board_2d.setup(game, interaction)
	board_3d = Board3D.new()
	board_3d.hide()  # Hidden boards initialise on demand, avoiding 32 model allocations on Android.
	board_3d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board_host.add_child(board_3d)
	board_3d.setup(game, interaction)
	mode_label.text = ("BATTLE · LAST STAND" if royal else "BATTLE · C0") if index == 1 else "CLASSIC"
	board_2d.animation_enabled = AppSettings.animations
	board_3d.animation_enabled = AppSettings.animations
	mode_select.select(index)
	mode_select.set_item_text(1, "Battle Chess · Last stand" if royal else "Battle Chess · C0")  # king's last stand
	copy_notation_button.text = "Copy battle log" if index == 1 else "Copy PGN"
	if index == 1:
		_configure_battle_flow(CombatAdapter.new())
	game.new_game(0 if index == 1 else 600000)
	set_view(_view_3d)
	set_flipped(_flipped)
	opponent.rebind()  # computer opponent follows the new match object
	battle_overlay.hide()
	_refresh()
	if index == 1:
		_message("Battle C0: kings do not duel. Combat is unavailable in this build." if not battle_adapter.available() else ("King's last stand · a checkmate becomes a duel for the King; chess is untimed." if royal else "Battle C0 · captures trigger combat; chess is untimed."))

func _configure_battle_flow(adapter: Node) -> void:
	if is_instance_valid(bridge):
		bridge.dispose()
		bridge.queue_free()
		bridge = null
	if is_instance_valid(battle_flow):
		battle_flow.dispose()
		battle_flow.queue_free()
	if is_instance_valid(battle_adapter) and battle_adapter != adapter:
		battle_adapter.queue_free()
	battle_adapter = adapter
	if adapter.get_parent() == null:
		add_child(adapter)
	battle_flow = Flow.new()
	add_child(battle_flow)
	# World mode: the arena is mounted inside the persistent 3D world, below the board.
	battle_flow.setup(game, adapter, board_3d.world.chamber.arena_mount if use_world else combat_host)
	if use_world:
		bridge = Bridge.new()
		add_child(bridge)
		bridge.setup(battle_flow, adapter, board_3d.world)
		bridge.presenting_changed.connect(_world_presenting_changed)
	# king's last stand: the banner / HUD context presenter exists only for a BattleRoyalMatch
	if is_instance_valid(royal_presenter):
		royal_presenter.dispose()
		royal_presenter.queue_free()
		royal_presenter = null
	if game is BattleRoyalMatch:
		royal_presenter = RoyalPresenter.new()
		add_child(royal_presenter)
		royal_presenter.setup(self, battle_flow, adapter)
	battle_flow.phase_changed.connect(_battle_phase)
	battle_flow.preview_requested.connect(_capture_preview)
	battle_flow.result_ready.connect(_battle_result)
	battle_flow.returning_to_board.connect(_animate_board_return)
	battle_flow.failed.connect(_message)

func _capture_preview(request: Dictionary) -> void:
	if battle_flow.is_royal_duel():
		return  # king's last stand: the duel is mandatory; RoyalPresenter shows the banner instead of the capture preview
	var a: Dictionary = request.attacker
	var d: Dictionary = request.defender
	Hud.show_versus(self, request)
	battle_detail.text = "Attacker wins: captures on %s.\nDefender wins: the attacker is removed and the defender stays on %s." % [request.to, d.square]
	var advantage := Balance.describe_edge(str(a.role), str(d.role))  # the attacker's advantage, in words (data/balance_v1.json)
	if advantage != "":
		battle_detail.text += "\n\n" + advantage
	var readiness = battle_adapter.check_request(request) if battle_adapter.has_method("check_request") else {"ok": battle_adapter.available(), "error": "Combat is unavailable in this build."}
	if not readiness.ok:
		battle_detail.text += "\n\n" + readiness.error
	fight_button.disabled = not readiness.ok
	if not readiness.ok:
		fight_button.tooltip_text = str(readiness.error)

func _start_battle_pressed() -> void:
	if use_world and is_instance_valid(bridge):
		var response = bridge.start_battle()
		if not response.get("ok", false):
			_message(str(response.get("error", "The battle could not start.")))
		return
	battle_flow.confirm_capture()

func _world_presenting_changed(presenting: bool) -> void:
	Hud.set_combat(self, presenting)
	if is_instance_valid(battle_flow):
		interaction.enabled = battle_flow.phase == "board" and not presenting

func _battle_phase_world(value: String) -> void:
	Hud.set_combat(self, value in ["loading", "countdown", "combat", "aftermath", "returning"])
	var presenting = is_instance_valid(bridge) and bridge.is_presenting()
	interaction.enabled = value == "board" and not presenting
	board_2d.set_process_input(false)
	board_3d.set_process_input(value == "board")
	battle_overlay.visible = value not in ["board", "returning"]
	combat_container.visible = false
	combat_host.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var capture_preview = value == "preview" and not battle_flow.is_royal_duel()  # king's last stand: banner instead of the preview card
	battle_card.visible = capture_preview
	battle_scrim.visible = capture_preview   # the card floats over the live HUD: dim it so text does not run into the card
	_place_battle_footer()
	fight_button.visible = capture_preview
	battle_cancel.visible = capture_preview
	battle_cancel.text = "Cancel capture"
	battle_return.visible = false
	battle_resign.visible = false
	battle_skip.visible = false
	battle_title.text = {"preview": "Capture preview", "loading": "The board opens…", "countdown": "Get ready", "combat": "Battle Chess · capture duel", "aftermath": "Battle result"}.get(value, "Battle Chess")
	battle_title.visible = false  # the preview card has its own heading; the combat HUD carries its own title/countdown

func _battle_phase(value: String) -> void:
	Music.go(get_tree(), {"preview": "preview", "loading": "pit", "countdown": "pit", "combat": "combat", "aftermath": "pit", "board": "board", "returning": "board"}.get(value, "board"))
	AppSettings.set_combat_input(value in ["countdown", "combat", "aftermath"])
	Hud.set_versus_visible(self, value == "preview")
	if use_world:
		_battle_phase_world(value)
		return
	battle_title.visible = true
	interaction.enabled = value == "board"
	board_2d.set_process_input(value == "board")
	board_3d.set_process_input(value == "board")
	battle_overlay.visible = value not in ["board", "returning"]
	combat_container.visible = value in ["countdown", "combat"]
	combat_host.render_target_update_mode = SubViewport.UPDATE_ALWAYS if combat_container.visible else SubViewport.UPDATE_DISABLED
	var royal_banner = value == "preview" and battle_flow.is_royal_duel()  # king's last stand: RoyalPresenter's banner replaces the preview card
	battle_card.visible = value in ["preview", "loading", "aftermath"] and not royal_banner
	fight_button.visible = value == "preview" and not royal_banner
	battle_cancel.visible = value in ["preview", "loading"] and not (battle_flow.is_royal_duel() and value == "preview")
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
	Music.go(get_tree(), "victory")   # the fight is decided: the score resolves (stinger) while the pit shows the aftermath
	if use_world:
		_message("%s wins the duel · %s." % ["Attacker" if value.outcome == "attacker" else "Defender", value.reason.replace("_", " ")])
	battle_detail.text = "%s wins\n%s\n\nAttacker HP: %s\nDefender HP: %s" % ["Attacker" if value.outcome == "attacker" else "Defender", value.reason.replace("_", " "), value.attackerHp, value.defenderHp]

func _animate_board_return() -> void:
	if use_world:
		return  # PitSequence already returned the camera and the winner
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
	_navigate_menu(false)

func _online_menu() -> void:
	_navigate_menu(true)

func _navigate_menu(open_online: bool) -> void:
	var leave = func():
		AppSettings.launch = {"menu": "online", "mode": "battle" if game is BattleChessMatch else "classic"} if open_online else {}
		get_tree().change_scene_to_file("res://ui/application.tscn")
	if game.engine.history.is_empty() or not game.engine.result.is_empty():
		leave.call()
		return
	Kit.confirm(self, "Leave local match?", "This local match is not saved. Return to the main menu?", "Main menu", leave, true)

func _show_game_result(expected_match: String, expected_result: String) -> void:
	if game.match_id != expected_match or game.engine.result != expected_result:
		return
	var data = {"result": expected_result, "reason": game.engine.reason, "mode": "battle" if game is BattleChessMatch else "classic", "plies": game.engine.history.size()}
	if is_instance_valid(royal_presenter) and not royal_presenter.result_note().is_empty():
		data["note"] = royal_presenter.result_note()  # king's last stand: why this checkmate stands
	AppResults.show_dialog(self, data, func(): pass, func(): get_tree().change_scene_to_file("res://ui/application.tscn"))
