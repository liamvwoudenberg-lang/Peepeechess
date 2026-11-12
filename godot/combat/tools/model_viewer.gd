extends SceneTree
## Dev tool: renders a character GLB (loaded at runtime, no import step) to a PNG.
##   xvfb-run -a godot --path godot --rendering-driver opengl3 --script res://combat/tools/model_viewer.gd -- \
##       GLB_PATH OUT_PNG [clip] [time_seconds] [yaw_degrees] [distance]
func _initialize() -> void:
	await process_frame
	var a := OS.get_cmdline_user_args()
	var doc := GLTFDocument.new(); var state := GLTFState.new()
	if doc.append_from_file(a[0], state) != OK:
		printerr("cannot load ", a[0]); quit(1); return
	var model := doc.generate_scene(state)
	var holder := Node3D.new(); get_root().add_child(holder); holder.add_child(model)
	holder.rotation_degrees.y = float(a[4]) if a.size() > 4 else 25.0
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.16, 0.17, 0.2)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color = Color(0.5, 0.52, 0.6)
	get_root().add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40, -30, 0); sun.light_energy = 1.3; get_root().add_child(sun)
	var rim := DirectionalLight3D.new(); rim.rotation_degrees = Vector3(-20, 150, 0); rim.light_energy = 0.6; get_root().add_child(rim)
	var floor_mesh := MeshInstance3D.new(); var disc := CylinderMesh.new(); disc.top_radius = 1.5; disc.bottom_radius = 1.5; disc.height = 0.02
	floor_mesh.mesh = disc; floor_mesh.position.y = -0.01; get_root().add_child(floor_mesh)
	var cam := Camera3D.new(); get_root().add_child(cam)
	var dist := float(a[5]) if a.size() > 5 else 4.2
	cam.position = Vector3(0, 1.1, dist); cam.look_at(Vector3(0, 1.0, 0)); cam.fov = 40
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if players.size() > 0 and a.size() > 2 and a[2] != "":
		var ap: AnimationPlayer = players[0]
		ap.play(a[2]); ap.seek(float(a[3]) if a.size() > 3 else 0.0, true); ap.pause()
	for _i in 6:
		await process_frame
	get_root().get_viewport().get_texture().get_image().save_png(a[1])
	quit()
