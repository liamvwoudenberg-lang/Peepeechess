class_name BoardScenery
extends RefCounted
## Builds the castle-courtyard look around the 3D chess board: marble / slate square materials, the carved frame trim, a stepped stone
## dais, courtyard paving, battlement walls with banners, corner pillars and flickering braziers. All numbers live in BoardLook.
##
## Everything is generated (no downloads, fixed seeds). Stone uses TRIPLANAR world-space mapping at a fixed texel density, so no wall,
## step or floor can show a stretched texture however it is sized. Nothing is built inside the play area (|x|,|z| < 4.45): the
## dais starts at the frame edge and the props stand outside it, so the board stays clear for pieces, marks and the pit trapdoor.
## Scenery is parented under ONE Node3D ("Scenery") so BoardThemeView (which walks the board's direct children) never sees it.

const L := preload("res://world/board_look.gd")

static var _cache: Dictionary = {}


## ---- procedural textures ---------------------------------------------------------------------------------------------------------
static func _noise(seed_value: int, frequency: float, kind: int = FastNoiseLite.TYPE_SIMPLEX_SMOOTH, fractal: int = FastNoiseLite.FRACTAL_FBM, octaves: int = 4) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.noise_type = kind
	n.frequency = frequency
	n.fractal_type = fractal
	n.fractal_octaves = octaves
	return n


## Marble (light) or slate (dark): a flat base colour with SUBTLE veining. Returns {albedo, normal}. Repeat-free per tile: each
## square uses its own uv offset, and the vein contrast is deliberately low so the board never looks blotchy.
static func _square_textures(light: bool) -> Dictionary:
	var key := "sq_light" if light else "sq_dark"
	if _cache.has(key):
		return _cache[key]
	var size: int = L.TEXTURE_SIZE
	var base: Color = L.LIGHT_SQUARE if light else L.DARK_SQUARE
	var vein: Color = L.LIGHT_VEIN if light else L.DARK_VEIN
	var ridge := _noise(17 if light else 29, 0.012 if light else 0.03, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, FastNoiseLite.FRACTAL_RIDGED, 4)
	var grain := _noise(71 if light else 83, 0.09, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, FastNoiseLite.FRACTAL_FBM, 3)
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var height := Image.create(size, size, false, Image.FORMAT_L8)
	for y in size:
		for x in size:
			var r := ridge.get_noise_2d(x, y) * 0.5 + 0.5          # 0..1, thin bright ridges
			var line := smoothstep(0.82, 0.98, r) * (0.55 if light else 0.4)
			var g := grain.get_noise_2d(x, y) * 0.04
			var c := base.lerp(vein, clampf(line, 0.0, 1.0))
			c = Color(clampf(c.r + g, 0, 1), clampf(c.g + g, 0, 1), clampf(c.b + g, 0, 1))
			img.set_pixel(x, y, c)
			height.set_pixel(x, y, Color(r * 0.35 + (g * 4.0 + 0.5) * 0.65, 0, 0))
	height.bump_map_to_normal_map(L.SQUARE_NORMAL_STRENGTH * 4.0)
	var out := {"albedo": ImageTexture.create_from_image(img), "normal": ImageTexture.create_from_image(height)}
	_cache[key] = out
	return out


## Seamless-ish flagstone / block texture: rows of offset stones with dark mortar, per-stone tint and fine grain. Tileable by construction
## (all noise is sampled modulo the texture size through coordinate wrapping of the brick grid).
static func _stone_textures(key: String, size: int, cols: int, rows: int, seed_value: int, tint: Color) -> Dictionary:
	if _cache.has(key):
		return _cache[key]
	var grain := _noise(seed_value, 0.07, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, FastNoiseLite.FRACTAL_FBM, 4)
	grain.set_meta("t", 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var tone := []
	for i in rows * cols * 2:
		tone.append(rng.randf_range(0.78, 1.08))
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var height := Image.create(size, size, false, Image.FORMAT_L8)
	var bw := float(size) / cols
	var bh := float(size) / rows
	var mortar := maxf(2.0, size / 128.0)
	for y in size:
		var row := int(y / bh)
		var offset := bw * 0.5 if row % 2 == 1 else 0.0
		for x in size:
			var xx := fposmod(x + offset, float(size))
			var col := int(xx / bw)
			var fx := fposmod(xx, bw)
			var fy := fposmod(float(y), bh)
			var edge := minf(minf(fx, bw - fx), minf(fy, bh - fy))
			var t: float = tone[(row * cols + col) % tone.size()]
			# wrap the noise lookup so the texture tiles
			var gx := float(x)
			var gy := float(y)
			var n := grain.get_noise_2d(gx, gy) * 0.5 + 0.5
			var shade := t * (0.9 + n * 0.18)
			var c := Color(tint.r * shade, tint.g * shade, tint.b * shade)
			var h := 0.62 + n * 0.25
			if edge < mortar:
				c = c * 0.38
				h = 0.1
			elif edge < mortar * 2.0:
				c = c * 0.8
				h = 0.45
			img.set_pixel(x, y, c)
			height.set_pixel(x, y, Color(h, 0, 0))
	height.bump_map_to_normal_map(6.0)
	img.generate_mipmaps()
	height.generate_mipmaps()
	var a := ImageTexture.create_from_image(img)
	var n_tex := ImageTexture.create_from_image(height)
	var out := {"albedo": a, "normal": n_tex}
	_cache[key] = out
	return out


static func _stone_material(tint: Color, key: String, cols: int, rows: int, seed_value: int, texel: float = -1.0) -> StandardMaterial3D:
	var tex := _stone_textures(key, 512, cols, rows, seed_value, tint)
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex.albedo
	m.normal_enabled = true
	m.normal_texture = tex.normal
	m.normal_scale = 0.8
	m.roughness = 0.88
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	var s: float = L.STONE_TEXEL if texel < 0.0 else texel
	m.uv1_scale = Vector3(s, s, s)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


## ---- materials used by board_3d.gd -------------------------------------------------------------------------------------------------
## One material per square (shared textures; only the uv offset differs) so the marble never repeats the same patch on neighbours.
static func square_material(light: bool, at: int) -> StandardMaterial3D:
	var tex := _square_textures(light)
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex.albedo
	m.normal_enabled = true
	m.normal_texture = tex.normal
	m.normal_scale = 0.6
	m.roughness = L.SQUARE_ROUGHNESS_LIGHT if light else L.SQUARE_ROUGHNESS_DARK
	m.metallic_specular = 0.55
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 + at * 31
	m.uv1_offset = Vector3(rng.randf(), rng.randf(), 0)
	m.uv1_scale = Vector3(0.6, 0.6, 1)   # sample a crop of the texture: a wider look with the same texel density, no visible tiling
	return m


static func plinth_material() -> StandardMaterial3D:
	return _stone_material(L.PLINTH_COLOR, "plinth", 4, 8, 311, 0.9)


static func gold_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = L.FRAME_COLOR
	m.metallic = L.FRAME_METALLIC
	m.roughness = L.FRAME_ROUGHNESS
	return m


## ---- geometry helpers ------------------------------------------------------------------------------------------------------------------
static func _box(parent: Node3D, size: Vector3, at: Vector3, mat: Material, shadow: bool = true) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = at
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node


static func _cyl(parent: Node3D, bottom: float, top: float, height: float, at: Vector3, mat: Material, segments: int = 20) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = bottom
	mesh.top_radius = top
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = at
	parent.add_child(node)
	return node


class Flicker:
	extends OmniLight3D
	var base := 1.0
	var amount := 0.15
	var phase := 0.0
	var animate := true
	func _process(_delta: float) -> void:
		if not animate:
			return
		var t := Time.get_ticks_msec() * 0.001 + phase
		light_energy = base * (1.0 + amount * (sin(t * 9.0) * 0.5 + sin(t * 23.0 + phase) * 0.35 + sin(t * 3.1) * 0.15))


## Builds everything and returns the "Scenery" node (already a child of `scene`).
static func build(scene: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "Scenery"
	scene.add_child(root)
	var stone := _stone_material(L.STONE_COLOR, "block", 4, 8, 101)
	var paving := _stone_material(L.STONE_DARK, "paving", 4, 4, 202, 0.2)
	var gold := gold_material()
	var floor_y: float = L.FLOOR_Y

	# ---- frame trim: gilded inlay lines on the carved frame, corner studs ----
	var inner := 4.02
	var outer := 4.38
	for edge in [-1, 1]:
		_box(root, Vector3(2 * inner + 0.06, 0.03, 0.05), Vector3(0, -0.02, edge * inner), gold, false)
		_box(root, Vector3(0.05, 0.03, 2 * inner + 0.06), Vector3(edge * inner, -0.02, 0), gold, false)
		_box(root, Vector3(2 * outer + 0.06, 0.04, 0.06), Vector3(0, -0.02, edge * outer), gold, false)
		_box(root, Vector3(0.06, 0.04, 2 * outer + 0.06), Vector3(edge * outer, -0.02, 0), gold, false)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_cyl(root, 0.1, 0.1, 0.07, Vector3(sx * outer, -0.02, sz * outer), gold, 16)

	# ---- dais: three low steps from the frame edge down to the paving ----
	var top := -0.14
	for i in range(L.DAIS_STEPS):
		var half: float = 4.45 + i * L.DAIS_STEP_RUN
		var step_top: float = top - i * L.DAIS_STEP_RISE
		var h: float = step_top - floor_y
		_box(root, Vector3(half * 2, h, half * 2), Vector3(0, floor_y + h * 0.5, 0), stone if i != 1 else paving)
	var dais_half: float = 4.45 + (L.DAIS_STEPS - 1) * L.DAIS_STEP_RUN
	# gold inlay line on the first step's rim
	for edge in [-1, 1]:
		_box(root, Vector3(2 * 4.45 + 0.04, 0.02, 0.04), Vector3(0, top + 0.012, edge * 4.45), gold, false)
		_box(root, Vector3(0.04, 0.02, 2 * 4.45 + 0.04), Vector3(edge * 4.45, top + 0.012, 0), gold, false)

	# ---- courtyard floor + flagstone ring ----
	_box(root, Vector3(L.FLOOR_HALF * 2, 0.3, L.FLOOR_HALF * 2), Vector3(0, floor_y - 0.15, 0), paving, false)
	var ring := _cyl(root, 11.0, 11.0, 0.03, Vector3(0, floor_y + 0.015, 0), stone, 64)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ring_gold := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 10.9
	torus.outer_radius = 11.05
	torus.rings = 96
	torus.ring_segments = 4
	ring_gold.mesh = torus
	ring_gold.material_override = gold
	ring_gold.scale = Vector3(1, 0.12, 1)
	ring_gold.position = Vector3(0, floor_y + 0.04, 0)
	ring_gold.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring_gold)

	# ---- battlement walls (far from the play area) ----
	var wd: float = L.WALL_DISTANCE
	var wh: float = L.WALL_HEIGHT
	for s in [-1, 1]:
		_box(root, Vector3(wd * 2 + 2.4, wh, 1.2), Vector3(0, floor_y + wh * 0.5, s * wd), stone, false)
		_box(root, Vector3(1.2, wh, wd * 2 + 2.4), Vector3(s * wd, floor_y + wh * 0.5, 0), stone, false)
		# cornice band + gold coping so the wall reads as built, not extruded
		_box(root, Vector3(wd * 2 + 2.8, 0.3, 1.6), Vector3(0, floor_y + wh - 0.15, s * wd), paving, false)
		_box(root, Vector3(1.6, 0.3, wd * 2 + 2.8), Vector3(s * wd, floor_y + wh - 0.15, 0), paving, false)
	var merlon := BoxMesh.new()
	merlon.size = Vector3(0.9, 0.9, 0.9)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = merlon
	var spots: Array[Vector3] = []
	var count := 11
	for i in range(count):
		var p := -wd + 1.2 + i * ((wd * 2 - 2.4) / (count - 1))
		for s in [-1, 1]:
			spots.append(Vector3(p, floor_y + wh + 0.45, s * wd))
			spots.append(Vector3(s * wd, floor_y + wh + 0.45, p))
	mm.instance_count = spots.size()
	for i in spots.size():
		mm.set_instance_transform(i, Transform3D(Basis(), spots[i]))
	var merlons := MultiMeshInstance3D.new()
	merlons.multimesh = mm
	merlons.material_override = stone
	merlons.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(merlons)

	# ---- banners on the walls (navy / crimson, gold fringe + emblem) ----
	var banner_i := 0
	for s in [-1, 1]:
		for p in [-8.0, 0.0, 8.0]:
			_banner(root, Vector3(p, floor_y + wh * 0.55, s * (wd - 0.65)), 0.0 if s < 0 else PI, banner_i)
			_banner(root, Vector3(s * (wd - 0.65), floor_y + wh * 0.55, p), PI * 0.5 if s < 0 else -PI * 0.5, banner_i + 1)
			banner_i += 1

	# ---- corner pillars ----
	var pp: float = L.PILLAR_POS
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var at := Vector3(sx * pp, 0, sz * pp)
			_box(root, Vector3(1.5, 0.5, 1.5), at + Vector3(0, floor_y + 0.25, 0), stone)
			_cyl(root, 0.55, 0.48, L.PILLAR_HEIGHT, at + Vector3(0, floor_y + 0.5 + L.PILLAR_HEIGHT * 0.5, 0), stone, 24)
			_box(root, Vector3(1.2, 0.35, 1.2), at + Vector3(0, floor_y + 0.5 + L.PILLAR_HEIGHT + 0.17, 0), stone)
			_cyl(root, 0.56, 0.56, 0.08, at + Vector3(0, floor_y + 0.95, 0), gold, 24)
			_pillar_props(root, at, floor_y, (sx + 1) + (sz + 1) / 2)

	# ---- braziers with flickering warm point lights (outside the dais) ----
	var bp: float = L.BRAZIER_POS
	var i := 0
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_brazier(root, Vector3(sx * bp, floor_y, sz * bp), i)
			i += 1
	return root


const PROP_DIR := "res://assets/world/props/"

## An imported Meshy prop (assets/world/props/<name>.fbx + <name>_{albedo,normal,roughness,metallic}.png), textured here so the
## material never depends on file names inside the FBX. Returns null when the files are missing (the procedural stand-in stays).
static func prop(name: String) -> Node3D:
	var packed = load(PROP_DIR + name + ".fbx") if ResourceLoader.exists(PROP_DIR + name + ".fbx") else null
	if not packed is PackedScene:
		return null
	var node: Node3D = packed.instantiate()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(PROP_DIR + name + "_albedo.png")
	mat.normal_enabled = true
	mat.normal_texture = load(PROP_DIR + name + "_normal.png")
	mat.roughness_texture = load(PROP_DIR + name + "_roughness.png")
	mat.metallic_texture = load(PROP_DIR + name + "_metallic.png")
	mat.metallic = 1.0
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for m in node.find_children("*", "MeshInstance3D", true, false):
		m.material_override = mat
	return node


## Torch sconce and heraldic banner (Meshy models) on the inner face of a corner pillar, plus a warm flickering light at the flame.
static func _pillar_props(parent: Node3D, pillar: Vector3, floor_y: float, index: int) -> void:
	var inward := Vector3(-signf(pillar.x), 0, -signf(pillar.z)).normalized()
	var yaw := atan2(inward.x, inward.z)
	var banner := prop("heraldic_banner")
	if banner != null:
		banner.position = pillar + inward * 0.64 + Vector3(0, floor_y + 3.55, 0)
		banner.rotation.y = yaw
		banner.scale = Vector3.ONE * L.PROP_BANNER_SCALE
		parent.add_child(banner)
	var torch := prop("torch_sconce")
	if torch != null:
		torch.position = pillar + inward * 0.8 + Vector3(0, floor_y + 1.75, 0)
		torch.rotation.y = yaw
		torch.scale = Vector3.ONE * L.PROP_TORCH_SCALE
		parent.add_child(torch)
		var light := Flicker.new()
		light.position = torch.position + Vector3(0, 0.55 * L.PROP_TORCH_SCALE, 0) + inward * 0.1
		light.light_color = L.BRAZIER_COLOR
		light.base = L.TORCH_ENERGY
		light.light_energy = L.TORCH_ENERGY
		light.amount = L.BRAZIER_FLICKER
		light.phase = index * 2.3 + 0.7
		light.omni_range = L.TORCH_RANGE
		light.omni_attenuation = 1.6
		light.light_cull_mask = 2
		parent.add_child(light)


static func _banner(parent: Node3D, at: Vector3, yaw: float, index: int) -> void:
	var holder := Node3D.new()
	holder.position = at
	holder.rotation.y = yaw
	parent.add_child(holder)
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = L.BANNER_NAVY if index % 2 == 0 else L.BANNER_CRIMSON
	cloth.roughness = 0.95
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	var gold := gold_material()
	_box(holder, Vector3(1.7, 3.4, 0.04), Vector3.ZERO, cloth, false)
	_box(holder, Vector3(1.86, 0.09, 0.07), Vector3(0, 1.72, 0.01), gold, false)           # rod
	_box(holder, Vector3(1.7, 0.1, 0.05), Vector3(0, -1.62, 0.01), gold, false)            # fringe bar
	var emblem := _box(holder, Vector3(0.5, 0.5, 0.05), Vector3(0, 0.3, 0.02), gold, false)
	emblem.rotation.z = PI * 0.25
	_box(holder, Vector3(0.06, 2.2, 0.05), Vector3(0, -0.2, 0.025), gold, false)


static func _brazier(parent: Node3D, at: Vector3, index: int) -> void:
	var holder := Node3D.new()
	holder.position = at
	parent.add_child(holder)
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color("23262b")
	iron.metallic = 0.7
	iron.roughness = 0.5
	var gold := gold_material()
	_cyl(holder, 0.34, 0.26, 0.2, Vector3(0, 0.1, 0), iron, 12)
	_cyl(holder, 0.1, 0.14, 1.0, Vector3(0, 0.7, 0), iron, 12)
	_cyl(holder, 0.55, 0.3, 0.34, Vector3(0, 1.38, 0), iron, 16)
	_cyl(holder, 0.58, 0.58, 0.05, Vector3(0, 1.56, 0), gold, 16)
	var fire := StandardMaterial3D.new()
	fire.albedo_color = L.BRAZIER_COLOR
	fire.emission_enabled = true
	fire.emission = L.BRAZIER_COLOR
	fire.emission_energy_multiplier = 2.5
	fire.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var flame := _cyl(holder, 0.0, 0.3, 0.5, Vector3(0, 1.85, 0), fire, 10)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var core := _cyl(holder, 0.0, 0.16, 0.34, Vector3(0, 1.8, 0), fire, 8)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := Flicker.new()
	light.name = "BrazierLight"
	light.position = Vector3(0, 2.1, 0)
	light.light_color = L.BRAZIER_COLOR
	light.base = L.BRAZIER_ENERGY
	light.light_energy = L.BRAZIER_ENERGY
	light.amount = L.BRAZIER_FLICKER
	light.phase = index * 1.7
	light.omni_range = L.BRAZIER_RANGE
	light.omni_attenuation = 1.6
	light.shadow_enabled = false
	light.light_cull_mask = 2   # WorldConstants.LAYER_BOARD: lights the board world only, never the arena
	holder.add_child(light)
