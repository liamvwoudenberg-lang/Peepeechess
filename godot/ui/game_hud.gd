extends RefCounted
## Heads-up display of the chess screen (godot/app/main.gd): top toolbar, player cards with clocks and captured
## material, turn / check / result banner, action buttons and a styled move list. main.gd keeps the game logic and
## calls Hud.build(self) once, Hud.refresh(self) after every state change and Hud.update_clocks(self) each frame
## (cheap: texts only change when the displayed second changes).
const T = preload("res://ui/theme/ui_tokens.gd")
const Kit = preload("res://ui/theme/ui_kit.gd")
const Icons = preload("res://ui/theme/ui_icons.gd")
const Motion = preload("res://ui/theme/ui_motion.gd")
const Backdrop = preload("res://ui/theme/backdrop.gd")
const AppSettings = preload("res://ui/application_settings.gd")
const START_COUNTS := {"p": 8, "n": 2, "b": 2, "r": 2, "q": 1}
const VALUES := {"p": 1, "n": 3, "b": 3, "r": 5, "q": 9}
const ICON := {"p": "pawn", "n": "knight", "b": "bishop", "r": "rook_piece", "q": "queen", "k": "king"}
const PIECE_NAMES := {"q": "Queen", "r": "Rook", "b": "Bishop", "n": "Knight"}

class Swatch:
	extends Control
	var light := true
	func _init(is_light: bool = true) -> void:
		light = is_light
		custom_minimum_size = Vector2(26, 26)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var centre := size * 0.5
		draw_circle(centre, 12.0, Color("f1eadb") if light else Color("14181d"))
		draw_arc(centre, 12.0, 0.0, TAU, 28, Color("8d97a6") if light else Color("c9cfd9"), 1.6, true)

## Pure helper (unit-tested): captured pieces and material balance from a FEN. Returns
## {"w": {"p": n, ...}, "b": {...}, "balance": white material minus black material} where "w" lists WHITE pieces that
## have been captured (missing from the board) and likewise for "b". Promotions never produce negative counts.
static func captured_from_fen(fen: String) -> Dictionary:
	var placement := fen.split(" ")[0]
	var present := {"w": {}, "b": {}}
	for ch in placement:
		if ch == "/" or ch.is_valid_int():
			continue
		var side := "w" if ch == ch.to_upper() else "b"
		var role := ch.to_lower()
		present[side][role] = int(present[side].get(role, 0)) + 1
	var result := {"w": {}, "b": {}, "balance": 0}
	var material := {"w": 0, "b": 0}
	for side in ["w", "b"]:
		for role in START_COUNTS:
			var missing := maxi(0, int(START_COUNTS[role]) - int(present[side].get(role, 0)))
			if missing > 0:
				result[side][role] = missing
			material[side] += int(present[side].get(role, 0)) * int(VALUES[role])
	result.balance = material.w - material.b
	return result

## The world fills the window; only these small controls float above it. Everything that used to consume a
## permanent sidebar remains reachable in the match drawer. Nodes and match callbacks are retained.
static func build(m: Control) -> Control:
	m.hud = {"combat": false, "drawer_open": false}
	m.body = BoxContainer.new()
	m.body.name = "GameViewport"
	m.body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_child(m.body)
	m.board_panel = PanelContainer.new()
	m.board_panel.name = "BoardViewport"
	m.board_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	m.board_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.board_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	m.body.add_child(m.board_panel)
	var host := Control.new()
	host.name = "BoardHost"
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	m.board_panel.add_child(host)
	var frame := Kit.safe_frame(m, 12)
	frame.name = "ChessChrome"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chrome := Control.new()
	chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(chrome)
	m.hud["chrome"] = frame
	m.hud["root"] = chrome
	chrome.resized.connect(func(): layout(m))
	var top := HBoxContainer.new()
	top.name = "FloatingToolbar"
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.add_theme_constant_override("separation", 6)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chrome.add_child(top)
	Kit.button(top, "Menu", func(): toggle_drawer(m), "", "list", "Match options and move history · Esc")
	var chip := Kit.chip(top, "CLASSIC")
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	m.mode_label = chip.get_child(0)
	m.hud["mode_chip"] = chip
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	m.view_button = Kit.button(top, "3D", func(): m.set_view(not m._view_3d), "", "", "Switch illustrated 2D / castle 3D")
	var overhead := Kit.button(top, "Top", func(): m._toggle_overhead(), "", "", "True top-down / tactical camera")
	m.hud["overhead"] = overhead
	var fullscreen := Kit.button(top, "[ ]", func(): m._toggle_fullscreen(), "", "", "Fullscreen · F11")
	fullscreen.visible = preload("res://ui/screen_mode.gd").available()
	fullscreen.custom_minimum_size.x = 44
	m.hud["fullscreen"] = fullscreen
	var help := Kit.button(top, "?", func(): toggle_help(m), "", "", "Controls · F1")
	help.custom_minimum_size.x = 44
	var bottom := VBoxContainer.new()
	bottom.name = "FloatingPlayers"
	bottom.add_theme_constant_override("separation", 6)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chrome.add_child(bottom)
	m.hud["bottom"] = bottom
	var banner := PanelContainer.new()
	banner.theme_type_variation = "InsetPanel"
	banner.name = "StatusBanner"
	banner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bottom.add_child(banner)
	var banner_row := HBoxContainer.new()
	banner_row.add_theme_constant_override("separation", 8)
	banner.add_child(banner_row)
	var banner_icon := Icons.new("crown", 18, T.GOLD)
	banner_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	banner_row.add_child(banner_icon)
	m.status_label = Kit.label(banner_row, "White to move", "", false)
	m.status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	m.status_label.custom_minimum_size.x = 120
	m.status_label.add_theme_font_size_override("font_size", 16)
	m.hud["banner"] = banner
	m.hud["banner_icon"] = banner_icon
	var players := HBoxContainer.new()
	players.add_theme_constant_override("separation", 8)
	players.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(players)
	m.hud["players"] = players
	_player_card(m, players, "b")
	_player_card(m, players, "w")
	_build_drawer(m, chrome)
	_build_help(m, chrome)
	m.message_label = Kit.label(m.info_panel.get_node("Scroll/Contents"), "", "Muted")
	m.message_label.add_theme_font_size_override("font_size", T.FS_SMALL)
	layout(m)
	return host

static func _build_drawer(m: Control, chrome: Control) -> void:
	var scrim := ColorRect.new()
	scrim.name = "DrawerScrim"
	scrim.color = Color(0.02, 0.025, 0.03, 0.65)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.hide()
	scrim.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			toggle_drawer(m))
	chrome.add_child(scrim)
	m.hud["scrim"] = scrim
	m.info_panel = PanelContainer.new()
	m.info_panel.name = "MatchDrawer"
	m.info_panel.theme_type_variation = "RaisedPanel"
	m.info_panel.hide()
	chrome.add_child(m.info_panel)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	m.info_panel.add_child(scroll)
	var info := VBoxContainer.new()
	info.name = "Contents"
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 10)
	scroll.add_child(info)
	var header := HBoxContainer.new()
	info.add_child(header)
	var heading := Kit.label(header, "MATCH OPTIONS", "Accent", false)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Kit.button(header, "Close", func(): toggle_drawer(m))
	Kit.section_header(info, "Local two-player", "user")
	var toolbar := Kit.flow(info, 8, 6)
	toolbar.name = "Toolbar"
	m.mode_select = OptionButton.new()
	m.mode_select.custom_minimum_size.y = Kit.target_height()
	m.mode_select.add_item("Classic Chess")
	m.mode_select.add_item("Battle Chess · C0")
	m.mode_select.item_selected.connect(m._switch_mode)
	toolbar.add_child(m.mode_select)
	Kit.button(toolbar, "New game", m._show_new, "", "play")
	m.flip_button = Kit.button(toolbar, "Flip board", func(): m.set_flipped(not m._flipped))
	Kit.button(toolbar, "Online", m._online_menu, "", "cloud")
	Kit.button(toolbar, "FEN / PGN", m._show_position, "", "list")
	Kit.button(toolbar, "Main menu", m._main_menu, "", "emblem")
	var actions := Kit.flow(info, 6, 6)
	m.start_button = Kit.primary(actions, "Start clock", func(): m.game.start_clock(), "clock")
	m.pause_button = Kit.secondary(actions, "Pause", func(): m.game.set_paused(not m.game.paused))
	m.undo_button = Kit.button(actions, "Undo", func(): m.opponent.undo())
	Kit.danger(actions, "Resign", m._confirm_resign, "flag")
	m.claim_button = Kit.secondary(info, "Draw options", m._show_draw)
	Kit.section_header(info, "Move history", "list")
	m.history_text = RichTextLabel.new()
	m.history_text.bbcode_enabled = true
	m.history_text.selection_enabled = true
	m.history_text.custom_minimum_size = Vector2(0, 120)
	m.history_text.focus_mode = Control.FOCUS_NONE
	info.add_child(m.history_text)
	var animate := Kit.toggle_row(info, "Animate moves", AppSettings.animations, func(on):
		m.board_2d.animation_enabled = on
		m.board_3d.animation_enabled = on
		AppSettings.animations = on
		AppSettings.save_preferences())
	m.hud["animate"] = animate

static func _build_help(m: Control, chrome: Control) -> void:
	var panel := PanelContainer.new()
	panel.name = "ChessHelp"
	panel.theme_type_variation = "RaisedPanel"
	panel.hide()
	chrome.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 12)
	scroll.add_child(box)
	Kit.label(box, "CONTROLS", "Accent", false)
	Kit.label(box, "Select a piece, then a legal square. Drag to move.\n\n3D camera: right-drag to orbit, wheel to zoom.\nTouch: tap to move, swipe to orbit, pinch to zoom.\nTop switches tactical / true overhead view.\n\nEsc opens match options. F11 toggles fullscreen.\nF1 shows or hides controls, including during duels.")
	Kit.button(box, "Close · F1", func(): toggle_help(m))
	m.hud["help"] = panel

static func layout(m: Control) -> void:
	if m.hud.is_empty():
		return
	var root: Control = m.hud["root"]
	var width := maxf(1.0, root.size.x if root.size.x > 1 else m.size.x - 24.0)
	var height := maxf(1.0, root.size.y if root.size.y > 1 else m.size.y - 24.0)
	var bottom: Control = m.hud["bottom"]
	var hud_width := minf(620.0, width)
	bottom.position = Vector2((width - hud_width) * 0.5, height - 108.0)
	bottom.size = Vector2(hud_width, 108)
	m.hud["mode_chip"].visible = width >= 560
	m.hud["overhead"].visible = m._view_3d
	for key in ["help"]:
		var overlay: Control = m.hud[key]
		var panel_size := Vector2(minf(440.0, width), minf(420.0, height - 100.0))
		overlay.position = Vector2((width - panel_size.x) * 0.5, maxf(56.0, (height - panel_size.y) * 0.5))
		overlay.size = panel_size
	var drawer_width := minf(420.0, width)
	m.info_panel.position = Vector2(0, 56)
	m.info_panel.size = Vector2(drawer_width, maxf(80.0, height - 64.0))

static func toggle_drawer(m: Control) -> void:
	if m.hud.get("combat", false):
		return
	m.hud["drawer_open"] = not m.info_panel.visible
	m.info_panel.visible = m.hud["drawer_open"]
	m.hud["scrim"].visible = m.info_panel.visible
	m.hud["bottom"].visible = not m.info_panel.visible
	m.hud["help"].hide()
	layout(m)
	if m.info_panel.visible:
		m.mode_select.grab_focus()
	else:
		m.get_viewport().gui_release_focus()

static func toggle_help(m: Control) -> void:
	if m.hud.get("combat", false):
		return
	var panel: Control = m.hud["help"]
	panel.visible = not panel.visible
	m.info_panel.hide()
	m.hud["scrim"].visible = panel.visible
	m.hud["bottom"].visible = not panel.visible
	layout(m)

## Visibility belongs to one parent: no chess buttons, instructions, history, clocks or tooltips can remain over a duel.
static func set_combat(m: Control, active: bool) -> void:
	if m.hud.is_empty():
		return
	m.hud["combat"] = active
	m.hud["chrome"].visible = not active
	if active:
		m.info_panel.hide()
		m.hud["help"].hide()
		m.hud["scrim"].hide()
		m.hud["drawer_open"] = false
		m.hud["bottom"].show()
		m.board_2d.tooltip_text = ""
		m.board_3d.tooltip_text = ""
		m.get_viewport().gui_release_focus()
		var toast := m.get_node_or_null("ToastLayer")
		if toast != null:
			toast.hide()

static func _player_card(m: Control, parent: Container, side: String) -> void:
	var card := PanelContainer.new()
	card.theme_type_variation = "PlayerCard"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", preload("res://ui/theme/peepee_theme.gd").flat(Color(0.055, 0.067, 0.075, 0.9), T.GOLD_LO, 1, 8, 10, 6))
	card.name = "PlayerCard" + side.to_upper()
	parent.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	var swatch := Swatch.new(side == "w")
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(swatch)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	row.add_child(info)
	var name_label := Kit.label(info, "White" if side == "w" else "Black", "", false)
	name_label.add_theme_font_size_override("font_size", 14)
	var captured := HBoxContainer.new()
	captured.add_theme_constant_override("separation", -6)
	captured.custom_minimum_size.y = 16
	info.add_child(captured)
	captured.hide()
	var balance := Kit.label(captured, "", "Caption", false)
	balance.add_theme_color_override("font_color", T.GOLD)
	var clock := Kit.label(row, "10:00", "", false)
	clock.add_theme_font_size_override("font_size", 22)
	clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	clock.custom_minimum_size.x = 68
	if side == "w":
		m.clock_white = clock
	else:
		m.clock_black = clock
	m.hud["card_" + side] = card
	m.hud["captured_" + side] = captured
	m.hud["balance_" + side] = balance
	m.hud["name_" + side] = name_label

## Puts the card of the side shown at the bottom (the one the board faces) last.
static func arrange(m: Control, flipped: bool) -> void:
	var players: BoxContainer = m.hud.get("players")
	if players == null:
		return
	var top := "w" if flipped else "b"
	var bottom := "b" if flipped else "w"
	players.move_child(m.hud["card_" + top], 0)
	players.move_child(m.hud["card_" + bottom], 1)

static func _set_captured(m: Control, side: String, counts: Dictionary, lead: int) -> void:
	var row: HBoxContainer = m.hud["captured_" + side]
	var balance: Label = m.hud["balance_" + side]
	row.remove_child(balance)
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()
	var tint := Color("f1eadb") if side == "w" else Color("7f8ea6")
	for role in ["q", "r", "b", "n", "p"]:
		for i in int(counts.get(role, 0)):
			row.add_child(Icons.new(ICON[role], 16, tint))
	balance.text = ("  +%d" % lead) if lead > 0 else ""
	row.add_child(balance)

## Re-styles the HUD for the current position. Called by main._refresh() after it has set status_label.text.
static func refresh(m: Control) -> void:
	if m.hud.is_empty():
		return
	var engine = m.game.engine
	var side: String = engine.turn
	var over: bool = not engine.result.is_empty()
	var check: bool = not over and engine.in_check()
	for s in ["w", "b"]:
		var active: bool = s == side and not over
		(m.hud["card_" + s] as PanelContainer).theme_type_variation = "PlayerCardActive" if active else "PlayerCard"
		var clock: Label = m.clock_white if s == "w" else m.clock_black
		clock.add_theme_color_override("font_color", T.GOLD_HI if active else T.TEXT_MUTED)
	var banner: PanelContainer = m.hud["banner"]
	var icon: Control = m.hud["banner_icon"]
	var previous: String = str(banner.get_meta(&"state", ""))
	var state := "turn"
	if over:
		state = "result"
	elif check:
		state = "check"
	elif m.game.paused:
		state = "paused"
	banner.theme_type_variation = {"result": "ResultPanel", "check": "CheckPanel"}.get(state, "InsetPanel")
	icon.kind = {"result": "trophy", "check": "warning", "paused": "clock"}.get(state, "crown")
	icon.color = {"result": T.GOLD_HI, "check": T.DANGER}.get(state, T.GOLD)
	if previous != state:
		banner.set_meta(&"state", state)
		if state in ["check", "result"]:
			Motion.fade_in(banner, 0.22, 0.96)
	# captured material (rebuilt only when the placement changes)
	var fen: String = engine.fen()
	var placement := fen.split(" ")[0]
	if str(m.hud.get("placement", "")) != placement:
		m.hud["placement"] = placement
		var captured := captured_from_fen(fen)
		var balance: int = captured.balance
		_set_captured(m, "w", captured.b, maxi(0, balance))   # white's row: black pieces white has captured
		_set_captured(m, "b", captured.w, maxi(0, -balance))
	render_history(m)

static func render_history(m: Control) -> void:
	var engine = m.game.engine
	var text: RichTextLabel = m.history_text
	text.clear()
	if engine.history.is_empty():
		text.append_text("[color=#b0b4bc]Your moves will appear here.[/color]")
		return
	var fields: PackedStringArray = engine.initial_fen.split(" ")
	var color_to_play: String = fields[1]
	var number := int(fields[5])
	var last: int = engine.history.size() - 1
	for i in engine.history.size():
		if color_to_play == "w":
			text.append_text("[color=#b0b4bc]%d.[/color]  " % number)
		elif i == 0:
			text.append_text("[color=#b0b4bc]%d...[/color]  " % number)
		var san: String = engine.history[i].san
		if i == last:
			text.append_text("[color=#f6d68f][b]%s[/b][/color]" % san.replace("[", "[lb]"))
			text.append_text("\n" if color_to_play == "b" else "     ")
		else:
			text.add_text(san + ("\n" if color_to_play == "b" else "     "))
		if color_to_play == "b":
			number += 1
		color_to_play = "b" if color_to_play == "w" else "w"
	text.scroll_to_line(maxi(0, text.get_line_count() - 1))

## Per-frame: only touches a Label when its text (the displayed second) or the low-time state really changed.
static func update_clocks(m: Control) -> void:
	if m.clock_white == null:
		return
	for pair in [["w", m.clock_white], ["b", m.clock_black]]:
		var clock: Label = pair[1]
		clock.visible = m.game.timed   # untimed games (Battle C0, "Untimed") show no clock
		var ms: int = m.game.remaining[pair[0]]
		clock.text = m._time_text(ms)
		var low: bool = m.game.timed and ms < 10000 and ms > 0 and m.game.started and m.game.engine.result.is_empty()
		if bool(clock.get_meta(&"low", false)) != low:
			clock.set_meta(&"low", low)
			if low:
				clock.add_theme_color_override("font_color", T.DANGER)
			else:
				refresh(m)

# ---------------------------------------------------------------- battle capture card
static func _fighter_column(parent: Container, title: String, fighter: Dictionary) -> void:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 4)
	parent.add_child(column)
	var white: bool = fighter.get("color", "w") == "w"
	var icon := Icons.new(ICON.get(str(fighter.get("role", "p")), "pawn"), 52, Color("f1eadb") if white else Color("7f8ea6"))
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(icon)
	var caption := Kit.label(column, title, "Caption", false)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var role_name := Kit.label(column, ("White " if white else "Black ") + str(PIECE_NAMES.get(str(fighter.get("role", "p")), {"p": "Pawn", "k": "King"}.get(str(fighter.get("role", "p")), "Piece"))), "Accent", false)
	role_name.add_theme_font_size_override("font_size", T.FS_BODY)
	role_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var hp := Kit.label(column, "%s HP" % str(fighter.get("stats", {}).get("maxHp", "?")), "Accent", false)
	hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

## Capture-preview header: attacker VS defender with piece icons and hit points.
static func show_versus(m: Control, request: Dictionary) -> void:
	var column: VBoxContainer = m.battle_card.get_child(0)
	var row: HBoxContainer = m.hud.get("versus")
	if row == null or not is_instance_valid(row):
		var caption := Kit.label(column, "CAPTURE PREVIEW", "Caption", false)
		caption.add_theme_color_override("font_color", T.GOLD)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.move_child(caption, 0)
		m.hud["versus_caption"] = caption
		row = HBoxContainer.new()
		row.name = "Versus"
		row.add_theme_constant_override("separation", T.S2)
		column.add_child(row)
		column.move_child(row, 1)
		m.hud["versus"] = row
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()
	_fighter_column(row, "ATTACKER", request.get("attacker", {}))
	var vs := Kit.label(row, "VS", "H2", false)
	vs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_fighter_column(row, "DEFENDER", request.get("defender", {}))
	row.visible = true

static func set_versus_visible(m: Control, value: bool) -> void:
	for key in ["versus", "versus_caption"]:
		var node = m.hud.get(key)
		if node != null and is_instance_valid(node):
			node.visible = value
