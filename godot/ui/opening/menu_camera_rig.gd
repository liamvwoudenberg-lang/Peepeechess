class_name MenuCameraRig
extends RefCounted
## The camera of the cinematic menu. It rests at a named station (menu_stations.gd) and flies between stations along a Catmull-Rom path
## through authored waypoints, easing in and out. Pure maths + a clock: the owner (OpeningScene._process or a test) calls advance().
##
## Flight length (owner decision 2026-11-17): the FIRST flight into each station in a session is long (LONG_FLIGHT, with fly-past beats:
## the look target glances at the station's beats on the way), every later flight into it is SHORT_FLIGHT. Reduce-motion replaces any
## flight by a REDUCED_FLIGHT crossfade (no spline, no roll). Tests use the instant mode (no flights at all).
signal flight_started(station_id: String, duration: float)
signal arrived(station_id: String)

const LONG_FLIGHT := 2.5
const SHORT_FLIGHT := 1.0
const REDUCED_FLIGHT := 0.15
const MAX_ROLL := 0.035
const FOV_SWOOSH := 5.0

## -1: automatic (instant when headless, so existing tests keep their instant page swaps); 0: always fly; 1: always instant.
static var instant_override := -1

var pos := Vector3.ZERO
var look := Vector3.ZERO
var fov := 55.0
var roll := 0.0
var current_id := ""        ## the station the camera rests at, or the station it is flying to
var origin_id := ""         ## the station the current/last flight started from
var active := false         ## the rig owns the camera (false while the opening screen still drives it)
var flying := false
var reduced_motion := false
var visited := {}           ## station id -> true once the camera has flown (or been placed) there
var history: Array[String] = []

var _pts: Array = []        ## position control points of the flight
var _looks: Array = []      ## look control points of the flight
var _from_fov := 55.0
var _to_fov := 55.0
var _t := 0.0
var _duration := 0.0
var _roll_sign := 1.0
var _reduced_flight := false

static func is_instant() -> bool:
	if instant_override >= 0:
		return instant_override == 1
	return DisplayServer.get_name() == "headless"

## Rest at `id` at once (no flight).
func place(id: String) -> void:
	var s := MenuStations.station(id)
	pos = s.pos
	look = s.look
	fov = float(s.fov)
	roll = 0.0
	current_id = id
	origin_id = id
	flying = false
	visited[id] = true
	active = true

## Duration the next flight to `id` would take from now.
func flight_time(id: String, reduced: bool = false) -> float:
	if is_instant():
		return 0.0
	if reduced or reduced_motion:
		return REDUCED_FLIGHT
	return SHORT_FLIGHT if visited.has(id) else LONG_FLIGHT

## Start a flight to `id` from wherever the camera is now (also while another flight runs: it retargets smoothly from the current pose).
## Returns the duration in seconds (0.0 when the camera simply arrived or is already there).
func fly_to(id: String, reduced: bool = false) -> float:
	if not MenuStations.STATIONS.has(id):
		return 0.0
	if id == current_id:
		return 0.0
	var from_id := current_id
	if from_id != "":
		history.append(from_id)
		if history.size() > 24:
			history.pop_front()
	var duration := flight_time(id, reduced)
	var target := MenuStations.station(id)
	origin_id = from_id if from_id != "" else id
	if duration <= 0.0:
		place(id)
		origin_id = from_id if from_id != "" else id
		arrived.emit(id)
		return 0.0
	_reduced_flight = reduced or reduced_motion
	_from_fov = fov
	_to_fov = float(target.fov)
	_t = 0.0
	_duration = duration
	var first_visit := not visited.has(id)
	current_id = id
	flying = true
	active = true
	if _reduced_flight:
		_pts = [pos, target.pos]
		_looks = [look, target.look]
	else:
		var path: Array = [pos]
		path.append_array(MenuStations.via(from_id if from_id != "" else id, id))
		path.append(target.pos)
		_pts = path
		var glances: Array = [look]
		if first_visit:
			glances.append_array(target.beats)   # fly-past beats only on the long first flight
		glances.append(target.look)
		_looks = glances
	_roll_sign = 1.0 if (target.pos.x + target.pos.z) >= (pos.x + pos.z) else -1.0
	flight_started.emit(id, duration)
	return duration

## Go back to the station the camera came from (the last flight is reversed). False when there is nowhere to go back to.
func back() -> bool:
	if history.is_empty():
		return false
	var id: String = history.pop_back()
	var keep := history.duplicate()
	fly_to(id)
	history = keep   # going back must not push the place we leave onto the history
	return true

## Jump to the end of the running flight.
func skip() -> void:
	if not flying:
		return
	var id := current_id
	var from := origin_id
	place(id)
	origin_id = from
	arrived.emit(id)

func progress() -> float:
	return clampf(_t / _duration, 0.0, 1.0) if flying and _duration > 0.0 else 1.0

func advance(delta: float) -> void:
	if not flying:
		return
	_t += delta
	var s := clampf(_t / _duration, 0.0, 1.0)
	var e := s * s * s * (s * (s * 6.0 - 15.0) + 10.0)   # smootherstep: zero velocity and acceleration at both ends
	if _reduced_flight:
		if s >= 0.5:
			var target := MenuStations.station(current_id)
			pos = target.pos
			look = target.look
			fov = float(target.fov)
		roll = 0.0
	else:
		pos = _spline(_pts, e)
		look = _spline(_looks, e)
		fov = lerpf(_from_fov, _to_fov, e) + FOV_SWOOSH * sin(PI * e)
		roll = _roll_sign * MAX_ROLL * sin(PI * e)
	if s >= 1.0:
		var id := current_id
		var from := origin_id
		place(id)
		origin_id = from
		arrived.emit(id)

## Camera transform for the pose (looking along `look - pos`, rolled).
func pose_basis() -> Basis:
	var dir := (look - pos)
	if dir.length() < 0.001:
		dir = Vector3(0, 0, -1)
	var basis := Basis.looking_at(dir.normalized(), Vector3.UP)
	return basis * Basis(Vector3.BACK, roll)

## Catmull-Rom through `points` (parameter 0..1 over the whole list).
static func _spline(points: Array, t: float) -> Vector3:
	var n := points.size()
	if n == 1:
		return points[0]
	var segs := n - 1
	var f := clampf(t, 0.0, 1.0) * segs
	var i := mini(int(floor(f)), segs - 1)
	var u := f - i
	var p0: Vector3 = points[maxi(i - 1, 0)]
	var p1: Vector3 = points[i]
	var p2: Vector3 = points[i + 1]
	var p3: Vector3 = points[mini(i + 2, segs)]
	var u2 := u * u
	var u3 := u2 * u
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u3)
