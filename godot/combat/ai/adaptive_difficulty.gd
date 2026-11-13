class_name AdaptiveDifficulty
extends RefCounted
## Optional training controller: moves the AI level one step at a time from the player's demonstrated performance, or stays on a fixed
## level. A smoothed score (exponential moving average of per-fight performance, 0..1) must stay above `up_at` / below `down_at`
## for `min_fights_between_changes` fights before the level changes, so one lucky or unlucky fight never swings it.
##
##   var ctl := AdaptiveDifficulty.new("normal")          # adaptive, starts on Normal
##   var fixed := AdaptiveDifficulty.fixed("hard")        # never changes
##   ctl.record_fight({"won": true, "hit_ratio": 0.6, "damage_taken": 0.3, "parries": 2})
##   ctl.level   # "normal" / "hard" ... for the next fight

const MIN_INDEX := 0
const MAX_INDEX := 3

var adaptive: bool = true
var index: int = 1
var score: float = 0.5
var smoothing: float = 0.4          # weight of the newest fight
var up_at: float = 0.72
var down_at: float = 0.32
var min_fights_between_changes: int = 2
var fights: int = 0
var _since_change: int = 0


func _init(start_level: String = "normal") -> void:
	index = clampi(AIDifficulty.level_index(start_level), MIN_INDEX, MAX_INDEX)


static func fixed(start_level: String) -> AdaptiveDifficulty:
	var ctl := AdaptiveDifficulty.new(start_level)
	ctl.adaptive = false
	return ctl


var level: String:
	get:
		return AIDifficulty.LEVELS[index]


## Performance of one finished fight, 0..1: a win counts 0.5, the rest comes from how cleanly it was won (hit ratio, damage taken as a
## fraction of the player's health, parries landed).
static func performance(fight: Dictionary) -> float:
	var won := 0.5 if bool(fight.get("won", false)) else 0.0
	var hit_ratio := clampf(float(fight.get("hit_ratio", 0.5)), 0.0, 1.0)
	var taken := clampf(float(fight.get("damage_taken", 0.5)), 0.0, 1.0)
	var parry_bonus := clampf(float(fight.get("parries", 0)) / 4.0, 0.0, 1.0)
	return clampf(won + 0.2 * hit_ratio + 0.2 * (1.0 - taken) + 0.1 * parry_bonus, 0.0, 1.0)


## Feeds one finished fight; returns the level for the next one.
func record_fight(fight: Dictionary) -> String:
	fights += 1
	_since_change += 1
	score = lerpf(score, performance(fight), smoothing)
	if adaptive and _since_change >= min_fights_between_changes:
		if score > up_at and index < MAX_INDEX:
			index += 1
			_after_change()
		elif score < down_at and index > MIN_INDEX:
			index -= 1
			_after_change()
	return level


func _after_change() -> void:
	_since_change = 0
	score = 0.5   # the new level starts from neutral so it has to be earned again
