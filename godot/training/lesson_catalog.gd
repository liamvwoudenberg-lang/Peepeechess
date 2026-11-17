class_name LessonCatalog
extends RefCounted
## Loads and orders the lessons in a folder (default res://training/lessons/*.json) and answers unlock questions.
##
##   var catalog := LessonCatalog.load_all()
##   for lesson in catalog.in_category("beginner"): ...
##   catalog.is_unlocked("b03_first_strike", progress)   # ProgressStore
##   catalog.next_after("b03_first_strike")              # next available lesson id or ""
##
## A lesson unlocks when every id in its `requires` list has been completed (any rating). A lesson without `requires` is unlocked when it is the
## first of its category. Unavailable lessons (`available: false`) are listed but can never be started, and never block the next one.

const DEFAULT_DIR := "res://training/lessons"

var lessons: Array = []          # ordered by (category, order)
var by_id: Dictionary = {}
var errors: Array = []           # schema problems found while loading (an invalid lesson is skipped)


static func load_all(dir_path: String = DEFAULT_DIR) -> LessonCatalog:
	var catalog := LessonCatalog.new()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		catalog.errors.append("cannot open %s" % dir_path)
		return catalog
	var names := dir.get_files()
	names.sort()
	for file_name in names:
		var name_str := String(file_name).trim_suffix(".remap")
		if not name_str.ends_with(".json"):
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [dir_path, name_str]))
		if not (parsed is Dictionary):
			catalog.errors.append("%s: not a JSON object" % name_str)
			continue
		var problems := LessonSchema.validate(parsed)
		if not problems.is_empty():
			catalog.errors.append_array(problems)
			continue
		if catalog.by_id.has(parsed["id"]):
			catalog.errors.append("duplicate lesson id %s" % parsed["id"])
			continue
		catalog.lessons.append(parsed)
		catalog.by_id[parsed["id"]] = parsed
	catalog.lessons.sort_custom(func(a, b):
		var ca := LessonSchema.CATEGORIES.find(String(a["category"]))
		var cb := LessonSchema.CATEGORIES.find(String(b["category"]))
		return ca < cb or (ca == cb and float(a["order"]) < float(b["order"])))
	return catalog


func get_lesson(id: String) -> Dictionary:
	return by_id.get(id, {})


func in_category(category: String) -> Array:
	return lessons.filter(func(l): return String(l["category"]) == category)


func playable() -> Array:
	return lessons.filter(func(l): return bool(l.get("available", true)))


func is_available(id: String) -> bool:
	return by_id.has(id) and bool(by_id[id].get("available", true))


func is_unlocked(id: String, progress: ProgressStore) -> bool:
	var lesson := get_lesson(id)
	if lesson.is_empty() or not is_available(id):
		return false
	if CampaignProgress.shared().is_lesson_unlocked(id):   # a Campaign reward opens the lesson without its prerequisites
		return true
	if lesson.has("requires"):
		for required in lesson["requires"]:
			# an unavailable prerequisite never blocks
			if is_available(String(required)) and not progress.is_completed(String(required)):
				return false
		return true
	var first := in_category(String(lesson["category"])).filter(func(l): return bool(l.get("available", true)))
	return not first.is_empty() and first[0]["id"] == id


## The next available lesson after `id` in catalog order ("" at the end).
func next_after(id: String) -> String:
	var i := -1
	for k in lessons.size():
		if lessons[k]["id"] == id:
			i = k
	for k in range(i + 1, lessons.size()):
		if bool(lessons[k].get("available", true)):
			return String(lessons[k]["id"])
	return ""
