class_name PitChamber
extends Node3D
## The underground side of the pit world, at the world origin (the combat simulation's own frame):
## stone ceiling slab with the 1 m hole, the warm light shaft, the lowerable ladder and the mount
## point where the CombatArena is parented. Procedural boxes/cylinders only; an optional ladder GLB
## from res://assets/world/ is used when present. Built once, hidden while no battle runs.

const W := preload("res://world/world_constants.gd")
const Models := preload("res://boards/piece_meshes.gd")
const LADDER_TOP := "res://assets/world/pit/ladder_top.glb"
const LADDER_SEGMENT := "res://assets/world/pit/ladder_segment_2m.glb"
const CAMERA_COLLISION_LAYER := 4  # CombatConstants.LAYER_CAMERA

signal arena_mounted(arena: Node)

var arena_mount: Node3D
var ladder: Node3D
var spot: SpotLight3D
var cones: Array[MeshInstance3D] = []
var uses_ladder_asset := false
## When true (default) the arena's physics tick is paused on mount; the pit releases it at DROP.
var gate_simulation := true
var quality := "high"
var _built := false
var _cone_materials: Array[StandardMaterial3D] = []
var _ladder_deploy := 0.0
var _hole_center := Vector3.ZERO


func _init() -> void:
	name = "PitChamber"
	visible = false
	arena_mount = Node3D.new()
	arena_mount.name = "ArenaMount"
	add_child(arena_mount)
	arena_mount.child_entered_tree.connect(_on_mount_child)


## Heavy props are built on first use (first battle), not when the board is created.
func build() -> void:
	if _built:
		return
	_built = true
	_build_ceiling()
	_build_backdrop()
	_build_light_shaft()
	_build_ladder()


func activate() -> void:
	build()
	visible = true
	set_light_shaft(0.0)
	set_ladder(0.0)


func deactivate() -> void:
	set_light_shaft(0.0)
	set_ladder(0.0)
	visible = false


static var _stone_cache: StandardMaterial3D = null


func _stone() -> StandardMaterial3D:
	if _stone_cache != null:
		return _stone_cache
	var tex := StoneArenaVisuals.stone_texture(7, Color(0.30, 0.29, 0.27))
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.albedo_color = Color(0.9, 0.88, 0.85)
	mat.roughness = 0.95
	mat.uv1_scale = Vector3(3, 3, 3)
	mat.uv1_triplanar = true
	_stone_cache = mat
	return mat


func _build_ceiling() -> void:
	var holder := Node3D.new()
	holder.name = "Ceiling"
	add_child(holder)
	var body := StaticBody3D.new()
	body.name = "CeilingCollider"
	body.collision_layer = CAMERA_COLLISION_LAYER
	body.collision_mask = 0
	holder.add_child(body)
	var mat := _stone()
	var h := W.HOLE_HALF
	var e := W.CEILING_HALF
	var y := W.CEILING_BOTTOM + W.CEILING_THICKNESS * 0.5
	var t := W.CEILING_THICKNESS
	var rects := [Rect2(-e, -e, e - h, 2 * e), Rect2(h, -e, e - h, 2 * e), Rect2(-h, -e, 2 * h, e - h), Rect2(-h, h, 2 * h, e - h)]
	for r in rects:
		var piece := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(r.size.x, t, r.size.y)
		piece.mesh = mesh
		piece.material_override = mat
		piece.position = Vector3(r.position.x + r.size.x * 0.5, y, r.position.y + r.size.y * 0.5)
		piece.layers = W.LAYER_CEILING
		holder.add_child(piece)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = mesh.size
		shape.shape = box
		shape.position = piece.position
		body.add_child(shape)


## Dark band that closes the gap between the arena wall top and the ceiling slab.
func _build_backdrop() -> void:
	var band := MeshInstance3D.new()
	band.name = "Backdrop"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 7.7
	mesh.bottom_radius = 7.7
	mesh.height = W.CEILING_BOTTOM
	mesh.radial_segments = 24
	mesh.rings = 1
	mesh.cap_top = false
	mesh.cap_bottom = false
	band.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.09, 0.075, 0.065)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	band.material_override = mat
	band.position = Vector3(0, W.CEILING_BOTTOM * 0.5, 0)
	band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(band)


func _build_light_shaft() -> void:
	spot = SpotLight3D.new()
	spot.name = "ShaftLight"
	spot.position = Vector3(0, W.BOARD_DEPTH - 0.1, 0)
	spot.rotation_degrees = Vector3(-90, 0, 0)
	spot.light_color = Color(1.0, 0.84, 0.55)
	spot.light_energy = 0.0
	spot.spot_range = W.BOARD_DEPTH + 1.0
	spot.spot_angle = 17.0
	spot.spot_attenuation = 0.6
	spot.light_cull_mask = W.LAYER_CHAMBER | W.LAYER_BOARD
	add_child(spot)
	var radii := [[0.42, 1.25, 0.10], [0.30, 0.8, 0.07]]
	for r in radii:
		var cone := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = r[0]
		mesh.bottom_radius = r[1]
		mesh.height = W.BOARD_DEPTH
		mesh.radial_segments = 20
		mesh.rings = 1
		cone.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.albedo_color = Color(1.0, 0.82, 0.5, 0.0)
		cone.material_override = mat
		cone.position = Vector3(0, W.BOARD_DEPTH * 0.5, 0)
		cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cone.set_meta("max_alpha", r[2])
		add_child(cone)
		cones.append(cone)
		_cone_materials.append(mat)


## 0 = dark shaft, 1 = full warm beam (tied to the trapdoor's openness).
func set_light_shaft(amount: float) -> void:
	if spot == null:
		return
	var a := clampf(amount, 0.0, 1.0)
	spot.light_energy = 2.0 * a
	spot.visible = a > 0.001
	for i in cones.size():
		_cone_materials[i].albedo_color.a = float(cones[i].get_meta("max_alpha")) * a
		cones[i].visible = a > 0.001


func apply_quality(value: String) -> void:
	quality = value
	if spot != null:
		spot.shadow_enabled = false


func _build_ladder() -> void:
	ladder = Node3D.new()
	ladder.name = "Ladder"
	# Origin = the board tile mid-plane above the hole, offset to the shaft's back wall.
	ladder.position = Vector3(0, W.BOARD_DEPTH, W.LADDER_Z)
	add_child(ladder)
	uses_ladder_asset = _build_ladder_asset()
	if not uses_ladder_asset:
		var wood := Models.material(Color("6a4d30"))
		var iron := Models.material(Color("3b3c40"), 0.6)
		var length := W.BOARD_DEPTH
		for side in [-1, 1]:
			Models.box(ladder, Vector3(0.05, length, 0.05), Vector3(side * W.LADDER_HALF_WIDTH, -length * 0.5, 0), wood)
		var y := 0.25
		while y < length - 0.1:
			Models.box(ladder, Vector3(W.LADDER_HALF_WIDTH * 2, 0.035, 0.035), Vector3(0, -y, 0), iron)
			y += 0.25
	ladder.visible = false


## Generated ladder set (godot/assets/world/pit/): the top section (y -1..+0.75 around the rim) plus
## 2 m segments stacked downwards until the foot is within a few cm of the arena floor.
func _build_ladder_asset() -> bool:
	if not (ResourceLoader.exists(LADDER_TOP) and ResourceLoader.exists(LADDER_SEGMENT)):
		return false
	var top = load(LADDER_TOP)
	var segment = load(LADDER_SEGMENT)
	if not (top is PackedScene and segment is PackedScene):
		return false
	ladder.add_child(top.instantiate())
	var bottom := -1.0
	while bottom > -(W.BOARD_DEPTH + 0.04) + 0.05:
		var part: Node3D = segment.instantiate()
		part.position = Vector3(0, bottom - 2.0, 0)
		ladder.add_child(part)
		bottom -= 2.0
	return true


## 0 = stowed in the shaft, 1 = hanging to the floor. Unrolls downwards from the rim.
func set_ladder(amount: float) -> void:
	if ladder == null:
		return
	_ladder_deploy = clampf(amount, 0.0, 1.0)
	ladder.visible = _ladder_deploy > 0.001
	ladder.scale = Vector3(1, maxf(_ladder_deploy, 0.001), 1)


func ladder_deploy() -> float:
	return _ladder_deploy


## World position of the climber's feet at height y on the ladder.
func climb_position(y: float) -> Vector3:
	return Vector3(0.0, y, W.LADDER_Z - 0.42)


func _on_mount_child(node: Node) -> void:
	if node.get("embedded") != null:
		node.set("embedded", true)
	if gate_simulation:
		# Node._ready() re-enables processing for scripts that define _physics_process, so the pause is
		# applied when the battle starts (add_child and start_battle happen in the same call stack, before
		# the next physics tick) and right away for arenas that are already running.
		if node.has_signal("battle_started"):
			node.connect("battle_started", func(_request: Dictionary): _gate(node))
		_gate(node)
	arena_mounted.emit(node)


func _gate(node: Node) -> void:
	if is_instance_valid(node) and node.has_method("set_physics_process"):
		node.set_physics_process(false)
