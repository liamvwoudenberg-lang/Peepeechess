extends SceneTree
## Geometry, quality and camera-cutaway regressions without a GPU or the combat simulation.
const Courtyard = preload("res://boards/courtyard_environment.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)

func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var camera := Camera3D.new()
	scene.add_child(camera)
	var court := Courtyard.new()
	scene.add_child(court)
	court.setup(camera, "high")
	check(court.is_in_group("courtyard_quality"), "graphics settings find the courtyard")
	check(court.triangles > 12000 and court.triangles < 45000, "bounded detailed courtyard geometry: %d triangles" % court.triangles)
	check(court.torch_lights.size() == 4, "four pooled torch lights")
	check(court.find_children("*", "CollisionObject3D", true, false).is_empty(), "decorative environment never changes picking or combat collisions")
	var minimum_clearance := 100.0
	for node in court.find_children("*", "MeshInstance3D", true, false):
		check(node.layers == 2, "castle uses board lighting layer")
		var vertices: PackedVector3Array = node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			minimum_clearance = minf(minimum_clearance, maxf(absf(vertex.x), absf(vertex.z)))
	check(minimum_clearance >= 4.449, "all decoration stays outside board frame (%0.3f m)" % minimum_clearance)
	var node_count := court.get_child_count()
	for preset in ["low", "balanced", "high"]:
		court.set_quality(preset)
		var lit := 0
		for light in court.torch_lights:
			lit += int(light.visible)
		check(lit == {"low": 1, "balanced": 2, "high": 4}[preset], "real lights capped for " + preset)
		check(court.get_child_count() == node_count, "graphics changes reuse all geometry")
	court.set_motion(false)
	for banner in court._banner_materials:
		check(is_zero_approx(float(banner.get_shader_parameter("wind"))), "reduced motion freezes each banner")
	camera.position = Vector3(0, 3, 12)
	camera.look_at(Vector3(0, 0.8, 0))
	court.update_camera(1.0)
	var faded := 0
	var solid := 0
	for section in court.architecture:
		if section.alpha < 0.2:
			faded += 1
		else:
			solid += 1
	check(faded > 0 and solid > 0, "only obstructing architecture fades")
	camera.position = Vector3(0, 16, 5)
	camera.look_at(Vector3(0, 0.8, 0))
	court.update_camera(1.0)
	var restored := true
	for section in court.architecture:
		restored = restored and section.alpha > 0.995
	check(restored, "architecture returns when the view clears")
	check(court.get_child_count() == node_count, "camera fading never allocates scene nodes")
	court.setup(camera, "balanced")
	check(court.get_child_count() == node_count, "repeated setup is idempotent")
	scene.free()
	await process_frame
	print("Courtyard environment: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
