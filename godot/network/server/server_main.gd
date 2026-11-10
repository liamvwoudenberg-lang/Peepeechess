extends SceneTree
const Server = preload("res://network/server/dedicated_server.gd")
var server
var deadline = 0
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var options = {}
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--"):
			printerr("Server arguments must use --name=value.")
			quit(2)
			return
		var parts = arg.trim_prefix("--").split("=", true, 1)
		if parts[0] not in ["bind", "port", "certificate", "private-key", "insecure-local", "run-seconds"]:
			printerr("Unknown server option: ", parts[0])
			quit(2)
			return
		options[parts[0]] = parts[1] if parts.size() > 1 else "true"
	var port_text: String = options.get("port", "2456")
	if not port_text.is_valid_int() or int(port_text) < 1 or int(port_text) > 65535:
		printerr("Invalid UDP port.")
		quit(2)
		return
	server = Server.new()
	root.add_child(server)
	var result = server.start(options.get("bind", "127.0.0.1"), int(port_text), options.get("certificate", ""), options.get("private-key", ""), options.get("insecure-local", "false") == "true")
	if result != OK:
		printerr("Server startup failed: ", error_string(result), ". Supply a certificate/key or explicit loopback development mode.")
		quit(1)
		return
	if options.has("run-seconds"):
		deadline = Time.get_ticks_msec() + int(options["run-seconds"]) * 1000
	print("SERVER_READY protocol=peepeechess-enet-v1 port=", port_text, " roles=", Server.Room.supported_roles())
func _process(_delta: float) -> bool:
	if deadline > 0 and Time.get_ticks_msec() >= deadline:
		quit(0)
	return false
