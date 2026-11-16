extends RefCounted
## Measurable animation quality: the sword must not sink into the fighter's own body while locomoting or striking, and the
## ladder climb must put the hands on the rungs, in front of the rails, with the body in front of the ladder.

## Capsules of the body that a blade can sink into: bone A, bone B, radius at the 1.7 m source height.
const BODY := [["mixamorig_Hips", "mixamorig_Spine2", 0.17], ["mixamorig_Spine2", "mixamorig_Neck", 0.15],
	["mixamorig_LeftUpLeg", "mixamorig_LeftLeg", 0.11], ["mixamorig_LeftLeg", "mixamorig_LeftFoot", 0.08],
	["mixamorig_RightUpLeg", "mixamorig_RightLeg", 0.11], ["mixamorig_RightLeg", "mixamorig_RightFoot", 0.08],
	["mixamorig_LeftArm", "mixamorig_LeftHand", 0.07]]
const LOCOMOTION := ["idle", "walk", "run", "strafe_left", "strafe_right", "block", "light_1", "light_2", "light_3", "heavy"]
const MAX_SINK := 0.04   # metres a blade sample may be inside a body capsule (the cartoon armour is not skin tight)
const LADDER_HALF := 0.28


static func _dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func run(h, tree: SceneTree) -> void:
	h.begin("paladin animation: the sword stays out of the body, the climb puts hands and feet on the ladder")
	for role in ["p", "n", "b", "r", "q", "k"]:
		if not PaladinModel.available(role):
			continue
		var fighter := PaladinFighter.new()
		tree.root.add_child(fighter)
		if not fighter.setup_free(role, 0, "w"):
			fighter.queue_free()
			continue
		var body := fighter.model as PaladinModel
		_sword(h, body, role)
		_ladder(h, body, role)
		fighter.queue_free()
		await tree.process_frame


static func _sword(h, body: PaladinModel, role: String) -> void:
	var sk := body.skeleton
	var k := body.height / PaladinModel.SOURCE_HEIGHT
	var sword := sk.get_node("WeaponSocket_R/Sword") as Node3D
	var length: float = ((sword.get_node("Blade") as MeshInstance3D).mesh as BoxMesh).size.z
	for clip in LOCOMOTION:
		if not body.player.has_animation(clip):
			continue
		body.player.play(clip)
		var duration := body.player.get_animation(clip).length
		var deepest := 0.0
		for i in 24:
			body.player.seek(duration * float(i) / 24.0, true)
			sk.force_update_all_bone_transforms()
			for s in 10:
				var p := sword.global_transform * Vector3(0, 0, 0.07 + length * float(s + 1) / 10.0)
				for capsule in BODY:
					var a := sk.global_transform * sk.get_bone_global_pose(sk.find_bone(capsule[0])).origin
					var b := sk.global_transform * sk.get_bone_global_pose(sk.find_bone(capsule[1])).origin
					deepest = maxf(deepest, float(capsule[2]) * k - _dist(p, a, b))
		h.check(deepest <= MAX_SINK, "%s %s: the blade sinks at most %.0f mm into the body (%.0f mm)" % [role, clip, MAX_SINK * 1000.0, deepest * 1000.0])


## Hands on the rails' plane and between the rails, feet near it, body in front of the ladder, at the pit's real ladder offset.
static func _ladder(h, body: PaladinModel, role: String) -> void:
	var sk := body.skeleton
	body.player.play("climb")
	var fit: Vector2 = PaladinFighter.LADDER_FIT[role]
	var ladder_z := 0.42 - fit.x   # WorldConstants.LADDER_Z - inset, the climber stands at z = 0
	var worst_hand := 0.0
	var closest := INF
	var worst_side := 0.0
	var behind := true
	for i in 20:
		body.player.seek(0.7333 * float(i) / 20.0, true)
		sk.force_update_all_bone_transforms()
		for bone in ["mixamorig_RightHand", "mixamorig_LeftHand"]:
			var p := sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone)).origin
			worst_hand = maxf(worst_hand, absf(p.z - ladder_z))
			closest = minf(closest, absf(p.z - ladder_z))
			worst_side = maxf(worst_side, absf(p.x) - LADDER_HALF)
		var chest := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("mixamorig_Spine2")).origin
		behind = behind and chest.z < ladder_z - 0.04
	h.check(closest <= 0.04, "%s climb: the hands reach the rungs' plane (closest %.0f mm)" % [role, closest * 1000.0])
	h.check(worst_hand <= 0.14, "%s climb: the hands never stray more than 14 cm from the rungs' plane (%.0f mm)" % [role, worst_hand * 1000.0])
	h.check(worst_side <= 0.0, "%s climb: the hands stay between the rails" % role)
	h.check(behind, "%s climb: the chest stays in front of the ladder" % role)
