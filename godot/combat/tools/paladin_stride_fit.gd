extends SceneTree
## Dev tool: measures the ground speed each paladin role needs in the Walking / Running clips (backward speed of the stance foot relative to the body) at the model height; divide by height / 1.7 to get PaladinModel.STANCE_SPEED.
##   godot --headless --path godot --script res://combat/tools/paladin_stride_fit.gd
func _initialize():
	await process_frame
	for role in ["p", "n", "b", "r", "q", "k"]:
		var f := PaladinFighter.new()
		root.add_child(f)
		f.setup_free(role, 0, "w")
		var body := f.model as PaladinModel
		var sk := body.skeleton
		f.limb_ik.force_ground = 0.0
		var line := "role %s height %.2f:" % [role, body.height]
		for clip in ["walk", "run"]:
			body.player.play(clip, 0.0)
			var length := body.player.get_animation(clip).length
			var n := 120
			var prev := {}
			var sum := 0.0
			var count := 0
			var floor_y := (sk.global_transform * Vector3(0.0, f.limb_ik.floor_height, 0.0)).y
			var lows := []
			var samples := []
			for i in n + 1:
				body.player.seek(length * float(i) / float(n), true)
				await process_frame
				for bone in ["mixamorig_LeftFoot", "mixamorig_RightFoot"]:
					var p: Vector3 = sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone)).origin
					samples.append([bone, i, p])
			# stance = the lowest 35% of foot heights per foot
			for bone in ["mixamorig_LeftFoot", "mixamorig_RightFoot"]:
				var mine := []
				for s in samples:
					if s[0] == bone:
						mine.append(s)
				var heights := []
				for s in mine:
					heights.append((s[2] as Vector3).y)
				heights.sort()
				var cut: float = heights[int(heights.size() * 0.35)]
				for j in range(1, mine.size()):
					if (mine[j][2] as Vector3).y <= cut and (mine[j - 1][2] as Vector3).y <= cut:
						var dz: float = (mine[j][2] as Vector3).z - (mine[j - 1][2] as Vector3).z
						sum += -dz / (length / float(n))
						count += 1
			var speed := sum / maxf(float(count), 1.0)
			line += "  %s needs %.2f m/s (nominal %.2f)" % [clip, speed, f._nominal_speed(clip)]
		print(line)
		f.queue_free()
		await process_frame
	quit()
