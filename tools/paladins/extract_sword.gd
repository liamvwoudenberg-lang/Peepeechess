extends SceneTree

const CLIPS := {
	"Sword_slash": "light_1", "Idle_with_a_sword": "idle", "Block_with_the_sword": "block",
	"Dodge_roll": "dodge", "Hit_to_the_chest": "hit_react_light", "Hit_knockback": "hit_react_heavy",
	"Death_fall_backwards": "defeat",
}

func _initialize() -> void:
	for role in ["pawn", "knight", "bishop", "rook", "queen", "king"]:
		for source in CLIPS:
			var state := GLTFState.new()
			var document := GLTFDocument.new()
			var path := "/tmp/pp_retarget_%s_%s.glb" % [role, source]
			if document.append_from_file(path, state) != OK:
				push_error("Unable to import %s" % path)
				quit(1)
				return
			var root := document.generate_scene(state)
			var players := root.find_children("*", "AnimationPlayer", true, false)
			if players.is_empty() or not players[0].has_animation("CC0_Retargeted"):
				push_error("Missing animation: %s" % path)
				quit(1)
				return
			var anim: Animation = players[0].get_animation("CC0_Retargeted").duplicate(true)
			if source == "Sword_slash":
				# Source impact is approximately frame 10 of 37. Moving later keys
				# in reverse preserves key order while aligning with the strike marker.
				var source_impact := 10.0 / 37.0
				for track in anim.get_track_count():
					for key in range(anim.track_get_key_count(track) - 1, -1, -1):
						var u := anim.track_get_key_time(track, key) / anim.length
						var mapped := u / source_impact * 0.36 if u <= source_impact else 0.36 + (u - source_impact) / (1.0 - source_impact) * 0.64
						anim.track_set_key_time(track, key, mapped * anim.length)
			if source == "Idle_with_a_sword":
				anim.loop_mode = Animation.LOOP_LINEAR
				for track in anim.get_track_count():
					var n := anim.track_get_key_count(track)
					if n > 1:
						anim.track_set_key_value(track, n - 1, anim.track_get_key_value(track, 0))
			if source == "Block_with_the_sword":
				# Blocking is held by the simulation. Hold the guard pose rather than
				# repeat the source's one-shot block reaction for the whole hold.
				var held := Animation.new()
				held.length = 1.0
				held.loop_mode = Animation.LOOP_LINEAR
				for track in anim.get_track_count():
					if anim.track_get_type(track) == Animation.TYPE_ROTATION_3D:
						var index := held.add_track(Animation.TYPE_ROTATION_3D)
						held.track_set_path(index, anim.track_get_path(track))
						var pose := anim.rotation_track_interpolate(track, anim.length * 0.45)
						held.rotation_track_insert_key(index, 0.0, pose)
						held.rotation_track_insert_key(index, 1.0, pose)
				anim = held
			var err := ResourceSaver.save(anim, "res://assets/paladins/animations/%s_%s.res" % [role, CLIPS[source]])
			root.free()
			if err != OK:
				quit(1)
				return
			print(role, " ", source, " ", anim.length)
	quit()
