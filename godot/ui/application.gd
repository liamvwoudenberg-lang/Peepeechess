extends Control
## Application navigation is independent from chess/combat authority.
const Settings = preload("res://ui/application_settings.gd")
const Api = preload("res://ui/account_api.gd")
const Results = preload("res://ui/results.gd")
const Kit = preload("res://ui/theme/ui_kit.gd")
const Tokens = preload("res://ui/theme/ui_tokens.gd")
const Motion = preload("res://ui/theme/ui_motion.gd")
const Backdrop = preload("res://ui/theme/backdrop.gd")
const Title = preload("res://ui/theme/title_screen.gd")
const Icons = preload("res://ui/theme/ui_icons.gd")
const SettingsPage = preload("res://ui/settings_page.gd")
const MaxWidth = preload("res://ui/theme/max_width_box.gd")
const INK = Tokens.BG
const PAPER = Tokens.TEXT
const MUTED = Tokens.TEXT_MUTED
const GOLD = Tokens.GOLD
const TIMES = [["3 + 2 · Blitz", 180000, 2000], ["5 + 0 · Blitz", 300000, 0], ["10 + 0 · Rapid", 600000, 0], ["15 + 10 · Rapid", 900000, 10000], ["30 + 0 · Classical", 1800000, 0]]
var api: Node
var page = "home"
var selected_mode = "classic"
var online = false
var ranked = false
var selected_time = 2
var opponent: Dictionary = OpponentUI.default_state()  # Local two-player / Computer (level, colour); see ui/opponent_ui.gd
var ruleset: Dictionary = {"royal": RoyalOption.load_choice()}  # king's last stand toggle (local Battle matches only); see ui/royal_option.gd
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
var _topbar: Control
var _topbar_holder: Control
var _page_width: MarginContainer
var _topbar_badge: Button
var _backdrop: Control
var _last_toast = ""
var _toast_clock = 0.0
var _history_loading = false
var _history_more_button: Button

func _ready() -> void:
	Settings.load_preferences()
	Settings.ensure_platform(get_tree())
	if Settings.launch.get("menu", "") == "online":
		var context = Settings.take_launch()
		online = true
		selected_mode = "battle" if context.get("mode", "classic") == "battle" else "classic"
	api = Api.new()
	add_child(api)
	_build_theme()
	_build_frame()
	navigate("play" if online else "home")
	PadUi.install(self, {"prefer": "content", "back": Callable(self, "_pad_back")})  # controller / keyboard focus (claude/pads-input)
	if not Settings.token.is_empty():
		_refresh_account()
	if not Settings.result.is_empty():
		var recent = Settings.result.duplicate(true)
		Settings.result.clear()
		Results.show_dialog(self, recent, func(): pass, func(): navigate("history"))

func _build_theme() -> void:
	Kit.install(self)  # shared design-system theme (godot/ui/theme), press animation and UI sounds

func _label(parent: Node, text: String, size_px: int = 17, color: Color = PAPER) -> Label:
	var variant = "Muted" if color == MUTED else ("Accent" if color == GOLD else ("H3" if size_px >= 20 and color == PAPER else ""))
	var label = Kit.label(parent, text, variant)
	if size_px != 17:
		label.add_theme_font_size_override("font_size", size_px)
	if color not in [PAPER, MUTED, GOLD]:
		label.add_theme_color_override("font_color", color)
	return label

func _button(parent: Node, text: String, action: Callable, primary: bool = false) -> Button:
	return Kit.button(parent, text, action, "PrimaryButton" if primary else "")

func _field(parent: Node, placeholder: String, secret: bool = false) -> LineEdit:
	var field = LineEdit.new()
	field.placeholder_text = placeholder
	field.secret = secret
	field.custom_minimum_size.y = Kit.target_height()
	field.max_length = 128 if secret else 64
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(field)
	return field

func _card(parent: Node) -> VBoxContainer:
	return Kit.card(parent)

func _flow(parent: Node) -> HFlowContainer:
	return Kit.flow(parent)

func _build_frame() -> void:
	_backdrop = Backdrop.new()
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_backdrop)
	var margin = Kit.safe_frame(self)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	var top_width = MaxWidth.new()  # keeps the navigation aligned with the centred page column on wide screens
	top_width.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(top_width)
	_topbar = VBoxContainer.new()
	_topbar.add_theme_constant_override("separation", 10)
	top_width.add_child(_topbar)
	_topbar_holder = top_width
	var brand_row = HBoxContainer.new()
	brand_row.add_theme_constant_override("separation", 12)
	_topbar.add_child(brand_row)
	var brand = Kit.button(brand_row, "PEEPEECHESS", func(): navigate("home"), "GhostButton", "emblem")
	brand.add_theme_font_size_override("font_size", 22)
	brand.add_theme_color_override("font_color", Tokens.GOLD_HI)
	brand.tooltip_text = "Main menu"
	var brand_spacer = Control.new()
	brand_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand_row.add_child(brand_spacer)
	account_badge = Kit.button(brand_row, "Sign in", func(): navigate("account"), "", "user")
	_topbar_badge = account_badge
	var nav = _flow(_topbar)
	for item in [["play", "Play", "crown"], ["profile", "Profile", "user"], ["history", "Match history", "clock"], ["leaderboard", "Leaderboard", "trophy"], ["settings", "Settings", "gear"]]:
		var target: String = item[0]
		_menu_buttons[target] = Kit.button(nav, item[1], func(): navigate(target), "NavButton", item[2])
	page_scroll = ScrollContainer.new()
	page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(page_scroll)
	var page_width = MaxWidth.new()
	page_width.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_width.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page_scroll.add_child(page_width)
	_page_width = page_width
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 18)
	page_width.add_child(content)
	var footer = MaxWidth.new()
	footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(footer)
	notice = _label(footer, "Your board. Your perspective. One shared game.", 14, MUTED)
	_update_badge()

## Circle on a controller: leave a sub-page for Play (PadUi calls this only when no dialog is open).
func _pad_back() -> void:
	if page != "play" and page != "home":
		navigate("play")
	elif page == "play":
		navigate("home")

func navigate(target: String) -> void:
	page = target if target in ["home", "play", "profile", "history", "leaderboard", "settings", "account"] else "play"
	_refresh_generation += 1
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	for key in _menu_buttons:
		_menu_buttons[key].theme_type_variation = "NavButtonActive" if key == page else "NavButton"
	account_badge = _topbar_badge
	_topbar_holder.visible = page != "home"
	notice.visible = page != "home"
	_backdrop.mode = "home" if page == "home" else "page"
	_page_width.max_width = 4000.0 if page == "home" else 1120.0
	_page_width.call("_fit")
	page_scroll.scroll_vertical = 0
	queue_label = null
	_history_loading = false
	_history_more_button = null
	match page:
		"home": Title.build(self, content, not OS.has_feature("mobile") and not OS.has_feature("web"))
		"play": _play_page()
		"account": _account_page()
		"settings": _settings_page()
		"profile": _profile_page()
		"history": _history_page()
		"leaderboard": _leaderboard_page()
	_update_badge()
	Motion.fade_in(content, Motion.DURATION, 1.0)

func _heading(title: String, detail: String) -> void:
	var labels = Kit.heading(content, title, detail)
	title_label = labels[0]
	subtitle_label = labels[1]

func _update_badge() -> void:
	if is_instance_valid(account_badge):
		account_badge.text = str(Settings.account.get("displayName", "Account")) if not Settings.token.is_empty() else "Sign in"

func _message(text: String, error: bool = false) -> void:
	notice.text = text
	notice.add_theme_color_override("font_color", Tokens.DANGER if error else MUTED)
	var now = Time.get_ticks_msec() / 1000.0
	if text != _last_toast or now - _toast_clock > Kit.toast_seconds:  # repeated polling errors do not spam toasts
		_last_toast = text
		_toast_clock = now
		Kit.toast(self, text, "danger" if error else "info")

func _play_page() -> void:
	_heading("Make your next move.", "Classic precision or a capture worth fighting for. Choose your game, then make it yours.")
	var modes = _flow(content)
	for data in [["classic", "♜", "Classic Chess", "The complete game. Checkmate, clocks and every special move."], ["battle", "⚔", "Battle Chess", "Legal captures open a duel. The winner decides who stays."]]:
		var selected: String = data[0]
		var card = _card(modes)
		card.get_parent().custom_minimum_size.x = 300
		card.get_parent().theme_type_variation = "SelectedPanel" if selected_mode == selected else "CardPanel"
		Kit.icon_label_row(card, "rook" if selected == "classic" else "sword", data[2], "H2" if selected_mode == selected else "H3")
		_label(card, data[3], 15, MUTED).custom_minimum_size = Vector2(260, 48)
		_button(card, "Selected" if selected_mode == selected else "Choose " + data[2], func(): selected_mode = selected; navigate("play"), selected_mode == selected)
	var setup = _card(content)
	_label(setup, "YOUR MATCH", 13, GOLD)
	var row = _flow(setup)
	_button(row, "Local · two players" + (" ✓" if not online and opponent.kind == "local" else ""), func(): online = false; opponent.kind = "local"; navigate("play"), not online and opponent.kind == "local")
	_button(row, "Computer" + (" ✓" if not online and opponent.kind == "computer" else ""), func(): online = false; opponent.kind = "computer"; navigate("play"), not online and opponent.kind == "computer")  # computer opponent
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
		_label(setup, "Battle · untimed chess · " + ("King's last stand · kings stay on the board" if ruleset.royal and not online else "traditional checkmate · kings stay on the board"), 15, MUTED)
		if not online:
			RoyalOption.build(setup, ruleset, func(): navigate("play"))  # king's last stand: local Battle only (never online)
	if not online and opponent.kind == "computer":
		OpponentUI.build_computer_options(setup, opponent, func(): navigate("play"))  # level + colour pickers
	if not online:
		var vs_computer = opponent.kind == "computer"
		_button(setup, ("Play the computer · " if vs_computer else "Start local ") + selected_mode.capitalize() + " Chess  →", start_local, true)
		_label(setup, "Play the computer at six levels; in Battle Chess it also fights your duels. No account required." if vs_computer else "Pass-and-play chess. Battle duels use two local control schemes; no account required.", 14, MUTED)
		if selected_mode == "battle":  # claude/pads-input: who fights with what (change it in Settings -> Controls)
			var seats = InputAssignment.shared()
			_label(setup, "Duel controls · " + seats.describe(0) + " · " + seats.describe(1) + "   (Settings → Controls & controllers)", 14, MUTED)
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

## What start_local() hands to the game screen (app/main.gd, app/main_opponent.gd).
func launch_data() -> Dictionary:
	var options = match_options()
	var launch = {"mode": options.mode, "initialMs": options.initialMs, "incrementMs": options.incrementMs, "view3d": Settings.preferred_3d}
	if opponent.kind == "computer":
		launch["opponent"] = OpponentUI.normalize(opponent)  # consumed by app/main_opponent.gd
	if options.mode == "battle" and ruleset.royal:
		launch["royal"] = true  # king's last stand: consumed by app/main.gd (_switch_mode(1, royal))
	return launch

func start_local() -> void:
	Settings.launch = launch_data()
	get_tree().change_scene_to_file("res://app/main.tscn")

func _account_page() -> void:
	_heading("One account. Every board.", "Use the same sign-in on Windows and Android. Your online profile, match history and ratings stay together.")
	var card = _card(content)
	if not Settings.token.is_empty():
		Kit.icon_label_row(card, "user", "Signed in as " + str(Settings.account.get("displayName", "Player")), "H2")
		_label(card, "Sessions stay in memory for this run. Your password and account token are never saved in preferences.", 15, MUTED)
		var buttons = _flow(card)
		_button(buttons, "View profile", func(): navigate("profile"), true)
		Kit.danger(buttons, "Sign out", func(): Kit.confirm(self, "Sign out?", "You will need your password to sign in again on this device.", "Sign out", _sign_out, true))
		return
	Kit.section_header(card, "Sign in or create an account", "user")
	_label(card, "Username", 14, MUTED)
	username_edit = _field(card, "3–24 letters, numbers or underscore")
	username_edit.max_length = 24
	_label(card, "Display name (new accounts)", 14, MUTED)
	display_name_edit = _field(card, "How other players see you")
	display_name_edit.max_length = 32
	_label(card, "Password", 14, MUTED)
	password_edit = _field(card, "At least 10 characters", true)
	password_edit.text_submitted.connect(func(_text): _authenticate(false))
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
	SettingsPage.build(self)  # godot/ui/settings_page.gd

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
	Kit.empty_state(content, "lock", "Sign in to continue", "Your online profile, match history and rankings live on your account.", "Sign in / create account", func(): navigate("account"))
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
	var head = HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	card.add_child(head)
	head.add_child(Icons.new("user", 44, Tokens.GOLD))
	var names = VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(names)
	var name_label = Kit.label(names, str(profile.get("displayName", "Player")), "H2")
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_label(names, "@" + str(profile.get("username", "")) + "  ·  Player ID " + str(profile.get("playerId", "")), 14, MUTED)
	var row = Kit.responsive(card, 700.0)
	for mode in ["classic", "battle"]:
		var stats: Dictionary = profile.get(mode, {})
		var column = Kit.card(row, "RaisedPanel", 8)
		column.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
		Kit.icon_label_row(column, "rook" if mode == "classic" else "sword", mode.capitalize() + " Chess", "H3")
		var rating = _label(column, str(stats.get("rating", 1200)), 42, GOLD)
		rating.add_theme_font_size_override("font_size", 42)
		_label(column, "RATING", 12, MUTED)
		var games = int(stats.get("games", 0))
		var bar = ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size.y = 10
		bar.max_value = maxf(1.0, games)
		bar.value = int(stats.get("wins", 0))
		bar.tooltip_text = "Wins out of games played"
		column.add_child(bar)
		_label(column, "%d wins   %d losses   %d draws   ·   %d games" % [stats.get("wins", 0), stats.get("losses", 0), stats.get("draws", 0), games], 15, MUTED)
	Kit.button(card, "Match history", func(): navigate("history"), "", "clock").size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

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

func _load_history(generation: int, offset: int = 0) -> void:
	if generation != _refresh_generation or page != "history" or _history_loading:
		return
	_history_loading = true
	var previous_button = _history_more_button
	if is_instance_valid(previous_button):
		previous_button.disabled = true
	var loading = Kit.loading_state(content, "Loading match history…")
	var response = await api.call_api(HTTPClient.METHOD_GET, "/v1/history/summary?limit=20&offset=" + str(offset))
	if generation != _refresh_generation:
		return
	_history_loading = false
	loading.queue_free()
	if not response.ok:
		if is_instance_valid(previous_button):
			previous_button.disabled = false
		_message(response.message, true)
		if offset == 0:
			Kit.error_state(content, "Match history could not be loaded. " + str(response.message), "Try again", func(): navigate("history"))
		return
	if is_instance_valid(previous_button):
		previous_button.queue_free()
	_history_more_button = null
	var matches: Array = response.data.get("matches", [])
	if matches.is_empty() and offset == 0:
		Kit.empty_state(content, "list", "No online matches yet", "Your first online match is waiting. Find an opponent from Play.", "Find a match", func(): online = true; navigate("play"))
	for record in matches:
		var card = _card(content)
		var is_white = record.whitePlayerId == Settings.account.get("playerId")
		var own_side = "white" if is_white else "black"
		var result = "Draw" if record.result == "draw" else ("Aborted" if record.result == "aborted" else ("Victory" if record.result == own_side else "Defeat"))
		var tint = Tokens.SUCCESS if result == "Victory" else (Tokens.DANGER if result == "Defeat" else Tokens.TEXT_MUTED)
		var head = HBoxContainer.new()
		head.add_theme_constant_override("separation", 10)
		card.add_child(head)
		head.add_child(Icons.new("trophy" if result == "Victory" else ("flag" if result == "Defeat" else "shield"), 26, tint))
		var title = _label(head, result + " · " + str(record.mode).capitalize() + " Chess", 21, GOLD)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		Kit.chip(head, "Ranked" if record.ranked else "Unranked", Tokens.GOLD if record.ranked else Tokens.TEXT_MUTED)
		var opponent: String = record.blackName if is_white else record.whiteName
		var delta = int(record.ratingChange.white if is_white else record.ratingChange.black)
		_label(card, "vs " + opponent + " · " + str(record.reason).replace("_", " ") + "\n" + str(record.plies) + " moves · " + ("+" if delta > 0 else "") + str(delta) + " rating · " + Time.get_datetime_string_from_unix_time(int(record.completedAt / 1000)).replace("T", " ") + " UTC", 15, MUTED)
		Kit.button(card, "Copy final FEN", func(): DisplayServer.clipboard_set(str(record.finalFen)); _message("Final position copied."), "GhostButton", "list").size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var next = response.data.get("nextOffset")
	if next != null:
		_history_more_button = _button(content, "Load older matches", func(): _load_history(generation, int(next)))

func _leaderboard_page() -> void:
	_heading("Earn your place.", "Separate Classic and Battle Chess ladders. Ratings can only be updated by authoritative match results.")
	if not _signed_in_or_prompt():
		return
	Kit.segmented(content, [["classic", "Classic"], ["battle", "Battle"]], selected_mode, func(value): selected_mode = value; navigate("leaderboard")).size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_load_leaderboard(_refresh_generation, selected_mode)

func _load_leaderboard(generation: int, mode: String) -> void:
	var loading = Kit.loading_state(content, "Loading leaderboard…")
	var response = await api.call_api(HTTPClient.METHOD_GET, "/v1/leaderboard?mode=" + mode + "&limit=20")
	if generation != _refresh_generation:
		return
	loading.queue_free()
	if not response.ok:
		_message(response.message, true)
		Kit.error_state(content, "The leaderboard could not be loaded. " + str(response.message), "Try again", func(): navigate("leaderboard"))
		return
	var players: Array = response.data.get("players", [])
	for i in players.size():
		var profile: Dictionary = players[i]
		var stats: Dictionary = profile[mode]
		var own = profile.playerId == Settings.account.get("playerId")
		var card = Kit.card(content, "SelectedPanel" if own else "CardPanel", 6)
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		card.add_child(row)
		var rank = _label(row, "%02d" % (i + 1), 28, GOLD if i < 3 else MUTED)
		rank.autowrap_mode = TextServer.AUTOWRAP_OFF
		rank.custom_minimum_size.x = 48
		var names = VBoxContainer.new()
		names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(names)
		var name_label = _label(names, str(profile.displayName), 21, GOLD if own else PAPER)
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_label(names, "%d wins · %d losses · %d draws" % [stats.wins, stats.losses, stats.draws], 14, MUTED)
		var rating = _label(row, str(stats.rating), 26, GOLD)
		rating.autowrap_mode = TextServer.AUTOWRAP_OFF
		var player_id: String = profile.playerId
		Kit.button(row, "Profile", func(): _view_player_profile(player_id), "GhostButton", "user")
	if players.is_empty():
		Kit.empty_state(content, "trophy", "The ladder is ready for its first players", "Play a ranked online match to appear here.")

func _view_player_profile(player_id: String) -> void:
	var response = await api.call_api(HTTPClient.METHOD_GET, "/v1/profile?playerId=" + player_id.uri_encode())
	if not response.ok:
		_message(response.message, true)
		return
	var profile: Dictionary = response.data.profile
	var dialog = AcceptDialog.new()
	dialog.title = str(profile.displayName)
	dialog.ok_button_text = "Close profile"
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	dialog.add_child(column)
	_label(column, str(profile.displayName), 28, GOLD)
	_label(column, "@" + str(profile.username), 16, MUTED)
	for mode in ["classic", "battle"]:
		var stats: Dictionary = profile[mode]
		_label(column, "%s Chess · %d rating\n%d wins · %d losses · %d draws" % [mode.capitalize(), stats.rating, stats.wins, stats.losses, stats.draws], 17)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(380, 260))

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
