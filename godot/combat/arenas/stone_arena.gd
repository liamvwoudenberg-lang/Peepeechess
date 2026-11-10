class_name StoneArena
extends Node3D
## Arena "stone-v1". build_colliders() creates only static collision (walls and pillars) and is
## what the headless authority uses. Visuals are added separately by the presentation layer
## (see stone_arena_visuals.gd) so a dedicated server needs no meshes or materials.
##
## Layout (metres, +Y up): flat floor at y=0; circular wall whose inner face is at radius
## ARENA_WALL_RADIUS; four pillars on the diagonals. White spawns at z=-2.6, Black at z=+2.6.

const PILLAR_POSITIONS: Array[Vector3] = [
	Vector3(3.4, 0.0, 3.4), Vector3(-3.4, 0.0, 3.4), Vector3(3.4, 0.0, -3.4), Vector3(-3.4, 0.0, -3.4),
]
const PILLAR_RADIUS := 0.55
const WALL_SEGMENTS := 24
const WALL_HEIGHT := 3.0
const WALL_THICKNESS := 0.6

var colliders: StaticBody3D = null
var pillar_body: StaticBody3D = null


func build_colliders() -> void:
	colliders = StaticBody3D.new()
	colliders.name = "WorldColliders"
	colliders.collision_layer = CombatConstants.LAYER_WORLD | CombatConstants.LAYER_CAMERA
	colliders.collision_mask = 0
	add_child(colliders)

	var apothem := CombatConstants.ARENA_WALL_RADIUS
	# Slightly longer than the polygon side so neighbouring boxes overlap with no gaps.
	var segment_length := 2.0 * apothem * tan(PI / float(WALL_SEGMENTS)) * 1.1
	for i in WALL_SEGMENTS:
		var angle := TAU * float(i) / float(WALL_SEGMENTS)
		var outward := Vector3(sin(angle), 0.0, cos(angle))
		var box := BoxShape3D.new()
		box.size = Vector3(segment_length, WALL_HEIGHT, WALL_THICKNESS)
		var shape := CollisionShape3D.new()
		shape.shape = box
		shape.position = outward * (apothem + WALL_THICKNESS * 0.5) + Vector3(0.0, WALL_HEIGHT * 0.5, 0.0)
		shape.rotation.y = angle  # local +Z maps onto the outward normal
		colliders.add_child(shape)

	pillar_body = StaticBody3D.new()
	pillar_body.name = "PillarColliders"
	pillar_body.collision_layer = CombatConstants.LAYER_WORLD
	pillar_body.collision_mask = 0
	add_child(pillar_body)
	for pos in PILLAR_POSITIONS:
		var cylinder := CylinderShape3D.new()
		cylinder.radius = PILLAR_RADIUS
		cylinder.height = 3.5
		var pillar := CollisionShape3D.new()
		pillar.shape = cylinder
		pillar.position = pos + Vector3(0.0, 1.75, 0.0)
		pillar_body.add_child(pillar)
