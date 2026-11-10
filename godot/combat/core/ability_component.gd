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
	# Bishop: directional teleport. The body vanishes (invulnerable) for `iframe_ticks`, reappears
	# `blink_tick` ticks after the cast started up to `blink_distance` metres away (stopped by walls,
	# pillars and the opponent), then recovers for the rest of `cast_ticks`.
	"blink": {
		"kind": "blink", "cast_ticks": 20, "stamina_cost": 20.0, "blink_distance": 4.0, "blink_tick": 3,
		"iframe_ticks": 10, "role": "b",
	},
	# Rook: 4 s of stronger guard (blocking costs no stamina and cannot be guard-broken), 3x poise,
	# slower movement. Casting is armoured and costs a little stamina.
	"fortress-guard": {
		"kind": "buff", "cast_ticks": 18, "stamina_cost": 10.0, "buff_ticks": 240,
		"move_mult": 0.7, "guard_cost_mult": 0.0, "guard_unbreakable": true, "poise_mult": 3.0, "role": "r",
	},
	# Queen: 6 s of quicker attacks, stronger hits, faster stamina regeneration and a chain of FIVE light
	# links instead of three (links 4 and 5 are only reachable while the buff is active).
	"royal-fury": {
		"kind": "buff", "cast_ticks": 14, "stamina_cost": 15.0, "buff_ticks": 360,
		"move_mult": 1.1, "attack_speed_mult": 1.35, "damage_mult": 1.1, "regen_mult": 1.5, "combo_length": 5, "role": "q",
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
