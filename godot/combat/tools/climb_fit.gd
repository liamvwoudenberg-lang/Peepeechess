extends RefCounted
## Where is the climbing fighter relative to the 1 m opening it climbs through? Shared by the climb audit tool
## (res://combat/tools/climb_audit.gd) and the pit_climb test so both measure exactly the same thing.
## A fighter is sampled in world space: every skeleton bone (optionally padded by a radius, a limb is not a point) and the
## 8 corners of every visible prop mesh (weapon, shield). Skinned body meshes are covered by their bones.
const W := preload("res://world/world_constants.gd")

## Vertical bands (world y) where the opening is a hard edge: the chamber ceiling slab with its underside coffer beams, and the
## board slab around the open trapdoor. Outside these bands nothing surrounds the climber. The board band ends at the TILE TOP
## (BOARD_DEPTH + TILE_THICKNESS / 2 = 7.04): on the last step the winner puts a foot on the neighbouring tile, up to 0.3 m past
## the opening's edge, and a point above the surface is standing on it, not inside it.
const BANDS := {
	"ceiling": [4.66, 5.6],
	"board": [6.5, 7.04],
}


## [[point: Vector3, radius: float, label: String], ...]
static func samples(visual: Node3D, bone_radius: float) -> Array:
	var points: Array = []
	for skeleton in visual.find_children("*", "Skeleton3D", true, false):
		for i in skeleton.get_bone_count():
			points.append([skeleton.global_transform * skeleton.get_bone_global_pose(i).origin, bone_radius, "bone " + skeleton.get_bone_name(i)])
	for mesh in visual.find_children("*", "MeshInstance3D", true, false):
		if not mesh.is_visible_in_tree() or mesh.mesh == null or mesh.skin != null:
			continue  # hidden, or a skinned body mesh (covered by its bones); what remains are props on sockets
		var box: AABB = mesh.get_aabb()
		for corner in 8:
			points.append([mesh.global_transform * box.get_endpoint(corner), 0.0, "prop %s (under %s)" % [mesh.name, mesh.get_parent().name]])
	return points


## How far the samples that are level with `band` reach outside the opening (metres; <= 0 means inside): across it ("width", x)
## and front-to-back ("depth", z), plus what reached furthest.
static func overshoot(points: Array, band: String) -> Dictionary:
	var low: float = BANDS[band][0]
	var high: float = BANDS[band][1]
	var result := {"width": -INF, "depth": -INF, "width_item": "", "depth_item": "", "width_at": Vector3.ZERO, "depth_at": Vector3.ZERO}
	for sample in points:
		var p: Vector3 = sample[0]
		if p.y < low or p.y > high:
			continue
		var over_x := absf(p.x) + float(sample[1]) - W.HOLE_HALF
		var over_z := absf(p.z) + float(sample[1]) - W.HOLE_HALF
		if over_x > result["width"]:
			result["width"] = over_x
			result["width_item"] = sample[2]
			result["width_at"] = p
		if over_z > result["depth"]:
			result["depth"] = over_z
			result["depth_item"] = sample[2]
			result["depth_at"] = p
	return result
