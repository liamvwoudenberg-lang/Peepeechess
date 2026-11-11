class_name BattleWorld
extends Node3D
## The ONE persistent 3D world: chess board on top, underground chamber below, one camera.
##
##   BattleWorld (this node, world origin)
##   |- WorldEnvironment, key/fill lights   (board render layer only)
##   |- BoardRoot      tiles, slabs, pieces, marks (ChessBoard3D builds into it); lifted + shifted
##   |                 during a battle so the contested tile is above the arena centre
##   |  `- TrapdoorController
##   |- PitChamber     ceiling+hole, light shaft, ladder, ArenaMount (the CombatArena goes here, at
##   |                 the origin, unscaled: the combat simulation works in world space)
##   |- CameraRig      the single Camera3D
##   |- MorphFx x2     pooled flash/dust
##   `- PitSequence    the capture presentation state machine
##
## The world is its own clock: advance(dt) steps pit, trapdoor, camera and FX in a fixed order and
## _process calls it unless auto_advance is false (headless tests step it explicitly).

const W := preload("res://world/world_constants.gd")

signal battle_shift_changed(active: bool)

var rig: CameraRig
var board_root: Node3D
var trapdoor: TrapdoorController
var chamber: PitChamber
var pit: PitSequence
var fx: Array[MorphFx] = []
var board: Node = null
var quality := "high"
var auto_advance := true
var shifted := false
var environment: Environment
var key_light: DirectionalLight3D
var fill_light: DirectionalLight3D


func _init() -> void:
	name = "BattleWorld"
	process_priority = 100
	var env_node := WorldEnvironment.new()
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("14272e")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b5d0d1")
	environment.ambient_light_energy = 0.22
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env_node.environment = environment
	add_child(env_node)
	key_light = DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-55, -25, 0)
	key_light.light_color = Color("fff0d5")
	key_light.light_energy = 0.42
	key_light.shadow_enabled = true
	key_light.light_cull_mask = W.LAYER_BOARD
	add_child(key_light)
	fill_light = DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-30, 145, 0)
	fill_light.light_color = Color("a2c5df")
	fill_light.light_energy = 0.18
	fill_light.light_cull_mask = W.LAYER_BOARD
	add_child(fill_light)
	board_root = Node3D.new()
	board_root.name = "BoardRoot"
	add_child(board_root)
	trapdoor = TrapdoorController.new()
	trapdoor.name = "Trapdoor"
	board_root.add_child(trapdoor)
	chamber = PitChamber.new()
	add_child(chamber)
	rig = CameraRig.new()
	rig.name = "CameraRig"
	rig.auto_advance = false
	add_child(rig)
	for i in 2:
		var effect := MorphFx.new()
		effect.name = "MorphFx%d" % i
		add_child(effect)
		fx.append(effect)
	pit = PitSequence.new()
	pit.name = "PitSequence"
	pit.setup(self)
	add_child(pit)
	trapdoor.changed.connect(func(openness: float): chamber.set_light_shaft(openness))
	set_quality("low" if OS.has_feature("mobile") else "high")


## Called by ChessBoard3D after it has built its tiles/slabs.
func bind_board(p_board: Node, tiles: Array, slabs: Array) -> void:
	board = p_board
	trapdoor.bind(tiles, slabs)


func set_quality(value: String) -> void:
	quality = value
	var low := value == "low"
	key_light.shadow_enabled = not low
	for effect in fx:
		effect.set_low_quality(low)
	chamber.apply_quality(value)


func set_animate(value: bool) -> void:
	rig.animate = value
	trapdoor.animate = value


func _process(delta: float) -> void:
	if auto_advance:
		advance(delta)


## Fixed order so the camera always sees this frame's pit/trapdoor state.
func advance(dt: float) -> void:
	pit.advance(dt)
	trapdoor.advance(dt)
	rig.advance(dt)
	for effect in fx:
		effect.advance(dt)


# ---- board access for the pit ---------------------------------------------------------------------
func can_present() -> bool:
	return board != null and trapdoor != null


func piece_node(piece_id: String) -> Node3D:
	if board == null:
		return null
	return board.pieces.get(piece_id, null)


func hold_board(value: bool) -> void:
	if board != null:
		board.set_sync_hold(value)


static func tag_board(node: Node) -> void:
	if node is VisualInstance3D:
		node.layers = W.LAYER_BOARD
	for child in node.find_children("*", "VisualInstance3D", true, false):
		child.layers = W.LAYER_BOARD


# ---- floating origin ---------------------------------------------------------------------------------
## Lifts the board to BOARD_DEPTH and shifts it so `tile_center` (board-local) is above the arena
## centre. The camera moves with it, so the picture is unchanged.
func apply_shift(tile_center: Vector3) -> void:
	board_root.position = Vector3(-tile_center.x, W.BOARD_DEPTH, -tile_center.z)
	rig.set_origin(board_root.position)
	chamber.activate()
	shifted = true
	battle_shift_changed.emit(true)


func clear_shift() -> void:
	board_root.position = Vector3.ZERO
	rig.set_origin(Vector3.ZERO)
	chamber.deactivate()
	shifted = false
	battle_shift_changed.emit(false)


## End of a sequence (normal or aborted): everything back to the plain chess world. `entries` are
## the two piece nodes with their original local position and y rotation.
func restore_after_battle(entries: Array, success: bool, winner: int = -1) -> void:
	if trapdoor.is_active():
		trapdoor.snap_closed()
	for i in entries.size():
		var node: Node3D = entries[i]["node"]
		if not is_instance_valid(node):
			continue
		node.scale = Vector3.ONE
		node.rotation = Vector3(0, entries[i]["rot_y"], 0)
		tag_board(node)
		if success and i == winner:
			node.visible = true
		elif success:
			node.visible = false      # the committed chess state removes the loser's mesh
			node.position = entries[i]["pos"]
		else:
			node.visible = true
			node.position = entries[i]["pos"]
	clear_shift()
	if success:
		rig.snap_to(rig.chess_view)
	hold_board(false)
	if board != null:
		# After the sync only pieces that still exist in the chess state remain; make sure none is hidden.
		for entry in entries:
			var node: Node3D = entry["node"]
			if is_instance_valid(node) and node.get_parent() != null and not node.visible and board.pieces.values().has(node):
				node.visible = true
