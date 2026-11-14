extends SceneTree
## Dev tool: renders every imported environment model (godot/assets/environment) in a row to one PNG.
##   xvfb-run -a godot --path godot --rendering-driver opengl3 --resolution 1600x500 --script res://combat/tools/env_models_sheet.gd -- OUT.png
func _initialize() -> void:
	await process_frame
	var out := OS.get_cmdline_user_args()[0]
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.12, 0.13, 0.16)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color = Color(0.6, 0.62, 0.7)
	get_root().add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40, -30, 0); get_root().add_child(sun)
	var x := 0.0
	for d in ["chessboard", "stone_circle", "pillar", "archway", "torch_sconce", "banner", "ascent"]:
		var fbx := ""
		for f in DirAccess.get_files_at("res://assets/environment/" + d):
			if f.ends_with(".fbx"): fbx = f
		var inst: Node3D = (load("res://assets/environment/%s/%s" % [d, fbx]) as PackedScene).instantiate()
		get_root().add_child(inst)
		inst.position = Vector3(x, 0, 0)
		inst.rotation_degrees.y = 25.0
		x += 1.25
	var cam := Camera3D.new(); get_root().add_child(cam)
	cam.position = Vector3(3.7, 0.9, 4.2); cam.look_at(Vector3(3.7, 0.0, 0.0)); cam.fov = 45
	for _i in 6:
		await process_frame
	get_root().get_viewport().get_texture().get_image().save_png(out)
	quit()
