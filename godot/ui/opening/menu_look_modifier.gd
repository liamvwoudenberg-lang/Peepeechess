class_name MenuLookModifier
extends SkeletonModifier3D
## Turns a station paladin's head and upper body toward a hovered prop, ON TOP of whatever clip is playing (it runs after the animation, like
## PaladinLimbIK). `yaw` is radians about the model's up axis (positive = toward the model's left); the neck and head take most of it, the
## spine a little.
const SPLIT := {"Spine2": 0.15, "Neck": 0.35, "Head": 0.5}
var yaw := 0.0            ## where to look (set by MenuWorld)
var weight := 1.0
var applied := 0.0        ## the yaw actually applied on the last update (tests read this)
var _bones := {}

func setup(skeleton: Skeleton3D) -> void:
	for short in SPLIT:
		for prefix in ["mixamorig_", "mixamorig:", ""]:
			var index := skeleton.find_bone(prefix + short)
			if index >= 0:
				_bones[short] = index
				break

func has_bones() -> bool:
	return not _bones.is_empty()

func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	applied = yaw * weight
	if absf(applied) < 0.0005:
		return
	for short in _bones:
		var index: int = _bones[short]
		var share: float = SPLIT[short]
		# a turn about the model's up axis, expressed in the bone's own frame through its current global pose
		var pose := skeleton.get_bone_global_pose(index)
		var up_local := (pose.basis.inverse() * Vector3.UP).normalized()
		var turn := Quaternion(up_local, applied * share)
		skeleton.set_bone_pose_rotation(index, skeleton.get_bone_pose_rotation(index) * turn)
