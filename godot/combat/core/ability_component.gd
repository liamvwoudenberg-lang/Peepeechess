class_name AbilityComponent
extends RefCounted
## One signature ability per fighter, gated by a cooldown (FighterStats.cooldownTicks), a
## stamina cost and an optional condition. Buff abilities (Last Stand) are timed modifiers
## held here; attack abilities (Lunging Strike) are executed by the state machine through
## AttackLibrary and only gated/cooled down here.

const DEFINITIONS := {
	# Pawn: below 35% HP, 5 s of faster movement and attacks, stronger hits, quicker stamina.
	"last-stand": {
		"kind": "buff", "cast_ticks": 12, "stamina_cost": 0.0, "hp_threshold": 0.35, "buff_ticks": 300,
		"move_mult": 1.3, "attack_speed_mult": 1.3, "damage_mult": 1.15, "regen_mult": 1.5, "role": "p",
	},
	# Knight: a committed forward charge executed as an AttackDefinition.
	"lunging-strike": {
		"kind": "attack", "stamina_cost": 28.0, "role": "n",
	},
}

var ability_id: String = ""
var definition: Dictionary = {}
var cooldown_total: int = 0
var cooldown_remaining: int = 0
var buff_remaining: int = 0
var activations: int = 0


static func is_known(id: String) -> bool:
	return DEFINITIONS.has(id)


## Returns false if the ability id is not implemented (the authority must then refuse the battle).
func setup(id: String, cooldown_ticks: int) -> bool:
	if not DEFINITIONS.has(id):
		return false
	ability_id = id
	definition = DEFINITIONS[id]
	cooldown_total = cooldown_ticks
	cooldown_remaining = 0
	buff_remaining = 0
	activations = 0
	return true


func is_attack_ability() -> bool:
	return definition.get("kind", "") == "attack"


func stamina_cost() -> float:
	return float(definition.get("stamina_cost", 0.0))


## {"ok": bool, "reason": "" | "cooldown" | "condition" | "stamina"}
func check(health: HealthComponent, stamina: StaminaComponent) -> Dictionary:
	if cooldown_remaining > 0:
		return {"ok": false, "reason": "cooldown"}
	if definition.has("hp_threshold") and not health.at_or_below(float(definition["hp_threshold"])):
		return {"ok": false, "reason": "condition"}
	# A free ability (Last Stand) stays usable while exhausted - that is when it matters most.
	if stamina_cost() > 0.0 and not stamina.can_afford(stamina_cost()):
		return {"ok": false, "reason": "stamina"}
	return {"ok": true, "reason": ""}


## Starts the cooldown (and the buff). Call once the cast has actually been accepted.
func commit() -> void:
	cooldown_remaining = cooldown_total
	activations += 1
	if definition.get("kind", "") == "buff":
		buff_remaining = int(definition["buff_ticks"])


func tick() -> void:
	if cooldown_remaining > 0:
		cooldown_remaining -= 1
	if buff_remaining > 0:
		buff_remaining -= 1


func buff_active() -> bool:
	return buff_remaining > 0


func move_mult() -> float:
	return float(definition["move_mult"]) if buff_active() else 1.0


func attack_speed_mult() -> float:
	return float(definition["attack_speed_mult"]) if buff_active() else 1.0


func damage_mult() -> float:
	return float(definition["damage_mult"]) if buff_active() else 1.0


func regen_mult() -> float:
	return float(definition["regen_mult"]) if buff_active() else 1.0
