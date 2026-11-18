extends SceneTree
## The online lobby must say what is happening when a server never answers (closed port): "Connecting…", then a clear "No answer…" notice,
## and Create must not pretend to work before "Authenticated".
var checks = 0
var failures: Array = []

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL: ", label)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var lobby = load("res://network/client/online_lobby.tscn").instantiate()
	root.add_child(lobby)
	await process_frame
	await process_frame
	lobby.hostname.text = "127.0.0.1"
	lobby.port.value = 59997
	lobby.ca_path.text = ""
	lobby._connect_pressed()
	expect(lobby.notices.text.begins_with("Connecting to 127.0.0.1:59997"), "pressing Connect shows progress: " + lobby.notices.text)
	var started = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 9500:
		await process_frame
	expect(lobby.notices.text.begins_with("No answer from 127.0.0.1:59997") or lobby.notices.text.begins_with("Could not connect to 127.0.0.1:59997"), "an unreachable server gives a clear message: " + lobby.notices.text.left(60))
	expect(lobby.client.create_match("battle", 0) == "", "Create does not run before authentication")
	print("LOBBY CONNECT: ", checks, " checks; failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
