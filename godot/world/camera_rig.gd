class_name CameraRig
extends Node3D
## The ONE Camera3D of the pit world, with named states and smooth, deterministic transitions.
##
## Everything is pose maths driven by advance(dt) (no Tween objects), so headless tests step it
## explicitly and an interrupted transition can never leave a dangling tween behind. Poses are
## {"p": Vector3, "q": Quaternion, "fov": float} in the world frame.
##
## Frames: chess poses are expressed relative to `origin` (the board root position). While a battle
## runs the board root is lifted/shifted (see BattleWorld.apply_shift) and `origin` follows it, so the
## camera sees exactly the same picture; descent and combat poses are plain world space.

enum State { CHESS_TOP_DOWN, CHESS_PERSPECTIVE, CAPTURE_FOCUS, COMBAT_TRANSITION, COMBAT_THIRD_PERSON, COMBAT_VICTORY, RETURN_TO_CHESS }
const STATE_NAMES: Array[String] = ["ChessTopDown", "ChessPerspective", "CaptureFocus", "CombatTransition", "CombatThirdPerson", "CombatVictory", "ReturnToChess"]
const W := preload("res://world/world_constants.gd")

signal transition_started(state: int)
signal transition_finished(state: int)

var camera: Camera3D
var state: int = State.CHESS_TOP_DOWN
## The chess view restored after a battle / abort.
var chess_view: int = State.CHESS_TOP_DOWN
var origin := Vector3.ZERO
var aspect := 1.6
var flipped := false
var animate := true
var auto_advance := true
## Perspective orbit (same defaults as the original 3D board).
var yaw := 0.0
var elevation := 0.88
var distance := 13.5
## Contested tile centre, board-local. Camera focus for CaptureFocus and the descent.
var focus_tile := Vector3.ZERO
## Source of the combat third-person pose (ThirdPersonCamera.camera). Never rendered itself.
var follow: Camera3D = null
## Victory/climb camera target (world frame) and slow orbit clock.
var victory_focus := Vector3(0, 1, 0)
var _victory_clock := 0.0

var _from := {}
var _t := 1.0
var _duration := 0.0
var _active := false
var _target_state: int = State.CHESS_TOP_DOWN


func _init() -> void:
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.near = W.CAMERA_NEAR
	camera.far = W.CAMERA_FAR
	camera.fov = W.FOV_TOP_DOWN
	add_child(camera)
	process_priority = 100  # after ThirdPersonCamera so the followed pose is current


func _ready() -> void:
	camera.current = true
	apply_steady()


func _process(delta: float) -> void:
	if auto_advance:
		advance(delta)


# ---- public API ---------------------------------------------------------------------------------
static func state_name(value: int) -> String:
	return STATE_NAMES[value]


func is_transitioning() -> bool:
	return _active


func transition_target() -> int:
	return _target_state


func is_chess_state(value: int = -1) -> bool:
	var s := state if value < 0 else value
	return s == State.CHESS_TOP_DOWN or s == State.CHESS_PERSPECTIVE


func default_duration(next: int) -> float:
	match next:
		State.CHESS_TOP_DOWN, State.CHESS_PERSPECTIVE:
			return W.VIEW_SWITCH_TIME
		State.CAPTURE_FOCUS:
			return W.CAPTURE_FOCUS_TIME
		State.COMBAT_TRANSITION:
			return W.DROP_TIME + W.DESCENT_EXTRA_TIME
		State.COMBAT_THIRD_PERSON:
			return W.COMBAT_BLEND_TIME
		State.COMBAT_VICTORY:
			return 0.8
		State.RETURN_TO_CHESS:
			return W.RETURN_CAMERA_TIME
	return 0.5


## Starts a transition from the CURRENT camera pose to `next`. duration < 0 uses the default; a
## non-animated rig (or duration 0) snaps.
func go(next: int, duration: float = -1.0) -> void:
	var d := default_duration(next) if duration < 0.0 else duration
	if next == State.CHESS_TOP_DOWN or next == State.CHESS_PERSPECTIVE:
		chess_view = next
	_from = current_pose()
	_target_state = next
	state = next
	transition_started.emit(next)
	if not animate or d <= 0.0:
		_active = false
		_t = 1.0
		apply_steady()
		transition_finished.emit(next)
		return
	_active = true
	_t = 0.0
	_duration = d
	_apply(_eval(0.0))


## Immediately adopts `next` (no animation) and cancels any running transition.
func snap_to(next: int) -> void:
	if next == State.CHESS_TOP_DOWN or next == State.CHESS_PERSPECTIVE:
		chess_view = next
	state = next
	_target_state = next
	_active = false
	_t = 1.0
	apply_steady()


## Recovery after an abort: leave whatever state we are in and glide (or snap) to the chess view.
func recover(duration: float = -1.0) -> void:
	var d := W.RECOVER_TIME if duration < 0.0 else duration
	follow = null
	var target := chess_view
	_from = current_pose()
	state = target
	_target_state = target
	if not animate or d <= 0.0:
		_active = false
		_t = 1.0
		apply_steady()
		transition_finished.emit(target)
		return
	_active = true
	_t = 0.0
	_duration = d
	_apply(_eval(0.0))


func set_aspect(value: float) -> void:
	aspect = maxf(0.2, value)
	if not _active:
		apply_steady()


func set_flipped(value: bool) -> void:
	flipped = value
	if state == State.CHESS_PERSPECTIVE:
		yaw = PI if value else 0.0
	if not _active:
		apply_steady()


func set_orbit(p_yaw: float, p_elevation: float, p_distance: float) -> void:
	yaw = p_yaw
	elevation = p_elevation
	distance = p_distance
	if state == State.CHESS_PERSPECTIVE and not _active:
		apply_steady()


## Shifts the chess frame (battle start/end). The picture does not change: the camera moves with the board.
func set_origin(value: Vector3) -> void:
	var delta := value - origin
	origin = value
	camera.position += delta
	for key in ["p"]:
		if _from.has(key):
			_from[key] += delta
	if not _active:
		apply_steady()


func advance(dt: float) -> void:
	_victory_clock += dt
	if _active:
		_t += dt / maxf(0.0001, _duration)
		if _t >= 1.0:
			_t = 1.0
			_active = false
			_apply(_eval(1.0))
			transition_finished.emit(state)
			return
		_apply(_eval(_t))
	elif state == State.COMBAT_THIRD_PERSON or state == State.COMBAT_VICTORY:
		apply_steady()


func current_pose() -> Dictionary:
	return {"p": camera.position, "q": camera.basis.get_rotation_quaternion(), "fov": camera.fov}


func apply_steady() -> void:
	_apply(pose_for(state))


# ---- poses ----------------------------------------------------------------------------------------
func pose_for(s: int) -> Dictionary:
	match s:
		State.CHESS_TOP_DOWN:
			return _top_down_pose(Vector3.ZERO, W.FOV_TOP_DOWN, 1.0)
		State.CHESS_PERSPECTIVE:
			return _perspective_pose()
		State.CAPTURE_FOCUS:
			return _focus_pose()
		State.COMBAT_THIRD_PERSON:
			return _third_person_pose()
		State.COMBAT_VICTORY:
			return _victory_pose()
		State.COMBAT_TRANSITION:
			return _descent(1.0)
		State.RETURN_TO_CHESS:
			return _return_path(1.0, _from)
	return current_pose()


func _quat_down() -> Quaternion:
	return _top_down_basis().get_rotation_quaternion()


func _top_down_basis() -> Basis:
	if flipped:
		return Basis(Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0))
	return Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))


## Straight-down narrow-FOV camera that frames `half_extent` metres (vertical) around `center`
## (board-local). `fit` lets the whole board fit narrow (portrait) windows.
func _top_down_pose(center: Vector3, fov: float, fit: float) -> Dictionary:
	var half := W.TOP_DOWN_HALF_EXTENT * maxf(1.0, 1.0 / maxf(0.45, aspect)) * fit
	var height := half / tan(deg_to_rad(fov) * 0.5)
	return _pose(origin + center + Vector3(0, height, 0), _top_down_basis(), fov)


func _focus_height() -> float:
	return W.FOCUS_HALF_EXTENT / tan(deg_to_rad(W.FOV_TOP_DOWN) * 0.5)


func _focus_pose() -> Dictionary:
	return _pose(origin + focus_tile + Vector3(0, _focus_height(), 0), _top_down_basis(), W.FOV_TOP_DOWN)


func _perspective_pose() -> Dictionary:
	var adjusted := distance * maxf(1.0, 1.0 / maxf(0.45, aspect))
	var offset := Vector3(sin(yaw) * cos(elevation), sin(elevation), cos(yaw) * cos(elevation)) * adjusted
	var target := origin + Vector3(0, 0.15, 0)
	var p := origin + offset
	# Occlusion: never dip below the board plane.
	p.y = maxf(p.y, origin.y + 0.8)
	return _pose(p, Basis.looking_at(target - p, Vector3.UP), W.FOV_PERSPECTIVE)


func _third_person_pose() -> Dictionary:
	if follow != null and is_instance_valid(follow) and follow.is_inside_tree():
		return _pose(follow.global_position, follow.global_transform.basis, follow.fov)
	return _fallback_combat_pose()


func _fallback_combat_pose() -> Dictionary:
	var p := Vector3(0.0, 2.8, -6.2)
	return _pose(p, Basis.looking_at(Vector3(0, 1.0, 0) - p, Vector3.UP), W.FOV_COMBAT)


func _victory_pose() -> Dictionary:
	var f := victory_focus
	var sway := sin(_victory_clock * 0.7) * 0.5
	# Once the climber nears the ceiling the camera slides under the shaft so it can see him leave.
	var shaft := W.smooth((f.y - 2.5) / 3.0)
	var back := lerpf(3.2, 0.35, shaft)
	var p := Vector3(f.x + sway * (1.0 - shaft), clampf(f.y - lerpf(0.6, 2.4, shaft), 1.5, 4.4), f.z - back)
	var look := f + Vector3(0, 0.5, 0)
	return _pose(p, Basis.looking_at(look - p, Vector3.UP), 58.0)


func _pose(p: Vector3, b: Basis, fov: float) -> Dictionary:
	return {"p": p, "q": b.orthonormalized().get_rotation_quaternion(), "fov": fov}


func _lerp_pose(a: Dictionary, b: Dictionary, w: float) -> Dictionary:
	return {"p": a["p"].lerp(b["p"], w), "q": (a["q"] as Quaternion).slerp(b["q"], w), "fov": lerpf(a["fov"], b["fov"], w)}


func _eval(t: float) -> Dictionary:
	match state:
		State.COMBAT_TRANSITION:
			return _descent(W.smooth(t))
		State.RETURN_TO_CHESS:
			return _return_path(t, _from)
	return _lerp_pose(_from, pose_for(state), W.smooth(t))


# ---- the dolly-zoom descent -----------------------------------------------------------------------
func _hole() -> Vector3:
	return origin + focus_tile


func _dolly_pose(a: float) -> Dictionary:
	## Height above the board plane and FOV change together so the framed width stays constant.
	var d := lerpf(_focus_height(), W.DESCENT_STOP_ABOVE_BOARD, a)
	var fov := rad_to_deg(2.0 * atan(W.FOCUS_HALF_EXTENT / d))
	var h := _hole()
	return _pose(Vector3(h.x, origin.y + d, h.z), _top_down_basis(), fov)


## Focus pose -> dolly-zoom down to just above the board -> through the shaft -> third-person pose.
func _descent(u: float) -> Dictionary:
	var split := 0.45
	if u <= split:
		return _dolly_pose(W.smooth(u / split))
	var start := _dolly_pose(1.0)
	var end := _third_person_pose()
	var b := W.smooth((u - split) / (1.0 - split))
	var h := _hole()
	var control := Vector3(h.x, W.CEILING_BOTTOM - 1.0, h.z)
	var p := _bezier(start["p"], control, end["p"], b)
	p = _clamp_to_shaft(p)
	return {"p": p, "q": (start["q"] as Quaternion).slerp(end["q"], W.smooth(b)), "fov": lerpf(start["fov"], end["fov"], W.smooth(b))}


## Chamber pose (current) -> up the shaft -> reverse dolly-zoom -> glide to the chess view.
func _return_path(u: float, from_pose: Dictionary) -> Dictionary:
	if from_pose.is_empty():
		return pose_for(chess_view)
	var dolly_end := _dolly_pose(1.0)
	if u <= 0.5:
		var b := W.smooth(u / 0.5)
		var h := _hole()
		var control := Vector3(h.x, W.CEILING_BOTTOM - 1.0, h.z)
		var p := _clamp_to_shaft(_bezier(from_pose["p"], control, dolly_end["p"], b))
		return {"p": p, "q": (from_pose["q"] as Quaternion).slerp(dolly_end["q"], W.smooth(b)), "fov": lerpf(from_pose["fov"], dolly_end["fov"], W.smooth(b))}
	if u <= 0.75:
		return _dolly_pose(1.0 - W.smooth((u - 0.5) / 0.25))
	return _lerp_pose(_focus_pose(), pose_for(chess_view), W.smooth((u - 0.75) / 0.25))


static func _bezier(a: Vector3, c: Vector3, b: Vector3, t: float) -> Vector3:
	var ac := a.lerp(c, t)
	var cb := c.lerp(b, t)
	return ac.lerp(cb, t)


## Camera collision for the one place a free camera could clip scenery: the 1 m shaft between the
## chamber ceiling and the board. Inside that vertical band it is kept clear of the shaft walls.
func _clamp_to_shaft(p: Vector3) -> Vector3:
	if p.y < W.CEILING_BOTTOM - 0.1 or p.y > origin.y:
		return p
	var h := _hole()
	var limit := W.HOLE_HALF - 0.2
	return Vector3(h.x + clampf(p.x - h.x, -limit, limit), p.y, h.z + clampf(p.z - h.z, -limit, limit))


func _apply(pose: Dictionary) -> void:
	camera.position = pose["p"]
	camera.basis = Basis(pose["q"])
	camera.fov = pose["fov"]
	# The ceiling slab is only ever visible from below it.
	var below := camera.position.y < W.CEILING_BOTTOM + W.CEILING_THICKNESS + 0.3
	camera.cull_mask = W.MASK_ALL if below else W.MASK_NO_CEILING
