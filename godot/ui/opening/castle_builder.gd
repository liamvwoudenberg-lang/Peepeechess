extends RefCounted
## Lays out the opening scene's geometry as a handful of merged batches (see mesh_batch.gd) plus the lists the scene turns
## into lights, halos, embers and statues. Pure data: it creates no nodes, so it is cheap to test and to rebuild.
##
## World: metres, +Y up. The castle looks toward +Z (the viewer): the gatehouse front is at z = +4, the long chequered bridge
## runs out over the valley toward +Z, the courtyard (a giant chessboard) lies behind the gate and the keep closes it at z = -42.
const Batch = preload("res://ui/opening/mesh_batch.gd")

enum Quality { LOW, BALANCED, HIGH }

# -- palette (sRGB; the materials convert) -----------------------------------------------------------------------------
const STONE := Color("8d8a86")
const STONE_WARM := Color("9f968c")
const STONE_DARK := Color("565763")
const SLATE := Color("3b4560")
const SLATE_RED := Color("7a3236")
const WOOD := Color("4b3524")
const IRON := Color("2b2e38")
const GOLD := Color("d6ab4c")
const MARBLE := Color("c8c4b6")
const SQUARE_DARK := Color("3d414f")
const WINDOW := Color("ffb347")
const WINDOW_HOT := Color("ffd27a")
const FLAME_LOW := Color("ff7a1c")
const FLAME_HIGH := Color("ffd45a")
const BANNER_CRIMSON := Color("9b2330")
const BANNER_NAVY := Color("233a78")
const BANNER_IVORY := Color("d9cfb3")

const GATE_Z := 4.0
## Test hook only: true rebuilds the pier tops that used to z-fight with the bridge tiles (proves the stability check can see the bug).
static var debug_pier_tops := false
const WALL_H := 11.0
const KEEP_Z := -42.0
const BASE_Y := -12.0   # walls and towers are buried this deep so they always meet the crag

var quality: int = Quality.BALANCED
var stone := Batch.new(3)       # dressed stone, textured
var roof := Batch.new(4)        # slate and tile, textured
var plain := Batch.new(5)       # wood, iron, gold, trees: vertex colour only
var lit := Batch.new(6)         # windows and flames: unshaded vertex colour
var rock := Batch.new(7)        # terrain: rock texture
var banners := Batch.new(8)     # cloth (shader)
## [{pos, color, size, flicker, phase}] additive billboards
var glows: Array[Dictionary] = []
## Flames: [{pos, height, phase}] teardrop billboards
var flames: Array[Dictionary] = []
## Ember emitters (world positions)
var embers: Array[Vector3] = []
## Real lights that exist for every quality: {pos, color, energy, range}
var gate_light := {}
## Pool of lights that relocate while the camera passes the gate: {ext, court, color, energy, range}
var light_slots: Array[Dictionary] = []
## Giant chess pieces: {role, side, xf: Transform3D, lod}
var statues: Array[Dictionary] = []
## Low mist cards: {pos, size}
var mist_cards: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()

func _init(q: int = Quality.BALANCED) -> void:
	quality = q
	_rng.seed = 90210
	stone.uv_scale = 0.5
	roof.uv_scale = 1.0
	rock.uv_scale = 0.06

func triangle_count() -> int:
	return stone.triangle_count() + roof.triangle_count() + plain.triangle_count() + lit.triangle_count() + rock.triangle_count() + banners.triangle_count()

func _segs(high: int) -> int:
	return high if quality != Quality.LOW else maxi(8, high * 2 / 3)

func _xf(pos: Vector3, yaw: float = 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), pos)

func _flame(pos: Vector3, height: float) -> void:
	flames.append({"pos": pos, "height": height, "phase": _rng.randf()})

func _glow(pos: Vector3, color: Color, size: float, flicker: bool = true) -> void:
	glows.append({"pos": pos, "color": color, "size": size, "flicker": flicker, "phase": _rng.randf()})

## Everything, in dependency order.
func build() -> void:
	_terrain()
	_bridge()
	_curtain_walls()
	_gatehouse()
	_towers()
	_keep()
	_court()
	_exterior_statues()
	_distant_lights()
	_mist()

# ---------------------------------------------------------------------------------------------------------------------
# generic parts
# ---------------------------------------------------------------------------------------------------------------------
## Crenellated wall between two points in the XZ plane (top at `height`); `outward` is +1 when the local +Z side faces out.
func wall(a: Vector2, b: Vector2, height: float, thick: float, color: Color = STONE, merlons: bool = true, both_sides: bool = true) -> void:
	var length := a.distance_to(b)
	if length < 0.1:
		return
	var d := (b - a) / length
	var yaw := atan2(-d.y, d.x)
	var mid := (a + b) * 0.5
	var basis := Basis(Vector3.UP, yaw)
	var depth := height - BASE_Y
	stone.box(Transform3D(basis, Vector3(mid.x, BASE_Y + depth * 0.5, mid.y)), Vector3(length, depth, thick), stone.jitter(color, 0.03), "b")
	# parapet: a thin continuous wall with merlons on the outer edges
	var sides := [1.0, -1.0] if both_sides else [1.0]
	for side in sides:
		var z_off: float = side * (thick * 0.5 - 0.3)
		stone.box(Transform3D(basis, Vector3(mid.x, height + 0.5, mid.y) + basis * Vector3(0, 0, z_off)), Vector3(length, 1.0, 0.6), stone.jitter(color, 0.03), "b")
		if not merlons:
			continue
		var pitch := 2.2
		var count := int(floor(length / pitch))
		var start := -0.5 * (count - 1) * pitch
		for i in count:
			var local := Vector3(start + i * pitch, height + 1.0 + 0.7, z_off)
			stone.box(Transform3D(basis, Vector3(mid.x, 0, mid.y) + basis * local), Vector3(1.2, 1.4, 0.6), stone.jitter(color, 0.05), "b")
	# pilasters give the long faces some relief for the raking moonlight
	if quality != Quality.LOW:
		var pil := int(floor(length / 9.0))
		for i in pil:
			var along := (-0.5 * (pil - 1) + i) * 9.0
			for side in sides:
				var off: float = side * (thick * 0.5 + 0.25)
				stone.box(Transform3D(basis, Vector3(mid.x, 0, mid.y) + basis * Vector3(along, (height - 0.5 + BASE_Y) * 0.5, off)), Vector3(1.8, height - 0.5 - BASE_Y, 0.7), stone.jitter(color, 0.05), "b")

## Round tower. style: "cone" (slate cone roof) or "rook" (crenellated crown). Returns the roof apex.
func tower(c: Vector2, r: float, height: float, roof_h: float, style: String = "cone", roof_color: Color = SLATE, face_yaw: float = 0.0, slits: bool = true) -> Vector3:
	var segs := _segs(24)
	var body_color := stone.jitter(STONE, 0.04)
	var profile := [Vector2(r * 1.3, BASE_Y), Vector2(r * 1.12, -0.5), Vector2(r * 1.04, 3.0), Vector2(r, 4.5), Vector2(r, height - 2.0), Vector2(r + 0.25, height - 1.7), Vector2(r + 0.95, height - 0.9), Vector2(r + 0.95, height)]
	stone.lathe(_xf(Vector3(c.x, 0, c.y)), profile, segs, body_color)
	if style == "rook":
		stone.lathe(_xf(Vector3(c.x, 0, c.y)), [Vector2(r + 0.95, height), Vector2(r + 0.95, height + 0.8), Vector2(r + 0.4, height + 0.8)], segs, body_color, Color(0, 0, 0, -1), true)
		var n := maxi(8, int(round(TAU * (r + 0.7) / 2.1)))
		for i in n:
			var a := TAU * i / n
			stone.box(Transform3D(Basis(Vector3.UP, a), Vector3(c.x + sin(a) * (r + 0.68), height + 0.8 + 0.8, c.y + cos(a) * (r + 0.68))), Vector3(1.25, 1.6, 0.7), stone.jitter(STONE, 0.05), "b")
		# squat inner roof peeking above the merlons
		roof.lathe(_xf(Vector3(c.x, height + 0.8, c.y)), [Vector2(r * 0.7, 0), Vector2(r * 0.5, roof_h * 0.45), Vector2(r * 0.18, roof_h * 0.85), Vector2(0, roof_h)], segs, roof_color)
	else:
		var apex := height + roof_h
		var base_r := r + 1.15
		roof.lathe(_xf(Vector3(c.x, height - 0.2, c.y)), [Vector2(base_r, 0), Vector2(base_r - 0.35, 0.5), Vector2(r * 0.78 + 0.2, roof_h * 0.34), Vector2(r * 0.40, roof_h * 0.68), Vector2(r * 0.12, roof_h * 0.93), Vector2(0.0, roof_h + 0.2)], segs, roof_color, Color(0, 0, 0, -1), false, true)
		plain.lathe(_xf(Vector3(c.x, apex, c.y)), [Vector2(0.09, 0), Vector2(0.09, 1.6), Vector2(0.2, 1.8), Vector2(0.0, 2.1)], 8, GOLD)
		_pennant(Vector3(c.x, apex + 1.4, c.y), 3.0, 1.1, BANNER_CRIMSON if _rng.randf() < 0.5 else BANNER_NAVY, _rng.randf_range(-0.4, 0.4))
	# arrow slits, some lit from inside
	if slits:
		var rows := [height * 0.35, height * 0.62, height * 0.85]
		for row in rows.size():
			var count := 5 if quality != Quality.LOW else 3
			for i in count:
				var a2 := face_yaw + (float(i) - (count - 1) * 0.5) * 0.5 + row * 0.25
				var outward := Vector3(sin(a2), 0, cos(a2))
				if outward.z < -0.15:
					continue   # only the half that can face the camera is worth drawing
				var pos := Vector3(c.x, rows[row], c.y) + outward * (r + 0.03)
				var glowing := (i + row) % 2 == 0
				lit.box(Transform3D(Basis(Vector3.UP, a2), pos), Vector3(0.5, 1.6, 0.08), WINDOW if glowing else Color("0a0c12"), "bk")
	return Vector3(c.x, height + roof_h, c.y)

## A hanging banner: `top` is the centre of the top edge, `yaw` turns its face (0 = facing +Z).
func banner(top: Vector3, width: float, length: float, color: Color, yaw: float = 0.0) -> void:
	var segs := 10
	var basis := Basis(Vector3.UP, yaw)
	var cloth := Color(color.r, color.g, color.b, 1.0)
	for i in segs:
		var v0 := float(i) / segs
		var v1 := float(i + 1) / segs
		var y0 := top.y - v0 * length
		var y1 := top.y - v1 * length
		var pa := top + basis * Vector3(-width * 0.5, y0 - top.y, 0)
		var pb := top + basis * Vector3(width * 0.5, y0 - top.y, 0)
		var pc := top + basis * Vector3(width * 0.5, y1 - top.y, 0)
		var pd := top + basis * Vector3(-width * 0.5, y1 - top.y, 0)
		# vertex order: a = top-left ... UV.x across, UV.y along the banner
		var n := basis * Vector3.BACK
		_cloth_quad(pd, pc, pb, pa, n, cloth, Vector2(0, v1), Vector2(1, v1), Vector2(1, v0), Vector2(0, v0))
	# gold cross-bar and tassels
	plain.box(Transform3D(basis, top + Vector3(0, 0.1, 0.02) * 1.0), Vector3(width + 0.5, 0.18, 0.18), GOLD, "b")

## A small flag on a pole (flies sideways in the wind).
func _pennant(base: Vector3, length: float, height: float, color: Color, yaw: float) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var segs := 6
	var cloth := Color(color.r, color.g, color.b, 0.4)   # alpha < 0.5 -> plain cloth in the shader, 0.4 = wind weight
	for i in segs:
		var u0 := float(i) / segs
		var u1 := float(i + 1) / segs
		var h0 := height * (1.0 - u0)
		var h1 := height * (1.0 - u1)
		var pa := base + basis * Vector3(u0 * length, -h0 * 0.5, 0)
		var pb := base + basis * Vector3(u1 * length, -h1 * 0.5, 0)
		var pc := base + basis * Vector3(u1 * length, h1 * 0.5, 0)
		var pd := base + basis * Vector3(u0 * length, h0 * 0.5, 0)
		# flag extends along local +X; wave amplitude grows with UV.y = u
		_cloth_quad(pa, pb, pc, pd, basis * Vector3.BACK, Color(cloth.r, cloth.g, cloth.b, 0.4), Vector2(0, u0), Vector2(0, u1), Vector2(1, u1), Vector2(1, u0))

func _cloth_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, color: Color, uva: Vector2, uvb: Vector2, uvc: Vector2, uvd: Vector2) -> void:
	var i0 := banners._push(a, n, color, uva)
	var i1 := banners._push(b, n, color, uvb)
	var i2 := banners._push(c, n, color, uvc)
	var i3 := banners._push(d, n, color, uvd)
	banners._tri(i0, i2, i1)
	banners._tri(i0, i3, i2)

## Brazier on a stand with a fire, glow, embers (and optionally a real light slot is added by the caller).
func brazier(pos: Vector3, scale_value: float = 1.0, with_embers: bool = true) -> void:
	var s := scale_value
	var segs := _segs(12)
	plain.lathe(_xf(pos), [Vector2(0.55 * s, 0), Vector2(0.4 * s, 0.25 * s), Vector2(0.14 * s, 0.7 * s), Vector2(0.14 * s, 1.1 * s), Vector2(0.32 * s, 1.25 * s), Vector2(0.7 * s, 1.7 * s), Vector2(0.78 * s, 1.95 * s), Vector2(0.66 * s, 1.95 * s), Vector2(0.55 * s, 1.75 * s)], segs, IRON)
	_flame(pos + Vector3(0, 1.92 * s, 0), 1.7 * s)
	_flame(pos + Vector3(0.2 * s, 1.9 * s, 0.12 * s), 1.2 * s)
	_flame(pos + Vector3(-0.18 * s, 1.9 * s, -0.1 * s), 1.0 * s)
	_glow(pos + Vector3(0, 2.4 * s, 0), Color(1.0, 0.55, 0.18, 0.9), 5.5 * s)
	if quality != Quality.LOW:
		_glow(pos + Vector3(0, 2.6 * s, 0), Color(1.0, 0.42, 0.12, 0.32), 17.0 * s)   # the wide halo is the costly overdraw: skipped on low
	if with_embers:
		embers.append(pos + Vector3(0, 2.7 * s, 0))

## Wall torch / bridge torch on a short post.
func torch_post(pos: Vector3, height: float = 1.6) -> void:
	stone.box(Transform3D(Basis.IDENTITY, pos + Vector3(0, height * 0.5, 0)), Vector3(0.7, height, 0.7), stone.jitter(STONE_WARM, 0.05), "b")
	stone.box(Transform3D(Basis.IDENTITY, pos + Vector3(0, height + 0.1, 0)), Vector3(0.95, 0.2, 0.95), stone.jitter(STONE_WARM, 0.05), "b")
	plain.box(Transform3D(Basis.IDENTITY, pos + Vector3(0, height + 0.45, 0)), Vector3(0.16, 0.7, 0.16), WOOD, "b")
	_flame(pos + Vector3(0, height + 0.82, 0), 0.75)
	_glow(pos + Vector3(0, height + 1.2, 0), Color(1.0, 0.55, 0.2, 0.85), 3.0)
	_glow(pos + Vector3(0, height + 1.3, 0), Color(1.0, 0.42, 0.14, 0.22), 9.0)

# ---------------------------------------------------------------------------------------------------------------------
# terrain
# ---------------------------------------------------------------------------------------------------------------------
func terrain_height(x: float, z: float, noise: FastNoiseLite, ridged: FastNoiseLite) -> float:
	var dx := maxf(absf(x) - 46.0, 0.0)
	var dz := maxf(maxf(z - 8.0, -72.0 - z), 0.0)
	var d := sqrt(dx * dx + dz * dz)
	var n := noise.get_noise_2d(x, z)
	var h := -0.5
	if d > 0.0:
		h = -0.5 - 40.0 * (1.0 - exp(-d / 8.0))
		h += n * 4.5 * minf(d / 6.0, 1.0)
	var r := Vector2(x, z + 30.0).length()
	var far := smoothstep(110.0, 330.0, r)
	var rg := ridged.get_noise_2d(x, z)
	h += far * (30.0 + 110.0 * (0.5 + 0.5 * rg))
	h += n * 2.0 * smoothstep(60.0, 120.0, r)
	return h

func _axis(extent: float, fine: float, coarse: float, fine_half: float) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	var x := -extent
	while x < extent:
		values.append(x)
		var step := fine if absf(x) < fine_half else (fine * 3.0 if absf(x) < fine_half * 2.2 else coarse)
		x += step
	values.append(extent)
	return values

func _terrain() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 31
	noise.frequency = 0.035
	noise.fractal_octaves = 3
	var ridged := FastNoiseLite.new()
	ridged.seed = 8
	ridged.frequency = 0.006
	ridged.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridged.fractal_octaves = 3
	var fine := 4.0 if quality != Quality.LOW else 6.0
	var xs := _axis(440.0, fine, 46.0, 72.0)
	var zs_pos := _axis(300.0, fine, 46.0, 72.0)   # z is centred on the castle (-30) below
	var heights := []
	for zi in zs_pos.size():
		var row := PackedFloat32Array()
		for xi in xs.size():
			row.append(terrain_height(xs[xi], zs_pos[zi] - 30.0, noise, ridged))
		heights.append(row)
	var grass := Color("1d2a2c")
	var cliff := Color("4b4d58")
	var peak := Color("6d748c")
	for zi in zs_pos.size() - 1:
		for xi in xs.size() - 1:
			var x0 := xs[xi]
			var x1 := xs[xi + 1]
			var z0 := zs_pos[zi] - 30.0
			var z1 := zs_pos[zi + 1] - 30.0
			var h00: float = heights[zi][xi]
			var h10: float = heights[zi][xi + 1]
			var h01: float = heights[zi + 1][xi]
			var h11: float = heights[zi + 1][xi + 1]
			var a := Vector3(x0, h00, z0)
			var b := Vector3(x1, h10, z0)
			var c := Vector3(x1, h11, z1)
			var d := Vector3(x0, h01, z1)
			# quad winding: viewed from above, +x right, +z toward the viewer (down the screen)
			var n := (d - a).cross(b - a).normalized()
			var avg := (h00 + h10 + h01 + h11) * 0.25
			var slope := 1.0 - clampf(n.y, 0.0, 1.0)
			var col := grass.lerp(cliff, clampf(slope * 5.0, 0.0, 1.0))
			col = col.lerp(peak, smoothstep(40.0, 130.0, avg))
			if avg > -1.0 and absf(avg + 0.5) < 1.0:
				col = Color("2e3138")
			col = rock.jitter(col, 0.1)
			rock.quad(d, c, b, a, col)
	# a faint ring of pines on the valley floor (small, so they read as texture in the fog)
	if quality != Quality.LOW:
		var count := 70 if quality == Quality.BALANCED else 140
		for i in count:
			var px := _rng.randf_range(-170.0, 170.0)
			var pz := _rng.randf_range(-160.0, 140.0)
			var ph := terrain_height(px, pz, noise, ridged)
			if ph > -22.0 or ph < -46.0 or Vector2(px, pz).length() < 55.0:
				continue
			var s := _rng.randf_range(0.8, 1.5)
			for k in 3:
				plain.cylinder(Vector3(px, ph + 1.8 + k * 2.2 * s, pz), (3.2 - k * 0.8) * s, (1.4 - k * 0.45) * s, 4.4 * s, 5, Color("16241f"), Color("203630"))

# ---------------------------------------------------------------------------------------------------------------------
# bridge
# ---------------------------------------------------------------------------------------------------------------------
func _bridge() -> void:
	var z_far := 120.0
	var width := 8.0
	var tile := 2.0
	var rows := int((z_far - GATE_Z) / tile)
	var cols := int(width / tile)
	var light := Color("c2bdaf")
	var dark := SQUARE_DARK
	for r in rows:
		var z1 := z_far - r * tile
		var z0 := z1 - tile
		for c in cols:
			var x0 := -width * 0.5 + c * tile
			var col: Color = light if (r + c) % 2 == 0 else dark
			stone.quad(Vector3(x0, 0.0, z1), Vector3(x0 + tile, 0.0, z1), Vector3(x0 + tile, 0.0, z0), Vector3(x0, 0.0, z0), stone.jitter(col, 0.035), Vector2(0, 0), tile * 0.25, tile * 0.25)
	# deck slab + underside
	stone.box(Transform3D(Basis.IDENTITY, Vector3(0, -1.6, (z_far + GATE_Z) * 0.5)), Vector3(width + 1.4, 3.2, z_far - GATE_Z), stone.jitter(STONE_DARK, 0.03), "bt")
	# parapets with posts
	for side in [-1.0, 1.0]:
		var x: float = side * (width * 0.5 + 0.35)
		stone.box(Transform3D(Basis.IDENTITY, Vector3(x, 0.55, (z_far + GATE_Z) * 0.5)), Vector3(0.7, 1.1, z_far - GATE_Z), stone.jitter(STONE, 0.03), "b")
		var z := GATE_Z + 6.0
		var post_index := 0
		while z < z_far - 4.0:
			if z > 66.0:
				break   # nothing behind the opening camera
			if post_index % 2 == 0:
				torch_post(Vector3(x, 1.1, z), 1.2)
			else:
				stone.box(Transform3D(Basis.IDENTITY, Vector3(x, 1.6, z)), Vector3(0.9, 1.0, 0.9), stone.jitter(STONE_WARM, 0.05), "b")
			z += 10.0 if quality != Quality.LOW else 20.0
			post_index += 1
	# piers vanish into the mist below
	var z_pier := GATE_Z + 16.0
	while z_pier < z_far:
		# top face skipped: it would sit at exactly y = 0, coplanar with the chequer tiles (z-fighting, visible as flicker)
		stone.box(Transform3D(Basis.IDENTITY, Vector3(0, -22.0, z_pier)), Vector3(9.4, 44.0, 5.0), stone.jitter(STONE_DARK, 0.03), "b" if debug_pier_tops else "bt")
		z_pier += 26.0

# ---------------------------------------------------------------------------------------------------------------------
# walls, towers, gatehouse
# ---------------------------------------------------------------------------------------------------------------------
func _curtain_walls() -> void:
	var half := 35.0
	var back := -66.0
	wall(Vector2(-half, 0), Vector2(-12.0, 0), WALL_H, 3.0)
	wall(Vector2(12.0, 0), Vector2(half, 0), WALL_H, 3.0)
	wall(Vector2(-half, 0), Vector2(-half, back), WALL_H, 3.0)
	wall(Vector2(half, 0), Vector2(half, back), WALL_H, 3.0)
	if quality != Quality.LOW:
		wall(Vector2(-half, back), Vector2(half, back), WALL_H, 3.0)

func _towers() -> void:
	var half := 35.0
	tower(Vector2(-half, 0), 6.2, 24.0, 12.0, "cone", SLATE, 0.0)
	tower(Vector2(half, 0), 6.2, 24.0, 12.0, "cone", SLATE, 0.0)
	tower(Vector2(-23.0, 0), 3.8, 19.0, 0.0, "rook", SLATE, 0.0)
	tower(Vector2(23.0, 0), 3.8, 19.0, 0.0, "rook", SLATE, 0.0)
	# the far corners and the tall pair behind the keep close the silhouette
	tower(Vector2(-half, -33.0), 5.0, 20.0, 0.0, "rook", SLATE, 0.0)
	tower(Vector2(half, -33.0), 5.0, 20.0, 0.0, "rook", SLATE, 0.0)
	if quality != Quality.LOW:
		tower(Vector2(-half, -66.0), 6.0, 26.0, 13.0, "cone", SLATE_RED, 0.0, false)
		tower(Vector2(half, -66.0), 6.0, 26.0, 13.0, "cone", SLATE_RED, 0.0, false)
	# banners on the corner towers
	for sx in [-1.0, 1.0]:
		banner(Vector3(sx * 35.0, 21.0, 6.9), 2.2, 8.0, BANNER_CRIMSON if sx < 0.0 else BANNER_NAVY, 0.0)
		banner(Vector3(sx * 23.0, 16.0, 4.5), 1.8, 6.0, BANNER_NAVY if sx < 0.0 else BANNER_CRIMSON, 0.0)

func _arch_y(x: float, half: float, spring: float, apex: float) -> float:
	var t := clampf(absf(x) / half, 0.0, 1.0)
	return spring + (apex - spring) * pow(maxf(1.0 - pow(t, 2.3), 0.0), 0.72)

func _gatehouse() -> void:
	var half := 3.0
	var spring := 5.2
	var apex := 9.2
	var top := 16.0
	var depth := 8.0
	# the two masses either side of the passage
	for sx in [-1.0, 1.0]:
		stone.box(Transform3D(Basis.IDENTITY, Vector3(sx * 6.5, (top + BASE_Y) * 0.5, 0)), Vector3(7.0, top - BASE_Y, depth), stone.jitter(STONE_WARM, 0.03), "b")
	# facade above the arch (front +Z and back -Z) and the vault soffit
	var steps := 16
	var xs := PackedFloat32Array()
	for i in steps + 1:
		xs.append(-half + 2.0 * half * float(i) / steps)
	for i in steps:
		var x0 := xs[i]
		var x1 := xs[i + 1]
		var y0 := _arch_y(x0, half, spring, apex)
		var y1 := _arch_y(x1, half, spring, apex)
		var col := stone.jitter(STONE_WARM, 0.03)
		stone.quad(Vector3(x0, y0, depth * 0.5), Vector3(x1, y1, depth * 0.5), Vector3(x1, top, depth * 0.5), Vector3(x0, top, depth * 0.5), col, Vector2(x0 * 0.5, y0 * 0.5), (x1 - x0) * 0.5, (top - y0) * 0.5)
		stone.quad(Vector3(x1, y1, -depth * 0.5), Vector3(x0, y0, -depth * 0.5), Vector3(x0, top, -depth * 0.5), Vector3(x1, top, -depth * 0.5), col, Vector2(x0 * 0.5, y0 * 0.5), (x1 - x0) * 0.5, (top - y0) * 0.5)
		# soffit (ceiling of the passage): normal facing down
		var dark := stone.jitter(STONE_DARK, 0.05)
		stone.quad(Vector3(x0, y0, -depth * 0.5), Vector3(x1, y1, -depth * 0.5), Vector3(x1, y1, depth * 0.5), Vector3(x0, y0, depth * 0.5), dark, Vector2(x0 * 0.5, 0), (x1 - x0) * 0.5, depth * 0.5)
	# ribs of the vault, a gold-trimmed arch ring on the facade
	for i in steps:
		var x0 := xs[i]
		var x1 := xs[i + 1]
		var ya := _arch_y(x0, half, spring, apex)
		var yb := _arch_y(x1, half, spring, apex)
		var mid := Vector3((x0 + x1) * 0.5, (ya + yb) * 0.5 + 0.12, depth * 0.5 + 0.1)
		var seg := Vector3(x1 - x0, yb - ya, 0).length()
		var ang := atan2(yb - ya, x1 - x0)
		plain.box(Transform3D(Basis(Vector3(0, 0, 1), ang), mid), Vector3(seg + 0.05, 0.42, 0.22), GOLD, "b")
	# raised portcullis teeth in the arch
	var bars := 12
	for i in bars:
		var x := -half + 0.45 + (2.0 * half - 0.9) * float(i) / (bars - 1)
		var y_top := _arch_y(x, half, spring, apex)
		plain.box(Transform3D(Basis.IDENTITY, Vector3(x, y_top - 0.8, depth * 0.5 - 0.9)), Vector3(0.11, 1.6, 0.11), IRON, "b")
		plain.box(Transform3D(Basis(Vector3(0, 0, 1), PI), Vector3(x, y_top - 1.7, depth * 0.5 - 0.9)), Vector3(0.18, 0.3, 0.18), IRON, "b")
	plain.box(Transform3D(Basis.IDENTITY, Vector3(0, spring + 1.0, depth * 0.5 - 0.9)), Vector3(2.0 * half, 0.1, 0.1), IRON, "b")
	# floor of the passage continues the chequer (three rows, z = +4 .. -2: the court's ground quad starts at z = -2, a fourth row
	# would lie coplanar under it)
	for r in 3:
		for c in 3:
			var col: Color = Color("c2bdaf") if (r + c) % 2 == 0 else SQUARE_DARK
			var x0 := -half + c * 2.0
			var z1 := depth * 0.5 - r * 2.0
			stone.quad(Vector3(x0, 0.0, z1), Vector3(x0 + 2.0, 0.0, z1), Vector3(x0 + 2.0, 0.0, z1 - 2.0), Vector3(x0, 0.0, z1 - 2.0), col, Vector2.ZERO, 0.5, 0.5)
	# parapet, machicolation corbels, merlons
	for z in [depth * 0.5 - 0.3, -depth * 0.5 + 0.3]:
		stone.box(Transform3D(Basis.IDENTITY, Vector3(0, top + 0.5, z)), Vector3(19.0, 1.0, 0.6), stone.jitter(STONE_WARM, 0.03), "b")
		for i in 9:
			stone.box(Transform3D(Basis.IDENTITY, Vector3(-8.0 + i * 2.0, top + 1.7, z)), Vector3(1.2, 1.4, 0.6), stone.jitter(STONE_WARM, 0.05), "b")
	for i in 10:
		stone.box(Transform3D(Basis.IDENTITY, Vector3(-9.0 + i * 2.0, top - 1.2, depth * 0.5 + 0.35)), Vector3(0.7, 1.4, 0.9), stone.jitter(STONE, 0.05), "b")
	# gabled roof over the gate chamber
	roof.wedge(Transform3D(Basis.IDENTITY, Vector3(0, top + 0.9, 0)), 11.0, 6.0, 4.5, SLATE_RED)
	plain.box(Transform3D(Basis.IDENTITY, Vector3(0, top + 5.6, 0)), Vector3(0.2, 2.6, 0.2), WOOD, "b")
	_pennant(Vector3(0, top + 6.2, 0), 3.4, 1.2, BANNER_CRIMSON, 0.0)
	# flanking drums
	tower(Vector2(-10.6, 2.4), 4.2, 21.0, 11.0, "cone", SLATE, 0.0)
	tower(Vector2(10.6, 2.4), 4.2, 21.0, 11.0, "cone", SLATE, 0.0)
	# the great banners and a coat-of-arms disc over the arch
	banner(Vector3(-6.4, 15.2, depth * 0.5 + 0.12), 2.4, 8.2, BANNER_CRIMSON, 0.0)
	banner(Vector3(6.4, 15.2, depth * 0.5 + 0.12), 2.4, 8.2, BANNER_NAVY, 0.0)
	plain.lathe(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 12.2, depth * 0.5 + 0.1)), [Vector2(1.5, 0), Vector2(1.5, 0.15), Vector2(1.05, 0.2), Vector2(1.05, 0.05)], 20, GOLD, Color(0, 0, 0, -1), true)
	# warm glow spilling out of the tunnel + the gate's own light
	_glow(Vector3(0, 4.4, 1.5), Color(1.0, 0.55, 0.2, 0.55), 11.0)
	_glow(Vector3(0, 3.0, 4.6), Color(1.0, 0.5, 0.16, 0.30), 18.0, false)
	gate_light = {"pos": Vector3(0, 4.2, 6.0), "color": Color(1.0, 0.62, 0.3), "energy": 3.2, "range": 26.0}
	# torches flanking the gate
	for sx in [-1.0, 1.0]:
		brazier(Vector3(sx * 5.6, 0.0, GATE_Z + 1.8), 0.9)

# ---------------------------------------------------------------------------------------------------------------------
# keep and courtyard
# ---------------------------------------------------------------------------------------------------------------------
func _keep() -> void:
	var cx := 0.0
	var cz := KEEP_Z - 10.0
	var width := 26.0
	var depth := 20.0
	var top := 34.0
	stone.box(Transform3D(Basis.IDENTITY, Vector3(cx, (top + BASE_Y) * 0.5, cz)), Vector3(width, top - BASE_Y, depth), stone.jitter(STONE, 0.03), "b")
	# string courses
	for y in [8.0, 17.0, 26.0]:
		stone.box(Transform3D(Basis.IDENTITY, Vector3(cx, y, KEEP_Z + 0.2)), Vector3(width + 0.6, 0.5, 0.7), stone.jitter(STONE_WARM, 0.03), "b")
	# crenellated crown and a great hall roof behind it
	for z in [KEEP_Z - 0.3, KEEP_Z - depth + 0.3]:
		stone.box(Transform3D(Basis.IDENTITY, Vector3(cx, top + 0.5, z)), Vector3(width, 1.0, 0.6), stone.jitter(STONE_WARM, 0.03), "b")
		for i in 12:
			stone.box(Transform3D(Basis.IDENTITY, Vector3(-11.0 + i * 2.0, top + 1.7, z)), Vector3(1.2, 1.4, 0.6), stone.jitter(STONE_WARM, 0.05), "b")
	roof.wedge(Transform3D(Basis.IDENTITY, Vector3(cx, top + 1.0, cz - 1.0)), 21.0, 13.0, 11.0, SLATE_RED)
	# corner turrets
	var turret_r := 3.4
	for sx in [-1.0, 1.0]:
		tower(Vector2(sx * width * 0.5, KEEP_Z), turret_r, top + 9.0, 13.0, "cone", SLATE, 0.0, false)
	if quality != Quality.LOW:
		for sx in [-1.0, 1.0]:
			tower(Vector2(sx * width * 0.5, KEEP_Z - depth), turret_r, top + 5.0, 11.0, "cone", SLATE, 0.0, false)
		# the tall slender tower behind, silhouetted against the moon side
		tower(Vector2(-7.0, KEEP_Z - 15.0), 4.2, 52.0, 20.0, "cone", SLATE, 0.0, false)
		tower(Vector2(9.0, KEEP_Z - 12.0), 3.0, 44.0, 14.0, "cone", SLATE_RED, 0.0, false)
	# windows: lit gothic slits in frames, a great window and the door
	var face_z := KEEP_Z + 0.05
	for row in [[11.0, 5], [20.0, 5], [29.0, 7]]:
		var n: int = row[1]
		for i in n:
			var x := (float(i) - (n - 1) * 0.5) * (width - 4.0) / maxf(float(n - 1), 1.0)
			if absf(x) < 3.0 and row[0] < 22.0 and row[0] > 15.0:
				continue   # room for the great window
			var tall := 3.4
			stone.box(Transform3D(Basis.IDENTITY, Vector3(x, row[0], face_z + 0.02)), Vector3(1.6, tall + 0.6, 0.3), stone.jitter(STONE_DARK, 0.05), "b")
			var lit_window := _rng.randf() < 0.78
			lit.box(Transform3D(Basis.IDENTITY, Vector3(x, row[0], face_z + 0.2)), Vector3(0.95, tall, 0.06), WINDOW if lit_window else Color("0a0c12"), "bk")
			if lit_window and quality != Quality.LOW and _rng.randf() < 0.5:
				_glow(Vector3(x, row[0], face_z + 0.9), Color(1.0, 0.62, 0.25, 0.28), 4.6, false)
	# great window with tracery
	stone.box(Transform3D(Basis.IDENTITY, Vector3(0, 18.5, face_z + 0.02)), Vector3(5.4, 8.6, 0.4), stone.jitter(STONE_DARK, 0.04), "b")
	lit.box(Transform3D(Basis.IDENTITY, Vector3(0, 18.5, face_z + 0.24)), Vector3(4.4, 7.6, 0.06), WINDOW_HOT, "bk")
	for i in 3:
		plain.box(Transform3D(Basis.IDENTITY, Vector3(-1.4 + i * 1.4, 18.5, face_z + 0.32)), Vector3(0.14, 7.6, 0.1), IRON, "b")
	for j in 3:
		plain.box(Transform3D(Basis.IDENTITY, Vector3(0, 15.6 + j * 2.9, face_z + 0.32)), Vector3(4.4, 0.14, 0.1), IRON, "b")
	_glow(Vector3(0, 18.5, face_z + 1.4), Color(1.0, 0.6, 0.22, 0.5), 15.0, false)
	# grand door
	stone.box(Transform3D(Basis.IDENTITY, Vector3(0, 3.4, face_z + 0.02)), Vector3(5.4, 6.8, 0.5), stone.jitter(STONE_DARK, 0.04), "b")
	lit.box(Transform3D(Basis.IDENTITY, Vector3(0, 3.0, face_z + 0.3)), Vector3(3.6, 6.0, 0.06), WINDOW, "bk")
	_glow(Vector3(0, 3.0, face_z + 1.2), Color(1.0, 0.55, 0.2, 0.5), 10.0, false)
	# banners down the front
	for sx in [-1.0, 1.0]:
		banner(Vector3(sx * 8.4, 32.0, face_z + 0.25), 2.4, 10.0, BANNER_CRIMSON if sx > 0.0 else BANNER_NAVY, 0.0)
		banner(Vector3(sx * 11.2, 30.0, face_z + 0.25), 1.8, 7.0, BANNER_IVORY, 0.0)

func _court() -> void:
	# ground of the court (flagstones) and the giant chessboard at its heart
	var ground_col := Color("4a4d59")
	stone.quad(Vector3(-34, 0, -2), Vector3(34, 0, -2), Vector3(34, 0, KEEP_Z), Vector3(-34, 0, KEEP_Z), ground_col, Vector2.ZERO, 34.0, 20.0)
	var sq := 4.0
	var x_start := -16.0
	var z_start := -8.0
	for r in 8:
		for c in 8:
			var col: Color = Color("c4bfb1") if (r + c) % 2 == 0 else SQUARE_DARK
			var x0 := x_start + c * sq
			var z0 := z_start - r * sq
			stone.quad(Vector3(x0, 0.16, z0), Vector3(x0 + sq, 0.16, z0), Vector3(x0 + sq, 0.16, z0 - sq), Vector3(x0, 0.16, z0 - sq), stone.jitter(col, 0.04), Vector2(c * 0.37, r * 0.29), 2.0, 2.0)
	# board rim
	var rim := Color("2b2e38")
	stone.box(Transform3D(Basis.IDENTITY, Vector3(0, 0.08, z_start + 0.5)), Vector3(33.0, 0.34, 1.0), rim, "b")
	stone.box(Transform3D(Basis.IDENTITY, Vector3(0, 0.08, z_start - 8 * sq - 0.5)), Vector3(33.0, 0.34, 1.0), rim, "b")
	for sx in [-1.0, 1.0]:
		stone.box(Transform3D(Basis.IDENTITY, Vector3(sx * 16.5, 0.08, z_start - 4 * sq)), Vector3(1.0, 0.34, 32.0), rim, "b")
	# braziers: four corners + two by the keep
	var corners := [Vector3(-19.5, 0, -9), Vector3(19.5, 0, -9), Vector3(-19.5, 0, -39.5), Vector3(19.5, 0, -39.5), Vector3(-19.5, 0, -24), Vector3(19.5, 0, -24)]
	for p in corners:
		brazier(p, 1.25)
	var court_lights := [Vector3(-19.5, 4.2, -9), Vector3(19.5, 4.2, -9), Vector3(-19.5, 4.2, -39.5), Vector3(19.5, 4.2, -39.5), Vector3(-14, 8.0, -24), Vector3(14, 8.0, -24), Vector3(0, 6.0, -36.0)]
	var ext_lights := [Vector3(-12.0, 4.2, 18.0), Vector3(12.0, 4.2, 18.0), Vector3(-5.0, 3.0, 36.0), Vector3(5.0, 3.0, 36.0), Vector3(-22.0, 6.0, 8.0), Vector3(22.0, 6.0, 8.0), Vector3(0.0, 8.0, 24.0)]
	for i in court_lights.size():
		light_slots.append({"ext": ext_lights[i], "court": court_lights[i], "color": Color(1.0, 0.6, 0.28), "energy": 2.6, "range": 22.0})
	# banners on the court walls (they face inward)
	for sx in [-1.0, 1.0]:
		for z in [-12.0, -24.0, -36.0]:
			banner(Vector3(sx * 33.3, 10.5, z), 2.2, 7.5, BANNER_CRIMSON if int(absf(z)) % 24 == 12 else BANNER_NAVY, -sx * PI * 0.5)
	# a giant game in progress
	var layout := [
		["rook", "light", 1, 1], ["knight", "light", 3, 3], ["king", "light", 5, 1], ["pawn", "light", 2, 2], ["pawn", "light", 4, 3], ["bishop", "light", 6, 2],
		["queen", "dark", 3, 7], ["rook", "dark", 7, 7], ["pawn", "dark", 2, 5], ["knight", "dark", 5, 5], ["bishop", "dark", 1, 6], ["king", "dark", 4, 7],
	]
	if quality == Quality.LOW:
		layout = [["king", "light", 5, 1], ["knight", "light", 3, 3], ["queen", "dark", 3, 6], ["pawn", "dark", 5, 5]]
	for entry in layout:
		var cx := x_start + (int(entry[2]) + 0.5) * sq
		var cz := z_start - (int(entry[3]) + 0.5) * sq
		var yaw := PI if entry[1] == "dark" else 0.0
		yaw += _rng.randf_range(-0.12, 0.12)
		var scale_value := 4.2
		statues.append({"role": entry[0], "side": entry[1], "xf": Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale_value), Vector3(cx, 0.16, cz)), "lod": 1})

func _exterior_statues() -> void:
	# two giants guard the bridge head: the white king and the black knight, each on a stepped plinth with a brazier at its foot
	var spec := [[-1.0, "king", "light", 7.4], [1.0, "knight", "dark", 8.4]]
	for entry in spec:
		var sx: float = entry[0]
		var p := Vector3(sx * 10.5, 0.0, 17.0)
		stone.box(Transform3D(Basis.IDENTITY, p + Vector3(0, 0.6, 0)), Vector3(7.4, 1.2, 7.4), stone.jitter(STONE_WARM, 0.03), "b")
		stone.box(Transform3D(Basis.IDENTITY, p + Vector3(0, 2.4, 0)), Vector3(6.2, 2.4, 6.2), stone.jitter(STONE, 0.03), "b")
		stone.box(Transform3D(Basis.IDENTITY, p + Vector3(0, 3.8, 0)), Vector3(6.9, 0.5, 6.9), stone.jitter(STONE_WARM, 0.03), "b")
		# gold inlay band
		plain.box(Transform3D(Basis.IDENTITY, p + Vector3(0, 2.4, 3.12)), Vector3(4.6, 0.3, 0.1), GOLD, "b")
		var yaw := -sx * 0.5
		statues.append({"role": entry[1], "side": entry[2], "xf": Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * float(entry[3])), p + Vector3(0, 4.05, 0)), "lod": 0})
		brazier(p + Vector3(-sx * 0.0, 0.0, 5.0) + Vector3(sx * 1.2, 0, 0), 1.35)
	if quality != Quality.LOW:
		# smaller pairs lining the bridge lead the eye to the gate
		for i in 2:
			for sx in [-1.0, 1.0]:
				var z := 40.0 + i * 30.0
				var role := "rook" if i == 0 else "pawn"
				var side := "light" if sx < 0.0 else "dark"
				var p2 := Vector3(sx * 6.2, 1.1, z)
				stone.box(Transform3D(Basis.IDENTITY, p2 + Vector3(0, 0.4, 0) - Vector3(0, 1.1, 0) + Vector3(0, 0.0, 0)), Vector3(3.2, 1.6, 3.2), stone.jitter(STONE_WARM, 0.04), "b")
				statues.append({"role": role, "side": side, "xf": Transform3D(Basis(Vector3.UP, -sx * 0.4).scaled(Vector3.ONE * 3.0), p2 + Vector3(0, 0.0, 0)), "lod": 1})

func _distant_lights() -> void:
	# watch-fires and hamlet windows far down the valley: tiny warm points give the scale of the landscape
	var count := 8 if quality == Quality.LOW else 18
	for i in count:
		var x := _rng.randf_range(-140.0, 140.0)
		var z := _rng.randf_range(-60.0, 120.0)
		if absf(x) < 70.0 and z < 40.0:
			continue
		_glow(Vector3(x, -36.0 + _rng.randf_range(-3.0, 3.0), z - 40.0), Color(1.0, 0.6, 0.25, 0.55), _rng.randf_range(2.0, 4.5))

func _mist() -> void:
	var count := 3 if quality == Quality.LOW else (5 if quality == Quality.BALANCED else 7)
	for i in count:
		mist_cards.append({"pos": Vector3(_rng.randf_range(-40.0, 40.0), -14.0 - i * 5.0, 20.0 + i * 24.0 - 40.0), "size": 360.0})
