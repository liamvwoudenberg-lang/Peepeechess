extends SceneTree
## Dev tool: prints the paladin skeleton (bone, parent, global rest position) and the GLB animation tracks.
##   godot --headless --path godot --script res://combat/tools/paladin_bones.gd -- <role>
func _initialize() -> void:
	await process_frame
	var role := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "p"
	var m := PaladinModel.create(role, "w", 1.7)
	get_root().add_child(m)
	var sk := m.skeleton
	print("bones: ", sk.get_bone_count())
	for i in sk.get_bone_count():
		var g := sk.get_bone_global_rest(i)
		print("%2d %-34s parent %2d  pos (%.2f %.2f %.2f)" % [i, sk.get_bone_name(i), sk.get_bone_parent(i), g.origin.x, g.origin.y, g.origin.z])
	for n in m.player.get_animation_list():
		var a := m.player.get_animation(n)
		var kinds := {}
		for t in a.get_track_count():
			var k := str(a.track_get_type(t))
			kinds[k] = int(kinds.get(k, 0)) + 1
		print("anim ", n, " len ", a.length, " tracks ", a.get_track_count(), " ", kinds)
	var w := m.player.get_animation("Walking")
	for i in 6:
		print("track ", w.track_get_path(i), " type ", w.track_get_type(i), " keys ", w.track_get_key_count(i))
	var hp := -1
	for i in w.get_track_count():
		if w.track_get_type(i) == Animation.TYPE_POSITION_3D:
			print("pos track ", w.track_get_path(i), " first ", w.track_get_key_value(i, 0), " mid ", w.track_get_key_value(i, w.track_get_key_count(i) / 2))
	quit()
