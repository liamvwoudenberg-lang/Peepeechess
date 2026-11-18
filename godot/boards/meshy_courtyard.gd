class_name MeshyCourtyard
extends RefCounted
## Meshy models for the chess world: the Weathered Chessboard as the board's stone base and the castle
## courtyard fortress (decimated offline, see tools/environment/decimate_fortress.gd) around it.
## Placement is numeric: the fortress' open courtyard centre/floor were measured from its vertices.

## Off until the placement is verified in a real render: the first numeric placement hid the board and pieces.
const ENABLED := true
const BASE_ENABLED := true
const FORTRESS_MESH := "res://assets/environment/courtyard_fortress/fortress_decimated.res"
const FORTRESS_TEXTURE := "res://assets/environment/courtyard_fortress/Meshy_AI_castle_courtyard_fortress_20261114_image-to-3d-texture_0.png"
const BOARD_SCENE := "res://assets/environment/chessboard/Meshy_AI_Weathered_Chessboard_20261114_texture.fbx"
const COURTYARD_CENTER := Vector3(-0.077, -0.181, -0.024)  # measured: widest open floor in the mesh
const FORTRESS_SCALE := 40.0
const FLOOR_Y := -0.11
const BOARD_WIDTH := 9.2   # the painted field is ~87% of the slab: 8.0 m, exactly the 8x8 tiles; the carved frame is the rest
const FRAME_SINK := 0.06    # the old gold frame box is lowered this far so the slab's carved border (up to 1.4 cm below its top) is not hidden
const BOARD_TOP := -0.036  # highest vertex; the frame boxes top out at -0.04, the tiles span -0.04..0.04

## The fortress, positioned so its courtyard floor lies just under the board. null when unavailable.
static func fortress() -> MeshInstance3D:
	if not ResourceLoader.exists(FORTRESS_MESH):
		return null
	var mesh := load(FORTRESS_MESH) as Mesh
	if mesh == null:
		return null
	var mi := MeshInstance3D.new()
	mi.name = "MeshyFortress"
	mi.mesh = mesh
	var tex := load(FORTRESS_TEXTURE) as Texture2D
	if tex != null:
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.roughness = 0.9
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = mat
	mi.scale = Vector3.ONE * FORTRESS_SCALE
	mi.position = Vector3(-COURTYARD_CENTER.x, FLOOR_Y - COURTYARD_CENTER.y * FORTRESS_SCALE, -COURTYARD_CENTER.z) * Vector3(FORTRESS_SCALE, 1, FORTRESS_SCALE)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## The Weathered Chessboard model as the board's stone base and frame. The FBX instance already carries its own -90 deg X rotation and x100
## scale, so the model's own transforms decide "up": its thin axis is world Y, +Y is the face with the painted squares, and the slab is flat
## (rim only ~2 cm above the field once scaled). It is normalised to BOARD_WIDTH with its highest vertex at BOARD_TOP, just below the tile
## tops, so tiles, pieces, labels and marks all stand above it. null when unavailable. Meta: "top_y", "width", "thickness".
static func board_base() -> Node3D:
	if not ResourceLoader.exists(BOARD_SCENE):
		return null
	var packed := load(BOARD_SCENE) as PackedScene
	if packed == null:
		return null
	var root := Node3D.new()
	root.name = "MeshyBoardBase"
	var model := packed.instantiate() as Node3D
	root.add_child(model)
	var box := _model_bounds(model)
	if box.size.x <= 0.0 or box.size.z <= 0.0:
		root.free()
		return null
	var k := BOARD_WIDTH / maxf(box.size.x, box.size.z)
	var c := box.get_center()
	model.scale = Vector3.ONE * k
	model.position = Vector3(-c.x * k, BOARD_TOP - (box.position.y + box.size.y) * k, -c.z * k)
	root.set_meta("top_y", BOARD_TOP)
	root.set_meta("width", BOARD_WIDTH)
	root.set_meta("thickness", box.size.y * k)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var instance := mi as MeshInstance3D
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var source := instance.mesh.surface_get_material(0)
		if source is StandardMaterial3D:   # weathered stone, not polished: no mirror highlights under the key light
			var matte := (source as StandardMaterial3D).duplicate() as StandardMaterial3D
			matte.metallic = 0.0
			matte.metallic_specular = 0.2
			matte.roughness = 0.9
			matte.albedo_color = Color(0.78, 0.76, 0.74)
			instance.material_override = matte
	return root


## The union of every mesh's AABB in the model's own space (the FBX's mesh node carries the rotation and scale).
static func _model_bounds(model: Node3D) -> AABB:
	var union := AABB()
	var first := true
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var node: Node = mi
		while node != null and node != model:
			xf = (node as Node3D).transform * xf
			node = node.get_parent()
		var box := xf * (mi as MeshInstance3D).get_aabb()
		union = box if first else union.merge(box)
		first = false
	return union
