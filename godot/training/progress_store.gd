class_name ProgressStore
extends RefCounted
## Saved training progress: per lesson the best rating, best time, attempts and whether it was ever completed, plus the difficulty
## settings. Stored as JSON (default user://training_progress.json), versioned, written atomically, and tolerant of a missing, corrupt
## or foreign file (it starts empty instead of failing, and prints no engine error). Headless-safe. Holds no secrets.
##
##   var progress := ProgressStore.new()      # loads the default file
##   progress.record_attempt("b03_first_strike", true, "silver", 41.5)
##   progress.save()

const VERSION := 1
const DEFAULT_PATH := "user://training_progress.json"
const RATINGS := ["", "bronze", "silver", "gold"]

var path: String
var lessons: Dictionary = {}    # id -> {completed, best_rating, best_seconds, attempts}
var adaptive: bool = true
var fixed_level: String = "normal"   # the fixed duel level, or the level adaptive difficulty has reached
var duel_ai: String = "auto"         # Battle Chess duel opponent: auto (follows the chess level) | easy..expert | adaptive
var last_error: String = ""


func _init(p_path: String = DEFAULT_PATH, auto_load: bool = true) -> void:
	path = p_path
	if auto_load:
		load_file()


func load_file() -> void:
	lessons.clear()
	adaptive = true
	fixed_level = "normal"
	duel_ai = "auto"
	last_error = ""
	if not FileAccess.file_exists(path):
		return
	var json := JSON.new()   # (an instance reports a parse error silently; JSON.parse_string would print an engine error)
	var parsed = json.data if json.parse(FileAccess.get_file_as_string(path)) == OK else null
	if not (parsed is Dictionary):
		last_error = "unreadable progress file: starting empty"
		return
	if int(parsed.get("version", 0)) != VERSION:
		last_error = "progress file version not supported: starting empty"
		return
	var settings = parsed.get("settings", {})
	if settings is Dictionary:
		adaptive = bool(settings.get("adaptive", true))
		var level := String(settings.get("fixed_level", "normal"))
		fixed_level = level if level in AIDifficulty.LEVELS else "normal"
		var duel := String(settings.get("duel_ai", "auto"))
		duel_ai = duel if duel == "auto" or duel == "adaptive" or duel in AIDifficulty.LEVELS else "auto"
	var stored = parsed.get("lessons", {})
	if not (stored is Dictionary):
		return
	for id in stored:
		var entry = stored[id]
		if not (entry is Dictionary):
			continue
		var rating := String(entry.get("best_rating", ""))
		lessons[String(id)] = {
			"completed": bool(entry.get("completed", false)),
			"best_rating": rating if rating in RATINGS else "",
			"best_seconds": maxf(0.0, float(entry.get("best_seconds", 0.0))),
			"attempts": maxi(0, int(entry.get("attempts", 0))),
		}


func save() -> int:
	var data := {"version": VERSION, "settings": {"adaptive": adaptive, "fixed_level": fixed_level, "duel_ai": duel_ai}, "lessons": lessons}
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		last_error = "could not write %s (%d)" % [tmp, FileAccess.get_open_error()]
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		last_error = "cannot open folder of %s" % path
		return ERR_FILE_CANT_OPEN
	if dir.file_exists(path.get_file()):
		dir.remove(path.get_file())
	var err := dir.rename(tmp.get_file(), path.get_file())
	if err != OK:
		last_error = "could not replace %s (%d)" % [path, err]
	return err


## Records one finished attempt. `rating` is "" for a failed attempt, else bronze|silver|gold. Keeps the best rating and fastest time.
func record_attempt(id: String, completed: bool, rating: String, seconds: float) -> void:
	var entry: Dictionary = lessons.get(id, {"completed": false, "best_rating": "", "best_seconds": 0.0, "attempts": 0})
	entry["attempts"] = int(entry["attempts"]) + 1
	if completed:
		entry["completed"] = true
		if RATINGS.find(rating) > RATINGS.find(String(entry["best_rating"])):
			entry["best_rating"] = rating
		if float(entry["best_seconds"]) <= 0.0 or seconds < float(entry["best_seconds"]):
			entry["best_seconds"] = seconds
	lessons[id] = entry


func is_completed(id: String) -> bool:
	return bool(lessons.get(id, {}).get("completed", false))


func best_rating(id: String) -> String:
	return String(lessons.get(id, {}).get("best_rating", ""))


func attempts(id: String) -> int:
	return int(lessons.get(id, {}).get("attempts", 0))


func completed_count() -> int:
	var n := 0
	for id in lessons:
		if bool(lessons[id]["completed"]):
			n += 1
	return n


func reset() -> void:
	lessons.clear()
