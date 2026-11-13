extends RefCounted
## Friends page: add friends by username, answer friend requests and challenges, and challenge a friend to a private
## online game. The account service owns every fact shown here (friendships, challenges, who is online); this file draws
## the last snapshot it received and sends intents. Accepting a challenge is the ordinary private-match join, so
## everything after it (seat ticket, ENet lobby, ready check, authoritative match) is the existing online path.
## Built into app.content by FriendsPage.build(app); the app polls refresh() (application.gd _process).
const Settings = preload("res://ui/application_settings.gd")
const Kit = preload("res://ui/theme/ui_kit.gd")
const T = preload("res://ui/theme/ui_tokens.gd")

# ---------------------------------------------------------------- pure helpers (unit-tested, no scene needed)

## Normalises a server response into the snapshot shape. Missing or mistyped parts become empty; nothing here can crash.
static func snapshot_from(data: Dictionary) -> Dictionary:
	var challenges = data.get("challenges", {})
	if not challenges is Dictionary:
		challenges = {}
	var outgoing = challenges.get("outgoing", null)
	return {
		"friends": _dictionaries(data.get("friends", [])),
		"incoming": _dictionaries(data.get("incoming", [])),
		"outgoing": _dictionaries(data.get("outgoing", [])),
		"challenges": {"incoming": _dictionaries(challenges.get("incoming", [])), "outgoing": outgoing if outgoing is Dictionary else null},
	}

static func _dictionaries(value) -> Array:
	var result: Array = []
	if value is Array:
		for item in value:
			if item is Dictionary:
				result.append(item)
	return result

## What needs the player's attention: unanswered friend requests plus challenges waiting for them.
static func badge_count(snapshot: Dictionary) -> int:
	return snapshot.get("incoming", []).size() + snapshot.get("challenges", {}).get("incoming", []).size()

static func control_text(challenge: Dictionary) -> String:
	if str(challenge.get("mode", "classic")) == "battle":
		return "Battle · untimed"
	return "Classic · %d + %d" % [int(int(challenge.get("initialMs", 0)) / 60000.0), int(int(challenge.get("incrementMs", 0)) / 1000.0)]

## `side` is the viewer's own colour in the challenged game.
static func side_text(side: String) -> String:
	return {"white": "you play White", "black": "you play Black"}.get(side, "colours drawn at random")

## [label, colour] for a friend's presence chip.
static func presence(friend: Dictionary) -> Array:
	if friend.get("inMatch", false):
		return ["In a match", T.WARNING]
	if friend.get("online", false):
		return ["Online", T.SUCCESS]
	return ["Offline", T.TEXT_MUTED]

## Friends who are around come first, then everyone alphabetically.
static func sorted_friends(friends: Array) -> Array:
	var copy := friends.duplicate()
	copy.sort_custom(func(a, b):
		var around_a: bool = a.get("online", false) or a.get("inMatch", false)
		var around_b: bool = b.get("online", false) or b.get("inMatch", false)
		if around_a != around_b:
			return around_a
		return str(a.get("displayName", "")).naturalnocasecmp_to(str(b.get("displayName", ""))) < 0)
	return copy

## Minutes until a challenge expires (clamped to the 10 minute invite lifetime so a skewed device clock cannot show nonsense).
static func minutes_left(challenge: Dictionary, now_ms: int) -> int:
	return clampi(int(ceil((int(challenge.get("expiresAt", 0)) - now_ms) / 60000.0)), 0, 10)

# ---------------------------------------------------------------- page

static func build(app: Control) -> void:
	var content: VBoxContainer = app.content
	var heading := Kit.heading(content, "Play the people you know.", "Add friends by username, then challenge them to a private online game. Friend games are always unranked.")
	app.title_label = heading[0]
	app.subtitle_label = heading[1]
	if not app._signed_in_or_prompt():
		return
	_add_card(app, content)
	var lists := VBoxContainer.new()
	lists.name = "FriendLists"
	lists.add_theme_constant_override("separation", 18)
	lists.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(lists)
	app.friend_lists = lists
	if app.friends_loaded:
		draw_lists(app)
	else:
		Kit.loading_state(lists, "Loading your friends…")
	refresh(app)

static func _add_card(app: Control, content: VBoxContainer) -> void:
	var card := Kit.card(content)
	card.name = "AddFriendCard"
	Kit.section_header(card, "Add a friend", "user")
	var row := Kit.flow(card)
	var field := LineEdit.new()
	field.name = "FriendUsername"
	field.placeholder_text = "Their username"
	field.max_length = 24
	field.custom_minimum_size = Vector2(240, Kit.target_height())
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(field)
	var submit := func():
		var username := field.text.strip_edges()
		field.text = ""
		request(app, username)
	field.text_submitted.connect(func(_text): submit.call())
	var send := Kit.button(row, "Send request", func(): submit.call(), "PrimaryButton", "check")
	send.name = "SendRequest"
	Kit.muted(card, "Your username is @" + str(Settings.account.get("username", "")) + ". Share it so friends can find you.")

## Rebuilds only the lists (never the add-friend field), so polling cannot wipe what the player is typing.
static func draw_lists(app: Control) -> void:
	var lists = app.friend_lists
	if not is_instance_valid(lists):
		return
	for child in lists.get_children():
		lists.remove_child(child)
		child.queue_free()
	var snapshot: Dictionary = app.friends
	var challenges: Dictionary = snapshot.challenges
	var now_ms := int(Time.get_unix_time_from_system() * 1000.0)
	# Challenges for you come first: they expire.
	if not challenges.incoming.is_empty():
		var card := Kit.card(lists, "SelectedPanel", 12)
		card.get_parent().name = "IncomingChallenges"
		Kit.section_header(card, "Challenges for you", "sword")
		for challenge in challenges.incoming:
			var code: String = str(challenge.get("code", ""))
			var row := _person_row(card, challenge.get("player", {}), "%s · %s · about %d min left" % [control_text(challenge), side_text(str(challenge.get("side", ""))), minutes_left(challenge, now_ms)])
			Kit.button(row, "Accept", func(): join_challenge(app, code), "PrimaryButton", "check").name = "AcceptChallenge"
			Kit.button(row, "Decline", func(): decline_challenge(app, code), "GhostButton", "close").name = "DeclineChallenge"
	var sent = challenges.outgoing
	if sent != null:
		var card := Kit.card(lists, "CardPanel", 12)
		card.get_parent().name = "OutgoingChallenge"
		Kit.section_header(card, "Challenge sent", "clock")
		var row := _person_row(card, sent.get("player", {}), "%s · %s · waiting for them to accept" % [control_text(sent), side_text(str(sent.get("side", "")))])
		Kit.button(row, "Cancel challenge", func(): cancel_challenge(app), "GhostButton", "close").name = "CancelChallenge"
	if not snapshot.incoming.is_empty():
		var card := Kit.card(lists, "CardPanel", 12)
		card.get_parent().name = "FriendRequests"
		Kit.section_header(card, "Friend requests", "user")
		for person in snapshot.incoming:
			var id: String = str(person.get("playerId", ""))
			var row := _person_row(card, person, "wants to be your friend")
			Kit.button(row, "Accept", func(): accept(app, id), "PrimaryButton", "check").name = "AcceptRequest"
			Kit.button(row, "Decline", func(): remove(app, id, ""), "GhostButton", "close").name = "DeclineRequest"
	var friends_card := Kit.card(lists, "CardPanel", 12)
	friends_card.get_parent().name = "FriendsCard"
	Kit.section_header(friends_card, "Friends (%d)" % snapshot.friends.size(), "pawn")
	if snapshot.friends.is_empty():
		Kit.muted(friends_card, "No friends yet. Send a request by username above. Once they accept, you can challenge them here.")
	for friend in sorted_friends(snapshot.friends):
		var state := presence(friend)
		var row := _person_row(friends_card, friend, "Classic %d · Battle %d" % [int(friend.get("classicRating", 0)), int(friend.get("battleRating", 0))])
		Kit.chip(row, state[0], state[1])
		var challenge_button := Kit.button(row, "Challenge", func(): open_challenge_sheet(app, friend), "PrimaryButton", "sword")
		challenge_button.name = "ChallengeFriend"
		if friend.get("inMatch", false):
			Kit.disable_with_reason(challenge_button, "They are in a match right now.")
		elif app.status.get("allocation") != null:
			Kit.disable_with_reason(challenge_button, "Finish your current match first.")
		var friend_id: String = str(friend.get("playerId", ""))
		var friend_name: String = str(friend.get("displayName", "this player"))
		Kit.button(row, "Remove", func(): Kit.confirm(app, "Remove friend?", "Remove " + friend_name + " from your friends? You can add them again later.", "Remove", func(): remove(app, friend_id, friend_name + " removed."), true), "GhostButton", "close").name = "RemoveFriend"
	if not snapshot.outgoing.is_empty():
		var card := Kit.card(lists, "CardPanel", 12)
		card.get_parent().name = "SentRequests"
		Kit.section_header(card, "Requests you sent", "clock")
		for person in snapshot.outgoing:
			var id: String = str(person.get("playerId", ""))
			var row := _person_row(card, person, "waiting for an answer")
			Kit.button(row, "Cancel", func(): remove(app, id, "Request cancelled."), "GhostButton", "close").name = "CancelRequest"

## Name and @username on the left; the caller appends chips and buttons to the returned flow (they wrap on narrow screens).
static func _person_row(parent: Control, who: Dictionary, detail: String) -> HFlowContainer:
	var row := Kit.flow(parent)
	var names := VBoxContainer.new()
	names.custom_minimum_size.x = 220
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(names)
	var name_label := Kit.label(names, str(who.get("displayName", "Player")), "H3", false)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	Kit.label(names, "@" + str(who.get("username", "")) + ("  ·  " + detail if detail != "" else ""), "Muted")
	return row

## Mode, time control and colour for a challenge to `friend`; sends it when confirmed.
static func open_challenge_sheet(app: Control, friend: Dictionary) -> void:
	var choice := {"mode": app.selected_mode, "time": app.selected_time, "side": "random"}
	var dialog := ConfirmationDialog.new()
	dialog.title = "Challenge " + str(friend.get("displayName", "your friend"))
	dialog.ok_button_text = "Send challenge"
	dialog.cancel_button_text = "Cancel"
	dialog.get_ok_button().theme_type_variation = "PrimaryButton"
	dialog.get_ok_button().custom_minimum_size.y = Kit.target_height()
	dialog.get_cancel_button().custom_minimum_size.y = Kit.target_height()
	var body := VBoxContainer.new()
	body.name = "ChallengeSheet"
	body.add_theme_constant_override("separation", T.S3)
	body.custom_minimum_size.x = 380
	dialog.add_child(body)
	Kit.label(body, "GAME", "Caption")
	var times := OptionButton.new()
	times.name = "ChallengeTime"
	times.custom_minimum_size.y = Kit.target_height()
	for control in app.TIMES:
		times.add_item(control[0])
	times.select(clampi(int(choice.time), 0, app.TIMES.size() - 1))
	times.item_selected.connect(func(index): choice.time = index)
	var mode_picker := Kit.segmented(body, [["classic", "Classic"], ["battle", "Battle"]], choice.mode, func(value):
		choice.mode = value
		times.visible = value == "classic")
	mode_picker.name = "ChallengeMode"
	body.add_child(times)
	times.visible = choice.mode == "classic"
	Kit.label(body, "YOUR COLOUR", "Caption")
	Kit.segmented(body, [["white", "White"], ["random", "Random"], ["black", "Black"]], "random", func(value): choice.side = value).name = "ChallengeSide"
	Kit.muted(body, "Friend games are always unranked. Your friend has ten minutes to accept.")
	dialog.confirmed.connect(func():
		challenge(app, str(friend.get("playerId", "")), choice)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	app.add_child(dialog)
	dialog.theme = null  # inherit the host's theme
	Kit.popup_in(app, dialog, 440, 400)
	Kit.refit(dialog)

# ---------------------------------------------------------------- network (intents only; the service decides)

## Polled by the app: every few seconds on this page, less often elsewhere (the badge and the "online" dot depend on it).
static func refresh(app: Control) -> void:
	if app._friends_loading or Settings.token.is_empty():
		return
	app._friends_loading = true
	var response = await app.api.call_api(HTTPClient.METHOD_GET, "/v1/friends")
	if not is_instance_valid(app):
		return
	app._friends_loading = false
	if Settings.token.is_empty():
		return  # signed out while the request was in flight
	if not response is Dictionary or not response.get("ok", false):
		if app.page == "friends":
			app._message(str(response.get("message", "Friends could not be loaded.")) if response is Dictionary else "Friends could not be loaded.", true)
		return
	_apply(app, response.data, true)

static func _apply(app: Control, data: Dictionary, announce: bool) -> void:
	app.friends = snapshot_from(data)
	app.friends_loaded = true
	if announce:
		_announce_new(app)
	app._update_friends_badge()
	if app.page == "friends":
		draw_lists(app)
	# After an app restart our own challenge can already be waiting: pick up its invite so status polling resumes.
	if app.friends.challenges.outgoing != null and app.status.get("invite") == null:
		app._poll_status()

## A toast the first time a request or challenge for you appears while you are on another page.
static func _announce_new(app: Control) -> void:
	if app.page == "friends":
		for person in app.friends.incoming:
			app._friend_alerts["request:" + str(person.get("playerId", ""))] = true
		for challenge in app.friends.challenges.incoming:
			app._friend_alerts["challenge:" + str(challenge.get("code", ""))] = true
		return
	for person in app.friends.incoming:
		var key := "request:" + str(person.get("playerId", ""))
		if not app._friend_alerts.has(key):
			app._friend_alerts[key] = true
			Kit.toast(app, str(person.get("displayName", "Someone")) + " sent you a friend request. Open Friends to answer.", "info")
	for challenge in app.friends.challenges.incoming:
		var key := "challenge:" + str(challenge.get("code", ""))
		if not app._friend_alerts.has(key):
			app._friend_alerts[key] = true
			Kit.toast(app, str(challenge.get("player", {}).get("displayName", "A friend")) + " challenges you to " + control_text(challenge) + ". Open Friends to answer.", "info")

## One mutation: guards against double taps, shows the service's own error text, redraws from the returned snapshot.
static func _send(app: Control, path: String, body: Dictionary) -> Dictionary:
	if app._busy:
		return {"ok": false}
	app._busy = true
	var response: Dictionary = await app.api.call_api(HTTPClient.METHOD_POST, path, body)
	if not is_instance_valid(app):
		return {"ok": false}
	app._busy = false
	if not response.get("ok", false):
		app._message(str(response.get("message", "That could not be completed.")), true)
		refresh(app)  # the world may have moved on: an expired challenge, a removed friend
		return response
	_apply(app, response.data, false)
	return response

static func request(app: Control, username: String) -> void:
	if username.length() < 3:
		app._message("Enter your friend's username.", true)
		return
	var response := await _send(app, "/v1/friends/request", {"username": username})
	if response.get("ok", false):
		app._message("You are now friends with @" + username.to_lower() + "." if response.data.get("result", "") == "accepted" else "Friend request sent to @" + username.to_lower() + ".")

static func accept(app: Control, player_id: String) -> void:
	var response := await _send(app, "/v1/friends/accept", {"playerId": player_id})
	if response.get("ok", false):
		app._message("Friend added.")

## Unfriend, decline an incoming request or cancel an outgoing one: the service treats them alike.
static func remove(app: Control, player_id: String, message: String) -> void:
	var response := await _send(app, "/v1/friends/remove", {"playerId": player_id})
	if response.get("ok", false) and message != "":
		app._message(message)

static func challenge(app: Control, player_id: String, choice: Dictionary) -> void:
	var classic: bool = choice.mode == "classic"
	var control: Array = app.TIMES[clampi(int(choice.time), 0, app.TIMES.size() - 1)]
	var response := await _send(app, "/v1/friends/challenge", {"playerId": player_id, "mode": choice.mode, "initialMs": control[1] if classic else 0, "incrementMs": control[2] if classic else 0, "side": choice.side})
	if response.get("ok", false):
		# The sender's invite is now in their status, so the app's status polling resumes and notices the allocation.
		app._accept_status({"ok": true, "data": {"status": response.data.get("status", {"queue": null, "allocation": null, "invite": null})}}, false)
		app._message("Challenge sent. Waiting for your friend…")

static func decline_challenge(app: Control, code: String) -> void:
	var response := await _send(app, "/v1/friends/challenge/decline", {"code": code})
	if response.get("ok", false):
		app._message("Challenge declined.")

## Accepting a challenge is the ordinary private join; the app then opens the seat ticket and the online lobby.
static func join_challenge(app: Control, code: String) -> void:
	if app._busy:
		return
	app._busy = true
	var response: Dictionary = await app.api.call_api(HTTPClient.METHOD_POST, "/v1/private/join", {"code": code})
	if not is_instance_valid(app):
		return
	app._busy = false
	if not response.get("ok", false):
		app._message(str(response.get("message", "That challenge is no longer available.")), true)
		refresh(app)
		return
	app._accept_status(response)

static func cancel_challenge(app: Control) -> void:
	var response: Dictionary = await app.api.call_api(HTTPClient.METHOD_DELETE, "/v1/queue")
	if not is_instance_valid(app):
		return
	app._accept_status(response, false)
	refresh(app)
