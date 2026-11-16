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

const LEVELS := ["easy", "normal", "hard", "expert"]
const BEHAVIOURS := ["idle", "passive_block", "attack_only", "normal"]

const PRESETS := {
	"easy": {
		"label": "Easy", "style": "balanced", "skill": 0.1,
		"params": {"react_extra": 16, "error_rate": 0.3, "follow_chance": 0.5, "follow_max": 1, "heavy_chance": 0.08,
				"defence_scale": 0.35, "parry_bias": -0.3, "block_bias": 0.1, "cooldown_scale": 1.8, "poke": 0.45, "hold_extra": 0.2},
		"summary": "Slow reactions, obvious attacks, short combos, forgiving timing.",
	},
	"normal": {
		"label": "Normal", "style": "balanced", "skill": 0.5,
		"params": {"react_extra": 4, "error_rate": 0.1, "follow_chance": 0.85, "follow_max": 2, "heavy_chance": 0.15,
				"defence_scale": 0.9, "cooldown_scale": 1.1},
		"summary": "Reasonable reactions, blocks and dodges sometimes, simple combos.",
	},
	"hard": {
		"label": "Hard", "style": "duelist", "skill": 0.78,
		"params": {"react_extra": 0, "error_rate": 0.06, "timing_jitter": 3, "follow_chance": 1.0, "follow_max": 2, "poke": 0.6},
		"summary": "Good spacing, parries on the frame data, punishes recovery, full light chains.",
	},
	"expert": {
		"label": "Expert", "style": "duelist", "skill": 1.0,
		"params": {"react_extra": 0, "error_rate": 0.0, "timing_jitter": 0, "follow_chance": 1.0, "follow_max": 2, "poke": 0.75,
				"cooldown_scale": 0.8, "heavy_chance": 0.22},
		"summary": "Matchup-aware, precise timing, punishes every opening, advanced combos. Still human-fair.",
	},
}

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
