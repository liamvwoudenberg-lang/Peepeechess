extends SceneTree
## Dev tool: renders the generated world assets (godot/assets/world) and the new ladder clips to PNGs. GLBs are loaded at
## runtime, no editor import needed.
##   xvfb-run -a -s "-screen 0 1280x800x24" godot --path godot --rendering-driver opengl3 \
##       --script res://combat/tools/world_viewer.gd -- MODE OUT_PNG [key=value ...]
## MODE: pieces (cam=top|45|low [lod=1] [black=1]) | trapdoor (open=0..1 cam=top|45|under) | ladder | shaft (cam=top|side) |
##       board (cam=top|45) | climb (class=pawn clip=climb t=0.3 [ladder=1]) | fall (class=pawn clip=drop_fall t=0.2)
const W := "res://assets/world/"
const CLASSES := ["pawn", "knight", "bishop", "rook", "queen", "king"]
var args: Dictionary = {}
var root3d: Node3D
var cam: Camera3D


func _initialize() -> void:
	await process_frame
	var a := OS.get_cmdline_user_args()
	if a.size() < 2:
		printerr("usage: MODE OUT_PNG [key=value ...]")
		quit(1)
		return
	for i in range(2, a.size()):
		var kv := String(a[i]).split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	root3d = Node3D.new()
	get_root().add_child(root3d)
	_environment()
	match a[0]:
		"pieces": _pieces()
		"piece": _piece()
		"trapdoor": _trapdoor()
		"ladder": _ladder()
		"shaft": _shaft()
		"board": _board()
		"climb": _climb()
		"fall": _climb()
		_: printerr("unknown mode ", a[0])
	for _i in 8:
		await process_frame
	get_root().get_viewport().get_texture().get_image().save_png(a[1])
	quit()


func _environment() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("14272e") if args.get("bg", "") == "" else Color(args["bg"])
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("b5d0d1")
	env.environment.ambient_light_energy = float(args.get("ambient", 0.55))
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	get_root().add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-55, -25, 0)
	key.light_color = Color("fff0d5")
	key.light_energy = float(args.get("key", 1.1))
	get_root().add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30, 145, 0)
	fill.light_color = Color("a2c5df")
	fill.light_energy = 0.35
	get_root().add_child(fill)
	cam = Camera3D.new()
	cam.fov = 35
	get_root().add_child(cam)


func _load(path: String) -> Node3D:
	var n := CharacterModel.load_scene(path)
	if n == null:
		printerr("cannot load ", path)
		n = Node3D.new()
	return n


func _place(path: String, pos: Vector3, yaw_deg: float = 0.0, parent: Node = null) -> Node3D:
	var n := _load(path)
	(parent if parent != null else root3d).add_child(n)
	n.position = pos
	n.rotation_degrees.y = yaw_deg
	return n


func _look(pos: Vector3, target: Vector3, up: Vector3 = Vector3.UP) -> void:
	cam.position = pos
	cam.look_at(target, up)


func _tile(pos: Vector3, light: bool) -> void:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.995, 0.08, 0.995)
	m.mesh = box
	var mat := StandardMaterial3D.new()
	var tile_path: String = W + "materials/tile_%s.tres" % ("light" if light else "dark")
	if ResourceLoader.exists(tile_path):
		mat = load(tile_path)
	else:
		mat.albedo_color = Color("b7b9a5") if light else Color("496e70")
	m.material_override = mat
	m.position = pos
	root3d.add_child(m)


func _pieces() -> void:
	var cols := ["pawn", "knight", "bishop", "rook", "queen", "king"]
	var lod := "_lod1" if args.get("lod", "0") == "1" else ""
	var sides := ["light", "dark"]
	for r in 2:
		for c in 6:
			var pos := Vector3((c - 2.5) * 1.0, 0.0, (r - 0.5) * 1.0)
			var tile_light := (c + r) % 2 == (1 if args.get("swap", "0") == "1" else 0)
			_tile(pos + Vector3(0, 0.0, 0), tile_light)
			var side: String = sides[r]
			var p := _place(W + "pieces/%s_%s%s.glb" % [cols[c], side, lod], pos + Vector3(0, 0.04, 0))
			if args.get("yaw", "") != "":
				p.rotation_degrees.y = float(args["yaw"])
	match args.get("cam", "top"):
		"top": _look(Vector3(0, 9.2, 0.001), Vector3.ZERO, Vector3(0, 0, -1))
		"45": _look(Vector3(0, 5.6, 5.6), Vector3(0, 0.45, 0.1))
		_: _look(Vector3(0, 1.0, 7.5), Vector3(0, 0.5, 0.0))


func _plinth_ring(inner: float, outer: float, y_top: float, y_bottom: float) -> void:
	## Four boxes forming a square ring (stands in for the board body around a pit hole)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("2b2d30")
	var h := y_top - y_bottom
	var mid := (y_top + y_bottom) * 0.5
	var span := outer * 2.0
	for sgn in [-1.0, 1.0]:
		var a := MeshInstance3D.new()
		var ba := BoxMesh.new()
		ba.size = Vector3(span, h, outer - inner)
		a.mesh = ba
		a.material_override = mat
		a.position = Vector3(0, mid, sgn * (inner + outer) * 0.5)
		root3d.add_child(a)
		var b := MeshInstance3D.new()
		var bb := BoxMesh.new()
		bb.size = Vector3(outer - inner, h, inner * 2.0)
		b.mesh = bb
		b.material_override = mat
		b.position = Vector3(sgn * (inner + outer) * 0.5, mid, 0)
		root3d.add_child(b)


func _piece() -> void:
	## one piece large: role=knight side=light|dark yaw=-60 (degrees about Y) cam=side|top
	_tile(Vector3.ZERO, args.get("tile", "light") == "light")
	var p := _place(W + "pieces/%s_%s.glb" % [args.get("role", "knight"), args.get("side", "light")], Vector3(0, 0.04, 0), float(args.get("yaw", -50)))
	cam.fov = 30
	if args.get("cam", "side") == "top":
		_look(Vector3(0, 3.2, 0.001), Vector3(0, 0.0, 0), Vector3(0, 0, -1))
	else:
		_look(Vector3(0, 0.9, 3.4), Vector3(0, 0.55, 0))


func _trapdoor() -> void:
	var open := float(args.get("open", 0.0))
	var side: String = args.get("side", "light")
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			if dx == 0 and dz == 0:
				continue
			_tile(Vector3(dx, 0, dz), ((dx + dz + 100) % 2 == 0) == (side == "light"))
	_plinth_ring(0.5, 1.5, -0.04, -0.8)
	_place(W + "pit/shaft_rim.glb", Vector3.ZERO)
	var td := _place(W + "pit/trapdoor_%s.glb" % side, Vector3.ZERO)
	var hl := td.find_child("hinge_left", true, false)
	var hr := td.find_child("hinge_right", true, false)
	if hl != null:
		hl.rotation_degrees.z = -92.0 * open
	if hr != null:
		hr.rotation_degrees.z = 92.0 * open
	for i in 3:
		_place(W + "pit/shaft_wall_segment.glb", Vector3(0, -1.54 - i, 0))
	match args.get("cam", "45"):
		"top": _look(Vector3(0, 5.0, 0.001), Vector3(0, 0, 0), Vector3(0, 0, -1))
		"under": _look(Vector3(0.0, -3.0, 0.15), Vector3(0, -0.1, 0), Vector3(0, 0, -1))
		_: _look(Vector3(0, 3.4, 3.0), Vector3(0, -0.3, 0))


func _ladder() -> void:
	_place(W + "pit/ladder_full_10m.glb", Vector3.ZERO)
	var wall := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 12.0, 0.2)
	wall.mesh = box
	wall.position = Vector3(0, -4.6, 0.25)
	root3d.add_child(wall)
	match args.get("cam", "full"):
		"full": _look(Vector3(2.0, -4.5, -9.5), Vector3(0, -4.5, 0), Vector3.UP)
		"top": _look(Vector3(1.5, 0.6, -2.2), Vector3(0, -0.3, 0), Vector3.UP)
		_: _look(Vector3(1.4, -8.8, -2.2), Vector3(0, -8.6, 0), Vector3.UP)


func _shaft() -> void:
	_place(W + "pit/shaft_rim.glb", Vector3.ZERO)
	_place(W + "pit/shaft_wall_segment.glb", Vector3(0, -1.54, 0))
	_place(W + "pit/shaft_wall_segment.glb", Vector3(0, -2.54, 0))
	_place(W + "pit/shaft_wall_segment.glb", Vector3(0, -3.54, 0))
	var cap := _place(W + "pit/chamber_ceiling.glb", Vector3(0, -3.54, 0))
	_place(W + "pit/ladder_top.glb", Vector3(0, 0, 0.42))
	var cone := _place(W + "pit/light_cone.glb", Vector3(0, -0.04, 0))
	cone.scale = Vector3(1, 3.5, 1)
	for mi in cone.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = load(W + "materials/light_cone.tres")
	match args.get("cam", "side"):
		"top": _look(Vector3(0, 8.0, 0.001), Vector3(0, 0, 0), Vector3(0, 0, -1))
		"under": _look(Vector3(5.0, -9.0, 5.0), Vector3(0, -4.5, 0))
		_: _look(Vector3(6.0, -2.0, 7.0), Vector3(0, -2.4, 0))


func _board() -> void:
	for at in 64:
		_tile(Vector3(at % 8 - 3.5, 0, 3.5 - at / 8), (at % 8 + at / 8) % 2 == 1)
	_place(W + "board/board_frame.glb", Vector3.ZERO)
	_place(W + "board/board_plaques.glb", Vector3.ZERO)
	var roles := ["rook", "knight", "bishop", "queen", "king", "bishop", "knight", "rook"]
	for i in 8:
		_place(W + "pieces/%s_dark.glb" % roles[i], Vector3(i - 3.5, 0.04, 3.5))
		_place(W + "pieces/pawn_dark.glb", Vector3(i - 3.5, 0.04, 2.5))
		_place(W + "pieces/%s_light.glb" % roles[i], Vector3(i - 3.5, 0.04, -3.5), 180.0)
		_place(W + "pieces/pawn_light.glb", Vector3(i - 3.5, 0.04, -2.5), 180.0)
	match args.get("cam", "top"):
		"top": _look(Vector3(0, 13.0, 0.001), Vector3.ZERO, Vector3(0, 0, -1))
		_: _look(Vector3(0, 9.0, 9.5), Vector3(0, 0, 0.3))


func _climb() -> void:
	var cls: String = args.get("class", "pawn")
	var clip: String = args.get("clip", "climb")
	var t := float(args.get("t", 0.0))
	var on_ladder: bool = args.get("ladder", "1") == "1"
	var y := 0.0
	if on_ladder:
		_place(W + "pit/ladder_full_10m.glb", Vector3(0, 0, 0.42), 0.0)
		# character origin: halfway between two rungs at phase 0 (see world/README.md)
		y = -4.0 + (0.4167 * t if clip == "climb" else 0.0)
		if clip == "ladder_idle":
			y = -4.0
	var model := CharacterModel.new()
	root3d.add_child(model)
	model.setup_free(CharacterModel.CLASS_NAMES.keys()[CLASSES.find(cls)], 0, "w")
	model.position = Vector3(0, y, 0)
	if model.player != null and model.player.has_animation(clip):
		model.player.play(clip)
		model.player.seek(t, true)
		model.player.pause()
	else:
		printerr("clip missing ", clip)
	var fy := y + 1.0
	if args.get("cam", "side") == "side":
		_look(Vector3(float(args.get("cx", 2.6)), fy + float(args.get("cy", 0.0)), float(args.get("cz", 0.5))), Vector3(0, fy, 0.3))
	elif args.get("cam") == "front":
		_look(Vector3(0.3, fy + 0.2, -2.6), Vector3(0, fy, 0.4))
	else:
		_look(Vector3(2.6, fy + 1.2, -2.8), Vector3(0, fy, 0.3))
	cam.fov = 38
