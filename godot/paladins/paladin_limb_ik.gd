class_name PaladinLimbIK
extends SkeletonModifier3D
## Analytic two-bone IK for the paladin rigs, run by the skeleton AFTER the animation has been applied (a SkeletonModifier3D).
## Godot 4.6 also ships TwoBoneIK3D; this solver is used instead because its targets are computed every frame from the animated pose
## itself (a plane, a floor, a planted foot) rather than from scene nodes, and because it is deterministic and testable headless.
##
## Two jobs, each blended by a weight so clips can fade in and out:
##   * ladder: the hands are pinned to the rungs' plane (z in the fighter's frame, +Z forward) and kept between the rails; the feet are kept
##     in front of that plane. The authored climb slides the hands about +-10 cm around the plane; with the pin they stay on it.
##   * ground: feet never sink below the floor, and a foot that touches down is held at its landing spot (in world space) until the animated
##     foot lifts again, so walk / run / strafe / idle do not skate. A slip beyond MAX_SLIP re-plants the foot (no stretched legs).
## Hand and foot orientation is preserved, so the sword grip does not change.

const CONTACT_HEIGHT := 0.05    # a foot closer than this to the floor (world m) is planted (the walk clips hover the ankle ~3 cm above its rest height)
const RELEASE_HEIGHT := 0.08    # ...and lifts when the animated foot is higher than this
const MAX_PULL := 0.04          # a planted foot is pulled at most this far (horizontally and vertically) from its animated spot: more would fold the legs into the blade and torso
const PLANT_SPEED := 0.8        # m/s: only a foot that is nearly still on the ground can be planted (a foot swinging past the floor is not)
const MAX_SLIP := 0.34          # metres a planted foot may be pulled from its animated spot before it re-plants

const LADDER_CLIPS := ["climb", "ladder_idle"]
const GROUND_CLIPS := ["idle", "walk", "run", "strafe_left", "strafe_right", "block", "Walking", "Running"]
## Clips in which the blade is re-aimed (skeleton space, x < 0 = outward for the right hand) because the animation folds the body around it:
## the roll brings the thigh up against a blade that points down and forward, so it is carried out to the side and up.
## Locomotion: the arm swings with the stride and a blade fixed in the hand would swing through the leg and skirt, so it holds its direction in
## the character's frame instead (forward and a little out), like a wrist that counter-rotates.
const SWORD_AIM_BY_CLIP := {"dodge": Vector3(-0.85, 0.4, 0.35), "walk": Vector3(-0.5, -0.2, 0.84), "run": Vector3(-0.5, -0.15, 0.85),
		"strafe_left": Vector3(-0.5, -0.2, 0.84), "strafe_right": Vector3(-0.5, -0.2, 0.84)}
const FADE_RATE := 7.0          # weight per second: a fade in or out takes about 0.15 s

var ladder_weight := 0.0
var ground_weight := 0.0
var sword: Node3D               # holder of the blade (child of the right hand attachment); re-aimed per clip, see SWORD_AIM_BY_CLIP
var sword_rest := Basis.IDENTITY
var sword_hand := -1
var sword_weight := 0.0
var _last_aim := Vector3(-0.5, -0.2, 0.84)
var player: AnimationPlayer     # its current clip decides what the IK does (read every frame; nobody has to call us)
var force_ladder := -1.0        # >= 0 overrides the clip-driven ladder weight (tests)
var force_ground := -1.0
var plane_z := 0.25             # the rungs' plane in the fighter's frame (m, +Z forward)
var half_width := 0.22          # the hands stay within this of the ladder's centre line (m)
var frame_node: Node3D          # the fighter: defines "forward" and the world floor
var floor_height := 0.0         # skeleton-space height of the foot bones when standing (their rest height)

var calls := 0
var _skeleton: Skeleton3D
var _chains := {}               # "LeftHand" ... -> {root, mid, tip, kind}
var fixed_dt := 0.0             # > 0: use this instead of the frame time (tests step the animation by hand)
var _dt := 0.016
var _last_world := {}           # chain name -> the animated foot position (world) of the previous update
var _planted := {}              # chain name -> world position the foot is held at


func setup(skeleton: Skeleton3D, frame: Node3D, animation_player: AnimationPlayer = null) -> bool:
	_skeleton = skeleton
	frame_node = frame
	player = animation_player
	for side in ["Left", "Right"]:
		_add_chain(side + "Hand", side + "Arm", side + "ForeArm", side + "Hand", "hand")
		_add_chain(side + "Foot", side + "UpLeg", side + "Leg", side + "Foot", "foot")
	if _chains.is_empty():
		return false
	if _chains.has("LeftFoot"):
		floor_height = skeleton.get_bone_global_rest(_chains["LeftFoot"]["tip"]).origin.y
	name = "LimbIK"
	skeleton.add_child(self)
	return true


func _add_chain(key: String, root: String, mid: String, tip: String, kind: String) -> void:
	var r := _skeleton.find_bone("mixamorig_" + root)
	var m := _skeleton.find_bone("mixamorig_" + mid)
	var t := _skeleton.find_bone("mixamorig_" + tip)
	if r >= 0 and m >= 0 and t >= 0:
		_chains[key] = {"root": r, "mid": m, "tip": t, "kind": kind}


func reset_planted() -> void:
	_planted.clear()


func _process_modification_with_delta(delta: float) -> void:
	calls += 1
	var clip: String = player.current_animation if player != null and is_instance_valid(player) else ""
	var want_ladder: float = (1.0 if clip in LADDER_CLIPS else 0.0) if force_ladder < 0.0 else force_ladder
	var want_ground: float = (1.0 if clip in GROUND_CLIPS else 0.0) if force_ground < 0.0 else force_ground
	_dt = fixed_dt if fixed_dt > 0.0 else maxf(delta, 0.0001)
	_aim_sword(clip, delta)
	ladder_weight = move_toward(ladder_weight, want_ladder, FADE_RATE * delta) if force_ladder < 0.0 else want_ladder
	ground_weight = move_toward(ground_weight, want_ground, FADE_RATE * delta) if force_ground < 0.0 else want_ground
	_apply()


func _aim_sword(clip: String, delta: float) -> void:
	if sword == null or not is_instance_valid(sword) or sword_hand < 0:
		return
	var want := 1.0 if SWORD_AIM_BY_CLIP.has(clip) else 0.0
	if want > 0.0:
		_last_aim = SWORD_AIM_BY_CLIP[clip]
	sword_weight = move_toward(sword_weight, want, FADE_RATE * delta)
	if sword_weight <= 0.001:
		sword.transform.basis = sword_rest
		return
	var aim: Vector3 = _last_aim   # kept while the weight fades out after a clip change
	var to_local := _skeleton.get_bone_global_pose(sword_hand).basis.orthonormalized().inverse()
	var z_dir: Vector3 = (to_local * aim.normalized()).normalized()
	var x_dir: Vector3 = to_local * Vector3(1.0, 0.0, 0.0)
	var y_dir := z_dir.cross(x_dir).normalized()
	x_dir = y_dir.cross(z_dir).normalized()
	var target := Basis(x_dir, y_dir, z_dir)
	sword.transform.basis = sword_rest.slerp(target, smoothstep(0.0, 1.0, sword_weight))


func _apply() -> void:
	if _skeleton == null or frame_node == null or not is_instance_valid(frame_node) or not frame_node.is_inside_tree():
		return
	var to_frame := frame_node.global_transform.affine_inverse() * _skeleton.global_transform
	var from_frame := to_frame.affine_inverse()
	for key in _chains:
		var chain: Dictionary = _chains[key]
		var tip_now := _skeleton.get_bone_global_pose(chain["tip"]).origin
		var target := tip_now
		var weight := 0.0
		if chain["kind"] == "hand":
			if ladder_weight <= 0.001:
				continue
			var p := to_frame * tip_now
			target = from_frame * Vector3(clampf(p.x, -half_width, half_width), p.y, plane_z)
			weight = ladder_weight
		else:
			var result := _foot_target(key, tip_now)
			target = result[0]
			weight = result[1]
			if ladder_weight > 0.001:   # on the ladder the foot stays in front of the rungs (a step on a rung, not through it)
				var p := to_frame * tip_now
				var lane := from_frame * Vector3(clampf(p.x, -half_width, half_width), p.y, minf(p.z, plane_z - 0.05))
				target = target.lerp(lane, ladder_weight)
				weight = maxf(weight, ladder_weight)
		if weight > 0.001 and target.distance_to(tip_now) > 0.0002:
			_solve(chain, target, weight)


## Floor / planted-foot target in skeleton space and its weight. A held foot fades out as the animated foot lifts (and as it drifts
## from its hold), so letting go never pops.
func _foot_target(key: String, tip_now: Vector3) -> Array:
	if ground_weight <= 0.001:
		_planted.erase(key)
		return [tip_now, 0.0]
	var skeleton_xf := _skeleton.global_transform
	var world := skeleton_xf * tip_now
	var floor_y := (skeleton_xf * Vector3(0.0, floor_height, 0.0)).y
	var height := world.y - floor_y
	var speed := 0.0
	if _last_world.has(key):
		speed = Vector2(world.x - _last_world[key].x, world.z - _last_world[key].z).length() / _dt
	_last_world[key] = world
	var held: Variant = _planted.get(key, null)
	var drift := 0.0
	if held != null:
		drift = Vector2(world.x - held.x, world.z - held.z).length()
		if height > RELEASE_HEIGHT or drift > MAX_SLIP or speed > PLANT_SPEED * 2.0:
			_planted.erase(key)
			held = null
	if held == null and height < CONTACT_HEIGHT and speed < PLANT_SPEED:
		_planted[key] = Vector3(world.x, floor_y, world.z)
		held = _planted[key]
		drift = 0.0
	if held != null:
		# rubber band: the anchor trails the animated foot at most MAX_PULL behind, so the foot is held where it landed as far as that reaches
		var anchor := Vector3(held.x, floor_y, held.z)
		var flat := Vector3(anchor.x - world.x, 0.0, anchor.z - world.z)
		if flat.length() > MAX_PULL:
			anchor = Vector3(world.x + flat.x / flat.length() * MAX_PULL, floor_y, world.z + flat.z / flat.length() * MAX_PULL)
			_planted[key] = anchor
		var lift := clampf(floor_y - world.y, -MAX_PULL, MAX_PULL)
		var fade := 1.0 - smoothstep(CONTACT_HEIGHT, RELEASE_HEIGHT, height)
		return [skeleton_xf.affine_inverse() * Vector3(anchor.x, world.y + lift, anchor.z), ground_weight * fade]
	if height < 0.0:   # never below the floor (even while swinging)
		return [skeleton_xf.affine_inverse() * Vector3(world.x, floor_y, world.z), ground_weight]
	return [tip_now, 0.0]


# ---- the two-bone solver ----------------------------------------------------------------------------------------------------------
func _solve(chain: Dictionary, target: Vector3, weight: float) -> void:
	var sk := _skeleton
	var root_i: int = chain["root"]
	var mid_i: int = chain["mid"]
	var tip_i: int = chain["tip"]
	var root_pose := sk.get_bone_global_pose(root_i)
	var mid_pose := sk.get_bone_global_pose(mid_i)
	var tip_pose := sk.get_bone_global_pose(tip_i)
	var r := root_pose.origin
	var m := mid_pose.origin
	var t := tip_pose.origin
	var goal := t.lerp(target, clampf(weight, 0.0, 1.0))
	var l1 := r.distance_to(m)
	var l2 := m.distance_to(t)
	if l1 < 0.001 or l2 < 0.001:
		return
	var to_goal := goal - r
	var d := clampf(to_goal.length(), absf(l1 - l2) + 0.002, l1 + l2 - 0.002)
	var dir := to_goal.normalized()
	var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	# the knee / elbow keeps bending the way the animation bends it
	var bend := (m - r) - dir * (m - r).dot(dir)
	if bend.length() < 0.0005:
		bend = (m - r) - ((t - r).normalized()) * (m - r).dot((t - r).normalized())
	if bend.length() < 0.0005:
		return
	var new_mid := r + dir * a + bend.normalized() * h
	var new_tip := r + dir * d
	var tip_basis := tip_pose.basis
	# root bone: swing its child direction onto the new mid; mid bone: swing onto the new tip
	_swing(root_i, root_pose, (m - r).normalized(), (new_mid - r).normalized())
	var mid_now := sk.get_bone_global_pose(mid_i)
	var tip_after_root := mid_now.origin + (mid_now.basis * (mid_pose.basis.inverse() * (t - m)))
	_swing(mid_i, mid_now, (tip_after_root - mid_now.origin).normalized(), (new_tip - mid_now.origin).normalized())
	# keep the hand / foot orientation of the animation (the grip and the sole do not change)
	var mid_final := sk.get_bone_global_pose(mid_i)
	var local_basis := mid_final.basis.orthonormalized().inverse() * tip_basis.orthonormalized()
	sk.set_bone_pose_rotation(tip_i, local_basis.get_rotation_quaternion())


## Rotates bone `i` (global pose `pose`) by the shortest arc taking `from` to `to` (both skeleton-space directions).
func _swing(i: int, pose: Transform3D, from: Vector3, to: Vector3) -> void:
	var dot := clampf(from.dot(to), -1.0, 1.0)
	if dot > 0.99999:
		return
	var axis := from.cross(to)
	if axis.length() < 1e-6:
		return
	var delta := Quaternion(axis.normalized(), acos(dot))
	var desired := Basis(delta) * pose.basis.orthonormalized()
	var parent := _skeleton.get_bone_parent(i)
	var parent_basis := Basis.IDENTITY if parent < 0 else _skeleton.get_bone_global_pose(parent).basis.orthonormalized()
	_skeleton.set_bone_pose_rotation(i, (parent_basis.inverse() * desired).get_rotation_quaternion())
