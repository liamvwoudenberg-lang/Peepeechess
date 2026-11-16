class_name DuelAi
extends RefCounted
## The Battle Chess duel opponent's difficulty: "auto" (the old behaviour, the chess level decides), a fixed Easy / Normal / Hard / Expert
## preset, or "adaptive" (starts at the saved level and moves one step at a time from how the player does). The choice and the adaptive
## level are saved in the training progress file (ProgressStore), so they survive restarts and are shared with Training.

const CHOICES := ["auto", "easy", "normal", "hard", "expert", "adaptive"]
const LABELS := {"auto": "Match chess level", "easy": "Easy", "normal": "Normal", "hard": "Hard", "expert": "Expert", "adaptive": "Adaptive"}

static var _store: ProgressStore = null
static var _controller: AdaptiveDifficulty = null


static func store() -> ProgressStore:
	if _store == null:
		_store = ProgressStore.new()
	return _store


static func choice() -> String:
	return store().duel_ai


static func set_choice(value: String) -> void:
	if value not in CHOICES:
		return
	store().duel_ai = value
	_controller = null
	store().save()


static func describe(value: String) -> String:
	match value:
		"auto":
			return "The computer's chess level also sets how well it fights."
		"adaptive":
			return "Starts at %s and moves up or down as you win or lose duels." % AIDifficulty.label(store().fixed_level)
	return AIDifficulty.summary(value)


## The AIDifficulty level the computer's duel seat should use now, "" for "auto" (keep the chess level's profile).
static func seat_level() -> String:
	var value := choice()
	if value == "auto":
		return ""
	if value == "adaptive":
		return store().fixed_level
	return value


## Feeds one finished duel against the computer (adaptive only): the level for the NEXT duel is saved.
static func record_duel(won: bool, damage_taken_fraction: float) -> void:
	if choice() != "adaptive":
		return
	if _controller == null:
		_controller = AdaptiveDifficulty.new(store().fixed_level)
	_controller.record_fight({"won": won, "hit_ratio": 0.6 if won else 0.3, "damage_taken": clampf(damage_taken_fraction, 0.0, 1.0), "parries": 0})
	store().fixed_level = _controller.level
	store().save()
