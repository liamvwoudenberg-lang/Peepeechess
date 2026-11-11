extends SceneTree
const Wire = preload("res://network/wire_codec.gd")
const Backend = preload("res://network/server/account_backend.gd")
const Server = preload("res://network/server/dedicated_server.gd")
const Client = preload("res://network/client/network_client.gd")
var checks = 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		printerr("FAIL ", message)
		quit(1)
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var codec = Wire.new()
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://contracts/application/v1/fixtures.json"))
	for value in fixtures.valid:
		check(not codec.pack(value.type, value.payload).is_empty(), "encode account handshake")
		check(codec.unpack(codec.pack(value.type, value.payload), Wire.MAX_CLIENT_BYTES).ok, "decode account handshake")
	for value in fixtures.invalid:
		check(codec.pack(value.type, value.payload).is_empty(), "reject invalid account handshake")
	check(Backend.safe_url("https://service.example", false), "HTTPS backend")
	check(not Backend.safe_url("http://service.example", true), "no public plaintext")
	check(Backend.safe_url("http://127.0.0.1:3456", true), "explicit loopback HTTP")
	check(not Backend.safe_url("http://127.0.0.1.evil:3456", true), "loopback lookalike")
	check(not Backend.safe_url("https://user:pass@host", false), "no URL credentials")
	var directory = ProjectSettings.globalize_path("user://test-outbox-" + str(Time.get_ticks_usec()))
	var bridge = Backend.new()
	check(bridge.configure("http://127.0.0.1:1", "test-1", "a".repeat(32), directory, true) == OK, "outbox configured")
	check(bridge.provision({"matchId": "unfinished"}), "durable admission")
	check(bridge.provision({"matchId": "complete"}), "second durable admission")
	bridge.complete("complete", "white", "Checkmate", "fen", [{"from": "e2", "to": "e4"}])
	var recovered = Backend.new()
	check(recovered.configure("http://127.0.0.1:1", "test-1", "a".repeat(32), directory, true) == OK, "restart outbox")
	check(recovered.jobs.unfinished.report.result == "aborted" and not recovered.jobs.unfinished.active, "restart never fabricates winner")
	check(recovered.jobs.complete.report.result == "white", "terminal result preserved")
	check(recovered.jobs.complete.report.history.size() == 1, "history preserved")
	for file in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory.path_join(file))
	DirAccess.remove_absolute(directory)
	bridge.free()
	recovered.free()
	var server = Server.new()
	root.add_child(server)
	server.attach(77, "127.0.0.1", 0)
	server.account_backend = Backend.new()
	root.add_child(server.account_backend)
	var sent: Array = []
	server.outgoing.connect(func(_id, type, payload, _reliable): sent.append({"type": type, "payload": payload}))
	server.receive(77, codec.pack("Hello", {"schemaVersion": 1, "protocol": "peepeechess-enet-v1", "resumeToken": null}), 0, ENetPacketPeer.FLAG_RELIABLE, 1)
	check(sent.size() == 1 and sent[0].payload.code == "UNAUTHENTICATED", "account mode rejects anonymous hello")
	check(server.sessions.is_empty(), "anonymous admission never creates identity")
	check(not server._create({}, "forged", {}, 1).ok, "clients cannot create competitive allocations")
	check(not server._join({}, "forged", {}, 1).ok, "clients cannot choose allocated seat")
	server.account_backend.queue_free()
	server.queue_free()
	var client = Client.new()
	root.add_child(client)
	check(client.has_method("connect_account_server"), "same native ticket client for both platforms")
	client.queue_free()
	await process_frame
	print("PASS application protocol/outbox: ", checks, " checks")
	quit(0)
