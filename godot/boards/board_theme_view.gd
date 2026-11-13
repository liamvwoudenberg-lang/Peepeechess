class_name BoardThemeView
extends RefCounted
## Applies BoardTheme to the 3D board and the 3D piece builder. Kept separate from board_3d.gd so the board
## script only needs three one-line hooks (attach_3d, destination_3d, anim_scale). Everything here is
## defensive: missing nodes are skipped, and the default theme ("slate") never overrides the board's own materials.
const Models = preload("res://boards/piece_meshes.gd")
const Interaction = preload("res://boards/board_interaction.gd")
const PIECE_DIR = "res://assets/world/pieces/"
const ROLE_NAMES = {"p": "pawn", "n": "knight", "b": "bishop", "r": "rook", "q": "queen", "k": "king"}

## Node that keeps one 3D board in sync with BoardTheme and unsubscribes when the board leaves the tree.
class Binder:
	extends Node
	var board
	func _init(p_board) -> void:
		name = "BoardThemeBinder"
		board = p_board
	func _ready() -> void:
		BoardTheme.events().changed.connect(_changed)
		BoardThemeView.apply_3d(board)
	func _changed() -> void:
		BoardThemeView.apply_3d(board)
	func _exit_tree() -> void:
		if BoardTheme.events().changed.is_connected(_changed):
			BoardTheme.events().changed.disconnect(_changed)

static func attach_3d(board: Node) -> void:
	board.add_child(Binder.new(board))

static func _flat_material(color: Color) -> StandardMaterial3D:
	return Models.material(color, 0.0)

static func _override(node: MeshInstance3D, material: Material, default_look: bool) -> void:
	if default_look:
		if node.has_meta("bt_original"):
			node.material_override = node.get_meta("bt_original")
			node.remove_meta("bt_original")
		return
	if not node.has_meta("bt_original"):
		node.set_meta("bt_original", node.material_override)
	node.material_override = material

static func apply_3d(board) -> void:
	if not is_instance_valid(board) or not "scene" in board or board.scene == null:
		return
	var scene: Node3D = board.scene
	var default_look = BoardTheme.is_default_look()
	var light_mat = _flat_material(BoardTheme.color("light_3d"))
	var dark_mat = _flat_material(BoardTheme.color("dark_3d"))
	var plinth_mat = Models.material(BoardTheme.color("plinth"), 0.3)
	var trim_mat = Models.material(BoardTheme.color("trim"), 0.7)
	var key_shadow = BoardTheme.shadows == "high"
	for child in scene.get_children():
		if child is MeshInstance3D:
			var square = -1
			for sub in child.get_children():
				if sub is StaticBody3D and sub.has_meta("square"):
					square = sub.get_meta("square")
			if square >= 0:
				_override(child, light_mat if (square % 8 + square / 8) % 2 else dark_mat, default_look)
			elif child.mesh is BoxMesh:
				var size: Vector3 = child.mesh.size
				if size.x > 8.0 and size.x < 8.75:
					_override(child, plinth_mat, default_look)
				elif size.x >= 8.75 and size.x < 9.0:
					_override(child, trim_mat, default_look)
		elif child is Label3D:
			child.visible = BoardTheme.coordinates
			child.modulate = BoardTheme.color("label_3d")
		elif child is WorldEnvironment and child.environment != null:
			child.environment.background_color = Color("14272e") if default_look else BoardTheme.color("backdrop")
	# Lights: the original board keeps them in `scene`; the pit world (godot/world/) keeps them on `board.world`.
	# The world's own low-quality mode (mobile) keeps priority: "high" never turns its shadows back on.
	var lit: Array = [scene]
	var world_low = false
	if "world" in board and board.world != null:
		lit.append(board.world)
		world_low = "quality" in board.world and board.world.quality == "low"
	for holder in lit:
		for child in holder.get_children():
			if child is DirectionalLight3D and child.light_energy >= 0.3:
				child.shadow_enabled = key_shadow and not world_low
	var signature = BoardTheme.piece_set
	if board.get_meta("bt_piece_set", signature) != signature and "pieces" in board and "_piece_roles" in board:
		for id in board.pieces.keys():
			var node: Node = board.pieces[id]
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.queue_free()
		board.pieces.clear()
		board._piece_roles.clear()
		board._last_match_id = ""
		board.set_meta("bt_piece_set", signature)
		board.sync_state()
	else:
		board.set_meta("bt_piece_set", signature)
	if "pieces" in board:
		for node in board.pieces.values():
			finish_piece(node)

## Alternate 3D piece set, or null to use the built-in procedural pieces.
static func build_piece(role: String, color: String) -> Node3D:
	if BoardTheme.piece_set == "paladin":
		return PaladinPiece.create(role, color)  # null when the models are missing: the procedural set is used
	if BoardTheme.piece_set != "carved" or not ROLE_NAMES.has(role):
		return null
	var path = "%s%s_%s%s.glb" % [PIECE_DIR, ROLE_NAMES[role], "light" if color == "w" else "dark", "_lod1" if OS.has_feature("mobile") else ""]
	if not ResourceLoader.exists(path, "PackedScene"):
		return null
	var scene = load(path)
	if not scene is PackedScene:
		return null
	var instance: Node = scene.instantiate()
	if not instance is Node3D:
		instance.free()
		return null
	# GLB pieces face +Z; the board turns white to face -Z, so pre-rotate and keep the same convention as the procedural set.
	instance.rotation.y = PI
	var root = Node3D.new()
	root.add_child(instance)
	PieceCrest.attach(root, role, color)
	return root

## Shadow quality for one piece (called for every piece the builder returns and again on a setting change).
static func finish_piece(root: Node) -> Node:
	var setting = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if BoardTheme.shadows == "high" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_set_shadows(root, setting)
	return root

static func _set_shadows(node: Node, setting: int) -> void:
	if node is GeometryInstance3D:
		node.cast_shadow = setting
	for child in node.get_children():
		_set_shadows(child, setting)

static func _mark_material(color: Color) -> StandardMaterial3D:
	var mat = Models.material(color)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat

## Legal-destination mark for the chosen highlight style (dots / rings / tile tint).
static func destination_3d(board, at: int, capture: bool) -> void:
	var at_position = Interaction.world_position(at) + Vector3(0, 0.055, 0)
	var before = board.marks.get_child_count()
	_make_destination(board, at_position, capture)
	if "world" in board and board.world != null:  # pit world: marks live on the board render layer (WorldConstants.LAYER_BOARD = 2)
		for index in range(before, board.marks.get_child_count()):
			board.marks.get_child(index).layers = 2

static func _make_destination(board, at_position: Vector3, capture: bool) -> void:
	match BoardTheme.highlight:
		"rings":
			var ring = TorusMesh.new()
			var radius = 0.4 if capture else 0.19
			ring.inner_radius = radius - 0.035
			ring.outer_radius = radius + 0.035
			ring.rings = 32
			ring.ring_segments = 6
			Models.add(board.marks, ring, at_position, _mark_material(Color(1, 0.83, 0.4, 0.9) if capture else Color(0.3, 0.9, 0.75, 0.9)), Vector3(1, 0.2, 1))
		"tint":
			var tint = BoxMesh.new()
			tint.size = Vector3(0.97, 0.012, 0.97)
			Models.add(board.marks, tint, at_position, _mark_material(Color(0.95, 0.35, 0.3, 0.42) if capture else Color(0.25, 0.85, 0.65, 0.38)))
		_:
			var disc = CylinderMesh.new()
			var disc_radius = 0.44 if capture else 0.17
			disc.top_radius = disc_radius
			disc.bottom_radius = disc_radius
			disc.height = 0.012
			disc.radial_segments = 32
			Models.add(board.marks, disc, at_position, _mark_material(Color(0.3, 0.9, 0.75, 0.85)))
