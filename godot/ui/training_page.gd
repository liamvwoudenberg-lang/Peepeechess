class_name TrainingPage
extends RefCounted
## The Training page of the application: lesson list (four categories, medals and saved progress, locked until the lessons they need are
## done), Free Practice (any role against any role, opponent behaviour and AI level, nothing scored) and the AI difficulty setting
## (Easy / Normal / Hard / Expert / Adaptive) used by Battle Chess duels against the computer. All logic is in godot/training/.

const Kit = preload("res://ui/theme/ui_kit.gd")
const Settings = preload("res://ui/application_settings.gd")
const SCENE := "res://training/training_scene.tscn"
const CATEGORIES := [["beginner", "Beginner"], ["intermediate", "Intermediate"], ["advanced", "Advanced"], ["expert", "Expert"]]
const MEDAL := {"": "", "bronze": "Bronze", "silver": "Silver", "gold": "Gold"}
const ROLE_NAMES := [["p", "Pawn"], ["n", "Knight"], ["b", "Bishop"], ["r", "Rook"], ["q", "Queen"], ["k", "King"]]
const BEHAVIOURS := [["idle", "Stands still"], ["passive_block", "Blocks"], ["attack_only", "Attacks"], ["normal", "Fights normally"]]

static var free_state := {"player_role": "q", "opponent_role": "p", "behaviour": "idle", "difficulty": "normal"}


static func build(app: Control) -> void:
	var progress: ProgressStore = DuelAi.store()
	var catalog := LessonCatalog.load_all()
	Kit.heading(app.content, "Train for the duel.", "Short lessons on the real combat engine, free practice against any piece, and the AI level of your Battle Chess opponents.")
	_summary_card(app, catalog, progress)
	_free_practice_card(app)
	_ai_card(app)
	for entry in CATEGORIES:
		var lessons: Array = catalog.in_category(entry[0])
		if lessons.is_empty():
			continue
		var section := Kit.card(app.content)
		var done := 0
		for lesson in lessons:
			if progress.is_completed(String(lesson["id"])):
				done += 1
		Kit.label(section, "%s  ·  %d / %d done" % [String(entry[1]).to_upper(), done, lessons.size()], "Accent")
		for lesson in lessons:
			_lesson_row(app, section, catalog, progress, lesson)


static func _summary_card(app: Control, catalog: LessonCatalog, progress: ProgressStore) -> void:
	var playable := catalog.playable()
	var card := Kit.card(app.content)
	Kit.label(card, "Progress: %d of %d lessons completed." % [progress.completed_count(), playable.size()], "H3")
	var next := ""
	for lesson in playable:
		if not progress.is_completed(String(lesson["id"])) and catalog.is_unlocked(String(lesson["id"]), progress):
			next = String(lesson["id"])
			break
	if next != "":
		var lesson: Dictionary = catalog.get_lesson(next)
		var row := Kit.flow(card)
		Kit.button(row, "Continue: %s" % String(lesson["title"]), func(): launch_lesson(app, next), "PrimaryButton", "sword")


static func _lesson_row(app: Control, parent: Node, catalog: LessonCatalog, progress: ProgressStore, lesson: Dictionary) -> void:
	var id := String(lesson["id"])
	var available := catalog.is_available(id)
	var unlocked := available and catalog.is_unlocked(id, progress)
	var row := Kit.flow(parent)
	var info := VBoxContainer.new()
	info.custom_minimum_size.x = 360
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var medal := String(MEDAL.get(progress.best_rating(id), ""))
	var title := "%s%s" % [String(lesson["title"]), ("  ·  " + medal + " medal") if medal != "" else ("  ·  completed" if progress.is_completed(id) else "")]
	Kit.label(info, title, "H3")
	if not available:
		Kit.label(info, "Unavailable: %s" % String(lesson.get("unavailable_reason", "not supported by this build")), "Muted")
	elif not unlocked:
		Kit.label(info, "Locked: finish the earlier %s lessons first." % String(lesson["category"]), "Muted")
	else:
		Kit.label(info, String(lesson.get("summary", "")), "Muted")
	var button := Kit.button(row, "Replay" if progress.is_completed(id) else "Start", func(): launch_lesson(app, id), "" if progress.is_completed(id) else "PrimaryButton")
	button.disabled = not unlocked


static func _free_practice_card(app: Control) -> void:
	var card := Kit.card(app.content)
	Kit.label(card, "FREE PRACTICE", "Accent")
	Kit.label(card, "Pick both pieces and how the opponent behaves. Nothing is scored; the fight restarts when it ends.", "Muted")
	var row := Kit.flow(card)
	_picker(row, "You play", ROLE_NAMES, "player_role")
	_picker(row, "Opponent", ROLE_NAMES, "opponent_role")
	_picker(row, "Behaviour", BEHAVIOURS, "behaviour")
	var levels: Array = []
	for level in AIDifficulty.LEVELS:
		levels.append([level, AIDifficulty.label(level)])
	_picker(row, "AI level", levels, "difficulty")
	Kit.button(card, "Start free practice", func(): launch_free(app), "PrimaryButton", "sword")


static func _picker(parent: Node, caption: String, options: Array, key: String) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	parent.add_child(box)
	Kit.label(box, caption, "Muted")
	var picker := OptionButton.new()
	picker.custom_minimum_size = Vector2(170, Kit.target_height())
	for i in options.size():
		picker.add_item(String(options[i][1]))
		if options[i][0] == free_state[key]:
			picker.select(i)
	picker.item_selected.connect(func(index: int): free_state[key] = options[index][0])
	box.add_child(picker)


static func _ai_card(app: Control) -> void:
	var card := Kit.card(app.content)
	Kit.label(card, "BATTLE CHESS AI", "Accent")
	Kit.label(card, "How the computer fights your Battle Chess duels. Adaptive moves one level at a time from how you do.", "Muted")
	var row := Kit.flow(card)
	for choice in DuelAi.CHOICES:
		var picked: String = choice
		var button := Kit.button(row, String(DuelAi.LABELS[choice]), func(): DuelAi.set_choice(picked); app.navigate("training"), "PrimaryButton" if DuelAi.choice() == choice else "")
		button.name = "Duel_" + choice
	Kit.label(card, DuelAi.describe(DuelAi.choice()), "Muted")


## Starts a lesson (full-screen training scene); the scene returns to this page.
static func launch_lesson(app: Control, lesson_id: String) -> void:
	Settings.launch = {"training": {"lesson": lesson_id}}
	app.get_tree().change_scene_to_file(SCENE)


static func launch_free(app: Control) -> void:
	Settings.launch = {"training": {"free": free_state.duplicate()}}
	app.get_tree().change_scene_to_file(SCENE)
