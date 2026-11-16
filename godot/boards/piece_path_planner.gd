class_name PiecePathPlanner
extends RefCounted
## Walking routes on the 3D board that go AROUND the other pieces. Squares are 1 m apart (BoardInteraction.world_position);
## a piece's footprint is a circle of FOOTPRINT metres around its square's centre. A move walks straight when that is clear;
## otherwise it follows the shortest route over the start, the goal and the 81 tile corners (the grid lines are 0.5 m from every
## square centre, so they are always free). Deterministic: ties break on node index. Knights keep their L path elsewhere.

const FOOTPRINT := 0.42
const HALF := 4.0   # the corner grid spans -4..4 on both axes


static func _segment_distance(a: Vector2, b: Vector2, p: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.000001:
		return a.distance_to(p)
	return (a + ab * clampf((p - a).dot(ab) / len2, 0.0, 1.0)).distance_to(p)


static func _clear(a: Vector2, b: Vector2, blockers: Array) -> bool:
	for center in blockers:
		if _segment_distance(a, b, center) < FOOTPRINT:
			return false
	return true


## `blockers`: world positions (Vector3, y ignored) of the squares holding other pieces. Returns the waypoints after `from`, ending exactly on `to`
## (y of `from` is kept on every waypoint).
static func plan(from: Vector3, to: Vector3, blockers: Array) -> Array[Vector3]:
	var path: Array[Vector3] = [to]
	var flat: Array = []
	for b in blockers:
		var v := Vector2(b.x, b.z)
		if v.distance_to(Vector2(from.x, from.z)) > 0.01 and v.distance_to(Vector2(to.x, to.z)) > 0.01:
			flat.append(v)
	var a := Vector2(from.x, from.z)
	var g := Vector2(to.x, to.z)
	if flat.is_empty() or _clear(a, g, flat):
		return path
	var nodes: Array[Vector2] = [a, g]
	for ix in range(-4, 5):
		for iz in range(-4, 5):
			nodes.append(Vector2(ix, iz))
	var count := nodes.size()
	var dist := PackedFloat64Array()
	dist.resize(count)
	dist.fill(INF)
	var prev := PackedInt32Array()
	prev.resize(count)
	prev.fill(-1)
	var done := PackedByteArray()
	done.resize(count)
	dist[0] = 0.0
	for _step in count:
		var u := -1
		var best := INF
		for i in count:
			if done[i] == 0 and dist[i] < best:
				best = dist[i]
				u = i
		if u < 0 or u == 1:
			break
		done[u] = 1
		for v in count:
			if done[v] == 1 or v == u:
				continue
			var d := nodes[u].distance_to(nodes[v])
			if d > 3.0 and u != 0 and v != 1 and u != 1:
				continue   # corner-to-corner hops stay local: keeps the graph small and the route tidy
			if dist[u] + d < dist[v] - 0.000001 and _clear(nodes[u], nodes[v], flat):
				dist[v] = dist[u] + d
				prev[v] = u
	if prev[1] < 0:
		return path   # no free route (cannot happen on an 8x8 board with the footprint below 0.5): fall back to straight
	var chain: Array[int] = []
	var at := 1
	while at != 0 and at >= 0:
		chain.push_front(at)
		at = prev[at]
	var out: Array[Vector3] = []
	for i in chain:
		out.append(Vector3(nodes[i].x, from.y, nodes[i].y) if i != 1 else to)
	return out
