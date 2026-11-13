extends SceneTree
## Dev tool: renders every paladin in both colours (idle / walk / run poses) to a PNG contact sheet.
##   xvfb-run -a godot --path godot --rendering-driver opengl3 --script res://combat/tools/paladin_sheet.gd -- OUT.png [clip] [time]
func _initialize() -> void:
	await process_frame
	var a := OS.get_cmdline_user_args()
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.16, 0.17, 0.2)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color = Color(0.55, 0.57, 0.65)
	get_root().add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40, -30, 0); sun.light_energy = 1.3; get_root().add_child(sun)
	var x := 0.0
	for side in ["w", "b"]:
		x = -3.0
		for role in ["p", "n", "b", "r", "q", "k"]:
			var m := PaladinModel.create(role, side, 1.0)
			if m == null:
				continue
			get_root().add_child(m)
			m.position = Vector3(x, 0.0 if side == "w" else 0.0, 0.0 if side == "w" else -1.4)
			m.play(a[2] if a.size() > 2 else "idle")
			if a.size() > 3 and m.player != null and m.player.is_playing():
				m.player.seek(float(a[3]), true)
				m.player.pause()
			x += 1.2
	var cam := Camera3D.new(); get_root().add_child(cam)
	cam.position = Vector3(0.6, 1.4, 5.0); cam.look_at(Vector3(0.6, 0.55, -0.7)); cam.fov = 42
	for _i in 6:
		await process_frame
	get_root().get_viewport().get_texture().get_image().save_png(a[0])
	quit()
