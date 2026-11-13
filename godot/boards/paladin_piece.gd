class_name PaladinPiece
extends Node3D
## A chess piece shown as a rigged paladin (PaladinModel) on the 3D board. The ROOT node keeps the contract every other piece node has
## (position = tile centre, rotation.y = 0 for white / PI for black, scale, visible are driven by BattleWorld / PitSequence); the model
## sits under `facer`, which turns it to face its walking direction and back to the resting direction afterwards.
## Models face +Z; the board rests white facing -Z (see BoardThemeView.build_piece), so the resting `facer.rotation.y` is PI for both sides.

## Standing height (m) per role: fits a 1 m tile and still reads from the straight-down camera.
const HEIGHTS := {"p": 1.1, "n": 1.3, "b": 1.36, "r": 1.24, "q": 1.44, "k": 1.52}
const WALK_SPEED := 1.5        # m/s for a one-square step
const RUN_SPEED := 3.0         # m/s for longer moves
const MAX_SECONDS := 2.5       # a whole move never takes longer (at normal animation speed)
const TURN_SECONDS := 0.12
const REST_YAW := PI

var role: String = "p"
var color: String = "w"
var model: PaladinModel
var facer: Node3D
var walking: bool = false
var _walk: Tween
var _turn: Tween


## Frees PaladinModel's cached templates and textures (they are never in the tree, so the engine would report them as leaked at exit).
## Called when a 3D board leaves the tree; the next piece simply rebuilds the cache.
static func release_cache() -> void:
	PaladinModel.release_all()


static func available(role_code: String) -> bool:
	return PaladinModel.available(role_code)


static var _exit_hooked := false


static func create(role_code: String, color_code: String) -> PaladinPiece:
	if not _exit_hooked:
		# The template cache is never in the tree: release it when the engine shuts down so it is not reported as leaked.
		var loop := Engine.get_main_loop() as SceneTree
		if loop != null:
			_exit_hooked = true  # PaladinModel hooks its own exit release
	var m := PaladinModel.create(role_code, color_code, float(HEIGHTS.get(role_code, 1.0)))
	if m == null:
		return null
	var piece := PaladinPiece.new()
	piece.role = role_code
	piece.color = color_code
	piece.model = m
	piece.facer = Node3D.new()
	piece.facer.name = "Facer"
	piece.facer.rotation.y = REST_YAW
	piece.add_child(piece.facer)
	piece.facer.add_child(m)
	m.play("idle")
	return piece


## The corner of the L for a knight (the long leg first); every other move is one straight leg.
static func path_between(role_code: String, from: Vector3, to: Vector3) -> Array[Vector3]:
	var path: Array[Vector3] = []
	if role_code == "n":
		var d := to - from
		path.append(from + (Vector3(d.x, 0, 0) if absf(d.x) > absf(d.z) else Vector3(0, 0, d.z)))
	path.append(to)
	return path


## Plays the walk (or run) along `points` from the current position. `time_scale` multiplies durations (BoardTheme.anim_seconds).
## Returns the total duration in seconds. `done` is called on arrival, after the piece has turned back to its resting direction.
func walk_along(points: Array[Vector3], time_scale: float = 1.0, done: Callable = Callable()) -> float:
	stop_walk()
	var total := 0.0
	var last := position
	for p in points:
		total += last.distance_to(p)
		last = p
	if total < 0.01:
		if not points.is_empty():
			position = points[points.size() - 1]
		return 0.0
	var run := total > 1.6
	var speed := RUN_SPEED if run else WALK_SPEED
	speed = maxf(speed, total / MAX_SECONDS)
	speed /= maxf(time_scale, 0.05)
	var clip := "run" if run else "walk"
	model.play(clip, model.locomotion_speed(clip, speed))
	walking = true
	_walk = create_tween()
	last = position
	var duration := 0.0
	for p in points:
		var direction := p - last
		var yaw := atan2(direction.x, direction.z) - rotation.y
		_walk.tween_callback(_face.bind(yaw))
		var leg := last.distance_to(p) / speed
		_walk.tween_property(self, "position", p, leg)
		duration += leg
		last = p
	_walk.tween_callback(_arrived.bind(done))
	return duration + TURN_SECONDS


func stop_walk() -> void:
	if _walk != null and _walk.is_valid():
		_walk.kill()
	if _turn != null and _turn.is_valid():
		_turn.kill()
	walking = false
	if facer != null:
		facer.rotation.y = REST_YAW
	if model != null and model.current != "idle":
		model.play("idle")


func _face(yaw: float) -> void:
	if _turn != null and _turn.is_valid():
		_turn.kill()
	var from_yaw := facer.rotation.y
	_turn = create_tween()
	_turn.tween_method(func(t: float): facer.rotation.y = lerp_angle(from_yaw, yaw, t), 0.0, 1.0, TURN_SECONDS)


func _arrived(done: Callable) -> void:
	walking = false
	model.play("idle")
	_face(REST_YAW)
	if done.is_valid():
		done.call()
