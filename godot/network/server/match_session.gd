class_name OnlineMatchSession
extends Node
## One server-owned chess match and isolated combat world. No rendering or client winners.
signal changed
signal combat_snapshot(snapshot: Dictionary)
signal battle_receipt(result: Dictionary)
const Classic = preload("res://chess/classic_match.gd")
const Battle = preload("res://chess/battle_match.gd")
const Royal = preload("res://chess/battle_royal_match.gd")
const Rules = preload("res://chess/chess_engine.gd")
const Sim = preload("res://combat/core/combat_simulation.gd")
const CombatHost = preload("res://combat/net/combat_net_server.gd")
const Profile = preload("res://combat/core/fighter_profile.gd")
const Balance = preload("res://combat/data/balance_data.gd")
var game: ClassicMatch
var status = "waiting"
var readiness = {"w": false, "b": false}
var connected = {"w": true, "b": false}
var missing_since = {"w": -1, "b": -1}
var draw_offer: Variant = null
var tick = 0
var frame_sequence = 0
var created_ms = 0
var completed_ms = -1
var sim: CombatSimulation
var combat_host: RefCounted
var receipts: Array = []
var _world: SubViewport
var _aftermath_end = 0
var _retired_battle_id = ""
var _now = 0

static func supported_roles() -> Array:
	var roles = []
	for role in ["p", "n", "b", "r", "q"]:
		if Profile.supports_role(role):
			roles.append(role)
	return roles

## `ruleset` "battle-royal-v1" (mode "battle" only) runs the king's last-stand sequence authoritatively here: the server
## owns the King's HP/stamina/cooldown carry-over. It is opt-in and in-process: the v1 wire schemas cannot carry the
## sequence yet (docs/architecture/BATTLE_ROYAL_V1.md), so the dedicated server never passes it.
func configure(id: String, mode: String, creator: String, base_ms: int, increment_ms: int, now: int, ruleset: String = "battle-checkmate-v1") -> void:
	created_ms = now
	_now = now
	game = (Royal.new() if ruleset == Royal.RULESET_ID else Battle.new()) if mode == "battle" else Classic.new()
	game.new_game(base_ms, increment_ms)
	game.match_id = id
	game.players = {"w": creator, "b": "open-" + id}
	game.authority_mode = "server"
	game.allow_undo = false
	game.last_poll = now
	game.changed.connect(_changed)
	game.move_committed.connect(func(_move): draw_offer = null)
	_world = SubViewport.new()
	_world.own_world_3d = true
	_world.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_world.size = Vector2i(1, 1)
	add_child(_world)

func _changed() -> void:
	if not game.engine.result.is_empty():
		status = "complete"
		if completed_ms < 0:
			completed_ms = _now
	changed.emit()

func color_of(player_id: String) -> String:
	for color in ["w", "b"]:
		if game.players[color] == player_id:
			return color
	return ""

func join(player_id: String, now: int) -> Dictionary:
	if status != "waiting" or connected.b or not game.players.b.begins_with("open-"):
		return error("FORBIDDEN", "The match has no open seat.")
	game.players.b = player_id
	set_connected(player_id, true, now)
	return {"ok": true}

func set_connected(player_id: String, present: bool, now: int) -> void:
	var color = color_of(player_id)
	if color.is_empty():
		return
	connected[color] = present
	missing_since[color] = -1 if present else now
	if combat_host != null:
		combat_host.set_seat_connected(player_id, present)
	changed.emit()

func command(payload: Dictionary, player_id: String, now: int) -> Dictionary:
	_now = now
	var color = color_of(player_id)
	if color.is_empty():
		return error("FORBIDDEN", "Not a member of this match.")
	if payload.action == "ready":
		if status == "complete":
			return error("WRONG_PHASE", "The match is complete.")
		if status == "active":
			return {"ok": true}
		readiness[color] = true
		if readiness.w and readiness.b and connected.w and connected.b:
			status = "active"
			game.started = true
			game.last_poll = now
		changed.emit()
		return {"ok": true}
	if status != "active":
		return error("WRONG_PHASE", "Both seats must be ready in a live match.")
	if payload.action == "resign":
		finish("0-1" if color == "w" else "1-0", "Resignation", now)
		return {"ok": true}
	if not game.board_input_allowed():
		return error("WRONG_PHASE", "Wait for the battle to settle.")
	match payload.action:
		"offer_draw":
			draw_offer = player_id
			changed.emit()
		"accept_draw":
			if draw_offer == null or draw_offer == player_id:
				return error("FORBIDDEN", "Only the opponent may accept a pending draw offer.")
			finish("1/2-1/2", "Draw by agreement", now)
		"claim_draw":
			if game is BattleChessMatch or game.players[game.engine.turn] != player_id:
				return error("FORBIDDEN", "Only the acting Classic seat may claim a draw.")
			game.poll_clock(now)
			if not game.engine.result.is_empty():
				return error("WRONG_PHASE", "The clock has expired.")
			var intended: Dictionary = payload.intended.duplicate(true) if payload.intended != null else {}
			if intended.get("promotion") == null:
				intended.erase("promotion")
			if not game.engine.claim_draw(payload.drawKind if payload.drawKind != null else "", intended):
				return error("ILLEGAL_MOVE", "That draw cannot be claimed.")
			_changed()
	return {"ok": true}

func move(payload: Dictionary, player_id: String, now: int) -> Dictionary:
	_now = now
	if status != "active":
		return error("WRONG_PHASE", "Both players must be ready before moving.")
	if payload.matchId != game.match_id or payload.playerId != player_id or color_of(player_id).is_empty():
		return error("FORBIDDEN", "The move does not belong to this seat and match.")
	# Reject unsupported combat before preparing a frozen transaction or recording a retry.
	if game is BattleChessMatch and game.board_input_allowed() and payload.expectedRevision == game.revision and game.players[game.engine.turn] == player_id:
		var inspected = game.engine.inspect_move(payload.from, payload.to, payload.promotion if payload.promotion != null else "q")
		if inspected.ok and game.engine.is_capture(inspected.move):
			var m: Dictionary = inspected.move
			var victim: int = m.to + (-8 if game.engine.turn == "w" else 8) if m.flag == "ep" else m.to
			for at in [m.from, victim]:
				if not Profile.supports_role(game.engine.board[at].to_lower()):
					return error("ILLEGAL_MOVE", "This fighter's combat mechanics are not available on the server yet.")
	game.poll_clock(now)
	game.server_tick = tick
	var response = game.submit_request(payload, player_id, now)
	_ensure_combat()
	return response

## Starts the authoritative simulation for a freshly prepared battle (also the next duel of a royal sequence).
func _ensure_combat() -> void:
	if status == "active" and game is BattleChessMatch and game.phase == "combat" and not game.pending_request().is_empty() and sim == null:
		_start_combat()

func _start_combat() -> void:
	sim = Sim.new()
	_world.add_child(sim)
	game.bind_combat_authority(sim)
	combat_host = CombatHost.new(sim)
	combat_host.snapshot_ready.connect(_combat_snapshot)
	combat_host.seat_abandoned.connect(func(player): finish("0-1" if color_of(player) == "w" else "1-0", "Combat input timeout", _now))
	combat_host.battle_aborted_draw.connect(func(): finish("1/2-1/2", "Both combat seats abandoned", _now))
	var options: Dictionary = game.combat_options()
	var reply = combat_host.start(game.pending_request()) if options.is_empty() else combat_host.start(game.pending_request(), options)
	if not reply.ok:
		finish("1/2-1/2", "Service aborted: combat initialization failed", _now)
		return
	for color in ["w", "b"]:
		# Always override clientTick-based estimates with transport-owned RTT.
		combat_host.set_seat_rtt_ms(game.players[color], 0)
		combat_host.set_seat_connected(game.players[color], connected[color])
	var request: Dictionary = game.pending_request()
	_log("BATTLE_START", {"matchId": game.match_id, "battleId": request.battleId, "startTick": request.startTick, "attacker": request.attacker.role, "defender": request.defender.role, "attackerPlayerId": request.attacker.playerId, "defenderPlayerId": request.defender.playerId})

func _combat_snapshot(snapshot: Dictionary) -> void:
	if sim == null or not game.accept_snapshot(snapshot, sim):
		finish("1/2-1/2", "Service aborted: invalid combat snapshot", _now)
		return
	combat_snapshot.emit(snapshot)

func input(payload: Dictionary, player_id: String) -> Dictionary:
	if payload.playerId != player_id or color_of(player_id).is_empty() or payload.matchId != game.match_id:
		return error("FORBIDDEN", "No active battle for this authenticated seat.")
	# A valid packet already in flight can arrive after knockout/return. It must
	# not become an error banner, a new action, or input to a subsequent duel.
	if payload.battleId == _retired_battle_id or (sim != null and not sim.is_running() and payload.battleId == sim.request.battleId):
		return {"ok": true, "ignored": true}
	if status != "active" or sim == null or combat_host == null:
		return error("FORBIDDEN", "No active battle for this authenticated seat.")
	return combat_host.receive_input(player_id, payload)

func step(now: int) -> void:
	_now = now
	if status == "complete":
		return
	check_disconnections(now)
	if status == "complete":
		return
	_ensure_combat() # a duel prepared without a move (a loaded mate position) gets its simulation here
	tick += 1
	if tick >= 2147477000 or game.engine.history.size() >= 4096:
		finish("1/2-1/2", "Service aborted: protocol counter limit", now)
		return
	if game is BattleChessMatch and game.phase == "combat" and sim != null:
		combat_host.step()
		if sim == null or status == "complete":
			return
		if not sim.result.is_empty():
			if not game.accept_result(sim.result, sim).ok:
				finish("1/2-1/2", "Service aborted: invalid combat result", now)
				return
			_log("BATTLE_DONE", {"matchId": game.match_id, "battleId": sim.request.battleId, "result": sim.result, "net": combat_host.diagnostics()})
			receipts.append(sim.result.duplicate(true))
			if receipts.size() > 32:
				receipts.pop_front()
			battle_receipt.emit(sim.result.duplicate(true))
			_aftermath_end = tick + 120
	elif game is BattleChessMatch and game.phase == "aftermath":
		if tick >= _aftermath_end:
			if not game.commit_battle().ok:
				finish("1/2-1/2", "Service aborted: combat settlement failed", now)
			_stop_combat()
			_ensure_combat()
	else:
		game.poll_clock(now)
	game.server_tick = tick
	game.last_poll = now

func check_disconnections(now: int) -> void:
	if status != "active":
		return
	for color in ["w", "b"]:
		if not connected[color] and missing_since[color] >= 0 and now - missing_since[color] >= 10000:
			if not connected.w and not connected.b:
				finish("1/2-1/2", "Both players disconnected", now)
			else:
				finish("0-1" if color == "w" else "1-0", "Disconnect timeout", now)
			return

func finish(result: String, reason: String, now: int) -> void:
	if status == "complete":
		return
	if game is BattleChessMatch:
		if game.phase == "aftermath":
			game.commit_battle()
		if not game.engine.result.is_empty():
			_stop_combat()
			return
		if sim != null and combat_host != null and sim.is_running():
			_log("BATTLE_ABORT", {"matchId": game.match_id, "battleId": sim.request.battleId, "reason": reason, "net": combat_host.diagnostics()})
		game.abandon_pending()
	_stop_combat()
	game.engine.result = result
	game.engine.reason = reason
	status = "complete"
	completed_ms = now
	draw_offer = null
	_changed()

## One structured line per combat event on the server's stdout (operators and the online test harness read these). The
## tuning stamp ("balance-v1:<hash>") names the exact combat balance this process simulates: a client built with another
## tuning would mispredict, and v1 messages carry no field to negotiate it (see docs/network/ONLINE_COMBAT.md).
func _log(tag: String, data: Dictionary) -> void:
	data["tuning"] = Balance.stamp()
	print("COMBAT_", tag, " ", JSON.stringify(data, "", true))

func _stop_combat() -> void:
	if sim != null:
		_retired_battle_id = sim.request.get("battleId", "")
		game.bind_combat_authority(null)
		sim.stop()
		_world.remove_child(sim)
		sim.queue_free()
		sim = null
	combat_host = null

func frame(player_id: String) -> Dictionary:
	frame_sequence += 1
	var resume: Variant = null
	if combat_host != null:
		resume = combat_host.input_resume(player_id)
	return {"schemaVersion": 1, "frameSequence": frame_sequence, "status": status, "state": game.match_state(), "clocks": game.clock_state(), "connected": connected.duplicate(), "ready": readiness.duplicate(), "drawOffer": draw_offer, "inputResume": resume}

func error(code: String, message: String) -> Dictionary:
	return {"ok": false, "error": {"schemaVersion": 1, "code": code, "message": message, "requestId": null, "currentRevision": game.revision, "retryable": code in ["STALE_REVISION", "WRONG_PHASE"]}}

func _exit_tree() -> void:
	_stop_combat()
