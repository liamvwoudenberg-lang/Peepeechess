extends Node
## Full-screen scene of a training fight. Launched by ui/training_page.gd with Settings.launch = {"training": {"lesson": id}} or
## {"training": {"free": {player_role, opponent_role, behaviour, difficulty}}}; leaving returns to the application's Training page.

const Settings = preload("res://ui/application_settings.gd")
const APPLICATION := "res://ui/application.tscn"

var catalog: LessonCatalog
var progress: ProgressStore
var view: TrainingView


func _ready() -> void:
	progress = DuelAi.store()
	catalog = LessonCatalog.load_all()
	var launch := Settings.take_launch()
	var request: Dictionary = launch.get("training", {})
	if request.has("free"):
		_run(FreePractice.make(request["free"]), "")
	elif request.has("lesson") and not catalog.get_lesson(String(request["lesson"])).is_empty():
		_run_lesson(String(request["lesson"]))
	else:
		_leave()


func _run_lesson(lesson_id: String) -> void:
	var lesson := catalog.get_lesson(lesson_id)
	_run(lesson, catalog.next_after(lesson_id))


func _run(lesson: Dictionary, next_id: String) -> void:
	if is_instance_valid(view):
		view.queue_free()
	view = TrainingView.new()
	view.setup(lesson, String(lesson.get("difficulty", "normal")), progress, next_id)
	view.exit_requested.connect(_leave)
	view.lesson_requested.connect(_run_lesson)
	add_child(view)


func _leave() -> void:
	Settings.launch = {"menu": "training"}
	get_tree().change_scene_to_file(APPLICATION)
