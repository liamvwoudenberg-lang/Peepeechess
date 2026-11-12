class_name PitSequence
extends Node
## Explicit presentation state machine for one capture:
##
##   IDLE -> CAPTURE_FOCUS -> TRAPDOOR_OPEN -> DROP -> COMBAT -> RESOLVE -> CLIMB -> RETURN -> IDLE
##
## It only PRESENTS. The winner is whatever the combat authority's BattleResult says
## (present_result); the sequence never inspects HP, never submits input and never touches the chess
## match. All motion is derived from advance(dt), so tests step it deterministically.
##
## External contract (wired by WorldBattleBridge, godot/world/battle_bridge.gd):
##   begin(request)            start CAPTURE_FOCUS (request = the frozen BattleRequest)
##   attach_arena(arena)       the arena is mounted + started (paused by PitChamber until DROP)
##   present_result(result)    the authoritative BattleResult (applied to visuals only)
##   abort(reason)             any phase -> consistent top-down world, no orphan nodes
## Signals: phase_changed, drop_started, combat_started, return_ready (winner is back on its tile:
## the bridge may now commit the chess result and stop the arena), finished, aborted.

# INTERLUDE is appended last (king's last stand, see the marked block at the end of this file): between two duels of one
# multi-duel sequence the pit stays in the chamber. Single captures never enter it, so the order above is unchanged.
enum Phase { IDLE, CAPTURE_FOCUS, TRAPDOOR_OPEN, DROP, COMBAT, RESOLVE, CLIMB, RETURN, INTERLUDE }
const PHASE_NAMES: Array[String] = ["IDLE", "CAPTURE_FOCUS", "TRAPDOOR_OPEN", "DROP", "COMBAT", "RESOLVE", "CLIMB", "RETURN", "INTERLUDE"]
const W := preload("res://world/world_constants.gd")
const Interaction := preload("res://boards/board_interaction.gd")
const Rules := preload("res://chess/chess_engine.gd")
const ARENA_WAIT_TIMEOUT := 20.0

signal phase_changed(phase: int)
signal drop_started
signal combat_started
signal return_ready
signal finished
signal aborted(reason: String)

var world: BattleWorld
var phase: int = Phase.IDLE
## false = do not wait for / require a CombatArena (timing-only tests, previews).
var require_arena := true
var arena: Node = null

var _time := 0.0
var _request: Dictionary = {}
var _tile := -1
var _tile_center := Vector3.ZERO
var _nodes: Array = []          # [attacker piece node, defender piece node]
var _colors: Array = []         # ["w"/"b", ...]
var _origin_local: Array = []   # original board-local positions
var _origin_rot: Array = []     # original y rotations
var _result: Dictionary = {}
var _winner_index := -1         # 0 attacker / 1 defender, from the authoritative result
var _landed := false
var _return_morphed := false
var _return_ready_sent := false
var _trapdoor_closing := false
var _climb := {}
var _dissolve_started := false
var _loser_detached := false
var _winner_visual: Node3D = null
var _loser_visual: Node3D = null


func setup(p_world: BattleWorld) -> void:
	world = p_world


static func phase_name(value: int) -> String:
	return PHASE_NAMES[value]


func is_idle() -> bool:
	return phase == Phase.IDLE


func request() -> Dictionary:
	return _request


func winner_index() -> int:
	return _winner_index


# ---- lifecycle ----------------------------------------------------------------------------------
## Returns false (and does nothing) when a sequence is already running or the pieces are missing.
func begin(battle_request: Dictionary) -> bool:
	if phase != Phase.IDLE or world == null or not world.can_present():
		return false
	var attacker: Dictionary = battle_request["attacker"]
	var defender: Dictionary = battle_request["defender"]
	var a_node: Node3D = world.piece_node(String(attacker["pieceId"]))
	var d_node: Node3D = world.piece_node(String(defender["pieceId"]))
	if a_node == null or d_node == null:
		return false
	_request = battle_request.duplicate(true)
	_nodes = [a_node, d_node]
	_colors = [String(attacker["color"]), String(defender["color"])]
	_tile = Rules.index(String(defender["square"]))
	_tile_center = Interaction.world_position(_tile)
	_origin_local = [a_node.position, d_node.position]
	_origin_rot = [a_node.rotation.y, d_node.rotation.y]
	_result = {}
	_winner_index = -1
	_landed = false
	_return_morphed = false
	_return_ready_sent = false
	_trapdoor_closing = false
	_dissolve_started = false
	_loser_detached = false
	_climb = {}
	_winner_visual = null
	_loser_visual = null
	arena = null
	world.hold_board(true)
	world.apply_shift(_tile_center)
	world.trapdoor.begin(_tile, _tile_center)
	world.rig.focus_tile = _tile_center
	world.rig.go(CameraRig.State.CAPTURE_FOCUS, W.CAPTURE_FOCUS_TIME)
	_enter(Phase.CAPTURE_FOCUS)
	return true


func attach_arena(node: Node) -> void:
	arena = node
	if node != null and not node.tree_exiting.is_connected(_arena_gone):
		node.tree_exiting.connect(_arena_gone.bind(node))
	_set_arena_overlays(false)
	_set_fighters_visible(false)
	if world != null and world.rig != null:
		world.rig.camera.make_current()


func _arena_gone(node: Node) -> void:
	if arena == node:
		arena = null


## The authoritative result. Only selects which fighter climbs out; never decides anything.
func present_result(result: Dictionary) -> void:
	if phase == Phase.IDLE or not _result.is_empty():
		return
	var outcome := String(result.get("outcome", ""))
	if outcome != "attacker" and outcome != "defender":
		return
	_result = result.duplicate(true)
	_winner_index = 0 if outcome == "attacker" else 1
	if phase == Phase.COMBAT:
		_begin_resolve()


func abort(reason: String = "aborted") -> void:
	if phase == Phase.IDLE:
		return
	var below_board := world.rig.camera.position.y < world.rig.origin.y - 0.5
	for visual in [_winner_visual, _loser_visual]:
		if visual != null and is_instance_valid(visual) and visual.get_parent() == world.chamber:
			visual.queue_free()
	_winner_visual = null
	_loser_visual = null
	world.restore_after_battle(_entries(), false)
	world.rig.recover(0.0 if below_board else W.RECOVER_TIME)
	arena = null
	_request = {}
	_result = {}
	_winner_index = -1
	_nodes = []
	_seq_clear()  # king's last stand: the sequence (if any) is over
	_enter(Phase.IDLE)
	aborted.emit(reason)


func _enter(next: int) -> void:
	phase = next
	_time = 0.0
	phase_changed.emit(next)


# ---- per-frame ------------------------------------------------------------------------------------
func advance(dt: float) -> void:
	if phase == Phase.IDLE:
		return
	_time += dt
	match phase:
		Phase.CAPTURE_FOCUS:
			_tick_capture()
		Phase.TRAPDOOR_OPEN:
			_tick_open()
		Phase.DROP:
			_tick_drop()
		Phase.COMBAT:
			pass
		Phase.RESOLVE:
			_tick_resolve()
		Phase.CLIMB:
			_tick_climb()
		Phase.RETURN:
			_tick_return(dt)
		Phase.INTERLUDE:
			_seq_tick_interlude()  # king's last stand


# CAPTURE_FOCUS: attacker slides onto the contested tile, camera zooms toward it.
func _stand_local(index: int) -> Vector3:
	return _tile_center + Vector3(0, 0, -W.PIECE_OFFSET if _colors[index] == "w" else W.PIECE_OFFSET)


func _tick_capture() -> void:
	var u := W.smooth(_time / W.PIECE_SLIDE_TIME)
	var a_node: Node3D = _nodes[0]
	var d_node: Node3D = _nodes[1]
	a_node.position = _origin_local[0].lerp(_stand_local(0), u) + Vector3(0, 0.35 * sin(PI * u), 0)
	d_node.position = _origin_local[1].lerp(_stand_local(1), u)
	if _time >= W.CAPTURE_FOCUS_TIME:
		world.trapdoor.open(W.TRAPDOOR_OPEN_TIME)
		_enter(Phase.TRAPDOOR_OPEN)


func _tick_open() -> void:
	var done: bool = _time >= W.TRAPDOOR_OPEN_TIME and world.trapdoor.is_open()
	if not done:
		return
	if require_arena and (arena == null or not is_instance_valid(arena)):
		if _time > ARENA_WAIT_TIMEOUT:
			abort("arena not ready")
		return
	_begin_drop()


func _begin_drop() -> void:
	for node in _nodes:
		_set_layers(node, W.LAYER_CHAMBER | W.LAYER_BOARD)
	_landed = false
	_release_simulation()
	world.rig.go(CameraRig.State.COMBAT_TRANSITION, W.DROP_TIME + W.DESCENT_EXTRA_TIME)
	_enter(Phase.DROP)
	drop_started.emit()


func _release_simulation() -> void:
	if arena != null and is_instance_valid(arena) and arena.has_method("set_physics_process"):
		arena.set_physics_process(true)


func _spawn_world(index: int) -> Vector3:
	return Vector3(0, 0, -W.SPAWN_Z if _colors[index] == "w" else W.SPAWN_Z)


# DROP: both pieces fall through the hole, morph at the landing, camera dolly-zooms down.
func _tick_drop() -> void:
	var t := minf(_time, W.DROP_TIME)
	if not _landed:
		var g := 2.0 * W.BOARD_DEPTH / (W.DROP_TIME * W.DROP_TIME)
		var y := W.BOARD_DEPTH - 0.5 * g * t * t
		var t_clear := sqrt(2.0 * (W.BOARD_DEPTH - W.CEILING_BOTTOM) / g)
		var lateral := W.smooth((t - t_clear) / maxf(0.01, W.DROP_TIME - t_clear))
		for i in 2:
			var node: Node3D = _nodes[i]
			var stand := _stand_local(i) + world.board_root.position   # world frame
			var spawn := _spawn_world(i)
			var p := Vector3(stand.x, 0, stand.z).lerp(spawn, lateral)
			node.position = Vector3(p.x, maxf(y, 0.0), p.z) - world.board_root.position
			node.rotation = Vector3(t * (3.0 if i == 0 else -3.0), 0, t * (1.4 if i == 0 else -1.1))
	if _time >= W.DROP_TIME and not _landed:
		_land()
	if _time >= W.DROP_TIME + W.DESCENT_EXTRA_TIME and not world.rig.is_transitioning():
		world.rig.go(CameraRig.State.COMBAT_THIRD_PERSON, W.COMBAT_BLEND_TIME)
		_set_arena_overlays(true)
		_enter(Phase.COMBAT)
		combat_started.emit()
		if not _result.is_empty():
			_begin_resolve()


func _land() -> void:
	_landed = true
	for i in 2:
		var node: Node3D = _nodes[i]
		node.visible = false
		node.rotation = Vector3(0, PI if _colors[i] == "b" else 0.0, 0)
		world.fx[i].play(_spawn_world(i) + Vector3(0, 0.6, 0), Color(1.0, 0.86, 0.55) if _colors[i] == "w" else Color(0.9, 0.55, 0.7))
	_set_fighters_visible(true)
	if world.rig.follow == null and arena != null and is_instance_valid(arena):
		var cams = arena.get("cameras")
		if cams is Array and not cams.is_empty():
			world.rig.follow = cams[0].camera


# RESOLVE: the loser's defeat plays and it disappears.
func _begin_resolve() -> void:
	_winner_visual = _visual(_winner_index)
	_loser_visual = _visual(1 - _winner_index)
	_dissolve_started = false
	_loser_detached = false
	if _winner_visual != null:
		world.rig.victory_focus = _winner_visual.global_position
	world.rig.go(CameraRig.State.COMBAT_VICTORY)
	_enter(Phase.RESOLVE)


func _tick_resolve() -> void:
	if _winner_visual != null and is_instance_valid(_winner_visual):
		world.rig.victory_focus = _winner_visual.global_position
	if not _loser_detached:
		_loser_detached = true
		_ensure_defeat_pose()
	var u := (_time - W.RESOLVE_DEFEAT_TIME) / W.RESOLVE_DISSOLVE_TIME
	if u >= 0.0 and _loser_visual != null and is_instance_valid(_loser_visual):
		if not _dissolve_started:
			_dissolve_started = true
			world.fx[1 - _winner_index].play(_loser_visual.global_position + Vector3(0, 0.5, 0), Color(0.7, 0.65, 0.55))
		_loser_visual.scale = Vector3.ONE * maxf(0.001, 1.0 - W.smooth(u))
	if _time >= W.RESOLVE_DEFEAT_TIME + W.RESOLVE_DISSOLVE_TIME:
		if _loser_visual != null and is_instance_valid(_loser_visual):
			_loser_visual.visible = false
		if _seq_continues():  # king's last stand: another duel follows, the pit stays in the chamber
			_seq_begin_interlude()
		else:
			_begin_climb()


func _ensure_defeat_pose() -> void:
	## Normally the simulation already put the loser into Defeated (knockout). On a timeout the loser
	## is still standing: detach it from the sim and play its defeat clip so the presentation matches.
	if _loser_visual == null or not is_instance_valid(_loser_visual):
		return
	var fighter = _loser_visual.get("fighter")
	if fighter != null and is_instance_valid(fighter) and fighter.sm.state == CombatConstants.State.DEFEATED:
		return
	_loser_visual.set_process(false)
	if _loser_visual.has_method("play_clip"):
		_loser_visual.call("play_clip", "defeat")


# CLIMB: the winner walks to the ladder foot, climbs out, steps back onto its tile.
func _begin_climb() -> void:
	_set_arena_overlays(false)
	var visual := _winner_visual
	if visual != null and is_instance_valid(visual):
		visual.set_process(false)
		if visual.get_parent() != world.chamber:
			visual.reparent(world.chamber, true)
		_set_layers(visual, W.LAYER_CHAMBER | W.LAYER_BOARD)
		var start := visual.global_position
		var foot := world.chamber.climb_position(0.0)
		var walk := Vector2(foot.x - start.x, foot.z - start.z).length()
		var t_walk := maxf(W.LADDER_DEPLOY_TIME, walk / W.CLIMB_WALK_SPEED)
		var top := W.BOARD_DEPTH + W.TILE_THICKNESS * 0.5
		_climb = {"start": start, "yaw": visual.rotation.y, "t_walk": t_walk, "t_climb": top / W.CLIMB_SPEED, "top": top, "stage": -1}
		if visual.has_method("play_clip"):
			visual.call("play_clip", "walk", 1.0)
	else:  # no arena (timing-only runs): same timeline, no model to move
		var top_y := W.BOARD_DEPTH + W.TILE_THICKNESS * 0.5
		_climb = {"start": world.chamber.climb_position(0.0), "yaw": 0.0, "t_walk": W.LADDER_DEPLOY_TIME, "t_climb": top_y / W.CLIMB_SPEED, "top": top_y, "stage": -1}
	_enter(Phase.CLIMB)


func climb_duration() -> float:
	return (_climb["t_walk"] + _climb["t_climb"] + W.CLIMB_EXIT_TIME) if not _climb.is_empty() else 0.0


func _tick_climb() -> void:
	var t_walk: float = _climb["t_walk"]
	var t_climb: float = _climb["t_climb"]
	var top: float = _climb["top"]
	world.chamber.set_ladder(W.smooth(_time / W.LADDER_DEPLOY_TIME))
	var visual := _winner_visual
	var pos := Vector3.ZERO
	var yaw := 0.0
	var foot := world.chamber.climb_position(0.0)
	if _time < t_walk:
		var u := W.smooth(_time / t_walk)
		var start: Vector3 = _climb["start"]
		pos = start.lerp(foot, u)
		var dir := foot - start
		var target_yaw: float = atan2(dir.x, dir.z) if Vector2(dir.x, dir.z).length() > 0.05 else 0.0
		yaw = lerp_angle(float(_climb["yaw"]), target_yaw if u < 0.8 else 0.0, minf(1.0, u * 1.5))
		_climb_stage(0, visual)
	elif _time < t_walk + t_climb:
		var h := (_time - t_walk) / t_climb
		pos = world.chamber.climb_position(h * top)
		_climb_stage(1, visual)
	else:
		var u := W.smooth((_time - t_walk - t_climb) / W.CLIMB_EXIT_TIME)
		var up := world.chamber.climb_position(top)
		var stand := _stand_local(_winner_index) + world.board_root.position
		pos = up.lerp(Vector3(stand.x, top, stand.z), u)
		_climb_stage(2, visual)
	if visual != null and is_instance_valid(visual):
		visual.global_position = pos
		visual.rotation.y = yaw
	world.rig.victory_focus = pos
	if _time >= t_walk + t_climb + W.CLIMB_EXIT_TIME:
		_begin_return()


func _climb_stage(stage: int, visual: Node3D) -> void:
	if _climb["stage"] == stage:
		return
	_climb["stage"] = stage
	if visual == null or not is_instance_valid(visual) or not visual.has_method("play_clip"):
		return
	if stage == 1:
		if visual.has_method("has_clip") and visual.call("has_clip", "climb"):
			visual.call("play_clip", "climb", W.CLIMB_SPEED / W.LADDER_CLIP_SPEED)
		else:
			visual.call("play_clip", "walk", 0.5)  # fallback: walk clip, slowed, while the model rises
	elif stage == 2:
		visual.call("play_clip", "walk", 1.0)


# RETURN: winner morphs back into its piece on the tile, the camera glides up, the trapdoor closes.
func _begin_return() -> void:
	_return_morphed = false
	_return_ready_sent = false
	_trapdoor_closing = false
	world.rig.go(CameraRig.State.RETURN_TO_CHESS, W.RETURN_CAMERA_TIME)
	_enter(Phase.RETURN)


func _tick_return(dt: float) -> void:
	var winner: Node3D = _nodes[_winner_index]
	if not _return_morphed:
		_return_morphed = true
		# The winner's mesh is placed on its tile in board-local space and pops into existence.
		winner.visible = true
		winner.rotation = Vector3(0, PI if _colors[_winner_index] == "b" else 0.0, 0)
		winner.scale = Vector3.ONE * 0.01
		winner.position = _stand_local(_winner_index)
		var color := Color(1.0, 0.86, 0.55) if _colors[_winner_index] == "w" else Color(0.9, 0.55, 0.7)
		world.fx[_winner_index].play(_stand_local(_winner_index) + world.board_root.position + Vector3(0, 0.6, 0), color)
		_seq_vanish_begin()  # king's last stand: the removed mating group vanishes (no-op for a single capture)
	_seq_vanish_tick()
	var u := _time / W.RETURN_MORPH_TIME
	if u < 1.0:
		var pop := W.smooth(u)
		winner.scale = Vector3.ONE * maxf(0.01, pop * (1.0 + 0.12 * sin(PI * u)))
		if _winner_visual != null and is_instance_valid(_winner_visual):
			_winner_visual.scale = Vector3.ONE * maxf(0.001, 1.0 - pop)
	else:
		winner.scale = Vector3.ONE
		winner.position = winner.position.lerp(_return_target(), minf(1.0, dt * 8.0))  # _return_target() == _tile_center for a single capture
		if _winner_visual != null and is_instance_valid(_winner_visual):
			_winner_visual.visible = false
		if not _return_ready_sent:
			_return_ready_sent = true
			world.chamber.set_ladder(0.0)
			return_ready.emit()
	if not _trapdoor_closing and _time >= W.RETURN_CAMERA_TIME * 0.5:
		_trapdoor_closing = true
		world.trapdoor.close(W.TRAPDOOR_CLOSE_TIME)
	if _time >= W.RETURN_CAMERA_TIME and not world.rig.is_transitioning() and world.trapdoor.is_closed():
		_finish_return()


func _finish_return() -> void:
	if not _return_ready_sent:
		_return_ready_sent = true
		return_ready.emit()
	var winner: Node3D = _nodes[_winner_index]
	winner.position = _return_target()
	world.restore_after_battle(_entries(), _seq_restore_success(), _seq_winner_entry())  # single capture: (_entries(), true, _winner_index)
	_winner_visual = null
	_loser_visual = null
	arena = null
	_request = {}
	_result = {}
	_nodes = []
	_seq_clear()
	_enter(Phase.IDLE)
	finished.emit()


func _entries() -> Array:
	if not _seq.is_empty():
		return _seq_entries()  # king's last stand: the King and the whole mating group
	var out: Array = []
	for i in _nodes.size():
		out.append({"node": _nodes[i], "pos": _origin_local[i], "rot_y": _origin_rot[i]})
	return out


# ---- helpers --------------------------------------------------------------------------------------
func _visual(index: int) -> Node3D:
	if arena == null or not is_instance_valid(arena):
		return null
	var color := String(_colors[index])
	return arena.get_node_or_null("Visual_" + color) as Node3D


func _set_fighters_visible(value: bool) -> void:
	if arena == null or not is_instance_valid(arena):
		return
	for color in ["w", "b"]:
		var visual := arena.get_node_or_null("Visual_" + color) as Node3D
		if visual != null:
			visual.visible = value


func _set_arena_overlays(value: bool) -> void:
	if arena == null or not is_instance_valid(arena):
		return
	for child in arena.get_children():
		if child is CanvasLayer:
			child.visible = value


static func _set_layers(root: Node, mask: int) -> void:
	if root is VisualInstance3D:
		root.layers = mask
	for child in root.find_children("*", "VisualInstance3D", true, false):
		child.layers = mask


# ======================================================================================================================
# BEGIN king's last stand (battle-royal-v1): multi-duel sequences. Everything below is NEW and self-contained; the phase
# code above only calls the small hooks named _seq_* / _return_target (all no-ops for an ordinary single capture).
#
# One descent for the WHOLE sequence: begin_sequence() + begin(duel 1) run the normal CAPTURE_FOCUS .. COMBAT. When the King
# wins a duel that is not the last, RESOLVE ends in INTERLUDE instead of CLIMB: the pit stays in the chamber (no climb, no
# scene change), `duel_cleared` tells the bridge to commit that duel, and next_duel(request) steps the next checker in: the
# arena restarts in place, both fighters flash in at their spawn points, the camera settles into the third-person pose and
# COMBAT resumes. Winning the last duel continues with CLIMB/RETURN: the King returns to ITS OWN square and the removed
# mating group vanishes; losing any duel climbs the winning checker out, and every piece is restored where the board has it.
# The sequence never decides anything (outcome / carried HP come from the combat authority through the bridge).
# ======================================================================================================================

## A non-final duel of a multi-duel sequence was won by the King and its RESOLVE finished (the pit is in INTERLUDE).
signal duel_cleared(index: int)
## The multi-duel sequence is over (normal end or abort); the single-capture machinery is back in charge.
signal sequence_ended

## Seconds the two fighters take to step in (flash at the spawns, camera settling) before the next duel's COMBAT.
const SEQ_STEP_IN_TIME := 0.8
const SEQ_VANISH_TIME := 0.5
const SEQ_VANISH_STAGGER := 0.15

var _seq: Dictionary = {}   # {} = ordinary single capture


## `info` = BattleRoyalMatch.royal_request() ({king: combatant, attackers: [combatant...]} in fighting order); `start_index` is
## the duel about to be presented (0 for a fresh sequence, > 0 when a duel is re-armed after an interruption). Call it while
## IDLE, then begin(duel request). Returns false (and changes nothing) when the pieces are not on the board.
func begin_sequence(info: Dictionary, start_index: int = 0) -> bool:
	if phase != Phase.IDLE or world == null or not world.can_present() or not _seq.is_empty():
		return false
	var king_node: Node3D = world.piece_node(String(info["king"]["pieceId"]))
	if king_node == null:
		return false
	var checkers: Array = []
	for entry in info["attackers"]:
		var node: Node3D = world.piece_node(String(entry["pieceId"]))
		if node == null:
			return false
		checkers.append({"id": String(entry["pieceId"]), "node": node, "pos": node.position, "rot_y": node.rotation.y})
	_seq = {"total": checkers.size(), "index": start_index, "stage": "", "t_stage": 0.0,
			"king": {"id": String(info["king"]["pieceId"]), "node": king_node, "pos": king_node.position, "rot_y": king_node.rotation.y},
			"checkers": checkers, "vanish": false}
	return true


func sequence_active() -> bool:
	return not _seq.is_empty()


## Index (0-based) of the duel being presented, -1 when no sequence runs.
func sequence_index() -> int:
	return int(_seq["index"]) if not _seq.is_empty() else -1


func sequence_total() -> int:
	return int(_seq["total"]) if not _seq.is_empty() else 0


## INTERLUDE only: present the next duel (`request` = its frozen BattleRequest, the King is the attacker). The caller restarts the
## arena (BattleFlow.confirm_capture -> adapter.start); the pit steps the fighters in once the arena runs the new battle.
func next_duel(request: Dictionary) -> bool:
	if phase != Phase.INTERLUDE or _seq.is_empty() or _seq["stage"] != "hold":
		return false
	var attacker: Dictionary = request["attacker"]
	var defender: Dictionary = request["defender"]
	var checker := _seq_checker(String(defender["pieceId"]))
	if checker.is_empty() or String(attacker["pieceId"]) != String(_seq["king"]["id"]):
		return false
	_seq["index"] = int(_seq["index"]) + 1
	_request = request.duplicate(true)
	_nodes = [_seq["king"]["node"], checker["node"]]
	_colors = [String(attacker["color"]), String(defender["color"])]
	_origin_local = [_seq["king"]["pos"], checker["pos"]]
	_origin_rot = [_seq["king"]["rot_y"], checker["rot_y"]]
	_result = {}
	_winner_index = -1
	_winner_visual = null
	_loser_visual = null
	(checker["node"] as Node3D).visible = false   # the checker "drops": the board is out of sight, only the fighter remains
	_seq["stage"] = "wait_arena"
	_seq["t_stage"] = _time
	return true


## Explicit end of a sequence: aborts a running presentation (everything restored) or just forgets an armed one.
func end_sequence() -> void:
	if phase != Phase.IDLE:
		abort("sequence ended")
	else:
		_seq_clear()


func _seq_checker(piece_id: String) -> Dictionary:
	for entry in _seq.get("checkers", []):
		if entry["id"] == piece_id:
			return entry
	return {}


func _seq_clear() -> void:
	if _seq.is_empty():
		return
	_seq = {}
	sequence_ended.emit()


## True after RESOLVE when the King won and more duels follow.
func _seq_continues() -> bool:
	return not _seq.is_empty() and _winner_index == 0 and int(_seq["index"]) + 1 < int(_seq["total"])


func _seq_begin_interlude() -> void:
	_set_arena_overlays(false)   # the previous duel's result panel must not stay on screen
	_seq["stage"] = "hold"
	_enter(Phase.INTERLUDE)
	_seq["t_stage"] = _time
	duel_cleared.emit(int(_seq["index"]))


func _seq_tick_interlude() -> void:
	match String(_seq["stage"]):
		"wait_arena":
			var arena_ok := not require_arena or _seq_arena_runs_request()
			if arena_ok:
				_seq_step_in()
			elif _time - float(_seq["t_stage"]) > ARENA_WAIT_TIMEOUT:
				abort("arena not ready")
		"step_in":
			if _time - float(_seq["t_stage"]) >= SEQ_STEP_IN_TIME and not world.rig.is_transitioning():
				_set_arena_overlays(true)
				_enter(Phase.COMBAT)
				combat_started.emit()
				if not _result.is_empty():
					_begin_resolve()


func _seq_arena_runs_request() -> bool:
	if arena == null or not is_instance_valid(arena):
		return false
	var sim = arena.get("sim")
	return sim != null and String(sim.request.get("battleId", "")) == String(_request.get("battleId", "?"))


## Both fighters flash in at their spawn points (the arena restarted in place: they stand at the start positions), the camera
## settles into the third-person pose and the arena's paused simulation is released (its own countdown runs).
func _seq_step_in() -> void:
	_seq["stage"] = "step_in"
	_seq["t_stage"] = _time
	_set_fighters_visible(false)
	for i in 2:
		world.fx[i].play(_spawn_world(i) + Vector3(0, 0.6, 0), Color(1.0, 0.86, 0.55) if _colors[i] == "w" else Color(0.9, 0.55, 0.7))
	_set_fighters_visible(true)
	if arena != null and is_instance_valid(arena):
		var cams = arena.get("cameras")
		if cams is Array and not cams.is_empty():
			world.rig.follow = cams[0].camera
		world.rig.camera.make_current()
	world.rig.go(CameraRig.State.COMBAT_THIRD_PERSON, SEQ_STEP_IN_TIME)
	_release_simulation()


## Where the winner of the whole sequence ends up (board-local): its own square (a single capture: the contested tile).
func _return_target() -> Vector3:
	if _seq.is_empty():
		return _tile_center
	return _origin_local[_winner_index]


## King and mating group, each with the position/rotation to restore. Index 0 is always the King.
func _seq_entries() -> Array:
	var out: Array = [{"node": _seq["king"]["node"], "pos": _seq["king"]["pos"], "rot_y": _seq["king"]["rot_y"]}]
	for entry in _seq["checkers"]:
		out.append({"node": entry["node"], "pos": entry["pos"], "rot_y": entry["rot_y"]})
	return out


## King survived the whole sequence: the committed board removes the group (success, winner = the King). King fell: the board
## is untouched, so every piece goes back to its square (not a "capture" restore).
func _seq_restore_success() -> bool:
	return _seq.is_empty() or _winner_index == 0


func _seq_winner_entry() -> int:
	if _seq.is_empty():
		return _winner_index
	return 0 if _winner_index == 0 else -1


## RETURN, King won the last duel: the mating group reappears on its squares for a moment and vanishes in dust.
func _seq_vanish_begin() -> void:
	if _seq.is_empty() or _winner_index != 0:
		return
	_seq["vanish"] = true
	var first := true
	for entry in _seq["checkers"]:
		var node: Node3D = entry["node"]
		if not is_instance_valid(node):
			continue
		node.visible = true
		node.scale = Vector3.ONE
		node.position = entry["pos"]
		node.rotation = Vector3(0, entry["rot_y"], 0)
		if first:
			first = false
			world.fx[1].play(Vector3(node.position) + world.board_root.position + Vector3(0, 0.6, 0), Color(0.7, 0.65, 0.55))


func _seq_vanish_tick() -> void:
	if _seq.is_empty() or not _seq.get("vanish", false):
		return
	var k := 0
	for entry in _seq["checkers"]:
		var node: Node3D = entry["node"]
		if is_instance_valid(node):
			var u := (_time - SEQ_VANISH_STAGGER * k) / SEQ_VANISH_TIME
			node.scale = Vector3.ONE * maxf(0.001, 1.0 - W.smooth(u))
			node.visible = u < 1.0
		k += 1
# END king's last stand
