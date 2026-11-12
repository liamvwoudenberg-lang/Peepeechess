extends Node3D
## The 3D backdrop of the home screen: a moonlit chess castle at the end of a chequered bridge.
##
## Cost model (Compatibility renderer, phones included):
##   * all static geometry is merged into a handful of MeshInstances (one draw call per material), the giant chess pieces are
##     merged by material too, halos and embers are single MultiMeshes, banners / embers / halos are animated in vertex shaders,
##     so the per-frame CPU work is: one camera transform, a few light energies, three uniform writes;
##   * the real light budget is small and fixed per quality (the pool relocates while the camera passes the gate);
##   * quality "low" drops the extra lights, clouds, trees, pieces and mist; reduce-motion freezes drift, wind, flicker and embers.
## `blend` is the camera's progress between the opening shot (0) and the menu vantage inside the courtyard (1); the 2D opening
## screen drives it, the scene only draws. Free the node to free everything (no statics, no autoloads).
const Builder = preload("res://ui/opening/castle_builder.gd")
const Assets = preload("res://ui/opening/opening_assets.gd")
const Batch = preload("res://ui/opening/mesh_batch.gd")
const PIECES := "res://assets/world/pieces/"
const MOON_DIR := Vector3(0.342, 0.407, -0.847)

const CAM_A := Vector3(0.0, 4.6, 74.0)
const LOOK_A := Vector3(1.5, 13.0, 0.0)
const CAM_B := Vector3(-24.0, 9.5, -5.0)
const LOOK_B := Vector3(7.0, 12.0, -40.0)

var quality: String = "balanced"
var animated := true
var blend := 0.0
## Camera-drift speed multiplier (the opening drifts slowly, the menu even slower).
var drift_rate := 1.0
var camera: Camera3D
var sun: DirectionalLight3D
var fill: DirectionalLight3D
var gate_light: OmniLight3D
var slot_lights: Array[OmniLight3D] = []
var environment: Environment
var triangle_count := 0
var build_msec := 0.0
var _slots: Array[Dictionary] = []
var _sky: ShaderMaterial
var _glow_material: ShaderMaterial
var _ember_material: ShaderMaterial
var _flame_material: ShaderMaterial
var _banner_material: ShaderMaterial
var _mist_materials: Array[ShaderMaterial] = []
var _clock := 0.0          # drift time
var _wall_clock := 0.0     # flicker / wind time
var _viewport_size := Vector2.ZERO
var _glow_flame_count := 0

static func quality_index(name: String) -> int:
	return {"low": Builder.Quality.LOW, "balanced": Builder.Quality.BALANCED, "high": Builder.Quality.HIGH}.get(name, Builder.Quality.BALANCED)

# ---------------------------------------------------------------------------------------------------------------------
func build(quality_name: String = "balanced", motion: bool = true, start_blend: float = 0.0) -> void:
	var started := Time.get_ticks_usec()
	quality = quality_name if quality_name in ["low", "balanced", "high"] else "balanced"
	animated = motion
	name = "OpeningScene"
	var q := quality_index(quality)
	var builder := Builder.new(q)
	builder.build()
	triangle_count = builder.triangle_count()
	_build_environment(q)
	_build_camera()
	_build_lights(q, builder)
	_build_meshes(q, builder)
	_build_statues(q, builder)
	_build_glows(q, builder)
	_build_flames(builder)
	_build_embers(q, builder)
	_build_mist(builder)
	set_motion(motion)
	set_blend(start_blend)
	build_msec = float(Time.get_ticks_usec() - started) / 1000.0

func set_motion(enabled: bool) -> void:
	animated = enabled
	set_process(enabled)
	var wind := 1.0 if enabled else 0.0
	if _banner_material != null:
		_banner_material.set_shader_parameter("wind", wind)
	if _glow_material != null:
		_glow_material.set_shader_parameter("speed", wind)
	if _flame_material != null:
		_flame_material.set_shader_parameter("speed", wind)
	if _ember_material != null:
		_ember_material.set_shader_parameter("speed", wind)
		var embers := get_node_or_null("Embers") as Node3D
		if embers != null:
			embers.visible = enabled   # embers are pure motion: hidden (not frozen mid-air) when motion is reduced
	for material in _mist_materials:
		material.set_shader_parameter("speed", wind)
	_update_lights()

# ---------------------------------------------------------------------------------------------------------------------
# environment, camera, lights
# ---------------------------------------------------------------------------------------------------------------------
func _build_environment(q: int) -> void:
	_sky = Assets.shader_material(Assets.SKY_SHADER)
	_sky.set_shader_parameter("moon_dir", MOON_DIR)
	_sky.set_shader_parameter("clouds", 0.0 if q == Builder.Quality.LOW else 1.0)
	var sky := Sky.new()
	sky.sky_material = _sky
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("5a6a9c")
	environment.ambient_light_energy = 0.55
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.0
	environment.fog_enabled = true
	environment.fog_light_color = Color("2b3760")
	environment.fog_density = 0.0042
	environment.fog_sky_affect = 0.25
	environment.fog_height = -6.0
	environment.fog_height_density = 0.012
	if q == Builder.Quality.HIGH:
		environment.glow_enabled = true
		environment.glow_intensity = 0.7
		environment.glow_strength = 1.0
		environment.glow_bloom = 0.04
		environment.glow_hdr_threshold = 0.9
		environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.06
	environment.adjustment_saturation = 1.12

func _build_camera() -> void:
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.environment = environment
	camera.near = 0.4
	camera.far = 1400.0
	camera.current = true
	add_child(camera)

func _build_lights(q: int, builder: Builder) -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Moon"
	sun.light_color = Color("a9bcff")
	sun.light_energy = 1.15
	sun.transform = Transform3D(Basis.looking_at(-MOON_DIR, Vector3.UP), Vector3.ZERO)
	if q == Builder.Quality.HIGH:
		sun.shadow_enabled = true
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		sun.directional_shadow_max_distance = 160.0
		sun.shadow_bias = 0.08
	add_child(sun)
	fill = DirectionalLight3D.new()
	fill.name = "Fill"
	fill.light_color = Color("7c8fd0")
	fill.light_energy = 0.42
	fill.transform = Transform3D(Basis.looking_at(Vector3(0.28, -0.42, -0.86), Vector3.UP), Vector3.ZERO)
	add_child(fill)
	gate_light = _omni(builder.gate_light)
	gate_light.name = "GateLight"
	var pool := {Builder.Quality.LOW: 3, Builder.Quality.BALANCED: 5, Builder.Quality.HIGH: 7}[q] as int
	for i in mini(pool, builder.light_slots.size()):
		var slot: Dictionary = builder.light_slots[i]
		var light := _omni({"pos": slot.ext, "color": slot.color, "energy": slot.energy, "range": slot.range})
		light.name = "TorchLight%d" % i
		slot_lights.append(light)
		_slots.append(slot)

func _omni(data: Dictionary) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.position = data.pos
	light.light_color = data.color
	light.light_energy = data.energy
	light.omni_range = data.range
	light.omni_attenuation = 1.4
	light.shadow_enabled = false
	add_child(light)
	return light

func _update_lights() -> void:
	var k := clampf((blend - 0.42) / 0.16, 0.0, 1.0)
	var in_court := k > 0.5
	var dim := sqrt(absf(k - 0.5) * 2.0)
	for i in slot_lights.size():
		var slot: Dictionary = _slots[i]
		var light := slot_lights[i]
		light.position = slot.court if in_court else slot.ext
		light.light_energy = float(slot.energy) * dim * _flicker(float(i))
	if gate_light != null:
		gate_light.light_energy = 3.2 * _flicker(9.0) * (1.0 - 0.55 * smoothstep(0.5, 1.0, blend))

func _flicker(phase: float) -> float:
	if not animated:
		return 1.0
	var t := _wall_clock
	return 0.90 + 0.06 * sin(t * 7.3 + phase * 2.1) + 0.04 * sin(t * 17.9 + phase * 5.3)

# ---------------------------------------------------------------------------------------------------------------------
# meshes
# ---------------------------------------------------------------------------------------------------------------------
func _mesh_instance(batch: Batch, material: Material, node_name: String) -> void:
	if batch.is_empty():
		return
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = batch.build_mesh()
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if quality == "high" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)

func _build_meshes(_q: int, builder: Builder) -> void:
	var stone_material := Assets.textured(Assets.stone_texture(), 0.92)
	_mesh_instance(builder.stone, stone_material, "Stone")
	var rock_material := Assets.textured(Assets.rock_texture(), 1.0)
	_mesh_instance(builder.rock, rock_material, "Terrain")
	var slate_material := Assets.textured(Assets.slate_texture(), 0.85)
	_mesh_instance(builder.roof, slate_material, "Roofs")
	var plain_material := Assets.plain(0.6)
	plain_material.metallic = 0.25
	_mesh_instance(builder.plain, plain_material, "Metal")
	var lit_material := Assets.plain(1.0, true)
	_mesh_instance(builder.lit, lit_material, "Windows")
	_banner_material = Assets.shader_material(Assets.BANNER_SHADER)
	_mesh_instance(builder.banners, _banner_material, "Banners")

func _build_statues(q: int, builder: Builder) -> void:
	# The six pieces share two materials sets (light / dark); merge every statue into one mesh per material.
	var buckets := {}
	var cache := {}
	for spec in builder.statues:
		var role: String = spec.role
		var side: String = spec.side
		var lod := "_lod1" if int(spec.lod) == 1 and q != Builder.Quality.HIGH or q == Builder.Quality.LOW else ""
		var key := role + "_" + side + lod
		if not cache.has(key):
			var packed := load(PIECES + key + ".glb") as PackedScene
			var mesh: Mesh = null
			if packed != null:
				var instance := packed.instantiate()
				for node in instance.find_children("*", "MeshInstance3D", true, false):
					mesh = (node as MeshInstance3D).mesh
					break
				cache[key] = [mesh, instance]
			else:
				cache[key] = [null, null]
		var entry: Array = cache[key]
		var mesh_value: Mesh = entry[0]
		if mesh_value == null:
			continue
		for surface in mesh_value.get_surface_count():
			var material := mesh_value.surface_get_material(surface)
			var bucket_key := side + ":" + (material.resource_name if material != null and material.resource_name != "" else str(surface))
			if not buckets.has(bucket_key):
				buckets[bucket_key] = [Batch.new(1), material]
			var batch: Batch = buckets[bucket_key][0]
			batch.add_arrays(mesh_value.surface_get_arrays(surface), spec.xf)
	for key in cache:
		var holder: Node = cache[key][1]
		if holder != null:
			holder.free()
	var index := 0
	for bucket_key in buckets:
		var data: Array = buckets[bucket_key]
		var batch: Batch = data[0]
		var instance := MeshInstance3D.new()
		instance.name = "Statues_" + str(bucket_key).replace(":", "_")
		instance.mesh = batch.build_mesh()
		var material: Material = data[1]
		if material is StandardMaterial3D:
			var copy := (material as StandardMaterial3D).duplicate() as StandardMaterial3D
			copy.vertex_color_use_as_albedo = false
			copy.metallic = minf(copy.metallic, 0.2)   # no reflection probe in this scene: keep the gold and bone trims readable
			copy.roughness = clampf(copy.roughness, 0.4, 0.9)
			instance.material_override = copy
		else:
			instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if quality == "high" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
		triangle_count += batch.triangle_count()
		index += 1

func _quad_mesh(size: float = 1.0) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	return quad

func _wide_aabb() -> AABB:
	return AABB(Vector3(-600, -120, -600), Vector3(1200, 400, 1200))

func _build_glows(_q: int, builder: Builder) -> void:
	if builder.glows.is_empty():
		return
	_glow_material = Assets.shader_material(Assets.GLOW_SHADER)
	_glow_material.set_shader_parameter("tex", Assets.glow_texture(64))
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = _quad_mesh(1.0)
	multimesh.instance_count = builder.glows.size()
	for i in builder.glows.size():
		var data: Dictionary = builder.glows[i]
		multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * float(data.size)), data.pos))
		multimesh.set_instance_color(i, data.color)
		multimesh.set_instance_custom_data(i, Color(float(data.phase), 1.0 if data.flicker else 0.0, 0.0, 0.0))
	var instance := MultiMeshInstance3D.new()
	instance.name = "Halos"
	instance.multimesh = multimesh
	instance.material_override = _glow_material
	instance.custom_aabb = _wide_aabb()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)

func _build_flames(builder: Builder) -> void:
	if builder.flames.is_empty():
		return
	_flame_material = Assets.shader_material(Assets.FLAME_SHADER)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = _quad_mesh(1.0)
	multimesh.instance_count = builder.flames.size()
	for i in builder.flames.size():
		var data: Dictionary = builder.flames[i]
		multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * float(data.height)), data.pos))
		multimesh.set_instance_custom_data(i, Color(float(data.phase), 0.0, 0.0, 0.0))
	var instance := MultiMeshInstance3D.new()
	instance.name = "Flames"
	instance.multimesh = multimesh
	instance.material_override = _flame_material
	instance.custom_aabb = _wide_aabb()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)

func _build_embers(q: int, builder: Builder) -> void:
	if builder.embers.is_empty():
		return
	var cap := {Builder.Quality.LOW: 24, Builder.Quality.BALANCED: 72, Builder.Quality.HIGH: 144}[q] as int
	var per := maxi(1, mini(10, cap / builder.embers.size()))
	var total := per * builder.embers.size()
	_ember_material = Assets.shader_material(Assets.EMBER_SHADER)
	_ember_material.set_shader_parameter("tex", Assets.glow_texture(32))
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = _quad_mesh(1.0)
	multimesh.instance_count = total
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var n := 0
	for pos in builder.embers:
		for k in per:
			multimesh.set_instance_transform(n, Transform3D(Basis.IDENTITY, pos))
			multimesh.set_instance_custom_data(n, Color(rng.randf(), rng.randf(), rng.randf(), 0.0))
			n += 1
	var instance := MultiMeshInstance3D.new()
	instance.name = "Embers"
	instance.multimesh = multimesh
	instance.material_override = _ember_material
	instance.custom_aabb = _wide_aabb()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)

func ember_count() -> int:
	var embers := get_node_or_null("Embers") as MultiMeshInstance3D
	return embers.multimesh.instance_count if embers != null else 0

func _build_mist(builder: Builder) -> void:
	if builder.mist_cards.is_empty():
		return
	var texture := Assets.mist_texture(96)
	var holder := Node3D.new()
	holder.name = "Mist"
	add_child(holder)
	for i in builder.mist_cards.size():
		var card: Dictionary = builder.mist_cards[i]
		var material := Assets.shader_material(Assets.MIST_SHADER)
		material.set_shader_parameter("tex", texture)
		material.set_shader_parameter("tint", Color(0.20, 0.26, 0.44, 0.34))
		material.set_shader_parameter("drift", Vector2(0.004 * (1 if i % 2 == 0 else -1), 0.0015))
		material.render_priority = -1
		_mist_materials.append(material)
		var plane := PlaneMesh.new()
		plane.size = Vector2(float(card.size), float(card.size))
		var instance := MeshInstance3D.new()
		instance.mesh = plane
		instance.material_override = material
		instance.position = card.pos
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(instance)

# ---------------------------------------------------------------------------------------------------------------------
# camera
# ---------------------------------------------------------------------------------------------------------------------
## Catmull-Rom through the shot's waypoints: up the bridge between the giants, through the gate, into the courtyard.
func _path(s: float) -> Vector3:
	var pts := [CAM_A, Vector3(0.0, 3.6, 30.0), Vector3(0.0, 4.2, 2.0), Vector3(-8.0, 6.0, -8.0), CAM_B]
	var segs := pts.size() - 1
	var f := clampf(s, 0.0, 1.0) * segs
	var i := mini(int(floor(f)), segs - 1)
	var t := f - i
	var p0: Vector3 = pts[maxi(i - 1, 0)]
	var p1: Vector3 = pts[i]
	var p2: Vector3 = pts[i + 1]
	var p3: Vector3 = pts[mini(i + 2, segs)]
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)

func set_blend(value: float) -> void:
	blend = clampf(value, 0.0, 1.0)
	drift_rate = lerpf(1.0, 0.55, blend)
	_apply_camera()
	_update_lights()

func _drift_offset() -> Vector3:
	if not animated:
		return Vector3.ZERO
	var amp := lerpf(1.0, 0.32, blend)
	return Vector3(sin(_clock * 0.13) * 2.4 + sin(_clock * 0.047) * 1.6, sin(_clock * 0.09) * 0.45, sin(_clock * 0.071 + 1.0) * 3.0) * amp

func _apply_camera() -> void:
	if camera == null:
		return
	var s := blend
	var pos := _path(s) + _drift_offset()
	var look_ease := smoothstep(0.0, 1.0, clampf((s - 0.05) / 0.9, 0.0, 1.0))
	var look := LOOK_A.lerp(LOOK_B, look_ease)
	if animated:
		look += Vector3(sin(_clock * 0.061) * 1.6, sin(_clock * 0.083 + 2.0) * 0.5, 0.0) * lerpf(1.0, 0.3, s)
	var up := Vector3.UP
	var roll := sin(s * PI) * 0.045
	var basis := Basis.looking_at((look - pos).normalized(), up)
	basis = basis * Basis(Vector3.BACK, roll)
	camera.transform = Transform3D(basis, pos)
	_update_projection(s)

func _update_projection(s: float) -> void:
	var size := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1280, 800)
	_viewport_size = size
	var aspect := size.x / maxf(size.y, 1.0)
	var swoosh := sin(s * PI)
	if aspect >= 1.15:
		camera.keep_aspect = Camera3D.KEEP_HEIGHT
		camera.fov = lerpf(46.0, 55.0, s) + 12.0 * swoosh * swoosh
	else:
		camera.keep_aspect = Camera3D.KEEP_WIDTH
		camera.fov = lerpf(66.0, 74.0, s) + 12.0 * swoosh * swoosh

## Advance the idle motion by `delta` seconds (the screen calls this; tests call it with explicit steps).
func advance(delta: float) -> void:
	_wall_clock += delta
	if animated:
		_clock += delta * drift_rate
	_apply_camera()
	_update_lights()
	if _sky != null:
		_sky.set_shader_parameter("t", _wall_clock if animated else 0.0)

func _process(delta: float) -> void:
	advance(delta)

func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE and camera != null:
		camera.make_current()
	elif what == NOTIFICATION_VISIBILITY_CHANGED:
		set_process(visible and animated)

func stats() -> Dictionary:
	var meshes := 0
	var lights := 0
	for node in find_children("*", "", true, false):
		if node is MeshInstance3D or node is MultiMeshInstance3D:
			meshes += 1
		elif node is Light3D:
			lights += 1
	return {"draw_nodes": meshes, "lights": lights, "triangles": triangle_count, "embers": ember_count(), "build_msec": build_msec, "quality": quality}
