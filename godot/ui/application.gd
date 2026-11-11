extends Control
## Application navigation is independent from chess/combat authority.
const Settings = preload("res://ui/application_settings.gd")
const Api = preload("res://ui/account_api.gd")
const Results = preload("res://ui/results.gd")
const INK = Color("142924")
const PAPER = Color("f4eddc")
const MUTED = Color("b6c4b5")
const GOLD = Color("e5c586")
const TIMES = [["3 + 2 · Blitz", 180000, 2000], ["5 + 0 · Blitz", 300000, 0], ["10 + 0 · Rapid", 600000, 0], ["15 + 10 · Rapid", 900000, 10000], ["30 + 0 · Classical", 1800000, 0]]
var api: Node
var page = "play"
var selected_mode = "classic"
var online = false
var ranked = false
var selected_time = 2
var status: Dictionary = {"queue": null, "allocation": null, "invite": null}
var content: VBoxContainer
var page_scroll: ScrollContainer
var title_label: Label
var subtitle_label: Label
var account_badge: Button
var notice: Label
var queue_label: Label
var invite_edit: LineEdit
var username_edit: LineEdit
var password_edit: LineEdit
var display_name_edit: LineEdit
var api_edit: LineEdit
var _poll_timer = 0.0
var _polling = false
var _busy = false
var _opening = false
var _refresh_generation = 0
var _menu_buttons: Dictionary = {}

func _ready() -> void:
	Settings.load_preferences()
	api = Api.new()
	add_child(api)
	_build_theme()
	_build_frame()
	navigate("play")
	PadUi.install(self, {"prefer": "content", "back": Callable(self, "_pad_back")})  # controller / keyboard focus (claude/pads-input)
	if not Settings.token.is_empty():
		_refresh_account()
	if not Settings.result.is_empty():
		var recent = Settings.result.duplicate(true)
		Settings.result.clear()
		Results.show_dialog(self, recent, func(): pass, func(): navigate("history"))

func _box(color: Color, radius: int = 16, padding: int = 20) -> StyleBoxFlat:
	var box = StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.set_border_width_all(1)
	box.border_color = Color("3f5647")
	box.content_margin_left = padding
	box.content_margin_right = padding
	box.content_margin_top = padding
	box.content_margin_bottom = padding
	return box

func _build_theme() -> void:
	theme = Theme.new()
	theme.default_font_size = 17
	for type_name in ["Label", "Button", "OptionButton", "CheckButton", "LineEdit"]:
		theme.set_color("font_color", type_name, PAPER)
		theme.set_color("font_hover_color", type_name, GOLD)
		theme.set_color("font_disabled_color", type_name, Color("748679"))
	for type_name in ["Button", "OptionButton"]:
		theme.set_stylebox("normal", type_name, _box(Color("233e32"), 10, 12))
		theme.set_stylebox("hover", type_name, _box(Color("345440"), 10, 12))
		theme.set_stylebox("pressed", type_name, _box(Color("456246"), 10, 12))
		theme.set_stylebox("disabled", type_name, _box(Color("1d3027"), 10, 12))
		var focus = _box(Color.TRANSPARENT, 10, 12)
		focus.border_color = GOLD
		focus.set_border_width_all(3)
		theme.set_stylebox("focus", type_name, focus)
	theme.set_stylebox("normal", "LineEdit", _box(Color("10271f"), 8, 12))
	theme.set_stylebox("panel", "PopupMenu", _box(Color("233e32")))
	theme.set_stylebox("panel", "AcceptDialog", _box(Color("233e32")))
	theme.set_color("font_placeholder_color", "LineEdit", Color("99ab9d"))

func _label(parent: Node, text: String, size_px: int = 17, color: Color = PAPER) -> Label:
	var label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, action: Callable, primary: bool = false) -> Button:
	var button = Button.new()
	button.text = text
	button.custom_minimum_size.y = 48
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(action)
	if primary:
		button.add_theme_stylebox_override("normal", _box(GOLD, 10, 12))
		button.add_theme_stylebox_override("hover", _box(Color("f5d9a2"), 10, 12))
		button.add_theme_color_override("font_color", INK)
		button.add_theme_color_override("font_hover_color", INK)
	parent.add_child(button)
	return button

func _field(parent: Node, placeholder: String, secret: bool = false) -> LineEdit:
	var field = LineEdit.new()
	field.placeholder_text = placeholder
	field.secret = secret
	field.custom_minimum_size.y = 48
	field.max_length = 128 if secret else 64
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(field)
	return field

func _card(parent: Node) -> VBoxContainer:
	var panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(Color("1d372c")))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)
	return column

func _flow(parent: Node) -> HFlowContainer:
	var flow = HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	parent.add_child(flow)
	return flow

func _build_frame() -> void:
	var background = ColorRect.new()
	background.color = INK
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 24)
	add_child(margin)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)
	var brand_row = HBoxContainer.new()
	brand_row.add_theme_constant_override("separation", 16)
	column.add_child(brand_row)
	var brand = _label(brand_row, "♜  PEEPEECHESS", 28, GOLD)
	brand.autowrap_mode = TextServer.AUTOWRAP_OFF
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	account_badge = _button(brand_row, "Sign in", func(): navigate("account"))
	var nav = _flow(column)
	for item in [["play", "Play"], ["profile", "Profile"], ["history", "Match history"], ["leaderboard", "Leaderboard"], ["settings", "Settings"]]:
		var target: String = item[0]
		_menu_buttons[target] = _button(nav, item[1], func(): navigate(target))
	page_scroll = ScrollContainer.new()
	page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(page_scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 18)
	page_scroll.add_child(content)
	notice = _label(column, "Your board. Your perspective. One shared game.", 14, MUTED)
	_update_badge()

## Circle on a controller: leave a sub-page for Play (PadUi calls this only when no dialog is open).
func _pad_back() -> void:
	if page != "play":
		navigate("play")

func navigate(target: String) -> void:
	page = target if target in ["play", "profile", "history", "leaderboard", "settings", "account"] else "play"
	_refresh_generation += 1
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	for key in _menu_buttons:
		_menu_buttons[key].disabled = key == page
	page_scroll.scroll_vertical = 0
	queue_label = null
	match page:
		"play": _play_page()
		"account": _account_page()
		"settings": _settings_page()
		"profile": _profile_page()
		"history": _history_page()
		"leaderboard": _leaderboard_page()
	_update_badge()

func _heading(title: String, detail: String) -> void:
	title_label = _label(content, title, 36)
	subtitle_label = _label(content, detail, 17, MUTED)

func _update_badge() -> void:
	if account_badge != null:
		account_badge.text = str(Settings.account.get("displayName", "Account")) if not Settings.token.is_empty() else "Sign in"

func _message(text: String, error: bool = false) -> void:
	notice.text = text
	notice.add_theme_color_override("font_color", Color("f1b7a0") if error else MUTED)

func _play_page() -> void:
	_heading("Make your next move.", "Classic precision or a capture worth fighting for. Choose your game, then make it yours.")
	var modes = _flow(content)
	for data in [["classic", "♜", "Classic Chess", "The complete game. Checkmate, clocks and every special move."], ["battle", "⚔", "Battle Chess", "Legal captures open a duel. The winner decides who stays."]]:
		var selected: String = data[0]
		var card = _card(modes)
		card.get_parent().custom_minimum_size.x = 300
		_label(card, data[1] + "  " + data[2], 25, GOLD if selected_mode == selected else PAPER)
		_label(card, data[3], 15, MUTED).custom_minimum_size = Vector2(260, 48)
		_button(card, "Selected" if selected_mode == selected else "Choose " + data[2], func(): selected_mode = selected; navigate("play"), selected_mode == selected)
	var setup = _card(content)
	_label(setup, "YOUR MATCH", 13, GOLD)
	var row = _flow(setup)
	_button(row, "Local · two players" + (" ✓" if not online else ""), func(): online = false; navigate("play"), not online)
	_button(row, "Online crossplay" + (" ✓" if online else ""), func(): online = true; navigate("play"), online)
	_button(row, "2D board" + (" ✓" if not Settings.preferred_3d else ""), func(): _choose_view(false), not Settings.preferred_3d)
	_button(row, "3D board" + (" ✓" if Settings.preferred_3d else ""), func(): _choose_view(true), Settings.preferred_3d)
	_label(setup, "Your opponent can choose a different board. Switch 2D / 3D at any time during play.", 14, MUTED)
	if selected_mode == "classic":
		var times = OptionButton.new()
		times.custom_minimum_size.y = 48
		for control in TIMES:
			times.add_item(control[0])
		times.select(selected_time)
		times.item_selected.connect(func(index): selected_time = index)
		setup.add_child(times)
	else:
		_label(setup, "Battle C0 · untimed chess · traditional checkmate · kings stay on the board", 15, MUTED)
	if not online:
		_button(setup, "Start local " + selected_mode.capitalize() + " Chess  →", start_local, true)
		_label(setup, "Pass-and-play chess. Battle duels use two local control schemes; no account required.", 14, MUTED)
		return
	if Settings.token.is_empty():
		_button(setup, "Sign in to play online  →", func(): navigate("account"), true)
		return
	var competition = _flow(setup)
	_button(competition, "Unranked" + (" ✓" if not ranked else ""), func(): ranked = false; navigate("play"), not ranked)
	_button(competition, "Ranked" + (" ✓" if ranked else ""), func(): ranked = true; navigate("play"), ranked)
	_label(setup, "Ranked games update your rating on the server. Private matches are always unranked.", 14, MUTED)
	var actions = _flow(setup)
	_button(actions, "Quick match  →", _queue, true)
	_button(actions, "Create private match", _create_private)
	invite_edit = _field(setup, "Invite code · six characters")
	invite_edit.max_length = 6
	_button(setup, "Join private match", _join_private)
	queue_label = _label(setup, _status_text(), 17, GOLD)
	var queue_actions = _flow(setup)
	_button(queue_actions, "Cancel search / invite", _cancel_queue)
	_button(queue_actions, "Reconnect to allocated match", _poll_status)
	if status.invite != null:
		_button(queue_actions, "Copy invite " + str(status.invite.code), func(): DisplayServer.clipboard_set(str(status.invite.code)); _message("Invite code copied."))

func _choose_view(use_3d: bool) -> void:
	Settings.preferred_3d = use_3d
	Settings.save_preferences()
	navigate("play")

func match_options() -> Dictionary:
	return {"mode": selected_mode, "ranked": ranked, "initialMs": TIMES[selected_time][1] if selected_mode == "classic" else 0, "incrementMs": TIMES[selected_time][2] if selected_mode == "classic" else 0}

func start_local() -> void:
	var options = match_options()
	Settings.launch = {"mode": options.mode, "initialMs": options.initialMs, "incrementMs": options.incrementMs, "view3d": Settings.preferred_3d}
	get_tree().change_scene_to_file("res://app/main.tscn")

func _account_page() -> void:
	_heading("One account. Every board.", "Use the same sign-in on Windows and Android. Your online profile, match history and ratings stay together.")
	var card = _card(content)
	if not Settings.token.is_empty():
		_label(card, "Signed in as " + str(Settings.account.get("displayName", "Player")), 24, GOLD)
		_label(card, "Sessions stay in memory for this run. Your password and account token are never saved in preferences.", 15, MUTED)
		_button(card, "View profile", func(): navigate("profile"), true)
		_button(card, "Sign out", _sign_out)
		return
	username_edit = _field(card, "Username · 3–24 letters, numbers or underscore")
	username_edit.max_length = 24
	display_name_edit = _field(card, "Display name · for a new account")
	display_name_edit.max_length = 32
	password_edit = _field(card, "Password · at least 10 characters", true)
	var actions = _flow(card)
	_button(actions, "Sign in", func(): _authenticate(false), true)
	_button(actions, "Create account", func(): _authenticate(true))
	_label(card, "Account service: " + Settings.api_url + "\nChange it in Settings to connect to your hosted service.", 14, MUTED)

func _authenticate(register: bool) -> void:
	if _busy:
		return
	var username = username_edit.text.strip_edges()
	var password = password_edit.text
	var display_name = display_name_edit.text.strip_edges()
	if username.length() < 3 or password.length() < 10 or (register and display_name.is_empty()):
		_message("Enter a username, a password of at least 10 characters, and a display name for a new account.", true)
		return
	_busy = true
	_message("Creating your account…" if register else "Signing in…")
	password_edit.text = ""
	var response = await api.authenticate(username, password, display_name, register)
	_busy = false
	if not response.ok:
		_message(response.message, true)
		return
	_message("Welcome, " + str(Settings.account.get("displayName", "Player")) + ".")
	navigate("play")

func _sign_out() -> void:
	await api.call_api(HTTPClient.METHOD_POST, "/v1/auth/logout", {})
	Settings.sign_out()
	status = {"queue": null, "allocation": null, "invite": null}
	_message("Signed out on this device.")
	navigate("account")

func _settings_page() -> void:
	_heading("Make yourself at home.", "Presentation settings belong to this device. They never change the match rules or your opponent's camera.")
	var card = _card(content)
	var row = _flow(card)
	_button(row, "Default board: " + ("3D" if Settings.preferred_3d else "2D"), func(): Settings.preferred_3d = not Settings.preferred_3d; Settings.save_preferences(); navigate("settings"))
	var animate = CheckButton.new()
	animate.text = "Piece animations"
	animate.custom_minimum_size.y = 48
	animate.button_pressed = Settings.animations
	animate.toggled.connect(func(on): Settings.animations = on; Settings.save_preferences())
	row.add_child(animate)
	var touch = CheckButton.new()
	touch.text = "Touch combat controls"
	touch.custom_minimum_size.y = 48
	touch.button_pressed = Settings.touch_controls
	touch.toggled.connect(func(on): Settings.touch_controls = on; Settings.save_preferences())
	row.add_child(touch)
	_label(card, "Graphics quality", 18, GOLD)
	var quality_row = _flow(card)
	for value in ["low", "balanced", "high"]:
		var quality: String = value
		_button(quality_row, value.capitalize() + (" ✓" if Settings.quality == value else ""), func(): Settings.quality = quality; Settings.save_preferences(); navigate("settings"), Settings.quality == value)
	_label(card, "Low limits presentation to 30 FPS. Balanced and High target 60 FPS. Server simulation remains authoritative at 60 ticks per second.", 14, MUTED)
	_label(card, "Master volume", 18, GOLD)
	var volume = HSlider.new()
	volume.min_value = 0
	volume.max_value = 1
	volume.step = 0.05
	volume.value = Settings.volume
	volume.custom_minimum_size = Vector2(250, 48)
	volume.value_changed.connect(func(value): Settings.volume = value; Settings.save_preferences())
	card.add_child(volume)
	_label(card, "Controls", 18, GOLD)
	_button(card, "Controls & controllers…", func(): ControlsScreen.open(self))  # claude/pads-input: bindings, P1/P2 devices, pad tuning
	_label(card, "Account service URL", 18, GOLD)
	api_edit = _field(card, "https://accounts.example.com")
	api_edit.max_length = 200
	api_edit.text = Settings.api_url
	_button(card, "Save service address", _save_api_url)
	_label(card, "Keyboard / mouse: click or drag a piece. Touch: tap or drag. 3D: orbit with right-drag or swipe; zoom with scroll or pinch. Controller: use the focused controls and board cursor. Esc releases the combat mouse.", 15, MUTED)
	_button(card, "Advanced direct-server lobby", func(): Settings.launch = {}; get_tree().change_scene_to_file("res://network/client/online_lobby.tscn"))

func _save_api_url() -> void:
	var value = api_edit.text.strip_edges().trim_suffix("/")
	if not Api.permitted_url(value):
		_message("Enter an HTTPS service address. Loopback HTTP is allowed for local development only.", true)
		return
	if value != Settings.api_url:
		Settings.sign_out()
		status = {"queue": null, "allocation": null, "invite": null}
	Settings.api_url = value
	Settings.save_preferences()
	_message("Account service saved. Sign in to this service to play online.")
	_update_badge()

func _signed_in_or_prompt() -> bool:
	if not Settings.token.is_empty():
		return true
	var card = _card(content)
	_label(card, "Sign in to see your online profile and records.", 19, MUTED)
	_button(card, "Sign in / create account", func(): navigate("account"), true)
	return false

func _profile_page() -> void:
	_heading("Your place at the board.", "Classic and Battle Chess have separate ratings. Local games never change your online statistics.")
	if not _signed_in_or_prompt():
		return
	_draw_profile(Settings.account)
	_refresh_account()

func _draw_profile(profile: Dictionary) -> void:
	var card = _card(content)
	card.name = "ProfileCard"
	_label(card, str(profile.get("displayName", "Player")), 30, GOLD)
	_label(card, "@" + str(profile.get("username", "")) + "\nPlayer ID · " + str(profile.get("playerId", "")), 14, MUTED)
	var row = _flow(card)
	for mode in ["classic", "battle"]:
		var stats: Dictionary = profile.get(mode, {})
		var column = _card(row)
		column.get_parent().custom_minimum_size.x = 260
		_label(column, mode.capitalize() + " Chess", 20, PAPER)
		_label(column, str(stats.get("rating", 1200)) + "  rating", 32, GOLD)
		_label(column, "%d wins   %d losses   %d draws\n%d games played" % [stats.get("wins", 0), stats.get("losses", 0), stats.get("draws", 0), stats.get("games", 0)], 16, MUTED)
	_button(card, "Match history", func(): navigate("history"))

func _refresh_account() -> void:
	var generation = _refresh_generation
	var response = await api.call_api(HTTPClient.METHOD_GET, "/v1/me")
	if not response.ok:
		_message(response.message, true)
		_update_badge()
		return
	Settings.account = response.data.profile.duplicate(true)
	_update_badge()
	if generation == _refresh_generation and page == "profile":
		for child in content.get_children():
			if child is PanelContainer:
				content.remove_child(child)
				child.queue_free()
		_draw_profile(Settings.account)

func _history_page() -> void:
	_heading("Every match tells a story.", "Completed online games, stored by the authoritative service. New results may take a moment to appear.")
	if not _signed_in_or_prompt():
		return
	_load_history(_refresh_generation)

func _load_history(generation: int) -> void:
	var loading = _label(content, "Loading match history…", 17, MUTED)
	var response = await api.call_api(HTTPClient.METHOD_GET, "/v1/history?limit=30")
	if generation != _refresh_generation:
		return
	loading.queue_free()
	if not response.ok:
		_message(response.message, true)
		return
	var matches: Array = response.data.get("matches", [])
	if matches.is_empty():
		_label(content, "Your first online match is waiting. Find an opponent from Play.", 20, MUTED)
	for record in matches:
		var card = _card(content)
		var is_white = record.whitePlayerId == Settings.account.get("playerId")
		var own_side = "white" if is_white else "black"
		var result = "Draw" if record.result == "draw" else ("Aborted" if record.result == "aborted" else ("Victory" if record.result == own_side else "Defeat"))
		_label(card, result + " · " + str(record.mode).capitalize() + " Chess · " + ("Ranked" if record.ranked else "Unranked"), 21, GOLD)
		var opponent: String = record.blackName if is_white else record.whiteName
		var delta = int(record.ratingChange.white if is_white else record.ratingChange.black)
		_label(card, "vs " + opponent + " · " + str(record.reason).replace("_", " ") + "\n" + str(record.history.size()) + " moves · " + ("+" if delta > 0 else "") + str(delta) + " rating · " + Time.get_datetime_string_from_unix_time(int(record.completedAt / 1000)).replace("T", " ") + " UTC", 15, MUTED)
		_button(card, "Copy final FEN", func(): DisplayServer.clipboard_set(str(record.finalFen)); _message("Final position copied."))

func _leaderboard_page() -> void:
	_heading("Earn your place.", "Separate Classic and Battle Chess ladders. Ratings can only be updated by authoritative match results.")
	if not _signed_in_or_prompt():
		return
	var row = _flow(content)
	_button(row, "Classic", func(): selected_mode = "classic"; navigate("leaderboard"), selected_mode == "classic")
	_button(row, "Battle", func(): selected_mode = "battle"; navigate("leaderboard"), selected_mode == "battle")
	_load_leaderboard(_refresh_generation, selected_mode)

func _load_leaderboard(generation: int, mode: String) -> void:
	var loading = _label(content, "Loading leaderboard…", 17, MUTED)
	var response = await api.call_api(HTTPClient.METHOD_GET, "/v1/leaderboard?mode=" + mode + "&limit=20")
	if generation != _refresh_generation:
		return
	loading.queue_free()
	if not response.ok:
		_message(response.message, true)
		return
	var players: Array = response.data.get("players", [])
	for i in players.size():
		var profile: Dictionary = players[i]
		var stats: Dictionary = profile[mode]
		var card = _card(content)
		_label(card, "%02d     %s     ·     %s" % [i + 1, profile.displayName, stats.rating], 23, GOLD if profile.playerId == Settings.account.get("playerId") else PAPER)
		_label(card, "%d wins · %d losses · %d draws" % [stats.wins, stats.losses, stats.draws], 14, MUTED)
	if players.is_empty():
		_label(content, "The ladder is ready for its first players.", 20, MUTED)

func _queue() -> void:
	if _busy:
		return
	_busy = true
	var response = await api.call_api(HTTPClient.METHOD_POST, "/v1/queue", match_options())
	_busy = false
	_accept_status(response)

func _create_private() -> void:
	if _busy:
		return
	_busy = true
	var options = match_options()
	options.erase("ranked")
	var response = await api.call_api(HTTPClient.METHOD_POST, "/v1/private", options)
	_busy = false
	_accept_status(response)

func _join_private() -> void:
	if _busy or invite_edit == null:
		return
	var code = invite_edit.text.strip_edges().to_upper()
	if code.length() != 6:
		_message("Enter the six-character invite code.", true)
		return
	_busy = true
	var response = await api.call_api(HTTPClient.METHOD_POST, "/v1/private/join", {"code": code})
	_busy = false
	_accept_status(response)

func _cancel_queue() -> void:
	var response = await api.call_api(HTTPClient.METHOD_DELETE, "/v1/queue")
	_accept_status(response)

func _poll_status() -> void:
	if _polling or _opening or Settings.token.is_empty():
		return
	_polling = true
	var response = await api.call_api(HTTPClient.METHOD_GET, "/v1/status")
	_polling = false
	_accept_status(response, false)

func _accept_status(response: Dictionary, redraw: bool = true) -> void:
	if not response.ok:
		_message(response.message, true)
		return
	status = response.data.status.duplicate(true)
	if status.allocation != null:
		_open_allocation(status.allocation)
		return
	if redraw and page == "play":
		navigate("play")
	elif is_instance_valid(queue_label):
		queue_label.text = _status_text()

func _status_text() -> String:
	if status.invite != null:
		return "Private invite  ·  " + str(status.invite.code) + "  ·  Share this code with a friend."
	if status.queue != null:
		return "Searching for " + ("a ranked" if status.queue.ranked else "an unranked") + " " + str(status.queue.mode).capitalize() + " opponent…"
	return "Ready when you are. Find an opponent or invite a friend."

func _open_allocation(allocation: Dictionary) -> void:
	if _opening:
		return
	_opening = true
	_message("Opponent found. Securing your seat…")
	var response = await api.call_api(HTTPClient.METHOD_POST, "/v1/tickets", {"matchId": allocation.matchId})
	if not response.ok:
		_opening = false
		_message(response.message, true)
		return
	Settings.launch = {"allocation": response.data.allocation, "ticket": response.data.ticket, "view3d": Settings.preferred_3d, "apiUrl": Settings.api_url}
	get_tree().change_scene_to_file("res://network/client/online_lobby.tscn")

func _process(delta: float) -> void:
	_poll_timer += delta
	if _poll_timer >= 2.0:
		_poll_timer = 0.0
		if not Settings.token.is_empty() and (status.queue != null or status.invite != null):
			_poll_status()
