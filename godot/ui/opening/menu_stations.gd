class_name MenuStations
extends RefCounted
## Data for the cinematic menu (docs/ui/CINEMATIC_MENU.md): where the camera rests for each page, the authored way between
## neighbouring stations, and where each station's paladin and props stand. Pure data, no nodes.
##
## World (see castle_builder.gd): metres, +Y up, the gate is at z = +4, the chequered bridge runs out toward +Z (outside the walls),
## the courtyard board (32 x 32 m, y = 0.16) lies behind the gate, the keep closes it at z = -42.
## One night look everywhere (owner decision 2026-11-17): stations differ by place and camera, never by time of day.

## Station ids, in a stable order.
const IDS := ["home", "hall", "yard", "warroom", "gallery", "archive", "tower", "armoury", "exterior"]

## Page -> station. Online play (the Play page with `online`) and Friends/Account are OUTSIDE the walls.
const PAGE_STATION := {
	"home": "home", "play": "hall", "training": "yard", "campaign": "warroom", "profile": "gallery",
	"history": "archive", "leaderboard": "tower", "settings": "armoury", "friends": "exterior", "account": "exterior",
}

## pos / look: camera. fov: vertical degrees on landscape windows. ground: y of the floor under the paladin and props.
## paladin: {role, side, fwd, left, scale} placed relative to the camera (fwd metres along its view on the ground plane, left metres to
## its left), facing the camera, so it always stands on the open "stage" side of the page frame. beats: where the camera glances during
## the long first flight into the station.
const STATIONS := {
	"home": {"pos": Vector3(-24.0, 9.5, -5.0), "look": Vector3(7.0, 12.0, -40.0), "fov": 55.0, "ground": 0.16,
		"paladin": {"role": "king", "side": "light", "fwd": 15.0, "left": 5.5, "scale": 3.2}, "beats": []},
	"hall": {"pos": Vector3(-14.0, 4.0, -4.0), "look": Vector3(2.0, 3.0, -24.0), "fov": 58.0, "ground": 0.16,
		"paladin": {"role": "knight", "side": "light", "fwd": 8.5, "left": 4.4, "scale": 2.7},
		"beats": [Vector3(-30.0, 9.0, -14.0)]},
	"yard": {"pos": Vector3(12.0, 4.0, -8.0), "look": Vector3(-8.0, 3.0, -26.0), "fov": 58.0, "ground": 0.16,
		"paladin": {"role": "pawn", "side": "light", "fwd": 8.0, "left": 3.2, "scale": 2.6},
		"beats": [Vector3(30.0, 6.0, -20.0)]},
	"warroom": {"pos": Vector3(0.0, 17.0, -13.0), "look": Vector3(0.0, 0.0, -27.0), "fov": 62.0, "ground": 0.16,
		"paladin": {"role": "queen", "side": "dark", "fwd": 15.0, "left": 6.0, "scale": 3.0},
		"beats": []},
	"gallery": {"pos": Vector3(-26.0, 5.0, -22.0), "look": Vector3(0.0, 6.0, -24.0), "fov": 56.0, "ground": 0.16,
		"paladin": {"role": "bishop", "side": "light", "fwd": 9.0, "left": 3.4, "scale": 2.7},
		"beats": [Vector3(-33.0, 9.0, -12.0)]},
	"archive": {"pos": Vector3(26.0, 5.0, -34.0), "look": Vector3(0.0, 5.0, -20.0), "fov": 56.0, "ground": 0.16,
		"paladin": {"role": "rook", "side": "dark", "fwd": 9.0, "left": 3.4, "scale": 2.7},
		"beats": []},
	"tower": {"pos": Vector3(0.0, 22.0, -31.0), "look": Vector3(0.0, 9.0, -46.0), "fov": 60.0, "ground": 0.16,
		"paladin": {"role": "king", "side": "dark", "fwd": 16.0, "left": 6.0, "scale": 3.4},
		"beats": [Vector3(0.0, 14.0, -44.0)]},
	"armoury": {"pos": Vector3(21.0, 4.5, -12.0), "look": Vector3(33.0, 5.0, -30.0), "fov": 56.0, "ground": 0.16,
		"paladin": {"role": "rook", "side": "light", "fwd": 8.0, "left": 3.0, "scale": 2.7},
		"beats": [Vector3(20.0, 9.0, -44.0)]},
	"exterior": {"pos": Vector3(3.0, 3.4, 46.0), "look": Vector3(-1.0, 5.5, 8.0), "fov": 56.0, "ground": 0.0,
		"paladin": {"role": "knight", "side": "dark", "fwd": 8.0, "left": 1.9, "scale": 2.6},
		"beats": [Vector3(-10.5, 9.0, 17.0), Vector3(10.5, 9.0, 17.0)]},
}

## Authored ways between neighbouring stations (positions the camera passes through, in order from the first id to the second).
## Pairs that are not listed use an automatic gentle arc; any flight to or from the exterior passes through the gate (GATE_PASS).
const VIA := {
	"home>hall": [Vector3(-19.0, 6.5, -4.5)],
	"home>exterior": [Vector3(-8.0, 6.0, -8.0), Vector3(0.0, 4.2, 2.0), Vector3(0.0, 3.6, 26.0)],
	"hall>exterior": [Vector3(-7.0, 4.4, -1.5), Vector3(0.0, 4.0, 4.0), Vector3(0.0, 3.6, 26.0)],
}
const GATE_PASS := [Vector3(0.0, 4.0, 3.0), Vector3(0.0, 3.6, 24.0)]   ## inside -> outside order

static func station(id: String) -> Dictionary:
	return STATIONS.get(id, STATIONS["home"])

static func station_for_page(page: String, online: bool = false) -> String:
	if page == "play" and online:
		return "exterior"
	return PAGE_STATION.get(page, "hall")

static func is_exterior(id: String) -> bool:
	return id == "exterior"

## Waypoints the camera passes through between two stations (excluding both ends), in travel order.
static func via(from_id: String, to_id: String) -> Array:
	var key := from_id + ">" + to_id
	if VIA.has(key):
		return (VIA[key] as Array).duplicate()
	var reverse := to_id + ">" + from_id
	if VIA.has(reverse):
		var list: Array = (VIA[reverse] as Array).duplicate()
		list.reverse()
		return list
	var outside_from := is_exterior(from_id)
	var outside_to := is_exterior(to_id)
	if outside_from != outside_to:
		var gate: Array = GATE_PASS.duplicate()
		if outside_from:
			gate.reverse()
		return gate
	var a: Vector3 = station(from_id).pos
	var b: Vector3 = station(to_id).pos
	return [(a + b) * 0.5 + Vector3(0.0, 0.12 * a.distance_to(b) + 1.0, 0.0)]

## Where a station's paladin stands: `fwd` metres along the camera's ground-plane view direction and `left` metres to its left.
static func paladin_position(id: String) -> Vector3:
	var s := station(id)
	var spec: Dictionary = s.paladin
	var pos: Vector3 = s.pos
	var look: Vector3 = s.look
	var forward := Vector3(look.x - pos.x, 0.0, look.z - pos.z)
	if forward.length() < 0.01:
		forward = Vector3(0, 0, -1)
	forward = forward.normalized()
	var left := Vector3(forward.z, 0.0, -forward.x)   # the camera's left on the ground plane (right = forward x up = (-fz, 0, fx))
	var p := pos + forward * float(spec.fwd) + left * float(spec.left)
	return Vector3(p.x, float(s.ground), p.z)

## Yaw that turns a model facing +Z toward `target` (ground plane).
static func yaw_toward(from: Vector3, target: Vector3) -> float:
	return atan2(target.x - from.x, target.z - from.z)
