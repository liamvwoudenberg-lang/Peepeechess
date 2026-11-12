extends RefCounted
## Cheap world-space ribbon between two moving points (a weapon's grip->tip, or a body's feet->head):
## one ImmediateMesh triangle strip rebuilt from a tiny fixed ring buffer each frame (<= ~12 points).
## Presentation only. No allocation in the update path beyond the mesh surface itself.

var node: MeshInstance3D
var mesh: ImmediateMesh
var mat: StandardMaterial3D
var max_points: int = 10
var life: float = 0.16
var color: Color = Color(1, 1, 1, 0.6)
var base_pts: PackedVector3Array = PackedVector3Array()
var tip_pts: PackedVector3Array = PackedVector3Array()
var ages: PackedFloat32Array = PackedFloat32Array()
var count: int = 0


func _init(parent: Node, points: int) -> void:
	max_points = maxi(points, 2)
	base_pts.resize(max_points)
	tip_pts.resize(max_points)
	ages.resize(max_points)
	mesh = ImmediateMesh.new()
	mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	node = MeshInstance3D.new()
	node.mesh = mesh
	node.top_level = true  # world space, independent of whatever it is parented to
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visible = false
	parent.add_child(node)


func clear() -> void:
	count = 0
	mesh.clear_surfaces()
	node.visible = false


## Adds the newest sample (index 0); older samples shift down. Dropped when the ring is full.
func push(base: Vector3, tip: Vector3) -> void:
	var last: int = mini(count, max_points - 1)
	for i in range(last, 0, -1):
		base_pts[i] = base_pts[i - 1]
		tip_pts[i] = tip_pts[i - 1]
		ages[i] = ages[i - 1]
	base_pts[0] = base
	tip_pts[0] = tip
	ages[0] = 0.0
	count = mini(count + 1, max_points)


## Ages samples, drops expired ones and rebuilds the strip. `dt` = 0 freezes the ribbon (hitstop).
func update(dt: float) -> void:
	if count == 0:
		return
	var keep := 0
	for i in count:
		ages[i] += dt
		if ages[i] <= life:
			keep = i + 1
	count = keep
	mesh.clear_surfaces()
	if count < 2:
		node.visible = false
		return
	node.visible = true
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, mat)
	for i in count:
		var fade := 1.0 - clampf(ages[i] / life, 0.0, 1.0)
		var c := Color(color.r, color.g, color.b, color.a * fade * fade)
		mesh.surface_set_color(c)
		mesh.surface_add_vertex(base_pts[i])
		mesh.surface_set_color(c)
		mesh.surface_add_vertex(tip_pts[i])
	mesh.surface_end()
