class_name CampaignProgress
extends RefCounted
## Saved campaign meta-progress and the run in progress, as JSON (default user://campaign_progress.json): versioned, written atomically, tolerant of a
## missing or corrupt file (starts empty, no engine error), offline, no account, no secrets. Also the unlock rules (skins, arenas, bonus Training lessons are
## granted the first time an encounter is cleared) and the equipped cosmetics.
##
## Skin ids are saved and shown, but applying a skin to the paladin models belongs to the paladin code (not wired yet, see docs/application/CAMPAIGN.md).
## Arena palettes are applied by StoneArenaVisuals through arena_light().

const VERSION := 1
const DEFAULT_PATH := "user://campaign_progress.json"
const SKINS := ["gilded", "obsidian", "ember"]
const ARENAS := ["crypt", "moonlit", "ember"]
## Arena palette -> the moonlight colour (the default arena stays white-blue).
const ARENA_LIGHT := {"crypt": Color(0.62, 0.9, 0.78), "moonlit": Color(0.6, 0.7, 1.0), "ember": Color(1.0, 0.62, 0.42)}

static var _shared: CampaignProgress = null

var path: String
var run: CampaignRun = null
var unlocked_skins: Array = []
var unlocked_arenas: Array = []
var unlocked_lessons: Array = []
var equipped_skin: String = ""
var equipped_arena: String = ""
var best_cleared: int = 0           # most encounters cleared in a single run
var runs_started: int = 0
var runs_cleared: int = 0
var cleared_ever: Array = []        # encounter ids cleared at least once (rewards are granted once)
var last_error: String = ""


static func shared() -> CampaignProgress:
	if _shared == null:
		_shared = CampaignProgress.new()
	return _shared


func _init(p_path: String = DEFAULT_PATH, auto_load: bool = true) -> void:
	path = p_path
	if auto_load:
		load_file()


func load_file() -> void:
	run = null
	unlocked_skins.clear()
	unlocked_arenas.clear()
	unlocked_lessons.clear()
	equipped_skin = ""
	equipped_arena = ""
	best_cleared = 0
	runs_started = 0
	runs_cleared = 0
	cleared_ever.clear()
	last_error = ""
	if not FileAccess.file_exists(path):
		return
	var json := JSON.new()
	var parsed = json.data if json.parse(FileAccess.get_file_as_string(path)) == OK else null
	if not (parsed is Dictionary):
		last_error = "unreadable campaign file: starting empty"
		return
	if int(parsed.get("version", 0)) != VERSION:
		last_error = "campaign file version not supported: starting empty"
		return
	var meta = parsed.get("meta", {})
	if meta is Dictionary:
		for id in meta.get("skins", []):
			if str(id) in SKINS and not unlocked_skins.has(str(id)):
				unlocked_skins.append(str(id))
		for id in meta.get("arenas", []):
			if str(id) in ARENAS and not unlocked_arenas.has(str(id)):
				unlocked_arenas.append(str(id))
		for id in meta.get("lessons", []):
			if str(id) != "" and not unlocked_lessons.has(str(id)):
				unlocked_lessons.append(str(id))
		for id in meta.get("cleared", []):
			if CampaignNodes.index_of(str(id)) >= 0 and not cleared_ever.has(str(id)):
				cleared_ever.append(str(id))
		var skin := str(meta.get("equipped_skin", ""))
		equipped_skin = skin if unlocked_skins.has(skin) else ""
		var arena := str(meta.get("equipped_arena", ""))
		equipped_arena = arena if unlocked_arenas.has(arena) else ""
		best_cleared = clampi(int(meta.get("best_cleared", 0)), 0, CampaignNodes.count())
		runs_started = maxi(0, int(meta.get("runs_started", 0)))
		runs_cleared = maxi(0, int(meta.get("runs_cleared", 0)))
	run = CampaignRun.from_dict(parsed.get("run", null))


func save() -> int:
	var data := {"version": VERSION, "meta": {"skins": unlocked_skins, "arenas": unlocked_arenas, "lessons": unlocked_lessons, "cleared": cleared_ever,
			"equipped_skin": equipped_skin, "equipped_arena": equipped_arena, "best_cleared": best_cleared, "runs_started": runs_started, "runs_cleared": runs_cleared},
			"run": run.to_dict() if run != null else null}
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


func start_run(seed_value: int) -> CampaignRun:
	run = CampaignRun.start(seed_value)
	runs_started += 1
	save()
	return run


func abandon_run() -> void:
	run = null
	save()


## Applies the result of the current encounter to the run and the meta-progress, then saves. Returns the run's report plus `rewards` (newly unlocked).
func report_result(won: bool) -> Dictionary:
	if run == null:
		return {"event": "ignored", "rewards": []}
	var index := run.index
	var result := run.report(won)
	var rewards: Array = []
	if won and str(result.get("event", "")) in ["boon", "cleared", "advance"]:
		rewards = _grant(CampaignNodes.node(index))
	if run.nodes_cleared() > best_cleared:
		best_cleared = run.nodes_cleared()
	if str(result.get("event", "")) == "cleared":
		runs_cleared += 1
	result["rewards"] = rewards
	save()
	return result


func _grant(data: Dictionary) -> Array:
	var id := str(data.get("id", ""))
	if id == "" or cleared_ever.has(id):
		return []
	cleared_ever.append(id)
	var rewards: Array = []
	var reward: Dictionary = data.get("reward", {})
	if reward.has("skin") and not unlocked_skins.has(str(reward["skin"])):
		unlocked_skins.append(str(reward["skin"]))
		rewards.append("skin:" + str(reward["skin"]))
	if reward.has("arena") and not unlocked_arenas.has(str(reward["arena"])):
		unlocked_arenas.append(str(reward["arena"]))
		rewards.append("arena:" + str(reward["arena"]))
	if reward.has("lesson") and not unlocked_lessons.has(str(reward["lesson"])):
		unlocked_lessons.append(str(reward["lesson"]))
		rewards.append("lesson:" + str(reward["lesson"]))
	return rewards


func equip_skin(id: String) -> bool:
	if id != "" and not unlocked_skins.has(id):
		return false
	equipped_skin = id
	save()
	return true


func equip_arena(id: String) -> bool:
	if id != "" and not unlocked_arenas.has(id):
		return false
	equipped_arena = id
	save()
	return true


func is_lesson_unlocked(lesson_id: String) -> bool:
	return unlocked_lessons.has(lesson_id)


## The arena's moonlight colour with the equipped palette applied (the default colour when none is equipped).
static func arena_light(default_color: Color) -> Color:
	var arena := shared().equipped_arena
	return ARENA_LIGHT.get(arena, default_color) if arena != "" else default_color
