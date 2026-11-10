class_name StoneArenaVisuals
extends Node3D
## Procedural dressing for arena "stone-v1": stone floor and wall, four pillars with torches,
## banners, fog and lighting. No imported assets. A dedicated server never builds this; the
## collision shapes live in StoneArena.build_colliders().

var _pillar_meshes: Array[MeshInstance3D] = []
var _pillar_mats: Array[StandardMaterial3D] = []
var _torches: Array[OmniLight3D] = []
var _flames: Array[MeshInstance3D] = []
var _time: float = 0.0


func build() -> void:
	_environment()
	_floor()
	_wall()
	_pillars()
	_banners()
	var sun := DirectionalLight3D.new()
	sun.name = "MoonLight"
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	sun.light_color = Color(0.72, 0.78, 1.0)
	sun.light_energy = 0.75
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 22.0
	add_child(sun)


func _process(delta: float) -> void:
	_time += delta
	for i in _torches.size():
		var flicker := 1.0 + 0.16 * sin(_time * 11.0 + float(i) * 1.7) + 0.08 * sin(_time * 23.0 + float(i) * 0.6)
		_torches[i].light_energy = 1.9 * flicker
		_flames[i].scale = Vector3(1.0, 1.0 + 0.25 * sin(_time * 14.0 + float(i)), 1.0)


func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.025, 0.03, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.34, 0.36, 0.48)
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.07, 0.08, 0.13)
	env.fog_density = 0.012
	var holder := WorldEnvironment.new()
	holder.environment = env
	add_child(holder)


static func stone_texture(seed_value: int, base: Color) -> ImageTexture:
	var size := 256
	var img := Image.create(size, size, true, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var tiles := 4
	var tile_px := size / tiles
	var tone: Array = []
	for _i in tiles * tiles:
		tone.append(rng.randf_range(0.82, 1.12))
	for y in size:
		for x in size:
			var tx := x / tile_px
			var ty := y / tile_px
			var lx := x % tile_px
			var ly := y % tile_px
			var edge := minf(minf(lx, tile_px - 1 - lx), minf(ly, tile_px - 1 - ly))
			var grout := 1.0 if edge > 2 else 0.55
			var speck := 0.94 + 0.12 * rng.randf()
			var c := base * float(tone[ty * tiles + tx]) * grout * speck
			img.set_pixel(x, y, Color(c.r, c.g, c.b))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _stone_material(uv_scale: float, tint: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = stone_texture(7, tint)
	m.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	m.roughness = 0.95
	return m


func _floor() -> void:
	var disc := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = CombatConstants.ARENA_WALL_RADIUS + 0.4
	mesh.bottom_radius = mesh.top_radius
	mesh.height = 0.4
	mesh.radial_segments = 48
	mesh.rings = 1
	disc.mesh = mesh
	disc.material_override = _stone_material(7.0, Color(0.5, 0.48, 0.46))
	disc.position = Vector3(0.0, -0.2, 0.0)
	add_child(disc)

	# Inlaid ring marking the fighting circle, and a centre mark.
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 6.35
	torus.outer_radius = 6.5
	torus.rings = 48
	torus.ring_segments = 6
	ring.mesh = torus
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.7, 0.55, 0.2)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(0.7, 0.5, 0.15)
	ring_mat.emission_energy_multiplier = 0.35
	ring.material_override = ring_mat
	ring.scale = Vector3(1.0, 0.05, 1.0)
	ring.position = Vector3(0.0, 0.01, 0.0)
	add_child(ring)


func _wall() -> void:
	var material := _stone_material(1.6, Color(0.42, 0.4, 0.42))
	var segments := StoneArena.WALL_SEGMENTS
	var apothem := CombatConstants.ARENA_WALL_RADIUS
	var length := 2.0 * apothem * tan(PI / float(segments)) * 1.1
	for i in segments:
		var angle := TAU * float(i) / float(segments)
		var outward := Vector3(sin(angle), 0.0, cos(angle))
		var block := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(length, StoneArena.WALL_HEIGHT, StoneArena.WALL_THICKNESS)
		block.mesh = box
		block.material_override = material
		block.position = outward * (apothem + StoneArena.WALL_THICKNESS * 0.5) + Vector3(0.0, StoneArena.WALL_HEIGHT * 0.5, 0.0)
		block.rotation.y = angle
		add_child(block)
		if i % 2 == 0:
			var merlon := MeshInstance3D.new()
			var small := BoxMesh.new()
			small.size = Vector3(length * 0.5, 0.45, StoneArena.WALL_THICKNESS)
			merlon.mesh = small
			merlon.material_override = material
			merlon.position = outward * (apothem + StoneArena.WALL_THICKNESS * 0.5) + Vector3(0.0, StoneArena.WALL_HEIGHT + 0.22, 0.0)
			merlon.rotation.y = angle
			add_child(merlon)


func _pillars() -> void:
	var material := _stone_material(1.2, Color(0.5, 0.48, 0.5))
	for pos in StoneArena.PILLAR_POSITIONS:
		var column := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = StoneArena.PILLAR_RADIUS
		cyl.bottom_radius = StoneArena.PILLAR_RADIUS
		cyl.height = 3.5
		column.mesh = cyl
		var fade_material := material.duplicate() as StandardMaterial3D
		fade_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		column.material_override = fade_material
		column.position = pos + Vector3(0.0, 1.75, 0.0)
		add_child(column)
		_pillar_meshes.append(column)
		_pillar_mats.append(fade_material)
		for y in [0.15, 3.4]:
			var cap := MeshInstance3D.new()
			var disc := CylinderMesh.new()
			disc.top_radius = StoneArena.PILLAR_RADIUS + 0.14
			disc.bottom_radius = StoneArena.PILLAR_RADIUS + 0.14
			disc.height = 0.3
			cap.mesh = disc
			cap.material_override = material
			cap.position = pos + Vector3(0.0, y, 0.0)
			add_child(cap)
		# Torch on the side facing the arena centre.
		var inward := (-Vector3(pos.x, 0.0, pos.z)).normalized()
		var mount := pos + inward * (StoneArena.PILLAR_RADIUS + 0.08) + Vector3(0.0, 2.2, 0.0)
		var bracket := MeshInstance3D.new()
		var stick := CylinderMesh.new()
		stick.top_radius = 0.045
		stick.bottom_radius = 0.035
		stick.height = 0.45
		bracket.mesh = stick
		var iron := StandardMaterial3D.new()
		iron.albedo_color = Color(0.12, 0.11, 0.1)
		bracket.material_override = iron
		bracket.position = mount
		add_child(bracket)
		var flame := MeshInstance3D.new()
		var drop := SphereMesh.new()
		drop.radius = 0.1
		drop.height = 0.26
		flame.mesh = drop
		var fire := StandardMaterial3D.new()
		fire.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fire.albedo_color = Color(1.0, 0.62, 0.2)
		flame.material_override = fire
		flame.position = mount + Vector3(0.0, 0.3, 0.0)
		add_child(flame)
		_flames.append(flame)
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.66, 0.34)
		light.light_energy = 1.9
		light.omni_range = 8.0
		light.position = mount + Vector3(0.0, 0.4, 0.0)
		add_child(light)
		_torches.append(light)


func _banners() -> void:
	var palette := [Color(0.9, 0.82, 0.55), Color(0.38, 0.12, 0.42), Color(0.9, 0.82, 0.55), Color(0.38, 0.12, 0.42)]
	for i in 4:
		var angle := TAU * float(i) / 4.0 + PI / 4.0
		var banner := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(1.1, 2.3)
		banner.mesh = quad
		var cloth := StandardMaterial3D.new()
		cloth.albedo_color = palette[i]
		cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
		cloth.roughness = 1.0
		banner.material_override = cloth
		var inward := -Vector3(sin(angle), 0.0, cos(angle))
		banner.position = -inward * (CombatConstants.ARENA_WALL_RADIUS - 0.04) + Vector3(0.0, 1.9, 0.0)
		banner.look_at_from_position(banner.position, banner.position + inward, Vector3.UP)
		add_child(banner)


## Pillars between a camera and the fighter it follows turn translucent instead of blocking the view.
func fade_occluders(camera_pos: Vector3, focus: Vector3) -> void:
	for i in _pillar_meshes.size():
		var centre := _pillar_meshes[i].global_position
		var a := Vector2(camera_pos.x, camera_pos.z)
		var b := Vector2(focus.x, focus.z)
		var c := Vector2(centre.x, centre.z)
		var ab := b - a
		var t := clampf((c - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var distance := (a + ab * t).distance_to(c)
		var blocking := distance < StoneArena.PILLAR_RADIUS + 0.7 and t > 0.02 and t < 0.98
		var target_alpha := 0.18 if blocking else 1.0
		var m := _pillar_mats[i]
		m.albedo_color.a = lerpf(m.albedo_color.a, target_alpha, 0.2)
