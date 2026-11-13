extends SceneTree
## Dev tool: renders clips of one paladin as a strip (rows = clips, columns = clip times) from a front 3/4 view.
##   xvfb-run -a godot --path godot --rendering-driver opengl3 --resolution 1500x900 --script res://combat/tools/paladin_strip.gd -- ROLE SIDE OUT.png clip1,clip2,.. [columns] [yaw]
func _initialize() -> void:
	await process_frame
	var a := OS.get_cmdline_user_args()
	var clips := a[3].split(",")
	var columns := int(a[4]) if a.size() > 4 else 5
	var yaw := float(a[5]) if a.size() > 5 else 35.0
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.16, 0.17, 0.2)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color = Color(0.6, 0.62, 0.7)
	get_root().add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40, -30, 0); sun.light_energy = 1.2; get_root().add_child(sun)
	for r in clips.size():
		for c in columns:
			var m := PaladinFighter.new()
			get_root().add_child(m)
			m.setup_free(a[0], 0, a[1])
			var anim_name: String = clips[r]
			m.position = Vector3(c * 1.6, -r * 2.2, 0)
			m.rotation_degrees.y = yaw
			if m.player.has_animation(anim_name):
				var t := m.player.get_animation(anim_name).length * float(c) / float(maxi(columns - 1, 1))
				m.player.play(anim_name)
				m.player.seek(t, true)
				m.player.pause()
	var cam := Camera3D.new(); get_root().add_child(cam)
	var cx := (columns - 1) * 0.8
	var cy := -(clips.size() - 1) * 1.1 + 0.9
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(clips.size() * 2.2, (columns * 1.6) * 0.6)
	cam.position = Vector3(cx, cy, 8.0); cam.look_at(Vector3(cx, cy, 0))
	for _i in 8:
		await process_frame
	get_root().get_viewport().get_texture().get_image().save_png(a[2])
	quit()
