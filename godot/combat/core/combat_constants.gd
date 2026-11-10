class_name CombatConstants
extends RefCounted
## Units, tick conventions and arena geometry for the combat module.
## Conventions come from docs/architecture/CONTRACTS.md: metres, +Y up, gameplay heading
## (sin(yaw), 0, cos(yaw)), fixed 60 Hz simulation ticks independent of display FPS.

const SCHEMA_VERSION := 1
const TICK_RATE := 60
const DT := 1.0 / 60.0
const COUNTDOWN_TICKS := 180
const DURATION_TICKS := 5400
## After this many ticks without an accepted input packet, held controls are neutralised.
const INPUT_NEUTRAL_AFTER_TICKS := 15
## Snapshots target 15 Hz.
const SNAPSHOT_EVERY_TICKS := 4
## Recent events are repeated in every snapshot so clients can de-duplicate by eventId.
const EVENT_HISTORY := 48
const MAX_EVENTS_PER_SNAPSHOT := 256

const ARENA_ID := "stone-v1"
const SPAWN_DISTANCE := 2.6
## Inner face of the wall colliders. Fighters stop against it via real engine collision.
const ARENA_WALL_RADIUS := 7.1
## Backstop only: a fighter centre is clamped to this radius if a collider were ever missed.
## It sits outside where the walls stop any fighter (7.1 - body radius), so it never fires normally.
const ARENA_WALK_RADIUS := 6.9
const BODY_HEIGHT := 1.8

const LAYER_WORLD := 1
const LAYER_FIGHTER := 2
## Only the outer wall is on this layer: the camera is pushed in by the wall, never by pillars.
const LAYER_CAMERA := 4

## Gameplay states. Names are the exact strings the CombatSnapshot schema permits.
enum State { IDLE, MOVING, ATTACKING, BLOCKING, PARRYING, DODGING, STAGGERED, ABILITY_CASTING, DEFEATED }
const STATE_NAMES: Array[String] = [
	"Idle", "Moving", "Attacking", "Blocking", "Parrying", "Dodging", "Staggered", "AbilityCasting", "Defeated",
]

## Light-attack chain length ("three-hit combo").
const COMBO_LENGTH := 3
## A press this many ticks before an action becomes available is remembered.
const INPUT_BUFFER_TICKS := 9
## A chain may still be continued this many ticks after a light attack ended.
const COMBO_GRACE_TICKS := 14
## Guard is not effective for the first ticks after raising it, so blocking needs anticipation.
const BLOCK_RAISE_TICKS := 3
const SPRINT_MIN_STAMINA := 4.0


static func state_name(state: int) -> String:
	return STATE_NAMES[state]


static func heading(yaw: float) -> Vector3:
	return Vector3(sin(yaw), 0.0, cos(yaw))


static func yaw_of(direction: Vector3) -> float:
	return atan2(direction.x, direction.z)


## Wraps into (-pi, pi]. Keeps +pi as +pi (the Black spawn facing) rather than -pi.
static func wrap_angle(angle: float) -> float:
	return angle - TAU * ceilf((angle - PI) / TAU)


static func angle_diff(from_angle: float, to_angle: float) -> float:
	return wrap_angle(to_angle - from_angle)


static func flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
