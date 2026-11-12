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

## Defaults == the Pawn/Knight movement profile (balance_v1.json "accel", "turn_free", ...). Every fighter now reads its
## own profile keys; these constants stay as the documented baseline and for the client predictor, which should read
## the profile too (FighterProfile.for_role(role)) to predict Bishop/Rook/Queen/King exactly.
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
	if sm.state == S.ABILITY_CASTING and sm.cast_kind == "blink" and sm.attack == null \
			and sm.state_ticks == int(f.ability.definition["blink_tick"]):
		_blink(f, opponent)

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
			target = wish * base_speed * float(f.profile["parry_steer"])
		S.ATTACKING, S.ABILITY_CASTING:
			if sm.attack == null:
				if sm.counter_stance():
					# Royal Counter: the King plants himself - slow shuffle only while the stance holds.
					target = wish * base_speed * float(f.ability.definition["stance_move_mult"])
			else:
				var forward := sm.attack.forward_speed(sm.state_ticks, sm.attack_total)
				if forward > 0.0:
					target = CombatConstants.heading(f.yaw) * forward
					forced = true
				else:
					var in_startup := sm.attack_phase() == AttackDefinition.Phase.STARTUP
					target = wish * base_speed * float(f.profile["attack_steer_startup" if in_startup else "attack_steer_other"])
		S.DODGING:
			target = sm.dodge_dir * _dodge_speed(f)
			forced = true
		_:
			target = Vector3.ZERO

	if forced:
		planar = target
	else:
		var rate := float(f.profile["accel" if target.length_squared() > 0.0001 else "decel"])
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
	var rate := float(f.profile["turn_free"])
	var locked := intent.lock_target and opponent != null and opponent.health.is_alive()
	match sm.state:
		S.DODGING, S.STAGGERED, S.DEFEATED:
			return
		S.ATTACKING, S.ABILITY_CASTING:
			if sm.attack == null:
				if not sm.counter_stance():
					return
				rate *= float(f.ability.definition["stance_turn_mult"])  # slow aim adjustment during the stance
			elif sm.attack_phase() != AttackDefinition.Phase.STARTUP:
				return  # the swing is committed once it leaves startup
			else:
				rate = float(f.profile["turn_attack_startup_locked" if locked else "turn_attack_startup"])
		_:
			if locked:
				rate = float(f.profile["turn_locked"])

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


## Bishop's Blink: instant displacement along the direction fixed at cast start. The path is cut short
## by the opponent's body (never through or inside them), then by engine collision with walls and
## pillars (move_and_collide stops at first contact), then the arena backstop. Teleporting leaves no
## momentum and no render smear (prev_position follows), and the reported velocity stays 0.
func _blink(f: FighterController, opponent: FighterController) -> void:
	var distance: float = float(f.ability.definition["blink_distance"])
	var dir := CombatConstants.flat(f.sm.blink_dir).normalized()
	if dir == Vector3.ZERO:
		return
	if opponent != null and opponent.health.is_alive():
		var reach_circle := f.hurt_radius() + opponent.hurt_radius() + 0.02
		var rel := CombatConstants.flat(f.global_position - opponent.global_position)
		var b := dir.dot(rel)
		var c := rel.length_squared() - reach_circle * reach_circle
		var disc := b * b - c
		if disc >= 0.0:
			var t := -b - sqrt(disc)
			if t >= 0.0 and t < distance:
				distance = maxf(0.0, t)
	if distance > 0.0:
		f.move_and_collide(dir * distance)
	var pos := f.global_position
	pos.y = 0.0
	var radial := Vector2(pos.x, pos.z)
	if radial.length() > CombatConstants.ARENA_WALK_RADIUS:
		radial = radial.normalized() * CombatConstants.ARENA_WALK_RADIUS
		pos.x = radial.x
		pos.z = radial.y
	f.global_position = pos
	f.carried_velocity = Vector3.ZERO
	f.knock_velocity = Vector3.ZERO
	f.prev_position = f.global_position


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
