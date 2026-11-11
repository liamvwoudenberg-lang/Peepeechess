class_name ChessBattleModel
extends RefCounted
## Battle Chess capture model used only by the computer opponent's evaluation.
##
## A capture in Battle Chess is a duel, not an exchange. The search therefore treats a capture as a
## chance node: value = p * (attacker wins) + (1 - p) * (defender wins), where p is the attacker
## class's probability to win a duel against the defender class.
##
## p comes from the combat owner's measured bot matrix (combat/data/balance_matrix_v1.json): for each
## ordered pair of classes the "balanced / skill 0.6" configuration (the default CombatAI mirror) played
## N seeded fights; wins/N is smoothed with a Laplace prior (w+1)/(N+2) and clamped to [0.08, 0.92] so no
## capture is ever treated as certain. This is a BOT-measured heuristic, not a human balance claim.
## If the file is missing a class-strength tier fallback (queen > rook ~ knight > bishop > pawn) is used.
const MATRIX_PATH = "res://combat/data/balance_matrix_v1.json"
## Material value in the evaluation when captures are duels (centipawns). Loosely follows the class
## strength ranking documented in combat/BALANCE.md (queen strongest, pawn weakest) rather than
## orthodox chess values: a Knight is a strong fighter, a Pawn a weak one.
const FIGHT_VALUE = {"p": 90, "n": 340, "b": 300, "r": 430, "q": 900, "k": 0}
const TIER = {"p": 0.0, "b": 1.0, "r": 1.7, "n": 2.0, "q": 3.0, "k": 1.5}
static var _table: Dictionary = {}
static var _loaded = false

static func ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var parsed = null
	if FileAccess.file_exists(MATRIX_PATH):
		parsed = JSON.parse_string(FileAccess.get_file_as_string(MATRIX_PATH))
	if parsed is Dictionary and parsed.has("pairs"):
		for key in parsed.pairs:
			var configs: Array = parsed.pairs[key].get("configs", [])
			for config in configs:
				if config.get("style", "") == "balanced" and absf(float(config.get("skill", 0.0)) - 0.6) < 0.001:
					var played = maxf(1.0, float(config.get("played", 8)))
					_table[key] = clampf((float(config.get("wins", 0)) + 1.0) / (played + 2.0), 0.08, 0.92)
	for a in TIER:
		for d in TIER:
			if not _table.has(a + d):
				_table[a + d] = clampf(0.5 + (TIER[a] - TIER[d]) * 0.16, 0.08, 0.92)

## Probability that the attacking class wins a duel against the defending class.
static func win_probability(attacker_role: String, defender_role: String) -> float:
	ensure()
	return _table.get(attacker_role + defender_role, 0.5)

static func value(role: String) -> int:
	return FIGHT_VALUE.get(role, 0)
