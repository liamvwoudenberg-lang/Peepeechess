class_name FreePractice
extends RefCounted
## Free Practice: any player role against any opponent role with a chosen opponent behaviour and difficulty, no objectives. It is an
## ordinary lesson dictionary (so TrainingSession / the UI run it like every other lesson) with `free_practice: true`: nothing is rated or
## saved, and the UI restarts the fight when it ends.
##
##   var lesson := FreePractice.make({"player_role": "n", "opponent_role": "q", "behaviour": "normal", "difficulty": "hard"})

const BEHAVIOUR_LABELS := {"idle": "Stand still", "passive_block": "Block", "attack_only": "Attack", "normal": "Fight normally"}


static func make(config: Dictionary = {}) -> Dictionary:
	var behaviour := String(config.get("behaviour", "idle"))
	var level := String(config.get("difficulty", "normal"))
	var player_role := String(config.get("player_role", "p"))
	var opponent_role := String(config.get("opponent_role", "p"))
	return {
		"id": "free_practice", "title": "Free Practice", "summary": "Practise freely.", "category": "beginner", "order": 0,
		"player_role": player_role if player_role in FighterRoster.ALL_ROLES else "p",
		"opponent_role": opponent_role if opponent_role in FighterRoster.ALL_ROLES else "p",
		"behaviour": behaviour if behaviour in AIDifficulty.BEHAVIOURS else "idle",
		"difficulty": level if level in AIDifficulty.LEVELS else "normal",
		"attacker": String(config.get("attacker", "player")),
		"arena": "stone-v1", "objectives": [], "fail": [], "free_practice": true,
	}
