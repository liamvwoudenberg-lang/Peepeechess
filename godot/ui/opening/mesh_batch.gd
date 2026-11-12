extends RefCounted
## Accumulates triangles (position, normal, vertex colour, UV) from many primitives into ONE indexed ArrayMesh, so a whole
## castle costs one draw call per material instead of one per brick. Everything is built in world space: callers pass a
## Transform3D for the primitive. UVs are generated here (local face coordinates, `uv_scale` tiles per metre) so the shared
## stone texture lines up with every wall. Static data only; nothing is allocated per frame.
const TAU_F := TAU
var verts := PackedVector3Array()
var norms := PackedVector3Array()
var cols := PackedColorArray()
var uvs := PackedVector2Array()
var idx := PackedInt32Array()
## Texture tiles per metre (the stone texture covers 2 m x 2 m at 0.5).
var uv_scale := 0.5
var _rng := RandomNumberGenerator.new()

func _init(seed_value: int = 1) -> void:
	_rng.seed = seed_value

func triangle_count() -> int:
	return idx.size() / 3

func vertex_count() -> int:
	return verts.size()

func is_empty() -> bool:
	return idx.is_empty()

## Per-primitive colour jitter keeps a thousand identical blocks from looking stamped.
func jitter(color: Color, amount: float = 0.06) -> Color:
	var k := 1.0 + _rng.randf_range(-amount, amount)
	return Color(color.r * k, color.g * k, color.b * k, color.a)

func _push(p: Vector3, n: Vector3, c: Color, uv: Vector2) -> int:
	verts.append(p)
	norms.append(n)
	cols.append(c)
	uvs.append(uv)
	return verts.size() - 1

func _tri(a: int, b: int, c: int) -> void:
	idx.append(a)
	idx.append(b)
	idx.append(c)

## One flat quad a-b-c-d (counter-clockwise seen from the front). `uv0` is the UV of `a`; `uv_u` / `uv_v` the UV axes in metres.
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, uv0: Vector2 = Vector2.ZERO, du: float = -1.0, dv: float = -1.0) -> void:
	var n := (b - a).cross(d - a).normalized()
	if n.length_squared() < 0.5:
		n = (c - a).cross(d - c).normalized()
	var w := (b - a).length() * uv_scale if du < 0.0 else du
	var h := (d - a).length() * uv_scale if dv < 0.0 else dv
	var i0 := _push(a, n, color, uv0)
	var i1 := _push(b, n, color, uv0 + Vector2(w, 0))
	var i2 := _push(c, n, color, uv0 + Vector2(w, h))
	var i3 := _push(d, n, color, uv0 + Vector2(0, h))
	_tri(i0, i2, i1)   # Godot front faces are clockwise
	_tri(i0, i3, i2)

## Quad given in a local frame and transformed.
func quad_xf(xf: Transform3D, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	quad(xf * a, xf * b, xf * c, xf * d, color)

## Axis-aligned-in-local-space box centred at the origin of `xf`. `skip` is a string of faces to leave out: "t" top,
## "b" bottom, "f" +z, "k" -z (back), "l" -x, "r" +x.
func box(xf: Transform3D, size: Vector3, color: Color, skip: String = "b") -> void:
	var h := size * 0.5
	var u := _rng.randf() * 4.0
	if not "f" in skip:
		_face(xf, Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z), color, size.x, size.y, u)
	if not "k" in skip:
		_face(xf, Vector3(h.x, -h.y, -h.z), Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), color, size.x, size.y, u)
	if not "r" in skip:
		_face(xf, Vector3(h.x, -h.y, h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), color, size.z, size.y, u)
	if not "l" in skip:
		_face(xf, Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, h.y, -h.z), color, size.z, size.y, u)
	if not "t" in skip:
		_face(xf, Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z), color, size.x, size.z, u)
	if not "b" in skip:
		_face(xf, Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z), color, size.x, size.z, u)

func _face(xf: Transform3D, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, w: float, h: float, u: float) -> void:
	var pa := xf * a
	var pb := xf * b
	var pc := xf * c
	var pd := xf * d
	var n := (pb - pa).cross(pd - pa).normalized()
	var i0 := _push(pa, n, color, Vector2(u, 0))
	var i1 := _push(pb, n, color, Vector2(u + w * uv_scale, 0))
	var i2 := _push(pc, n, color, Vector2(u + w * uv_scale, h * uv_scale))
	var i3 := _push(pd, n, color, Vector2(u, h * uv_scale))
	_tri(i0, i2, i1)
	_tri(i0, i3, i2)

## Convenience: a box standing on the ground, centred on `base` (x, z), rotated about Y by `yaw` radians.
func block(base: Vector3, size: Vector3, yaw: float, color: Color, skip: String = "b") -> void:
	box(Transform3D(Basis(Vector3.UP, yaw), base + Vector3(0, size.y * 0.5, 0)), size, color, skip)

## Surface of revolution about the local Y axis. `profile` = [Vector2(radius, y), ...] from bottom to top.
## `color_top` (optional) blends the vertex colour along the profile (bottom -> top). Smooth normals.
func lathe(xf: Transform3D, profile: Array, segments: int, color: Color, color_top: Color = Color(0, 0, 0, -1), cap_top: bool = false, cap_bottom: bool = false, v_scale: float = -1.0) -> void:
	var rings := profile.size()
	if rings < 2:
		return
	var blend := color_top.a >= 0.0
	var circumference := TAU * maxf(float((profile[0] as Vector2).x), float((profile[rings - 1] as Vector2).x))
	var tiles := maxf(1.0, roundf(circumference * uv_scale))
	var base := verts.size()
	var vs := uv_scale if v_scale < 0.0 else v_scale
	var v_run := 0.0
	for r in rings:
		var p: Vector2 = profile[r]
		if r > 0:
			v_run += (p - (profile[r - 1] as Vector2)).length() * vs
		# slope of the profile for the normal
		var prev: Vector2 = profile[maxi(r - 1, 0)]
		var next: Vector2 = profile[mini(r + 1, rings - 1)]
		var tangent := (next - prev)
		var normal2 := Vector2(tangent.y, -tangent.x).normalized()   # (radial, up)
		var c := color
		if blend:
			c = color.lerp(color_top, float(r) / float(rings - 1))
		for s in segments + 1:
			var a := TAU * float(s) / float(segments)
			var dir := Vector3(sin(a), 0, cos(a))
			var pos := xf * Vector3(dir.x * p.x, p.y, dir.z * p.x)
			var nrm := (xf.basis * Vector3(dir.x * normal2.x, normal2.y, dir.z * normal2.x)).normalized()
			_push(pos, nrm, c, Vector2(tiles * float(s) / float(segments), v_run))
	for r in rings - 1:
		for s in segments:
			var i0 := base + r * (segments + 1) + s
			var i1 := i0 + 1
			var i2 := i0 + segments + 1
			var i3 := i2 + 1
			_tri(i0, i2, i1)
			_tri(i1, i2, i3)
	if cap_top:
		_cap(xf, profile[rings - 1], segments, color_top if blend else color, true)
	if cap_bottom:
		_cap(xf, profile[0], segments, color, false)

func _cap(xf: Transform3D, ring: Vector2, segments: int, color: Color, up: bool) -> void:
	var n := (xf.basis * (Vector3.UP if up else Vector3.DOWN)).normalized()
	var centre := _push(xf * Vector3(0, ring.y, 0), n, color, Vector2(0.5, 0.5))
	var first := verts.size()
	for s in segments + 1:
		var a := TAU * float(s) / float(segments)
		_push(xf * Vector3(sin(a) * ring.x, ring.y, cos(a) * ring.x), n, color, Vector2(0.5 + sin(a) * 0.5, 0.5 + cos(a) * 0.5))
	for s in segments:
		if up:
			_tri(centre, first + s + 1, first + s)
		else:
			_tri(centre, first + s, first + s + 1)

## Cylinder or truncated cone standing on `base` (world), optionally with caps.
func cylinder(base: Vector3, r_bottom: float, r_top: float, height: float, segments: int, color: Color, color_top: Color = Color(0, 0, 0, -1), cap_top: bool = false, cap_bottom: bool = false) -> void:
	lathe(Transform3D(Basis.IDENTITY, base), [Vector2(r_bottom, 0), Vector2(r_top, height)], segments, color, color_top, cap_top, cap_bottom)

## Triangular roof prism / gable: a box-like wedge. Used for small gate roofs and pennant stands.
func wedge(xf: Transform3D, width: float, depth: float, height: float, color: Color) -> void:
	var hw := width * 0.5
	var hd := depth * 0.5
	var apex_a := Vector3(0, height, -hd)
	var apex_b := Vector3(0, height, hd)
	quad_xf(xf, Vector3(-hw, 0, hd), Vector3(hw, 0, hd), apex_b, apex_b, color)
	quad_xf(xf, Vector3(-hw, 0, -hd), Vector3(-hw, 0, hd), apex_b, apex_a, color)
	quad_xf(xf, Vector3(hw, 0, hd), Vector3(hw, 0, -hd), apex_a, apex_b, color)
	quad_xf(xf, Vector3(hw, 0, -hd), Vector3(-hw, 0, -hd), apex_a, apex_a, color)

## Append a triangle mesh (arrays from another mesh) transformed by `xf`; used for the giant chess pieces. Normals are
## rotated by the basis (uniform scale assumed). Vertex colour is a constant `color`.
func add_arrays(arrays: Array, xf: Transform3D, color: Color = Color.WHITE) -> void:
	var src_v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if src_v.is_empty():
		return
	var src_n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var src_uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var src_i: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var base := verts.size()
	var basis_n := xf.basis.orthonormalized()
	for i in src_v.size():
		verts.append(xf * src_v[i])
		norms.append((basis_n * src_n[i]).normalized() if i < src_n.size() else Vector3.UP)
		cols.append(color)
		uvs.append(src_uv[i] if i < src_uv.size() else Vector2.ZERO)
	if src_i.is_empty():
		for i in src_v.size():
			idx.append(base + i)
	else:
		for i in src_i:
			idx.append(base + i)

func build_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if idx.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
