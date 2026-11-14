class_name CourtyardEnvironment
extends Node3D
## The chessboard is the courtyard floor. Scenery starts beyond its 4.4 m frame and has no physics
## bodies: neither chess picking nor the authoritative combat simulation sees decorative obstacles.
## Reuses the opening castle's texture, masonry batching and GPU cloth/flame assets. Separate wings
## and arcade spans let only the architecture between the camera and the action fade away.
const Batch = preload("res://ui/opening/mesh_batch.gd")
const Assets = preload("res://ui/opening/opening_assets.gd")
const BOARD_LAYER := 2
const CLEAR_HALF := 4.45
const STONE := Color("c4ac88")
const TRIM := Color("d9c59e")
const DARK := Color("61564b")
const SLATE := Color("48565c")
const IRON := Color("353a3a")
const GOLD := Color("bca36b")

var camera: Camera3D
var quality := "high"
var architecture: Array[Dictionary] = []
var torch_lights: Array[OmniLight3D] = []
var triangles := 0
var _built := false
var _stone_texture: Texture2D
var _roof_texture: Texture2D
var _floor_material: StandardMaterial3D
var _banner_materials: Array[ShaderMaterial] = []
var _flames: ShaderMaterial
var _optional: Array[Node3D] = []
var _flame_positions: Array[Vector3] = []
var _rng := RandomNumberGenerator.new()
var _time := 0.0
var _motion := true

func _enter_tree() -> void:
	add_to_group("courtyard_quality")

func setup(view_camera: Camera3D, preset: String = "high") -> void:
	camera = view_camera
	if not _built:
		_built = true
		name = "CastleCourtyard"
		_rng.seed = 734
		_stone_texture = Assets.stone_texture()
		_roof_texture = Assets.slate_texture()
		_flames = Assets.shader_material(Assets.FLAME_SHADER)
		_build_floor()
		for side in 4:
			_build_wing(side)
			for bay in 5:
				_build_arcade(side, float(bay - 2) * 3.0)
		for x in [-1.0, 1.0]:
			for z in [-1.0, 1.0]:
				_build_tower(Vector3(x * 10.1, 0, z * 10.1), x != z)
		_build_keep()
		_build_gardens()
		_build_flames()
	set_quality(preset)

func set_quality(preset: String) -> void:
	quality = preset if preset in ["low", "balanced", "high"] else "balanced"
	var count := 1 if quality == "low" else (2 if quality == "balanced" else 4)
	for i in torch_lights.size():
		torch_lights[i].visible = i < count
	for detail in _optional:
		detail.visible = quality != "low"
	set_motion(_motion)

func set_motion(enabled: bool) -> void:
	_motion = enabled
	for banner in _banner_materials:
		banner.set_shader_parameter("wind", (0.12 if quality == "low" else 0.22) if enabled else 0.0)
	if _flames != null:
		_flames.set_shader_parameter("speed", 0.6 if enabled else 0.0)

func _process(delta: float) -> void:
	update_camera(delta)

## A segment test against precomputed architectural bounds. No raycasts/colliders, per-frame mesh
## rebuilds, or screen-reading effects; this also works on the GLES Compatibility renderer.
func update_camera(delta: float) -> void:
	if not is_instance_valid(camera) or not is_inside_tree():
		return
	_time += delta
	var eye := camera.global_position
	var forward := -camera.global_basis.z
	var focus := Vector3(0, 0.8, 0)
	if forward.y < -0.025:
		var plane_hit := eye + forward * maxf(0.0, (0.8 - eye.y) / forward.y)
		focus = Vector3(clampf(plane_hit.x, -4, 4), 0.8, clampf(plane_hit.z, -4, 4))
	elif eye.y < 6:
		focus = Vector3(clampf(eye.x + forward.x * 5, -4, 4), 0.8, clampf(eye.z + forward.z * 5, -4, 4))
	var weight := 1.0 - exp(-delta * 10.0)
	for section in architecture:
		var bounds: AABB = global_transform * section.bounds
		var blocked: bool = bounds.grow(0.35).intersects_segment(eye, focus) != null
		var target := 0.06 if blocked else 1.0
		section.alpha = lerpf(float(section.alpha), target, weight)
		if absf(float(section.alpha) - target) < 0.005:
			section.alpha = target
		var opaque: bool = float(section.alpha) > 0.995
		for part in section.parts:
			var material: Material = part.material_override
			if material is StandardMaterial3D:
				material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED if opaque else BaseMaterial3D.TRANSPARENCY_ALPHA
				material.albedo_color.a = float(section.alpha)
			elif material is ShaderMaterial:
				material.set_shader_parameter("visibility", float(section.alpha))
			part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if opaque else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A slow, restrained light variation; the flame silhouette supplies the movement, never a strobe.
	for i in torch_lights.size():
		torch_lights[i].light_energy = 0.48 + sin(_time * 2.3 + i * 1.7) * 0.025

func _xf(at: Vector3, yaw: float = 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), at)

func _mesh(batch, material: Material, label: String) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = batch.build_mesh()
	instance.material_override = material
	instance.layers = BOARD_LAYER
	triangles += batch.triangle_count()
	add_child(instance)
	return instance

func _section(label: String, stone, plain = null, roof = null) -> void:
	var parts: Array[MeshInstance3D] = []
	if not stone.is_empty():
		parts.append(_mesh(stone, Assets.textured(_stone_texture, 0.94), label))
	if plain != null and not plain.is_empty():
		parts.append(_mesh(plain, Assets.plain(0.88), label + "Details"))
	if roof != null and not roof.is_empty():
		parts.append(_mesh(roof, Assets.textured(_roof_texture, 0.88), label + "Roof"))
	var bounds := AABB()
	var first := true
	for part in parts:
		if first:
			bounds = part.mesh.get_aabb()
			first = false
		else:
			bounds = bounds.merge(part.mesh.get_aabb())
	architecture.append({"parts": parts, "bounds": bounds, "alpha": 1.0})

func _build_floor() -> void:
	var floor := Batch.new(17)
	floor.uv_scale = 0.75
	# Four continuous strips under the pavers prevent distant mortar joints becoming transparent gaps.
	for s in [-1.0, 1.0]:
		floor.box(_xf(Vector3(s * 8.225, -0.14, 0)), Vector3(7.55, 0.18, 24), DARK)
		floor.box(_xf(Vector3(0, -0.14, s * 8.225)), Vector3(8.9, 0.18, 7.55), DARK)
	for x in 32:
		for z in 32:
			var px := (float(x) - 15.5) * 0.75
			var pz := (float(z) - 15.5) * 0.75
			if absf(px) < 4.8 and absf(pz) < 4.8:
				continue
			floor.box(_xf(Vector3(px, -0.075 - _rng.randf() * 0.008, pz)), Vector3(0.728, 0.07, 0.728), floor.jitter(Color("968c78"), 0.15))
	# Narrow dressed-stone border makes the inlaid chessboard belong to the paving.
	for s in [-1.0, 1.0]:
		floor.box(_xf(Vector3(s * 4.57, -0.06, 0)), Vector3(0.24, 0.10, 9.4), TRIM)
		floor.box(_xf(Vector3(0, -0.06, s * 4.57)), Vector3(8.9, 0.10, 0.24), TRIM)
	_floor_material = Assets.textured(_stone_texture, 0.98)
	var instance := _mesh(floor, _floor_material, "CourtyardFlagstones")
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _build_wing(side: int) -> void:
	var stone := Batch.new(30 + side)
	var plain := Batch.new(40 + side)
	var yaw := float(side) * PI * 0.5
	var basis := Basis(Vector3.UP, yaw)
	# Outermost warm masonry curtain, moulded cornices and individual battlements.
	stone.box(Transform3D(basis, basis * Vector3(0, 2.6, -10.25)), Vector3(19, 5.2, 0.62), STONE)
	for y in [0.14, 0.45, 4.85, 5.22]:
		stone.box(Transform3D(basis, basis * Vector3(0, y, -10.25)), Vector3(19.3, 0.18, 0.85), TRIM)
	for i in 19:
		stone.box(Transform3D(basis, basis * Vector3(float(i - 9), 5.65, -10.25)), Vector3(0.48, 0.75, 0.7), stone.jitter(STONE, 0.08))
	for i in 6:
		var along := float(i) * 3.15 - 7.875
		stone.box(Transform3D(basis, basis * Vector3(along, 2.4, -9.85)), Vector3(0.55, 4.8, 0.28), TRIM)
		# Recesses are dark rather than emissive to avoid competing with the pieces.
		plain.box(Transform3D(basis, basis * Vector3(along + 1.55, 3.8, -9.91)), Vector3(0.42, 1.25, 0.055), Color("3a3f3c"))
	_section("Curtain%d" % side, stone, plain)
	# Banners on the outer wall stay beyond the board's sightlines.
	for along in [-4.7, 4.7]:
		_build_banner(basis * Vector3(along, 4.4, -9.8), 0.75, 1.85, yaw, Color("873a35") if side % 2 == 0 else Color("334a61"))

func _build_arcade(side: int, along: float) -> void:
	var stone := Batch.new(60 + side * 9 + int(along))
	var plain := Batch.new(90 + side)
	var yaw := float(side) * PI * 0.5
	var basis := Basis(Vector3.UP, yaw)
	var center := basis * Vector3(along, 0, -8.55)
	for sign in [-1.0, 1.0]:
		var pos := center + basis * Vector3(sign * 1.42, 0, 0)
		stone.box(_xf(pos + Vector3(0, 0.16, 0), yaw), Vector3(0.67, 0.32, 0.67), TRIM)
		stone.cylinder(pos + Vector3(0, 0.3, 0), 0.24, 0.19, 2.48, 12, STONE)
		stone.cylinder(pos + Vector3(0, 2.78, 0), 0.20, 0.31, 0.25, 12, TRIM)
		stone.box(_xf(pos + Vector3(0, 3.07, 0), yaw), Vector3(0.68, 0.20, 0.62), TRIM)
	# Voussoirs form a real open arch, not a solid rectangle over a black painted opening.
	var radius := 1.4
	for i in 13:
		var a0 := float(i) / 13.0 * PI
		var a1 := float(i + 1) / 13.0 * PI
		_arch_stone(stone, _xf(center + Vector3(0, 2.9, 0), yaw), radius, radius + 0.24, a0, a1 - 0.008, 0.42, stone.jitter(TRIM, 0.055))
	stone.box(_xf(center + Vector3(0, 4.55, 0), yaw), Vector3(2.94, 0.17, 0.66), TRIM)
	stone.box(_xf(center + Vector3(0, 4.77, -0.18), yaw), Vector3(2.94, 0.3, 0.3), STONE)
	# Vault walkway links the arcade to the curtain wall while leaving the courtyard open to the sky.
	stone.box(_xf(center + basis * Vector3(0, 4.40, -0.75), yaw), Vector3(3.0, 0.15, 1.8), STONE)
	_section("Arcade%d_%d" % [side, int(along)], stone, plain)

func _arch_stone(batch, xf: Transform3D, inner: float, outer: float, a: float, b: float, depth: float, color: Color) -> void:
	var p0 := Vector3(cos(a) * inner, sin(a) * inner, depth * 0.5)
	var p1 := Vector3(cos(b) * inner, sin(b) * inner, depth * 0.5)
	var p2 := Vector3(cos(b) * outer, sin(b) * outer, depth * 0.5)
	var p3 := Vector3(cos(a) * outer, sin(a) * outer, depth * 0.5)
	var back := Vector3(0, 0, -depth)
	batch.quad_xf(xf, p0, p1, p2, p3, color)
	batch.quad_xf(xf, p3 + back, p2 + back, p1 + back, p0 + back, color)
	batch.quad_xf(xf, p1, p0, p0 + back, p1 + back, color.darkened(0.1))
	batch.quad_xf(xf, p3, p2, p2 + back, p3 + back, color)
	batch.quad_xf(xf, p0, p3, p3 + back, p0 + back, color)
	batch.quad_xf(xf, p2, p1, p1 + back, p2 + back, color)

func _build_tower(pos: Vector3, spire: bool) -> void:
	var stone := Batch.new(int(pos.x * 12 + pos.z * 5))
	var plain := Batch.new(8)
	var roof := Batch.new(7)
	var height := 8.4 if spire else 7.2
	stone.lathe(_xf(pos), [Vector2(1.65, -0.1), Vector2(1.65, 0.3), Vector2(1.36, 0.7), Vector2(1.27, height - 1.0), Vector2(1.35, height - 0.8), Vector2(1.57, height - 0.45), Vector2(1.57, height)], 24, STONE, TRIM, true)
	for y in [0.5, 2.6, height - 0.9]:
		stone.lathe(_xf(pos), [Vector2(1.36, y), Vector2(1.43, y + 0.07), Vector2(1.43, y + 0.18), Vector2(1.34, y + 0.23)], 24, TRIM)
	for i in 8:
		var a := float(i) * TAU / 8
		var outward := Vector3(sin(a), 0, cos(a))
		for y in [2.0, 4.5]:
			plain.box(_xf(pos + outward * 1.32 + Vector3(0, y, 0), a), Vector3(0.15, 0.78, 0.025), Color("3a3b36"))
	if spire:
		roof.lathe(_xf(pos + Vector3(0, height, 0)), [Vector2(1.78, 0), Vector2(1.78, 0.16), Vector2(1.2, 1.2), Vector2(0.55, 2.4), Vector2(0.08, 3.4)], 24, SLATE)
		plain.cylinder(pos + Vector3(0, height + 3.4, 0), 0.055, 0.035, 0.7, 8, GOLD)
	else:
		for i in 10:
			var a := float(i) * TAU / 10
			stone.box(_xf(pos + Vector3(sin(a) * 1.41, height + 0.37, cos(a) * 1.41), a), Vector3(0.5, 0.74, 0.4), STONE)
	_section("Tower_%d_%d" % [int(pos.x), int(pos.z)], stone, plain, roof)

func _build_keep() -> void:
	var stone := Batch.new(109)
	var roof := Batch.new(112)
	var plain := Batch.new(111)
	stone.block(Vector3(0, 0, -15.0), Vector3(9.3, 11.8, 3.2), 0, STONE)
	for y in [0.4, 5.0, 8.0, 11.5]:
		stone.box(_xf(Vector3(0, y, -15.0)), Vector3(9.7, 0.22, 3.5), TRIM)
	for x in [-3.6, -1.8, 0.0, 1.8, 3.6]:
		for y in [6.0, 9.2]:
			plain.box(_xf(Vector3(x, y, -13.37)), Vector3(0.58, 1.48, 0.04), Color("42483f"))
			for sign in [-1.0, 1.0]:
				stone.box(_xf(Vector3(x + sign * 0.35, y, -13.32)), Vector3(0.14, 1.6, 0.18), TRIM)
	for i in 15:
		stone.box(_xf(Vector3(float(i - 7) * 0.65, 12.1, -13.55)), Vector3(0.32, 0.65, 0.42), STONE)
	roof.wedge(_xf(Vector3(0, 11.9, -15.0), PI * 0.5), 3.9, 9.4, 2.5, SLATE)
	_section("DistantKeep", stone, plain, roof)

func _build_banner(top: Vector3, width: float, length: float, yaw: float, color: Color) -> void:
	# The same banner shader and UV convention used by the opening castle, with restrained wind.
	var cloth := Batch.new(6)
	var xf := _xf(top, yaw)
	for i in 10:
		var a := float(i) / 10
		var b := float(i + 1) / 10
		var at := cloth.verts.size()
		cloth._push(xf * Vector3(-width * 0.5, -length * a, 0), xf.basis.z, color, Vector2(0, a))
		cloth._push(xf * Vector3(width * 0.5, -length * a, 0), xf.basis.z, color, Vector2(1, a))
		cloth._push(xf * Vector3(width * 0.5, -length * b, 0), xf.basis.z, color, Vector2(1, b))
		cloth._push(xf * Vector3(-width * 0.5, -length * b, 0), xf.basis.z, color, Vector2(0, b))
		cloth._tri(at, at + 1, at + 2)
		cloth._tri(at, at + 2, at + 3)
	var banner_material := Assets.shader_material(Assets.BANNER_SHADER.replace("uniform float wind = 1.0;", "uniform float wind = 0.2;\nuniform float visibility = 1.0;").replace("ROUGHNESS = 0.92;", "ROUGHNESS = 0.92;\nALPHA = visibility;"))
	_banner_materials.append(banner_material)
	var instance := _mesh(cloth, banner_material, "RoyalBanner")
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pole := Batch.new(3)
	pole.box(_xf(top + Vector3(0, 0.06, 0), yaw), Vector3(width + 0.2, 0.07, 0.07), GOLD)
	var crossbar := _mesh(pole, Assets.plain(0.7), "BannerCrossbar")
	architecture.append({"parts": [instance, crossbar], "bounds": instance.mesh.get_aabb().merge(crossbar.mesh.get_aabb()), "alpha": 1.0})

func _build_gardens() -> void:
	var detail := Batch.new(343)
	var leaves := Batch.new(344)
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 10
	sphere.rings = 5
	var arrays := sphere.get_mesh_arrays()
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			var stone := Batch.new(341)
			var flora := Batch.new(342)
			var pos := Vector3(x * 6.3, 0, z * 6.3)
			stone.lathe(_xf(pos), [Vector2(0.8, -0.03), Vector2(0.8, 0.15), Vector2(0.68, 0.2), Vector2(0.68, 0.5), Vector2(0.78, 0.53), Vector2(0.78, 0.68), Vector2(0.61, 0.68)], 16, TRIM, STONE)
			flora.cylinder(pos + Vector3(0, 0.63, 0), 0.61, 0.61, 0.025, 12, Color("4e5140"), Color(0,0,0,-1), true)
			flora.cylinder(pos + Vector3(0, 0.65, 0), 0.11, 0.055, 2.2, 9, Color("625844"))
			# Layered cypress profile, as in the reference, keeps the outer board silhouette clean.
			flora.lathe(_xf(pos + Vector3(0, 1.1, 0)), [Vector2(0.10, 0), Vector2(0.53, 0.25), Vector2(0.44, 0.65), Vector2(0.51, 0.88), Vector2(0.33, 1.35), Vector2(0.40, 1.52), Vector2(0.18, 2.05), Vector2(0.25, 2.22), Vector2(0.025, 2.85)], 12, Color("3c5945"), Color("748263"), true)
			for i in 9:
				var a := float(i) * TAU / 9
				var loc := pos + Vector3(sin(a) * 0.51, 0.77, cos(a) * 0.51)
				detail.add_arrays(arrays, Transform3D(Basis.IDENTITY.scaled(Vector3(0.14, 0.24, 0.13)), loc), Color("74805b"))
				if i % 3 == 0:
					detail.add_arrays(arrays, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.07), loc + Vector3(0, 0.25, 0)), Color("b5a2a3"))
			# Small dry leaves outside the play area, batched rather than particles.
			for i in 28:
				var p := pos + Vector3(_rng.randf_range(-1.2, 1.2), -0.028, _rng.randf_range(-1.2, 1.2))
				if absf(p.x) < CLEAR_HALF or absf(p.z) < CLEAR_HALF:
					continue
				leaves.box(_xf(p, _rng.randf() * TAU), Vector3(0.10, 0.008, 0.045), leaves.jitter(Color("94764f"), 0.2))
			_build_torch(Vector3(x * 5.2, 0, z * 7.4), stone, flora)
			_section("Garden_%d_%d" % [int(x), int(z)], stone, flora)
	var plants := Assets.plain(0.96)
	_optional.append(_mesh(detail, plants, "HerbsAndFlowers"))
	_optional.append(_mesh(leaves, Assets.plain(1.0), "FallenLeaves"))
	# Delicate ivy trails cling to the exterior arches, never across a playable square.
	var ivy := Batch.new(620)
	for side in 4:
		var basis := Basis(Vector3.UP, float(side) * PI * 0.5)
		for branch in 3:
			for i in 16:
				var p := basis * Vector3(-6.1 + float(branch) * 0.24 + sin(float(i) * 0.7) * 0.15, 4.25 - float(i) * 0.20, -8.30)
				var leaf_x := basis.x * 0.11
				var leaf_y := Vector3.UP * 0.075
				ivy.quad(p - leaf_x, p + leaf_y, p + leaf_x, p - leaf_y, ivy.jitter(Color("52664a"), 0.15))
	var ivy_material := Assets.plain(0.96)
	ivy_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_optional.append(_mesh(ivy, ivy_material, "ArcadeIvy"))

func _build_torch(pos: Vector3, stone, plain) -> void:
	stone.box(_xf(pos + Vector3(0, 0.12, 0)), Vector3(0.5, 0.24, 0.5), STONE)
	plain.cylinder(pos + Vector3(0, 0.2, 0), 0.16, 0.08, 0.95, 10, IRON)
	plain.lathe(_xf(pos + Vector3(0, 1.15, 0)), [Vector2(0.11, 0), Vector2(0.30, 0.2), Vector2(0.32, 0.29), Vector2(0.23, 0.3)], 12, IRON)
	_flame_positions.append(pos + Vector3(0, 1.42, 0))
	var light := OmniLight3D.new()
	light.name = "CourtyardTorch"
	light.position = pos + Vector3(0, 1.75, 0)
	light.light_color = Color("ffbb76")
	light.light_energy = 0.48
	light.omni_range = 3.0
	light.omni_attenuation = 1.3
	light.shadow_enabled = false
	light.light_cull_mask = BOARD_LAYER
	add_child(light)
	torch_lights.append(light)

func _build_flames() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_custom_data = true
	multi.mesh = quad
	multi.instance_count = _flame_positions.size()
	for i in _flame_positions.size():
		multi.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.55), _flame_positions[i]))
		multi.set_instance_custom_data(i, Color(float(i) * 0.23, 0, 0, 0))
	var instance := MultiMeshInstance3D.new()
	instance.name = "TorchFlames"
	instance.multimesh = multi
	instance.material_override = _flames
	instance.layers = BOARD_LAYER
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.custom_aabb = AABB(Vector3(-12, -1, -12), Vector3(24, 15, 24))
	add_child(instance)
