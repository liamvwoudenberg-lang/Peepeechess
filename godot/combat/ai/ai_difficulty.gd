class_name AIDifficulty
extends RefCounted
## Four AI difficulty presets as reusable PARAMETER SETS for CombatAI. A preset changes how the AI decides (reaction delay, how
## often it defends or hesitates, how long its combos are, how well it times a parry), never how much damage it deals or how much
## health it has: the AI plays through the same CombatInput channel as a human, sees only the public CombatSnapshot (never a future
## tick, never the human's pending input) and obeys the same recovery windows, stamina and cooldowns.
##
##   var ai := AIDifficulty.make_ai("hard", builder, my_stats, opp_stats, seed)
##
## `config(level)` -> {style, skill, params}: `style` and `skill` are CombatAI's existing knobs, `params` are the NEUTRAL keys that
## CombatAI.apply_params() accepts (react_extra, error_rate, follow_chance, timing_jitter, heavy_chance, defence_scale, parry_bias,
## block_bias, follow_max, cooldown_scale, poke, hold_extra, punish, ...). Add a level or tune one by editing PRESETS only.
## BEHAVIOURS are the fixed opponents of Free Practice and lessons (idle, passive_block, attack_only, normal).

const ChessRules = preload("res://config/chess_rules.gd")
const LEVELS := ["easy", "normal", "hard", "expert"]
const BEHAVIOURS := ["idle", "passive_block", "attack_only", "normal"]

static var PRESETS: Dictionary = ChessRules.duel_ai_levels()   # config/chess_rules.json: duel_ai_levels

## Fixed-behaviour opponents (lessons / Free Practice). `idle` and `passive_block` are driven by TrainingOpponent without a CombatAI.
const BEHAVIOUR_PARAMS := {
	"attack_only": {"style": "aggressive", "skill": 0.4, "params": {"defence_scale": 0.0, "error_rate": 0.0, "poke": 1.0}},
}


static func level_index(level: String) -> int:
	return maxi(0, LEVELS.find(level.to_lower()))


static func config(level: String) -> Dictionary:
	var preset: Dictionary = PRESETS[LEVELS[level_index(level)]]
	return {"style": preset["style"], "skill": preset["skill"], "params": preset["params"].duplicate()}


static func label(level: String) -> String:
	return String(PRESETS[LEVELS[level_index(level)]]["label"])


static func summary(level: String) -> String:
	return String(PRESETS[LEVELS[level_index(level)]]["summary"])


## A CombatAI configured for `level` (a LEVELS name) or for a custom {style, skill, params} dictionary.
static func make_ai(level_or_config: Variant, builder: CombatInputBuilder, my_stats: Dictionary, opp_stats: Dictionary, seed_value: int = 1) -> CombatAI:
	var cfg: Dictionary = level_or_config if level_or_config is Dictionary else config(String(level_or_config))
	var ai := CombatAI.new(builder, my_stats, opp_stats, seed_value, float(cfg["skill"]), String(cfg["style"]))
	ai.apply_params(cfg.get("params", {}))
	return ai


## Behaviour AI for a lesson opponent: `attack_only` and `normal` (with `level`) return a CombatAI; `idle` / `passive_block` return null
## (TrainingOpponent builds their packets).
static func make_behaviour_ai(behaviour: String, level: String, builder: CombatInputBuilder, my_stats: Dictionary, opp_stats: Dictionary, seed_value: int) -> CombatAI:
	match behaviour:
		"attack_only":
			return make_ai(BEHAVIOUR_PARAMS["attack_only"], builder, my_stats, opp_stats, seed_value)
		"normal":
			return make_ai(level, builder, my_stats, opp_stats, seed_value)
	return null
