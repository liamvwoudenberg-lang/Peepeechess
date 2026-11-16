class_name TrainingView
extends Control
## One training fight on screen: the real CombatArena (same simulation, camera, controls and effects as a Battle Chess duel) with the
## lesson's opponent driven from outside (TrainingOpponent), the ObjectiveTracker watching the real combat events, and a dark-plaque HUD:
## objectives with progress, the combo counter, feedback toasts, hints, and a result card (Retry / Next lesson / Back).
## Free Practice (lesson.free_practice) has no objectives: nothing is rated or saved and the fight restarts when it ends.
## Esc / Circle opens the pause menu (Resume, Restart, Leave).

signal exit_requested
signal lesson_requested(lesson_id: String)

const PLAYER_ID := "player-white"
const OPPONENT_ID := "player-black"
const TEXT := Color("f6e3b0")
const WHITE := Color("ffffff")
const MUTED := Color("c9d3da")
const GOOD := Color("9de0a4")
const BAD := Color("f0a090")

var lesson: Dictionary = {}
var level: String = "normal"
var progress: ProgressStore
var next_lesson_id: String = ""
var seed_value: int = 1

var arena: Node
var tracker: ObjectiveTracker
var opponent: TrainingOpponent
var _session: TrainingSession
var _layer: CanvasLayer
var _objective_box: VBoxContainer
var _title: Label
var _hint: Label
var _combo: Label
var _toast: Label
var _toast_time := 0.0
var _card: PanelContainer
var _menu: PanelContainer
var _pad: Node
var _ended := false
var _paused := false
var _tick_counter := 0


func setup(p_lesson: Dictionary, p_level: String, p_progress: ProgressStore, p_next: String = "") -> void:
	lesson = p_lesson
	level = p_level
	progress = p_progress
	next_lesson_id = p_next


func _ready() -> void:
	process_priority = -10   # before the arena: the opponent's packet is in the simulation when the arena steps it
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer = CanvasLayer.new()
	_layer.layer = 30
	add_child(_layer)
	_build_hud()
	_start_fight()


func _plaque(parent: Node, alpha: float = 0.82) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.05, 0.09, alpha)
	style.border_color = Color("c9a45c")
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel


func _label(parent: Node, text: String, size_px: int = 18, color: Color = WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


func _build_hud() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	_layer.add_child(margin)
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(root)
	# objectives (top left)
	var plaque := _plaque(root)
	plaque.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	plaque.custom_minimum_size = Vector2(330, 0)
	plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	plaque.add_child(column)
	_title = _label(column, String(lesson.get("title", "Training")), 22, TEXT)
	if bool(lesson.get("free_practice", false)):
		_label(column, "%s vs %s · %s" % [FighterRoster.display_name(String(lesson["player_role"])), FighterRoster.display_name(String(lesson["opponent_role"])), FreePractice.BEHAVIOUR_LABELS.get(String(lesson["behaviour"]), "")], 15, MUTED)
		_label(column, "No score: practise as long as you like. Esc opens the menu.", 14, MUTED)
	else:
		_label(column, String(lesson.get("summary", "")), 15, MUTED)
	_objective_box = VBoxContainer.new()
	_objective_box.add_theme_constant_override("separation", 3)
	column.add_child(_objective_box)
	# combo counter (top centre)
	_combo = _label(root, "", 34, TEXT)
	_combo.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_combo.offset_top = 80
	_combo.offset_left = -160
	_combo.offset_right = 160
	_combo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# feedback toast (upper middle)
	_toast = _label(root, "", 26, GOOD)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_top = 130
	_toast.offset_left = -260
	_toast.offset_right = 260
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.modulate.a = 0.0
	# hint (bottom centre)
	var hints: Array = lesson.get("hints", [])
	_hint = _label(root, String(hints[0]) if not hints.is_empty() else "", 18, WHITE)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.offset_top = -90
	_hint.offset_bottom = -30
	_hint.offset_left = -360
	_hint.offset_right = 360
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.visible = _hint.text != ""
	var leave := Button.new()
	leave.text = "Menu (Esc)"
	leave.focus_mode = Control.FOCUS_NONE
	leave.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	leave.offset_left = -150
	leave.offset_bottom = 44
	leave.pressed.connect(_open_menu)
	root.add_child(leave)


func _refresh_objectives() -> void:
	for child in _objective_box.get_children():
		_objective_box.remove_child(child)
		child.queue_free()
	if tracker == null:
		return
	for objective in tracker.objectives:
		var optional := bool(objective["def"].get("optional", false))
		var done: bool = objective["done"]
		var target: float = objective["target"]
		var text := "%s %s" % ["✓" if done else "•", String(objective["def"].get("text", objective["def"].get("id", "")))]
		if target > 1.0 and not done:
			text += "  %d/%d" % [int(minf(objective["value"], target)), int(target)]
		if optional:
			text += " (bonus)"
		_label(_objective_box, text, 17, GOOD if done else WHITE)


func _start_fight() -> void:
	_ended = false
	_clear_card()
	if is_instance_valid(arena):
		arena.queue_free()
		await get_tree().process_frame
	_session = TrainingSession.new(lesson, {"level": level, "seed": seed_value})
	var request := _session.lesson_request()
	var packed := load("res://combat/arena.tscn") as PackedScene
	arena = packed.instantiate()
	add_child(arena)
	move_child(arena, 0)
	arena.call("configure_seats", {
		PLAYER_ID: {"type": "human", "scheme": InputAssignment.shared().scheme_for_color("w")},
		OPPONENT_ID: {"type": "driven"},
	})
	var reply: Dictionary = arena.call("start_battle", request, {"allow_experimental_roles": true})
	if not reply.get("ok", false):
		_show_card("Could not start", String(reply.get("error", "The fight could not start.")), false)
		return
	_session.apply_handicaps(arena.sim)
	_session.sim = arena.sim
	tracker = ObjectiveTracker.new(arena.sim, PLAYER_ID, lesson)
	tracker.objective_progress.connect(func(_id, _c, _t): _refresh_objectives())
	tracker.objective_completed.connect(func(_id): _refresh_objectives())
	tracker.combo_changed.connect(func(count: int): _combo.text = "%d-hit combo" % count if count >= 2 else "")
	tracker.combo_failed.connect(func(_count: int): _combo.text = "")
	tracker.feedback.connect(func(_kind: String, text: String): _flash(text, GOOD))
	tracker.lesson_completed.connect(_on_completed)
	tracker.lesson_failed.connect(_on_failed)
	arena.connect("battle_finished", _on_battle_finished)
	opponent = TrainingOpponent.new(String(lesson.get("behaviour", "idle")), level, CombatInputBuilder.new(String(request["matchId"]), String(request["battleId"]), OPPONENT_ID),
			FighterRoster.stats_for(String(lesson["opponent_role"])), FighterRoster.stats_for(String(lesson["player_role"])), seed_value * 2 + 2)
	_combo.text = ""
	_refresh_objectives()


func _physics_process(_delta: float) -> void:
	if _paused or _ended or arena == null or tracker == null or arena.get("sim") == null or not arena.sim.is_running():
		return
	tracker.update()
	arena.sim.submit_input(opponent.packet(arena.sim.snapshot(false)))
	_tick_counter += 1


func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		_toast.modulate.a = clampf(_toast_time / 0.5, 0.0, 1.0)


func _flash(text: String, color: Color = GOOD) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", color)
	_toast.modulate.a = 1.0
	_toast_time = 1.6


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE):
		if _menu != null:
			_close_menu()
		elif _card == null:
			_open_menu()
		get_viewport().set_input_as_handled()


# ---- results ----------------------------------------------------------------------------------------------------------
func _on_completed(stats: Dictionary) -> void:
	if _ended:
		return
	_ended = true
	_freeze()
	var rating := ObjectiveTracker.rate(lesson, stats)
	progress.record_attempt(String(lesson["id"]), true, rating, float(stats.get("seconds", 0.0)))
	progress.save()
	var text := "%s medal · %.1f s · %d hits taken · best combo %d" % [rating.capitalize(), float(stats.get("seconds", 0.0)), int(stats.get("hits_taken", 0)), int(stats.get("best_combo", 0))]
	_show_card("Lesson complete", text, true)


func _on_failed(reason: String, stats: Dictionary) -> void:
	if _ended:
		return
	_ended = true
	_freeze()
	progress.record_attempt(String(lesson["id"]), false, "", float(stats.get("seconds", 0.0)))
	progress.save()
	_show_card("Not this time", reason if reason != "" else "The lesson was not completed.", false)


func _on_battle_finished(_result: Dictionary) -> void:
	if _ended:
		return
	if tracker != null:
		tracker.update()
	if _ended:
		return
	_ended = true
	if bool(lesson.get("free_practice", false)):
		_show_card("Fight over", "Free practice is not scored.", false)
	else:
		progress.record_attempt(String(lesson["id"]), false, "", float(tracker.summary().get("seconds", 0.0)) if tracker != null else 0.0)
		progress.save()
		_show_card("Fight over", "The lesson was not completed. Try again.", false)


func _freeze() -> void:
	if is_instance_valid(arena):
		arena.set_physics_process(false)


func _clear_card() -> void:
	if _card != null:
		if _card.has_meta("holder") and is_instance_valid(_card.get_meta("holder")):
			_card.get_meta("holder").queue_free()
		_card.queue_free()
		_card = null
	_remove_pad()


func _remove_pad() -> void:
	if is_instance_valid(_pad):
		_pad.queue_free()
	_pad = null


func _centered_plaque() -> Array:
	var holder := CenterContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(holder)
	var panel := _plaque(holder, 0.94)
	panel.custom_minimum_size = Vector2(420, 0)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	return [holder, column]


func _button(parent: Node, text: String, action: Callable, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 48)
	button.add_theme_font_size_override("font_size", 19)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(key, WHITE)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("8a6a2a") if primary else Color("1b2a3a")
	normal.border_color = Color("c9a45c")
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(8)
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = normal.bg_color.lightened(0.15)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("focus", hover)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _show_card(title: String, text: String, success: bool) -> void:
	_clear_card()
	_release_mouse()
	var made := _centered_plaque()
	_card = made[0].get_child(0)
	_card.set_meta("holder", made[0])
	var column: VBoxContainer = made[1]
	_label(column, title, 30, GOOD if success else TEXT)
	_label(column, text, 18, WHITE)
	var first: Button = null
	if success and next_lesson_id != "":
		first = _button(column, "Next lesson", func(): lesson_requested.emit(next_lesson_id), true)
	var retry := _button(column, "Try again" if not bool(lesson.get("free_practice", false)) else "Restart", func(): _restart(), first == null)
	if first == null:
		first = retry
	_button(column, "Back to lessons", func(): exit_requested.emit())
	_install_pad(first)


func _install_pad(first: Button) -> void:
	_pad = PadUi.install(self, {"back": Callable(self, "_pad_back")})
	first.call_deferred("grab_focus")


func _pad_back() -> void:
	if _menu != null:
		_close_menu()


func _release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _restart() -> void:
	seed_value += 1
	_clear_card()
	_paused = false
	_start_fight()


# ---- pause menu -------------------------------------------------------------------------------------------------------
func _open_menu() -> void:
	if _menu != null or _card != null:
		return
	_paused = true
	if is_instance_valid(arena):
		arena.set_physics_process(false)
	_release_mouse()
	var made := _centered_plaque()
	_menu = made[0].get_child(0)
	_menu.set_meta("holder", made[0])
	var column: VBoxContainer = made[1]
	_label(column, "Paused", 28, TEXT)
	var resume := _button(column, "Resume", _close_menu, true)
	_button(column, "Restart", func(): _close_menu(); _restart())
	_button(column, "Leave training", func(): exit_requested.emit())
	_install_pad(resume)


func _close_menu() -> void:
	if _menu == null:
		return
	if _menu.has_meta("holder") and is_instance_valid(_menu.get_meta("holder")):
		_menu.get_meta("holder").queue_free()
	_menu = null
	_remove_pad()
	_paused = false
	if is_instance_valid(arena) and not _ended:
		arena.set_physics_process(true)
		if arena.get("_mouse_captured") == true:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
