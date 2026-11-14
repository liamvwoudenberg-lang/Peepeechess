class_name HitboxController
extends RefCounted
## Hit detection for one fighter's current swing.
##
## The hitbox is a flat sector in front of the attacker (reach, arc) that exists only during the
## ACTIVE phase of the current AttackDefinition. The hurtbox is the target's body circle
## (profile radius). Detection is analytic rather than Area3D overlap so it is evaluated inside
## the same fixed tick as everything else, needs no physics callbacks, and is identical on a
## headless server. Each target can be hit at most once per swing.
##
## Reach is measured from the attacker's origin to the nearest point of the target's hurtbox.
## Line of sight is not modelled (pillars do not block hits) - a documented simplification.

var swing_serial: int = 0
var hit_anything: bool = false
var _already_hit: Dictionary = {}


func begin_swing() -> void:
	swing_serial += 1
	hit_anything = false
	_already_hit.clear()


func end_swing() -> void:
	_already_hit.clear()


## Pure geometry test; `target_radius` is the hurtbox circle.
static func in_sector(origin: Vector3, yaw: float, reach: float, arc_degrees: float,
		target: Vector3, target_radius: float) -> bool:
	var to := CombatConstants.flat(target - origin)
	var dist := to.length()
	if dist - target_radius > reach:
		return false
	if dist <= target_radius:
		return true
	var offset := absf(CombatConstants.angle_diff(yaw, CombatConstants.yaw_of(to)))
	var angular_half_size := asin(clampf(target_radius / dist, 0.0, 1.0))
	return offset - angular_half_size <= deg_to_rad(arc_degrees * 0.5)


## True exactly once per swing per target, on the first active tick the target is inside the hitbox.
func try_hit(attacker: FighterController, defender: FighterController) -> bool:
	var sm := attacker.sm
	if not sm.attack_active() or _already_hit.has(defender.player_id):
		return false
	if not defender.health.is_alive():
		return false
	var reach: float = float(attacker.stats["reachM"]) * sm.attack.reach_mult + defender.reach_bonus()
	if not in_sector(attacker.global_position, attacker.yaw, reach, sm.attack.arc_degrees,
			defender.global_position, defender.hit_radius()):
		return false
	_already_hit[defender.player_id] = true
	hit_anything = true
	return true


## Debug/presentation description of the live hitbox.
func shape(attacker: FighterController) -> Dictionary:
	var sm := attacker.sm
	if sm.attack == null:
		return {"active": false}
	return {
		"active": sm.attack_active(),
		"origin": attacker.global_position,
		"yaw": attacker.yaw,
		"reach": float(attacker.stats["reachM"]) * sm.attack.reach_mult,
		"arc_degrees": sm.attack.arc_degrees,
	}
