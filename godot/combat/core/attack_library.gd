class_name AttackLibrary
extends RefCounted
## Per-role attack tables (data: res://combat/data/balance_v1.json). Bot-measured, not human-tested balance.
## Timings scale off the FighterStats the authority supplies (lightTicks, heavyTicks); the
## relative shapes (windows, damage multipliers, costs) live in the data.

const Balance := preload("res://combat/data/balance_data.gd")


## Roles the v1 contract can send (the King is experimental: see FighterProfile.is_experimental_role).
static func supports_role(role: String) -> bool:
	return role == "p" or role == "n" or role == "b" or role == "r" or role == "q"


## {"light": Array[AttackDefinition], "heavy": AttackDefinition, "abilities": {id: AttackDefinition}} or {}.
## Built from balance_v1.json; shared and cached until the tuning revision changes. Treat as read-only.
static func for_role(role: String) -> Dictionary:
	return Balance.attack_tables(role)


## Light attack for the given 0-based chain index. A role's table may hold more links than the
## default three (Queen: five); the fighter's current chain length (AbilityComponent.combo_length)
## decides how many are reachable.
static func light(role: String, index: int) -> AttackDefinition:
	var table: Array = for_role(role)["light"]
	return table[clampi(index, 0, table.size() - 1)]


static func heavy(role: String) -> AttackDefinition:
	return for_role(role)["heavy"]


## Attack executed by an attack-type ability, or null.
static func ability_attack(role: String, ability_id: String) -> AttackDefinition:
	return for_role(role)["abilities"].get(ability_id, null)
