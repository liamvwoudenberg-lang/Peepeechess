class_name HitWeight
extends RefCounted
## How HEAVY a landed blow should feel. Pure data + maths (no nodes, no simulation access): CombatVfx asks it for the hitstop,
## camera shake / punch-in / FOV kick, spark and sprite scale of one impact. Light < heavy (charged) < ability < finisher.
## Presentation only: nothing here reads or changes simulation state, time or the network.

enum Tier { LIGHT, HEAVY, ABILITY, FINISHER }

## hitstop = display frames the two models freeze (CombatVfx clamps to 5), shake = trauma multiplier, punch = metres the camera is
## pushed along the blow, fov = degrees of zoom-in (negative = in), sparks / sprite = size multipliers, ring = shockwave ring.
const PROFILES := [
	{"name": "light", "hitstop": 2, "shake": 1.0, "punch": 0.05, "fov": 0.0, "sparks": 1.0, "sprite": 1.0, "ring": false, "camera": "hit"},
	{"name": "heavy", "hitstop": 3, "shake": 1.7, "punch": 0.14, "fov": -2.5, "sparks": 1.6, "sprite": 1.35, "ring": true, "camera": "heavy_hit"},
	{"name": "ability", "hitstop": 4, "shake": 2.1, "punch": 0.18, "fov": -4.0, "sparks": 2.0, "sprite": 1.6, "ring": true, "camera": "ability_hit"},
	{"name": "finisher", "hitstop": 5, "shake": 2.6, "punch": 0.24, "fov": -7.0, "sparks": 2.6, "sprite": 2.0, "ring": true, "camera": "final"},
]


## `kind` is AttackDefinition.Kind (LIGHT / HEAVY / ABILITY), -1 when unknown. A knockout is always a finisher; with no attack
## information the blow's felt damage decides (20+ = heavy, the old threshold).
static func tier_for(kind: int, felt_damage: int, final_blow: bool) -> int:
	if final_blow:
		return Tier.FINISHER
	match kind:
		AttackDefinition.Kind.ABILITY:
			return Tier.ABILITY
		AttackDefinition.Kind.HEAVY:
			return Tier.HEAVY
		AttackDefinition.Kind.LIGHT:
			return Tier.LIGHT
	return Tier.HEAVY if felt_damage >= 20 else Tier.LIGHT


static func profile(tier: int) -> Dictionary:
	return PROFILES[clampi(tier, 0, PROFILES.size() - 1)]


## Display frames of hitstop for a blow of this tier and felt damage: stronger tiers freeze longer, a big number adds a frame.
static func hitstop_frames(tier: int, felt_damage: int) -> int:
	return clampi(int(profile(tier)["hitstop"]) + (1 if felt_damage >= 40 else 0), 1, 5)


## Camera trauma for a blow: the tier's multiplier on a base that grows with the felt damage (0.08 .. 0.28).
static func shake_amount(tier: int, felt_damage: int) -> float:
	var power := clampf(float(felt_damage) / 40.0, 0.2, 1.0)
	return (0.08 + 0.2 * power) * float(profile(tier)["shake"])
