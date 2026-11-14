extends RefCounted
## Finds coplanar overlapping triangles (the cause of z-fighting) in the MeshInstance3Ds under a node.
##   Scan.scan(node) -> {pairs: Array[{a, b, plane, normal, at}], triangles: int}
## Two same-facing triangles are a z-fight pair when their planes agree (normals parallel, plane offsets within EPS_PLANE) and their
## footprints overlap with real area (Sutherland-Hodgman clip in the dominant plane).
const EPS_PLANE := 0.004
const MIN_AREA := 0.0005

static func scan(root: Node) -> Dictionary:
	var tris: Array = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.visible:
			continue
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			if arrays.size() <= Mesh.ARRAY_VERTEX or arrays[Mesh.ARRAY_VERTEX] == null:
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx = arrays[Mesh.ARRAY_INDEX]
			var count: int = idx.size() if idx != null else verts.size()
			for i in range(0, count - 2, 3):
				var a: Vector3 = mi.global_transform * verts[idx[i] if idx != null else i]
				var b: Vector3 = mi.global_transform * verts[idx[i + 1] if idx != null else i + 1]
				var c: Vector3 = mi.global_transform * verts[idx[i + 2] if idx != null else i + 2]
				var n := (b - a).cross(c - a)
				if n.length() < 1e-6:
					continue
				var nn := n.normalized()
				tris.append({"a": a, "b": b, "c": c, "n": nn, "d": nn.dot(a), "mesh": mi.name})
	var pairs: Array = []
	var buckets: Dictionary = {}
	for i in tris.size():
		var t: Dictionary = tris[i]
		var key := "%d_%d" % [int(round(t["d"] / EPS_PLANE)), _axis(t["n"])]
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(i)
	for key in buckets:
		var list: Array = buckets[key]
		if list.size() < 2 or list.size() > 6000:
			continue
		for x in list.size():
			for y in range(x + 1, list.size()):
				var p: Dictionary = tris[list[x]]
				var q: Dictionary = tris[list[y]]
				if p["n"].dot(q["n"]) < 0.9999:
					continue
				if absf(p["d"] - q["d"]) > EPS_PLANE:
					continue
				if _overlap_area(p, q) > MIN_AREA:
					pairs.append({"a": p["mesh"], "b": q["mesh"], "plane": p["d"], "normal": p["n"], "at": (p["a"] + p["b"] + p["c"]) / 3.0})
	return {"pairs": pairs, "triangles": tris.size()}

static func _axis(n: Vector3) -> int:
	var ax := n.abs()
	return 0 if ax.x >= ax.y and ax.x >= ax.z else (1 if ax.y >= ax.z else 2)

static func _project(v: Vector3, axis: int) -> Vector2:
	return Vector2(v.y, v.z) if axis == 0 else (Vector2(v.x, v.z) if axis == 1 else Vector2(v.x, v.y))

static func _overlap_area(p: Dictionary, q: Dictionary) -> float:
	var axis := _axis(p["n"])
	var poly: Array = [_project(p["a"], axis), _project(p["b"], axis), _project(p["c"], axis)]
	var clip: Array = [_project(q["a"], axis), _project(q["b"], axis), _project(q["c"], axis)]
	if _signed_area(clip) < 0.0:
		clip.reverse()
	if _signed_area(poly) < 0.0:
		poly.reverse()
	for i in 3:
		var e0: Vector2 = clip[i]
		var e1: Vector2 = clip[(i + 1) % 3]
		var out: Array = []
		for j in poly.size():
			var cur: Vector2 = poly[j]
			var prev: Vector2 = poly[(j + poly.size() - 1) % poly.size()]
			var cur_in := (e1 - e0).cross(cur - e0) >= -1e-9
			var prev_in := (e1 - e0).cross(prev - e0) >= -1e-9
			if cur_in:
				if not prev_in:
					out.append(_isect(prev, cur, e0, e1))
				out.append(cur)
			elif prev_in:
				out.append(_isect(prev, cur, e0, e1))
		poly = out
		if poly.size() < 3:
			return 0.0
	return absf(_signed_area(poly))

static func _signed_area(poly: Array) -> float:
	var s := 0.0
	for i in poly.size():
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		s += a.x * b.y - b.x * a.y
	return s * 0.5

static func _isect(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> Vector2:
	var r := b - a
	var s := d - c
	var den := r.cross(s)
	if absf(den) < 1e-12:
		return a
	var t := (c - a).cross(s) / den
	return a + r * t
