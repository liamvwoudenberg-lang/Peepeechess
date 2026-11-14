extends SceneTree

const W := preload("res://world/world_constants.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for role in ["p", "n", "b", "r", "q", "k"]:
		var f := PaladinFighter.new()
		root.add_child(f)
		assert(f.setup_free(role, 0, "w"))
		f.set_props_stowed(1.0)
		var body := f.model as PaladinModel
		var sk := body.skeleton
		var fit := f.ladder_fit()
		var anim := f.player.get_animation("climb")
		f.player.play("climb")
		var max_grid_error := 0.0
		var max_depth_error := 0.0
		for step in 9:
			var u := float(step) / 8.0
			f.player.seek(anim.length * u, true)
			sk.force_update_all_bone_transforms()
			# Sample limbs during their planted portions, not while reaching.
			for spec in [["LeftHand", 0.0, 0.5, 0.035], ["RightHand", 0.5, 1.0, 0.035], ["LeftFoot", 0.0, 0.25, 0.055], ["RightFoot", 0.25, 0.75, 0.055]]:
				if u < spec[1] or u > spec[2]:
					continue
				var index := sk.find_bone("mixamorig_" + String(spec[0]))
				var p := f.to_local(sk.global_transform * sk.get_bone_global_pose(index).origin)
				assert(absf(p.x) < W.LADDER_HALF_WIDTH + 0.08)
				var height := p.y + 0.325442 * body.height / PaladinModel.SOURCE_HEIGHT * u - float(spec[3])
				var grid := (height - W.BOARD_DEPTH - fit.y) / fit.x - 0.5
				max_grid_error = maxf(max_grid_error, absf(grid - round(grid)) * fit.x)
				if String(spec[0]).ends_with("Hand"):
					max_depth_error = maxf(max_depth_error, absf(p.z - (W.LADDER_Z - fit.z)))
		assert(max_grid_error < 0.10, "%s rung error %s" % [role, max_grid_error])
		assert(max_depth_error < 0.14, "%s hand depth error %s" % [role, max_depth_error])
		print(role, " max planted-joint rung error ", snappedf(max_grid_error, 0.001), "m, hand depth error ", snappedf(max_depth_error, 0.001), "m")
		f.free()
	print("PASS: paladin ladder alignment samples")
	quit()
