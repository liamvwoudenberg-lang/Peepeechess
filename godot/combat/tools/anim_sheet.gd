extends SceneTree
## Contact sheet of a character animation (dev tool for the visual review in ANIMATION_INTEGRITY.md). Frames are posed by hand
## (AnimationPlayer seek + advance(0)), so the sheet shows exactly the sampled poses.
##
##   xvfb-run -a -s "-screen 0 1280x800x24" godot --path godot --rendering-driver opengl3 --script res://combat/tools/anim_sheet.gd -- \
##       class=knight clips=light_1:6,12,18;heavy:20,36,50 out=/tmp/sheet.png [lod=0] [cols=6] [yaw=35] [tile=300x380] [dist=4.6] [assets=DIR/characters]
## Tiles run row-major in the order given; the clip/frame list is printed.
func _initialize() -> void:
	await process_frame
	var a := {"class": "knight", "clips": "idle:0", "out": "/tmp/anim_sheet.png", "lod": "0", "cols": "6", "yaw": "35", "tile": "300x380", "dist": "4.6", "look": "1.0"}
	for token in OS.get_cmdline_user_args():
		var kv: PackedStringArray = String(token).split("=", true, 1)
		if kv.size() == 2:
			a[kv[0]] = kv[1]
	if a.has("assets"):
		CharacterModel.characters_root = a["assets"]
	var role := ""
	for r in CharacterModel.CLASS_NAMES:
		if CharacterModel.CLASS_NAMES[r] == a["class"]:
			role = r
	var tiles: Array = []
	for part in String(a["clips"]).split(";"):
		var cf: PackedStringArray = part.split(":")
		for f in cf[1].split(","):
			tiles.append([cf[0], int(f)])
	var size := Vector2i(int(String(a["tile"]).split("x")[0]), int(String(a["tile"]).split("x")[1]))
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.2, 0.22, 0.26)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.57, 0.65)
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -28, 0)
	sun.light_energy = 1.3
	vp.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8, 8)
	floor_mesh.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.32, 0.32, 0.34)
	floor_mesh.material_override = fm
	vp.add_child(floor_mesh)
	var holder := Node3D.new()
	vp.add_child(holder)
	var m := CharacterModel.new()
	holder.add_child(m)
	if not m.setup_free(role, int(a["lod"])):
		printerr("cannot load ", a["class"])
		quit(1)
		return
	m.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	holder.rotation_degrees.y = float(a["yaw"])
	var cam := Camera3D.new()
	cam.fov = 40
	vp.add_child(cam)
	var dist := float(a["dist"])
	cam.position = Vector3(0, float(a["look"]) + 0.15, dist)
	cam.look_at(Vector3(0, float(a["look"]), 0))
	var cols := int(a["cols"])
	var rows := int(ceil(float(tiles.size()) / float(cols)))
	var sheet := Image.create(size.x * cols, size.y * rows, false, Image.FORMAT_RGBA8)
	for i in tiles.size():
		var clip: String = tiles[i][0]
		var frame: int = tiles[i][1]
		var anim := m.player.get_animation(clip)
		anim.loop_mode = Animation.LOOP_NONE
		m.player.play(clip, 0.0)
		m.player.seek(minf(float(frame) / 60.0, anim.length), true)
		m.player.advance(0.0)
		for _k in 4:
			await process_frame
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, size), Vector2i((i % cols) * size.x, (i / cols) * size.y))
		print("tile %d: %s frame %d" % [i, clip, frame])
	sheet.save_png(a["out"])
	print("wrote ", a["out"])
	quit()
