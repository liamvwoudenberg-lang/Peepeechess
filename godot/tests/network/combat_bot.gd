extends SceneTree
## Independent process for the online combat end-to-end test (scripts/test-online-combat.mjs). It is a real client:
## OnlineChessClient over ENet/DTLS to the dedicated server (usually through a UDP latency/loss proxy), the real
## OnlineCombatView mounting the real CombatArena in its network-client mode (prediction, reconciliation, interpolation),
## and a scripted "device" that feeds the predicted fighter through net_client().set_intent()/press() exactly like the
## keyboard, gamepad and touch adapters do. It reports what it measured to a JSON file.
##
## Options (--name=value): seat=w|b port ca invite report line mode seed battles cooldown_scale
##   mode: fight (two scripted fighters), parry (both seats attack on the same server tick and react with parries),
##         reconnect (seat w reconnects voluntarily mid-fight; the harness blacks out seat b's link), invalid (seat b also
##         sends forged/replayed/malformed packets).
const Client = preload("res://network/client/network_client.gd")
const View = preload("res://network/client/online_combat_view.gd")
const Bot = preload("res://combat/net/net_bot.gd")
const LINES = {
	"p-p": "e2e4 d7d5 e4d5",
	"n-p": "b1c3 d7d5 c3d5",
	"b-p": "e2e4 d7d5 f1b5 c7c6 b5c6",
	"r-p": "h2h4 a7a6 h4h5 b7b6 h1h3 c7c6 h3g3 d7d6 g3g7",
	"q-p": "e2e4 e7e5 d1h5 b8c6 h5e5",
	"p-n": "e2e4 g8f6 e4e5 d7d6 e5f6",
	"n-q": "e2e4 e7e5 g1f3 d8h4 f3h4",
	"b-n": "e2e4 b8c6 f1b5 a7a6 b5c6",
	"p-p-black": "e2e4 d7d5 a2a3 d5e4",
}
var client
var view
var host
var behavior
var options = {}
var seat = "w"
var line = "p-p"
var mode = "fight"
var moves: Array = []
var expected_battles = 1
var reports: Dictionary = {"boards": {}, "battles": {}, "battleStats": {}, "errors": [], "protocolCodes": {}, "welcomes": 0, "reconnected": false, "events": [], "connectionEvents": [], "pressVisualMs": [], "pressConfirmMs": [], "notes": []}
var _created = false
var _joined = false
var _ready_sent = false
var _sent_revision = -1
var _deadline = 0
var _closing = false
var _resigned = false
var _reconnect_done = false
var _pending_press: Dictionary = {}
var _press_seen = 0
var _bad_steps: Dictionary = {}
var _last_bad_tick = -1000
var _fire_cycle = -1
var _parry_seen_at = -1
var _parry_done = false
var _event_ids: Dictionary = {}

func _init() -> void:
	call_deferred("run")

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts = arg.trim_prefix("--").split("=", true, 1)
		options[parts[0]] = parts[1] if parts.size() > 1 else "true"
	seat = options.get("seat", "w")
	line = options.get("line", "p-p")
	mode = options.get("mode", "fight")
	expected_battles = int(options.get("battles", "1"))
	moves = LINES[line].split(" ")
	_deadline = Time.get_ticks_msec() + 160000
	client = Client.new()
	root.add_child(client)
	host = SubViewport.new()
	host.own_world_3d = true
	host.size = Vector2i(320, 180)
	root.add_child(host)
	view = View.new()
	root.add_child(view)
	view.setup(client, host)
	# The scripted device owns the fighter: keep the keyboard/pad source out of the way (touch mode keeps it disabled).
	view.touch_enabled = true
	behavior = Bot.new("fighter", int(options.get("seed", "1")) * 10 + (1 if seat == "w" else 2))
	behavior.cooldown_scale = float(options.get("cooldown_scale", "1.0"))
	client.session_ready.connect(_welcome)
	client.frame_received.connect(_frame)
	client.battle_result_received.connect(_result)
	client.protocol_error.connect(_error)
	client.connection_changed.connect(func(connected): reports.connectionEvents.append({"connected": connected, "ms": Time.get_ticks_msec()}))
	if client.connect_server("127.0.0.1", int(options.port), options.ca) != OK:
		finish(false, "could not connect")

func _welcome(_value: Dictionary) -> void:
	reports.welcomes += 1
	if reports.welcomes > 1:
		reports.reconnected = true
	if seat == "w" and not _created:
		_created = true
		client.create_match("battle", 0)

func _frame(frame: Dictionary) -> void:
	if _closing:
		return
	view.sync(frame)
	if view.source != null:
		view.source.enabled = false
	if seat == "w":
		var file = FileAccess.open(options.invite, FileAccess.WRITE)
		file.store_string(frame.state.matchId)
		file.close()
	reports.boards[str(frame.state.chess.revision)] = frame.state.chess.duplicate(true)
	if frame.state.phase == "aftermath" and frame.state.combat != null and frame.state.combat.result != null:
		reports.battles[frame.state.combat.battleId] = frame.state.combat.result.duplicate(true)
	if not _ready_sent:
		_ready_sent = true
		client.command("ready")
	if frame.status == "complete":
		reports.final = frame.state.duplicate(true)
		return
	if frame.status != "active" or frame.state.phase != "board" or _sent_revision == frame.state.chess.revision:
		return
	var ply: int = frame.state.chess.ply
	var turn_seat = "w" if ply % 2 == 0 else "b"
	if ply < moves.size():
		if turn_seat == seat:
			_sent_revision = frame.state.chess.revision
			client.chess_move(moves[ply].substr(0, 2), moves[ply].substr(2, 2))
	elif seat == "w" and not _resigned and reports.battles.size() >= expected_battles:
		_resigned = true
		_sent_revision = frame.state.chess.revision
		client.command("resign")

func _result(result: Dictionary) -> void:
	reports.battles[result.battleId] = result.duplicate(true)
	if view.net_client() != null and view.battle_id == result.battleId:
		reports.battleStats[result.battleId] = _collect(view.net_client())

func _error(value: Dictionary) -> void:
	var key = value.code + ": " + value.message.substr(0, 60)
	reports.protocolCodes[value.code] = int(reports.protocolCodes.get(value.code, 0)) + 1
	if mode == "invalid" and seat == "b":
		return # the point of the exercise: every rejection is expected and counted by code
	if value.code == "FORBIDDEN" and not client.authenticated and reports.welcomes > 0:
		return # Resume can race the previous transport's three-second liveness timeout.
	reports.errors.append(key)
	if value.code == "UNAUTHENTICATED":
		finish(false, value.message)

func _mean(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total = 0.0
	for value in values:
		total += float(value)
	return total / values.size()

func _percentile(values: Array, fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted = values.duplicate()
	sorted.sort()
	return float(sorted[mini(sorted.size() - 1, int(float(sorted.size()) * fraction))])

func _collect(net) -> Dictionary:
	var out = {"stats": net.stats.duplicate(), "rttTicksEstimate": net.rtt_estimate_ticks(), "clockOffset": net.clock_offset}
	out["corrections"] = {"n": net.corrections.size(), "mean": _mean(net.corrections), "p95": _percentile(net.corrections, 0.95), "max": net.max_correction}
	out["catchups"] = {"n": net.catchups.size(), "mean": _mean(net.catchups), "max": _percentile(net.catchups, 1.0)}
	out["unacked"] = net.unacked_count()
	return out

func _on_event(event: Dictionary) -> void:
	reports.events.append({"id": int(event.eventId), "type": event.type, "tick": int(event.tick), "actor": event.actorPlayerId, "target": event.targetPlayerId, "damage": event.get("damage", 0)})

func _physics_process(_delta: float) -> bool:
	if client == null or _closing or view == null:
		return false
	var net = view.net_client()
	if net == null:
		_pending_press.clear()
		return false
	if not net.event_confirmed.is_connected(_on_event):
		net.event_confirmed.connect(_on_event)
	if not client.authenticated or net.latest.is_empty():
		return false
	var tick: int = view.arena._local_tick + 1
	if tick % 30 == 0:
		# keep the latest numbers: a client that was offline when the result arrived never sees the battle end through its arena
		reports.battleStats[client.frame.state.battle.battleId] = _collect(net)
	_measure_presses(net)
	match mode:
		"parry":
			_parry(net, tick)
		_:
			behavior.think(net, tick)
	if mode == "reconnect" and seat == "w" and not _reconnect_done and tick >= 420:
		_reconnect_done = true
		reports.notes.append("voluntary reconnect at local tick %d" % tick)
		client.reconnect_session()
	if mode == "invalid" and seat == "b":
		_invalid(net, tick)
	_start_press_probe(net)
	return false

# ---- input-to-visual latency: press -> the arena's on-screen fighter (predicted) and -> the server's confirmation ----
func _start_press_probe(net) -> void:
	if net.press_log.size() > _press_seen:
		var entry: Dictionary = net.press_log[net.press_log.size() - 1]
		_press_seen = net.press_log.size()
		if net.predicted_action() == entry.action and _pending_press.is_empty():
			_pending_press = {"action": entry.action, "t": Time.get_ticks_usec(), "visual": -1, "confirm": -1, "seq": -1, "tick": entry.tick}

func _measure_presses(net) -> void:
	if _pending_press.is_empty():
		return
	var now = Time.get_ticks_usec()
	var pending_action = net._pending_action
	if int(_pending_press.seq) < 0 and not pending_action.is_empty():
		_pending_press.seq = int(pending_action.get("seq", -1))
	if _pending_press.visual < 0:
		var proxy = view.arena.sim.fighter_by_id(client.player_id)
		if proxy != null and proxy.sm.state not in [CombatConstants.State.IDLE, CombatConstants.State.MOVING, CombatConstants.State.BLOCKING]:
			_pending_press.visual = now - int(_pending_press.t)
	if _pending_press.confirm < 0 and int(_pending_press.seq) >= 0:
		var me: Dictionary = {}
		for f in net.latest.get("fighters", []):
			if f.playerId == client.player_id:
				me = f
		if not me.is_empty() and int(me.lastInputSequence) >= int(_pending_press.seq) and String(me.state) not in ["Idle", "Moving", "Blocking"]:
			_pending_press.confirm = now - int(_pending_press.t)
	if (_pending_press.visual >= 0 and _pending_press.confirm >= 0) or now - int(_pending_press.t) > 1500000:
		if _pending_press.visual >= 0:
			reports.pressVisualMs.append(float(_pending_press.visual) / 1000.0)
		if _pending_press.confirm >= 0:
			reports.pressConfirmMs.append(float(_pending_press.confirm) / 1000.0)
		_pending_press.clear()

# ---- simultaneous attack / parry reaction ----------------------------------------------------------------------------------
func _parry(net, tick: int) -> void:
	var me: Dictionary = net.view(net.local_id, float(tick))
	var opp: Dictionary = net.view(net.opponent_id, float(tick))
	if me.is_empty() or opp.is_empty():
		return
	var to_opp: Vector3 = CombatConstants.flat(opp.position - me.position)
	var yaw = CombatConstants.yaw_of(to_opp) if to_opp.length() > 0.01 else 0.0
	var dir = to_opp.normalized() if to_opp.length() > 0.01 else Vector3.ZERO
	var close = to_opp.length() < 1.75
	net.set_intent(0.0 if close else dir.x, 0.0 if close else dir.z, yaw, true, false, false)
	var request: Dictionary = client.frame.state.battle
	var live = net.view_server_tick(float(tick)) - float(request.startTick + CombatConstants.COUNTDOWN_TICKS)
	# both seats press light when THEIR view reaches the same server tick (each input then arrives one RTT later on both)
	if live >= 60.0 and close:
		var cycle = int((live - 60.0) / 150.0)
		if cycle != _fire_cycle and String(me.state) in ["Idle", "Moving"]:
			_fire_cycle = cycle
			net.press("light")
			_parry_done = false
			_parry_seen_at = -1
	if String(opp.state) == "Attacking" and _parry_seen_at < 0 and String(me.state) in ["Idle", "Moving", "Blocking"]:
		_parry_seen_at = tick
	if _parry_seen_at >= 0 and not _parry_done and tick - _parry_seen_at >= (3 if seat == "w" else 5):
		_parry_done = true
		net.press("parry")
	if String(opp.state) != "Attacking":
		_parry_seen_at = -1

# ---- invalid inputs (seat b) -----------------------------------------------------------------------------------------------
func _invalid(net, tick: int) -> void:
	var step: int = (tick - 190) / 80
	if tick < 190 or (tick - 190) % 80 != 0 or _bad_steps.has(step):
		return
	_bad_steps[step] = true
	var builder = client.input_builder
	var request: Dictionary = client.frame.state.battle
	var send = func(payload: Dictionary, reliable: bool = false) -> void:
		client.transport.send(client.transport.server_peer, client.wire.pack("CombatInput", payload), reliable)
	match step:
		0: # a valid packet and its exact replay: the replay is stale and must change nothing
			var fresh = builder.build(0, 0, 0, true, false, false)
			send.call(fresh)
			send.call(fresh)
			reports.notes.append("replayed sequence %d" % fresh.sequence)
		1: # a packet claiming to be the other seat
			var spoof = builder.build(0, 0, 0, true, false, false)
			spoof.playerId = net.opponent_id
			send.call(spoof)
		2: # another battle's id
			var other = builder.build(0, 0, 0, true, false, false)
			other.battleId = request.matchId + ":duel:99"
			send.call(other)
			net.press("light") # guarantees a non-zero cumulative counter for the regression probe below
		3: # cumulative press counter going backwards (a legal-looking packet that would replay/undo a press)
			var back = builder.build(0, 0, 0, true, false, false)
			for action in ["light", "heavy", "dodge", "parry", "ability"]:
				if int(back[action]) > 0:
					back[action] = int(back[action]) - 1
					reports.notes.append("counter regression sent: " + action)
					send.call(back)
					break
		4: # out-of-range movement vector (schema violation)
			var big = builder.build(0, 0, 0, true, false, false)
			big.moveX = 50.0
			client.transport.send(client.transport.server_peer, JSON.stringify({"type": "CombatInput", "payload": big}).to_utf8_buffer(), false)
		5: # an injected authoritative field
			var forged = builder.build(0, 0, 0, true, false, false)
			forged["damage"] = 99999
			client.transport.send(client.transport.server_peer, JSON.stringify({"type": "CombatInput", "payload": forged}).to_utf8_buffer(), false)
		6: # a client may never send a battle result
			var result = {"schemaVersion": 1, "matchId": request.matchId, "battleId": request.battleId, "expectedRevision": request.expectedRevision, "resolvedTick": request.startTick + 200, "winnerPlayerId": client.player_id, "outcome": "attacker", "reason": "knockout", "attackerHp": 80, "defenderHp": 0}
			client.transport.send(client.transport.server_peer, client.wire.pack("BattleResult", result), true)
		7: # valid input but on the reliable channel
			var wrong = builder.build(0, 0, 0, true, false, false)
			send.call(wrong, true)

func _process(_delta: float) -> bool:
	if _closing:
		return false
	if reports.has("final"):
		if reports.battles.size() >= expected_battles:
			finish(true)
		return false
	if client != null and client.authenticated and seat == "b" and not _joined and FileAccess.file_exists(options.invite):
		var id = FileAccess.get_file_as_string(options.invite).strip_edges()
		if not id.is_empty():
			_joined = true
			client.join_match(id)
	if _deadline > 0 and Time.get_ticks_msec() >= _deadline:
		finish(false, "scenario timed out")
	return false

func finish(ok: bool, message: String = "") -> void:
	if _closing:
		return
	_closing = true
	reports.ok = ok
	reports.message = message
	reports.seat = seat
	reports.line = line
	reports.mode = mode
	reports.connected = client.authenticated if client != null else false
	var file = FileAccess.open(options.report, FileAccess.WRITE)
	file.store_string(JSON.stringify(reports, "", true, true))
	file.close()
	print("COMBAT_BOT_DONE seat=", seat, " line=", line, " mode=", mode, " ok=", ok, " ", message)
	if view != null:
		view.stop()
	if client != null:
		await client.disconnect_gracefully()
	for node in [view, host, client]:
		if node != null:
			node.queue_free()
	await process_frame
	await process_frame
	quit(0 if ok else 1)
