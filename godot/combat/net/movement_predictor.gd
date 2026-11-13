extends RefCounted
## Pure-math client-side predictor for a fighter's FREE-STATE movement (Idle / Moving / Blocking).
## It mirrors FighterMovement.tick for those states using the same constants, so with identical
## inputs it reproduces the server's position to well under a centimetre in open space. It has no
## physics dependency; the world is the same circular 24-sided wall, four pillars and the opponent
## body the server resolves with engine collision + analytic separation.
##
## It deliberately does NOT model attacks, dodges, parries, stagger, abilities, knock-back or
## buff multipliers: when the authoritative state is anything but free the client stops predicting
## and shows server state (see CombatNetClient).
##
## Per-role movement feel (accel/decel/turn rates, sprint, block slow, radius) is read from the same tuning the server
## fighter uses (FighterProfile.for_role(role), i.e. balance_v1.json), including the experimental King, so the model is
## exact for every role. Buff abilities that change walking speed (Last Stand 1.3x, Royal Fury 1.1x, Fortress Guard 0.7x)
## are modelled: the remaining buff time is recovered from the snapshot's `cooldownTicks` (buff and cooldown both start at
## the cast and tick down together), so `buff_remaining = cooldownTicks - (cooldown_total - buff_ticks)`.
##
## State dictionary: {pos: Vector3, vel: Vector3 (carried planar velocity), yaw: float,
##                    stamina: float, exhausted: bool, buff: int (remaining buff ticks)}

const S := CombatConstants.State
const WALL_FACES := 24
const PILLAR_RADIUS := 0.55
const PILLARS: Array[Vector2] = [Vector2(3.4, 3.4), Vector2(-3.4, 3.4), Vector2(3.4, -3.4), Vector2(-3.4, -3.4)]


## `stamina_cost_mult`: the seat's stamina cost multiplier (the attacker's advantage, see BALANCE.md; 1.0 = neutral). The server
## scales every stamina cost by it, so the predicted sprint drain must be scaled the same way.
static func params_for(role: String, stats: Dictionary, stamina_cost_mult: float = 1.0) -> Dictionary:
	var profile := FighterProfile.for_role(role)
	return {
		"speed": float(stats["moveSpeedMps"]),
		"sprint_mult": float(profile["sprint_mult"]),
		"block_move_mult": float(profile["block_move_mult"]),
		"drain": float(profile["sprint_drain_per_tick"]) * stamina_cost_mult,
		"radius": float(profile["radius"]),
		# per-role movement profile (balance_v1.json); Pawn/Knight equal the FighterMovement constants
		"accel": float(profile.get("accel", FighterMovement.ACCEL)),
		"decel": float(profile.get("decel", FighterMovement.DECEL)),
		"turn_free": float(profile.get("turn_free", FighterMovement.TURN_FREE)),
		"turn_locked": float(profile.get("turn_locked", FighterMovement.TURN_LOCKED)),
	}.merged(_buff_params(stats))


## Speed multiplier / duration of the role's buff ability (1.0 / 0 when the ability is not a movement buff).
static func _buff_params(stats: Dictionary) -> Dictionary:
	var definition: Dictionary = AbilityComponent.DEFINITIONS.get(String(stats.get("abilityId", "")), {})
	var buff_ticks := int(definition.get("buff_ticks", 0)) if String(definition.get("kind", "")) == "buff" else 0
	return {
		"buff_move_mult": float(definition.get("move_mult", 1.0)) if buff_ticks > 0 else 1.0,
		"buff_ticks": buff_ticks,
		"cooldown_total": int(stats.get("cooldownTicks", 0)),
	}


## Remaining buff ticks implied by a snapshot's `cooldownTicks` (0 when no buff is running).
static func buff_remaining(params: Dictionary, cooldown_ticks: int) -> int:
	var buff_ticks: int = int(params.get("buff_ticks", 0))
	if buff_ticks <= 0 or cooldown_ticks <= 0:
		return 0
	return maxi(0, cooldown_ticks - (int(params["cooldown_total"]) - buff_ticks))


static func initial(pos: Vector3, yaw: float, stamina: float, buff: int = 0) -> Dictionary:
	return {"pos": Vector3(pos.x, 0.0, pos.z), "vel": Vector3.ZERO, "yaw": yaw, "stamina": stamina, "exhausted": false, "buff": buff}


## One 60 Hz tick. `intent`: {move_x, move_z, yaw, lock, sprint, block}. `opp`: {pos: Vector3, radius: float,
## alive: bool}.
static func step(state: Dictionary, intent: Dictionary, params: Dictionary, opp: Dictionary) -> Dictionary:
	var pos: Vector3 = state["pos"]
	var yaw: float = state["yaw"]
	var stamina: float = state["stamina"]
	var exhausted: bool = state["exhausted"]
	var planar: Vector3 = state["vel"]
	var radius: float = params["radius"]

	# facing (FighterMovement._update_facing for free states)
	var locked: bool = bool(intent["lock"]) and bool(opp.get("alive", true)) and opp.has("pos")
	var rate: float = float(params.get("turn_locked", FighterMovement.TURN_LOCKED)) if locked \
			else float(params.get("turn_free", FighterMovement.TURN_FREE))
	var desired: float = float(intent["yaw"])
	if locked:
		var to: Vector3 = CombatConstants.flat(opp["pos"] - pos)
		if to.length_squared() > 0.0001:
			desired = CombatConstants.yaw_of(to)
	yaw = CombatConstants.wrap_angle(yaw + clampf(CombatConstants.angle_diff(yaw, desired), -rate, rate))

	var wish := Vector3(float(intent["move_x"]), 0.0, float(intent["move_z"]))
	if wish.length() > 1.0:
		wish = wish.normalized()
	var buff: int = int(state.get("buff", 0))
	var speed: float = params["speed"]
	if buff > 0:
		speed *= float(params.get("buff_move_mult", 1.0))
	var target := Vector3.ZERO
	if bool(intent["block"]) and not exhausted:
		target = wish * speed * float(params["block_move_mult"])
	else:
		if bool(intent["sprint"]) and wish.length() > 0.5 and not exhausted and stamina >= CombatConstants.SPRINT_MIN_STAMINA:
			speed *= float(params["sprint_mult"])
			stamina = maxf(0.0, stamina - float(params["drain"]))
			if stamina <= 0.0:
				exhausted = true
		target = wish * speed
	var accel: float = float(params.get("accel", FighterMovement.ACCEL)) if target.length_squared() > 0.0001 \
			else float(params.get("decel", FighterMovement.DECEL))
	planar = planar.move_toward(target, accel * CombatConstants.DT)

	var motion := planar * CombatConstants.DT
	var before := pos
	pos = _world(pos + motion, radius)
	if opp.has("pos") and bool(opp.get("alive", true)):
		pos = _separate(pos, opp["pos"], radius + float(opp.get("radius", 0.4)))
		pos = _world(pos, radius)
	var moved := CombatConstants.flat(pos - before)
	var velocity := moved / CombatConstants.DT
	var blocked := moved.length() < motion.length() - 0.0005
	return {"pos": pos, "vel": velocity if blocked else planar, "yaw": yaw, "stamina": stamina,
			"exhausted": exhausted, "velocity": velocity, "buff": maxi(0, buff - 1)}


## Pushes a fighter centre out of the 24 wall half-planes and the pillar discs (sliding along them).
static func _world(p: Vector3, radius: float) -> Vector3:
	var limit := CombatConstants.ARENA_WALL_RADIUS - radius
	for _pass in 2:
		for i in WALL_FACES:
			var a := TAU * float(i) / float(WALL_FACES)
			var n := Vector3(sin(a), 0.0, cos(a))
			var excess := p.dot(n) - limit
			if excess > 0.0:
				p -= n * excess
		for pillar in PILLARS:
			var c := Vector3(pillar.x, 0.0, pillar.y)
			var d := p - c
			var min_d := PILLAR_RADIUS + radius
			if d.length() < min_d:
				p = c + (d.normalized() if d.length() > 0.0001 else Vector3(0, 0, 1)) * min_d
	p.y = 0.0
	return p


static func _separate(p: Vector3, other: Vector3, min_distance: float) -> Vector3:
	var offset := CombatConstants.flat(p - other)
	var d := offset.length()
	if d >= min_distance:
		return p
	var n := offset / d if d > 0.0001 else Vector3(0, 0, 1)
	return other + n * min_distance
