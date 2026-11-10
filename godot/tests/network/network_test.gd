extends SceneTree
const Server = preload("res://network/server/dedicated_server.gd")
const Wire = preload("res://network/wire_codec.gd")
const Builder = preload("res://combat/core/combat_input_builder.gd")
const Remote = preload("res://network/client/remote_match.gd")
var checks = 0
var failures: Array = []
var server
var wire = Wire.new()
var sent: Array = []
var now = 1000
var serial = 0
func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL: ", label)
func _init() -> void:
	call_deferred("run")
func packet(id: int, type_name: String, payload: Dictionary, unreliable: bool = false) -> Dictionary:
	now += 250
	sent.clear()
	server.receive(id, wire.pack(type_name, payload), 1 if unreliable else 0, 0 if unreliable else ENetPacketPeer.FLAG_RELIABLE, now)
	for reply in sent:
		if reply.id == id and reply.type in ["Welcome", "Ack", "ProtocolError"]:
			return reply.payload
	return {}
func hello(id: int, token: Variant = null) -> Dictionary:
	server.attach(id, "127.0.0." + str(id), now)
	return packet(id, "Hello", {"schemaVersion":1, "protocol":"peepeechess-enet-v1", "resumeToken":token})
func command(id: int, match_id: String, action: String, kind: Variant = null) -> Dictionary:
	serial += 1
	return packet(id, "MatchCommand", {"schemaVersion":1, "commandId":"command-" + str(serial), "matchId":match_id, "action":action, "drawKind":kind, "intended":null})
func move(id: int, room, from: String, to: String, player: String = "", revision: int = -1) -> Dictionary:
	serial += 1
	return packet(id, "ChessMoveRequest", {"schemaVersion":1, "requestId":"move-" + str(serial), "matchId":room.game.match_id, "playerId":player if not player.is_empty() else server.connections[id].player, "expectedRevision":room.game.revision if revision < 0 else revision, "from":from, "to":to, "promotion":null})
func create(id: int, mode: String = "classic", base_ms: int = 600000) -> Dictionary:
	serial += 1
	return packet(id, "CreateMatch", {"schemaVersion":1, "commandId":"create-" + str(serial), "mode":mode, "initialMs":base_ms, "incrementMs":0})
func start_room(white: int, black: int, mode: String = "classic", base_ms: int = 600000):
	var created = create(white, mode, base_ms)
	if not created.has("matchId"):
		expect(false, "room created: " + str(created))
		return null
	var room = server.rooms[created.matchId]
	serial += 1
	packet(black, "JoinMatch", {"schemaVersion":1, "commandId":"join-" + str(serial), "matchId":created.matchId})
	command(white, created.matchId, "ready")
	command(black, created.matchId, "ready")
	return room
func run() -> void:
	for case in JSON.parse_string(FileAccess.get_file_as_string("res://contracts/network/v1/fixtures.json")):
		expect(wire.valid(case.type, case.payload) == case.valid, "shared network schema: " + case.name)
	for text in ['{"type":"Ping","payload":{"schemaVersion":1,"nonce":0,"nonce":1}}', '{"type":"Ping","payload":{"schemaVersion":1,"nonce":0,"no\\u006ece":1}}', '{"type":"Ping","type":"Ping","payload":{"schemaVersion":1,"nonce":1}}', '{broken', '['.repeat(40) + '0' + ']'.repeat(40), '{"type":"Ping","payload":{"schemaVersion":1,"nonce":1e999}}']:
		expect(not wire.unpack(text.to_utf8_buffer(), 65536).ok, "strict JSON refuses duplicate/invalid/deep/nonfinite payload")
	for bytes in [PackedByteArray([0xc0, 0x80]), PackedByteArray([0xed, 0xa0, 0x80]), PackedByteArray([0xff])]:
		expect(not wire.unpack(bytes, 65536).ok, "invalid UTF-8 rejected before parsing")
	expect(not wire.unpack(" ".repeat(65537).to_utf8_buffer(), 65536).ok, "client frame size bounded")
	server = Server.new()
	root.add_child(server)
	server.set_process(false)
	server.set_physics_process(false)
	server.outgoing.connect(func(id, type_name, payload, _reliable): sent.append({"id":id, "type":type_name, "payload":payload}))
	var white = hello(1)
	var black = hello(2)
	expect(white.has("sessionToken") and black.playerId != white.playerId and white.sessionToken.length() == 64, "server-issued independent identities and 256-bit tokens")
	expect(server.sessions[white.playerId].digest == white.sessionToken.sha256_text() and not server.sessions[white.playerId].has("sessionToken"), "server retains token digest only")
	var impostor = hello(3, "ff".repeat(32))
	expect(impostor.code == "UNAUTHENTICATED", "invalid token rejected")
	impostor = hello(4, white.sessionToken)
	expect(impostor.code == "FORBIDDEN" and server.sessions[white.playerId].peer == 1, "active session cannot be stolen by another peer")
	server.attach(5, "127.0.0.5", now)
	var denied = packet(5, "CreateMatch", {"schemaVersion":1,"commandId":"unauth","mode":"classic","initialMs":0,"incrementMs":0})
	expect(denied.code == "UNAUTHENTICATED", "commands require authentication")
	var room = start_room(1, 2)
	if room == null:
		quit(1)
		return
	expect(room.status == "active" and room.game.started and not room.game.allow_undo, "both ready starts authoritative clocks; online undo forbidden")
	var before = room.game.engine.fen()
	expect(move(1, room, "e2", "e5").code == "ILLEGAL_MOVE" and room.game.engine.fen() == before, "illegal move cannot mutate board")
	expect(move(2, room, "e2", "e4", white.playerId).code == "FORBIDDEN", "identity in a payload is not authentication")
	expect(move(1, room, "e2", "e4", "", 7).code == "STALE_REVISION", "revision checked on server")
	var last_poll = room.game.last_poll
	command(1, room.game.match_id, "ready")
	expect(room.game.last_poll == last_poll, "repeated readiness cannot reset or pause a running clock")
	var battle_result = JSON.parse_string(FileAccess.get_file_as_string("res://contracts/v1/fixtures.json")).filter(func(case): return case.type == "BattleResult" and case.valid)[0].payload
	expect(packet(1, "BattleResult", battle_result).code == "FORBIDDEN" and room.game.engine.fen() == before, "client-reported winner forbidden")
	var intent = {"schemaVersion":1,"requestId":"idempotent","matchId":room.game.match_id,"playerId":white.playerId,"expectedRevision":0,"from":"f2","to":"f3","promotion":null}
	var ack = packet(1, "ChessMoveRequest", intent)
	expect(ack.revision == 1, "server commits valid move")
	var after = room.game.engine.fen()
	expect(packet(1, "ChessMoveRequest", intent) == ack and room.game.revision == 1 and room.game.engine.fen() == after, "exact retry acknowledges once")
	intent.to = "f4"
	expect(packet(1, "ChessMoveRequest", intent).code == "INVALID_PAYLOAD", "request ID cannot change its intent")
	move(2, room, "e7", "e5")
	move(1, room, "g2", "g4")
	move(2, room, "d8", "h4")
	expect(room.status == "complete" and room.game.engine.result == "0-1", "complete Classic checkmate is server-owned")
	expect(wire.valid("MatchFrame", room.frame(white.playerId)), "terminal Classic frame conforms to nested contracts")
	var classic = start_room(1, 2)
	expect(command(1, classic.game.match_id, "accept_draw").code == "FORBIDDEN", "draw needs an opponent offer")
	command(1, classic.game.match_id, "offer_draw")
	expect(command(1, classic.game.match_id, "accept_draw").code == "FORBIDDEN", "cannot accept own draw")
	command(2, classic.game.match_id, "accept_draw")
	expect(classic.game.engine.result == "1/2-1/2", "two-seat draw agreement")
	classic = start_room(1, 2, "classic", 1000)
	classic.step(now + 1001)
	expect(classic.status == "complete" and classic.game.engine.reason == "Time expired", "server monotonic clock decides timeout")
	var battle = start_room(1, 2, "battle", 0)
	move(1, battle, "e2", "e4")
	move(2, battle, "d7", "d5")
	move(1, battle, "e4", "d5")
	await physics_frame
	await process_frame
	expect(battle.sim != null and battle.game.phase == "combat", "capture starts the real server combat simulation")
	var request = battle.game.pending_request()
	var builder = Builder.new(request.matchId, request.battleId, white.playerId)
	var valid = builder.build(1, 1, 0, true, true, false)
	expect(not packet(2, "CombatInput", valid, true).is_empty(), "opponent cannot send another seat's combat input")
	valid.playerId = black.playerId
	expect(packet(1, "CombatInput", valid, true).code == "FORBIDDEN", "payload seat spoof rejected")
	valid.playerId = white.playerId
	packet(1, "CombatInput", valid, true)
	expect(battle.sim.fighter_by_id(white.playerId).last_input_sequence == 1, "legitimate input reaches server fighter")
	now += 1000
	var duplicate = packet(1, "CombatInput", valid, true)
	expect(duplicate.get("code") == "STALE_INPUT", "replayed input sequence rejected")
	var forged = valid.duplicate(true)
	forged.sequence = 2
	forged["damage"] = 9999
	sent.clear()
	now += 1100
	server.receive(1, JSON.stringify({"type":"CombatInput", "payload":forged}).to_utf8_buffer(), 1, 0, now)
	expect(sent.any(func(reply): return reply.type == "ProtocolError" and reply.payload.code == "INVALID_PAYLOAD"), "damage field rejected at transport schema")
	var frozen = battle.game.engine.fen()
	packet(1, "BattleResult", battle_result)
	expect(battle.game.engine.fen() == frozen and battle.game.revision == 2, "forged winner cannot settle a pending capture")
	server.detach(1, now)
	var resumed = hello(6, white.sessionToken)
	expect(resumed.playerId == white.playerId and battle.connected.w, "reconnect preserves identity and board seat")
	var resumed_frame = battle.frame(white.playerId)
	expect(resumed_frame.inputResume.sequence == 1 and resumed_frame.inputResume.battleId == request.battleId, "reconnect preserves accepted input acknowledgment")
	builder.sequence = 1
	valid = builder.build(0, 0, 0, true, false, false)
	packet(6, "CombatInput", valid, true)
	expect(battle.sim.fighter_by_id(white.playerId).last_input_sequence == 2, "input sequence continues after reconnect")
	var clocks = battle.game.remaining.duplicate()
	server.detach(6, now)
	for index in range(20):
		battle.step(now + index * 16)
	expect(battle.sim.server_tick > request.startTick and battle.game.remaining == clocks, "disconnect does not pause combat or invent chess time")
	battle.step(now + 10001)
	expect(battle.status == "complete" and battle.game.engine.result == "0-1" and battle.sim == null and battle.game.pending_request().is_empty(), "disconnect forfeit terminates and clears combat without a fake battle result")
	resumed = hello(7, white.sessionToken)
	var both = start_room(7, 2, "battle", 0)
	server.detach(7, now)
	server.detach(2, now)
	both.step(now + 10001)
	expect(both.game.engine.result == "1/2-1/2" and both.game.engine.reason == "Both players disconnected", "both absent produces explicit draw")
	var flood = hello(8)
	var ping = wire.pack("Ping", {"schemaVersion":1,"nonce":1})
	sent.clear()
	for i in range(300):
		server.receive(8, ping, 0, ENetPacketPeer.FLAG_RELIABLE, now)
	expect(sent.any(func(reply): return reply.type == "ProtocolError" and reply.payload.code == "RATE_LIMITED"), "flood bounded before repeated schema/command work")
	server.queue_free()
	await process_frame
	print("NETWORK AUTHORITY: ", checks, " checks; failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
