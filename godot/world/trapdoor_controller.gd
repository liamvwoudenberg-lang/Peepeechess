class_name TrapdoorController
extends Node3D
## The only part of the board that ever changes geometry: the contested tile's two hinged leaves.
##
## begin(tile) swaps the tile's solid block for two leaves that are pixel-identical while closed, and
## the board slabs under it for a ring of boxes with a hole (the originals are only hidden, never
## moved). set_target(true/false) + advance(dt) swing the leaves down/up; finish() puts the original
## tile and slabs back. Nothing is allocated after the first begin(): leaves, ring and liner are reused.

const W := preload("res://world/world_constants.gd")
const Models := preload("res://boards/piece_meshes.gd")

signal changed(openness: float)
signal opened
signal closed

var tile := -1
var openness := 0.0
var animate := true
var _target := 0.0
var _duration := W.TRAPDOOR_OPEN_TIME
var _center := Vector3.ZERO
var _tile_node: MeshInstance3D
var _tiles: Array = []
var _slabs: Array = []            # [{node, ring: Array[MeshInstance3D]}]
var _pivot_left: Node3D
var _pivot_right: Node3D
var _leaf_material: Material
var _liner: Array[Node3D] = []
var uses_shaft_asset := false
const SHAFT_RIM := "res://assets/world/pit/shaft_rim.glb"
const SHAFT_WALL := "res://assets/world/pit/shaft_wall_segment.glb"
var _built := false
var _active := false


## `tiles`: MeshInstance3D per square index. `slabs`: board slabs (plinth, frame) that must be holed.
func bind(tiles: Array, slabs: Array) -> void:
	_tiles = tiles
	_slabs.clear()
	for slab in slabs:
		_slabs.append({"node": slab, "ring": []})


func is_active() -> bool:
	return _active


func is_closed() -> bool:
	return openness <= 0.0001


func is_open() -> bool:
	return openness >= 0.9999


func _build() -> void:
	if _built:
		return
	_built = true
	_pivot_left = Node3D.new()
	_pivot_left.name = "LeafLeft"
	_pivot_right = Node3D.new()
	_pivot_right.name = "LeafRight"
	add_child(_pivot_left)
	add_child(_pivot_right)
	var half := W.TILE_SIZE * 0.5
	for entry in [[_pivot_left, 1.0], [_pivot_right, -1.0]]:
		var leaf := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(half, W.TILE_THICKNESS, W.TILE_SIZE)
		leaf.mesh = mesh
		leaf.position = Vector3(entry[1] * half * 0.5, 0, 0)
		leaf.layers = W.LAYER_BOARD
		(entry[0] as Node3D).add_child(leaf)
	for slab in _slabs:
		for i in 4:
			var piece := MeshInstance3D.new()
			piece.mesh = BoxMesh.new()
			piece.layers = W.LAYER_BOARD
			var source: MeshInstance3D = slab["node"]
			piece.material_override = source.material_override
			add_child(piece)
			slab["ring"].append(piece)
	uses_shaft_asset = _build_liner_asset()
	if not uses_shaft_asset:
		var liner_material := Models.material(Color("2a2926"), 0.0)
		liner_material.roughness = 0.95
		for i in 4:
			var wall := MeshInstance3D.new()
			wall.mesh = BoxMesh.new()
			wall.material_override = liner_material
			wall.layers = W.LAYER_BOARD | W.LAYER_CHAMBER
			add_child(wall)
			_liner.append(wall)


## Generated shaft set (godot/assets/world/pit/): rim under the tile layer + one 1 m wall segment below it.
func _build_liner_asset() -> bool:
	if not (ResourceLoader.exists(SHAFT_RIM) and ResourceLoader.exists(SHAFT_WALL)):
		return false
	var rim = load(SHAFT_RIM)
	var wall = load(SHAFT_WALL)
	if not (rim is PackedScene and wall is PackedScene):
		return false
	var holder := Node3D.new()
	holder.name = "ShaftAsset"
	var rim_node: Node3D = rim.instantiate()
	holder.add_child(rim_node)
	var wall_node: Node3D = wall.instantiate()
	wall_node.position = Vector3(0, -1.54, 0)   # stacked below the rim (rim bottom is y = -0.54)
	holder.add_child(wall_node)
	for node in [rim_node, wall_node]:
		for visual in node.find_children("*", "VisualInstance3D", true, false):
			visual.layers = W.LAYER_BOARD | W.LAYER_CHAMBER
	add_child(holder)
	_liner.append(holder)
	return true


## Prepares the hole under `at` (centre in board-local space). Visually identical to the closed tile.
func begin(at: int, center: Vector3) -> void:
	_build()
	if _active:
		finish()
	tile = at
	_center = Vector3(center.x, 0.0, center.z)
	_tile_node = _tiles[at]
	_leaf_material = _tile_node.material_override
	for pivot in [_pivot_left, _pivot_right]:
		(pivot.get_child(0) as MeshInstance3D).material_override = _leaf_material
	var half := W.TILE_SIZE * 0.5
	_pivot_left.position = _center + Vector3(-half, 0, 0)
	_pivot_right.position = _center + Vector3(half, 0, 0)
	for slab in _slabs:
		_layout_ring(slab)
		(slab["node"] as Node3D).visible = false
		for piece in slab["ring"]:
			piece.visible = true
	_layout_liner()
	_tile_node.visible = false
	_pivot_left.visible = true
	_pivot_right.visible = true
	for wall in _liner:
		wall.visible = false  # revealed with the opening
	openness = 0.0
	_target = 0.0
	_active = true
	_pose()


func _layout_ring(slab: Dictionary) -> void:
	var node: MeshInstance3D = slab["node"]
	var size: Vector3 = (node.mesh as BoxMesh).size
	var c := node.position
	var h := W.TILE_SIZE * 0.5
	var x0 := c.x - size.x * 0.5
	var x1 := c.x + size.x * 0.5
	var z0 := c.z - size.z * 0.5
	var z1 := c.z + size.z * 0.5
	var rects := [
		Rect2(x0, z0, (_center.x - h) - x0, size.z),                         # left strip
		Rect2(_center.x + h, z0, x1 - (_center.x + h), size.z),              # right strip
		Rect2(_center.x - h, z0, 2.0 * h, (_center.z - h) - z0),             # near strip
		Rect2(_center.x - h, _center.z + h, 2.0 * h, z1 - (_center.z + h)),  # far strip
	]
	for i in 4:
		var r: Rect2 = rects[i]
		var piece: MeshInstance3D = slab["ring"][i]
		(piece.mesh as BoxMesh).size = Vector3(maxf(r.size.x, 0.001), size.y, maxf(r.size.y, 0.001))
		piece.position = Vector3(r.position.x + r.size.x * 0.5, c.y, r.position.y + r.size.y * 0.5)


func _layout_liner() -> void:
	if uses_shaft_asset:
		_liner[0].position = Vector3(_center.x, 0, _center.z)
		return
	var top := W.PLINTH_CENTER.y - W.PLINTH_SIZE.y * 0.5
	var length := W.BOARD_DEPTH + top - (W.CEILING_BOTTOM + W.CEILING_THICKNESS)
	var h := W.TILE_SIZE * 0.5
	var t := 0.06
	var cy := top - length * 0.5
	var specs := [
		[Vector3(t, length, W.TILE_SIZE + 2 * t), Vector3(_center.x - h - t * 0.5, cy, _center.z)],
		[Vector3(t, length, W.TILE_SIZE + 2 * t), Vector3(_center.x + h + t * 0.5, cy, _center.z)],
		[Vector3(W.TILE_SIZE, length, t), Vector3(_center.x, cy, _center.z - h - t * 0.5)],
		[Vector3(W.TILE_SIZE, length, t), Vector3(_center.x, cy, _center.z + h + t * 0.5)],
	]
	for i in 4:
		((_liner[i] as MeshInstance3D).mesh as BoxMesh).size = specs[i][0]
		_liner[i].position = specs[i][1]


func open(duration: float = W.TRAPDOOR_OPEN_TIME) -> void:
	_set_target(1.0, duration)


func close(duration: float = W.TRAPDOOR_CLOSE_TIME) -> void:
	_set_target(0.0, duration)


func _set_target(value: float, duration: float) -> void:
	if not _active:
		return
	_target = value
	_duration = maxf(0.0001, duration)
	if not animate:
		openness = value
		_pose()
		_arrived()


func advance(dt: float) -> void:
	if not _active or is_equal_approx(openness, _target):
		return
	var step := dt / _duration
	openness = move_toward(openness, _target, step)
	_pose()
	if is_equal_approx(openness, _target):
		_arrived()


func _arrived() -> void:
	if _target >= 1.0:
		opened.emit()
	else:
		closed.emit()


func _pose() -> void:
	if _pivot_left == null:
		return
	var angle := W.LEAF_OPEN_ANGLE * W.smooth(openness)
	_pivot_left.rotation = Vector3(0, 0, -angle)
	_pivot_right.rotation = Vector3(0, 0, angle)
	var reveal := openness > 0.001
	for wall in _liner:
		wall.visible = reveal
	changed.emit(openness)


## Closes at once (abort/recovery) and restores the original solid tile and slabs.
func snap_closed() -> void:
	if not _active:
		return
	openness = 0.0
	_target = 0.0
	_pose()
	finish()


## Restores the solid board. Only valid when closed (or from snap_closed()).
func finish() -> void:
	if not _active:
		return
	if _tile_node != null:
		_tile_node.visible = true
	for slab in _slabs:
		(slab["node"] as Node3D).visible = true
		for piece in slab["ring"]:
			piece.visible = false
	if _pivot_left != null:
		_pivot_left.visible = false
		_pivot_right.visible = false
	for wall in _liner:
		wall.visible = false
	_active = false
	tile = -1
	changed.emit(0.0)
