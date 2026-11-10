class_name FighterController
extends CharacterBody3D
## One fighter: a CharacterBody3D that owns the reusable combat components.
##
##   HealthComponent, StaminaComponent, AbilityComponent, HitboxController,
##   FighterMovement, CombatStateMachine
##
## It holds no input handling and makes no decisions about other fighters: the CombatSimulation
## feeds it validated FighterIntent each tick and resolves hits between fighters. Everything
## here is headless-safe (no camera, audio, mesh or UI dependency).

const S := CombatConstants.State

var player_id: String = ""
var piece_id: String = ""
var character_id: String = ""
var color: String = "w"
var role: String = "p"
var stats: Dictionary = {}
var profile: Dictionary = {}
## Unmodified role tuning; `profile` is this plus any active buff (Fortress Guard) applied each tick.
var base_profile: Dictionary = {}
var _poise_scale: float = 1.0

var health := HealthComponent.new()
var stamina := StaminaComponent.new()
var ability := AbilityComponent.new()
var hitbox := HitboxController.new()
var movement := FighterMovement.new()
var sm := CombatStateMachine.new()

var yaw: float = 0.0
var sprinting: bool = false
var carried_velocity: Vector3 = Vector3.ZERO
var knock_velocity: Vector3 = Vector3.ZERO
var poise: float = 0.0
var poise_delay: int = 0
var hit_react_ticks: int = 0
var last_input_sequence: int = 0
var local_tick: int = 0
## Previous-tick transform, so rendering can interpolate between 60 Hz ticks.
var prev_position: Vector3 = Vector3.ZERO
var prev_yaw: float = 0.0

var _pending_events: Array[String] = []


## Returns "" on success or a reason string. `combatant` is a contract Combatant dictionary.
func setup(combatant: Dictionary, spawn_position: Vector3, spawn_yaw: float) -> String:
	player_id = combatant["playerId"]
	piece_id = combatant["pieceId"]
	character_id = combatant["characterId"]
	color = combatant["color"]
	role = combatant["role"]
	stats = combatant["stats"]
	profile = FighterProfile.for_role(role)
	if profile.is_empty() or not AttackLibrary.supports_role(role) or not FighterProfile.supports_role(role):
		return "role '%s' is not implemented in the combat module" % role

	health.setup(float(stats["maxHp"]))
	stamina.setup(float(stats["maxStamina"]), float(profile["stamina_regen_per_tick"]),
			int(profile["stamina_regen_delay"]))
	if not ability.setup(String(stats["abilityId"]), int(stats["cooldownTicks"])):
		return "ability '%s' is not implemented" % String(stats["abilityId"])
	if String(ability.definition["role"]) != role:
		return "ability '%s' does not belong to role '%s'" % [ability.ability_id, role]
	base_profile = profile.duplicate()
	poise = float(profile["poise"])
	sm.bind(self)

	name = "Fighter_" + color
	# Engine collision is used for the static world only. Fighter-vs-fighter contact is resolved
	# analytically in FighterMovement: kinematic bodies only update their collision transform
	# when the engine steps physics, which an authority stepping ticks itself cannot rely on.
	collision_layer = CombatConstants.LAYER_FIGHTER
	collision_mask = CombatConstants.LAYER_WORLD
	var shape := CapsuleShape3D.new()
	shape.radius = hurt_radius()
	shape.height = CombatConstants.BODY_HEIGHT
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = Vector3(0.0, CombatConstants.BODY_HEIGHT * 0.5, 0.0)
	add_child(collider)

	teleport(spawn_position, spawn_yaw)
	return ""


func hurt_radius() -> float:
	return float(profile["radius"])


## Moves the fighter instantly (spawning, tests). Not used during normal play.
func teleport(position_xz: Vector3, facing_yaw: float = NAN) -> void:
	global_position = Vector3(position_xz.x, 0.0, position_xz.z)
	prev_position = global_position
	if not is_nan(facing_yaw):
		yaw = facing_yaw
		prev_yaw = yaw


func heading() -> Vector3:
	return CombatConstants.heading(yaw)


func is_alive() -> bool:
	return health.is_alive()


## True if `point` lies within a cone of `arc_degrees` centred on this fighter's facing.
func faces_toward(point: Vector3, arc_degrees: float) -> bool:
	var to := CombatConstants.flat(point - global_position)
	if to.length_squared() < 0.0001:
		return true
	return absf(CombatConstants.angle_diff(yaw, CombatConstants.yaw_of(to))) <= deg_to_rad(arc_degrees * 0.5)


## Damage this fighter deals with `def`, before the defender's armour.
func compute_damage(def: AttackDefinition) -> int:
	var damage := float(stats["baseDamage"]) * def.damage_mult * ability.damage_mult()
	if sm.riposte_ticks > 0:
		damage *= float(profile["riposte_mult"])
	return maxi(1, roundi(damage))


## Current light-chain length (3, or longer while Royal Fury is active).
func combo_limit() -> int:
	return ability.combo_length()


## Applies buff-driven changes to the role tuning before this tick's decisions and hit resolution.
## Fortress Guard: blocking costs nothing and can never exhaust the guard, and the poise pool is
## scaled (the current pool scales with it, so the buff is felt immediately and fades cleanly).
func _apply_buff_modifiers() -> void:
	profile["block_cost_mult"] = float(base_profile["block_cost_mult"]) * ability.guard_cost_mult()
	var scale := ability.poise_mult()
	if not is_equal_approx(scale, _poise_scale):
		poise = poise * scale / _poise_scale
		_poise_scale = scale
	profile["poise"] = float(base_profile["poise"]) * scale
	poise = minf(poise, float(profile["poise"]))
	if ability.guard_unbreakable():
		# Never exhausted while the buff lasts, so the guard cannot collapse for lack of stamina.
		stamina.exhausted = false
		stamina.current = maxf(stamina.current, 0.5)


func queue_event(type: String) -> void:
	_pending_events.append(type)


func drain_events() -> Array[String]:
	var out := _pending_events.duplicate()
	_pending_events.clear()
	return out


func add_knockback(direction: Vector3, distance: float) -> void:
	var dir := CombatConstants.flat(direction)
	if dir.length_squared() < 0.0001 or distance <= 0.0:
		return
	# Decaying velocity whose total displacement over its lifetime equals `distance`.
	knock_velocity += dir.normalized() * distance / (CombatConstants.DT * (1.0 / (1.0 - FighterMovement.KNOCK_DECAY)))


# ---- tick phases, driven by CombatSimulation ------------------------------------------------
func think(intent: FighterIntent) -> void:
	prev_position = global_position
	prev_yaw = yaw
	stamina.regen_multiplier = ability.regen_mult()
	_apply_buff_modifiers()
	sm.tick(intent)


func move(intent: FighterIntent, opponent: FighterController) -> void:
	movement.tick(self, intent, opponent)


func end_tick() -> void:
	sm.end_tick()
	local_tick += 1
	ability.tick()
	if hit_react_ticks > 0:
		hit_react_ticks -= 1
	# Stamina regenerates unless guarding or sprinting.
	stamina.tick(sm.state != S.BLOCKING and not sprinting)
	if poise_delay > 0:
		poise_delay -= 1
	elif poise < float(profile["poise"]):
		poise = minf(float(profile["poise"]), poise + float(profile["poise_regen_per_tick"]))


func snapshot() -> Dictionary:
	var p := global_position
	return {
		"playerId": player_id,
		"pieceId": piece_id,
		"position": {"x": snappedf(p.x, 0.0001), "y": 0.0, "z": snappedf(p.z, 0.0001)},
		"velocity": {"x": snappedf(velocity.x, 0.0001), "y": 0.0, "z": snappedf(velocity.z, 0.0001)},
		"yawRadians": clampf(snappedf(CombatConstants.wrap_angle(yaw), 0.0001), -PI, PI),
		"hp": health.current,
		"stamina": snappedf(stamina.current, 0.01),
		"state": CombatConstants.state_name(sm.state),
		"stateTicks": sm.state_ticks,
		"cooldownTicks": ability.cooldown_remaining,
		"lastInputSequence": last_input_sequence,
	}
