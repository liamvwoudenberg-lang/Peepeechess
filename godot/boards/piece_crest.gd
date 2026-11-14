class_name PieceCrest
extends RefCounted
## Board-only heraldry. The cached, vertex-coloured mesh costs one draw per pedestal; it has no
## collider and never changes a fighter, a chess coordinate, or the supplied Meshy geometry.
const RADIUS := 0.44
const TOP := 0.13
static var _meshes: Dictionary = {}
static var _material: StandardMaterial3D


static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.roughness = 0.62
		_material.metallic = 0.25
	return _material


static func attach(root: Node3D, role: String, side: String) -> MeshInstance3D:
	var key := role + side
	if not _meshes.has(key):
		_meshes[key] = _build_base(role, side)
	var part := MeshInstance3D.new()
	part.name = "ClassCrest"
	part.mesh = _meshes[key]
	part.material_override = material()
	part.set_meta("role", role)
	part.set_meta("side", side)
	root.add_child(part)
	return part


static func _append(tool: SurfaceTool, mesh: Mesh, transform: Transform3D, color: Color) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for i in indices.size() if not indices.is_empty() else vertices.size():
		var at: int = indices[i] if not indices.is_empty() else i
		tool.set_color(color)
		tool.set_normal((transform.basis * normals[at]).normalized())
		tool.add_vertex(transform * vertices[at])


static func _cylinder(tool: SurfaceTool, radius: float, height: float, at: Vector3, color: Color, top: float = -1.0) -> void:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top < 0.0 else top
	mesh.height = height
	mesh.radial_segments = 32
	_append(tool, mesh, Transform3D(Basis.IDENTITY, at), color)


static func _box(tool: SurfaceTool, size: Vector3, at: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_append(tool, mesh, Transform3D(Basis.IDENTITY, at), color)


static func _ring(tool: SurfaceTool, inner: float, outer: float, y: float, color: Color) -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 40
	mesh.ring_segments = 6
	_append(tool, mesh, Transform3D(Basis.IDENTITY, Vector3(0, y, 0)), color)


static func _build_base(role: String, side: String) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rim := Color("eee6d0") if side == "w" else Color("17202b")
	var well := Color("303c43") if side == "w" else Color("b5a78c")
	var trim := Color("c9a35b") if side == "w" else Color("a68166")
	_cylinder(tool, RADIUS, 0.055, Vector3(0, 0.0675, 0), rim)
	_cylinder(tool, 0.402, 0.035, Vector3(0, 0.1125, 0), well)
	_ring(tool, 0.408, 0.438, 0.094, rim)
	_ring(tool, 0.377, 0.396, 0.13, trim)
	# Two mirrored badges remain visible beyond the feet from either side of the board. Each has a
	# familiar chess silhouette rather than a text/font dependency, so it also works on Android.
	for direction in [-1.0, 1.0]:
		var badge := Vector3(0, TOP + 0.004, direction * 0.297)
		_cylinder(tool, 0.105, 0.008, badge, rim)
		_symbol(tool, role, badge + Vector3(0, 0.005, 0), 0.078, well, direction)
	tool.index()
	return tool.commit()


static func _symbol(tool: SurfaceTool, role: String, at: Vector3, unit: float, color: Color, direction: float) -> void:
	# Glyphs lie in the XZ plane. Their raised top surface remains crisp without expensive decals.
	var outline: PackedVector2Array
	match role:
		"p":
			_cylinder(tool, unit * 0.42, 0.006, at + Vector3(0, 0, -unit * 0.48 * direction), color)
			outline = PackedVector2Array([Vector2(-0.25, -0.1), Vector2(0.25, -0.1), Vector2(0.35, 0.45), Vector2(0.65, 0.7), Vector2(-0.65, 0.7), Vector2(-0.35, 0.45)])
		"n":
			outline = PackedVector2Array([Vector2(-0.7, 0.75), Vector2(-0.5, 0.2), Vector2(-0.4, -0.35), Vector2(-0.2, -0.85), Vector2(0.0, -0.65), Vector2(0.4, -0.55), Vector2(0.8, -0.2), Vector2(0.7, 0.05), Vector2(0.2, 0.0), Vector2(0.3, 0.3), Vector2(0.65, 0.75)])
		"b":
			outline = PackedVector2Array([Vector2(0.0, -0.9), Vector2(0.55, -0.15), Vector2(0.2, 0.25), Vector2(0.55, 0.7), Vector2(-0.55, 0.7), Vector2(-0.2, 0.25), Vector2(-0.55, -0.15), Vector2(-0.12, -0.74), Vector2(-0.05, -0.1), Vector2(0.12, -0.1)])
		"r":
			outline = PackedVector2Array([Vector2(-0.7, 0.75), Vector2(-0.45, 0.45), Vector2(-0.45, -0.2), Vector2(-0.75, -0.4), Vector2(-0.75, -0.85), Vector2(-0.35, -0.85), Vector2(-0.35, -0.55), Vector2(-0.15, -0.55), Vector2(-0.15, -0.85), Vector2(0.15, -0.85), Vector2(0.15, -0.55), Vector2(0.35, -0.55), Vector2(0.35, -0.85), Vector2(0.75, -0.85), Vector2(0.75, -0.4), Vector2(0.45, -0.2), Vector2(0.45, 0.45), Vector2(0.7, 0.75)])
		"q":
			outline = PackedVector2Array([Vector2(-0.65, 0.75), Vector2(-0.9, -0.65), Vector2(-0.4, -0.15), Vector2(0, -0.95), Vector2(0.4, -0.15), Vector2(0.9, -0.65), Vector2(0.65, 0.75)])
		_:
			outline = PackedVector2Array([Vector2(-0.22, 0.8), Vector2(-0.22, 0.15), Vector2(-0.7, 0.15), Vector2(-0.7, -0.25), Vector2(-0.22, -0.25), Vector2(-0.22, -0.85), Vector2(0.22, -0.85), Vector2(0.22, -0.25), Vector2(0.7, -0.25), Vector2(0.7, 0.15), Vector2(0.22, 0.15), Vector2(0.22, 0.8)])
	var triangles := Geometry2D.triangulate_polygon(outline)
	for index in triangles:
		var point := outline[index] * unit
		tool.set_color(color)
		tool.set_normal(Vector3.UP)
		tool.add_vertex(at + Vector3(point.x, 0, point.y * direction))
		# The mirrored badge reverses winding; material culling is avoided with a second top triangle below.
	# Flip the top triangles as well: the crest remains visible for both board orientations.
	for i in range(0, triangles.size(), 3):
		for index in [triangles[i + 2], triangles[i + 1], triangles[i]]:
			var point := outline[index] * unit
			tool.set_color(color)
			tool.set_normal(Vector3.UP)
			tool.add_vertex(at + Vector3(point.x, 0, point.y * direction))


static func crown(model: PaladinModel, role: String, side: String) -> void:
	if role not in ["k", "q"] or model.skeleton == null:
		return
	var index := -1
	for i in model.skeleton.get_bone_count():
		if model.skeleton.get_bone_name(i).ends_with("HeadTop_End"):
			index = i
			break
	if index < 0:
		return
	var socket := BoneAttachment3D.new()
	socket.name = "RoyalCrown"
	socket.bone_name = model.skeleton.get_bone_name(index)
	model.skeleton.add_child(socket)
	var key := "crown" + role + side
	if not _meshes.has(key):
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		var gold := Color("e9c36e") if side == "w" else Color("d1a16c")
		_ring(tool, 0.105, 0.135, 0.025, gold)
		var points := 4 if role == "k" else 5
		for i in points:
			var angle := TAU * i / points
			_cylinder(tool, 0.032, 0.12 if role == "k" else 0.16, Vector3(sin(angle) * 0.12, 0.08, cos(angle) * 0.12), gold, 0.006)
		if role == "k":
			_box(tool, Vector3(0.052, 0.25, 0.052), Vector3(0, 0.16, 0), gold)
			_box(tool, Vector3(0.19, 0.052, 0.052), Vector3(0, 0.21, 0), gold)
		else:
			_cylinder(tool, 0.045, 0.10, Vector3(0, 0.07, 0), gold, 0.0)
		tool.index()
		_meshes[key] = tool.commit()
	var part := MeshInstance3D.new()
	part.name = "KingCross" if role == "k" else "QueenFivePointCrown"
	part.mesh = _meshes[key]
	part.material_override = material()
	socket.add_child(part)
