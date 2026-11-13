class_name ProgressStore
extends RefCounted
## Saved training progress: per lesson the best rating, best time, attempts and whether it was ever completed, plus the difficulty
## settings. Stored in a ConfigFile (default user://training_progress.cfg), versioned, written atomically, and tolerant of a missing or
## corrupt file (it starts empty instead of failing). Headless-safe. Holds no secrets.
##
##   var progress := ProgressStore.new()      # loads the default file
##   progress.record_attempt("b03_first_strike", true, "silver", 41.5)
##   progress.save()

const VERSION := 1
const DEFAULT_PATH := "user://training_progress.cfg"
const RATINGS := ["", "bronze", "silver", "gold"]

var path: String
var lessons: Dictionary = {}    # id -> {completed, best_rating, best_seconds, attempts}
var adaptive: bool = true
var fixed_level: String = "normal"
var last_error: String = ""


func _init(p_path: String = DEFAULT_PATH, auto_load: bool = true) -> void:
	path = p_path
	if auto_load:
		load_file()


func load_file() -> void:
	lessons.clear()
	adaptive = true
	fixed_level = "normal"
	last_error = ""
	var config := ConfigFile.new()
	var err := config.load(path)
	if err != OK:
		if err != ERR_FILE_NOT_FOUND:
			last_error = "unreadable progress file (%d): starting empty" % err
		return
	if int(config.get_value("meta", "version", 0)) != VERSION:
		last_error = "progress file version not supported: starting empty"
		return
	adaptive = bool(config.get_value("settings", "adaptive", true))
	var level := String(config.get_value("settings", "fixed_level", "normal"))
	fixed_level = level if level in AIDifficulty.LEVELS else "normal"
	for section in config.get_sections():
		if not section.begins_with("lesson:"):
			continue
		var id := section.trim_prefix("lesson:")
		var rating := String(config.get_value(section, "best_rating", ""))
		lessons[id] = {
			"completed": bool(config.get_value(section, "completed", false)),
			"best_rating": rating if rating in RATINGS else "",
			"best_seconds": maxf(0.0, float(config.get_value(section, "best_seconds", 0.0))),
			"attempts": maxi(0, int(config.get_value(section, "attempts", 0))),
		}


func save() -> int:
	var config := ConfigFile.new()
	config.set_value("meta", "version", VERSION)
	config.set_value("settings", "adaptive", adaptive)
	config.set_value("settings", "fixed_level", fixed_level)
	for id in lessons:
		var entry: Dictionary = lessons[id]
		var section := "lesson:%s" % id
		config.set_value(section, "completed", entry["completed"])
		config.set_value(section, "best_rating", entry["best_rating"])
		config.set_value(section, "best_seconds", entry["best_seconds"])
		config.set_value(section, "attempts", entry["attempts"])
	var tmp := path + ".tmp"
	var err := config.save(tmp)
	if err != OK:
		last_error = "could not write %s (%d)" % [tmp, err]
		return err
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		last_error = "cannot open folder of %s" % path
		return ERR_FILE_CANT_OPEN
	if dir.file_exists(path.get_file()):
		dir.remove(path.get_file())
	err = dir.rename(tmp.get_file(), path.get_file())
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
