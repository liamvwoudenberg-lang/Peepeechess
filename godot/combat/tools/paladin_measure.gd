extends SceneTree
## Dev tool: measures every paladin model's real body (at its in-game height) and checks the Walking / Running clips for root motion.
##   godot --headless --path godot --script res://combat/tools/paladin_measure.gd
## Prints one line per role: height, shoulder half-width, body half-depth (97th percentile of |z| in the torso band), arm length
## (shoulder -> hand), and the horizontal drift of the Hips over one loop of Walking / Running (0 = in place, no root motion).
func _initialize() -> void:
	await process_frame
	for role in ["p", "n", "b", "r", "q", "k"]:
		var height: float = float(PaladinFighter.HEIGHTS.get(role, 1.7))
		var m := PaladinModel.create(role, "w", height)
		if m == null:
			print(role, ": no model")
			continue
		root.add_child(m)
		await process_frame
		var sk := m.skeleton
		var scale: float = m.get_child(0).scale.x
		var to_world := sk.global_transform
		var rest := func(bone: String) -> Vector3:
			var i := sk.find_bone(bone)
			return (to_world * sk.get_bone_global_rest(i).origin) if i >= 0 else Vector3.ZERO
		var l_arm: Vector3 = rest.call("mixamorig_LeftArm")
		var r_arm: Vector3 = rest.call("mixamorig_RightArm")
		var l_hand: Vector3 = rest.call("mixamorig_LeftHand")
		var half_width := absf(l_arm.x - r_arm.x) * 0.5
		# torso depth from the mesh (bind pose): |z| of vertices between 30% and 80% of the height
		var zs: Array = []
		var xs_waist: Array = []
		for mi in m.meshes:
			var arrays := mi.mesh.surface_get_arrays(0)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v in verts:
				var w: Vector3 = mi.global_transform * v
				if w.y > height * 0.30 and w.y < height * 0.80:
					zs.append(absf(w.z))
				if w.y > height * 0.45 and w.y < height * 0.55 and absf(w.x) < half_width * 0.95:
					xs_waist.append(absf(w.x))
		zs.sort()
		xs_waist.sort()
		var half_depth: float = zs[int(zs.size() * 0.97)] if zs.size() > 0 else 0.0
		var waist: float = xs_waist[int(xs_waist.size() * 0.95)] if xs_waist.size() > 0 else 0.0
		var line := "%s h=%.2f scale=%.3f shoulder_half_width=%.3f waist_half_width=%.3f half_depth=%.3f arm_length=%.3f" % [role, height, scale, half_width, waist, half_depth, l_arm.distance_to(l_hand)]
		for clip in ["Walking", "Running"]:
			var drift := _hips_drift(m.player, clip)
			line += " %s_hips_drift=(%.3f, %.3f)" % [clip, drift.x, drift.y]
		print(line)
		m.queue_free()
		await process_frame
	PaladinModel.release_all()
	quit()

## Horizontal (x, z) displacement of the hips position track between the first and last key of a clip, in model units.
func _hips_drift(player: AnimationPlayer, clip: String) -> Vector2:
	if player == null or not player.has_animation(clip):
		return Vector2(-1, -1)
	var anim := player.get_animation(clip)
	for t in anim.get_track_count():
		var path := String(anim.track_get_path(t))
		if anim.track_get_type(t) == Animation.TYPE_POSITION_3D and path.ends_with(":mixamorig_Hips"):
			var n := anim.track_get_key_count(t)
			if n < 2:
				return Vector2.ZERO
			var a: Vector3 = anim.track_get_key_value(t, 0)
			var b: Vector3 = anim.track_get_key_value(t, n - 1)
			return Vector2(b.x - a.x, b.z - a.z)
	return Vector2(-2, -2)
