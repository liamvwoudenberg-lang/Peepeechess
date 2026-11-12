extends Control
const AppSettings = preload("res://ui/application_settings.gd")
const AppResults = preload("res://ui/results.gd")
const Kit = preload("res://ui/theme/ui_kit.gd")
const Tokens = preload("res://ui/theme/ui_tokens.gd")
var _result_key = ""
var _provisioned = false
var _connection_row: Control
var _lobby_row: Control
const Client = preload("res://network/client/network_client.gd")
const Remote = preload("res://network/client/remote_match.gd")
const Interaction = preload("res://boards/board_interaction.gd")
const Board2D = preload("res://boards/board_2d.gd")
const Board3D = preload("res://boards/board_3d.gd")
const CombatView = preload("res://network/client/online_combat_view.gd")
const Touch = preload("res://network/client/touch_combat_input.gd")
var client: OnlineChessClient
var game: RemoteChessMatch
var interaction: BoardInteraction
var board_2d: ChessBoard2D
var board_3d: ChessBoard3D
var combat_view: OnlineCombatView
var combat_host: SubViewport
var combat_container: SubViewportContainer
var touch_controls: OnlineTouchCombatInput
var hostname: LineEdit
var port: SpinBox
var ca_path: LineEdit
var match_id: LineEdit
var info: Label
var notices: Label
var history: RichTextLabel
var board_host: Control
var view_button: Button
var ready_button: Button
var accept_draw: Button
var touch_toggle: CheckButton
var input_select: OptionButton
var _view_3d = false
var _flipped = false
var _displayed_phase = "board"
var _last_clock_tick = -1
var _capture: Dictionary = {}
var capture_dialog: ConfirmationDialog
var promotion_dialog: AcceptDialog
var _promotion: Dictionary = {}

func _ready() -> void:
	AppSettings.load_preferences()
	AppSettings.ensure_platform(get_tree())
	client = Client.new()
	add_child(client)
	game = Remote.new()
	game.bind(client)
	interaction = Interaction.new(game)
	interaction.move_requested.connect(_move_intent)
	_build_ui()
	combat_view = CombatView.new()
	add_child(combat_view)
	combat_view.setup(client, combat_host)
	touch_controls.client = client
	touch_controls.view = combat_view
	client.connection_changed.connect(_connection)
	client.frame_received.connect(_frame)
	client.clocks_received.connect(_clocks)
	client.protocol_error.connect(func(error): notices.text = error.code + ": " + error.message)
	client.session_ready.connect(func(welcome): notices.text = "Authenticated · Combat roles: " + ", ".join(welcome.combatRoles))
	capture_dialog = ConfirmationDialog.new()
	capture_dialog.title = "Confirm capture duel"
	capture_dialog.confirmed.connect(_confirm_capture)
	add_child(capture_dialog)
	promotion_dialog = AcceptDialog.new()
	promotion_dialog.title = "Choose promotion"
	promotion_dialog.get_ok_button().hide()
	var row = HBoxContainer.new()
	promotion_dialog.add_child(row)
	for role in ["q", "r", "b", "n"]:
		var selected = role
		_button(row, {"q":"Queen", "r":"Rook", "b":"Bishop", "n":"Knight"}[role], func(): promotion_dialog.hide(); _move(_promotion.from, _promotion.to, selected))
	add_child(promotion_dialog)
	set_view(AppSettings.preferred_3d)
	board_2d.animation_enabled = AppSettings.animations
	board_3d.animation_enabled = AppSettings.animations
	touch_toggle.button_pressed = AppSettings.touch_controls
	PadUi.install(self, {"board": true})  # pad board cursor + menu focus (claude/pads-input)
	var launch = AppSettings.take_launch()
	if launch.has("allocation") and launch.has("ticket"):
		_provisioned = true
		_connect_allocation(launch)

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button = Button.new()
	button.text = text
	button.custom_minimum_size.y = Kit.target_height()
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _label(parent: Node, text: String) -> Label:
	var label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _build_ui() -> void:
	Kit.install(self)
	var background = ColorRect.new()
	background.color = Tokens.BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(background)
	var margin = Kit.safe_frame(self, 12)
	var column = VBoxContainer.new()
	margin.add_child(column)
	_label(column, "PEEPEECHESS · Online native crossplay")
	var connection_row = HFlowContainer.new()
	column.add_child(connection_row)
	_connection_row = connection_row
	hostname = LineEdit.new()
	hostname.text = "localhost"
	hostname.placeholder_text = "Server hostname"
	hostname.custom_minimum_size = Vector2(180, 42)
	connection_row.add_child(hostname)
	port = SpinBox.new()
	port.min_value = 1
	port.max_value = 65535
	port.value = 2456
	connection_row.add_child(port)
	ca_path = LineEdit.new()
	ca_path.placeholder_text = "Custom CA certificate (optional)"
	ca_path.custom_minimum_size = Vector2(230, 42)
	connection_row.add_child(ca_path)
	_button(connection_row, "Connect / resume", func(): client.connect_server(hostname.text.strip_edges(), int(port.value), ca_path.text.strip_edges()))
	_button(connection_row, "Local game", _return_local)
	_button(column, "Main menu", _return_menu)
	var lobby = HFlowContainer.new()
	column.add_child(lobby)
	_lobby_row = lobby
	_button(lobby, "Create Classic · 10 min", func(): client.create_match("classic", 600000))
	_button(lobby, "Create Battle C0", func(): client.create_match("battle", 0))
	match_id = LineEdit.new()
	match_id.placeholder_text = "Private match invite ID"
	match_id.custom_minimum_size = Vector2(250, 42)
	lobby.add_child(match_id)
	_button(lobby, "Join", func(): client.join_match(match_id.text.strip_edges()))
	_button(lobby, "Copy invite", func(): DisplayServer.clipboard_set(match_id.text))
	ready_button = _button(lobby, "Ready", func(): client.command("ready"))
	var actions = HFlowContainer.new()
	column.add_child(actions)
	view_button = _button(actions, "3D board", func(): set_view(not _view_3d))
	_button(actions, "Flip board", func(): set_flipped(not _flipped))
	_button(actions, "Offer draw", func(): client.command("offer_draw"))
	accept_draw = _button(actions, "Accept draw", func(): client.command("accept_draw"))
	_button(actions, "Claim draw", _claim_draw)
	_button(actions, "Resign", _resign)
	input_select = OptionButton.new()
	input_select.add_item("Keyboard / mouse")
	input_select.add_item("Gamepad 1")
	input_select.custom_minimum_size.y = 42
	input_select.item_selected.connect(func(index): combat_view.input_scheme = "kb1" if index == 0 else InputAssignment.first_pad_scheme(); if_source_scheme())
	actions.add_child(input_select)
	touch_toggle = CheckButton.new()
	touch_toggle.text = "Touch combat"
	touch_toggle.button_pressed = DisplayServer.is_touchscreen_available()
	touch_toggle.toggled.connect(func(on): _set_touch(on))
	actions.add_child(touch_toggle)
	_button(actions, "Capture mouse", _capture_mouse)
	info = _label(column, "Connect securely to a dedicated server. Invite a second player, then both choose Ready.")
	notices = _label(column, "Choose your own board view. Esc releases the combat mouse.")
	var split = HBoxContainer.new()
	split.size_flags_vertical = SIZE_EXPAND_FILL
	column.add_child(split)
	board_host = Control.new()
	board_host.size_flags_horizontal = SIZE_EXPAND_FILL
	board_host.size_flags_vertical = SIZE_EXPAND_FILL
	board_host.custom_minimum_size = Vector2(260, 300)
	split.add_child(board_host)
	board_2d = Board2D.new()
	board_2d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board_host.add_child(board_2d)
	board_2d.setup(game, interaction)
	board_3d = Board3D.new()
	board_3d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board_host.add_child(board_3d)
	board_3d.setup(game, interaction)
	board_3d.visible = false
	board_3d.viewport_3d.render_target_update_mode = SubViewport.UPDATE_DISABLED
	history = RichTextLabel.new()
	history.custom_minimum_size.x = 165
	history.mouse_filter = MOUSE_FILTER_IGNORE
	split.add_child(history)
	resized.connect(func(): history.visible = size.x >= 700)
	history.visible = size.x >= 700
	combat_container = SubViewportContainer.new()
	combat_container.stretch = true
	combat_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	combat_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board_host.add_child(combat_container)
	combat_host = SubViewport.new()
	combat_host.own_world_3d = true
	combat_host.handle_input_locally = false
	combat_host.size = Vector2i(900, 600)
	combat_container.add_child(combat_host)
	combat_container.visible = false
	touch_controls = Touch.new()
	touch_controls.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board_host.add_child(touch_controls)
	touch_controls.visible = false

func if_source_scheme() -> void:
	if combat_view.source != null:
		combat_view.source.scheme = combat_view.input_scheme
		combat_view.source.mouse_look = combat_view.input_scheme == "kb1"

func _set_touch(on: bool) -> void:
	combat_view.touch_enabled = on
	touch_controls.enabled = on
	touch_controls.visible = on and combat_container.visible
	if combat_view.source != null:
		combat_view.source.enabled = not on and client.authenticated

func _connection(connected: bool) -> void:
	interaction.enabled = connected
	if combat_view.source != null:
		combat_view.source.enabled = connected and not combat_view.touch_enabled
	if not connected:
		notices.text = "Disconnected · input disabled; attempting session recovery. The server keeps running."

func _frame(value: Dictionary) -> void:
	_last_clock_tick = value.state.serverTick
	match_id.text = value.state.matchId
	ready_button.disabled = value.status != "waiting"
	accept_draw.disabled = value.drawOffer == null or value.drawOffer == client.player_id or value.state.phase != "board"
	var seat = "White" if value.state.players.w == client.player_id else "Black"
	var phase: String = value.state.phase
	info.text = "%s · %s · %s\nWhite %s · Black %s · %s" % [seat, value.status, phase, _time(value.clocks.whiteMs, value.clocks.timed), _time(value.clocks.blackMs, value.clocks.timed), value.state.reason if value.state.reason != null else ("White" if game.engine.turn == "w" else "Black") + " to move"]
	if value.drawOffer != null:
		notices.text = "Draw offered by " + ("you" if value.drawOffer == client.player_id else "your opponent")
	history.clear()
	for i in value.state.chess.history.size():
		var h: Dictionary = value.state.chess.history[i]
		history.add_text("%d. %s%s%s\n" % [i + 1, h.from, h.to, " [defended]" if h.outcome == "defender" else ""])
	var in_combat = phase in ["combat", "aftermath"]
	AppSettings.set_combat_input(in_combat)
	if in_combat and _displayed_phase == "board":
		get_viewport().gui_release_focus()
	board_2d.set_process_input(not in_combat)
	board_3d.set_process_input(not in_combat)
	interaction.enabled = not in_combat and client.authenticated
	combat_container.visible = in_combat
	set_view(_view_3d)
	combat_host.render_target_update_mode = SubViewport.UPDATE_ALWAYS if in_combat else SubViewport.UPDATE_DISABLED
	combat_view.sync(value)
	_set_touch(touch_toggle.button_pressed)
	if phase == "aftermath" and value.state.combat != null and value.state.combat.result != null:
		var result: Dictionary = value.state.combat.result
		notices.text = ("Attacker" if result.outcome == "attacker" else "Defender") + " wins · " + result.reason.replace("_", " ")
	if _displayed_phase in ["combat", "aftermath"] and not in_combat:
		board_host.modulate.a = 0.5
		create_tween().tween_property(board_host, "modulate:a", 1.0, 0.4)
	if phase == "complete" and _result_key != value.state.matchId:
		_result_key = value.state.matchId
		call_deferred("_show_online_result", value.duplicate(true))
	_displayed_phase = phase
	if not _capture.is_empty() and (_capture.revision != game.revision or _capture.matchId != game.match_id or phase != "board"):
		capture_dialog.hide()
		_capture.clear()

func _clocks(sync: Dictionary) -> void:
	if sync.serverTick < _last_clock_tick or client.frame.is_empty():
		return
	_last_clock_tick = sync.serverTick
	var value = client.frame.duplicate(true)
	value.clocks = sync.clocks
	value.connected = sync.connected
	# Update text without rebuilding board state or combat presentation.
	var seat = "White" if value.state.players.w == client.player_id else "Black"
	info.text = "%s · %s · %s\nWhite %s · Black %s · %s" % [seat, value.status, value.state.phase, _time(sync.clocks.whiteMs, sync.clocks.timed), _time(sync.clocks.blackMs, sync.clocks.timed), value.state.reason if value.state.reason != null else ("White" if game.engine.turn == "w" else "Black") + " to move"]

func _time(ms: int, timed: bool) -> String:
	return "%d:%02d" % [ms / 60000, ms / 1000 % 60] if timed else "untimed"

func _move_intent(from: String, to: String, promotion_needed: bool) -> void:
	if promotion_needed:
		_promotion = {"from": from, "to": to}
		promotion_dialog.popup_centered()
	else:
		_move(from, to, "q")

func _move(from: String, to: String, promotion: String) -> void:
	if not game.board_input_allowed():
		return
	if client.frame.state.mode == "battle":
		var inspected = game.engine.inspect_move(from, to, promotion)
		if inspected.ok and game.engine.is_capture(inspected.move):
			var m: Dictionary = inspected.move
			var victim: int = m.to + (-8 if game.engine.turn == "w" else 8) if m.flag == "ep" else m.to
			var roles = [game.engine.board[m.from].to_lower(), game.engine.board[victim].to_lower()]
			if not roles.all(func(role): return role in client.combat_roles):
				notices.text = "This capture needs a fighter that is not implemented on the server yet."
				return
			_capture = {"from": from, "to": to, "promotion": promotion, "revision": game.revision, "matchId": game.match_id}
			capture_dialog.dialog_text = "%s → %s\nAttacker wins: captures on %s.\nDefender wins: attacker removed, defender stays.\nThe server starts and settles the duel." % [from, to, to]
			capture_dialog.popup_centered()
			return
	game.play(from, to, promotion)

func _confirm_capture() -> void:
	capture_dialog.hide()
	if not _capture.is_empty() and _capture.revision == game.revision and _capture.matchId == game.match_id:
		game.play(_capture.from, _capture.to, _capture.promotion)
	_capture.clear()

func _claim_draw() -> void:
	if not game.board_input_allowed():
		return
	var claims = game.engine.claimable_draws()
	if claims.is_empty():
		notices.text = "No immediate draw claim is available. The protocol also supports claims with an intended move."
	else:
		client.command("claim_draw", claims[0])

func _resign() -> void:
	if client.frame.is_empty():
		return
	var dialog = ConfirmationDialog.new()
	dialog.dialog_text = "Resign your online seat?"
	dialog.confirmed.connect(func(): client.command("resign"); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()

func set_view(use_3d: bool) -> void:
	_view_3d = use_3d
	AppSettings.preferred_3d = use_3d
	AppSettings.save_preferences()
	var board_visible = client.frame.is_empty() or client.frame.state.phase not in ["combat", "aftermath"]
	board_2d.visible = board_visible and not use_3d
	board_3d.visible = board_visible and use_3d
	board_3d.viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS if board_3d.visible else SubViewport.UPDATE_DISABLED
	view_button.text = "2D board" if use_3d else "3D board"

func _capture_mouse() -> void:
	if combat_view.arena != null:
		get_viewport().gui_release_focus()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _return_local() -> void:
	notices.text = "Disconnecting…"
	await client.disconnect_gracefully()
	get_tree().change_scene_to_file("res://app/main.tscn")

func set_flipped(flipped: bool) -> void:
	_flipped = flipped
	board_2d.set_flipped(flipped)
	board_3d.set_flipped(flipped)

func _exit_tree() -> void:
	if combat_view != null:
		combat_view.stop()
	if interaction != null:
		interaction.dispose()

func _connect_allocation(launch: Dictionary) -> void:
	var allocation: Dictionary = launch.allocation
	var endpoint: Dictionary = allocation.endpoint
	var ca_file = ""
	if not str(endpoint.get("caCertificate", "")).is_empty():
		var pem = str(endpoint.caCertificate)
		if pem.length() > 65536 or not pem.begins_with("-----BEGIN CERTIFICATE-----"):
			notices.text = "The account service returned an invalid server certificate."
			return
		ca_file = "user://dedicated-ca.crt"
		var file = FileAccess.open(ca_file, FileAccess.WRITE)
		if file == null:
			notices.text = "Could not store the trusted server certificate."
			return
		file.store_string(pem)
		file.close()
	match_id.text = allocation.matchId
	hostname.text = str(endpoint.host)
	port.value = int(endpoint.port)
	_connection_row.hide()
	_lobby_row.hide()
	# A provisioned account already owns a seat. Ready still requires a deliberate tap.
	_button(info.get_parent(), "Ready to play", func(): client.command("ready"))
	notices.text = "Connecting to your " + ("ranked" if allocation.ranked else "unranked") + " " + str(allocation.mode).capitalize() + " match…"
	client.call("connect_account_server", str(endpoint.host), int(endpoint.port), str(launch.ticket), ca_file, bool(endpoint.get("insecureLocal", false)), str(endpoint.get("serverName", endpoint.host)))
	set_view(bool(launch.get("view3d", AppSettings.preferred_3d)))

func _show_online_result(value: Dictionary) -> void:
	if not is_inside_tree():
		return
	var data = {"result": value.state.result, "reason": value.state.reason, "mode": value.state.mode, "plies": value.state.chess.history.size(), "playerId": client.player_id, "players": value.state.players}
	AppResults.show_dialog(self, data, func(): pass, _return_menu_now)

func _return_menu() -> void:
	if client.frame.is_empty() or client.frame.status == "complete":
		_return_menu_now()
		return
	var dialog = ConfirmationDialog.new()
	dialog.title = "Leave online match?"
	dialog.dialog_text = "The server keeps the match running. Leaving an active match can forfeit your seat after the reconnect timeout."
	dialog.ok_button_text = "Leave match"
	dialog.confirmed.connect(func(): dialog.queue_free(); _return_menu_now())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()

func _return_menu_now() -> void:
	notices.text = "Disconnecting…"
	await client.disconnect_gracefully()
	get_tree().change_scene_to_file("res://ui/application.tscn")
