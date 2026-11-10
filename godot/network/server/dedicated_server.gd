class_name DedicatedChessServer
extends Node
signal outgoing(peer_id: int, type_name: String, payload: Dictionary, reliable: bool)
const Wire = preload("res://network/wire_codec.gd")
const Transport = preload("res://network/enet_transport.gd")
const Budget = preload("res://network/rate_budget.gd")
const Room = preload("res://network/server/match_session.gd")
const MAX_SESSIONS = 128
const MAX_ROOMS = 16
const MAX_COMMANDS = 4096
var wire = Wire.new()
var transport: ChessEnetTransport
var connections: Dictionary = {}
var sessions: Dictionary = {}
var token_index: Dictionary = {}
var rooms: Dictionary = {}
var dirty: Dictionary = {}
var server_id = "server-" + Crypto.new().generate_random_bytes(16).hex_encode()
var _crypto = Crypto.new()
var _ip_budgets: Dictionary = {}
var _last_periodic = 0
var _last_clocks = 0
var _running = false

func start(address: String, port: int, certificate: String = "", key: String = "", insecure_local: bool = false) -> Error:
	transport = Transport.new()
	add_child(transport)
	transport.connected.connect(func(id): attach(id, transport.peers[id].get_remote_address(), Time.get_ticks_msec()))
	transport.disconnected.connect(func(id): detach(id, Time.get_ticks_msec()))
	transport.packet_received.connect(func(id, bytes, channel, flags): receive(id, bytes, channel, flags, Time.get_ticks_msec()))
	var response = transport.listen(address, port, certificate, key, insecure_local)
	_running = response == OK
	return response

func attach(id: int, address: String, now: int) -> void:
	if not _ip_budgets.has(address):
		if _ip_budgets.size() >= 512:
			_reject_peer(id)
			return
		_ip_budgets[address] = {"budget": Budget.new(0.2, 12, now), "seen": now}
	_ip_budgets[address].seen = now
	if not _ip_budgets[address].budget.take(now):
		_reject_peer(id)
		return
	connections[id] = {"player": "", "created": now, "seen": now, "strikes": 0, "lastError": -1000,
		"packets": Budget.new(180, 240, now), "bytes": Budget.new(131072, 131072, now),
		"control": Budget.new(10, 20, now), "input": Budget.new(90, 120, now)}

func detach(id: int, now: int) -> void:
	if not connections.has(id):
		return
	var player: String = connections[id].player
	connections.erase(id)
	if sessions.has(player) and sessions[player].peer == id:
		sessions[player].peer = 0
		var room = rooms.get(sessions[player].matchId)
		if room != null:
			room.set_connected(player, false, now)

func _reject_peer(id: int) -> void:
	if transport != null:
		transport.drop(id)

func receive(id: int, bytes: PackedByteArray, channel: int, flags: int, now: int) -> void:
	if not connections.has(id):
		return
	var connection: Dictionary = connections[id]
	if not connection.packets.take(now) or not connection.bytes.take(now, bytes.size()):
		_error(id, "RATE_LIMITED", "Packet budget exceeded.", null, now, true)
		return
	var parsed = wire.unpack(bytes, Wire.MAX_CLIENT_BYTES)
	if not parsed.ok:
		connection.strikes += 1
		_error(id, parsed.code, "Invalid network message.", null, now, true)
		if connection.strikes >= 8:
			_reject_peer(id)
		return
	var type_name: String = parsed.type
	var payload: Dictionary = parsed.payload
	var request_id = payload.get("requestId", payload.get("commandId"))
	if type_name not in Wire.CLIENT_TYPES:
		_error(id, "FORBIDDEN", "Clients may only submit intent, never authoritative state or results.", request_id, now)
		return
	if channel != (1 if type_name == "CombatInput" else 0) or bool(flags & ENetPacketPeer.FLAG_RELIABLE) != (type_name != "CombatInput"):
		_error(id, "INVALID_PAYLOAD", "Incorrect message channel or delivery mode.", request_id, now)
		return
	if not connection["input" if type_name == "CombatInput" else "control"].take(now):
		_error(id, "RATE_LIMITED", "Message rate exceeded.", request_id, now, true)
		return
	if type_name == "Hello":
		_hello(id, payload, now)
		return
	var player: String = connection.player
	if not sessions.has(player) or sessions[player].peer != id or sessions[player].expires <= now:
		_error(id, "UNAUTHENTICATED", "Authenticate or resume a valid session first.", request_id, now)
		return
	connection.seen = now
	if type_name == "Ping":
		_send(id, "Pong", {"schemaVersion": 1, "nonce": payload.nonce})
		return
	var session: Dictionary = sessions[player]
	if type_name == "CombatInput":
		var room = rooms.get(session.matchId)
		var reply = room.input(payload, player) if room != null else {"ok": false, "code": "FORBIDDEN", "message": "No match for this seat."}
		if not reply.ok:
			_send_failure(id, reply, null, now, true)
		return
	var serialized = JSON.stringify({"type": type_name, "payload": payload}, "", true, true)
	if session.commands.has(request_id):
		var previous: Dictionary = session.commands[request_id]
		if previous.intent != serialized:
			_error(id, "INVALID_PAYLOAD", "Request ID was reused with different intent.", request_id, now)
		else:
			_send(id, previous.type, previous.payload)
		return
	if session.commands.size() >= MAX_COMMANDS:
		_error(id, "RATE_LIMITED", "This session reached its command limit.", request_id, now)
		return
	var reply: Dictionary
	match type_name:
		"CreateMatch":
			reply = _create(session, player, payload, now)
		"JoinMatch":
			reply = _join(session, player, payload, now)
		_:
			var room = rooms.get(session.matchId)
			if room == null or payload.matchId != session.matchId:
				reply = {"ok": false, "code": "FORBIDDEN", "message": "Not a member of this match."}
			elif type_name == "ChessMoveRequest":
				reply = room.move(payload, player, now)
			else:
				reply = room.command(payload, player, now)
	if reply.ok:
		var room = rooms[session.matchId]
		var ack = {"schemaVersion": 1, "requestId": request_id, "matchId": session.matchId, "revision": room.game.revision}
		session.commands[request_id] = {"intent": serialized, "type": "Ack", "payload": ack}
		_send(id, "Ack", ack)
	else:
		var failure = _failure_payload(reply, request_id)
		session.commands[request_id] = {"intent": serialized, "type": "ProtocolError", "payload": failure}
		_send(id, "ProtocolError", failure)

func _hello(id: int, payload: Dictionary, now: int) -> void:
	if not connections[id].player.is_empty():
		_error(id, "FORBIDDEN", "This connection is already authenticated.", null, now)
		return
	var token: String = payload.resumeToken if payload.resumeToken != null else ""
	var player = ""
	if not token.is_empty():
		player = token_index.get(token.sha256_text(), "")
		if not sessions.has(player) or sessions[player].expires <= now:
			_error(id, "UNAUTHENTICATED", "The session token is invalid or expired.", null, now)
			return
		if sessions[player].peer != 0:
			_error(id, "FORBIDDEN", "This session already has an active connection.", null, now)
			return
	else:
		if sessions.size() >= MAX_SESSIONS:
			_error(id, "RATE_LIMITED", "The server session limit was reached.", null, now)
			return
		token = _crypto.generate_random_bytes(32).hex_encode()
		player = "player-" + _crypto.generate_random_bytes(16).hex_encode()
		var digest = token.sha256_text()
		sessions[player] = {"digest": digest, "expires": now + 86400000, "peer": 0, "matchId": "", "commands": {}}
		token_index[digest] = player
	var session: Dictionary = sessions[player]
	session.peer = id
	connections[id].player = player
	connections[id].seen = now
	var room = rooms.get(session.matchId)
	if room != null:
		room.check_disconnections(now)
		room.set_connected(player, true, now)
	_send(id, "Welcome", {"schemaVersion": 1, "protocol": "peepeechess-enet-v1", "playerId": player, "sessionToken": token, "serverId": server_id, "expiresInSeconds": maxi(1, (session.expires - now) / 1000), "combatRoles": Room.supported_roles()})
	if room != null:
		_send(id, "MatchFrame", room.frame(player))

func _live_room(session: Dictionary) -> bool:
	return rooms.has(session.matchId) and rooms[session.matchId].status != "complete"

func _create(session: Dictionary, player: String, payload: Dictionary, now: int) -> Dictionary:
	if _live_room(session) or rooms.size() >= MAX_ROOMS:
		return {"ok": false, "code": "FORBIDDEN", "message": "Leave or finish the current match, or wait for capacity."}
	if payload.mode == "battle" and (payload.initialMs != 0 or payload.incrementMs != 0):
		return {"ok": false, "code": "INVALID_PAYLOAD", "message": "Battle C0 chess is untimed."}
	if payload.mode == "classic" and payload.initialMs > 0 and payload.initialMs < 1000:
		return {"ok": false, "code": "INVALID_PAYLOAD", "message": "Timed games need at least one second."}
	var id = "match-" + _crypto.generate_random_bytes(16).hex_encode()
	var room = Room.new()
	add_child(room)
	room.configure(id, payload.mode, player, int(payload.initialMs), int(payload.incrementMs), now)
	room.changed.connect(func(): dirty[id] = true)
	room.combat_snapshot.connect(func(snapshot): _broadcast(id, "CombatSnapshot", snapshot, false))
	rooms[id] = room
	session.matchId = id
	dirty[id] = true
	return {"ok": true}

func _join(session: Dictionary, player: String, payload: Dictionary, now: int) -> Dictionary:
	if _live_room(session) or not rooms.has(payload.matchId):
		return {"ok": false, "code": "FORBIDDEN", "message": "No available match for this session."}
	var reply = rooms[payload.matchId].join(player, now)
	if reply.ok:
		session.matchId = payload.matchId
	return reply

func _failure_payload(reply: Dictionary, request_id: Variant) -> Dictionary:
	var error: Dictionary = reply.get("error", reply)
	return {"schemaVersion": 1, "requestId": request_id, "code": error.get("code", "INTERNAL"), "message": str(error.get("message", "Server rejected the operation.")).substr(0, 256), "retryable": error.get("code") in ["STALE_REVISION", "WRONG_PHASE", "RATE_LIMITED"], "currentRevision": error.get("currentRevision")}

func _send_failure(id: int, reply: Dictionary, request_id: Variant, now: int, limited: bool = false) -> void:
	var payload = _failure_payload(reply, request_id)
	_error(id, payload.code, payload.message, request_id, now, limited, payload.currentRevision)

func _error(id: int, code: String, message: String, request_id: Variant, now: int, limited: bool = false, revision: Variant = null) -> void:
	if limited and connections.has(id):
		if now - connections[id].lastError < 1000:
			return
		connections[id].lastError = now
	_send(id, "ProtocolError", {"schemaVersion": 1, "requestId": request_id, "code": code, "message": message, "retryable": code in ["STALE_REVISION", "WRONG_PHASE", "RATE_LIMITED"], "currentRevision": revision})

func _send(id: int, type_name: String, payload: Dictionary, reliable: bool = true) -> void:
	var bytes = wire.pack(type_name, payload)
	if bytes.is_empty() or bytes.size() > Wire.MAX_SERVER_BYTES:
		push_error("Server produced an invalid or oversized " + type_name)
		return
	outgoing.emit(id, type_name, payload.duplicate(true), reliable)
	if transport != null:
		transport.send(id, bytes, reliable)

func _broadcast(match_id: String, type_name: String, payload: Dictionary, reliable: bool = true) -> void:
	for player in sessions:
		var session: Dictionary = sessions[player]
		if session.matchId == match_id and session.peer != 0:
			_send(session.peer, type_name, payload, reliable)

func _full_frame(match_id: String) -> void:
	if not rooms.has(match_id):
		return
	for player in sessions:
		var session: Dictionary = sessions[player]
		if session.matchId == match_id and session.peer != 0:
			_send(session.peer, "MatchFrame", rooms[match_id].frame(player))

func expire(now: int) -> void:
	for id in connections.keys():
		var connection: Dictionary = connections[id]
		if (connection.player.is_empty() and now - connection.created >= 5000) or now - connection.seen >= 3000:
			detach(id, now)
			_reject_peer(id)
	for player in sessions.keys():
		var session: Dictionary = sessions[player]
		if now >= session.expires:
			if session.peer != 0:
				var id: int = session.peer
				detach(id, now)
				_reject_peer(id)
			token_index.erase(session.digest)
			sessions.erase(player)
	for id in rooms.keys():
		var room = rooms[id]
		if (room.status == "complete" and now - room.completed_ms >= 60000) or (room.status == "waiting" and now - room.created_ms >= 300000):
			for session in sessions.values():
				if session.matchId == id:
					session.matchId = ""
			rooms.erase(id)
			dirty.erase(id)
			room.queue_free()
	for address in _ip_budgets.keys():
		if now - _ip_budgets[address].seen >= 600000:
			_ip_budgets.erase(address)

func _process(_delta: float) -> void:
	if _running:
		expire(Time.get_ticks_msec())
		transport.poll()

func step(now: int) -> void:
	for room in rooms.values():
		room.step(now)
	for id in dirty.keys():
		_full_frame(id)
	dirty.clear()
	if now - _last_clocks >= 200:
		_last_clocks = now
		for id in rooms:
			var room = rooms[id]
			_broadcast(id, "ClockSync", {"schemaVersion": 1, "matchId": id, "serverTick": room.tick, "clocks": room.game.clock_state(), "connected": room.connected.duplicate()}, false)
	if now - _last_periodic >= 1000:
		_last_periodic = now
		for id in rooms:
			_full_frame(id)

func _physics_process(_delta: float) -> void:
	if _running:
		step(Time.get_ticks_msec())
