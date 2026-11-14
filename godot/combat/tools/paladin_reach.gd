extends SceneTree
## Dev tool: compares, per role, how far the DRAWN sword tip reaches at the strike pose with where the simulation lets a blow land.
##   godot --headless --path godot --script res://combat/tools/paladin_reach.gd
## For each light/heavy clip the model is posed at PaladinClips.STRIKE and the blade tip is measured forward of the fighter origin.
## `needed` = the distance from the attacker's origin to the nearest point of a defender standing at the simulation's maximum hit range
## (reachM * reach_mult + the separation/hit radius difference), minus the forward motion the attack itself contributes.
func _initialize() -> void:
	await process_frame
	var rows := []
	for role in ["p", "n", "b", "r", "q", "k"]:
		var fighter := PaladinFighter.new()
		root.add_child(fighter)
		if not fighter.setup_free(role, 0, "w"):
			print(role, ": setup failed")
			continue
		await process_frame
		var blade: MeshInstance3D = null
		for node in fighter.find_children("Blade", "MeshInstance3D", true, false):
			blade = node
		var stats := FighterRoster.stats_for(role)
		var profile := FighterProfile.for_role(role)
		for clip in ["light_1", "heavy"]:
			var anim := fighter.player.get_animation(clip)
			fighter.player.play(clip)
			fighter.player.seek(PaladinClips.STRIKE * anim.length, true)
			fighter.player.pause()
			await process_frame
			await process_frame
			var tip: Vector3 = blade.global_transform * Vector3(0, 0, (blade.mesh as BoxMesh).size.z * 0.5)
			var forward := tip.z
			var lateral := tip.x
			print("%s %-7s tip forward %.2f m (lateral %.2f, height %.2f) | sim reachM %.2f, separation radius %.2f, hit radius %.2f" % [role, clip, forward, lateral, tip.y, float(stats["reachM"]), float(profile["radius"]), PaladinConfig.hit_radius(role, float(profile["radius"]))])
		fighter.queue_free()
		await process_frame
	PaladinModel.release_all()
	quit()
