extends RefCounted
## Import/validation tests for the Blender-generated characters. Models are parsed at runtime
## from the committed GLBs (no editor import needed). These FAIL when a deliverable is missing
## (a skipped asset must never read as a pass).
##
## Checks per class: skeleton identical to the shared humanoid (names, hierarchy), every required clip
## present with the length the manifest/spec promises (frames at 60 fps == sim ticks), rotation-only tracks,
## weapon sockets bound as BoneAttachment3D with props that follow the animated hand, character scale vs the
## simulation capsule, triangle budgets, LOD1 variant, convex collision proxy, textures, team-tint surface,
## and the strike reaching about the simulation's reachM.

const CLASSES := ["pawn", "knight", "bishop", "rook", "queen", "king"]
const ROLES := {"pawn": "p", "knight": "n", "bishop": "b", "rook": "r", "queen": "q", "king": "k"}
const REACH := {"pawn": 1.95, "knight": 1.65, "bishop": 1.75, "rook": 2.0, "queen": 1.65, "king": 1.8}
const CAPSULE_RADIUS := {"pawn": 0.38, "knight": 0.45, "bishop": 0.4, "rook": 0.5, "queen": 0.4, "king": 0.45}
const SCALE := {"pawn": 0.94, "knight": 1.04, "bishop": 1.0, "rook": 1.12, "queen": 1.0, "king": 1.06}
const MANIFEST := "res://assets/combat/manifest/asset_manifest.json"
const CORE_BONES := ["Root", "Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "LeftShoulder", "LeftUpperArm",
		"LeftLowerArm", "LeftHand", "RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperLeg",
		"LeftLowerLeg", "LeftFoot", "LeftToes", "RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes"]
const SOCKET_BONES := ["WeaponSocket_R", "WeaponSocket_L", "ShieldSocket_L", "BackSocket", "HeadTop"]


static func _manifest() -> Dictionary:
	if not FileAccess.file_exists(MANIFEST):
		return {}
	return JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))


static func _load(cls: String, suffix: String = "") -> Node3D:
	return CharacterModel.load_scene("res://assets/combat/characters/%s/%s%s.glb" % [cls, cls, suffix])


static func _tris(model: Node) -> int:
	var total := 0
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = mi.mesh
		for i in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(i)
			var idx = arrays[Mesh.ARRAY_INDEX]
			total += (idx.size() if idx != null else arrays[Mesh.ARRAY_VERTEX].size()) / 3
	return total


static func run(h, tree: SceneTree) -> void:
	var manifest := _manifest()
	h.begin("assets: manifest exists and lists every class")
	h.check(not manifest.is_empty(), "asset_manifest.json exists")
	var reference_bones: Array = []
	for cls in CLASSES:
		await _check_class(h, tree, cls, manifest, reference_bones)
	_check_arena(h, tree, manifest)


static func _check_class(h, tree: SceneTree, cls: String, manifest: Dictionary, reference_bones: Array) -> void:
	h.begin("assets/%s: loads, shared skeleton, sockets" % cls)
	var model := _load(cls)
	if not h.check(model != null, "%s.glb loads" % cls):
		return
	tree.root.add_child(model)
	await tree.physics_frame
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	h.eq(skeletons.size(), 1, "exactly one Skeleton3D")
	var sk: Skeleton3D = skeletons[0]
	var names: Array = []
	for i in sk.get_bone_count():
		names.append(sk.get_bone_name(i))
	for bone in CORE_BONES + SOCKET_BONES:
		h.check(bone in names, "bone %s present" % bone)
	if reference_bones.is_empty():
		reference_bones.append_array(names)
	h.eq(names, reference_bones, "bone names and order are identical to the other classes (shared rig)")
	h.eq(sk.get_bone_name(sk.get_bone_parent(sk.find_bone("LeftHand"))), "LeftLowerArm", "hierarchy: LeftHand under LeftLowerArm")
	h.near(sk.get_bone_global_rest(sk.find_bone("Hips")).origin.y, 0.95 * float(SCALE[cls]), 0.06, "hips height scales with the class")
	var head_top: float = sk.get_bone_global_rest(sk.find_bone("HeadTop")).origin.y
	h.near(head_top, 1.90 * float(SCALE[cls]), 0.12, "overall height ~%.2f m" % head_top)
	var attachments := model.find_children("*", "BoneAttachment3D", true, false)
	var bound: Array = attachments.map(func(a): return a.bone_name)
	h.check("WeaponSocket_R" in bound, "weapon bound to WeaponSocket_R")
	if cls in ["knight", "rook"]:
		h.check("ShieldSocket_L" in bound, "shield bound to ShieldSocket_L")
	if cls == "queen":
		h.check("WeaponSocket_L" in bound, "second blade bound to WeaponSocket_L")

	h.begin("assets/%s: materials, textures, team tint, budgets" % cls)
	var textured := 0
	var accent := 0
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var mat: Material = mi.mesh.surface_get_material(i)
			if mat is StandardMaterial3D:
				if mat.albedo_texture != null:
					textured += 1
				if String(mat.resource_name).ends_with("_Accent"):
					accent += 1
	h.check(textured >= 2, "at least two textured materials (%d)" % textured)
	h.check(accent >= 1, "a *_Accent team-tint material exists")
	var tris := _tris(model)
	h.check(tris > 800, "a real mesh, not a stub (%d tris)" % tris)
	h.check(tris <= 14000, "LOD0 within budget incl. props (%d <= 14000)" % tris)
	var lod1 := _load(cls, "_lod1")
	if h.check(lod1 != null, "mobile LOD1 exists"):
		var lod_tris := _tris(lod1)
		h.check(lod_tris < tris * 0.75, "LOD1 is clearly lighter (%d vs %d)" % [lod_tris, tris])
		h.check(lod1.find_children("*", "Skeleton3D", true, false).size() == 1, "LOD1 keeps the skeleton")
		lod1.free()
	var hull := _load(cls, "_collision")
	if h.check(hull != null, "collision proxy exists"):
		var mesh: MeshInstance3D = hull.find_children("*", "MeshInstance3D", true, false)[0]
		var shape := mesh.mesh.create_convex_shape()
		h.check(shape != null and shape.points.size() <= 128, "convex hull with <=128 points (%d)" % (shape.points.size() if shape else -1))
		var width := mesh.get_aabb().size.x
		h.check(width * 0.5 <= float(CAPSULE_RADIUS[cls]) + 0.45, "body half-width %.2f fits the simulation capsule %.2f (+ pauldrons)" % [width * 0.5, CAPSULE_RADIUS[cls]])
		hull.free()

	h.begin("assets/%s: animation set matches the sim timelines" % cls)
	var ap: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0] if not model.find_children("*", "AnimationPlayer", true, false).is_empty() else null
	if h.check(ap != null, "AnimationPlayer present"):
		var promised: Dictionary = manifest.get("characters", {}).get(cls, {}).get("clips", {})
		for clip in CharacterModel.REQUIRED_CLIPS:
			if not h.check(ap.has_animation(clip), "clip '%s' exists" % clip):
				continue
			var anim := ap.get_animation(clip)
			if promised.has(clip):
				h.near(anim.length * 60.0, float(promised[clip]), 1.01, "'%s' is %d frames at 60 fps (%.1f)" % [clip, promised[clip], anim.length * 60.0])
			for t in anim.get_track_count():
				var kind := anim.track_get_type(t)
				h.check(kind != Animation.TYPE_SCALE_3D, "'%s' has no scale tracks" % clip)
				if kind == Animation.TYPE_POSITION_3D:
					var path := String(anim.track_get_path(t))
					h.check(path.ends_with(":Hips") or path.ends_with(":Root"), "'%s' only translates Hips/Root (%s)" % [clip, path])
		var idle := ap.get_animation("idle")
		var light := ap.get_animation("light_1")
		h.check(light.length > 0.2, "light_1 has real duration")
		var first_rot := _first_rotation_track(idle)
		h.check(first_rot >= 0, "idle animates rotations")

		h.begin("assets/%s: props follow the animated hand; strike reach vs sim reachM" % cls)
		var attach: BoneAttachment3D = null
		for a in attachments:
			if a.bone_name == "WeaponSocket_R":
				attach = a
		if attach != null and not attach.get_children().is_empty():
			var prop: MeshInstance3D = attach.get_child(0)
			var before: Vector3 = (prop.global_transform * prop.get_aabb()).get_center()
			ap.play("light_1")
			var active := 0.5 * (ap.get_animation("light_1").length) * 0.9
			ap.seek(active, true)
			await tree.physics_frame
			await tree.physics_frame
			var after_box: AABB = prop.global_transform * prop.get_aabb()
			h.check(before.distance_to(after_box.get_center()) > 0.15, "the weapon moved with the arm during light_1 (%.2f m)" % before.distance_to(after_box.get_center()))
			var far := 0.0
			for corner in 8:
				var c := after_box.get_endpoint(corner)
				far = maxf(far, Vector2(c.x, c.z).length())
			var reach: float = REACH[cls]
			h.check(far >= reach - 0.8 and far <= reach + 1.4, "strike extent %.2f m is plausible for reachM %.2f" % [far, reach])
		else:
			h.check(false, "weapon prop is attached to WeaponSocket_R")
	model.queue_free()


static func _first_rotation_track(anim: Animation) -> int:
	for t in anim.get_track_count():
		if anim.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			return t
	return -1


static func _check_arena(h, tree: SceneTree, manifest: Dictionary) -> void:
	h.begin("assets/arena: GLB exists, LOD1, light sidecar")
	for file in ["stone_arena.glb", "stone_arena_lod1.glb", "stone_arena_lights.json"]:
		h.check(FileAccess.file_exists("res://assets/combat/arena/" + file), "%s exists" % file)
	var arena := CharacterModel.load_scene("res://assets/combat/arena/stone_arena.glb")
	if h.check(arena != null, "arena loads"):
		tree.root.add_child(arena)
		var aabb := AABB()
		var first := true
		for mi in arena.find_children("*", "MeshInstance3D", true, false):
			var box: AABB = mi.global_transform * mi.get_aabb()
			aabb = box if first else aabb.merge(box)
			first = false
		h.check(aabb.size.x >= 14.0 and aabb.size.x <= 40.0, "arena footprint %.1f m (wall inner radius 7.1 plus outer props)" % aabb.size.x)
		h.check(absf(aabb.position.y) < 0.6, "floor sits at y=0 (lowest point %.2f)" % aabb.position.y)
		h.check(_tris(arena) <= 40000, "arena within budget (%d tris)" % _tris(arena))
		arena.free()
