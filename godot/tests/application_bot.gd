extends "res://tests/network/bot_client.gd"
## Account-authenticated independent client. Reuses the real chess/combat input
## strategy from transport tests, never server internals or fabricated damage.
var _move_after = 0
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts = arg.trim_prefix("--").split("=", true, 1)
		options[parts[0]] = parts[1] if parts.size() > 1 else "true"
	seat = options.get("seat", "w")
	scenario = options.get("scenario", "classic")
	_deadline = Time.get_ticks_msec() + 150000
	_created = true
	_joined = true
	client = Client.new()
	root.add_child(client)
	game = Remote.new()
	game.bind(client)
	client.session_ready.connect(_welcome)
	client.frame_received.connect(_frame)
	client.battle_result_received.connect(func(result): reports.battles[result.battleId] = result.duplicate(true))
	client.protocol_error.connect(_error)
	reports["connectionEvents"] = []
	client.connection_changed.connect(func(connected): reports.connectionEvents.append({"connected":connected, "ms":Time.get_ticks_msec()}))
	var ticket = FileAccess.get_file_as_string(options.ticket_file).strip_edges()
	if ticket.is_empty() or not client.has_method("connect_account_server"):
		finish(false, "account transport unavailable")
		return
	client.connect_account_server("127.0.0.1", int(options.port), ticket, options.get("ca", ""), options.get("insecure_local", "false") == "true")

func _welcome(_value: Dictionary) -> void:
	reports.welcomes += 1
	_move_after = Time.get_ticks_msec() + int(options.get("begin_after", "0"))
	print("ACCOUNT_AUTHENTICATED seat=", seat)
	if client.player_id != options.expected_player:
		finish(false, "dedicated player identity differs from authenticated account")
		return
	if reports.welcomes > 1:
		reports.reconnected = true

func _frame(value: Dictionary) -> void:
	if value.status == "active" and value.state.phase == "board" and Time.get_ticks_msec() < _move_after:
		return
	super._frame(value)

func _process(delta: float) -> bool:
	if _move_after > 0 and Time.get_ticks_msec() >= _move_after and client != null and client.authenticated and not client.frame.is_empty():
		_move_after = 0
		_frame(client.frame)
	return super._process(delta)
