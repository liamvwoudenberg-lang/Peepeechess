extends SceneTree
## Deployment probe: a real protocol round trip against a Peepeechess dedicated server (connect, authenticate, create a Classic match and
## receive its lobby frame). Exit 0 = healthy, 1 = failed, 2 = bad arguments. Used after every deploy and by the health checks.
##   godot --headless --path godot --script res://network/server/probe_client.gd -- --host=1.2.3.4 --port=7777 [--ca=/path/ca.pem] [--name=cert.host] [--insecure-local]
const Client := preload("res://network/client/network_client.gd")
var client
var _deadline := 0
var _stage := 0


func _initialize() -> void:
	await process_frame   # the client's transport is created in its _ready: let the tree finish adding it
	var options := {"host": "127.0.0.1", "port": "7777", "ca": "", "name": "", "insecure-local": "false", "timeout": "20"}
	for arg in OS.get_cmdline_user_args():
		var parts: PackedStringArray = String(arg).trim_prefix("--").split("=", true, 1)
		if not options.has(parts[0]):
			printerr("unknown option ", parts[0])
			quit(2)
			return
		options[parts[0]] = parts[1] if parts.size() > 1 else "true"
	var new_client = Client.new()
	root.add_child(new_client)
	await process_frame
	client = new_client
	var err: int = client.connect_server(options["host"], int(options["port"]), options["ca"], options["insecure-local"] == "true", options["name"])
	if err != OK:
		printerr("PROBE_FAIL connect error ", error_string(err))
		quit(1)
		return
	_deadline = Time.get_ticks_msec() + int(options["timeout"]) * 1000
	print("PROBE_START ", options["host"], ":", options["port"])


func _process(_delta: float) -> bool:
	if client == null:
		return false
	if Time.get_ticks_msec() > _deadline:
		printerr("PROBE_FAIL timeout at stage ", _stage)
		quit(1)
		return false
	if _stage == 0 and client.authenticated:
		_stage = 1
		client.create_match("classic", 0)
	elif _stage == 1 and not client.frame.is_empty():
		print("PROBE_OK authenticated and received the match lobby frame")
		quit(0)
	return false
