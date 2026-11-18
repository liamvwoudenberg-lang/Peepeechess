class_name BoardFx
extends RefCounted
## Cosmetic effects of the idle 3D board scene: real flame / ember / smoke particles for torches and braziers, and additive light
## shafts. Pure presentation. Particles obey GraphicsSettings.particles and shafts GraphicsSettings.light_shafts; both are re-applied
## when Settings change (events().changed). Everything lives under the "Scenery" node, which is hidden while a duel runs.

const L := preload("res://world/board_look.gd")

static var _cache: Dictionary = {}


## Child of the scenery that shows or hides its children following one graphics toggle ("particles" or "light_shafts").
class Gate:
	extends Node3D
	var key := "particles"

	func _ready() -> void:
		GraphicsSettings.events().changed.connect(apply)
		apply()

	func _exit_tree() -> void:
		if GraphicsSettings.events().changed.is_connected(apply):
			GraphicsSettings.events().changed.disconnect(apply)

	func apply() -> void:
		var on: bool = GraphicsSettings.particles if key == "particles" else GraphicsSettings.light_shafts
		visible = on
		for c in find_children("*", "GPUParticles3D", true, false):
			c.emitting = on


static func gate(parent: Node3D, key: String) -> Gate:
	var g := Gate.new()
	g.name = "Fx_" + key
	g.key = key
	parent.add_child(g)
	return g


static func _soft_texture() -> Texture2D:
	if _cache.has("soft"):
		return _cache["soft"]
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = grad
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	_cache["soft"] = t
	return t


static func _quad_material(additive: bool) -> StandardMaterial3D:
	var key := "qm_add" if additive else "qm_mix"
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_texture()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	_cache[key] = m
	return m


static func _ramp(colors: Array, offsets: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


static func _curve(points: Array) -> CurveTexture:
	var c := Curve.new()
	for p in points:
		c.add_point(p)
	var t := CurveTexture.new()
	t.curve = c
	return t


static func _layer(parent: Node3D, amount: int, lifetime: float, additive: bool, size: float, pm: ParticleProcessMaterial) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = _quad_material(additive)
	p.draw_pass_1 = q
	p.visibility_aabb = AABB(Vector3(-1.5, -0.5, -1.5), Vector3(3, 5, 3))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.local_coords = false
	parent.add_child(p)
	return p


## Flame + rising embers + soft smoke at `at` (scenery-local). `s` scales the whole fire (brazier 1.0, wall torch ~0.7).
static func fire(g: Node3D, at: Vector3, s: float = 1.0) -> void:
	var root := Node3D.new()
	root.position = at
	g.add_child(root)
	# flame: additive orange -> red, shrinking as it rises
	var f := ParticleProcessMaterial.new()
	f.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	f.emission_sphere_radius = 0.13 * s
	f.direction = Vector3(0, 1, 0)
	f.spread = 12.0
	f.initial_velocity_min = 0.35 * s
	f.initial_velocity_max = 0.8 * s
	f.gravity = Vector3(0, 0.6, 0)
	f.damping_min = 0.2
	f.damping_max = 0.5
	f.scale_min = 0.8
	f.scale_max = 1.2
	f.scale_curve = _curve([Vector2(0, 0.6), Vector2(0.25, 1.0), Vector2(1, 0.0)])
	f.color_ramp = _ramp([Color(1.0, 0.93, 0.6, 0.95), Color(1.0, 0.55, 0.14, 0.8), Color(0.75, 0.16, 0.05, 0.0)], [0.0, 0.4, 1.0])
	_layer(root, 22, 0.75, true, 0.55 * s, f).name = "Flame"
	# embers: tiny bright sparks drifting up and sideways
	var e := ParticleProcessMaterial.new()
	e.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	e.emission_sphere_radius = 0.16 * s
	e.direction = Vector3(0, 1, 0)
	e.spread = 38.0
	e.initial_velocity_min = 0.5 * s
	e.initial_velocity_max = 1.3 * s
	e.gravity = Vector3(0.15, 0.35, 0.05)
	e.scale_min = 0.5
	e.scale_max = 1.0
	e.color_ramp = _ramp([Color(1.0, 0.85, 0.4, 1.0), Color(1.0, 0.5, 0.12, 0.9), Color(0.8, 0.2, 0.05, 0.0)], [0.0, 0.5, 1.0])
	_layer(root, 14, 2.6, true, 0.07 * maxf(s, 0.8), e).name = "Embers"
	# smoke: faint cool grey, grows and fades
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.1 * s
	m.direction = Vector3(0, 1, 0)
	m.spread = 14.0
	m.initial_velocity_min = 0.3 * s
	m.initial_velocity_max = 0.6 * s
	m.gravity = Vector3(0.1, 0.25, 0)
	m.scale_min = 0.8
	m.scale_max = 1.3
	m.scale_curve = _curve([Vector2(0, 0.4), Vector2(1, 1.8)])
	m.color_ramp = _ramp([Color(0.35, 0.36, 0.42, 0.0), Color(0.35, 0.36, 0.42, 0.22), Color(0.2, 0.22, 0.28, 0.0)], [0.0, 0.25, 1.0])
	var smoke := _layer(root, 8, 3.0, false, 0.9 * s, m)
	smoke.name = "Smoke"
	smoke.position = Vector3(0, 0.35 * s, 0)


const SHAFT_SHADER := "
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 tint = vec3(1.0, 0.8, 0.5);
uniform float strength = 0.16;
void fragment() {
	float along = 1.0 - UV.y;
	float rim = pow(clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 1.6);
	ALBEDO = tint;
	ALPHA = strength * rim * (0.15 + 0.85 * smoothstep(0.0, 0.5, along)) * smoothstep(0.0, 0.18, UV.y);
}
"


static func _shaft_material() -> ShaderMaterial:
	if _cache.has("shaft"):
		return _cache["shaft"]
	var sh := Shader.new()
	sh.code = SHAFT_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("tint", Vector3(L.KEY_COLOR.r, L.KEY_COLOR.g, L.KEY_COLOR.b))
	m.set_shader_parameter("strength", L.SHAFT_STRENGTH)
	_cache["shaft"] = m
	return m


## Soft additive cones of dusk light falling along the key light's direction onto the courtyard, ending OUTSIDE the play area.
static func shafts(g: Node3D, floor_y: float) -> void:
	var rot := Basis.from_euler(Vector3(deg_to_rad(L.KEY_ROTATION.x), deg_to_rad(L.KEY_ROTATION.y), deg_to_rad(L.KEY_ROTATION.z)), EULER_ORDER_YXZ)
	var dir := (rot * Vector3.FORWARD).normalized()
	var up := -dir
	var x_axis := up.cross(Vector3.FORWARD).normalized()
	var basis := Basis(x_axis, up, x_axis.cross(up).normalized())
	for target in L.SHAFT_TARGETS:
		var length: float = L.SHAFT_LENGTH
		var hit := Vector3(target.x, floor_y, target.y)
		var mesh := CylinderMesh.new()
		mesh.top_radius = L.SHAFT_RADIUS_TOP
		mesh.bottom_radius = L.SHAFT_RADIUS_BOTTOM
		mesh.height = length
		mesh.radial_segments = 20
		mesh.rings = 1
		mesh.cap_top = false
		mesh.cap_bottom = false
		var n := MeshInstance3D.new()
		n.mesh = mesh
		n.material_override = _shaft_material()
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# the cylinder's +Y end is the source: its centre sits half a length up the reversed light direction from the hit point
		n.transform = Transform3D(basis, hit + up * (length * 0.5))
		g.add_child(n)
