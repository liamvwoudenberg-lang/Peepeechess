class_name OnlineChessClient
extends Node
## Protocol/session client independent of board scenes, input devices and rendering.
signal session_ready(welcome: Dictionary)
signal frame_received(frame: Dictionary)
signal combat_received(snapshot: Dictionary)
signal battle_result_received(result: Dictionary)
signal clocks_received(clocks: Dictionary)
signal acknowledged(ack: Dictionary)
signal protocol_error(error: Dictionary)
signal connection_changed(connected: bool)
const Wire = preload("res://network/wire_codec.gd")
const Transport = preload("res://network/enet_transport.gd")
const Builder = preload("res://combat/core/combat_input_builder.gd")
var wire = Wire.new()
var transport: ChessEnetTransport
var authenticated = false
var player_id = ""
var session_token = ""
var _account_ticket = ""
var server_id = ""
var combat_roles: Array = []
var frame: Dictionary = {}
var latest_combat: Dictionary = {}
var battle_results: Dictionary = {}
var input_builder: CombatInputBuilder
var pending: Dictionary = {}
var address = "localhost"
var port = 2456
var ca_path = ""
var insecure_local = false
var auto_reconnect = true
var _wanted = false
var _retry_at = 0
var _retry_delay = 250
var _retry_until = 0
var _started = 0
var _last_receive = 0
var _last_ping = 0
var _nonce = 0
var _serial = 0
var _last_frame_sequence = 0
var _latest_clock: Dictionary = {}

func _ready() -> void:
	transport = Transport.new()
	add_child(transport)
	transport.connected.connect(_connected)
	transport.disconnected.connect(func(_id): _lost())
	transport.transport_error.connect(func(_message): _lost())
	transport.packet_received.connect(_packet)

func connect_server(hostname: String, server_port: int = 2456, certificate_authority: String = "", allow_loopback_plaintext: bool = false) -> Error:
	address = hostname
	port = server_port
	ca_path = certificate_authority
	insecure_local = allow_loopback_plaintext
	_wanted = true
	_retry_until = Time.get_ticks_msec() + 15000
	return _connect()

func connect_account_server(hostname: String, server_port: int, ticket: String, certificate_authority: String = "", allow_loopback_plaintext: bool = false) -> void:
	disconnect_server(true)
	_account_ticket = ticket
	connect_server(hostname, server_port, certificate_authority, allow_loopback_plaintext)

func _connect() -> Error:
	authenticated = false
	_started = Time.get_ticks_msec()
	_last_receive = _started
	var result = transport.connect_to(address, port, ca_path, insecure_local)
	if result != OK:
		_wanted = false
		protocol_error.emit(_error("INTERNAL", "Unable to create a secure ENet connection: " + error_string(result)))
	return result

func _connected(id: int) -> void:
	if id != transport.server_peer:
		return
	if not _account_ticket.is_empty() and session_token.is_empty():
		_send("AccountHello", {"schemaVersion": 1, "protocol": "peepeechess-enet-v1", "ticket": _account_ticket})
		return
	_send("Hello", {"schemaVersion": 1, "protocol": "peepeechess-enet-v1", "resumeToken": session_token if not session_token.is_empty() else null})

func _lost() -> void:
	if transport != null:
		transport.close()
	var was_connected = authenticated
	authenticated = false
	if was_connected:
		_retry_until = Time.get_ticks_msec() + 12000
	connection_changed.emit(false)
	if _wanted and auto_reconnect:
		_retry_at = Time.get_ticks_msec() + _retry_delay
		_retry_delay = mini(1000, _retry_delay * 2)

func disconnect_server(forget: bool = false) -> void:
	_wanted = false
	_retry_at = 0
	if transport != null:
		transport.close()
	authenticated = false
	connection_changed.emit(false)
	if forget:
		session_token = ""
		_account_ticket = ""
		player_id = ""
		server_id = ""
		frame.clear()
		latest_combat.clear()
		battle_results.clear()
		input_builder = null
		pending.clear()
		_last_frame_sequence = 0
		_latest_clock.clear()

func reconnect_session() -> void:
	if authenticated:
		transport.disconnect_gracefully(transport.server_peer)

func disconnect_gracefully() -> void:
	_wanted = false
	_retry_at = 0
	authenticated = false
	connection_changed.emit(false)
	var id = transport.server_peer
	transport.disconnect_gracefully(id)
	var deadline = Time.get_ticks_msec() + 2000
	while transport.host != null and transport.peers.has(id) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	transport.close()

func _packet(id: int, bytes: PackedByteArray, channel: int, flags: int) -> void:
	if id != transport.server_peer:
		return
	var parsed = wire.unpack(bytes, Wire.MAX_SERVER_BYTES)
	if not parsed.ok or parsed.type not in Wire.SERVER_TYPES:
		protocol_error.emit(_error("INVALID_PAYLOAD", "The server sent an invalid message."))
		return
	var reliable = parsed.type not in ["CombatSnapshot", "ClockSync"]
	if channel != (0 if reliable else 1) or bool(flags & ENetPacketPeer.FLAG_RELIABLE) != reliable:
		return
	_last_receive = Time.get_ticks_msec()
	var payload: Dictionary = parsed.payload
	if parsed.type == "Welcome":
		if (not player_id.is_empty() and payload.playerId != player_id) or (not server_id.is_empty() and payload.serverId != server_id):
			protocol_error.emit(_error("UNAUTHENTICATED", "Server identity/session changed; start a new session explicitly."))
			disconnect_server()
			return
		player_id = payload.playerId
		session_token = payload.sessionToken
		_account_ticket = ""
		server_id = payload.serverId
		combat_roles = payload.combatRoles.duplicate()
		authenticated = true
		_retry_delay = 250
		_retry_at = 0
		_last_frame_sequence = 0
		connection_changed.emit(true)
		session_ready.emit(payload.duplicate(true))
		for entry in pending.values():
			entry.retryAt = 0
		return
	if parsed.type == "ProtocolError":
		if payload.requestId != null:
			pending.erase(payload.requestId)
		protocol_error.emit(payload.duplicate(true))
		if not authenticated:
			if payload.code == "FORBIDDEN" and not session_token.is_empty():
				_lost() # Old transport may still be within its heartbeat timeout.
			else:
				disconnect_server()
		return
	if not authenticated:
		return
	match parsed.type:
		"Ack":
			pending.erase(payload.requestId)
			acknowledged.emit(payload.duplicate(true))
		"MatchFrame":
			if frame.get("state", {}).get("matchId") == payload.state.matchId and payload.frameSequence <= _last_frame_sequence:
				return
			if player_id not in payload.state.players.values():
				return
			_last_frame_sequence = payload.frameSequence
			if not frame.is_empty() and frame.state.matchId != payload.state.matchId:
				battle_results.clear()
				_latest_clock.clear()
			frame = payload.duplicate(true)
			if _latest_clock.get("matchId") == frame.state.matchId and _latest_clock.serverTick > frame.state.serverTick:
				frame.clocks = _latest_clock.clocks.duplicate(true)
			if frame.state.battle != null:
				_restore_input(frame)
				if frame.state.combat != null and (latest_combat.get("battleId") != frame.state.combat.battleId or latest_combat.get("serverTick", -1) <= frame.state.combat.serverTick):
					latest_combat = frame.state.combat.duplicate(true)
			else:
				latest_combat.clear()
				input_builder = null
			frame_received.emit(frame.duplicate(true))
			if frame.state.combat != null and frame.state.combat.result != null:
				_receipt(frame.state.combat.result)
		"CombatSnapshot":
			if frame.is_empty() or frame.state.phase not in ["combat", "aftermath"] or frame.state.battle == null or payload.matchId != frame.state.matchId or payload.battleId != frame.state.battle.battleId or payload.serverTick <= latest_combat.get("serverTick", -1):
				return
			latest_combat = payload.duplicate(true)
			combat_received.emit(payload.duplicate(true))
			if payload.result != null:
				_receipt(payload.result)
		"BattleResult":
			_receipt(payload)
		"ClockSync":
			if frame.is_empty() or payload.matchId != frame.state.matchId or payload.serverTick < frame.state.serverTick or payload.serverTick < _latest_clock.get("serverTick", -1):
				return
			_latest_clock = payload.duplicate(true)
			frame.clocks = payload.clocks.duplicate(true)
			frame.connected = payload.connected.duplicate()
			clocks_received.emit(payload.duplicate(true))

func _receipt(result: Dictionary) -> void:
	# Trusted-server receipt is presentation data, never a board settlement path.
	if frame.is_empty() or result.matchId != frame.state.matchId or result.winnerPlayerId not in frame.state.players.values():
		return
	if battle_results.has(result.battleId):
		if battle_results[result.battleId] != result:
			protocol_error.emit(_error("INVALID_PAYLOAD", "Conflicting authoritative battle receipt."))
		return
	battle_results[result.battleId] = result.duplicate(true)
	battle_result_received.emit(result.duplicate(true))

func _restore_input(value: Dictionary) -> void:
	var battle: Dictionary = value.state.battle
	if input_builder == null or input_builder.battle_id != battle.battleId:
		input_builder = Builder.new(value.state.matchId, battle.battleId, player_id)
	var resume = value.inputResume
	if resume != null and resume.battleId == battle.battleId:
		input_builder.sequence = maxi(input_builder.sequence, int(resume.sequence))
		input_builder.client_tick = maxi(input_builder.client_tick, int(resume.clientTick))
		for action in input_builder.counters:
			input_builder.counters[action] = maxi(input_builder.counters[action], int(resume[action]))

func request(type_name: String, payload: Dictionary) -> String:
	var id: String = payload.get("requestId", payload.get("commandId", ""))
	if not authenticated or type_name not in ["CreateMatch", "JoinMatch", "MatchCommand", "ChessMoveRequest"] or not wire.valid(type_name, payload):
		protocol_error.emit(_error("INVALID_PAYLOAD", "Cannot submit this command before authentication or with invalid fields."))
		return ""
	pending[id] = {"type": type_name, "payload": payload.duplicate(true), "retryAt": Time.get_ticks_msec() + 1000, "expires": Time.get_ticks_msec() + 15000}
	_send(type_name, payload)
	return id

func _id() -> String:
	_serial += 1
	return "cmd-" + str(Time.get_ticks_usec()) + "-" + str(_serial)

func create_match(mode: String, base_ms: int = 600000, increment_ms: int = 0) -> String:
	return request("CreateMatch", {"schemaVersion": 1, "commandId": _id(), "mode": mode, "initialMs": base_ms, "incrementMs": increment_ms})

func join_match(match_id: String) -> String:
	return request("JoinMatch", {"schemaVersion": 1, "commandId": _id(), "matchId": match_id})

func command(action: String, kind: Variant = null, intended: Variant = null) -> String:
	if frame.is_empty():
		return ""
	return request("MatchCommand", {"schemaVersion": 1, "commandId": _id(), "matchId": frame.state.matchId, "action": action, "drawKind": kind, "intended": intended})

func chess_move(from: String, to: String, promotion: String = "q") -> String:
	if frame.is_empty():
		return ""
	return request("ChessMoveRequest", {"schemaVersion": 1, "requestId": _id(), "matchId": frame.state.matchId, "playerId": player_id, "expectedRevision": frame.state.chess.revision, "from": from, "to": to, "promotion": promotion})

func submit_combat_input(packet: Dictionary) -> Dictionary:
	if not authenticated or packet.get("playerId") != player_id or not wire.valid("CombatInput", packet):
		return {"ok": false}
	return {"ok": _send("CombatInput", packet, false) == OK}

func _send(type_name: String, payload: Dictionary, reliable: bool = true) -> Error:
	return transport.send(transport.server_peer, wire.pack(type_name, payload), reliable)

func _process(_delta: float) -> void:
	var now = Time.get_ticks_msec()
	transport.poll()
	if authenticated:
		if now - _last_receive >= 3000:
			_lost()
		elif now - _last_ping >= 1000:
			_last_ping = now
			_nonce += 1
			_send("Ping", {"schemaVersion": 1, "nonce": _nonce})
		for id in pending.keys():
			if not authenticated:
				break
			var entry: Dictionary = pending[id]
			if now >= entry.expires:
				pending.erase(id)
				protocol_error.emit(_error("INTERNAL", "Command acknowledgment timed out; refresh state before retrying."))
			elif now >= entry.retryAt:
				_send(entry.type, entry.payload)
				entry.retryAt = now + 1000
	elif _wanted:
		if _retry_until > 0 and now >= _retry_until:
			disconnect_server()
			protocol_error.emit(_error("UNAUTHENTICATED", "Connection recovery timed out."))
		elif _retry_at > 0 and now >= _retry_at:
			_retry_at = 0
			_connect()
		elif _retry_at == 0 and now - _started >= 5000:
			_lost()

func _error(code: String, message: String) -> Dictionary:
	return {"schemaVersion": 1, "requestId": null, "code": code, "message": message, "retryable": false, "currentRevision": null}

func _exit_tree() -> void:
	_wanted = false
	if transport != null:
		transport.close()
