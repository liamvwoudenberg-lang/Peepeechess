class_name MeshyCourtyard
extends RefCounted
## Meshy models for the chess world: the Weathered Chessboard as the board's stone base and the castle
## courtyard fortress (decimated offline, see tools/environment/decimate_fortress.gd) around it.
## Placement is numeric: the fortress' open courtyard centre/floor were measured from its vertices.

const FORTRESS_MESH := "res://assets/environment/courtyard_fortress/fortress_decimated.res"
const FORTRESS_TEXTURE := "res://assets/environment/courtyard_fortress/Meshy_AI_castle_courtyard_fortress_20261114_image-to-3d-texture_0.png"
const BOARD_SCENE := "res://assets/environment/chessboard/Meshy_AI_Weathered_Chessboard_20261114_texture.fbx"
const COURTYARD_CENTER := Vector3(-0.077, -0.284, -0.024)  # measured: widest open floor in the mesh
const FORTRESS_SCALE := 28.0
const FLOOR_Y := -0.11
const BOARD_WIDTH := 9.4
const BOARD_TOP := -0.035

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

## The Weathered Chessboard model as the board's base, normalised to BOARD_WIDTH with its top at BOARD_TOP.
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
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		root.free()
		return null
	var mi: MeshInstance3D = meshes[0]
	var box := mi.get_aabb()
	var size := box.size
	# The thin axis is the board's thickness; stand it up on Y (the FBX is Z-thin).
	var thin_z := size.z < size.y
	var k := BOARD_WIDTH / maxf(size.x, size.y if thin_z else size.z)
	model.scale = Vector3.ONE * k
	var c := box.get_center() * k
	var lift := BOARD_TOP - size[2 if thin_z else 1] * k * 0.5
	if thin_z:
		model.rotation_degrees.x = -90.0  # world = (x, z, -y)
		model.position = Vector3(-c.x, lift - c.z, c.y)
	else:
		model.position = Vector3(-c.x, lift - c.y, -c.z)
	return root
