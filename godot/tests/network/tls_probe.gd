extends SceneTree
## A wrong CA must never obtain an authenticated session, even on the correct address/port.
const Client = preload("res://network/client/network_client.gd")
var client
var deadline = 0
var expect_valid = false
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var options = {}
	for arg in OS.get_cmdline_user_args():
		var parts = arg.trim_prefix("--").split("=", true, 1)
		options[parts[0]] = parts[1]
	client = Client.new()
	root.add_child(client)
	client.auto_reconnect = false
	expect_valid = options.get("expect-valid", "false") == "true"
	client.session_ready.connect(_authenticated)
	client.connect_server("127.0.0.1", int(options.port), options.ca)
	deadline = Time.get_ticks_msec() + 3500
func _process(_delta: float) -> bool:
	if deadline > 0 and Time.get_ticks_msec() > deadline:
		client.disconnect_server()
		if expect_valid:
			printerr("FAIL: trusted server did not authenticate")
			quit(1)
		else:
			print("PASS: incorrect CA never authenticated")
			quit(0)
	return false

func _authenticated(_welcome: Dictionary) -> void:
	if expect_valid:
		await client.disconnect_gracefully()
		print("PASS: trusted server remains available after rejected handshake")
		quit(0)
	else:
		printerr("FAIL: untrusted server authenticated")
		quit(1)
