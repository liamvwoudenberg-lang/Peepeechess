extends SceneTree
## Independent process using the production client. No direct access to server state.
const Client = preload("res://network/client/network_client.gd")
const Remote = preload("res://network/client/remote_match.gd")
var client
var game
var options = {}
var seat = "w"
var scenario = "classic"
var reports: Dictionary = {"boards":{}, "battles":{}, "errors":[], "welcomes":0, "reconnected":false, "forgeryRejected":false, "damageRejected":false}
var _created = false
var _joined = false
var _ready_sent = false
var _sent_revision = -1
var _deadline = 0
var _reconnect_triggered = false
var _forgery_sent = false
var _last_bad_sent = -2000
var _bad_attempts = 0
var _closing = false
const CLASSIC_MOVES = [["f2","f3"],["e7","e5"],["g2","g4"],["d8","h4"]]
const BATTLE_MOVES = [["e2","e4"],["d7","d5"],["e4","d5"],["g8","f6"],["d2","d4"],["f6","d5"],["c2","c4"],["e7","e5"],["d5","e6"],["c7","c6"],["d4","d5"],["c6","d5"]]
func _init() -> void:
	call_deferred("run")
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts = arg.trim_prefix("--").split("=", true, 1)
		options[parts[0]] = parts[1] if parts.size() > 1 else "true"
	seat = options.get("seat", "w")
	scenario = options.get("scenario", "classic")
	_deadline = Time.get_ticks_msec() + 150000
	client = Client.new()
	root.add_child(client)
	game = Remote.new()
	game.bind(client)
	client.session_ready.connect(_welcome)
	client.frame_received.connect(_frame)
	client.battle_result_received.connect(func(result): reports.battles[result.battleId] = result.duplicate(true))
	client.protocol_error.connect(_error)
	reports["connectionEvents"] = []
	client.connection_changed.connect(func(connected): reports.connectionEvents.append({"connected":connected, "ms":Time.get_ticks_msec()}))
	if client.connect_server("127.0.0.1", int(options.port), options.ca) != OK:
		finish(false, "could not connect")
func _welcome(_value: Dictionary) -> void:
	reports.welcomes += 1
	if reports.welcomes > 1:
		reports.reconnected = true
	if seat == "w" and not _created:
		_created = true
		client.create_match("battle" if scenario == "battle" else "classic", 0 if scenario == "battle" else (1000 if scenario == "clock" else 60000))
func _frame(frame: Dictionary) -> void:
	if _closing:
		return
	if seat == "w":
		var file = FileAccess.open(options.invite, FileAccess.WRITE)
		file.store_string(frame.state.matchId)
		file.close()
	reports.boards[str(frame.state.chess.revision)] = frame.state.chess.duplicate(true)
	if frame.state.phase == "aftermath" and frame.state.combat != null and frame.state.combat.result != null:
		reports.battles[frame.state.combat.battleId] = frame.state.combat.result.duplicate(true)
	if not _ready_sent:
		_ready_sent = true
		client.command("ready")
	if frame.status == "complete":
		reports.final = frame.state.duplicate(true)
		return
	if frame.status != "active" or frame.state.phase != "board" or frame.state.players[game.engine.turn] != client.player_id or _sent_revision == frame.state.chess.revision:
		return
	if scenario == "clock":
		return
	var moves = BATTLE_MOVES if scenario == "battle" else CLASSIC_MOVES
	var ply: int = frame.state.chess.ply
	if ply < moves.size():
		_sent_revision = frame.state.chess.revision
		client.chess_move(moves[ply][0], moves[ply][1])
	elif seat == "w" and scenario == "battle":
		_sent_revision = frame.state.chess.revision
		client.command("resign")
func _error(value: Dictionary) -> void:
	if value.code == "FORBIDDEN" and _forgery_sent and "authoritative state or results" in value.message:
		reports.forgeryRejected = true
	elif value.code == "INVALID_PAYLOAD" and _forgery_sent:
		reports.damageRejected = true
	elif value.code == "FORBIDDEN" and not client.authenticated and reports.welcomes > 0:
		pass # Resume can race the previous transport's three-second liveness timeout.
	else:
		reports.errors.append(value.code + ": " + value.message)
		if value.code == "UNAUTHENTICATED":
			finish(false, value.message)
func _physics_process(_delta: float) -> bool:
	if client == null or _closing or not client.authenticated or client.frame.is_empty() or client.frame.state.phase != "combat" or client.input_builder == null or client.latest_combat.is_empty():
		return false
	var snapshot: Dictionary = client.latest_combat
	var request: Dictionary = client.frame.state.battle
	if seat == "w" and scenario == "battle" and not _reconnect_triggered and snapshot.countdownTicksRemaining < 120:
		_reconnect_triggered = true
		client.reconnect_session()
		return false
	if seat == "b" and not _forgery_sent:
		_forgery_sent = true
		var forged = {"schemaVersion":1,"matchId":request.matchId,"battleId":request.battleId,"expectedRevision":request.expectedRevision,"resolvedTick":request.startTick + 180,"winnerPlayerId":client.player_id,"outcome":"defender","reason":"knockout","attackerHp":0,"defenderHp":request.defender.stats.maxHp}
		client.transport.send(client.transport.server_peer, client.wire.pack("BattleResult", forged), true)
	if seat == "b" and not reports.damageRejected and _bad_attempts < 6 and Time.get_ticks_msec() - _last_bad_sent >= 1100:
		_last_bad_sent = Time.get_ticks_msec()
		_bad_attempts += 1
		var bad = client.input_builder.build(0, 0, 0, true, false, false)
		bad["damage"] = 99999
		client.transport.send(client.transport.server_peer, JSON.stringify({"type":"CombatInput","payload":bad}).to_utf8_buffer(), false)
	var me: Dictionary
	var opponent: Dictionary
	for fighter in snapshot.fighters:
		if fighter.playerId == client.player_id:
			me = fighter
		else:
			opponent = fighter
	if me.is_empty() or opponent.is_empty():
		return false
	var winning: Dictionary = request.defender if request.from == "f6" else request.attacker
	var delta = Vector3(opponent.position.x - me.position.x, 0, opponent.position.z - me.position.z)
	var movement = delta.normalized() if winning.playerId == client.player_id and delta.length() > 1.15 else Vector3.ZERO
	if winning.playerId == client.player_id and snapshot.countdownTicksRemaining == 0 and client.input_builder.client_tick % 40 == 0:
		client.input_builder.press("light")
	client.submit_combat_input(client.input_builder.build(movement.x, movement.z, atan2(delta.x, delta.z), true, false, false))
	return false
func _process(_delta: float) -> bool:
	if _closing:
		return false
	if reports.has("final"):
		var expected = reports.final.chess.history.filter(func(entry): return entry.outcome != "quiet").size() if scenario == "battle" else 0
		if reports.battles.size() >= expected:
			finish(true)
		return false
	if client != null and client.authenticated and seat == "b" and not _joined and FileAccess.file_exists(options.invite):
		var id = FileAccess.get_file_as_string(options.invite).strip_edges()
		if not id.is_empty():
			_joined = true
			client.join_match(id)
	if _deadline > 0 and Time.get_ticks_msec() >= _deadline:
		finish(false, "scenario timed out")
	return false
func finish(ok: bool, message: String = "") -> void:
	if _closing:
		return
	_closing = true
	reports.ok = ok
	reports.message = message
	reports.seat = seat
	reports.scenario = scenario
	var file = FileAccess.open(options.report, FileAccess.WRITE)
	file.store_string(JSON.stringify(reports, "", true, true))
	file.close()
	print("CLIENT_DONE seat=", seat, " scenario=", scenario, " ok=", ok)
	if client != null:
		await client.disconnect_gracefully()
	quit(0 if ok else 1)
