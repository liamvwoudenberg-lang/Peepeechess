extends RefCounted
## Pit world (godot/world/): camera rig, trapdoor, PitSequence state machine, interruption recovery,
## leak checks, top-down chess view and a scripted end-to-end capture through the real battle flow.
## Everything is driven by explicit advance(dt) calls (world.auto_advance = false), so it is deterministic;
## only the e2e part lets the real CombatArena tick (at a raised physics rate to keep it short).

const Main := preload("res://app/main.tscn")
const Interaction := preload("res://boards/board_interaction.gd")
const BattleMatch := preload("res://chess/battle_match.gd")
const BattleRules := preload("res://chess/battle_rules.gd")
const Rules := preload("res://chess/chess_engine.gd")
const W := preload("res://world/world_constants.gd")
const FEN := "7k/8/8/4q3/3P4/8/8/7K w - - 0 1"
const DT := 1.0 / 60.0
const PHASES := ["IDLE", "CAPTURE_FOCUS", "TRAPDOOR_OPEN", "DROP", "COMBAT", "RESOLVE", "CLIMB", "RETURN"]


static func run(h, tree: SceneTree) -> void:
	await _camera(h, tree)
	await _sequence_timing(h, tree)
	await _result_presentation(h, tree)
	await _interruptions(h, tree)
	await _repeat_leaks(h, tree)
	await _top_down_view(h, tree)
	await _single_camera(h, tree)
	await _end_to_end(h, tree)


# ---- fixtures ------------------------------------------------------------------------------------
static func _fixture(tree: SceneTree) -> Dictionary:
	var holder := Control.new()
	holder.size = Vector2(800, 600)
	tree.root.add_child(holder)
	var game := BattleMatch.new()
	game.new_game(0, 0, FEN)
	var interaction := Interaction.new(game)
	var board := ChessBoard3D.new()
	board.size = Vector2(800, 600)
	holder.add_child(board)
	board.setup(game, interaction)
	board.animation_enabled = false
	var world: BattleWorld = board.world
	world.auto_advance = false
	world.pit.require_arena = false
	await tree.process_frame
	return {"holder": holder, "game": game, "interaction": interaction, "board": board, "world": world}


static func _free(fx: Dictionary, tree: SceneTree) -> void:
	fx["interaction"].dispose()
	fx["holder"].queue_free()
	await tree.process_frame


static func _capture_request(fx: Dictionary) -> Dictionary:
	var game: BattleMatch = fx["game"]
	if game.phase != "board":
		game.cancel_pending()
	game.play("d4", "e5")
	return game.pending_request()


static func _step(world: BattleWorld, seconds: float) -> void:
	var n := int(ceil(seconds / DT - 0.0001))
	for _i in n:
		world.advance(DT)


## Steps until the pit is in `phase` and has spent `into` seconds in it (max 40 s). Returns false on timeout.
static func _run_to(world: BattleWorld, phase: int, into: float = 0.0) -> bool:
	var guard := 0
	while guard < 40 * 60:
		if world.pit.phase == phase and world.pit._time >= into:
			return true
		if world.pit.phase == PitSequence.Phase.IDLE and phase != PitSequence.Phase.IDLE:
			return false
		world.advance(DT)
		guard += 1
	return false


static func _record(world: BattleWorld) -> Array:
	var log: Array = []
	var clock := {"t": 0.0}
	world.pit.phase_changed.connect(func(p: int): log.append([p, clock["t"]]))
	log.append(clock)  # last element is the clock dictionary; callers advance it via _timed_step
	return log


static func _count(node: Node) -> int:
	var n := 1
	for child in node.get_children():
		n += _count(child)
	return n


static func _snapshot_board(board: ChessBoard3D) -> Dictionary:
	var out := {}
	for i in board.tiles.size():
		var tile: MeshInstance3D = board.tiles[i]
		out["tile%d" % i] = [tile.transform, tile.visible]
	for child in board.world.board_root.get_children():
		if child is MeshInstance3D and child.mesh is BoxMesh:
			out["box:" + str(child.get_index())] = [child.transform, child.visible, (child.mesh as BoxMesh).size]
	return out


static func _world_is_chess(h, fx: Dictionary, label: String) -> void:
	var world: BattleWorld = fx["world"]
	var board: ChessBoard3D = fx["board"]
	h.check(world.pit.is_idle(), label + ": pit idle")
	h.check(world.board_root.position == Vector3.ZERO and not world.shifted, label + ": board root back at the origin")
	h.check(not world.chamber.visible, label + ": chamber hidden")
	h.check(not world.trapdoor.is_active() and world.trapdoor.is_closed(), label + ": trapdoor closed and inactive")
	h.check(world.rig.origin == Vector3.ZERO, label + ": camera frame restored")
	h.check(not board.sync_hold, label + ": board sync released")
	for tile in board.tiles:
		if not tile.visible:
			h.check(false, label + ": a tile stayed hidden")
			break
	var state: Dictionary = fx["game"].chess_state()
	var ids := []
	for p in state.pieces:
		ids.append(p.pieceId)
		var node: Node3D = board.pieces.get(p.pieceId)
		if node == null:
			h.check(false, label + ": missing piece mesh " + p.pieceId)
			continue
		h.check(node.visible and node.scale == Vector3.ONE and node.position.is_equal_approx(Interaction.world_position(Rules.index(p.square))), label + ": piece %s on its tile, visible, unscaled" % p.pieceId)
		h.check(node.rotation.x == 0.0 and node.rotation.z == 0.0, label + ": piece %s upright" % p.pieceId)
	h.eq(board.pieces.size(), ids.size(), label + ": mesh registry equals chess state")


# ---- camera ----------------------------------------------------------------------------------------
static func _camera(h, tree: SceneTree) -> void:
	var fx := await _fixture(tree)
	var world: BattleWorld = fx["world"]
	var rig := world.rig
	rig.animate = true

	h.begin("world camera: top-down is a straight-down narrow-FOV perspective camera")
	rig.set_aspect(1.5)
	rig.snap_to(CameraRig.State.CHESS_TOP_DOWN)
	var forward := -rig.camera.basis.z
	h.check(forward.is_equal_approx(Vector3.DOWN), "looks straight down")
	h.near(rig.camera.fov, W.FOV_TOP_DOWN, 0.001, "narrow FOV")
	h.check(rig.camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "perspective (not orthographic)")
	var half_height := rig.camera.position.y * tan(deg_to_rad(rig.camera.fov) * 0.5)
	h.check(half_height >= 4.8, "whole 8x8 board (+ frame) fits vertically (half height %.2f)" % half_height)
	h.check((rig.camera.basis.y).is_equal_approx(Vector3(0, 0, -1)), "rank 8 is up the screen")
	rig.set_flipped(true)
	h.check((rig.camera.basis.y).is_equal_approx(Vector3(0, 0, 1)), "flipped board turns the top-down view around")
	rig.set_flipped(false)
	rig.set_aspect(0.5)
	h.check(rig.camera.position.y * tan(deg_to_rad(rig.camera.fov) * 0.5) >= 4.8 / 0.5 * 0.95, "portrait window still fits the board width")
	h.check(rig.camera.far > rig.camera.position.y + 10.0, "far plane reaches the board from the portrait height")
	rig.set_aspect(1.5)

	h.begin("world camera: every named state is reachable and reaches its target pose")
	h.eq(CameraRig.STATE_NAMES.size(), 7, "seven named states")
	h.eq(CameraRig.state_name(CameraRig.State.COMBAT_TRANSITION), "CombatTransition", "state names")
	rig.focus_tile = Vector3(1, 0, -2)
	rig.snap_to(CameraRig.State.CHESS_TOP_DOWN)
	var follow := Camera3D.new()
	follow.fov = 68.0
	world.add_child(follow)
	follow.global_position = Vector3(0.5, 2.6, -5.0)
	follow.look_at(Vector3(0, 1, 0))
	for state in [CameraRig.State.CHESS_PERSPECTIVE, CameraRig.State.CAPTURE_FOCUS, CameraRig.State.COMBAT_THIRD_PERSON, CameraRig.State.COMBAT_VICTORY, CameraRig.State.CHESS_TOP_DOWN]:
		rig.follow = follow
		rig.go(state, 0.4)
		h.check(rig.is_transitioning() or state == rig.state, "transition to %s starts" % CameraRig.state_name(state))
		var mid_pos := rig.camera.position
		_step(world, 0.2)
		h.check(rig.is_transitioning(), "%s still gliding at half time" % CameraRig.state_name(state))
		_step(world, 0.25)
		h.check(not rig.is_transitioning() and rig.state == state, "%s reached" % CameraRig.state_name(state))
		var target := rig.pose_for(state)
		h.check(rig.camera.position.distance_to(target["p"]) < 0.01 and absf(rig.camera.fov - float(target["fov"])) < 0.01, "%s pose matches its target" % CameraRig.state_name(state))
		h.check(mid_pos != rig.camera.position or state == CameraRig.State.CHESS_TOP_DOWN, "%s moved" % CameraRig.state_name(state))
	rig.go(CameraRig.State.CAPTURE_FOCUS, 0.3)
	_step(world, 0.4)
	h.check(absf(rig.camera.position.x - 1.0) < 0.01 and absf(rig.camera.position.z + 2.0) < 0.01, "CaptureFocus centres on the contested tile")
	h.check(rig.camera.cull_mask & W.LAYER_CEILING == 0, "the chamber ceiling is culled from cameras above it")
	rig.animate = false
	rig.go(CameraRig.State.CHESS_PERSPECTIVE)
	h.check(not rig.is_transitioning() and rig.state == CameraRig.State.CHESS_PERSPECTIVE, "a non-animated rig snaps")
	rig.animate = true

	h.begin("world camera: the descent is a dolly-zoom that stays inside the shaft")
	rig.set_origin(Vector3(-1, W.BOARD_DEPTH, 2))   # tile (1,0,-2) is now above the arena centre
	rig.focus_tile = Vector3(1, 0, -2)
	rig.snap_to(CameraRig.State.CAPTURE_FOCUS)
	rig.follow = follow
	rig.go(CameraRig.State.COMBAT_TRANSITION, 2.0)
	var width_ok := true
	var shaft_ok := true
	var min_y := 1e9
	var max_fov := 0.0
	var samples := 0
	for i in 120:
		world.advance(DT)
		var p := rig.camera.position
		var above := p.y - rig.origin.y
		if rig.camera.position.y > W.BOARD_DEPTH + W.DESCENT_STOP_ABOVE_BOARD - 0.05 and rig.camera.position.y < W.BOARD_DEPTH + 30.0:
			var width := 2.0 * above * tan(deg_to_rad(rig.camera.fov) * 0.5)
			samples += 1
			if absf(width - 2.0 * W.FOCUS_HALF_EXTENT) > 0.02 * 2.0 * W.FOCUS_HALF_EXTENT:
				width_ok = false
		if p.y >= W.CEILING_BOTTOM - 0.1 and p.y <= W.BOARD_DEPTH:
			if absf(p.x) > 0.31 or absf(p.z) > 0.31:
				shaft_ok = false
		min_y = minf(min_y, p.y)
		max_fov = maxf(max_fov, rig.camera.fov)
	h.check(samples > 10, "dolly-zoom segment sampled (%d)" % samples)
	h.check(width_ok, "framed width at the board stays constant while height and FOV change together")
	h.check(shaft_ok, "camera never touches the shaft walls")
	h.check(max_fov > 40.0, "FOV widens during the dolly-zoom (%.1f)" % max_fov)
	_step(world, 1.0)
	h.check(rig.camera.position.distance_to(rig.pose_for(CameraRig.State.COMBAT_THIRD_PERSON)["p"]) < 0.01, "descent ends exactly on the third-person pose")
	h.check(rig.camera.cull_mask & W.LAYER_CEILING != 0, "ceiling visible again once the camera is below it")
	h.begin("world camera: recover() returns to the chess view from any state")
	rig.chess_view = CameraRig.State.CHESS_TOP_DOWN
	rig.recover(0.0)
	h.check(rig.state == CameraRig.State.CHESS_TOP_DOWN and not rig.is_transitioning(), "snapped back")
	rig.set_origin(Vector3.ZERO)
	rig.go(CameraRig.State.COMBAT_VICTORY, 0.5)
	_step(world, 0.1)
	rig.recover(0.3)
	_step(world, 0.4)
	h.check(rig.state == rig.chess_view and rig.camera.position.distance_to(rig.pose_for(rig.chess_view)["p"]) < 0.01, "glided back mid-transition")
	follow.queue_free()
	await _free(fx, tree)


# ---- phase order & durations ------------------------------------------------------------------------
static func _sequence_timing(h, tree: SceneTree) -> void:
	var fx := await _fixture(tree)
	var world: BattleWorld = fx["world"]
	var pit := world.pit
	h.begin("world pit: phase order and durations")
	var request := _capture_request(fx)
	var log: Array = []
	var clock := {"t": 0.0}
	pit.phase_changed.connect(func(p: int): log.append([p, clock["t"]]))
	h.check(pit.begin(request), "begin accepted")
	h.check(not pit.begin(request), "a second begin while running is refused")
	h.eq(pit.phase, PitSequence.Phase.CAPTURE_FOCUS, "CAPTURE_FOCUS")
	var returned: Array = []
	pit.return_ready.connect(func(): returned.append(clock["t"]))
	var finished: Array = []
	pit.finished.connect(func(): finished.append(clock["t"]))
	var drops: Array = []
	pit.drop_started.connect(func(): drops.append(clock["t"]))
	var guard := 0
	var result_sent := -1.0
	while guard < 60 * 40 and pit.phase != PitSequence.Phase.IDLE or guard == 0:
		clock["t"] += DT
		world.advance(DT)
		guard += 1
		if pit.phase == PitSequence.Phase.COMBAT and result_sent < 0.0 and pit._time >= 0.5:
			result_sent = clock["t"]
			pit.present_result({"outcome": "attacker", "winnerPlayerId": request.attacker.playerId})
	h.check(pit.is_idle(), "sequence completes")
	var order := []
	for entry in log:
		order.append(PHASES[entry[0]])
	h.eq(order, ["CAPTURE_FOCUS", "TRAPDOOR_OPEN", "DROP", "COMBAT", "RESOLVE", "CLIMB", "RETURN", "IDLE"], "phase order")
	var at := {}
	for entry in log:
		at[PHASES[entry[0]]] = entry[1]
	h.near(at["TRAPDOOR_OPEN"] - at["CAPTURE_FOCUS"], W.CAPTURE_FOCUS_TIME, 0.04, "CAPTURE_FOCUS duration")
	h.near(at["DROP"] - at["TRAPDOOR_OPEN"], W.TRAPDOOR_OPEN_TIME, 0.04, "TRAPDOOR_OPEN duration")
	h.near(at["COMBAT"] - at["DROP"], W.DROP_TIME + W.DESCENT_EXTRA_TIME, 0.05, "DROP (fall + descent) duration")
	h.near(at["RESOLVE"], result_sent, 0.03, "RESOLVE starts when the authoritative result is presented")
	h.near(at["CLIMB"] - at["RESOLVE"], W.RESOLVE_DEFEAT_TIME + W.RESOLVE_DISSOLVE_TIME, 0.05, "RESOLVE duration")
	var climb: float = at["RETURN"] - at["CLIMB"]
	h.check(climb > W.BOARD_DEPTH / W.CLIMB_SPEED, "CLIMB takes longer than the ladder alone (%.2f s)" % climb)
	h.near(climb, (W.BOARD_DEPTH + W.TILE_THICKNESS * 0.5) / W.CLIMB_SPEED + W.CLIMB_EXIT_TIME + maxf(W.LADDER_DEPLOY_TIME, 0.5), 0.8, "CLIMB duration ~ walk + ladder + exit")
	h.check(at["IDLE"] - at["RETURN"] >= W.RETURN_CAMERA_TIME - 0.001, "RETURN lasts at least the camera glide (%.2f s)" % (at["IDLE"] - at["RETURN"]))
	h.eq(drops.size(), 1, "drop_started once")
	h.eq(returned.size(), 1, "return_ready exactly once")
	h.eq(finished.size(), 1, "finished exactly once")
	h.check(returned[0] <= finished[0], "return_ready comes before finished")
	fx["game"].cancel_pending()   # nobody committed this capture in the unit fixture
	await tree.process_frame
	_world_is_chess(h, fx, "after sequence")
	await _free(fx, tree)


# ---- the sequence presents the result it is given ------------------------------------------------------
static func _result_presentation(h, tree: SceneTree) -> void:
	for outcome in ["attacker", "defender"]:
		var fx := await _fixture(tree)
		var world: BattleWorld = fx["world"]
		var pit := world.pit
		var game: BattleMatch = fx["game"]
		h.begin("world pit: presents an %s win without deciding or changing anything" % outcome)
		var request := _capture_request(fx)
		var revision: int = game.revision
		var fen: String = game.engine.fen()
		var attacker_node: Node3D = world.piece_node(request.attacker.pieceId)
		var defender_node: Node3D = world.piece_node(request.defender.pieceId)
		pit.begin(request)
		h.check(_run_to(world, PitSequence.Phase.COMBAT, 0.3), "reaches COMBAT")
		pit.present_result({"outcome": "nonsense"})
		_step(world, 0.5)
		h.eq(pit.phase, PitSequence.Phase.COMBAT, "an invalid result is ignored; the sequence never picks a winner")
		pit.present_result({"outcome": outcome, "winnerPlayerId": request[outcome].playerId})
		pit.present_result({"outcome": "defender" if outcome == "attacker" else "attacker"})
		h.eq(pit.winner_index(), 0 if outcome == "attacker" else 1, "the first authoritative result wins; later ones are ignored")
		var returned := []
		pit.return_ready.connect(func(): returned.append(true))
		h.check(_run_to(world, PitSequence.Phase.RETURN, 0.8), "reaches the end of RETURN")
		var winner: Node3D = attacker_node if outcome == "attacker" else defender_node
		var loser: Node3D = defender_node if outcome == "attacker" else attacker_node
		h.check(winner.visible and winner.scale.is_equal_approx(Vector3.ONE), "the winner's mesh is back on the board")
		h.check(winner.position.distance_to(Interaction.world_position(Rules.index("e5"))) < 0.05, "the winner stands on the contested tile")
		h.check(not loser.visible, "the loser's mesh stays gone")
		h.eq(returned.size(), 1, "return_ready fired")
		_step(world, 3.0)
		h.check(pit.is_idle(), "sequence finished")
		h.eq(game.revision, revision, "the match revision is untouched by the presentation")
		h.eq(game.engine.fen(), fen, "the chess position is untouched by the presentation")
		h.eq(game.phase, "combat", "the pending capture is still the match's business (bridge commits it)")
		h.check(world.rig.state == CameraRig.State.CHESS_TOP_DOWN or world.rig.state == CameraRig.State.CHESS_PERSPECTIVE, "camera back in a chess state")
		game.cancel_pending()
		await tree.process_frame
		_world_is_chess(h, fx, outcome)
		await _free(fx, tree)


# ---- interruption at every phase ------------------------------------------------------------------------
static func _interruptions(h, tree: SceneTree) -> void:
	var fx := await _fixture(tree)
	var world: BattleWorld = fx["world"]
	var pit := world.pit
	var game: BattleMatch = fx["game"]
	h.begin("world pit: interruption at every phase restores a consistent top-down world")
	var request := _capture_request(fx)
	var baseline := {}
	# Warm up once so lazily built props exist, then take the node-count and geometry baseline.
	pit.begin(request)
	_run_to(world, PitSequence.Phase.COMBAT, 0.1)
	pit.abort("warm-up")
	_step(world, 1.0)
	baseline["nodes"] = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	baseline["geometry"] = _snapshot_board(fx["board"])
	var fen: String = game.engine.fen()
	var cases := [
		["CAPTURE_FOCUS", PitSequence.Phase.CAPTURE_FOCUS, 0.3, false],
		["TRAPDOOR_OPEN", PitSequence.Phase.TRAPDOOR_OPEN, 0.3, false],
		["DROP (falling)", PitSequence.Phase.DROP, 0.4, false],
		["DROP (landed)", PitSequence.Phase.DROP, 1.5, false],
		["COMBAT", PitSequence.Phase.COMBAT, 0.4, false],
		["RESOLVE", PitSequence.Phase.RESOLVE, 0.9, true],
		["CLIMB (ladder)", PitSequence.Phase.CLIMB, 1.0, true],
		["CLIMB (top)", PitSequence.Phase.CLIMB, 4.2, true],
		["RETURN (morph)", PitSequence.Phase.RETURN, 0.2, true],
		["RETURN (camera)", PitSequence.Phase.RETURN, 1.2, true],
	]
	for entry in cases:
		var label: String = entry[0]
		request = _capture_request(fx)
		var aborted := []
		pit.aborted.connect(func(reason: String): aborted.append(reason))
		h.check(pit.begin(request), label + ": begin")
		if entry[3]:
			_run_to(world, PitSequence.Phase.COMBAT, 0.2)
			pit.present_result({"outcome": "attacker"})
		h.check(_run_to(world, entry[1], entry[2]), label + ": reached")
		pit.abort("test")
		h.eq(aborted.size(), 1, label + ": aborted signal")
		_step(world, 0.6)   # recovery glide
		_world_is_chess(h, fx, label)
		h.check(not world.rig.is_transitioning() and world.rig.state == world.rig.chess_view, label + ": camera settled in the chess view")
		h.check(world.rig.camera.position.distance_to(world.rig.pose_for(world.rig.chess_view)["p"]) < 0.01, label + ": camera at the chess pose")
		h.eq(game.engine.fen(), fen, label + ": chess position untouched")
		h.eq(game.phase, "combat", label + ": pending capture untouched")
		var geometry := _snapshot_board(fx["board"])
		h.check(geometry == baseline["geometry"], label + ": board geometry identical to before")
		h.eq(Performance.get_monitor(Performance.OBJECT_NODE_COUNT), baseline["nodes"], label + ": no orphan nodes")
		h.check(pit.begin(request), label + ": a new sequence can start right after")
		pit.abort("cleanup")
		_step(world, 0.6)
		for conn in pit.aborted.get_connections():
			pit.aborted.disconnect(conn["callable"])
	# Disposal/cancel through the camera glide when the world is torn down mid-sequence.
	game.cancel_pending()
	await _free(fx, tree)


# ---- three captures in a row ------------------------------------------------------------------------------
static func _repeat_leaks(h, tree: SceneTree) -> void:
	var fx := await _fixture(tree)
	var world: BattleWorld = fx["world"]
	var pit := world.pit
	h.begin("world pit: three back-to-back captures leak no nodes")
	var counts := []
	var world_counts := []
	var geometry: Dictionary = {}
	for round in 3:
		var request := _capture_request(fx)
		pit.begin(request)
		_run_to(world, PitSequence.Phase.COMBAT, 0.2)
		pit.present_result({"outcome": "attacker" if round % 2 == 0 else "defender"})
		h.check(_run_to(world, PitSequence.Phase.IDLE, 0.0), "capture %d completes" % (round + 1))
		_step(world, 0.3)
		if round == 0:
			geometry = _snapshot_board(fx["board"])
		counts.append(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		world_counts.append(_count(world))
		h.check(_snapshot_board(fx["board"]) == geometry, "capture %d: tile and slab transforms unchanged" % (round + 1))
		# Restore the loser mesh the committed chess state would have removed.
		for id in fx["board"].pieces:
			fx["board"].pieces[id].visible = true
	h.eq(counts[1], counts[0], "global node count stable after capture 2")
	h.eq(counts[2], counts[0], "global node count stable after capture 3")
	h.eq(world_counts[2], world_counts[0], "world subtree size stable")
	var rest: int = fx["board"].tiles.size()
	h.eq(rest, 64, "all 64 tiles still present")
	fx["game"].cancel_pending()
	await _free(fx, tree)


# ---- the 2D (top-down) and 3D views of the world board -----------------------------------------------------------
static func _top_down_view(h, tree: SceneTree) -> void:
	var app = Main.instantiate()
	tree.root.size = Vector2i(1200, 800)
	tree.root.add_child(app)
	await tree.process_frame
	await tree.process_frame
	app.game.new_game(0)
	app.board_3d.animation_enabled = false
	app.board_2d.animation_enabled = false
	var board: ChessBoard3D = app.board_3d
	var world: BattleWorld = board.world
	world.auto_advance = false
	h.begin("world views: the 2D button is a top-down camera on the same 3D board")
	h.check(app.use_world, "world mode is the default")
	app.set_view(false)
	await tree.process_frame
	h.check(board.visible and not app.board_2d.visible, "the 3D board is shown for the 2D view")
	h.eq(world.rig.state, CameraRig.State.CHESS_TOP_DOWN, "top-down camera")
	await tree.physics_frame
	await tree.physics_frame
	for flipped in [false, true]:
		app.set_flipped(flipped)
		await tree.process_frame
		var bad := 0
		for at in 64:
			var screen := board.camera.unproject_position(Interaction.world_position(at) + Vector3(0, 0.04, 0))
			var local := screen * board.size / Vector2(board.viewport_3d.size)
			if board.square_at(local) != at:
				bad += 1
		h.eq(bad, 0, "every square resolves through a physics ray in the top-down view (flipped=%s)" % str(flipped))
	app.set_flipped(false)
	await tree.process_frame
	# Click e2 then e4 with the mouse path.
	var points := {}
	for sq in ["e2", "e4"]:
		var screen := board.camera.unproject_position(Interaction.world_position(Rules.index(sq)) + Vector3(0, 0.04, 0))
		points[sq] = screen * board.size / Vector2(board.viewport_3d.size)
	for sq in ["e2", "e4"]:
		for pressed in [true, false]:
			var event := InputEventMouseButton.new()
			event.position = points[sq]
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = pressed
			board._gui_input(event)
		if sq == "e2":
			h.eq(app.interaction.selected, Rules.index("e2"), "click selects the pawn")
			h.check(board.marks.get_child_count() >= 3, "legal-move dots / selection marks are drawn")
	h.check(app.game.engine.history.size() == 1 and app.game.engine.history[0].san == "e4", "click-click commits a legal move in top-down view")
	h.check(board.marks.get_child_count() >= 2, "last-move highlight is drawn")
	var before := board.camera.position
	board._orbit(Vector2(60, 30))
	h.check(board.camera.position == before, "orbit is ignored in the top-down view")
	app.set_view(true)
	await tree.process_frame
	h.eq(world.rig.state, CameraRig.State.CHESS_PERSPECTIVE, "3D button = perspective camera")
	var persp := board.camera.position
	board._orbit(Vector2(60, 30))
	h.check(board.camera.position != persp, "orbit works in the perspective view")
	h.check(app.game.match_state().phase != "x", "views never touch the match")
	app.set_view(false)
	app.board_3d.set_top_down(false)
	app.set_world_mode(false)
	h.check(app.board_2d.visible and not app.board_3d.visible, "legacy fallback: Board2D is available again")
	app.set_world_mode(true)
	app.queue_free()
	await tree.process_frame


# ---- one human seat: the rig follows the arena's single third-person camera -------------------------------------
static func _single_camera(h, tree: SceneTree) -> void:
	var fx := await _fixture(tree)
	var world: BattleWorld = fx["world"]
	var pit := world.pit
	pit.require_arena = true
	h.begin("world pit: single third-person camera (human vs AI seat) is followed by the rig")
	var request := _capture_request(fx)
	var arena: CombatArena = (load("res://combat/arena.tscn") as PackedScene).instantiate()
	arena.configure_seats({request.attacker.playerId: {"type": "human", "scheme": "kb1"}, request.defender.playerId: {"type": "ai", "skill": 0.6}})
	h.check(pit.begin(request), "begin")
	arena.battle_finished.connect(func(result: Dictionary): pit.present_result(result))  # what the bridge does
	world.chamber.arena_mount.add_child(arena)
	h.check(arena.embedded, "embedded flag set on mount")
	h.check(arena.start_battle(request)["ok"], "arena starts")
	h.check(not arena.is_physics_processing(), "the started arena's simulation is paused until DROP")
	pit.attach_arena(arena)
	h.check(not arena.hud.visible, "HUD hidden before COMBAT")
	var started_tick := arena.sim.server_tick
	var frames := 0
	var forced := false
	var follow_error := 1e9
	while frames < 3000 and not (forced and pit.is_idle()):
		frames += 1
		world.advance(DT)
		await tree.process_frame
		if pit.phase == PitSequence.Phase.TRAPDOOR_OPEN:
			h.eq(arena.sim.server_tick, started_tick, "no simulation tick before the trapdoor is open")
		if pit.phase == PitSequence.Phase.COMBAT and not forced:
			forced = true
			h.check(arena.hud.visible, "HUD visible in COMBAT")
			h.check(arena.cameras.size() == 1 and world.rig.follow == arena.cameras[0].camera, "rig follows the single third-person camera")
			follow_error = world.rig.camera.global_position.distance_to(arena.cameras[0].camera.global_position)
			h.check(follow_error < 0.35, "rig camera sits on the followed camera (%.3f m)" % follow_error)
			h.check(not arena.cameras[0].camera.current, "the arena camera is not the active one")
			if pit.winner_index() < 0:
				arena.sim.defender().health.apply_damage(100000)
		if pit.phase == PitSequence.Phase.RETURN and is_instance_valid(arena) and arena.get_parent() != null and pit._return_ready_sent:
			arena.stop_battle()
			arena.get_parent().remove_child(arena)
			arena.queue_free()
	h.check(forced and pit.is_idle(), "sequence completed (%d frames, phase %s, forced %s, t %.2f)" % [frames, PHASES[pit.phase], str(forced), pit._time])
	h.eq(Input.mouse_mode, Input.MOUSE_MODE_VISIBLE, "mouse released after the arena stopped")
	fx["game"].cancel_pending()
	await _free(fx, tree)


# ---- end to end through the real flow, adapter and CombatArena ---------------------------------------------------
static func _expected_fen(winner: String) -> String:
	var ref := BattleRules.new()
	ref.load_fen(FEN)
	var move: Dictionary = ref.inspect_move("d4", "e5", "q").move
	ref.settle_capture(move, winner)
	return ref.fen()


static func _boot_battle(tree: SceneTree) -> Dictionary:
	var app = Main.instantiate()
	tree.root.size = Vector2i(1200, 800)
	tree.root.add_child(app)
	await tree.process_frame
	await tree.process_frame
	app._switch_mode(1)
	app.game.new_game(0, 0, FEN)
	app.board_3d.animation_enabled = false
	var world: BattleWorld = app.board_3d.world
	world.auto_advance = false
	await tree.process_frame
	return {"app": app, "world": world}


## Plays the capture through the real UI entry point; `kill` = "attacker"|"defender"|"" (who is knocked out
## by damaging the real simulation, so the real CombatSimulation produces the BattleResult).
static func _fight(h, tree: SceneTree, ctx: Dictionary, kill: String, label: String, interrupt_in: int = -1) -> void:
	var app = ctx["app"]
	var world: BattleWorld = ctx["world"]
	var pit := world.pit
	app.game.play("d4", "e5")
	await tree.process_frame
	h.eq(app.battle_flow.phase, "preview", label + ": preview shown")
	h.check(app.battle_card.visible and app.fight_button.visible, label + ": preview card visible")
	var phases := []
	pit.phase_changed.connect(func(p: int): phases.append(PHASES[p]))
	app._start_battle_pressed()
	h.check(not pit.is_idle(), label + ": the pit started")
	var forced := false
	var frames := 0
	while frames < 3000:
		frames += 1
		world.advance(DT)
		await tree.process_frame
		if interrupt_in >= 0 and frames == interrupt_in:
			app.battle_flow.interrupt("test interrupt")
		if pit.phase == PitSequence.Phase.COMBAT and not forced and kill != "":
			forced = true
			var arena: CombatArena = world.chamber.arena_mount.get_child(0)
			h.check(arena.mode == CombatArena.Mode.AUTHORITY, label + ": the real arena runs in AUTHORITY mode inside the chamber")
			h.check(arena.global_position == Vector3.ZERO and arena.global_transform.basis.is_equal_approx(Basis.IDENTITY), label + ": arena at the world origin, unrotated, unscaled")
			h.check(arena.hud != null and arena.hud.visible, label + ": combat HUD visible during COMBAT")
			h.eq(world.rig.state, CameraRig.State.COMBAT_THIRD_PERSON, label + ": third-person camera")
			h.eq(world.find_children("*", "WorldEnvironment", true, false).size(), 1, label + ": a single WorldEnvironment (the embedded arena adds none)")
			var leaking := 0
			for light in arena.find_children("*", "Light3D", true, false):
				if light.light_cull_mask & W.LAYER_BOARD != 0:
					leaking += 1
			h.eq(leaking, 0, label + ": arena lights cannot light the chess board")
			h.check(arena.embedded, label + ": arena was mounted with embedded=true")
			var cameras_current := 0
			for cam in world.get_viewport().find_children("*", "Camera3D", true, false):
				if cam.current and cam.get_viewport() == world.get_viewport():
					cameras_current += 1
			h.eq(cameras_current, 1, label + ": exactly one current Camera3D in the shared world")
			h.check(world.rig.camera.current, label + ": the rig camera is the active one")
			var loser = arena.sim.defender() if kill == "defender" else arena.sim.attacker()
			loser.health.apply_damage(100000)
		if pit.is_idle() and app.battle_flow.phase == "board" and (forced or interrupt_in >= 0):
			break
	h.check(frames < 3000, label + ": finished in time (%d frames)" % frames)
	ctx["phases"] = phases


static func _end_to_end(h, tree: SceneTree) -> void:
	var saved_rate := Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = 600   # the arena ticks one logical 60 Hz tick per physics frame
	var counts := {}
	for scenario in [["attacker", false, false], ["defender", true, true]]:
		var kill: String = "defender" if scenario[0] == "attacker" else "attacker"
		var label: String = "e2e %s wins" % scenario[0]
		var ctx := await _boot_battle(tree)
		var app = ctx["app"]
		var world: BattleWorld = ctx["world"]
		app.set_view(scenario[1])
		app.set_flipped(scenario[2])
		await tree.process_frame
		var view_state: int = world.rig.state
		var nodes_before := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
		h.begin(label + ": local Battle Chess capture through BattleFlow + CombatArena")
		await _fight(h, tree, ctx, kill, label)
		var expected := _expected_fen(scenario[0])
		h.eq(app.game.engine.fen(), expected, label + ": chess position equals the BattleChessMatch post-battle position")
		h.eq(ctx["phases"], ["CAPTURE_FOCUS", "TRAPDOOR_OPEN", "DROP", "COMBAT", "RESOLVE", "CLIMB", "RETURN", "IDLE"], label + ": full phase order")
		h.eq(app.game.revision, 1, label + ": the result was committed exactly once")
		h.eq(app.game.phase, "board", label + ": match is back on the board")
		h.check(app.interaction.enabled, label + ": board input re-enabled")
		h.eq(world.rig.state, view_state, label + ": returned to the previously selected chess view")
		h.check(app._view_3d == scenario[1] and app._flipped == scenario[2], label + ": view and flip preserved")
		h.eq(world.chamber.arena_mount.get_child_count(), 0, label + ": arena removed from the chamber")
		await tree.process_frame
		await tree.process_frame
		_world_is_chess(h, {"world": world, "board": app.board_3d, "game": app.game}, label)
		var pieces := []
		for p in app.game.chess_state().pieces:
			pieces.append(p.square)
		pieces.sort()
		h.eq(pieces, ["e5" if scenario[0] == "attacker" else "e5", "h1", "h8"], label + ": survivors on the board")
		# The survivor on e5 is the right colour.
		var survivor: String = app.game.engine.board[Rules.index("e5")]
		h.eq(survivor, "P" if scenario[0] == "attacker" else "q", label + ": the winner's piece stands on e5")
		ctx["app"].queue_free()
		await tree.process_frame
		await tree.process_frame
		counts[scenario[0]] = nodes_before

	# Interruptions through the real flow: cancel in COMBAT, adapter failure (disconnect), chess change.
	for case in [["interrupt during the descent", 150], ["interrupt in combat", 330]]:
		var ctx := await _boot_battle(tree)
		var app = ctx["app"]
		var world: BattleWorld = ctx["world"]
		var label: String = "e2e " + case[0]
		h.begin(label + ": the board survives an interrupted battle")
		var fen_before: String = app.game.engine.fen()
		await _fight(h, tree, ctx, "", label, case[1])
		for _i in 40:
			world.advance(DT)
			await tree.process_frame
		h.eq(app.game.engine.fen(), fen_before, label + ": chess position untouched")
		h.eq(app.game.phase, "board", label + ": pending capture cancelled by the flow")
		h.eq(world.chamber.arena_mount.get_child_count(), 0, label + ": arena removed")
		_world_is_chess(h, {"world": world, "board": app.board_3d, "game": app.game}, label)
		ctx["app"].queue_free()
		await tree.process_frame
	# A failing adapter (lost link / crashed arena) aborts the presentation too.
	var ctx := await _boot_battle(tree)
	var app = ctx["app"]
	var world: BattleWorld = ctx["world"]
	h.begin("e2e adapter failure: presentation aborts and the board is consistent")
	app.game.play("d4", "e5")
	await tree.process_frame
	app._start_battle_pressed()
	for _i in 120:
		world.advance(DT)
		await tree.process_frame
	app.battle_adapter.failed.emit("simulated disconnect")
	await tree.process_frame
	for _i in 40:
		world.advance(DT)
		await tree.process_frame
	h.eq(app.game.engine.fen(), FEN, "chess position untouched after a failure")
	_world_is_chess(h, {"world": world, "board": app.board_3d, "game": app.game}, "after failure")
	app.queue_free()
	await tree.process_frame
	Engine.physics_ticks_per_second = saved_rate
