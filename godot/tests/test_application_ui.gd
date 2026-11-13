extends SceneTree
const Scene = preload("res://ui/application.tscn")
const Settings = preload("res://ui/application_settings.gd")
const Api = preload("res://ui/account_api.gd")
const Results = preload("res://ui/results.gd")
const Local = preload("res://app/main.tscn")
const FriendsPage = preload("res://ui/friends_page.gd")
var checks = 0
var failures: Array = []
var shell: Control
class HistoryApi:
	extends Node
	signal proceed
	var requests: Array = []
	var replies: Array = []
	var wait_for_reply = false
	func call_api(_method: int, path: String, _body: Dictionary = {}, _authenticate: bool = true) -> Dictionary:
		requests.append(path)
		if wait_for_reply:
			await proceed
		return replies.pop_front()

## Scripted account service for the Friends page: records every request and answers from `routes` ("VERB /path" -> reply).
class FriendsApi:
	extends Node
	var requests: Array = []
	var routes: Dictionary = {}
	func call_api(method: int, path: String, body: Dictionary = {}, _authenticate: bool = true) -> Dictionary:
		var verb: String = {HTTPClient.METHOD_GET: "GET", HTTPClient.METHOD_POST: "POST", HTTPClient.METHOD_DELETE: "DELETE"}.get(method, "?")
		requests.append([verb, path, body])
		return routes.get(verb + " " + path, {"ok": false, "message": "no scripted route for " + verb + " " + path})
	func count(verb_path: String) -> int:
		var total := 0
		for request in requests:
			if request[0] + " " + request[1] == verb_path:
				total += 1
		return total
	func last_body(verb_path: String) -> Dictionary:
		for i in range(requests.size() - 1, -1, -1):
			if requests[i][0] + " " + requests[i][1] == verb_path:
				return requests[i][2]
		return {}

func friends_buttons(named: String) -> Array:
	return shell.friend_lists.find_children(named, "Button", true, false) if is_instance_valid(shell.friend_lists) else []

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL: ", label)

func _init() -> void:
	call_deferred("run")

func screenshot(name: String) -> void:
	if "--screenshots" not in OS.get_cmdline_user_args():
		return
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://" + name + ".png")
	print("Screenshot: ", ProjectSettings.globalize_path("user://" + name + ".png"))

func run() -> void:
	root.size = Vector2i(1280, 800)
	Settings.loaded = true
	Settings.reset_intro()   # a fresh process: the 3D opening screen is due
	Settings.preferred_3d = false
	Settings.token = ""
	Settings.account.clear()
	Settings.launch.clear()
	shell = Scene.instantiate()
	root.add_child(shell)
	await process_frame
	await process_frame
	expect(shell.page == "home" and shell.intro != null and shell.scene3d != null, "application opens on the 3D opening screen")
	expect(shell.content.find_child("ClassicButton", true, false) == null, "the main menu is not shown before a button is pressed")
	var press := InputEventKey.new()
	press.pressed = true
	press.keycode = KEY_ENTER
	root.push_input(press)
	for i in 4:
		if shell.intro != null:
			shell.intro.advance(1.0)   # explicit steps: the glide is 2.4 s
	expect(shell.page == "home" and shell.intro == null and shell.content.find_child("ClassicButton", true, false) != null, "a button press leads from the opening screen to the main menu")
	shell.navigate("play")
	await process_frame
	expect(root.get_node_or_null("PlatformInput") != null, "application installs persistent controller adapter")
	expect(shell.content.get_child_count() >= 4, "mode cards and game setup rendered")
	await screenshot("application-play")
	for target in ["account", "settings", "profile", "history", "leaderboard", "friends", "play"]:
		shell.navigate(target)
		expect(shell.page == target and shell.content.get_child_count() >= 3, "navigation opens " + target)
	shell.selected_mode = "classic"
	shell.selected_time = 2
	expect(shell.match_options() == {"mode": "classic", "ranked": false, "initialMs": 600000, "incrementMs": 0}, "Classic setup selects supported rapid control")
	shell.selected_mode = "battle"
	expect(shell.match_options().initialMs == 0 and shell.match_options().incrementMs == 0, "Battle setup forces C0 untimed clocks")
	shell.online = true
	shell.navigate("play")
	expect(shell.invite_edit == null, "signed-out player gets sign-in gate before online controls")
	Settings.account = {"playerId": "test-profile", "displayName": "Test Knight", "username": "test_knight", "classic": {"rating": 1232, "wins": 2, "losses": 1, "draws": 0, "games": 3}, "battle": {"rating": 1200, "wins": 0, "losses": 0, "draws": 0, "games": 0}}
	Settings.token = "memory-only-test-token"
	shell.navigate("play")
	expect(shell.invite_edit != null and shell.account_badge.text == "Test Knight", "authenticated menu exposes private matches and account")
	shell._accept_status({"ok": true, "data": {"status": {"queue": {"mode": "battle", "ranked": false}, "allocation": null, "invite": null}}}, false)
	expect(shell.queue_label.text.contains("Battle") and shell.queue_label.text.contains("Searching"), "queue state is displayed without changing gameplay")
	shell._accept_status({"ok": true, "data": {"status": {"queue": null, "allocation": null, "invite": {"code": "ABC234", "expiresAt": 999}}}})
	expect(shell.queue_label.text.contains("ABC234"), "private invite status displays server-issued code")
	await screenshot("application-online")
	shell.status = {"queue": null, "allocation": null, "invite": null}
	var history_api = HistoryApi.new()
	shell.api.queue_free()
	shell.api = history_api
	shell.add_child(history_api)
	var summary = {"matchId": "summary-1", "mode": "classic", "ranked": true, "whitePlayerId": "test-profile", "blackPlayerId": "opponent", "whiteName": "Test Knight", "blackName": "Other Knight", "result": "white", "reason": "checkmate", "finalFen": "position", "plies": 73, "completedAt": 1800000000000, "ratingChange": {"white": 16, "black": -16}}
	history_api.replies.append({"ok": true, "data": {"matches": [summary], "nextOffset": 20}})
	shell.navigate("history")
	expect(history_api.requests[-1] == "/v1/history/summary?limit=20&offset=0", "history requests bounded summary page without full move arrays")
	expect(shell._history_more_button != null and shell._history_more_button.text == "Load older matches", "history exposes pagination for older records")
	history_api.wait_for_reply = true
	history_api.replies.append({"ok": false, "message": "Temporary failure"})
	shell._history_more_button.pressed.emit()
	shell._load_history(shell._refresh_generation, 20)
	expect(history_api.requests.size() == 2 and shell._history_more_button.disabled, "duplicate history pagination taps cannot issue concurrent requests")
	history_api.proceed.emit()
	await process_frame
	expect(not shell._history_more_button.disabled, "failed history page can be retried")
	history_api.wait_for_reply = false
	var older = summary.duplicate(true)
	older.matchId = "summary-2"
	history_api.replies.append({"ok": true, "data": {"matches": [older], "nextOffset": null}})
	shell._history_more_button.pressed.emit()
	expect(history_api.requests[-1] == "/v1/history/summary?limit=20&offset=20", "pagination requests server-provided next offset")
	expect(shell._history_more_button == null, "last history page removes older-record button")
	var history_cards = 0
	for child in shell.content.get_children():
		if child is PanelContainer:
			history_cards += 1
	expect(history_cards == 2, "older history summaries append without replacing current records")
	history_api.wait_for_reply = true
	history_api.replies.append({"ok": true, "data": {"matches": [summary], "nextOffset": 20}})
	shell.navigate("history")
	shell.navigate("settings")
	history_api.proceed.emit()
	await process_frame
	expect(shell.page == "settings" and shell._history_more_button == null and not shell._history_loading, "stale history response cannot append records after navigation")
	# ---- Friends: pure helpers first, then the real page against a scripted account service
	var empty_snapshot = FriendsPage.snapshot_from({})
	expect(empty_snapshot.friends.is_empty() and empty_snapshot.challenges.outgoing == null and empty_snapshot.challenges.incoming.is_empty(), "an empty response gives an empty friends snapshot")
	var garbage = FriendsPage.snapshot_from({"friends": "x", "incoming": [1, {"playerId": "p"}], "outgoing": null, "challenges": [1, 2]})
	expect(garbage.friends.is_empty() and garbage.incoming.size() == 1 and garbage.challenges.incoming.is_empty() and garbage.challenges.outgoing == null, "malformed friends data degrades to empty parts instead of crashing")
	expect(FriendsPage.control_text({"mode": "classic", "initialMs": 180000, "incrementMs": 2000}) == "Classic · 3 + 2" and FriendsPage.control_text({"mode": "battle"}) == "Battle · untimed", "a challenge shows its time control")
	expect(FriendsPage.side_text("white") == "you play White" and FriendsPage.side_text("black") == "you play Black" and FriendsPage.side_text("random").contains("random"), "a challenge says which colour the player gets")
	expect(FriendsPage.presence({"inMatch": true, "online": true})[0] == "In a match" and FriendsPage.presence({"online": true})[0] == "Online" and FriendsPage.presence({})[0] == "Offline", "the presence chip prefers in-match over online over offline")
	var order = FriendsPage.sorted_friends([{"displayName": "Zed"}, {"displayName": "bob", "online": true}, {"displayName": "Amy"}, {"displayName": "Cy", "inMatch": true}]).map(func(f): return f.displayName)
	expect(order == ["bob", "Cy", "Amy", "Zed"], "friends who are around come first, then alphabetical (got %s)" % str(order))
	var now_ms = int(Time.get_unix_time_from_system() * 1000.0)
	expect(FriendsPage.minutes_left({"expiresAt": now_ms + 90000}, now_ms) == 2 and FriendsPage.minutes_left({"expiresAt": 0}, 5) == 0 and FriendsPage.minutes_left({"expiresAt": 99999999999999}, 5) == 10, "challenge time left rounds up and stays within the ten minute lifetime")
	var ada = {"playerId": "f-1", "username": "ada", "displayName": "Ada", "online": true, "inMatch": false, "classicRating": 1250, "battleRating": 1180}
	var bob = {"playerId": "f-2", "username": "bob", "displayName": "Bob", "online": false, "inMatch": false, "classicRating": 1200, "battleRating": 1200}
	var cy = {"playerId": "f-3", "username": "cy_cy", "displayName": "Cy", "online": true, "inMatch": true, "classicRating": 1300, "battleRating": 1100}
	var dee = {"playerId": "r-1", "username": "dee", "displayName": "Dee"}
	var eli = {"playerId": "o-1", "username": "eli", "displayName": "Eli"}
	var incoming_challenge = {"code": "ABC234", "player": {"playerId": "f-1", "username": "ada", "displayName": "Ada"}, "mode": "classic", "initialMs": 600000, "incrementMs": 0, "side": "black", "expiresAt": now_ms + 540000}
	var no_challenges = {"incoming": [], "outgoing": null}
	var full = {"friends": [bob, ada, cy], "incoming": [dee], "outgoing": [eli], "challenges": {"incoming": [incoming_challenge], "outgoing": null}}
	expect(FriendsPage.badge_count(full) == 2 and FriendsPage.badge_count({}) == 0, "the badge counts friend requests plus challenges waiting")
	var friends_api = FriendsApi.new()
	shell.api.queue_free()
	shell.api = friends_api
	shell.add_child(friends_api)
	shell.status = {"queue": null, "allocation": null, "invite": null}
	shell._reset_friends()
	friends_api.routes["GET /v1/friends"] = {"ok": true, "data": full}
	shell.navigate("friends")
	await process_frame
	expect(friends_api.count("GET /v1/friends") == 1 and shell.friends.friends.size() == 3, "the Friends page loads its snapshot from the account service")
	expect(shell.friend_lists.get_node_or_null("FriendsCard") != null and shell.friend_lists.get_node_or_null("IncomingChallenges") != null and shell.friend_lists.get_node_or_null("FriendRequests") != null and shell.friend_lists.get_node_or_null("SentRequests") != null, "friends, challenges, requests and sent requests are all listed")
	expect(shell._menu_buttons.friends.text == "Friends · 2", "the Friends button shows how many answers are waiting")
	var challenge_buttons = friends_buttons("ChallengeFriend")
	expect(challenge_buttons.size() == 3 and challenge_buttons.filter(func(b): return b.disabled).size() == 1, "every friend can be challenged except the one who is in a match")
	expect(friends_buttons("AcceptChallenge").size() == 1 and friends_buttons("AcceptRequest").size() == 1 and friends_buttons("CancelRequest").size() == 1, "there are answer buttons for the challenge and the request, and a cancel for the one sent")
	await screenshot("application-friends")
	# Adding a friend by username; polling redraws never wipe the field.
	var field: LineEdit = shell.content.find_child("FriendUsername", true, false)
	field.text = "  "
	field.text_submitted.emit("  ")
	expect(friends_api.count("POST /v1/friends/request") == 0, "an empty username is never sent")
	var requested = full.duplicate(true)
	requested["result"] = "requested"
	friends_api.routes["POST /v1/friends/request"] = {"ok": true, "data": requested}
	field.text = "keep me"
	FriendsPage.draw_lists(shell)
	expect(field.text == "keep me", "redrawing the lists does not erase what the player is typing")
	field.text = "Eve_99"
	shell.content.find_child("SendRequest", true, false).pressed.emit()
	await process_frame
	expect(friends_api.last_body("POST /v1/friends/request") == {"username": "Eve_99"} and field.text == "", "a friend request sends the typed username and clears the field")
	# Accepting a request, then declining a challenge.
	friends_api.routes["POST /v1/friends/accept"] = {"ok": true, "data": {"friends": [ada, bob, cy, dee], "incoming": [], "outgoing": [eli], "challenges": {"incoming": [incoming_challenge], "outgoing": null}}}
	friends_buttons("AcceptRequest")[0].pressed.emit()
	await process_frame
	expect(friends_api.last_body("POST /v1/friends/accept") == {"playerId": "r-1"} and shell.friends.friends.size() == 4 and shell.friends.incoming.is_empty() and shell._menu_buttons.friends.text == "Friends · 1", "accepting a request adds the friend and lowers the badge")
	friends_api.routes["POST /v1/friends/challenge/decline"] = {"ok": true, "data": {"friends": [ada, bob, cy, dee], "incoming": [], "outgoing": [eli], "challenges": no_challenges}}
	friends_buttons("DeclineChallenge")[0].pressed.emit()
	await process_frame
	expect(friends_api.last_body("POST /v1/friends/challenge/decline") == {"code": "ABC234"} and shell.friends.challenges.incoming.is_empty() and shell._menu_buttons.friends.text == "Friends", "declining a challenge sends its code and clears it")
	# Accepting a challenge is the ordinary private join; an expired one starts nothing and shows the service's message.
	friends_api.routes["GET /v1/friends"] = {"ok": true, "data": full}
	await FriendsPage.refresh(shell)
	friends_api.routes["POST /v1/private/join"] = {"ok": true, "data": {"status": {"queue": null, "allocation": null, "invite": null}}}
	friends_buttons("AcceptChallenge")[0].pressed.emit()
	await process_frame
	expect(friends_api.last_body("POST /v1/private/join") == {"code": "ABC234"}, "accepting a challenge uses the ordinary private-match join")
	friends_api.routes["POST /v1/private/join"] = {"ok": false, "message": "That invite is unavailable."}
	friends_buttons("AcceptChallenge")[0].pressed.emit()
	await process_frame
	expect(shell.notice.text == "That invite is unavailable." and shell.status.allocation == null, "an expired challenge shows the service's message and starts nothing")
	# Challenging a friend: the sheet sends mode, an untimed Battle clock and the chosen colour; the sender's invite starts status polling.
	var waiting = {"code": "XYZ789", "player": {"playerId": "f-1", "username": "ada", "displayName": "Ada"}, "mode": "battle", "initialMs": 0, "incrementMs": 0, "side": "black", "expiresAt": now_ms + 600000}
	var sent_snapshot = {"friends": [ada], "incoming": [], "outgoing": [], "challenges": {"incoming": [], "outgoing": waiting}, "status": {"queue": null, "allocation": null, "invite": {"code": "XYZ789", "expiresAt": now_ms + 600000}}}
	friends_api.routes["POST /v1/friends/challenge"] = {"ok": true, "data": sent_snapshot}
	shell.selected_mode = "battle"
	FriendsPage.open_challenge_sheet(shell, ada)
	await process_frame
	var sheet = shell.find_child("ChallengeSheet", true, false)
	expect(sheet != null and sheet.find_child("ChallengeTime", true, false).visible == false, "the challenge sheet opens, with no time choice for untimed Battle")
	sheet.find_child("ChallengeSide", true, false).get_child(2).button_pressed = true  # Black
	sheet.get_parent().get_ok_button().pressed.emit()
	await process_frame
	expect(friends_api.last_body("POST /v1/friends/challenge") == {"playerId": "f-1", "mode": "battle", "initialMs": 0, "incrementMs": 0, "side": "black"}, "the sheet sends the chosen mode, clock and colour")
	expect(shell.status.invite != null and shell.status.invite.code == "XYZ789" and shell.friends.challenges.outgoing != null, "a sent challenge keeps status polling alive through the sender's invite")
	shell.navigate("play")
	expect(shell.queue_label != null and shell.queue_label.text.contains("Ada") and shell.queue_label.text.contains("accept"), "the Play page says who the challenge is waiting for")
	friends_api.routes["GET /v1/friends"] = {"ok": true, "data": sent_snapshot}
	shell.navigate("friends")
	await process_frame
	expect(friends_buttons("CancelChallenge").size() == 1, "a waiting challenge can be cancelled")
	friends_api.routes["DELETE /v1/queue"] = {"ok": true, "data": {"status": {"queue": null, "allocation": null, "invite": null}}}
	friends_api.routes["GET /v1/friends"] = {"ok": true, "data": {"friends": [ada], "incoming": [], "outgoing": [], "challenges": no_challenges}}
	friends_buttons("CancelChallenge")[0].pressed.emit()
	await process_frame
	await process_frame
	expect(friends_api.count("DELETE /v1/queue") == 1 and shell.status.invite == null and shell.friends.challenges.outgoing == null, "cancelling withdraws the invite and refreshes the page")
	# No challenges while a match is allocated; removing a friend asks first.
	shell.status = {"queue": null, "allocation": {"matchId": "m-1"}, "invite": null}
	FriendsPage.draw_lists(shell)
	expect(friends_buttons("ChallengeFriend").all(func(b): return b.disabled), "challenges wait until the current match is finished")
	shell.status = {"queue": null, "allocation": null, "invite": null}
	FriendsPage.draw_lists(shell)
	friends_api.routes["POST /v1/friends/remove"] = {"ok": true, "data": {"friends": [], "incoming": [], "outgoing": [], "challenges": no_challenges}}
	friends_buttons("RemoveFriend")[0].pressed.emit()
	await process_frame
	var confirmations = shell.find_children("*", "ConfirmationDialog", true, false)
	expect(not confirmations.is_empty() and friends_api.count("POST /v1/friends/remove") == 0, "removing a friend asks for confirmation first")
	confirmations[confirmations.size() - 1].get_ok_button().pressed.emit()
	await process_frame
	expect(friends_api.last_body("POST /v1/friends/remove") == {"playerId": "f-1"} and shell.friends.friends.is_empty(), "confirming removes the friend")
	# Announcements happen once per request or challenge, and only away from the Friends page.
	shell._friend_alerts.clear()
	shell.page = "play"
	FriendsPage._apply(shell, full, true)
	FriendsPage._apply(shell, full, true)
	expect(shell._friend_alerts.size() == 2, "a new request and a new challenge are each announced exactly once")
	# A failed refresh explains itself and can be retried; a different account never inherits the list.
	friends_api.routes["GET /v1/friends"] = {"ok": false, "message": "The account service is unavailable."}
	shell.navigate("friends")
	await process_frame
	expect(shell.notice.text == "The account service is unavailable." and not shell._friends_loading, "a failed refresh shows the service's message and can be retried")
	shell._reset_friends()
	expect(shell.friends.friends.is_empty() and not shell.friends_loaded and shell._menu_buttons.friends.text == "Friends", "signing out or switching account clears the friends list")
	Settings.sign_out()
	var requests_before = friends_api.requests.size()
	await FriendsPage.refresh(shell)
	expect(friends_api.requests.size() == requests_before, "a signed-out client never polls for friends")
	shell.navigate("settings")
	await screenshot("application-settings")
	expect(Api.permitted_url("https://accounts.example.org"), "HTTPS account service accepted")
	for bad in ["http://accounts.example.org", "http://localhost.evil.test", "http://127.0.0.1.evil.test", "https://user:password@evil.test", "file:///tmp/service", "http://192.168.0.1:3100"]:
		expect(not Api.permitted_url(bad), "unsafe account service rejected: " + bad)
	for good in ["http://127.0.0.1:3100", "http://localhost:3100", "http://[::1]:3100"]:
		expect(Api.permitted_url(good), "explicit loopback development accepted")
	expect(Results.title("1-0") == "White wins", "local result identifies winner")
	expect(Results.title("1/2-1/2") == "A well-fought draw", "draw result displayed")
	expect(Results.title("0-1", "black-account", {"w": "white-account", "b": "black-account"}) == "Victory", "online result uses authoritative player IDs")
	expect(Results.title("1-0", "black-account", {"w": "white-account", "b": "black-account"}) == "Defeat", "opponent win maps to defeat")
	Settings.preferred_3d = true
	Settings.animations = false
	Settings.quality = "low"
	expect(Settings.save_preferences() == OK, "presentation preferences saved")
	expect(Engine.max_fps == 30, "low graphics preference only limits presentation frame rate")
	Settings.set_combat_input(true)
	expect(not root.get_node("PlatformInput").cursor_enabled, "gamepad pointer yields to combat")
	Settings.set_combat_input(false)
	expect(root.get_node("PlatformInput").cursor_enabled, "gamepad pointer resumes on board")
	var config = ConfigFile.new()
	expect(config.load("user://preferences.cfg") == OK and config.get_value("presentation", "view3d") == true, "presentation preference persists")
	expect(not config.has_section_key("network", "token") and not config.has_section("account"), "account credentials never saved in preferences")
	Settings.launch = {"mode": "battle", "initialMs": 0, "incrementMs": 0, "view3d": true}
	var local = Local.instantiate()
	root.add_child(local)
	await process_frame
	expect(local.game is BattleChessMatch and not local.game.timed, "menu launch initializes existing Battle C0 authority")
	expect(local._view_3d and not local.board_2d.visible and local.board_3d.visible, "menu launch preserves selected 3D perspective")
	expect(Settings.launch.is_empty(), "launch intent consumed exactly once")
	expect(not local.board_2d.animation_enabled and not local.board_3d.animation_enabled, "both local views honor animation preference")
	local.game.new_game(0)
	var state = local.game.match_state()
	local.set_view(false)
	expect(local.game.match_state() == state and not Settings.preferred_3d, "view switch preserves state and updates only local preference")
	local.queue_free()
	await process_frame
	Settings.launch = {"mode": "classic", "initialMs": 180000, "incrementMs": 2000, "view3d": false}
	local = Local.instantiate()
	root.add_child(local)
	await process_frame
	expect(not local.game is BattleChessMatch and local.game.initial_ms == 180000 and local.game.increment_ms == 2000, "menu launch initializes existing Classic clocks")
	local.queue_free()
	shell.queue_free()
	await process_frame
	Settings.sign_out()
	Settings.quality = "balanced"
	Settings.animations = true
	Settings.save_preferences()
	print("Application UI: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
