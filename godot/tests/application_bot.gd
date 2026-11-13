extends "res://tests/network/bot_client.gd"
## Account-authenticated independent client. Reuses the real chess/combat input
## strategy from transport tests, never server internals or fabricated damage.
const AccountApi = preload("res://ui/account_api.gd")
const Settings = preload("res://ui/application_settings.gd")
const FriendsPage = preload("res://ui/friends_page.gd")
var _move_after = 0

## Wraps the application's API client for the friends UI smoke: everything passes through to the real service except the seat
## ticket request, which is withheld so the lobby scene never opens (the match itself is played by separate bot clients).
class TicketGuard:
	extends Node
	var inner: Node
	var requested: Array = []
	func call_api(method: int, path: String, body: Dictionary = {}, authenticate: bool = true) -> Dictionary:
		if path == "/v1/tickets":
			requested.append(str(body.get("matchId", "")))
			return {"ok": false, "message": "ticket withheld by the test"}
		return await inner.call_api(method, path, body, authenticate)

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts = arg.trim_prefix("--").split("=", true, 1)
		options[parts[0]] = parts[1] if parts.size() > 1 else "true"
	if options.get("smoke_api", "false") == "true":
		_api_smoke()
		return
	if options.get("smoke_friends", "false") == "true":
		_friends_ui_smoke()
		return
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

func _api_smoke() -> void:
	_deadline = Time.get_ticks_msec() + 60000
	Settings.api_url = options.api_url
	Settings.sign_out()
	var credentials = JSON.parse_string(FileAccess.get_file_as_string(options.credentials_file))
	if not _require_api(credentials is Dictionary, "API smoke credentials missing"):
		return
	var api = AccountApi.new()
	root.add_child(api)
	reports["apiChecks"] = []
	var response = await api.authenticate(credentials.username, credentials.password, credentials.displayName, true)
	if not _require_api(response.ok and not Settings.token.is_empty() and Settings.account.get("username") == credentials.username, "API registration failed"):
		return
	var identity = Settings.account.playerId
	reports.apiChecks.append("register")
	Settings.sign_out()
	response = await api.authenticate(credentials.username, credentials.password)
	if not _require_api(response.ok and Settings.account.get("playerId") == identity, "API independent login changed identity"):
		return
	reports.apiChecks.append("login")
	for path in ["/v1/me", "/v1/status", "/v1/history?limit=20", "/v1/history/summary?limit=20&offset=0", "/v1/leaderboard?mode=classic&limit=20"]:
		response = await api.call_api(HTTPClient.METHOD_GET, path)
		if not _require_api(response.ok, "API authenticated read failed: " + path):
			return
		if path.begins_with("/v1/history/summary") and not _require_api(response.data.matches is Array and response.data.matches.is_empty() and response.data.nextOffset == null, "API compact history response invalid"):
			return
		reports.apiChecks.append(path)
	response = await api.call_api(HTTPClient.METHOD_POST, "/v1/queue", {"mode":"classic", "ranked":false, "initialMs":60000, "incrementMs":0})
	if not _require_api(response.ok and response.data.status.queue != null and response.data.status.allocation == null, "API queue enter failed"):
		return
	response = await api.call_api(HTTPClient.METHOD_DELETE, "/v1/queue")
	if not _require_api(response.ok and response.data.status.queue == null, "API queue cancel failed"):
		return
	reports.apiChecks.append("queue/cancel")
	response = await api.call_api(HTTPClient.METHOD_POST, "/v1/private", {"mode":"classic", "initialMs":60000, "incrementMs":0})
	if not _require_api(response.ok and response.data.status.invite != null, "API private invite failed"):
		return
	response = await api.call_api(HTTPClient.METHOD_DELETE, "/v1/queue")
	if not _require_api(response.ok and response.data.status.invite == null, "API private invite cancel failed"):
		return
	reports.apiChecks.append("private/cancel")
	response = await api.call_api(HTTPClient.METHOD_POST, "/v1/auth/logout")
	if not _require_api(response.ok, "API logout failed"):
		return
	response = await api.call_api(HTTPClient.METHOD_GET, "/v1/me")
	if not _require_api(not response.ok and Settings.token.is_empty() and Settings.account.is_empty(), "API unauthorized response did not clear account session"):
		return
	reports.apiChecks.append("logout/401-signout")
	api.queue_free()
	finish(true)

func _wait_for(condition: Callable, timeout_ms: int) -> bool:
	var until = Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < until:
		if condition.call():
			return true
		await process_frame
	return false

## The real application scene and Friends page against the real account service. This process plays one friend through the
## UI (accept the incoming request, challenge, wait for the allocation); the test harness plays the other friend over HTTP.
func _friends_ui_smoke() -> void:
	_deadline = Time.get_ticks_msec() + 100000
	Settings.api_url = options.api_url
	Settings.loaded = true  # keep the harness's service address; never read preferences
	Settings.sign_out()
	var credentials = JSON.parse_string(FileAccess.get_file_as_string(options.credentials_file))
	if not _require_api(credentials is Dictionary, "friends UI credentials missing"):
		return
	var login = AccountApi.new()
	root.add_child(login)
	var response = await login.authenticate(credentials.username, credentials.password)
	login.queue_free()
	if not _require_api(response.ok, "friends UI sign-in failed: " + str(response.get("message", ""))):
		return
	root.size = Vector2i(1280, 800)
	var app = load("res://ui/application.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	var guard = TicketGuard.new()
	guard.inner = app.api
	app.add_child(guard)
	app.api = guard
	reports["friendsUi"] = []
	app.navigate("friends")
	if not _require_api(await _wait_for(func(): return app.friends_loaded and app.friends.incoming.size() == 1, 20000), "the friend request never appeared on the Friends page"):
		return
	if not _require_api(app.friends.incoming[0].username == options.other_username and app._menu_buttons.friends.text == "Friends · 1", "the request or the Friends badge is wrong"):
		return
	reports.friendsUi.append("request visible with badge")
	app.friend_lists.find_child("AcceptRequest", true, false).pressed.emit()
	if not _require_api(await _wait_for(func(): return app.friends.friends.size() == 1 and app.friends.incoming.is_empty(), 15000), "accepting the request in the UI did not add the friend"):
		return
	reports.friendsUi.append("accepted through the UI")
	var buttons = app.friend_lists.find_children("ChallengeFriend", "Button", true, false)
	if not _require_api(buttons.size() == 1 and not buttons[0].disabled, "the new friend cannot be challenged"):
		return
	FriendsPage.challenge(app, str(options.other_id), {"mode": "classic", "time": 0, "side": "white"})
	if not _require_api(await _wait_for(func(): return app.friends.challenges.outgoing != null and app.status.invite != null, 15000), "the sent challenge never showed as waiting"):
		return
	reports.friendsUi.append("challenge sent")
	print("FRIENDS_UI_CHALLENGED")
	if not _require_api(await _wait_for(func(): return app.status.allocation != null and not guard.requested.is_empty(), 60000), "the accepted challenge never produced an allocation"):
		return
	reports["allocation"] = app.status.allocation.duplicate(true)
	reports.friendsUi.append("allocation received after the friend accepted")
	finish(true)

func _require_api(condition: bool, message: String) -> bool:
	if not condition:
		finish(false, message)
	return condition
