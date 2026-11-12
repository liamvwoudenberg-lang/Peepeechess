class_name FighterProfile
extends RefCounted
## Role tuning that the v1 FighterStats contract does not carry (poise, armour, guard, dodge,
## stamina economy, movement feel). The numbers live in res://combat/data/balance_v1.json and are served by
## the Balance loader (balance_data.gd); this class is the stable lookup API. The contract's stats
## (HP, stamina, damage, speed, reach, light/heavy/parry ticks, ability cooldown) always come
## from the BattleRequest, never from here.
##
## Pawn  - fast spear fighter: mobile and cheap to dodge, low poise/HP, no armour.
## Knight - armoured longsword fighter: high poise, damage reduction, strong parries and guard.
## Bishop - arcane spellblade: light armour and poise, evasive (Blink), decent parry riposte.
## Rook   - massive plate, warhammer and tower shield: huge poise, 25% armour, wide guard, weak parry, slow.
## Queen  - dual blades: lowest poise, fast cheap attacks, quick dodge, strong riposte.
## King   - EXPERIMENTAL (not part of the v1 contract): armoured, slow, strong parry; Royal Counter stance.

const Balance := preload("res://combat/data/balance_data.gd")


## Roles the v1 contract can send to the authority. The King is deliberately NOT here: the schema forbids it,
## so the default `CombatSimulation.start(request)` keeps refusing it. See `is_experimental_role`.
static func supports_role(role: String) -> bool:
	return role == "p" or role == "n" or role == "b" or role == "r" or role == "q"


## True for roles that have tuning but are outside the v1 contract (only the King today). They fight only
## when the caller opts in with `CombatSimulation.start(request, {"allow_experimental_roles": true})`.
static func is_experimental_role(role: String) -> bool:
	return role == "k" and Balance.has_role(role)


## A fresh copy of the role's tuning ({} for unknown roles).
static func for_role(role: String) -> Dictionary:
	return Balance.profile(role)
