class_name ThirdPersonCamera
extends Node3D
## Third-person camera: smooth follow, free orbit, wall/pillar collision, and target lock-on.
## It is presentation only: it reads the fighters' interpolated positions and never feeds back
## into the simulation. `view_heading()` is what the input layer uses to turn camera-relative
## stick/WASD input into the world-space move vector the CombatInput contract requires.

const FOLLOW_HEIGHT := 1.55
const MIN_DISTANCE := 2.6
const MAX_DISTANCE := 7.5
const COLLISION_MARGIN := 0.25
const BASE_FOV := 68.0
## Frame-rate independent smoothing rates (1/s). Higher = snappier.
const PIVOT_RATE := 14.0
const LOCK_RATE := 9.0
const LOCK_RATE_BOOST := 20.0     # briefly after (re)locking so the camera snaps to the target
const LOOKAHEAD_S := 0.10         # seconds of own velocity added to the pivot
const MAX_TRAUMA := 0.8
## The camera never enters an arena pillar (it used to sit inside one and fill the screen with stone).
const PILLAR_CAMERA_MARGIN := 0.45
const PILLAR_TOP := 5.0

## Reduce-motion accessibility option: no shake, FOV kicks or finish orbit (set by CombatVfx.configure_from_args).
static var reduce_motion: bool = false

var target: FighterController
var opponent: FighterController
var locked: bool = true
var yaw: float = 0.0           # gameplay heading the camera looks along (sin, cos convention)
var pitch: float = 0.32        # elevation above horizontal, radians
var distance: float = 4.8
var camera: Camera3D
## false when the camera is mounted inside a larger 3D world that owns the active camera (bind() then leaves `current` alone).
var make_current: bool = true
var shake: float = 0.0          # trauma 0..MAX_TRAUMA (kept as `shake` for older callers)
var _pivot: Vector3 = Vector3.ZERO
var _spring: float = 4.8
var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
var _clock: float = 0.0
var _look_ahead: Vector3 = Vector3.ZERO
var _fov_kick: float = 0.0
var _fov_kick_target: float = 0.0
var _fov_hold: float = 0.0
var _punch: Vector3 = Vector3.ZERO     # decaying positional impulse (world space)
var _lock_boost: float = 0.0
var _intro_t: float = -1.0             # >= 0 while the opening push-in runs (a slow glide from far to the normal framing)
const INTRO_SECONDS := 3.0
const INTRO_EXTRA_DISTANCE := 3.2
var _finish_t: float = -1.0            # >= 0 once the battle is over
var _finish_target: FighterController = null


func _init() -> void:
	camera = Camera3D.new()
	camera.fov = 68.0
	camera.near = 0.1
	camera.far = 80.0
	add_child(camera)
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 1.0
	_noise.seed = 7


func bind(p_target: FighterController, p_opponent: FighterController) -> void:
	target = p_target
	opponent = p_opponent
	yaw = target.yaw
	_intro_t = 0.0
	_pivot = _fighter_position(target) + Vector3(0.0, FOLLOW_HEIGHT, 0.0)
	if make_current:
		camera.current = true


func view_heading() -> float:
	return yaw


func add_look(delta_yaw: float, delta_pitch: float) -> void:
	if locked:
		return
	yaw = CombatConstants.wrap_angle(yaw - delta_yaw)
	pitch = clampf(pitch + delta_pitch, -0.15, 1.1)


func toggle_lock() -> void:
	locked = not locked
	if not locked and target != null:
		yaw = target.yaw
	elif locked:
		_lock_boost = 0.3  # snap to the target quickly, then settle back to the smooth rate


func zoom(amount: float) -> void:
	distance = clampf(distance + amount, MIN_DISTANCE, MAX_DISTANCE)


func add_shake(amount: float) -> void:
	if reduce_motion:
		return
	shake = minf(shake + amount, MAX_TRAUMA)


## Impact feedback by event kind (see CombatVfx): trauma shake, a tiny directional punch and a short FOV kick.
## Everything is small and decays quickly; none of it touches the simulation or the input heading.
func feedback(kind: String, amount: float, dir: Vector3 = Vector3.ZERO) -> void:
	if reduce_motion:
		return
	match kind:
		"hit":
			add_shake(amount * 0.8)
			punch(dir, 0.05)
		"heavy_hit":
			add_shake(amount)
			punch(dir, 0.12)
			kick_fov(-2.0, 0.05)
		"block":
			add_shake(amount * 0.6)
			punch(dir, 0.04)
		"parry":
			add_shake(amount * 0.5)
			punch(dir, 0.1)
			kick_fov(-6.0, 0.28)   # a slow zoom-in on the perfect parry: held long enough to read, then released
		"final":
			add_shake(amount)
			punch(dir, 0.2)
			kick_fov(-7.0, 0.5)    # the knockout blow
		"guardbreak":
			add_shake(amount)
			punch(dir, 0.15)
			kick_fov(-3.0, 0.06)
		"dash":
			kick_fov(5.0, 0.05)
		"ability":
			add_shake(amount)
			kick_fov(2.5, 0.08)


## Pushes the camera along `dir` (flat world direction) by `amount` metres; it eases back at once.
func punch(dir: Vector3, amount: float) -> void:
	if reduce_motion:
		return
	_punch += CombatConstants.flat(dir).normalized() * amount if dir.length() > 0.01 else Vector3.ZERO


## FOV impulse in degrees, held `hold` seconds, then released with an ease.
func kick_fov(delta_deg: float, hold: float = 0.0) -> void:
	if reduce_motion:
		return
	_fov_kick_target = clampf(delta_deg, -8.0, 8.0)
	_fov_hold = hold


## Battle over: slowly orbit and push in on the winner (null: both down / draw -> keep the player's framing).
func set_finish(winner: FighterController) -> void:
	_finish_t = 0.0
	_finish_target = winner


## Pushes a camera position out of the pillar cylinders (continuous, so no popping while a fighter circles one).
static func _clear_of_pillars(p: Vector3) -> Vector3:
	if p.y > PILLAR_TOP:
		return p
	var min_d: float = StoneArena.PILLAR_RADIUS + PILLAR_CAMERA_MARGIN
	for c in StoneArena.PILLAR_POSITIONS:
		var dx := p.x - c.x
		var dz := p.z - c.z
		var d := sqrt(dx * dx + dz * dz)
		if d < min_d:
			if d < 0.001:
				dx = 1.0
				dz = 0.0
				d = 1.0
			p.x = c.x + dx / d * min_d
			p.z = c.z + dz / d * min_d
	return p


static func _fighter_position(f: FighterController) -> Vector3:
	return f.prev_position.lerp(f.global_position, Engine.get_physics_interpolation_fraction())


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return
	_clock += delta
	_lock_boost = maxf(0.0, _lock_boost - delta)
	var own := _fighter_position(target)
	var foe_alive := opponent != null and is_instance_valid(opponent) and opponent.is_inside_tree() and opponent.health.is_alive()
	var focus := target
	var finishing := _finish_t >= 0.0 and not reduce_motion
	if _finish_t >= 0.0:
		_finish_t += delta
		if _finish_target != null and is_instance_valid(_finish_target) and _finish_target.is_inside_tree():
			focus = _finish_target
	var focus_pos := _fighter_position(focus)
	var desired_pivot := focus_pos + Vector3(0.0, FOLLOW_HEIGHT, 0.0)
	var want_distance := distance
	if finishing:
		# Slow orbit around the winner, easing closer.
		yaw = CombatConstants.wrap_angle(yaw + delta * 0.18)
		want_distance = lerpf(distance, MIN_DISTANCE + 0.6, clampf(_finish_t / 2.5, 0.0, 1.0))
		desired_pivot = focus_pos + Vector3(0.0, 1.35, 0.0)
	elif locked and foe_alive and _finish_t < 0.0:
		var foe := _fighter_position(opponent)
		var to_foe := CombatConstants.flat(foe - own)
		if to_foe.length() > 0.05:
			var heading := CombatConstants.yaw_of(to_foe)
			var rate := LOCK_RATE_BOOST if _lock_boost > 0.0 else LOCK_RATE
			yaw = lerp_angle(yaw, heading, 1.0 - exp(-rate * delta))
			# Shift the pivot toward the opponent and pull back when they are far, so both stay framed.
			desired_pivot += to_foe * 0.28
			want_distance = clampf(distance + to_foe.length() * 0.18, MIN_DISTANCE, MAX_DISTANCE)
	# Velocity look-ahead: the view leads the fighter slightly so there is more room in the direction of travel.
	if not reduce_motion and _finish_t < 0.0:
		var flat_v := CombatConstants.flat(target.velocity)
		_look_ahead = _look_ahead.lerp(flat_v * LOOKAHEAD_S, 1.0 - exp(-6.0 * delta))
		desired_pivot += _look_ahead
	_pivot = _pivot.lerp(desired_pivot, 1.0 - exp(-PIVOT_RATE * delta))

	if _intro_t >= 0.0 and not reduce_motion:
		_intro_t += delta
		var k := clampf(_intro_t / INTRO_SECONDS, 0.0, 1.0)
		want_distance += INTRO_EXTRA_DISTANCE * (1.0 - k * k * (3.0 - 2.0 * k))   # smoothstep: eases to the normal distance
		if k >= 1.0:
			_intro_t = -1.0
	var heading_vec := CombatConstants.heading(yaw)
	var right := Vector3(-heading_vec.z, 0.0, heading_vec.x)
	var offset := -heading_vec * cos(pitch) + Vector3.UP * sin(pitch)
	var wanted := _pivot + offset * want_distance + right * (-0.45)

	# Collision: shorten the arm to just in front of whatever geometry is in the way.
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(_pivot, wanted, CombatConstants.LAYER_CAMERA)
	var hit := space.intersect_ray(query)
	var full := _pivot.distance_to(wanted)
	var allowed := full
	if not hit.is_empty():
		allowed = maxf(0.6, _pivot.distance_to(hit["position"]) - COLLISION_MARGIN)
	# Snap in at once when blocked, ease back out when clear (no popping).
	if allowed < _spring:
		_spring = allowed
	else:
		_spring = lerpf(_spring, allowed, 1.0 - exp(-4.0 * delta))
	var pos := _pivot + (wanted - _pivot).normalized() * minf(_spring, full)

	pos = _clear_of_pillars(pos)
	pos = _keep_inside_arena(pos)

	# Impact punch (decays in ~0.1 s) and noise-based trauma shake: offset ~ trauma^2 (small hits stay subtle).
	_punch *= exp(-18.0 * delta)
	pos += _punch
	shake = maxf(0.0, shake - delta * 2.2)
	var roll := 0.0
	if shake > 0.0:
		var power := shake * shake
		var t := _clock * 38.0
		pos += (right * _noise.get_noise_2d(t, 0.0) + Vector3.UP * _noise.get_noise_2d(t, 31.0)) * power * 0.22
		roll = _noise.get_noise_2d(t, 77.0) * power * 0.05
	camera.global_position = pos
	camera.look_at(_pivot + Vector3.UP * 0.05, Vector3.UP)
	if roll != 0.0:
		camera.rotate_object_local(Vector3.FORWARD, roll)

	# FOV: base + impulse that is held briefly and released (fast out, slow back).
	if _fov_hold > 0.0:
		_fov_hold -= delta
		_fov_kick = lerpf(_fov_kick, _fov_kick_target, 1.0 - exp(-40.0 * delta))
	else:
		_fov_kick_target = 0.0
		_fov_kick = lerpf(_fov_kick, 0.0, 1.0 - exp(-9.0 * delta))
	camera.fov = BASE_FOV + _fov_kick


## The camera never leaves the arena: horizontally it stays inside the wall (a margin short of it) and vertically below the wall top, so
## the intro pull-back, the victory orbit and a fighter standing against the wall can never show the outside of the arena or the
## back of the wall (see through it).
func _keep_inside_arena(pos: Vector3) -> Vector3:
	var max_radius := CombatConstants.ARENA_WALL_RADIUS - 0.5
	var flat := Vector2(pos.x, pos.z)
	if flat.length() > max_radius:
		flat = flat.normalized() * max_radius
		pos.x = flat.x
		pos.z = flat.y
	pos.y = clampf(pos.y, 0.45, StoneArena.WALL_HEIGHT - 0.3)
	return pos
