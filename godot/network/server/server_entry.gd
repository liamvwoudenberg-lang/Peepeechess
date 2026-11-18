extends Node
## Entry point of the EXPORTED dedicated server (the exported binary ignores --script): the Linux Server presets define the feature
## `peepeechess_server`, and project.godot overrides run/main_scene for that feature to this scene. Same options as server_main.gd.
const Server = preload("res://network/server/dedicated_server.gd")
var server
var deadline = 0
func _ready() -> void:
	call_deferred("run")
func run() -> void:
	var options = {}
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--"):
			printerr("Server arguments must use --name=value.")
			get_tree().quit(2)
			return
		var parts = arg.trim_prefix("--").split("=", true, 1)
		if parts[0] not in ["bind", "port", "certificate", "private-key", "insecure-local", "run-seconds", "backend-url", "server-id", "outbox-dir", "backend-insecure-local", "build-check", "move-timeout-seconds"]:
			printerr("Unknown server option: ", parts[0])
			get_tree().quit(2)
			return
		options[parts[0]] = parts[1] if parts.size() > 1 else "true"
	var port_text: String = options.get("port", "2456")
	if not port_text.is_valid_int() or int(port_text) < 1 or int(port_text) > 65535:
		printerr("Invalid UDP port.")
		get_tree().quit(2)
		return
	server = Server.new()
	add_child(server)
	var build_check: String = options.get("build-check", OS.get_environment("PEEPEECHESS_BUILD_CHECK") if not OS.get_environment("PEEPEECHESS_BUILD_CHECK").is_empty() else "match")
	if build_check not in ["off", "match", "require"]:
		printerr("--build-check must be off, match or require.")
		get_tree().quit(2)
		return
	server.build_policy = build_check
	var timeout_text: String = options.get("move-timeout-seconds", OS.get_environment("PEEPEECHESS_MOVE_TIMEOUT_SECONDS") if not OS.get_environment("PEEPEECHESS_MOVE_TIMEOUT_SECONDS").is_empty() else "0")
	if not timeout_text.is_valid_int() or int(timeout_text) < 0 or int(timeout_text) > 86400:
		printerr("--move-timeout-seconds must be 0..86400.")
		get_tree().quit(2)
		return
	server.move_timeout_ms = int(timeout_text) * 1000
	if options.has("backend-url"):
		var configured = server.configure_backend(options["backend-url"], options.get("server-id", "local-1"), OS.get_environment("PEEPEECHESS_BACKEND_SECRET"), options.get("outbox-dir", "user://server-outbox"), options.get("backend-insecure-local", "false") == "true")
		if configured != OK:
			printerr("Account backend configuration/outbox failed: ", error_string(configured))
			get_tree().quit(2)
			return
	var result = server.start(options.get("bind", "127.0.0.1"), int(port_text), options.get("certificate", ""), options.get("private-key", ""), options.get("insecure-local", "false") == "true")
	if result != OK:
		printerr("Server startup failed: ", error_string(result), ". Supply a certificate/key or explicit loopback development mode.")
		get_tree().quit(1)
		return
	if options.has("run-seconds"):
		deadline = Time.get_ticks_msec() + int(options["run-seconds"]) * 1000
	print("SERVER_READY protocol=peepeechess-enet-v1 port=", port_text, " roles=", Server.Room.supported_roles(), " tuning=", Server.Room.Balance.stamp())
func _process(_delta: float) -> void:
	if deadline > 0 and Time.get_ticks_msec() >= deadline:
		get_tree().quit(0)
