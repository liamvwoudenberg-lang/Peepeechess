extends RefCounted
## Training UI and the duel AI setting: the duel-AI choice persists and drives the computer's duel seat (AIDifficulty), adaptive moves
## the saved level, the training fight view runs the real arena with the lesson's opponent and tracker, results are saved, and the
## Training page lists lessons (locked / unlocked) and the Training / Duel-AI entries exist in the menus.

const Settings := preload("res://ui/application_settings.gd")
const TMP := "user://training_ui_test.json"


static func run(h, tree: SceneTree) -> void:
	_duel_ai(h)
	await _arena_seat_level(h, tree)
	await _view(h, tree)
	await _pages(h, tree)


static func _fresh_store() -> ProgressStore:
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(TMP)
	var store := ProgressStore.new(TMP)
	DuelAi._store = store
	DuelAi._controller = null
	return store


static func _duel_ai(h) -> void:
	var store := _fresh_store()
	h.check(DuelAi.choice() == "auto" and DuelAi.seat_level() == "", "duel AI defaults to the chess level (no preset)")
	DuelAi.set_choice("hard")
	h.check(DuelAi.seat_level() == "hard", "a fixed choice is the seat level")
	h.check(ProgressStore.new(TMP).duel_ai == "hard", "the choice is saved")
	DuelAi.set_choice("bogus")
	h.check(DuelAi.choice() == "hard", "an unknown choice is ignored")
	DuelAi.record_duel(true, 0.0)
	h.check(store.fixed_level == "normal", "a fixed choice never records adaptive progress (level stays)")
	DuelAi.set_choice("adaptive")
	for i in 8:
		DuelAi.record_duel(true, 0.05)
	h.check(AIDifficulty.level_index(store.fixed_level) > 1, "adaptive rises after many clean wins (%s)" % store.fixed_level)
	h.check(DuelAi.seat_level() == store.fixed_level, "adaptive seat level is the saved level")
	var high := store.fixed_level
	for i in 12:
		DuelAi.record_duel(false, 0.9)
	h.check(AIDifficulty.level_index(store.fixed_level) < AIDifficulty.level_index(high), "adaptive falls after many losses (%s)" % store.fixed_level)
	h.check(ProgressStore.new(TMP).fixed_level == store.fixed_level, "the adaptive level is saved")
	DirAccess.remove_absolute(TMP)
	DuelAi._store = null
	DuelAi._controller = null


static func _arena_seat_level(h, tree: SceneTree) -> void:
	var arena: Node = (load("res://combat/arena.tscn") as PackedScene).instantiate()
	tree.root.add_child(arena)
	arena.call("configure_seats", {"player-white": {"type": "ai", "level": "expert"}, "player-black": {"type": "driven"}})
	var reply: Dictionary = arena.call("start_battle", FighterRoster.build_request("q", "p", "w", "seat-level", 4, 0))
	h.check(reply.get("ok", false), "arena starts")
	h.check(arena._ais.size() == 1, "a level seat builds one AI and a driven seat none (%d)" % arena._ais.size())
	arena.queue_free()
	await tree.process_frame


static func _view(h, tree: SceneTree) -> void:
	var store := _fresh_store()
	var catalog := LessonCatalog.load_all()
	var lesson := catalog.get_lesson("b01_movement")
	var view := TrainingView.new()
	view.setup(lesson, "easy", store, "b02_camera")
	tree.root.add_child(view)
	for i in 4:
		await tree.process_frame
	h.check(view.arena != null and view.tracker != null and view.opponent != null, "the training view builds arena, tracker and opponent")
	h.check(view._objective_box.get_child_count() == lesson["objectives"].size(), "objectives are listed")
	for i in 30:
		await tree.physics_frame
	h.check(view.arena.sim.server_tick > 0, "the fight advances on its own")
	view._open_menu()
	h.check(view._menu != null and view._paused, "the pause menu opens and pauses")
	view._close_menu()
	h.check(view._menu == null and not view._paused, "the pause menu closes")
	view._on_completed({"seconds": 9.0, "hits_taken": 0, "best_combo": 0, "completed": true})
	h.check(view._card != null and store.is_completed("b01_movement"), "completion shows the result card and saves progress")
	h.check(store.best_rating("b01_movement") != "", "a rating is saved")
	var arena_before: Node = view.arena
	view._restart()
	for i in 4:
		await tree.process_frame
	h.check(view.arena != null and view.arena != arena_before and view._card == null, "Try again starts a fresh fight")
	view.queue_free()
	# free practice: nothing is saved
	var free := TrainingView.new()
	free.setup(FreePractice.make({"player_role": "n", "opponent_role": "q", "behaviour": "passive_block", "difficulty": "hard"}), "hard", store, "")
	tree.root.add_child(free)
	for i in 4:
		await tree.process_frame
	h.check(free.arena != null, "free practice starts")
	free._on_battle_finished({})
	h.check(not store.lessons.has("free_practice"), "free practice is never saved")
	free.queue_free()
	await tree.process_frame
	DirAccess.remove_absolute(TMP)
	DuelAi._store = null


static func _pages(h, tree: SceneTree) -> void:
	_fresh_store()
	tree.root.size = Vector2i(1280, 800)
	Settings.loaded = true
	Settings.token = ""
	Settings.account.clear()
	Settings.launch.clear()
	Settings.intro_seen = true
	var shell: Control = (load("res://ui/application.tscn") as PackedScene).instantiate()
	tree.root.add_child(shell)
	for i in 4:
		await tree.process_frame
	shell.navigate("training")
	for i in 3:
		await tree.process_frame
	var starts := 0
	var enabled := 0
	var locked_text := 0
	for node in shell.content.find_children("*", "Button", true, false):
		if node.text in ["Start", "Replay"]:
			starts += 1
			if not node.disabled:
				enabled += 1
	for node in shell.content.find_children("*", "Label", true, false):
		if node.text.begins_with("Locked:"):
			locked_text += 1
	h.check(starts >= 20, "the Training page lists the lessons (%d buttons)" % starts)
	h.check(enabled >= 1 and enabled < starts, "only unlocked lessons can start (%d of %d)" % [enabled, starts])
	h.check(locked_text > 0, "locked lessons say so")
	h.check(shell.content.find_child("Duel_adaptive", true, false) != null, "the AI level choice is on the Training page")
	h.check(shell._menu_buttons.has("training"), "Training is in the top navigation")
	shell.queue_free()
	await tree.process_frame
	# title screen entry
	var title := preload("res://ui/theme/title_screen.gd")
	h.check(FileAccess.get_file_as_string("res://ui/theme/title_screen.gd").contains('"training", "Training"'), "Training is on the title menu")
	# Play page: duel opponent row
	var box := VBoxContainer.new()
	tree.root.add_child(box)
	OpponentUI.build_computer_options(box, OpponentUI.default_state(), func(): pass)
	h.check(box.find_child("Duel_expert", true, false) != null and box.find_child("Duel_auto", true, false) != null, "the computer options offer the duel AI choices")
	box.queue_free()
	DirAccess.remove_absolute(TMP)
	DuelAi._store = null
	var _unused = title
