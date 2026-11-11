class_name AbilityComponent
extends RefCounted
## One signature ability per fighter, gated by a cooldown (FighterStats.cooldownTicks), a
## stamina cost and an optional condition. Buff abilities (Last Stand) are timed modifiers
## held here; attack abilities (Lunging Strike) are executed by the state machine through
## AttackLibrary and only gated/cooled down here.

const Balance := preload("res://combat/data/balance_data.gd")

## id -> definition. The data is in balance_v1.json (see Balance); this getter keeps the old
## `AbilityComponent.DEFINITIONS` access working and always reflects the active tuning (copy per read).
## Kinds: "buff" (timed modifiers), "attack" (an AttackLibrary swing), "blink" (teleport), "counter"
## (Royal Counter stance: armoured, a timed frontal hit is negated and riposted).
static var DEFINITIONS: Dictionary:
	get:
		var out := {}
		for id in Balance.ability_ids():
			out[id] = Balance.ability(id)
		return out


var ability_id: String = ""
var definition: Dictionary = {}
var cooldown_total: int = 0
var cooldown_remaining: int = 0
var buff_remaining: int = 0
var activations: int = 0


static func is_known(id: String, allow_experimental: bool = false) -> bool:
	return Balance.has_ability(id) and (allow_experimental or not bool(Balance.ability(id).get("experimental", false)))


## Returns false if the ability id is not implemented (the authority must then refuse the battle).
## Experimental abilities (the King's Royal Counter, not part of the v1 contract) are refused unless
## `allow_experimental` is set - only the opt-in `CombatSimulation.start(request, options)` path sets it.
func setup(id: String, cooldown_ticks: int, allow_experimental: bool = false) -> bool:
	if not is_known(id, allow_experimental):
		return false
	ability_id = id
	definition = Balance.ability(id)
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
	return float(definition.get("move_mult", 1.0)) if buff_active() else 1.0


func attack_speed_mult() -> float:
	return float(definition.get("attack_speed_mult", 1.0)) if buff_active() else 1.0


func damage_mult() -> float:
	return float(definition.get("damage_mult", 1.0)) if buff_active() else 1.0


func regen_mult() -> float:
	return float(definition.get("regen_mult", 1.0)) if buff_active() else 1.0


## Length of the light chain: CombatConstants.COMBO_LENGTH, longer while a buff extends it (Royal Fury).
func combo_length() -> int:
	if buff_active():
		return int(definition.get("combo_length", CombatConstants.COMBO_LENGTH))
	return CombatConstants.COMBO_LENGTH


## Multiplier on the stamina a blocked hit costs (Fortress Guard: 0).
func guard_cost_mult() -> float:
	return float(definition.get("guard_cost_mult", 1.0)) if buff_active() else 1.0


func guard_unbreakable() -> bool:
	return buff_active() and bool(definition.get("guard_unbreakable", false))


## Multiplier on the maximum poise pool (Fortress Guard: 3x).
func poise_mult() -> float:
	return float(definition.get("poise_mult", 1.0)) if buff_active() else 1.0
