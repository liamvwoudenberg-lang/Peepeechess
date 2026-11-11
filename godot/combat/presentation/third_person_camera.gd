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

var target: FighterController
var opponent: FighterController
var locked: bool = true
var yaw: float = 0.0           # gameplay heading the camera looks along (sin, cos convention)
var pitch: float = 0.32        # elevation above horizontal, radians
var distance: float = 4.8
var camera: Camera3D
var shake: float = 0.0
var _pivot: Vector3 = Vector3.ZERO
var _spring: float = 4.8
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	camera = Camera3D.new()
	camera.fov = 68.0
	camera.near = 0.1
	camera.far = 80.0
	add_child(camera)


func bind(p_target: FighterController, p_opponent: FighterController) -> void:
	target = p_target
	opponent = p_opponent
	yaw = target.yaw
	_pivot = _fighter_position(target) + Vector3(0.0, FOLLOW_HEIGHT, 0.0)
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


func zoom(amount: float) -> void:
	distance = clampf(distance + amount, MIN_DISTANCE, MAX_DISTANCE)


func add_shake(amount: float) -> void:
	shake = minf(shake + amount, 0.6)


static func _fighter_position(f: FighterController) -> Vector3:
	return f.prev_position.lerp(f.global_position, Engine.get_physics_interpolation_fraction())


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return
	var own := _fighter_position(target)
	var foe_alive := opponent != null and is_instance_valid(opponent) and opponent.is_inside_tree() and opponent.health.is_alive()
	var desired_pivot := own + Vector3(0.0, FOLLOW_HEIGHT, 0.0)
	var want_distance := distance
	if locked and foe_alive:
		var foe := _fighter_position(opponent)
		var to_foe := CombatConstants.flat(foe - own)
		if to_foe.length() > 0.05:
			var heading := CombatConstants.yaw_of(to_foe)
			yaw = lerp_angle(yaw, heading, 1.0 - exp(-9.0 * delta))
			# Shift the pivot toward the opponent and pull back when they are far, so both stay framed.
			desired_pivot += to_foe * 0.28
			want_distance = clampf(distance + to_foe.length() * 0.18, MIN_DISTANCE, MAX_DISTANCE)
	_pivot = _pivot.lerp(desired_pivot, 1.0 - exp(-14.0 * delta))

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

	shake = maxf(0.0, shake - delta * 2.5)
	if shake > 0.0:
		pos += Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * shake * 0.12
	camera.global_position = pos
	camera.look_at(_pivot + Vector3.UP * 0.05, Vector3.UP)
