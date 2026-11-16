extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for role in ["p", "n", "b", "r", "q", "k"]:
		for side in ["w", "b"]:
			var fighter := PaladinFighter.new()
			root.add_child(fighter)
			assert(fighter.setup_free(role, 0, side))
			var clip := fighter.player.get_animation("light_1")
			assert(clip != null and absf(clip.length - 37.0 / 24.0) < 0.01)
			assert(clip.find_track(NodePath(PaladinClips._track_prefix(fighter.player) + "mixamorig_RightArm"), Animation.TYPE_ROTATION_3D) >= 0)
			for name in ["idle", "block", "dodge", "hit_react_light", "hit_react_heavy", "defeat"]:
				var actual := fighter.player.get_animation(name)
				var filename: String = PaladinModel.FILES[role]
				var reference := load("res://assets/paladins/animations/%s_%s.res" % [filename, name]) as Animation
				assert(actual != null and reference != null and is_equal_approx(actual.length, reference.length))
			var remapped := fighter._remap_clip_time("light_1", 0.25, 0.25)
			assert(is_equal_approx(remapped.x, PaladinClips.STRIKE))
			var expected: float = 1.6 / ((0.325442 / 0.733333) * fighter.model.height / 1.7)
			assert(is_equal_approx(fighter.ladder_playback_speed(1.6), expected))
			fighter.free()
	print("PASS: retargeted combat clips and climb playback for six roles and both sides")
	quit()
