extends SceneTree
## Regression for the flickering chequer tiles on the opening screen (root cause: the top faces of the bridge piers sat at exactly y = 0,
## coplanar with the bridge's chequer quads, so the two surfaces z-fought). Headless: no coplanar overlapping horizontal surfaces at the
## tile plane, no duplicated tile quads, and the check is proven sensitive by re-enabling the old pier tops.
##   godot --headless --path godot --script res://tests/ui/tile_stability_test.gd
const Scan = preload("res://tests/ui/coplanar_scan.gd")
const OpeningScene = preload("res://ui/opening/opening_scene.gd")
const Builder = preload("res://ui/opening/castle_builder.gd")
var checks := 0
var failures: Array = []

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL: ", label)

func _initialize() -> void:
	call_deferred("run")

## Coplanar overlapping pairs on the horizontal plane y = `y` (either facing).
func horizontal_pairs(report: Dictionary, y: float) -> int:
	var count := 0
	for p in report["pairs"]:
		if absf(p["normal"].y) > 0.99 and absf(absf(p["plane"]) - absf(y)) < 0.01:
			count += 1
	return count

func build_report(quality: String) -> Dictionary:
	var s := OpeningScene.new()
	root.add_child(s)
	s.build(quality, false, 0.0)
	var report := Scan.scan(s)
	report["quads"] = _tile_quads(s)
	s.free()
	return report

## Number of distinct horizontal triangles at y = 0 (tile quads): a duplicated board would double them.
func _tile_quads(scene: Node) -> Dictionary:
	var seen := {}
	var dup := 0
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for surface in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(surface)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx = arrays[Mesh.ARRAY_INDEX]
			var n: int = idx.size() if idx != null else verts.size()
			for i in range(0, n - 2, 3):
				var a: Vector3 = verts[idx[i] if idx != null else i]
				var b: Vector3 = verts[idx[i + 1] if idx != null else i + 1]
				var c: Vector3 = verts[idx[i + 2] if idx != null else i + 2]
				if absf(a.y) < 0.001 and absf(b.y) < 0.001 and absf(c.y) < 0.001:
					var key := "%d|%d|%s|%s|%s" % [mi.get_instance_id(), surface, str(a.snapped(Vector3.ONE * 0.01)), str(b.snapped(Vector3.ONE * 0.01)), str(c.snapped(Vector3.ONE * 0.01))]
					if seen.has(key):
						dup += 1
					seen[key] = true
	return {"distinct": seen.size(), "duplicates": dup}

func run() -> void:
	for quality in ["low", "balanced", "high"]:
		var report := build_report(quality)
		expect(report["triangles"] > 1000, "%s: the scene has geometry (%d triangles)" % [quality, report["triangles"]])
		expect(horizontal_pairs(report, 0.0) == 0, "%s: no coplanar overlap on the tile plane y=0 (%d pairs)" % [quality, horizontal_pairs(report, 0.0)])
		expect(report["quads"]["duplicates"] == 0, "%s: no duplicated tile triangles (%d distinct)" % [quality, report["quads"]["distinct"]])
	# sensitivity: the old geometry must be detected
	Builder.debug_pier_tops = true
	var legacy := build_report("balanced")
	Builder.debug_pier_tops = false
	expect(horizontal_pairs(legacy, 0.0) > 100, "the check sees the old pier tops (%d pairs at y=0)" % horizontal_pairs(legacy, 0.0))
	print("TILE STABILITY: ", checks, " checks; failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
