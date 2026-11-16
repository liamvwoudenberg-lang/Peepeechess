extends RefCounted
## Measurable animation quality: the sword must not sink into the fighter's own body while locomoting or striking, and the
## ladder climb must put the hands on the rungs, in front of the rails, with the body in front of the ladder.

## Capsules of the body that a blade can sink into: bone A, bone B, radius at the 1.7 m source height.
const BODY := [["mixamorig_Hips", "mixamorig_Spine2", 0.17], ["mixamorig_Spine2", "mixamorig_Neck", 0.15],
	["mixamorig_LeftUpLeg", "mixamorig_LeftLeg", 0.11], ["mixamorig_LeftLeg", "mixamorig_LeftFoot", 0.08],
	["mixamorig_RightUpLeg", "mixamorig_RightLeg", 0.11], ["mixamorig_RightLeg", "mixamorig_RightFoot", 0.08],
	["mixamorig_LeftArm", "mixamorig_LeftHand", 0.07]]
const LOCOMOTION := ["idle", "walk", "run", "strafe_left", "strafe_right", "block", "light_1", "light_2", "light_3", "heavy", "dodge", "parry", "victory", "hit_react_light"]
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
		await _sword(h, body, role, tree)
		await _ladder(h, body, role, tree)
		await _ground(h, fighter, body, role, tree)
		fighter.queue_free()
		await tree.process_frame


static func _sword(h, body: PaladinModel, role: String, tree: SceneTree) -> void:
	var fighter := body.get_parent() as PaladinFighter
	var sk := body.skeleton
	var k := body.height / PaladinModel.SOURCE_HEIGHT
	var sword := sk.get_node("WeaponSocket_R/Sword") as Node3D
	var length: float = ((sword.get_node("Blade") as MeshInstance3D).mesh as BoxMesh).size.z
	var bones := []
	for capsule in BODY:
		for name in [capsule[0], capsule[1]]:
			if not bones.has(name):
				bones.append(name)
	var latest := _after_modifiers(sk, bones)
	var blade := {"xf": Transform3D.IDENTITY}
	var hand := sk.find_bone("mixamorig_RightHand")
	# The blade's world transform from the hand pose of THIS update (the bone attachment node itself lags a frame behind the signal).
	sk.skeleton_updated.connect(func(): blade["xf"] = sk.global_transform * sk.get_bone_global_pose(hand) * sword.transform)
	for clip in LOCOMOTION:
		if not body.player.has_animation(clip):
			continue
		body.player.play(clip, 0.0)
		var duration := body.player.get_animation(clip).length
		var deepest := 0.0
		var ground_speed := fighter._nominal_speed("run") if clip == "run" else (fighter._nominal_speed("walk") if clip in ["walk", "strafe_left", "strafe_right"] else 0.0)
		fighter.limb_ik.reset_planted()
		for i in 24:
			body.player.seek(duration * float(i) / 24.0, true)
			fighter.global_position = Vector3(0, 0, ground_speed * duration * float(i) / 24.0)   # a walker moves: a planted foot is held on the ground, not in place
			await tree.process_frame
			if i < 3:
				continue   # fades settle
			for s in 10:
				var p: Vector3 = (blade["xf"] as Transform3D) * Vector3(0, 0, 0.07 + length * float(s + 1) / 10.0)
				for capsule in BODY:
					deepest = maxf(deepest, float(capsule[2]) * k - _dist(p, latest[capsule[0]], latest[capsule[1]]))
		fighter.global_position = Vector3.ZERO
		h.check(deepest <= MAX_SINK, "%s %s: the blade sinks at most %.0f mm into the body (%.0f mm)" % [role, clip, MAX_SINK * 1000.0, deepest * 1000.0])


## Samples the skeleton AFTER the skeleton modifiers (the limb IK) have run: poses read at any other time miss them.
static func _after_modifiers(sk: Skeleton3D, bones: Array) -> Dictionary:
	var latest := {}
	sk.skeleton_updated.connect(func():
		for bone in bones:
			latest[bone] = sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone)).origin)
	return latest


## Hands on the rails' plane and between the rails, feet near it, body in front of the ladder, at the pit's real ladder offset.
static func _ladder(h, body: PaladinModel, role: String, tree: SceneTree) -> void:
	var sk := body.skeleton
	var fighter := body.get_parent() as PaladinFighter
	fighter.limb_ik.force_ladder = 1.0
	body.player.play("climb", 0.0)
	var latest := _after_modifiers(sk, ["mixamorig_RightHand", "mixamorig_LeftHand", "mixamorig_Spine2", "mixamorig_RightFoot", "mixamorig_LeftFoot"])
	var fit: Vector2 = PaladinFighter.LADDER_FIT[role]
	var ladder_z := 0.42 - fit.x   # WorldConstants.LADDER_Z - inset, the climber stands at z = 0
	var worst_hand := 0.0
	var closest := INF
	var worst_side := 0.0
	var behind := true
	var feet_front := true
	for i in 24:
		body.player.seek(0.7333 * float(i) / 24.0, true)
		await tree.process_frame   # the skeleton runs its modifiers during the frame
		if i < 4:
			continue   # the IK has faded in
		for bone in ["mixamorig_RightHand", "mixamorig_LeftHand"]:
			var p: Vector3 = latest[bone]
			worst_hand = maxf(worst_hand, absf(p.z - ladder_z))
			closest = minf(closest, absf(p.z - ladder_z))
			worst_side = maxf(worst_side, absf(p.x) - LADDER_HALF)
		for bone in ["mixamorig_RightFoot", "mixamorig_LeftFoot"]:
			feet_front = feet_front and (latest[bone] as Vector3).z <= ladder_z - 0.03
		behind = behind and (latest["mixamorig_Spine2"] as Vector3).z < ladder_z - 0.04
	h.check(closest <= 0.02, "%s climb: the hands reach the rungs' plane (closest %.0f mm)" % [role, closest * 1000.0])
	h.check(worst_hand <= 0.04, "%s climb: with the IK the hands are pinned to the rungs' plane, never more than 4 cm off it (%.0f mm)" % [role, worst_hand * 1000.0])
	h.check(worst_side <= 0.0, "%s climb: the hands stay between the rails" % role)
	h.check(behind, "%s climb: the chest stays in front of the ladder" % role)
	h.check(feet_front, "%s climb: the feet stay in front of the rungs, not through them" % role)
	fighter.limb_ik.force_ladder = -1.0


## Walking and running with the body moving at the clip's own speed: no foot below the floor, and a foot standing on the floor does not skate (mean speed).
const SLIDE_MAX := 0.15   # walk; a run is allowed 0.40 (the legs cover more ground per frame)
const SLIDE_MAX_RUN := 0.40   # m/s of ground speed a foot standing on the floor (height < 1 cm) may have


static func _ground(h, fighter: PaladinFighter, body: PaladinModel, role: String, tree: SceneTree) -> void:
	var sk := body.skeleton
	var ik := fighter.limb_ik
	var dt := 1.0 / 60.0
	var latest := _after_modifiers(sk, ["mixamorig_LeftFoot", "mixamorig_RightFoot"])
	ik.fixed_dt = dt
	for clip in ["walk", "run"]:
		var speed := fighter._nominal_speed(clip)   # m/s the clip is foot-locked at, for this model's height
		for mode in [0.0, 1.0]:
			ik.force_ground = mode
			ik.reset_planted()
			fighter.global_position = Vector3.ZERO
			body.player.play(clip, 0.0)
			var length := body.player.get_animation(clip).length
			var lowest := INF
			var slide_sum := 0.0
			var slide_count := 0
			var last := {}
			for i in 150:
				fighter.global_position = Vector3(0, 0, speed * dt * float(i))
				body.player.seek(fmod(dt * float(i), length), true)
				await tree.process_frame
				var floor_y := (sk.global_transform * Vector3(0.0, ik.floor_height, 0.0)).y
				for bone in ["mixamorig_LeftFoot", "mixamorig_RightFoot"]:
					var p: Vector3 = latest[bone]
					if i > 30:
						lowest = minf(lowest, p.y - floor_y)
						if last.has(bone) and p.y - floor_y < 0.01 and (last[bone] as Vector3).y - floor_y < 0.01:
							slide_sum += Vector2(p.x - last[bone].x, p.z - last[bone].z).length() / dt
							slide_count += 1
					last[bone] = p
			var worst_slide := slide_sum / float(maxi(slide_count, 1))   # mean ground speed of a foot standing on the floor
			if mode == 1.0:
				h.check(lowest >= -0.005, "%s %s: with ground IK no foot sinks below the floor (%.0f mm)" % [role, clip, lowest * 1000.0])
				h.check(worst_slide <= (SLIDE_MAX_RUN if clip == "run" else SLIDE_MAX), "%s %s: with ground IK a planted foot slides %.0f cm/s at most on average (%.1f cm/s over %d frames)" % [role, clip, (SLIDE_MAX_RUN if clip == "run" else SLIDE_MAX) * 100.0, worst_slide * 100.0, slide_count])
	ik.force_ground = -1.0
	ik.fixed_dt = 0.0
	fighter.global_position = Vector3.ZERO
