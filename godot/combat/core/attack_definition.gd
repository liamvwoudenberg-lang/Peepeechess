class_name AttackDefinition
extends Resource
## One authored attack timeline. This is the single source of truth for an attack's frame data:
## the hitbox window, chain/cancel point, forward motion, armour frames AND the normalised
## pose time the visual rig plays are all derived from it, so animation and hit windows cannot
## drift apart. Windows are normalised (0..1) and resolved against the attack's total tick
## length, which comes from the server-approved FighterStats (lightTicks / heavyTicks) so
## balance stays a data change, not a code change.
##
## Honest note on "animation-driven": a headless authority has no AnimationPlayer, so the
## windows live in this data and the presentation scrubs its procedural poses with the same
## numbers (FighterVisual). Imported animation clips should be authored to these markers.

enum Kind { LIGHT, HEAVY, ABILITY }
enum Phase { STARTUP, ACTIVE, RECOVERY }

@export var id: String = ""
@export var kind: Kind = Kind.LIGHT
@export var combo_index: int = 0
## Presentation key understood by FighterVisual (pose set). Never used by the simulation.
@export var animation: String = "slash"

## Total length = round(stats.lightTicks|heavyTicks * ticks_scale), or absolute_ticks if > 0.
@export var ticks_scale: float = 1.0
@export var absolute_ticks: int = 0

@export_range(0.0, 1.0) var startup_end: float = 0.35
@export_range(0.0, 1.0) var active_end: float = 0.55
## From this point a buffered follow-up (chain, dodge, parry) may cancel the recovery.
@export_range(0.0, 1.0) var cancel_from: float = 0.8

@export var damage_mult: float = 1.0
@export var reach_mult: float = 1.0
@export var arc_degrees: float = 60.0
@export var stamina_cost: float = 10.0
## Poise damage breaks the target's stance into a Staggered state; smaller hits only flinch.
@export var poise_damage: float = 10.0
@export var hitstun_ticks: int = 12
## Multiplier on the stamina a blocker pays to absorb this attack.
@export var guard_cost_mult: float = 1.0
@export var knockback_m: float = 0.3

@export var forward_motion_m: float = 0.0
@export_range(0.0, 1.0) var motion_start: float = 0.0
@export_range(0.0, 1.0) var motion_end: float = 0.0
## Armour (no flinch/stagger from lower poise hits) between these normalised times; -1 = none.
@export var armor_start: float = -1.0
@export var armor_end: float = -1.0


## Total attack length in ticks. attack_speed_mult > 1 shortens it (e.g. Last Stand).
func total_ticks(stats: Dictionary, attack_speed_mult: float = 1.0) -> int:
	var base: int = absolute_ticks
	if base <= 0:
		var stat_ticks: int = int(stats["lightTicks"]) if kind == Kind.LIGHT else int(stats["heavyTicks"])
		base = roundi(float(stat_ticks) * ticks_scale)
	return maxi(6, ceili(float(base) / attack_speed_mult - 0.0001))


## [first_active_tick, end_tick) of the hit window for an attack of `total` ticks.
func active_window(total: int) -> Vector2i:
	var first: int = clampi(roundi(startup_end * float(total)), 1, total - 2)
	var last: int = clampi(roundi(active_end * float(total)), first + 1, total - 1)
	return Vector2i(first, last)


func phase_at(tick: int, total: int) -> int:
	var window := active_window(total)
	if tick < window.x:
		return Phase.STARTUP
	if tick < window.y:
		return Phase.ACTIVE
	return Phase.RECOVERY


## First tick at which a buffered follow-up may cancel into the next action.
func cancel_tick(total: int) -> int:
	return clampi(roundi(cancel_from * float(total)), active_window(total).y, total)


## Forward speed (m/s along the facing) at the given tick; 0 outside the motion window.
func forward_speed(tick: int, total: int) -> float:
	if forward_motion_m <= 0.0 or motion_end <= motion_start:
		return 0.0
	var first: int = roundi(motion_start * float(total))
	var last: int = maxi(first + 1, roundi(motion_end * float(total)))
	if tick < first or tick >= last:
		return 0.0
	return forward_motion_m / (float(last - first) * CombatConstants.DT)


func has_armor_at(tick: int, total: int) -> bool:
	if armor_start < 0.0:
		return false
	return tick >= roundi(armor_start * float(total)) and tick < roundi(armor_end * float(total))
