extends SceneTree
const Server = preload("res://network/server/dedicated_server.gd")
const Client = preload("res://network/client/network_client.gd")
var server
var client
var deadline = 0
func _init() -> void:
	call_deferred("run")
func run() -> void:
	server = Server.new()
	root.add_child(server)
	if server.start("127.0.0.1", 24991, "", "", true) != OK:
		quit(1)
		return
	client = Client.new()
	root.add_child(client)
	client.protocol_error.connect(func(error): printerr(error))
	client.session_ready.connect(func(_welcome): print("ENET_CONNECTED"); client.create_match("classic", 60000))
	client.frame_received.connect(func(frame): print("MATCH_CREATED ", frame.state.matchId); quit(0))
	client.connect_server("127.0.0.1", 24991, "", true)
	deadline = Time.get_ticks_msec() + 8000
func _process(_delta: float) -> bool:
	if deadline > 0 and Time.get_ticks_msec() > deadline:
		printerr("Connection smoke timed out")
		quit(1)
	return false
