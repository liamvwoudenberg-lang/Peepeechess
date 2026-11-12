extends SceneTree
## Opponent selection (Play page + New game dialog), the game screen with a computer opponent (turns, input guard,
## undo of two plies, draw offer, resignation, Battle seat) and the board settings page (apply + persist).
## Run with `-- --screenshots` to also save PNGs (needs a rendering driver).
const Scene = preload("res://ui/application.tscn")
const Settings = preload("res://ui/application_settings.gd")
const Local = preload("res://app/main.tscn")
const Rules = preload("res://chess/chess_engine.gd")
var checks = 0
var failures: Array = []
var shell: Control
func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("FAIL: ", label)
func _init() -> void:
	call_deferred("run")
func shot(name: String) -> void:
	if "--screenshots" not in OS.get_cmdline_user_args():
		return
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://" + name + ".png")
	print("Screenshot: ", ProjectSettings.globalize_path("user://" + name + ".png"))
func named(parent: Node, node_name: String) -> Node:
	return parent.find_child(node_name, true, false)
func wait_until(test: Callable, seconds: float = 8.0) -> bool:
	var deadline = Time.get_ticks_msec() + int(seconds * 1000)
	while not test.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	return test.call()
func launch_game(launch: Dictionary) -> Control:
	Settings.launch = launch
	var game_screen = Local.instantiate()
	root.add_child(game_screen)
	await process_frame
	await process_frame
	return game_screen

func run() -> void:
	root.size = Vector2i(1280, 800)
	Settings.loaded = true
	Settings.preferred_3d = false
	Settings.token = ""
	Settings.account.clear()
	Settings.launch.clear()
	Settings.animations = true
	BoardTheme.reset()
	shell = Scene.instantiate()
	root.add_child(shell)
	await process_frame
	await process_frame
	shell.navigate("play")  # the application opens on the title screen (ui-polish); the opponent picker lives on Play
	await process_frame
	# ---- Play page: Local / Computer, level, colour ----
	expect(shell.opponent.kind == "local" and named(shell.content, "ComputerOptions") == null, "Play page starts with a local two-player match and no computer options")
	var computer_button: Button = null
	for b in shell.content.find_children("*", "Button", true, false):
		if b.text.begins_with("Computer"):
			computer_button = b
	expect(computer_button != null, "Play page offers a Computer opponent")
	computer_button.pressed.emit()
	await process_frame
	expect(shell.opponent.kind == "computer" and named(shell.content, "ComputerOptions") != null, "choosing Computer shows level and colour pickers")
	await shot("ai-play-page")
	for level in range(1, 7):
		expect(named(shell.content, "Level_%d" % level) != null, "level %d button exists" % level)
	named(shell.content, "Level_5").pressed.emit()
	await process_frame
	named(shell.content, "Color_b").pressed.emit()
	await process_frame
	expect(shell.opponent.level == 5 and shell.opponent.color == "b", "level 5 / Black selected")
	expect(named(shell.content, "Level_5").button_pressed and named(shell.content, "Color_b").button_pressed and not named(shell.content, "Color_w").button_pressed, "selected options are shown pressed")
	expect(shell.match_options() == {"mode": "classic", "ranked": false, "initialMs": 600000, "incrementMs": 0}, "match_options() is unchanged by the opponent choice")
	shell.selected_mode = "classic"
	# start_local() hands the choice to the game screen through the launch dictionary and changes scene
	shell.start_local()
	expect(Settings.launch.get("opponent", {}).get("kind", "") == "computer" and Settings.launch.opponent.level == 5 and Settings.launch.opponent.color == "b", "launch carries the opponent choice")
	for i in 3:
		await process_frame
	var screen: Control = current_scene
	expect(screen != null and screen.get("opponent") != null, "the game screen opened")
	if screen == null:
		quit(1)
		return
	var computer: ComputerOpponent = screen.opponent.computer
	expect(computer.active and computer.level == 5 and computer.human_color == "b" and computer.ai_color == "w", "Play page choice starts a level 5 game with the human as Black")
	expect(screen.interaction.allowed_side == "b" and screen._flipped, "human colour owns the pieces and the board is flipped for Black")
	expect(Settings.launch.is_empty(), "launch consumed")
	await shot("ai-game-screen")
	# the computer (White) opens on its own, off the main thread
	expect(await wait_until(func(): return screen.game.engine.history.size() == 1), "the computer plays the first move")
	expect(screen.game.engine.turn == "b" and not computer.is_thinking(), "then it is the human's turn")
	var legal_first = screen.game.engine.history[0].from + screen.game.engine.history[0].to
	expect(legal_first.length() == 4, "its move is recorded in the history (%s)" % legal_first)
	# input guard: only the human colour can be picked up
	screen.interaction.select(Rules.index("e1") if screen.game.engine.turn == "w" else Rules.index("e2"))
	expect(screen.interaction.selected == -1, "the computer's pieces cannot be selected")
	screen.queue_free()
	await process_frame
	expect(not is_instance_valid(computer), "leaving the screen frees the computer opponent (its search thread is joined in _exit_tree)")
	# ---- New game dialog on the game screen ----
	screen = await launch_game({"mode": "classic", "initialMs": 600000, "incrementMs": 0})
	computer = screen.opponent.computer
	expect(not computer.active and screen.interaction.allowed_side == "", "a normal launch is a local two-player game")
	screen._show_new()
	await process_frame
	expect(named(screen.new_dialog, "Opponent_Local") != null and named(screen.new_dialog, "Opponent_Computer") != null, "New game dialog offers Local and Computer")
	named(screen.new_dialog, "Opponent_Computer").pressed.emit()
	await process_frame
	named(screen.new_dialog, "Level_2").pressed.emit()
	await process_frame
	named(screen.new_dialog, "Color_w").pressed.emit()
	await process_frame
	await shot("ai-new-game-dialog")
	screen.new_dialog.confirmed.emit()
	screen.new_dialog.hide()  # the real OK button hides the dialog
	await process_frame
	expect(computer.active and computer.level == 2 and computer.human_color == "w" and screen.interaction.allowed_side == "w", "New game dialog starts a level 2 game as White")
	expect(not screen._flipped, "White human keeps the normal board orientation")
	# human move through the real board interaction, computer answers
	screen.interaction.click(Rules.index("e2"))
	screen.interaction.click(Rules.index("e4"))
	expect(screen.game.engine.history.size() == 1 and screen.game.engine.history[0].san == "e4", "human move goes through the normal path")
	screen.interaction.select(Rules.index("e7"))
	expect(screen.interaction.selected == -1, "while the computer thinks its pieces cannot be selected")
	expect(await wait_until(func(): return screen.game.engine.history.size() == 2), "the computer replies")
	# ---- undo takes back two plies ----
	expect(screen.game.engine.turn == "w" and not screen.undo_button.disabled, "undo is available on the human's turn")
	screen.undo_button.pressed.emit()
	expect(screen.game.engine.history.size() == 0 and screen.game.engine.turn == "w", "undo takes back two plies (the reply and the human move)")
	for i in 20:
		await process_frame
	expect(screen.game.engine.history.size() == 0, "the computer does not move after the undo")
	# undo while the computer is still thinking takes back the human move only
	screen.interaction.click(Rules.index("d2"))
	screen.interaction.click(Rules.index("d4"))
	expect(screen.game.engine.history.size() == 1 and computer.is_thinking(), "computer thinks after d4")
	screen.undo_button.pressed.emit()
	expect(screen.game.engine.history.size() == 0 and screen.game.engine.turn == "w" and not computer.is_thinking(), "undo during thinking cancels the search and restores the human turn")
	await create_timer(1.2).timeout
	expect(screen.game.engine.history.size() == 0, "a cancelled search never plays a stale move")
	# ---- draw offer / resignation ----
	screen.interaction.click(Rules.index("e2"))
	screen.interaction.click(Rules.index("e4"))
	expect(await wait_until(func(): return screen.game.engine.history.size() == 2), "reply before the draw offer")
	computer.last_score = 150
	expect(screen.opponent.handle_draw_offer() and screen.game.engine.result == "", "the computer declines a draw when it is better")
	computer.last_score = -400
	expect(screen.opponent.handle_draw_offer() and screen.game.engine.result == "1/2-1/2" and screen.game.engine.reason == "Draw by agreement", "the computer accepts a draw when it is clearly worse")
	screen.game.new_game(600000, 0)
	computer.begin({"level": 1, "color": "w", "seed": 4})
	screen.interaction.click(Rules.index("g1"))
	screen.interaction.click(Rules.index("f3"))
	screen.opponent.resign()
	expect(screen.game.engine.result == "0-1" and screen.game.engine.reason == "Resignation", "the human resigns even while the computer is thinking")
	expect(not computer.is_thinking(), "resigning cancels the search")
	# ---- local game after a computer game ----
	await process_frame  # the result dialog of the resigned game opens on the next idle frame; close it like a player would
	await process_frame
	for window in screen.find_children("*", "Window", true, false):
		if window.visible:
			window.hide()
	screen._show_new()
	await process_frame
	named(screen.new_dialog, "Opponent_Local").pressed.emit()
	await process_frame
	screen.new_dialog.confirmed.emit()
	screen.new_dialog.hide()  # the real OK button hides the dialog
	await process_frame
	expect(not computer.active and screen.interaction.allowed_side == "", "choosing Local ends the computer game")
	# ---- Battle Chess hands the computer colour to the combat adapter ----
	screen.queue_free()
	await process_frame
	screen = await launch_game({"mode": "battle", "initialMs": 0, "incrementMs": 0, "opponent": {"kind": "computer", "level": 4, "color": "w"}})
	computer = screen.opponent.computer
	expect(screen.game is BattleChessMatch and computer.active and computer.level == 4, "Battle launch with a computer opponent")
	expect(screen.battle_adapter.computer_seat.get("color", "") == "b" and screen.battle_adapter.computer_seat.seat.type == "ai", "Battle: the computer colour is a CombatAI seat")
	expect(not screen.undo_button.disabled == false or screen.game.engine.history.is_empty(), "Battle has no undo (rules)")
	screen.queue_free()
	await process_frame
	# ---- board settings ----
	Settings.loaded = true
	shell.navigate("settings")
	await process_frame
	await process_frame
	expect(named(shell.content, "BoardSettings") != null and named(shell.content, "BoardPreview2D") != null and named(shell.content, "BoardPreview3D") != null, "Settings page has the Board & pieces card with 2D and 3D previews")
	await shot("ai-board-settings-slate")
	for pair in [["Theme_marble", "theme", "marble"], ["Highlight_tint", "highlight", "tint"], ["Pieces_carved", "pieces", "carved"], ["Speed_fast", "animation", "fast"], ["Shadows_low", "shadows", "low"]]:
		named(shell.content, pair[0]).pressed.emit()
		expect(BoardTheme.current()[pair[1]] == pair[2], "board setting %s = %s" % [pair[1], pair[2]])
	named(shell.content, "Coordinates").button_pressed = false
	named(shell.content, "Coordinates").toggled.emit(false)
	expect(not BoardTheme.coordinates, "coordinates switched off")
	await process_frame
	await shot("ai-board-settings-marble")
	named(shell.content, "Speed_off").pressed.emit()
	expect(BoardTheme.anim_scale() == 0.0 and not Settings.animations, "animation speed Off also turns the pre-existing animation switch off")
	named(shell.content, "Speed_fast").pressed.emit()
	expect(BoardTheme.anim_scale() == 0.5 and Settings.animations, "Fast is half the normal duration")
	# persistence: written by save_preferences(), restored by load_preferences()
	var config = ConfigFile.new()
	expect(config.load("user://preferences.cfg") == OK and config.get_value("board", "theme", "") == "marble" and config.get_value("board", "pieces", "") == "carved" and config.get_value("board", "coordinates", true) == false, "board settings are written to preferences")
	var saved = BoardTheme.current()
	BoardTheme.reset()
	expect(BoardTheme.theme_id == "slate", "reset restores defaults")
	Settings.loaded = false
	Settings.load_preferences()
	expect(BoardTheme.current() == saved, "board settings are restored from preferences")
	BoardTheme.apply({"theme": "nonsense", "highlight": "x", "pieces": "none", "animation": "warp", "shadows": "ultra"})
	expect(BoardTheme.current() == saved, "invalid values are ignored")
	# apply to a live 3D board: tiles, labels, piece set, highlights, shadows
	Settings.launch = {"mode": "classic", "initialMs": 0, "incrementMs": 0, "view3d": true}
	screen = Local.instantiate()
	root.add_child(screen)
	await process_frame
	await process_frame
	var board = screen.board_3d
	var dark_tile = null
	for child in board.scene.get_children():
		if child is MeshInstance3D:
			for sub in child.get_children():
				if sub is StaticBody3D and sub.get_meta("square", -1) == 0:
					dark_tile = child
	expect(dark_tile != null and dark_tile.material_override.albedo_color.is_equal_approx(Color(BoardTheme.THEMES.marble.dark_3d)), "3D tiles use the saved theme colours")
	var labels_visible = false
	for child in board.scene.get_children():
		if child is Label3D and child.visible:
			labels_visible = true
	expect(not labels_visible, "coordinates off hides the 3D labels")
	var carved = 0
	for piece in board.pieces.values():
		carved += piece.find_children("Piece_*", "Node3D", true, false).size()
	expect(carved >= 32, "carved set builds the GLB pieces when selected (%d nodes)" % carved)
	var key_shadow = true
	var light_parent: Node = board.world if board.get("world") != null else board.scene  # pit world keeps its lights on the world node
	for child in light_parent.get_children():
		if child is DirectionalLight3D and child.light_energy >= 0.3:
			key_shadow = child.shadow_enabled
	expect(not key_shadow, "shadow quality Low turns the key-light shadow off")
	screen.interaction.select(Rules.index("g1"))
	var box_marks = 0
	for mark in board.marks.get_children():
		if mark is MeshInstance3D and mark.mesh is BoxMesh:
			box_marks += 1
	expect(box_marks == 2, "tile-tint highlight draws one tinted tile per legal destination (%d)" % box_marks)
	BoardTheme.apply({"theme": "slate", "pieces": "procedural", "highlight": "rings", "coordinates": true, "shadows": "high"})
	await process_frame
	carved = 0
	for piece in board.pieces.values():
		carved += piece.find_children("Piece_*", "Node3D", true, false).size()
	expect(carved == 0 and board.pieces.size() == 32, "switching back rebuilds the procedural set live")
	screen.interaction.select(Rules.index("g1"))
	var ring_marks = 0
	for mark in board.marks.get_children():
		if mark is MeshInstance3D and mark.mesh is TorusMesh:
			ring_marks += 1
	expect(ring_marks == 2, "ring highlight draws a ring per destination (%d)" % ring_marks)
	expect(dark_tile.material_override == null or not dark_tile.material_override.albedo_color.is_equal_approx(Color(BoardTheme.THEMES.marble.dark_3d)), "default theme restores the board's own materials")
	screen.queue_free()
	await process_frame
	shell.queue_free()
	await process_frame
	BoardTheme.reset()
	Settings.animations = true
	Settings.preferred_3d = false
	Settings.save_preferences()
	print("AI UI: ", checks, " checks; failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
