class_name FighterMovement
extends RefCounted
## Movement for one fighter: facing, walk / strafe / sprint, directional dodge, attack lunges and
## knock-back, applied to the fighter's CharacterBody3D with engine collision.
##
## Input is world-space (CONTRACTS.md: clients convert camera-relative input), so "strafing"
## is simply moving while locked-on: facing tracks the opponent and the move vector is free.
##
## Motion is integrated with an explicit fixed DT using move_and_collide + a small slide loop
## (not move_and_slide, which would use the engine frame delta). That keeps the result a
## function of ticks, callable from the server's own tick loop or from _physics_process.

const S := CombatConstants.State

const TURN_FREE := 0.30           # rad per tick (~1000 deg/s)
const TURN_LOCKED := 0.45
const TURN_ATTACK_STARTUP := 0.07
const TURN_ATTACK_STARTUP_LOCKED := 0.12
const ACCEL := 45.0               # m/s^2
const DECEL := 70.0
const KNOCK_DECAY := 0.8
const ATTACK_STEER_STARTUP := 0.35
const ATTACK_STEER_OTHER := 0.12
const PARRY_STEER := 0.25


func tick(f: FighterController, intent: FighterIntent, opponent: FighterController) -> void:
	var sm := f.sm
	_update_facing(f, intent, opponent)

	var wish := intent.move_vector()
	if wish.length() > 1.0:
		wish = wish.normalized()
	var base_speed: float = float(f.stats["moveSpeedMps"]) * f.ability.move_mult()
	var planar := f.carried_velocity
	var target := Vector3.ZERO
	var forced := false
	f.sprinting = false

	match sm.state:
		S.IDLE, S.MOVING:
			var speed := base_speed
			if intent.sprint and wish.length() > 0.5 and not f.stamina.exhausted \
					and f.stamina.current >= CombatConstants.SPRINT_MIN_STAMINA:
				speed *= float(f.profile["sprint_mult"])
				f.sprinting = true
				f.stamina.drain(float(f.profile["sprint_drain_per_tick"]))
			target = wish * speed
		S.BLOCKING:
			target = wish * base_speed * float(f.profile["block_move_mult"])
		S.PARRYING:
			target = wish * base_speed * PARRY_STEER
		S.ATTACKING, S.ABILITY_CASTING:
			if sm.attack != null:
				var forward := sm.attack.forward_speed(sm.state_ticks, sm.attack_total)
				if forward > 0.0:
					target = CombatConstants.heading(f.yaw) * forward
					forced = true
				else:
					var in_startup := sm.attack_phase() == AttackDefinition.Phase.STARTUP
					target = wish * base_speed * (ATTACK_STEER_STARTUP if in_startup else ATTACK_STEER_OTHER)
		S.DODGING:
			target = sm.dodge_dir * _dodge_speed(f)
			forced = true
		_:
			target = Vector3.ZERO

	if forced:
		planar = target
	else:
		var rate := ACCEL if target.length_squared() > 0.0001 else DECEL
		planar = planar.move_toward(target, rate * CombatConstants.DT)

	var motion := (planar + f.knock_velocity) * CombatConstants.DT
	f.knock_velocity *= KNOCK_DECAY
	if f.knock_velocity.length_squared() < 0.0004:
		f.knock_velocity = Vector3.ZERO

	var before := f.global_position
	_slide(f, motion)
	_separate(f, opponent)
	var moved := CombatConstants.flat(f.global_position - before)
	f.velocity = moved / CombatConstants.DT
	# When a wall or the other fighter stopped us, carry the real velocity so we do not
	# keep "pushing" into it and take a moment to reverse.
	var blocked := moved.length() < motion.length() - 0.0005
	if forced:
		f.carried_velocity = Vector3.ZERO  # authored motion (dodge, lunge) leaves no momentum behind
	elif blocked:
		f.carried_velocity = f.velocity
	else:
		f.carried_velocity = planar


func _update_facing(f: FighterController, intent: FighterIntent, opponent: FighterController) -> void:
	var sm := f.sm
	var rate := TURN_FREE
	var locked := intent.lock_target and opponent != null and opponent.health.is_alive()
	match sm.state:
		S.DODGING, S.STAGGERED, S.DEFEATED:
			return
		S.ATTACKING, S.ABILITY_CASTING:
			if sm.attack == null:
				return
			if sm.attack_phase() != AttackDefinition.Phase.STARTUP:
				return  # the swing is committed once it leaves startup
			rate = TURN_ATTACK_STARTUP_LOCKED if locked else TURN_ATTACK_STARTUP
		_:
			if locked:
				rate = TURN_LOCKED

	var desired := intent.yaw
	if locked:
		var to := CombatConstants.flat(opponent.global_position - f.global_position)
		if to.length_squared() > 0.0001:
			desired = CombatConstants.yaw_of(to)
	var diff := CombatConstants.angle_diff(f.yaw, desired)
	f.yaw = CombatConstants.wrap_angle(f.yaw + clampf(diff, -rate, rate))


## Ease-out dodge speed whose per-tick displacements sum exactly to dodge_distance.
func _dodge_speed(f: FighterController) -> float:
	var total: int = f.sm.dodge_total
	var distance: float = float(f.profile["dodge_distance"])
	var weight := 2.0 * (1.0 - (float(f.sm.state_ticks) + 0.5) / float(total))
	return distance / (float(total) * CombatConstants.DT) * maxf(weight, 0.0)


## Fighters are solid to each other: if the move left the bodies overlapping, push the mover out
## along the line between centres (which makes it slide around the other fighter). The correction
## itself goes through _slide so it can never push the mover into a wall. A defeated opponent is
## no longer solid.
func _separate(f: FighterController, opponent: FighterController) -> void:
	if opponent == null or not opponent.health.is_alive():
		return
	var min_distance := f.hurt_radius() + opponent.hurt_radius()
	var offset := CombatConstants.flat(f.global_position - opponent.global_position)
	var distance := offset.length()
	if distance >= min_distance:
		return
	var normal := offset / distance if distance > 0.0001 else -CombatConstants.heading(f.yaw)
	var target := opponent.global_position + normal * min_distance
	_slide(f, CombatConstants.flat(target - f.global_position))


func _slide(f: FighterController, motion: Vector3) -> void:
	var remaining := CombatConstants.flat(motion)
	for _i in 3:
		if remaining.length_squared() < 1e-10:
			break
		var collision := f.move_and_collide(remaining)
		if collision == null:
			break
		var normal := CombatConstants.flat(collision.get_normal())
		if normal.length_squared() < 1e-6:
			break
		remaining = CombatConstants.flat(collision.get_remainder()).slide(normal.normalized())
	# Defence in depth: never leave the arena even if a collider was missed.
	var pos := f.global_position
	pos.y = 0.0
	var radial := Vector2(pos.x, pos.z)
	if radial.length() > CombatConstants.ARENA_WALK_RADIUS:
		radial = radial.normalized() * CombatConstants.ARENA_WALK_RADIUS
		pos.x = radial.x
		pos.z = radial.y
	f.global_position = pos
