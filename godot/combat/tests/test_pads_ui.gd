extends RefCounted
## Board cursor, menu focus and the controls screen, driven by injected pad / key events (no physical pad; see
## test_pads.gd for what is and is not proven).

const Pads := preload("res://combat/tests/test_pads.gd")
const Settings := preload("res://ui/application_settings.gd")
const AppScene := preload("res://ui/application.tscn")
const MainScene := preload("res://app/main.tscn")
const Match := preload("res://chess/classic_match.gd")
const TMP := "user://pads_test/ui_controls.json"
const PROMO_FEN := "7k/P7/8/8/8/8/8/K7 w - - 0 1"


static func run(h, tree: SceneTree) -> void:
	await _cursor_logic(h, tree)
	await _cursor_promotion(h, tree)
	await _application_focus(h, tree)
	await _controls_screen(h, tree)
	await _main_scene(h, tree)


# ---- helpers ---------------------------------------------------------------------------------------------------
static func press(device: int, button: int, tree: SceneTree) -> void:
	Pads.btn(device, button, true)
	Input.flush_buffered_events()
	await tree.process_frame
	await tree.process_frame
	Pads.btn(device, button, false)
	Input.flush_buffered_events()
	await tree.process_frame


static func press_key(code: int, tree: SceneTree) -> void:
	Pads.key(code, true)
	Input.flush_buffered_events()
	await tree.process_frame
	await tree.process_frame
	Pads.key(code, false)
	Input.flush_buffered_events()
	await tree.process_frame


static func frames(tree: SceneTree, n: int = 2) -> void:
	for _i in n:
		await tree.process_frame


static func focus_ok(tree: SceneTree) -> bool:
	var owner := tree.root.gui_get_focus_owner()
	return owner != null and owner.is_visible_in_tree() and owner.focus_mode == Control.FOCUS_ALL and not (owner is BaseButton and (owner as BaseButton).disabled)


static func fresh_match(fen: String = "") -> Array:
	var game := Match.new()
	game.new_game(0, 0) if fen.is_empty() else game.new_game(0, 0, fen)
	return [game, BoardInteraction.new(game)]


# ---- cursor ---------------------------------------------------------------------------------------------------------
static func _cursor_logic(h, tree: SceneTree) -> void:
	h.begin("board cursor: D-pad moves, Cross selects, legal moves highlight, Cross confirms (existing BoardInteraction API)")
	var bindings := ControlBindings.new()
	var assignment := Pads.fake_assignment(bindings, [0, 1])
	var pair := fresh_match()
	var game = pair[0]
	var interaction: BoardInteraction = pair[1]
	var moves: Array = []
	interaction.move_requested.connect(func(from, to, promo): moves.append([from, to, promo]); game.play(from, to))
	var cursor := BoardPadCursor.create(game, interaction, assignment)
	tree.root.add_child(cursor)
	h.eq(cursor.cursor, 12, "the cursor starts on e2")
	await press(0, JOY_BUTTON_DPAD_RIGHT, tree)
	h.eq(cursor.cursor, 13, "D-pad right -> f2")
	await press(0, JOY_BUTTON_DPAD_UP, tree)
	h.eq(cursor.cursor, 21, "D-pad up -> f3 (rank increases for White)")
	await press(0, JOY_BUTTON_DPAD_LEFT, tree)
	await press(0, JOY_BUTTON_DPAD_DOWN, tree)
	h.eq(cursor.cursor, 12, "left then down -> e2 again")
	cursor.set_cursor(0)
	await press(0, JOY_BUTTON_DPAD_LEFT, tree)
	await press(0, JOY_BUTTON_DPAD_DOWN, tree)
	h.eq(cursor.cursor, 0, "the cursor stops at the edge of the board")
	cursor.set_cursor(63)
	await press(0, JOY_BUTTON_DPAD_RIGHT, tree)
	await press(0, JOY_BUTTON_DPAD_UP, tree)
	h.eq(cursor.cursor, 63, "...on every edge")

	h.begin("board cursor: whose pad? the side to move's pad only; the other player's pad is ignored")
	cursor.set_cursor(12)
	await press(1, JOY_BUTTON_DPAD_UP, tree)
	h.eq(cursor.cursor, 12, "White to move: pad 1 (Black's) does nothing")
	await press(1, JOY_BUTTON_A, tree)
	h.eq(interaction.selected, -1, "...and cannot select")
	await press(2, JOY_BUTTON_DPAD_UP, tree)
	h.eq(cursor.cursor, 12, "a pad that is not connected / not assigned does nothing")
	await press(0, JOY_BUTTON_DPAD_UP, tree)
	h.eq(cursor.cursor, 20, "pad 0 (White's) moves it")

	h.begin("board cursor: select, highlight legal destinations, confirm, cancel")
	cursor.set_cursor(12)
	await press(0, JOY_BUTTON_A, tree)
	h.eq(interaction.selected, 12, "Cross on e2 selects the pawn")
	var squares: Array = []
	for m in interaction.destinations:
		squares.append(m.to)
	squares.sort()
	h.eq(squares, [20, 28], "its legal destinations (e3, e4) are highlighted by the existing selection state")
	await press(0, JOY_BUTTON_B, tree)
	h.eq(interaction.selected, -1, "Circle cancels the selection")
	await press(0, JOY_BUTTON_A, tree)
	await press(0, JOY_BUTTON_A, tree)
	h.eq(interaction.selected, -1, "Cross on the selected piece again deselects it (same as a second click)")
	await press(0, JOY_BUTTON_A, tree)
	cursor.set_cursor(36)  # e5: empty, not a destination
	await press(0, JOY_BUTTON_A, tree)
	h.eq(interaction.selected, -1, "Cross on an empty non-destination square clears (a click elsewhere)")
	cursor.set_cursor(52)  # e7: a Black pawn
	await press(0, JOY_BUTTON_A, tree)
	h.eq(interaction.selected, -1, "cannot select the opponent's piece")
	cursor.set_cursor(12)
	await press(0, JOY_BUTTON_A, tree)
	await press(0, JOY_BUTTON_DPAD_UP, tree)
	await press(0, JOY_BUTTON_DPAD_UP, tree)
	h.eq(cursor.cursor, 28, "cursor on e4")
	await press(0, JOY_BUTTON_A, tree)
	h.eq(moves, [["e2", "e4", false]], "Cross on a highlighted square emits move_requested(e2, e4, no promotion)")
	h.eq(game.engine.turn, "b", "the host played it; Black is to move")
	h.eq(interaction.selected, -1, "the selection cleared")

	h.begin("board cursor: Black's turn belongs to pad 1; pad 0 is ignored")
	cursor.set_cursor(52)
	await press(0, JOY_BUTTON_DPAD_LEFT, tree)
	h.eq(cursor.cursor, 52, "Black to move: pad 0 does nothing")
	await press(1, JOY_BUTTON_DPAD_LEFT, tree)
	h.eq(cursor.cursor, 51, "pad 1 moves the cursor")
	await press(1, JOY_BUTTON_A, tree)
	h.eq(interaction.selected, 51, "pad 1 selects Black's d7 pawn")
	await press(1, JOY_BUTTON_B, tree)

	h.begin("board cursor: Classic (strict_turns = false) lets either pad play; a single pad plays both sides")
	cursor.strict_turns = false
	cursor.set_cursor(51)
	await press(0, JOY_BUTTON_DPAD_LEFT, tree)
	h.eq(cursor.cursor, 50, "either pad in Classic")
	cursor.strict_turns = true
	Pads.set_pads(assignment, [0])
	await press(0, JOY_BUTTON_DPAD_LEFT, tree)
	h.eq(cursor.cursor, 49, "with one pad connected it controls Black as well")
	Pads.set_pads(assignment, [])
	await press(0, JOY_BUTTON_DPAD_LEFT, tree)
	h.eq(cursor.cursor, 49, "with no pad connected pad events do nothing")
	Pads.set_pads(assignment, [0, 1])

	h.begin("board cursor: Triangle jumps to the next own piece; L1/R1 step through the legal destinations")
	game.undo()
	cursor.set_cursor(0)
	await press(0, JOY_BUTTON_Y, tree)
	h.eq(cursor.cursor, 1, "from a1 the next White piece is b1")
	await press(0, JOY_BUTTON_Y, tree)
	h.eq(cursor.cursor, 2, "then c1")
	cursor.set_cursor(1)
	await press(0, JOY_BUTTON_A, tree)
	h.eq(interaction.selected, 1, "knight b1 selected")
	await press(0, JOY_BUTTON_RIGHT_SHOULDER, tree)
	h.eq(cursor.cursor, 16, "R1 -> first destination (a3)")
	await press(0, JOY_BUTTON_RIGHT_SHOULDER, tree)
	h.eq(cursor.cursor, 18, "R1 -> c3")
	await press(0, JOY_BUTTON_RIGHT_SHOULDER, tree)
	h.eq(cursor.cursor, 16, "R1 wraps")
	await press(0, JOY_BUTTON_LEFT_SHOULDER, tree)
	h.eq(cursor.cursor, 18, "L1 steps back")
	await press(0, JOY_BUTTON_B, tree)

	h.begin("board cursor: the view's rotation maps screen directions (flipped 2D = 2 quarter turns, 3D yaw)")
	var turns := [0]
	cursor.quarter_turns_provider = func(): return turns[0]
	cursor.set_cursor(27)  # d4
	turns[0] = 2
	await press(0, JOY_BUTTON_DPAD_UP, tree)
	h.eq(cursor.cursor, 19, "flipped: up on screen is DOWN the ranks (d3)")
	await press(0, JOY_BUTTON_DPAD_RIGHT, tree)
	h.eq(cursor.cursor, 18, "flipped: right on screen is towards the a-file (c3)")
	turns[0] = 1
	cursor.set_cursor(27)
	await press(0, JOY_BUTTON_DPAD_UP, tree)
	h.eq(cursor.cursor, 26, "quarter turn 1 (camera yaw 90 degrees): up goes towards the a-file (c4)")
	await press(0, JOY_BUTTON_DPAD_RIGHT, tree)
	h.eq(cursor.cursor, 34, "...and right goes up the ranks (c5)")
	turns[0] = 3
	cursor.set_cursor(27)
	await press(0, JOY_BUTTON_DPAD_UP, tree)
	h.eq(cursor.cursor, 28, "quarter turn 3: up goes towards the h-file (e4)")
	turns[0] = 0

	h.begin("board cursor: left stick = digital steps with auto-repeat, dead zone, no ghost steps")
	cursor.set_cursor(24)  # a4
	Pads.axis(0, JOY_AXIS_LEFT_X, 0.3)
	Input.flush_buffered_events()
	await frames(tree, 6)
	h.eq(cursor.cursor, 24, "a weak push (0.3) does nothing")
	Pads.axis(0, JOY_AXIS_LEFT_X, 1.0)
	Input.flush_buffered_events()
	await frames(tree, 3)
	h.eq(cursor.cursor, 25, "a full push moves exactly one square at first")
	await tree.create_timer(0.25).timeout
	h.eq(cursor.cursor, 25, "...and waits for the repeat delay")
	await tree.create_timer(0.7).timeout
	h.check(cursor.cursor >= 28, "...then repeats while held (now %d)" % cursor.cursor)
	Pads.axis(0, JOY_AXIS_LEFT_X, 0.0)
	Input.flush_buffered_events()
	await frames(tree, 3)
	var rest := cursor.cursor
	await tree.create_timer(0.5).timeout
	h.eq(cursor.cursor, rest, "releasing the stick stops it")
	Pads.axis(1, JOY_AXIS_LEFT_X, 1.0)  # not White's pad
	Input.flush_buffered_events()
	await tree.create_timer(0.5).timeout
	h.eq(cursor.cursor, rest, "the other player's stick never moves the cursor")
	Pads.release_all()

	h.begin("board cursor: inactive when the host disables the board (battle phases) or a dialog is open; keyboard only when enabled")
	cursor.set_cursor(12)
	interaction.enabled = false
	await press(0, JOY_BUTTON_DPAD_UP, tree)
	h.eq(cursor.cursor, 12, "interaction.enabled = false -> pad ignored")
	interaction.enabled = true
	cursor.active = false
	await press(0, JOY_BUTTON_DPAD_UP, tree)
	h.eq(cursor.cursor, 12, "active = false -> pad ignored")
	cursor.active = true
	var dialog := AcceptDialog.new()
	tree.root.add_child(dialog)
	dialog.popup_centered(Vector2i(200, 100))
	await frames(tree, 2)
	await press(0, JOY_BUTTON_DPAD_UP, tree)
	h.eq(cursor.cursor, 12, "a visible dialog owns the pad")
	dialog.hide()
	dialog.queue_free()
	await frames(tree, 2)
	await press(0, JOY_BUTTON_DPAD_UP, tree)
	h.eq(cursor.cursor, 20, "closing the dialog gives the pad back")
	await press_key(KEY_RIGHT, tree)
	h.eq(cursor.cursor, 20, "keyboard arrows are ignored while keyboard = false (the 2D board has its own)")
	cursor.keyboard = true
	await press_key(KEY_RIGHT, tree)
	h.eq(cursor.cursor, 21, "keyboard = true: Right arrow moves")
	await press_key(KEY_UP, tree)
	await press_key(KEY_ENTER, tree)
	h.eq(interaction.selected, -1, "Enter on an empty square selects nothing")
	cursor.set_cursor(12)
	await press_key(KEY_ENTER, tree)
	h.eq(interaction.selected, 12, "Enter selects")
	await press_key(KEY_ESCAPE, tree)
	h.eq(interaction.selected, -1, "Esc cancels")
	cursor.queue_free()
	interaction.dispose()
	await frames(tree, 2)


static func _cursor_promotion(h, tree: SceneTree) -> void:
	h.begin("board cursor: promotion via the cursor's own picker (Queen / Rook / Bishop / Knight)")
	var bindings := ControlBindings.new()
	var assignment := Pads.fake_assignment(bindings, [0, 1])
	var pair := fresh_match(PROMO_FEN)
	var game = pair[0]
	var interaction: BoardInteraction = pair[1]
	var requested: Array = []
	interaction.move_requested.connect(func(from, to, promo): requested.append([from, to, promo]))
	var cursor := BoardPadCursor.create(game, interaction, assignment)
	cursor.own_promotion_picker = true
	tree.root.add_child(cursor)
	cursor.set_cursor(48)  # a7
	await press(0, JOY_BUTTON_A, tree)
	h.eq(interaction.selected, 48, "pawn on a7 selected")
	await press(0, JOY_BUTTON_DPAD_UP, tree)
	h.eq(cursor.cursor, 56, "cursor on a8")
	await press(0, JOY_BUTTON_A, tree)
	h.check(not cursor.promoting.is_empty(), "Cross on a promotion square opens the picker")
	h.eq(requested, [], "...and the host's dialog is NOT asked (no double UI)")
	h.eq(game.engine.board[56], "", "nothing was played yet")
	await press(0, JOY_BUTTON_B, tree)
	h.check(cursor.promoting.is_empty() and interaction.selected == -1, "Circle cancels the picker and the selection")
	h.eq(game.engine.board[48], "P", "the pawn is still on a7")
	cursor.set_cursor(48)
	await press(0, JOY_BUTTON_A, tree)
	cursor.set_cursor(56)
	await press(0, JOY_BUTTON_A, tree)
	h.eq(cursor.promoting.get("index"), 0, "the picker starts on Queen")
	await press(0, JOY_BUTTON_DPAD_RIGHT, tree)
	await press(0, JOY_BUTTON_DPAD_RIGHT, tree)
	h.eq(cursor.promoting.get("index"), 2, "D-pad right twice -> Bishop")
	await press(0, JOY_BUTTON_DPAD_LEFT, tree)
	h.eq(cursor.promoting.get("index"), 1, "D-pad left -> Rook")
	await press(0, JOY_BUTTON_LEFT_SHOULDER, tree)
	await press(0, JOY_BUTTON_LEFT_SHOULDER, tree)
	h.eq(cursor.promoting.get("index"), 3, "L1 wraps around to Knight")
	await press(0, JOY_BUTTON_RIGHT_SHOULDER, tree)
	h.eq(cursor.promoting.get("index"), 0, "R1 wraps to Queen")
	await press(0, JOY_BUTTON_DPAD_RIGHT, tree)
	await press(0, JOY_BUTTON_A, tree)
	h.eq(game.engine.board[56], "R", "Cross on Rook plays a7a8=R through the match's own admission")
	h.eq(game.engine.board[48], "", "the pawn left a7")
	h.eq(game.engine.turn, "b", "Black to move")

	h.begin("board cursor: without the picker the host dialog is asked (promotion_needed = true)")
	cursor.queue_free()
	interaction.dispose()
	pair = fresh_match(PROMO_FEN)
	game = pair[0]
	interaction = pair[1]
	requested.clear()
	interaction.move_requested.connect(func(from, to, promo): requested.append([from, to, promo]))
	cursor = BoardPadCursor.create(game, interaction, assignment)
	tree.root.add_child(cursor)
	cursor.set_cursor(48)
	await press(0, JOY_BUTTON_A, tree)
	cursor.set_cursor(56)
	await press(0, JOY_BUTTON_A, tree)
	h.eq(requested, [["a7", "a8", true]], "move_requested(a7, a8, true)")
	h.check(cursor.promoting.is_empty(), "no picker")
	cursor.queue_free()
	interaction.dispose()
	await frames(tree, 2)


# ---- application menus ---------------------------------------------------------------------------------------------
static func _application_focus(h, tree: SceneTree) -> void:
	h.begin("menus: pad navigation of the real application scene never loses focus (D-pad, Cross, Circle)")
	tree.root.size = Vector2i(1280, 800)
	Settings.loaded = true
	Settings.token = ""
	Settings.account.clear()
	Settings.launch.clear()
	Settings.preferred_3d = false
	var bindings := ControlBindings.new()
	var assignment := Pads.fake_assignment(bindings, [0, 1])
	var old_b := ControlBindings.shared()
	var old_a := InputAssignment.shared()
	ControlBindings.set_shared(bindings)
	InputAssignment.set_shared(assignment)
	ControllerGlyphs.fake_devices = {0: {"name": "PS4 Controller"}, 1: {"name": "PS4 Controller"}}
	var shell: Control = AppScene.instantiate()
	tree.root.add_child(shell)
	await frames(tree, 3)
	shell.navigate("play")  # the application now opens on the title screen; this suite exercises the Play page and the header navigation
	await frames(tree, 3)
	var ui: PadUi = shell.get_node_or_null("PadUi")
	if not h.check(ui != null, "the application installs a PadUi helper"):
		shell.queue_free()
		return
	h.check(InputMap.has_action("ui_accept") and _has_pad_button("ui_accept", JOY_BUTTON_A), "Cross is ui_accept")
	h.check(_has_pad_button("ui_cancel", JOY_BUTTON_B), "Circle is ui_cancel")
	h.check(tree.root.gui_get_focus_owner() == null, "before any pad input nothing is focused (mouse users see no focus ring)")
	await press(0, JOY_BUTTON_DPAD_DOWN, tree)
	h.check(focus_ok(tree), "the first D-pad press reveals a focused control")
	var first := tree.root.gui_get_focus_owner()
	h.check(shell.content.is_ancestor_of(first), "...inside the page content (Play), not the header")
	var seen: Dictionary = {}
	var lost := 0
	for i in 14:
		await press(0, JOY_BUTTON_DPAD_DOWN, tree)
		if not focus_ok(tree):
			lost += 1
		else:
			seen[tree.root.gui_get_focus_owner().get_path()] = true
	h.eq(lost, 0, "14 more D-pad presses: focus was never lost")
	h.check(seen.size() >= 3, "...and it really travelled (%d distinct controls before the end of the page)" % seen.size())
	for i in 6:
		await press(0, JOY_BUTTON_DPAD_UP, tree)
		if not focus_ok(tree):
			lost += 1
	h.eq(lost, 0, "...also moving up")
	# Stick navigation uses the same ui_* actions.
	Pads.axis(0, JOY_AXIS_LEFT_Y, 1.0)
	Input.flush_buffered_events()
	await frames(tree, 2)
	Pads.axis(0, JOY_AXIS_LEFT_Y, 0.0)
	Input.flush_buffered_events()
	await frames(tree, 2)
	h.check(focus_ok(tree), "the left stick navigates too")

	# Cross presses the focused button; the page rebuilds and focus is restored by the guard.
	var settings_button: Button = shell._menu_buttons["settings"]
	settings_button.grab_focus()
	await press(0, JOY_BUTTON_A, tree)
	await frames(tree, 3)
	h.eq(shell.page, "settings", "Cross on the Settings button opens Settings")
	h.check(focus_ok(tree), "after the page rebuilt (and the button got disabled) focus is restored on an enabled control")
	await press(1, JOY_BUTTON_B, tree)
	await frames(tree, 2)
	h.eq(shell.page, "play", "Circle on any pad goes back to Play")
	h.check(focus_ok(tree), "...with a valid focus")
	for page in ["account", "profile", "history", "leaderboard", "settings", "play"]:
		shell.navigate(page)
		await frames(tree, 3)
		h.check(focus_ok(tree), "navigate(%s): focus valid while a pad is in use" % page)
		await press(0, JOY_BUTTON_DPAD_DOWN, tree)
		h.check(focus_ok(tree), "...and after one more D-pad press")
	# An OptionButton's popup is a window of its own: D-pad + Cross choose an item and focus returns to the button.
	shell.navigate("play")
	await frames(tree, 3)
	var option: OptionButton = shell.content.find_children("*", "OptionButton", true, false)[0]
	var chosen_before: int = shell.selected_time
	option.grab_focus()
	await press(0, JOY_BUTTON_A, tree)
	await frames(tree, 2)
	h.check(option.get_popup().visible, "Cross opens the time-control list")
	await press(0, JOY_BUTTON_DPAD_DOWN, tree)
	await press(0, JOY_BUTTON_A, tree)
	await frames(tree, 3)
	h.check(not option.get_popup().visible and shell.selected_time != chosen_before, "D-pad + Cross choose another time control (%d -> %d)" % [chosen_before, shell.selected_time])
	h.check(focus_ok(tree), "focus is valid after the list closed")
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(40, 10)
	motion.position = Vector2(300, 300)
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await frames(tree, 2)
	h.check(not ui.nav_mode, "moving the mouse leaves pad mode (the guard stops re-focusing behind a mouse user)")
	shell.queue_free()
	await frames(tree, 2)
	ControlBindings.set_shared(old_b)
	InputAssignment.set_shared(old_a)
	ControllerGlyphs.fake_devices = {}
	Pads.release_all()


static func _has_pad_button(action: String, button: int) -> bool:
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton and int(e.button_index) == button:
			return true
	return false


# ---- controls screen ----------------------------------------------------------------------------------------------------
static func _controls_screen(h, tree: SceneTree) -> void:
	h.begin("controls screen: opens from Settings, pad focus stays inside it, rebinding with keys and pad buttons, persistence")
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://pads_test"))
	Settings.loaded = true
	Settings.token = ""
	var bindings := ControlBindings.new()
	var assignment := Pads.fake_assignment(bindings, [0, 1])
	var old_b := ControlBindings.shared()
	var old_a := InputAssignment.shared()
	ControlBindings.set_shared(bindings)
	InputAssignment.set_shared(assignment)
	ControllerGlyphs.fake_devices = {0: {"name": "PS4 Controller"}, 1: {"name": "PS4 Controller"}}
	var shell: Control = AppScene.instantiate()
	tree.root.add_child(shell)
	await frames(tree, 2)
	shell.navigate("settings")
	await frames(tree, 2)
	var opener: Button = null
	for node in shell.content.find_children("*", "Button", true, false):
		if (node as Button).text.begins_with("Controls"):
			opener = node
	if not h.check(opener != null, "Settings has a 'Controls & controllers' button"):
		shell.queue_free()
		return
	await press(0, JOY_BUTTON_DPAD_DOWN, tree)  # enter pad mode
	opener.grab_focus()
	await press(0, JOY_BUTTON_A, tree)
	await frames(tree, 3)
	var screen: ControlsScreen = shell.get_node_or_null("ControlsScreen")
	if not h.check(screen != null, "Cross on the button opened the controls screen"):
		shell.queue_free()
		return
	screen.path = TMP
	h.check(focus_ok(tree) and screen.is_ancestor_of(tree.root.gui_get_focus_owner()), "focus is inside the controls screen")
	var outside := 0
	for i in 40:
		await press(0, JOY_BUTTON_DPAD_DOWN, tree)
		var owner := tree.root.gui_get_focus_owner()
		if owner == null or not screen.is_ancestor_of(owner):
			outside += 1
	h.eq(outside, 0, "40 D-pad presses: focus never left the screen (nor was lost), the list scrolled to follow")
	h.eq(screen.row_text("pad/light"), "Square", "pad rows use the connected controller's words (PS4: Square)")
	h.eq(screen.row_text("pad/dodge"), "Cross", "Cross")
	h.eq(screen.row_text("pad/sprint"), "L2", "L2")
	h.eq(screen.row_text("kb1/light"), "F", "keyboard rows show key names")
	ControllerGlyphs.fake_devices = {0: {"name": "XInput Gamepad"}}
	Pads.set_pads(assignment, [0])
	screen._refresh()
	h.eq(screen.row_text("pad/light"), "X", "with an Xbox pad connected the same row reads X")
	h.eq(screen.row_text("pad/block"), "LB", "LB")
	Pads.set_pads(assignment, [])
	screen._refresh()
	h.eq(screen.row_text("pad/light"), "Square / X", "with no pad connected both vocabularies are shown")
	Pads.set_pads(assignment, [0, 1])
	ControllerGlyphs.fake_devices = {0: {"name": "PS4 Controller"}, 1: {"name": "PS4 Controller"}}
	screen._refresh()

	# Keyboard rebinding
	screen._rows["kb1/light"].pressed.emit()
	await frames(tree)
	h.check(not screen.capture.is_empty() and screen._rows["kb1/light"].text.begins_with("Press a key"), "the row asks for a key")
	await press_key(KEY_H, tree)
	h.eq(bindings.key_for("kb1", "light"), KEY_H, "H is bound to light for Player 1")
	h.check(screen.capture.is_empty() and screen._rows["kb1/light"].text == "H", "the row shows H")
	screen._rows["kb1/heavy"].pressed.emit()
	await press_key(KEY_H, tree)
	h.eq(bindings.key_for("kb1", "heavy"), KEY_H, "heavy took H")
	h.eq(bindings.key_for("kb1", "light"), KEY_G, "...and light got heavy's old key (swap)")
	h.check(screen.status.text.contains("swapped"), "the conflict is explained: '%s'" % screen.status.text)
	screen._rows["kb1/dodge"].pressed.emit()
	await press_key(KEY_J, tree)  # Player 2's light
	h.eq(bindings.key_for("kb1", "dodge"), KEY_SPACE, "a key used by the other player's set is refused")
	h.check(screen.status.text.contains("cannot be used") and screen.status.text.contains("other player"), "...with a warning: '%s'" % screen.status.text)
	screen._rows["kb1/dodge"].pressed.emit()
	await press_key(KEY_ESCAPE, tree)
	h.check(screen.capture.is_empty() and bindings.key_for("kb1", "dodge") == KEY_SPACE, "Esc cancels a capture without changing anything")
	h.check(is_instance_valid(screen), "...and does not close the screen")
	screen._rows["kb2/lock"].pressed.emit()
	await press_key(KEY_BACKSLASH, tree)
	h.eq(bindings.key_for("kb2", "lock"), KEY_BACKSLASH, "Player 2's lock-on rebound")

	# Pad rebinding
	screen._rows["pad/light"].pressed.emit()
	await frames(tree)
	h.check(screen._rows["pad/light"].text.begins_with("Press a button"), "the pad row asks for a button")
	await press(0, JOY_BUTTON_Y, tree)  # Triangle (heavy's button)
	h.eq(bindings.pad_input("light"), {"type": "button", "index": JOY_BUTTON_Y}, "Triangle bound to light")
	h.eq(bindings.pad_input("heavy"), {"type": "button", "index": JOY_BUTTON_X}, "heavy took Square (swap)")
	h.check(screen.status.text.contains("swapped"), "swap explained: '%s'" % screen.status.text)
	screen._rows["pad/ability"].pressed.emit()
	await press(1, JOY_BUTTON_START, tree)
	h.check(not screen.capture.is_empty() or screen.status.text.length() > 0, "Options is not captured")
	h.eq(bindings.pad_input("ability"), ControlBindings.DEFAULT_PAD["ability"], "Options never becomes a binding")
	var trigger := InputEventJoypadMotion.new()
	trigger.device = 0
	trigger.axis = JOY_AXIS_TRIGGER_LEFT
	trigger.axis_value = 1.0
	Input.parse_input_event(trigger)
	Input.flush_buffered_events()
	await frames(tree)
	h.eq(bindings.pad_input("ability"), {"type": "axis", "index": JOY_AXIS_TRIGGER_LEFT}, "a trigger can be captured (L2 -> ability)")
	h.eq(bindings.pad_input("sprint"), {"type": "button", "index": JOY_BUTTON_B}, "...and sprint received Circle in the swap")
	Pads.axis(0, JOY_AXIS_TRIGGER_LEFT, 0.0)
	screen._rows["pad/dodge"].pressed.emit()
	screen.capture["left"] = 0.01
	await tree.create_timer(0.2).timeout
	h.check(screen.capture.is_empty() and bindings.pad_input("dodge") == ControlBindings.DEFAULT_PAD["dodge"], "a pad capture times out instead of trapping a pad-only player")
	h.check(screen.status.text.contains("timed out"), "...and says so")

	# Tuning + persistence
	screen._sliders["deadzone"]["slider"].value = 0.3
	h.eq(float(bindings.pad_setting("deadzone")), 0.3, "the dead zone slider writes the setting")
	screen._sliders["invert_look_y"]["check"].button_pressed = true
	h.eq(bindings.pad_setting("invert_look_y"), true, "the invert switch writes the setting")
	screen._on_seat_selected(1, "kb2")
	h.eq(bindings.seat_pref(1), "kb2", "the seat selector writes the preference")
	screen._on_seat_selected(0, "kb2")
	h.eq(bindings.seat_pref(1), "auto", "choosing the same device for both players resets the other to Automatic")
	var reloaded := ControlBindings.new()
	h.check(reloaded.load_file(TMP), "the file was written")
	h.eq(reloaded.keys, bindings.keys, "keyboard bindings persisted")
	h.eq(reloaded.pad, bindings.pad, "pad bindings persisted")
	h.eq(reloaded.pad_settings, bindings.pad_settings, "pad settings persisted")
	h.eq(reloaded.seat_prefs, bindings.seat_prefs, "seat preferences persisted")
	# Reset
	screen._on_reset_all()
	h.check(not bindings.is_default(), "the first press only asks for confirmation")
	screen._on_reset_all()
	h.check(bindings.is_default(), "the second press resets everything")
	h.check(ControlBindings.new().load_file(TMP) and ControlBindings.new().is_default(), "and the reset is saved")
	# Circle leaves the screen
	await press(0, JOY_BUTTON_B, tree)
	await frames(tree, 3)
	h.check(not is_instance_valid(screen) or screen.is_queued_for_deletion(), "Circle closes the controls screen")
	await frames(tree, 2)
	h.check(focus_ok(tree), "back on Settings focus is valid again")
	shell.queue_free()
	await frames(tree, 2)
	ControlBindings.set_shared(old_b)
	InputAssignment.set_shared(old_a)
	ControllerGlyphs.fake_devices = {}
	Pads.release_all()
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))


# ---- the real board screen ---------------------------------------------------------------------------------------------------
static func _main_scene(h, tree: SceneTree) -> void:
	h.begin("main scene: two pads play a hot-seat game on the real board screen (cursor, turn ownership, promotion dialog, menu focus)")
	tree.root.size = Vector2i(1200, 800)
	Settings.loaded = true
	Settings.launch.clear()
	Settings.preferred_3d = false
	var bindings := ControlBindings.new()
	var assignment := Pads.fake_assignment(bindings, [0, 1])
	var old_b := ControlBindings.shared()
	var old_a := InputAssignment.shared()
	ControlBindings.set_shared(bindings)
	InputAssignment.set_shared(assignment)
	var app: Control = MainScene.instantiate()
	tree.root.add_child(app)
	await frames(tree, 3)
	var ui: PadUi = app.get_node_or_null("PadUi")
	if not h.check(ui != null, "main installs a PadUi helper"):
		app.queue_free()
		return
	await frames(tree, 2)
	var cursor: BoardPadCursor = ui.cursor
	if not h.check(cursor != null and ui.board_mode, "a board cursor exists and starts in board mode"):
		app.queue_free()
		return
	h.check(cursor.get_parent() == ui and cursor._overlay != null and cursor._overlay.get_parent() == app.board_2d.get_parent(), "its overlay sits over the board")
	h.check(not cursor.strict_turns, "Classic: either pad may play (strict_turns off)")
	# The overlay maps squares to screen rectangles through the real 2D board.
	var r: Rect2 = ui._square_rect(12)
	var expected: Vector2 = app.board_2d.square_center(12)
	h.check(r.size.x > 20 and r.get_center().distance_to(expected) < 1.0, "the 2D square rectangle is centred on the square (%s vs %s)" % [str(r.get_center()), str(expected)])
	await press(0, JOY_BUTTON_A, tree)
	h.eq(app.interaction.selected, 12, "Cross selects e2 on the real board")
	await press(0, JOY_BUTTON_DPAD_UP, tree)
	await press(0, JOY_BUTTON_DPAD_UP, tree)
	await press(0, JOY_BUTTON_A, tree)
	await frames(tree, 2)
	h.eq(app.game.engine.history.size(), 1, "Cross on e4 played e2e4 through the application's own handler")
	h.eq(app.game.engine.turn, "b", "Black to move")
	# Flip: up on screen reverses
	app.set_flipped(true)
	await frames(tree)
	cursor.set_cursor(52)
	await press(1, JOY_BUTTON_DPAD_UP, tree)
	h.eq(cursor.cursor, 44, "board flipped: Up moves down the ranks as it does on screen")
	app.set_flipped(false)
	# 3D view maps through the camera.
	app.set_view(true)
	await frames(tree, 3)
	h.check(cursor.keyboard, "3D view enables the cursor's keyboard handling")
	var r3: Rect2 = ui._square_rect(12)
	h.check(r3.size.x > 5 and r3.size.y > 5, "a 3D square projects to a screen rectangle (%s)" % str(r3))
	var c12: Vector2 = r3.get_center()
	var c13: Vector2 = ui._square_rect(13).get_center()
	h.check(c13.x > c12.x, "f2 is to the right of e2 on screen")
	app.set_view(false)
	await frames(tree)

	# Promotion through the host dialog, navigated with the pad.
	app.game.new_game(0, 0, PROMO_FEN)
	await frames(tree, 2)
	cursor.set_cursor(48)
	await press(0, JOY_BUTTON_A, tree)
	await press(0, JOY_BUTTON_DPAD_UP, tree)
	await press(0, JOY_BUTTON_A, tree)
	await frames(tree, 3)
	h.check(app.promotion_dialog.visible, "the promotion dialog opened")
	var owner: Control = app.promotion_dialog.gui_get_focus_owner()
	h.check(owner is Button and app.promotion_dialog.is_ancestor_of(owner) and (owner as Button).text == "Queen", "the dialog opens with focus already on Queen (the pad was in use: no extra press needed)")
	await press(0, JOY_BUTTON_DPAD_RIGHT, tree)
	owner = app.promotion_dialog.gui_get_focus_owner()
	h.check(owner is Button and (owner as Button).text == "Rook", "D-pad right moves Queen -> Rook (got %s)" % (owner as Button).text if owner is Button else "none")
	await press(0, JOY_BUTTON_A, tree)
	await frames(tree, 2)
	h.eq(app.game.engine.board[56], "R", "Cross on Rook promoted to a rook")
	h.check(not app.promotion_dialog.visible, "the dialog closed")
	# Circle cancels the dialog
	app.game.new_game(0, 0, PROMO_FEN)
	await frames(tree, 2)
	cursor.set_cursor(48)
	await press(0, JOY_BUTTON_A, tree)
	await press(0, JOY_BUTTON_DPAD_UP, tree)
	await press(0, JOY_BUTTON_A, tree)
	await frames(tree, 3)
	await press(0, JOY_BUTTON_DPAD_DOWN, tree)
	h.check(app.promotion_dialog.gui_get_focus_owner() != null, "focus stays valid inside the dialog after a D-pad press")
	await press(0, JOY_BUTTON_B, tree)
	await frames(tree, 3)
	h.check(not app.promotion_dialog.visible, "Circle closes the promotion dialog")
	h.eq(app.interaction.selected, -1, "...and clears the selection (the host's canceled handler)")
	h.eq(app.game.engine.board[48], "P", "the pawn did not move")

	# Options: board mode <-> menu focus
	await press(0, JOY_BUTTON_START, tree)
	h.check(not ui.board_mode, "Options leaves board mode")
	await press(0, JOY_BUTTON_DPAD_DOWN, tree)
	h.check(focus_ok(tree), "...and the D-pad now navigates the toolbar (focus visible)")
	var focused: Control = tree.root.gui_get_focus_owner()
	var moved := 0
	for i in 8:
		await press(0, JOY_BUTTON_DPAD_RIGHT, tree)
		if focus_ok(tree):
			moved += 1
	h.eq(moved, 8, "8 more presses: focus never lost in the toolbar")
	var before := cursor.cursor
	await press(0, JOY_BUTTON_DPAD_UP, tree)
	h.eq(cursor.cursor, before, "the board cursor does not move in menu mode")
	await press(0, JOY_BUTTON_B, tree)
	h.check(ui.board_mode and tree.root.gui_get_focus_owner() == null, "Circle in the menu returns to the board and releases focus")
	await press(0, JOY_BUTTON_DPAD_RIGHT, tree)
	h.eq(cursor.cursor, before + 1, "the board cursor moves again")

	# Battle Chess: strict turns, overlay scope
	app._switch_mode(1)
	await frames(tree, 3)
	cursor = ui.cursor
	h.check(cursor != null and cursor.strict_turns, "Battle Chess rebuilds the cursor for the new match with strict turns")
	cursor.set_cursor(12)
	await press(1, JOY_BUTTON_DPAD_UP, tree)
	h.eq(cursor.cursor, 12, "Battle: White to move, Black's pad is ignored")
	await press(0, JOY_BUTTON_DPAD_UP, tree)
	h.eq(cursor.cursor, 20, "...White's pad moves it")
	app._battle_phase("preview")
	await frames(tree, 2)
	h.check(app.battle_overlay.visible, "the capture overlay is shown")
	await press(0, JOY_BUTTON_DPAD_DOWN, tree)
	h.check(focus_ok(tree) and app.battle_overlay.is_ancestor_of(tree.root.gui_get_focus_owner()), "pad focus is inside the capture overlay (Start battle / Cancel), not on the toolbar behind it")
	for i in 6:
		await press(0, JOY_BUTTON_DPAD_UP if i % 2 == 0 else JOY_BUTTON_DPAD_DOWN, tree)
		if not (focus_ok(tree) and app.battle_overlay.is_ancestor_of(tree.root.gui_get_focus_owner())):
			h.check(false, "focus escaped the overlay")
	before = cursor.cursor
	await press(0, JOY_BUTTON_DPAD_RIGHT, tree)
	h.eq(cursor.cursor, before, "the board cursor is inactive during the preview")
	app._battle_phase("board")
	await frames(tree, 3)
	h.check(not app.battle_overlay.visible, "overlay closed")
	app.queue_free()
	await frames(tree, 3)
	ControlBindings.set_shared(old_b)
	InputAssignment.set_shared(old_a)
	Pads.release_all()
