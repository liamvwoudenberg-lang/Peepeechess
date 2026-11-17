extends SceneTree
## One side of a REAL two-process hosted game over localhost UDP (run twice by scripts/test-host-play-processes.mjs).
##   godot --headless --path godot --script res://tests/network/host_proc.gd -- --role=host --dir=<shared dir> [--port=N]
##   godot --headless --path godot --script res://tests/network/host_proc.gd -- --role=guest --dir=<shared dir> [--via-port=N]
## Host: HostedGame (fake router, no IP lookup) + its own client as Black, writes the invite to <dir>/invite.txt, waits for the guest.
## Guest: reads the invite, joins with InviteJoin (optionally dialling a latency proxy at 127.0.0.1:<via-port>), White plays e2-e4, Black answers e7-e5.
## --relay=ws://127.0.0.1:N (host): hosts through the relay (tools/relay/relay.mjs), the invite then carries the relay and no IP address.
## --mode=battle: the host is White, the guest answers d7-d5 and the host captures e4xd5: the capture duel must start on the host's server.
## --no-relay (guest): ignore the invite's relay and use its direct addresses.
const Client = preload("res://network/client/network_client.gd")
const Balance = preload("res://combat/data/balance_data.gd")
var args: Dictionary = {}
var ok = true

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			args[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	call_deferred("run")

func fail(text: String) -> void:
	ok = false
	print("PROC FAIL: ", text)

func wait_for(test: Callable, milliseconds: int) -> bool:
	var deadline = Time.get_ticks_msec() + milliseconds
	while not test.call():
		if Time.get_ticks_msec() > deadline:
			return false
		await process_frame
	return true

func run() -> void:
	var dir: String = args.get("dir", "")
	if str(args.get("role", "")) == "host":
		await host(dir)
	else:
		await guest(dir)
	print("PROC %s: %s" % [args.get("role", "?"), "ok" if ok else "FAILED"])
	quit(0 if ok else 1)

func host(dir: String) -> void:
	var fake = FakePortMapper.new()
	fake.scripted = {"ok": true, "external_ip": "127.0.0.1", "message": "fake", "private_external": false}
	var hosted = HostedGame.new()
	root.add_child(hosted)
	var battle = str(args.get("mode", "classic")) == "battle"
	var options = {"mode": "battle" if battle else "classic", "color": "w" if battle else "b", "port": int(args.get("port", "24980")), "mapper": fake, "version": "proc", "seal": false}
	if args.has("relay"):
		options["connection"] = str(args.get("connection", "relay"))
		options["relay_url"] = str(args.relay)
	if hosted.begin(options) != OK:
		fail("host could not start")
		return
	var client = Client.new()
	root.add_child(client)
	client.session_ready.connect(func(_w): client.create_match("battle" if battle else "classic", 0 if battle else 600000, 0))
	client.frame_received.connect(func(frame): if hosted.match_id.is_empty(): hosted.set_match(str(frame.state.matchId)))
	client.session_token = hosted.host_token
	client.connect_server("127.0.0.1", hosted.port, hosted.certificate.certificate_path, false, HostInvite.CERT_HOSTNAME)
	if not await wait_for(func(): return not hosted.state.invite.is_empty(), 15000):
		fail("no invite")
		return
	var invite: String = hosted.state.invite
	var file = FileAccess.open(dir.path_join("invite.txt"), FileAccess.WRITE)
	file.store_string(invite)
	file.close()
	print("invite length ", invite.length())
	if not await wait_for(func(): return str(client.frame.get("state", {}).get("players", {}).get("w", "")).begins_with("player-"), 40000):
		fail("the guest never joined")
		return
	if args.has("relay") and str(args.get("connection", "relay")) == "relay":
		var decoded = HostInvite.decode(invite)
		if not decoded.ok or not decoded.hosts.is_empty() or str(decoded.relay).is_empty():
			fail("a relay-only invite must carry no host address")
			return
	client.command("ready")
	if not await wait_for(func(): return client.frame.get("status") == "active", 20000):
		fail("game never became active")
		return
	if battle:
		client.chess_move("e2", "e4")
		if not await wait_for(func(): return client.frame.get("state", {}).get("chess", {}).get("history", []).size() >= 2, 20000):
			fail("the guest's d7-d5 never arrived")
			return
		client.chess_move("e4", "d5")
		var room = hosted.server.rooms.values()[0]
		if not await wait_for(func(): return room.game.phase in ["preview", "combat", "countdown"], 20000):
			fail("the capture did not start a duel on the host's server (phase %s)" % room.game.phase)
		var captured = FileAccess.open(dir.path_join("host.captured"), FileAccess.WRITE)
		captured.store_string("1")
		captured.close()
		await wait_for(func(): return FileAccess.file_exists(dir.path_join("guest.done")), 20000)
		client.disconnect_server(true)
		for _i in 10:
			await process_frame
		hosted.stop()
		return
	if not await wait_for(func(): return client.frame.get("state", {}).get("chess", {}).get("history", []).size() >= 1, 20000):
		fail("never saw White's move")
		return
	client.chess_move("e7", "e5")
	if not await wait_for(func(): return client.frame.get("state", {}).get("chess", {}).get("history", []).size() >= 2, 15000):
		fail("Black's own move was not accepted")
	await wait_for(func(): return FileAccess.file_exists(dir.path_join("guest.done")), 20000)
	client.disconnect_server(true)
	for _i in 10:
		await process_frame
	hosted.stop()

func guest(dir: String) -> void:
	if not await wait_for(func(): return FileAccess.file_exists(dir.path_join("invite.txt")), 40000):
		fail("no invite file")
		return
	var text = FileAccess.get_file_as_string(dir.path_join("invite.txt"))
	var client = Client.new()
	root.add_child(client)
	var join = InviteJoin.new()
	root.add_child(join)
	var joined = []
	var failed = []
	join.joined.connect(func(invite): joined.append(invite))
	join.failed.connect(func(code, message): failed.append(code + ": " + message))
	if args.has("via-port"):
		join.address_override = {"host": "127.0.0.1", "port": int(args["via-port"])}
	if args.has("no-relay"):
		join.relay_enabled = false
	var begun = join.begin(client, text, Balance.stamp())
	if not begun.ok:
		fail("invite refused: " + str(begun))
		return
	if not await wait_for(func(): return not joined.is_empty() or not failed.is_empty(), 30000) or joined.is_empty():
		fail("join failed " + str(failed))
		return
	client.command("ready")
	if not await wait_for(func(): return client.frame.get("status") == "active", 20000):
		fail("game never became active (guest)")
		return
	if str(args.get("mode", "classic")) == "battle":
		if not await wait_for(func(): return client.frame.get("state", {}).get("chess", {}).get("history", []).size() >= 1, 20000):
			fail("never saw White's move")
			return
		client.chess_move("d7", "d5")
		await wait_for(func(): return client.frame.get("state", {}).get("chess", {}).get("history", []).size() >= 2, 20000)
		await wait_for(func(): return FileAccess.file_exists(dir.path_join("host.captured")), 20000)
		var battle_done = FileAccess.open(dir.path_join("guest.done"), FileAccess.WRITE)
		battle_done.store_string("1")
		battle_done.close()
		client.disconnect_server(true)
		for _i in 10:
			await process_frame
		return
	client.chess_move("e2", "e4")
	if not await wait_for(func(): return client.frame.get("state", {}).get("chess", {}).get("history", []).size() >= 2, 20000):
		fail("never saw Black's answer")
	var done = FileAccess.open(dir.path_join("guest.done"), FileAccess.WRITE)
	done.store_string("1")
	done.close()
	client.disconnect_server(true)
	for _i in 10:
		await process_frame
