class_name ClassicPieceMeshes
extends RefCounted
## Portable, role-specific 3D geometry. No combat/Blender resources required.
static func material(color: Color, metallic: float = 0.0) -> StandardMaterial3D:
	var value = StandardMaterial3D.new()
	value.albedo_color = color
	value.metallic = metallic
	value.roughness = 0.32 if metallic > 0 else 0.6
	return value

static func add(root: Node3D, mesh: Mesh, at: Vector3, mat: Material, scale_value: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var part = MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = mat
	part.position = at
	part.scale = scale_value
	root.add_child(part)
	return part

static func cylinder(root: Node3D, radius: float, top: float, height: float, y: float, mat: Material) -> void:
	var mesh = CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = top
	mesh.height = height
	mesh.radial_segments = 24
	add(root, mesh, Vector3(0, y, 0), mat)

static func box(root: Node3D, dimensions: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mesh = BoxMesh.new()
	mesh.size = dimensions
	return add(root, mesh, at, mat)

static func sphere(root: Node3D, radius: float, at: Vector3, mat: Material, scale_value: Vector3 = Vector3.ONE) -> void:
	var mesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2
	mesh.radial_segments = 20
	mesh.rings = 12
	add(root, mesh, at, mat, scale_value)

static func build(role: String, color: String) -> Node3D:
	var custom = BoardThemeView.build_piece(role, color)  # alternate piece set from board settings; null = built-in procedural set
	if custom != null:
		return BoardThemeView.finish_piece(custom)
	var root = Node3D.new()
	var body = material(Color("d4cbb2") if color == "w" else Color("303e50"), 0.18)
	var trim = material(Color("cfa958") if color == "w" else Color("b4866c"), 0.7)
	var dark = material(Color("30474b"), 0.1)
	var height: float = {"p": 0.7, "n": 0.92, "b": 1.05, "r": 0.82, "q": 1.16, "k": 1.26}[role]
	cylinder(root, 0.32, 0.29, 0.10, 0.10, trim)
	cylinder(root, 0.29, 0.24, 0.12, 0.19, body)
	cylinder(root, 0.23, 0.13, height * 0.48, 0.25 + height * 0.24, body)
	cylinder(root, 0.20, 0.20, 0.06, height * 0.65, trim)
	match role:
		"p":
			sphere(root, 0.19, Vector3(0, 0.64, 0), body)
		"r":
			cylinder(root, 0.24, 0.25, 0.30, 0.68, body)
			for i in range(6):
				var angle = i * TAU / 6
				var block = box(root, Vector3(0.14, 0.17, 0.14), Vector3(sin(angle) * 0.18, 0.9, cos(angle) * 0.18), body)
				block.rotation.y = angle
		"n":
			var neck = box(root, Vector3(0.25, 0.46, 0.28), Vector3(0, 0.69, 0), body)
			neck.rotation.x = -0.35
			box(root, Vector3(0.27, 0.22, 0.43), Vector3(0, 0.93, -0.11), body)
			for x in [-0.085, 0.085]:
				box(root, Vector3(0.07, 0.15, 0.09), Vector3(x, 1.1, 0.015), trim)
				box(root, Vector3(0.025, 0.045, 0.055), Vector3(x * 1.64, 0.97, -0.13), dark)
			for y in range(4):
				box(root, Vector3(0.10, 0.09, 0.12), Vector3(0, 0.63 + y * 0.1, 0.17), trim)
		"b":
			sphere(root, 0.2, Vector3(0, 0.90, 0), body, Vector3(0.88, 1.45, 0.88))
			var slit = box(root, Vector3(0.025, 0.22, 0.30), Vector3(0.055, 1.01, 0), dark)
			slit.rotation.z = -0.5
			sphere(root, 0.055, Vector3(0, 1.2, 0), trim)
		"q":
			cylinder(root, 0.13, 0.23, 0.22, 0.98, body)
			for i in range(5):
				var angle = i * TAU / 5
				sphere(root, 0.065, Vector3(sin(angle) * 0.20, 1.14, cos(angle) * 0.20), trim)
			cylinder(root, 0.09, 0.04, 0.16, 1.14, trim)
		"k":
			cylinder(root, 0.18, 0.18, 0.18, 0.99, body)
			box(root, Vector3(0.10, 0.40, 0.10), Vector3(0, 1.26, 0), trim)
			box(root, Vector3(0.32, 0.09, 0.10), Vector3(0, 1.31, 0), trim)
	PieceCrest.attach(root, role, color)
	return BoardThemeView.finish_piece(root)
