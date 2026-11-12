extends RefCounted
## Validation of the generated WORLD assets (godot/assets/world, produced by tools/blender/) and of the four world clips
## (climb, ladder_idle, drop_fall, land) in the six fighter GLBs. GLBs are parsed at runtime (no editor import needed). Missing
## deliverables FAIL, they never skip.
##
## Contracts checked here are the ones the world presentation code relies on; they are documented in godot/assets/world/README.md.

const W := "res://assets/world/"
const ROLES := ["pawn", "knight", "bishop", "rook", "queen", "king"]
const SIDES := ["light", "dark"]
const HEIGHT := {"pawn": 0.70, "knight": 1.0, "bishop": 1.04, "rook": 0.85, "queen": 1.19, "king": 1.31}
const CLASSES := ["pawn", "knight", "bishop", "rook", "queen", "king"]
const CLIPS := {"climb": 72, "ladder_idle": 120, "drop_fall": 40, "land": 36}
const LOOPING := ["climb", "ladder_idle", "drop_fall"]
const RUNG := 0.25
const PLANE := 0.42
const GRIP := 0.07
const BALL := 0.062
const FILES := "abcdefgh"


static func _load(rel: String) -> Node3D:
	return CharacterModel.load_scene(W + rel)


static func _tris(node: Node) -> int:
	var total := 0
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = mi.mesh
		for i in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(i)
			var idx = arrays[Mesh.ARRAY_INDEX]
			total += (idx.size() if idx != null else arrays[Mesh.ARRAY_VERTEX].size()) / 3
	return total


## AABB of every mesh at or under `node`, in the space of `root` (default: node's own space), for nodes outside the tree too.
static func _aabb(node: Node3D, root: Node3D = null) -> AABB:
	var stop: Node = root if root != null else node
	var box := AABB()
	var first := true
	var meshes: Array = node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		meshes.append(node)
	for mi in meshes:
		var m: MeshInstance3D = mi
		var xf := Transform3D.IDENTITY
		var n: Node = m
		while n != null and n != stop:
			if n is Node3D:
				xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var b := xf * m.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


static func _min_ring(node: Node3D) -> float:
	## smallest max(|x|, |z|) over all vertices: the half-width of the opening of a square ring
	var best := 1e9
	var meshes: Array = node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		meshes.append(node)
	for mi in meshes:
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			for v in mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				best = minf(best, maxf(absf(v.x), absf(v.z)))
	return best


static func _materials(node: Node) -> Array:
	var names: Array = []
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i)
			if mat != null and not names.has(String(mat.resource_name)):
				names.append(String(mat.resource_name))
	return names


static func run(h, tree: SceneTree) -> void:
	_pieces(h)
	_board(h)
	_pit(h)
	await _clips(h, tree)


# ----------------------------------------------------------------------------------------------------------------------
static func _pieces(h) -> void:
	h.begin("world/pieces: manifest and all 12 pieces + LOD1 exist")
	var manifest_path := W + "manifest/world_manifest.json"
	h.check(FileAccess.file_exists(manifest_path), "world_manifest.json exists")
	var heights := {}
	for role in ROLES:
		for side in SIDES:
			var base_name := "%s_%s" % [role, side]
			h.begin("world/pieces/%s: pivot, scale, budget, materials" % base_name)
			var piece := _load("pieces/%s.glb" % base_name)
			if not h.check(piece != null, "%s.glb loads" % base_name):
				continue
			var root_name := "Piece_%s_%s" % [role.capitalize(), side.capitalize()]
			h.check(piece.name == root_name or piece.find_child(root_name, true, false) != null, "piece root node %s exists" % root_name)
			h.check(piece.find_child("Piece_%s_%s_Mesh" % [role.capitalize(), side.capitalize()], true, false) != null, "mesh node exists")
			var box := _aabb(piece)
			h.near(box.position.y, 0.0, 0.005, "pivot on the floor (min y)")
			h.near(box.get_center().x, 0.0, 0.03, "centred on x")
			h.near(box.end.y, float(HEIGHT[role]), 0.06, "height %.2f m is the designed ~%.2f" % [box.end.y, HEIGHT[role]])
			h.check(box.size.x <= 0.76 and box.size.z <= 0.80, "fits the 1.0 m tile (%.2f x %.2f)" % [box.size.x, box.size.z])
			h.check(box.size.x >= 0.56, "base is about 0.7 m wide (%.2f)" % box.size.x)
			var tris := _tris(piece)
			h.check(tris <= 2500 and tris > 300, "triangle budget (%d <= 2500)" % tris)
			var mats := _materials(piece)
			h.check(mats.size() >= 3 and mats.any(func(m): return String(m).begins_with("Piece_%s" % side.capitalize())), "has the %s material set %s" % [side, str(mats)])
			if side == "light":
				heights[role] = box.end.y
			var lod := _load("pieces/%s_lod1.glb" % base_name)
			if h.check(lod != null, "LOD1 exists"):
				h.check(_tris(lod) < tris * 0.75, "LOD1 is lighter (%d vs %d)" % [_tris(lod), tris])
				h.near(_aabb(lod).end.y, box.end.y, 0.06, "LOD1 keeps the height")
				lod.free()
			piece.free()
	h.begin("world/pieces: silhouettes ordered pawn < rook < knight < bishop < queen < king")
	h.check(heights["pawn"] < heights["rook"] and heights["rook"] < heights["knight"] and heights["knight"] < heights["bishop"] \
			and heights["bishop"] < heights["queen"] and heights["queen"] < heights["king"], "heights are strictly ordered %s" % str(heights))
	h.near(heights["king"], 1.3, 0.1, "king ~1.3 m")
	h.near(heights["pawn"], 0.7, 0.05, "pawn ~0.7 m")


static func _img_wrap_ok(path: String) -> bool:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null:
		return false
	img.convert(Image.FORMAT_RGB8)
	var w := img.get_width()
	var h_ := img.get_height()
	var wrap := 0.0
	var inner := 0.0
	for y in range(0, h_, 4):
		wrap += absf(img.get_pixel(0, y).r - img.get_pixel(w - 1, y).r)
		inner += absf(img.get_pixel(w / 2, y).r - img.get_pixel(w / 2 - 1, y).r)
	for x in range(0, w, 4):
		wrap += absf(img.get_pixel(x, 0).r - img.get_pixel(x, h_ - 1).r)
		inner += absf(img.get_pixel(x, h_ / 2).r - img.get_pixel(x, h_ / 2 - 1).r)
	return wrap <= inner * 2.0 + 0.02 * (w / 4.0)


static func _board(h) -> void:
	h.begin("world/board: tiles match Codex's tile (0.995 x 0.08 x 0.995) and carry marble textures")
	for side in SIDES:
		var tile := _load("board/tile_%s.glb" % side)
		if not h.check(tile != null, "tile_%s.glb loads" % side):
			continue
		var box := _aabb(tile)
		h.near(box.size.x, 0.995, 0.002, "tile width")
		h.near(box.size.z, 0.995, 0.002, "tile depth")
		h.near(box.size.y, 0.08, 0.002, "tile height")
		h.near(box.get_center().y, 0.0, 0.002, "centred on y = 0 (top at +0.04)")
		h.check(_materials(tile).has("Tile_%s" % side.capitalize()), "material Tile_%s" % side.capitalize())
		tile.free()
		var tex := W + "textures/Tile_%s.png" % side.capitalize()
		var img := Image.load_from_file(ProjectSettings.globalize_path(tex))
		if h.check(img != null, "texture %s exists" % tex):
			h.check(img.get_width() <= 512 and img.get_height() <= 512, "texture <= 512 px (%dx%d)" % [img.get_width(), img.get_height()])
			h.check(_img_wrap_ok(tex), "%s is seamless (edges wrap like neighbouring pixels)" % tex)
		var mat = load(W + "materials/tile_%s.tres" % side)
		h.check(mat is StandardMaterial3D and (mat as StandardMaterial3D).albedo_texture != null, "materials/tile_%s.tres loads with its texture" % side)

	h.begin("world/board: frame, corner posts and plinth around the 8 x 8 board")
	var frame := _load("board/board_frame.glb")
	if h.check(frame != null, "board_frame.glb loads"):
		for n in ["BoardFrame", "BoardFrame_Mesh", "BoardBase_Mesh", "CornerPost_NE_Mesh", "CornerPost_SW_Mesh"]:
			h.check(frame.find_child(n, true, false) != null, "node %s" % n)
		var ring := frame.find_child("BoardFrame_Mesh", true, false) as Node3D
		var rb := _aabb(ring)
		h.near(rb.end.x, 5.10, 0.05, "plinth outer half-width")
		h.near(_min_ring(ring), 4.0, 0.01, "inner edge of the frame at |x| = 4.0 (tiles end at 3.9975)")
		h.check(rb.end.y > 0.05 and rb.end.y < 0.2, "frame top is just above the tile tops (%.2f)" % rb.end.y)
		h.check(rb.position.y <= -0.5, "plinth extends below the tiles (%.2f)" % rb.position.y)
		h.check(_tris(frame) <= 2500, "frame budget (%d tris)" % _tris(frame))
		frame.free()

	h.begin("world/board: 32 file/rank plaques at Interaction.world_position() coordinates")
	var plaques := _load("board/board_plaques.glb")
	if h.check(plaques != null, "board_plaques.glb loads"):
		for i in 8:
			var f: String = FILES[i]
			for edge in ["s", "n"]:
				var node := plaques.find_child("plaque_file_%s_%s" % [f, edge], true, false) as Node3D
				if h.check(node != null, "plaque_file_%s_%s" % [f, edge]):
					h.near(node.position.x, float(i) - 3.5, 0.001, "file %s at x = i - 3.5" % f)
					h.near(absf(node.position.z), 4.39, 0.01, "file plaque on the border field")
			for edge in ["w", "e"]:
				var rn := plaques.find_child("plaque_rank_%d_%s" % [i + 1, edge], true, false) as Node3D
				if h.check(rn != null, "plaque_rank_%d_%s" % [i + 1, edge]):
					h.near(rn.position.z, float(i + 1) - 4.5, 0.001, "rank %d at z = r - 4.5" % (i + 1))
					h.near(absf(rn.position.x), 4.39, 0.01, "rank plaque on the border field")
		h.check(plaques.find_child("plaque_file_a_s_glyph", true, false) != null, "glyph nodes exist")
		h.check(_materials(plaques).has("Plaque_Gold") and _materials(plaques).has("Plaque_Stone"), "plaque materials")
		h.check(_tris(plaques) <= 5000, "plaque budget (%d drawn tris)" % _tris(plaques))
		plaques.free()


# ----------------------------------------------------------------------------------------------------------------------
static func _pit(h) -> void:
	for side in SIDES:
		h.begin("world/pit/trapdoor_%s: leaves, hinge pivots at the tile edges, tile-sized" % side)
		var td := _load("pit/trapdoor_%s.glb" % side)
		if not h.check(td != null, "trapdoor_%s.glb loads" % side):
			continue
		var hl := td.find_child("hinge_left", true, false) as Node3D
		var hr := td.find_child("hinge_right", true, false) as Node3D
		if h.check(hl != null and hr != null, "nodes hinge_left / hinge_right exist"):
			h.near(hl.position.x, -0.4975, 0.001, "hinge_left at the left tile edge")
			h.near(hr.position.x, 0.4975, 0.001, "hinge_right at the right tile edge")
			h.near(hl.position.y, 0.0, 0.001, "hinge on the tile mid-plane")
			h.check(hl.find_child("leaf_left", true, false) != null and hr.find_child("leaf_right", true, false) != null, "each hinge holds its leaf mesh")
			var box := _aabb(td)
			h.near(box.size.x, 0.995, 0.01, "closed width 0.995")
			h.near(box.size.z, 0.995, 0.01, "closed depth 0.995")
			h.near(box.end.y, 0.04, 0.002, "top flush with the tile top")
			h.near(box.position.y, -0.047, 0.01, "underside incl. straps")
			# Open: rotate the pivots, the free edges must drop into the shaft
			hl.rotation_degrees.z = -90.0
			hr.rotation_degrees.z = 90.0
			for leaf_name in ["leaf_left", "leaf_right"]:
				var lb := _aabb(td.find_child(leaf_name, true, false) as Node3D, td)
				h.check(lb.position.y < -0.45 and lb.size.x < 0.1 and lb.end.y < 0.06, "%s swung open hangs down the shaft wall (y %.2f..%.2f, thickness %.2f)" % [leaf_name, lb.position.y, lb.end.y, lb.size.x])
		var mats := _materials(td)
		h.check(mats.has("Tile_%s" % side.capitalize()) and mats.has("Pit_Wood") and mats.has("Pit_Iron"), "tile top + wood underside + iron %s" % str(mats))
		h.check(_tris(td) <= 1500, "budget (%d tris)" % _tris(td))
		td.free()

	h.begin("world/pit: shaft rim (1.0 opening, ~1.4 outer) and tileable wall segment")
	var rim := _load("pit/shaft_rim.glb")
	if h.check(rim != null, "shaft_rim.glb loads"):
		var rb := _aabb(rim)
		h.near(_min_ring(rim), 0.5, 0.0125, "opening is one tile (1.0)")
		h.check(rb.size.x >= 1.4 and rb.size.x <= 1.5, "outer ~1.4 m (%.2f)" % rb.size.x)
		h.near(rb.end.y, -0.04, 0.002, "top just under the tile layer (y = -0.04)")
		rim.free()
	var wall := _load("pit/shaft_wall_segment.glb")
	if h.check(wall != null, "shaft_wall_segment.glb loads"):
		var wb := _aabb(wall)
		h.near(wb.position.y, 0.0, 0.001, "origin at the bottom")
		h.near(wb.size.y, 1.0, 0.001, "1.0 m tall: stacks without gaps")
		h.near(wb.size.x, 1.4, 0.001, "outer 1.4 m")
		h.near(_min_ring(wall), 0.5, 0.0125, "inner opening 1.0")
		wall.free()

	h.begin("world/pit: ladder segment, top section and 10 m assembly with climb anchors")
	_check_ladder(h, "ladder_segment_2m.glb", 8, 2, 2.0, 1.9)
	_check_ladder(h, "ladder_top.glb", 7, 2, 1.75, 1.7)
	_check_ladder(h, "ladder_full_10m.glb", 39, 2, 9.5, 9.9)

	h.begin("world/pit: chamber ceiling cap with a one-tile hole, light cone helper")
	var cap := _load("pit/chamber_ceiling.glb")
	if h.check(cap != null, "chamber_ceiling.glb loads"):
		var cb := _aabb(cap)
		h.near(_min_ring(cap), 0.5, 0.0125, "hole is one tile (1.0 x 1.0)")
		h.check(cb.size.x >= 15.9, "covers the arena (%.1f m wide)" % cb.size.x)
		h.check(_tris(cap) <= 800, "budget (%d tris)" % _tris(cap))
		cap.free()
	var cone := _load("pit/light_cone.glb")
	if h.check(cone != null, "light_cone.glb loads"):
		var cb := _aabb(cone)
		h.near(cb.size.y, 1.0, 0.001, "unit height")
		h.near(cb.end.y, 0.0, 0.001, "apex end at y = 0")
		h.check(cb.size.x > 2.0, "widens downwards (%.1f)" % cb.size.x)
		h.check(_tris(cone) <= 16, "trivial mesh (%d tris)" % _tris(cone))
		var mi := cone.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		h.check(mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] != null, "vertex colours carry the alpha falloff")
		cone.free()
	var cone_mat = load(W + "materials/light_cone.tres")
	h.check(cone_mat is StandardMaterial3D and (cone_mat as StandardMaterial3D).blend_mode == BaseMaterial3D.BLEND_MODE_ADD \
			and (cone_mat as StandardMaterial3D).shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "materials/light_cone.tres is unshaded additive")


static func _check_ladder(h, file: String, rungs: int, mats_min: int, length_min: float, length_max: float) -> void:
	var ladder := _load("pit/" + file)
	if not h.check(ladder != null, "%s loads" % file):
		return
	var box := _aabb(ladder)
	h.check(box.size.y >= length_min and box.size.y <= length_max + 0.2, "%s length %.2f m" % [file, box.size.y])
	h.near(box.size.x, 0.62, 0.05, "%s width %.2f" % [file, box.size.x])
	var digits := 3 if file.contains("full") else 2
	var prev := -1e9
	var count := 0
	for k in rungs:
		var tag := ("%0" + str(digits) + "d") % k
		var rung := ladder.find_child("rung_" + tag, true, false) as Node3D
		if not h.check(rung != null, "%s: anchor rung_%s" % [file, tag]):
			return
		count += 1
		var y := rung.global_position.y if rung.is_inside_tree() else (rung.transform.origin.y + _parent_y(rung, ladder))
		if prev > -1e8:
			h.near(y - prev, RUNG, 0.0005, "%s: rung_%s spaced 0.25 from the previous" % [file, tag])
		else:
			h.near(fposmod(y, RUNG), 0.125, 0.0005, "%s: rung centres on the grid (j + 0.5) * 0.25" % file)
		prev = y
		for pair in [["hand_L_", 0.17], ["hand_R_", -0.17], ["foot_L_", 0.15], ["foot_R_", -0.15]]:
			var a := ladder.find_child(String(pair[0]) + tag, true, false) as Node3D
			if a == null:
				h.check(false, "%s: anchor %s%s" % [file, pair[0], tag])
				return
			h.near(a.transform.origin.x, float(pair[1]), 0.001, "%s %s%s x" % [file, pair[0], tag])
	h.eq(count, rungs, "%s has %d rungs" % [file, rungs])
	h.check(ladder.find_child("rung_" + (("%0" + str(digits) + "d") % rungs), true, false) == null, "%s has no extra rung" % file)
	h.check(_tris(ladder) <= 3000, "%s budget (%d tris)" % [file, _tris(ladder)])
	h.check(_materials(ladder).size() >= mats_min, "%s wood + iron materials" % file)
	ladder.free()


static func _parent_y(n: Node3D, stop: Node) -> float:
	var y := 0.0
	var p := n.get_parent()
	while p != null and p != stop.get_parent():
		if p is Node3D:
			y += (p as Node3D).transform.origin.y
		p = p.get_parent()
	return y


# ----------------------------------------------------------------------------------------------------------------------
static func _bone_pos(sk: Skeleton3D, bone: String) -> Vector3:
	return (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone))).origin


static func _clips(h, tree: SceneTree) -> void:
	h.begin("world clips: CharacterModel loops the new loop clips")
	for c in LOOPING:
		h.check(c in CharacterModel.LOOPING, "%s is in CharacterModel.LOOPING" % c)
	h.check(not ("land" in CharacterModel.LOOPING), "land is one-shot")
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/combat/manifest/asset_manifest.json"))
	for cls in CLASSES:
		for lod in [0, 1]:
			h.begin("world clips/%s lod%d: climb, ladder_idle, drop_fall, land present with the documented lengths" % [cls, lod])
			var path := "res://assets/combat/characters/%s/%s%s.glb" % [cls, cls, "_lod1" if lod == 1 else ""]
			var model := CharacterModel.load_scene(path)
			if not h.check(model != null, "%s loads" % path):
				continue
			var ap := model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
			for c in CLIPS:
				if h.check(ap.has_animation(c), "AnimationPlayer has '%s'" % c):
					h.near(ap.get_animation(c).length * 60.0, float(CLIPS[c]), 1.01, "'%s' is %d frames" % [c, CLIPS[c]])
					h.eq(int(manifest["characters"][cls]["clips"].get(c, -1)), int(CLIPS[c]), "manifest lists '%s'" % c)
					for t in ap.get_animation(c).get_track_count():
						var kind := ap.get_animation(c).track_get_type(t)
						h.check(kind != Animation.TYPE_SCALE_3D, "'%s' has no scale tracks" % c)
						if kind == Animation.TYPE_POSITION_3D:
							var tp := String(ap.get_animation(c).track_get_path(t))
							h.check(tp.ends_with(":Hips") or tp.ends_with(":Root"), "'%s' only translates Hips/Root" % c)
			# root motion stripped: no clip moves Root
			for c in CLIPS:
				var anim := ap.get_animation(c)
				for t in anim.get_track_count():
					if anim.track_get_type(t) == Animation.TYPE_POSITION_3D and String(anim.track_get_path(t)).ends_with(":Root"):
						var d := (anim.position_track_interpolate(t, 0.0) as Vector3).distance_to(anim.position_track_interpolate(t, anim.length))
						h.check(d < 0.001, "'%s' Root does not travel" % c)
			model.free()

	for cls in CLASSES:
		h.begin("world clips/%s: loop closure, ladder contacts on the 0.25 m rung grid, no sliding" % cls)
		var model := CharacterModel.load_scene("res://assets/combat/characters/%s/%s.glb" % [cls, cls])
		tree.root.add_child(model)
		var sk := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var ap := model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		for c in LOOPING:
			var anim := ap.get_animation(c)
			var worst := 0.0
			for t in anim.get_track_count():
				if anim.track_get_type(t) == Animation.TYPE_ROTATION_3D:
					var a: Quaternion = anim.rotation_track_interpolate(t, 0.0)
					var b: Quaternion = anim.rotation_track_interpolate(t, anim.length)
					worst = maxf(worst, rad_to_deg(a.angle_to(b)))
			h.check(worst < 1.0, "'%s' loops: first and last pose differ by %.2f deg" % [c, worst])
		var length := ap.get_animation("climb").length
		var hand_y: Array = []
		var hand_z: Array = []
		var toe_y: Array = []
		for i in 5:
			var u := 0.5 + 0.5 * float(i) / 4.0         # right hand + left foot HOLD during u in [0.5, 1]
			ap.play("climb")
			ap.seek(length * u, true)
			ap.pause()
			await tree.physics_frame
			await tree.physics_frame
			var rise := 2.0 * RUNG * u
			var wrist := _bone_pos(sk, "RightHand")
			hand_y.append(wrist.y + rise)
			hand_z.append(wrist.z)
			toe_y.append(_bone_pos(sk, "LeftToes").y + rise)
		var hy_min := 1e9
		var hy_max := -1e9
		var ty_min := 1e9
		var ty_max := -1e9
		for i in 5:
			hy_min = minf(hy_min, hand_y[i])
			hy_max = maxf(hy_max, hand_y[i])
			ty_min = minf(ty_min, toe_y[i])
			ty_max = maxf(ty_max, toe_y[i])
		h.check(hy_max - hy_min < 0.015, "right hand holds still while the body rises (slide %.1f mm)" % ((hy_max - hy_min) * 1000.0))
		h.check(ty_max - ty_min < 0.035, "left foot holds still (slide %.1f mm)" % ((ty_max - ty_min) * 1000.0))
		h.near(fposmod(hand_y[0] - GRIP, RUNG), 0.125, 0.012, "hand grip height is on a rung centre (j + 0.5) * 0.25")
		h.near(fposmod(toe_y[0] - BALL, RUNG), 0.125, 0.012, "ball of the foot rests on a rung")
		h.near(float(hand_z[0]), PLANE, 0.015, "hand is on the rung plane 0.42 m in front of the character")
		h.check(hand_y[0] - GRIP > 0.8, "hands are at a plausible height")
		# the character faces +Z and climbs up: the head is higher than the hands' lower rung and in front of the hips
		ap.play("ladder_idle")
		ap.seek(0.0, true)
		ap.pause()
		await tree.physics_frame
		await tree.physics_frame
		h.check(_bone_pos(sk, "Head").y > _bone_pos(sk, "RightHand").y - 0.2, "ladder_idle: head above the hands")
		model.queue_free()
		await tree.process_frame
