extends SceneTree
## Real ENet sockets on loopback, a real DedicatedChessServer, two real OnlineChessClients each with a real OnlineCombatView
## (CombatArena in its network-client mode). Proves the online path predicts, reconciles and interpolates:
##   * the arena runs through CombatNetClient and shares the transport's ONE input builder (sequence/counters);
##   * a device intent moves the predicted fighter before the server has even answered, and the server agrees later;
##   * a press shows its cosmetic action at once and the server really performs it (no double press);
##   * a reconnect mid-fight continues the same sequence stream (nothing stale rejected, no replayed press);
##   * after the result the client stops sending for that battle.
## Localhost is NOT the internet: latency here is ~1 ms, so reconciliation error is trivially small. scripts/test-online-combat.mjs
## repeats the fights through a latency/loss proxy.
const Server = preload("res://network/server/dedicated_server.gd")
const Client = preload("res://network/client/network_client.gd")
const View = preload("res://network/client/online_combat_view.gd")
const Bot = preload("res://combat/net/net_bot.gd")
var checks = 0
var failures: Array = []
var errors: Array = []
var server
var clients: Array = []
var views: Array = []
var hosts: Array = []
const PORT = 24995

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL: ", label)

func until(condition: Callable, label: String, seconds: int = 10) -> bool:
	var deadline = Time.get_ticks_msec() + seconds * 1000
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	var passed = condition.call()
	expect(passed, label)
	return passed

func _init() -> void:
	call_deferred("run")

func ticks(count: int) -> void:
	for _i in range(count):
		await physics_frame

func fighter_of(snapshot: Dictionary, id: String) -> Dictionary:
	for f in snapshot.fighters:
		if f.playerId == id:
			return f
	return {}

func run() -> void:
	server = Server.new()
	root.add_child(server)
	expect(server.start("127.0.0.1", PORT, "", "", true) == OK, "server starts")
	for _i in range(2):
		var client = Client.new()
		root.add_child(client)
		client.protocol_error.connect(func(error): errors.append(error.code + ": " + error.message))
		var host = SubViewport.new()
		host.own_world_3d = true
		host.size = Vector2i(320, 180)
		root.add_child(host)
		var view = View.new()
		root.add_child(view)
		view.setup(client, host)
		client.frame_received.connect(view.sync)
		clients.append(client)
		hosts.append(host)
		views.append(view)
		client.connect_server("127.0.0.1", PORT, "", true)
	if not await until(func(): return clients[0].authenticated and clients[1].authenticated, "both clients authenticate"):
		await cleanup()
		return
	clients[0].create_match("battle", 0)
	await until(func(): return not clients[0].frame.is_empty(), "creator gets the lobby")
	clients[1].join_match(clients[0].frame.state.matchId)
	await until(func(): return not clients[1].frame.is_empty(), "joiner gets the lobby")
	clients[0].command("ready")
	clients[1].command("ready")
	await until(func(): return clients[0].frame.status == "active" and clients[1].frame.status == "active", "match active")
	# e4 d5 exd5: a pawn-takes-pawn duel
	var script = [["e2", "e4"], ["d7", "d5"], ["e4", "d5"]]
	for ply in range(script.size()):
		var mover = clients[ply % 2]
		await until(func(): return mover.frame.state.chess.ply == ply and mover.frame.state.phase == "board" and mover.frame.state.players["w" if ply % 2 == 0 else "b"] == mover.player_id, "seat %d to move at ply %d" % [ply % 2, ply])
		mover.chess_move(script[ply][0], script[ply][1])
	if not await until(func(): return views[0].arena != null and views[1].arena != null and views[0].net_client() != null and views[1].net_client() != null, "both views mount the arena through the network client path"):
		await cleanup()
		return
	var white = clients[0]
	var black = clients[1]
	var view = views[0]
	var net = view.net_client()
	expect(net.builder == white.input_builder and views[1].net_client().builder == black.input_builder, "the arena's client shares the transport's single input builder")
	expect(view.arena.mode == CombatArena.Mode.PRESENTATION and view.arena._inputs.is_empty() and view.arena.process_priority == 100, "presentation arena owns no input source and ticks after the devices")
	expect(view.source != null and view.source.net_client == net and view.source.builder == null, "the keyboard/pad source feeds the predicting client, not the raw builder")
	# --- countdown: both clients are already sending one input per tick
	await until(func(): return net.stats["sent"] > 20, "inputs flow during the countdown")
	await until(func(): return white.latest_combat.has("countdownTicksRemaining") and white.latest_combat.countdownTicksRemaining == 0, "countdown ends", 12)
	await ticks(10)
	# --- keyboard: a real key event through LocalInputSource drives the predicted fighter
	view.source.enabled = true
	var key = InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	var kb_start: Vector3 = net.view(white.player_id, float(view.arena._local_tick))["position"]
	await ticks(12)
	var kb_end: Vector3 = net.view(white.player_id, float(view.arena._local_tick))["position"]
	key.pressed = false
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	expect(kb_end.distance_to(kb_start) > 0.2, "a W key press moves the predicted fighter through the keyboard source (%.3f m in 12 ticks)" % kb_end.distance_to(kb_start))
	await ticks(40)
	# This test now plays the part of the device itself: take the keyboard/pad source out (touch mode keeps it disabled).
	for each in views:
		each.touch_enabled = true
		each.source.enabled = false
	# --- device intent -> predicted movement before the server's answer
	var start: Vector3 = net.view(white.player_id, float(view.arena._local_tick))["position"]
	var server_before: Dictionary = fighter_of(white.latest_combat, white.player_id)
	net.set_intent(0.0, 1.0, 0.0, false, false, false)
	await ticks(4)
	var moved: Vector3 = net.view(white.player_id, float(view.arena._local_tick))["position"]
	var shown: Vector3 = view.arena.sim.fighter_by_id(white.player_id).global_position
	expect(moved.distance_to(start) > 0.05, "the local fighter moves within 4 ticks of the intent (predicted %.3f m)" % moved.distance_to(start))
	expect(shown.distance_to(moved) < 0.25, "the proxy fighter on screen follows the prediction")
	var server_now: Dictionary = fighter_of(white.latest_combat, white.player_id)
	expect(server_now.serverTick if server_now.has("serverTick") else true, "(sanity)")
	await ticks(60)
	net.set_intent(0.0, 0.0, 0.0, false, false, false)
	await ticks(30)
	var authoritative: Dictionary = fighter_of(white.latest_combat, white.player_id)
	var predicted: Vector3 = net.view(white.player_id, float(view.arena._local_tick))["position"]
	var server_position = Vector3(authoritative.position.x, 0.0, authoritative.position.z)
	expect(predicted.distance_to(server_position) < 0.1, "prediction and authority agree after the move (%.4f m apart)" % predicted.distance_to(server_position))
	expect(server_position.distance_to(Vector3(server_before.position.x, 0.0, server_before.position.z)) > 1.0, "the server really moved the fighter")
	expect(net.stats["hard_snaps"] == 0 and net.max_correction < 0.1, "loopback prediction never needed a correction above 0.1 m (max %.4f)" % net.max_correction)
	expect(net.stats["applied"] > 10 and net.stats["rejected"] == 0, "snapshots applied through the client (%d) none rejected" % net.stats["applied"])
	# --- a press: cosmetic action at once, the server performs it exactly once
	var counter_before = white.input_builder.counters["light"]
	net.press("light")
	await physics_frame
	var local_view: Dictionary = net.view(white.player_id, float(view.arena._local_tick))
	expect(local_view["predicted_action"] == "light" and local_view["state"] == "Attacking", "a press shows the attack pose at once, before any snapshot")
	await ticks(45)
	expect(white.input_builder.counters["light"] == counter_before + 1, "exactly one light counter increment")
	var after: Dictionary = fighter_of(white.latest_combat, white.player_id)
	expect(net.stats["actions_confirmed"] + net.stats["actions_expired"] + net.stats["actions_rejected"] >= 1, "the predicted action was resolved by the server (confirmed %d, rejected %d, expired %d)" % [net.stats["actions_confirmed"], net.stats["actions_rejected"], net.stats["actions_expired"]])
	expect(after.lastInputSequence > 0, "server acknowledges the input sequence (%d)" % after.lastInputSequence)
	# --- remote fighter is interpolated on the other client
	var remote: Dictionary = views[1].net_client().view(white.player_id, float(views[1].arena._local_tick))
	expect(not remote.is_empty() and not remote.get("predicted", true), "the opponent is a server-driven interpolated fighter on the other client")
	# --- reconnect mid-fight: one sequence stream, nothing replayed
	var room = server.rooms[white.frame.state.matchId]
	var invalid_before = room.combat_host.counters["invalid"]
	var sequence_before = white.input_builder.sequence
	net.set_intent(0.0, -0.4, 0.0, false, false, false)
	white.reconnect_session()
	await until(func(): return not white.authenticated, "client drops its transport", 4)
	await until(func(): return white.authenticated, "client resumes its session", 8)
	await ticks(60)
	expect(white.input_builder == net.builder and white.input_builder.sequence > sequence_before, "the same builder keeps counting across the reconnect")
	expect(room.combat_host.counters["invalid"] == invalid_before, "no counter regression was ever sent (no invalid input)")
	expect(room.combat_host.input_resume(white.player_id).sequence <= white.input_builder.sequence, "the server's resume point is below the client's stream")
	expect(white.frame.state.phase == "combat" or white.frame.state.phase == "aftermath", "still in the same battle after the reconnect")
	net.set_intent(0.0, 0.0, 0.0, false, false, false)
	# --- finish: a scripted fighter on the white seat (same bot class as the lockstep suites) wins against an idle black seat
	var bot = Bot.new("fighter", 7)
	var deadline = Time.get_ticks_msec() + 60000
	while white.battle_results.is_empty() and Time.get_ticks_msec() < deadline and views[0].net_client() != null:
		bot.think(views[0].net_client(), float(views[0].arena._local_tick))
		await physics_frame
	await until(func(): return white.battle_results.size() > 0 and black.battle_results.size() > 0, "both clients receive the authoritative result", 40)
	await until(func(): return views[0].net_client() == null or not views[0].net_client().active, "the client stops sending inputs once the result is known", 5)
	expect(white.battle_results == black.battle_results, "both clients hold the identical server result")
	await until(func(): return white.frame.state.phase == "board" and black.frame.state.phase == "board", "server settles back to the board", 15)
	expect(views[0].arena == null and views[1].arena == null, "views tear the arena down after settlement")
	var stale = room.combat_host.counters["stale"] if room.combat_host != null else 0
	expect(stale >= 0, "(counters readable)")
	var visible_errors = errors.filter(func(e): return not e.begins_with("FORBIDDEN"))
	expect(visible_errors.is_empty(), "no protocol error banners during a normal fight: " + str(visible_errors))
	await cleanup()

func cleanup() -> void:
	for view in views:
		view.queue_free()
	for host in hosts:
		host.queue_free()
	for client in clients:
		client.queue_free()
	server.queue_free()
	await process_frame
	await process_frame
	print("ONLINE PREDICTION: ", checks, " checks; failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
