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

static func build(m: Control) -> Control:
	m.hud = {}
	var backdrop := Backdrop.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_child(backdrop)
	var frame := Kit.safe_frame(m, 16)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	frame.add_child(column)
	# ---- toolbar
	var toolbar := Kit.flow(column, 8, 6)
	toolbar.name = "Toolbar"
	var brand := Kit.button(toolbar, "PEEPEECHESS", m._main_menu, "GhostButton", "emblem", "Return to the application menu.")
	brand.add_theme_font_size_override("font_size", T.FS_LEAD)
	brand.add_theme_color_override("font_color", T.GOLD_HI)
	var chip := Kit.chip(toolbar, "CLASSIC")
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	m.mode_label = chip.get_child(0)
	m.mode_select = OptionButton.new()
	m.mode_select.custom_minimum_size.y = Kit.target_height()
	m.mode_select.add_item("Classic Chess")
	m.mode_select.add_item("Battle Chess · C0")
	m.mode_select.item_selected.connect(m._switch_mode)
	toolbar.add_child(m.mode_select)
	Kit.button(toolbar, "Online", m._online_menu, "", "cloud", "Find an opponent or invite a friend.")
	Kit.button(toolbar, "New game", m._show_new, "", "play", "Choose a time control and start a local two-player match.")
	m.view_button = Kit.button(toolbar, "3D board", func(): m.set_view(not m._view_3d), "", "", "Switch views without restarting the match.")
	m.flip_button = Kit.button(toolbar, "Flip board", func(): m.set_flipped(not m._flipped), "", "", "Change only your local perspective.")
	Kit.button(toolbar, "FEN / PGN", m._show_position, "", "list", "Import a position, or copy FEN and PGN.")
	# ---- body
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	m.body = BoxContainer.new()
	m.body.add_theme_constant_override("separation", 16)
	m.body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(m.body)
	m.board_panel = PanelContainer.new()
	m.board_panel.theme_type_variation = "HudPanel"
	m.board_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.board_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	m.body.add_child(m.board_panel)
	var host := Control.new()
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	m.board_panel.add_child(host)
	_build_side(m)
	m.message_label = Kit.label(column, "Ready · Choose New game for time controls. Undo is available in local play.", "Muted")
	m.message_label.add_theme_font_size_override("font_size", T.FS_SMALL)
	return host

static func _player_card(m: Control, parent: Container, side: String) -> void:
	var card := PanelContainer.new()
	card.theme_type_variation = "PlayerCard"
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
	var name_label := Kit.label(info, "White" if side == "w" else "Black", "H3", false)
	var captured := HBoxContainer.new()
	captured.add_theme_constant_override("separation", -6)
	captured.custom_minimum_size.y = 16
	info.add_child(captured)
	var balance := Kit.label(captured, "", "Caption", false)
	balance.add_theme_color_override("font_color", T.GOLD)
	var clock := Kit.label(row, "10:00", "ClockLabel", false)
	clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	clock.custom_minimum_size.x = 96
	if side == "w":
		m.clock_white = clock
	else:
		m.clock_black = clock
	m.hud["card_" + side] = card
	m.hud["captured_" + side] = captured
	m.hud["balance_" + side] = balance
	m.hud["name_" + side] = name_label

static func _build_side(m: Control) -> void:
	m.info_panel = PanelContainer.new()
	m.info_panel.theme_type_variation = "HudPanel"
	m.info_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	m.body.add_child(m.info_panel)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 10)
	m.info_panel.add_child(info)
	Kit.section_header(info, "Local two-player", "user")
	var players := VBoxContainer.new()
	players.add_theme_constant_override("separation", 8)
	info.add_child(players)
	m.hud["players"] = players
	_player_card(m, players, "b")
	_player_card(m, players, "w")
	var banner := PanelContainer.new()
	banner.theme_type_variation = "InsetPanel"
	banner.name = "StatusBanner"
	info.add_child(banner)
	var banner_row := HBoxContainer.new()
	banner_row.add_theme_constant_override("separation", 10)
	banner.add_child(banner_row)
	var banner_icon := Icons.new("crown", 26, T.GOLD)
	banner_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	banner_row.add_child(banner_icon)
	m.status_label = Kit.label(banner_row, "White to move", "H3")
	m.status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.hud["banner"] = banner
	m.hud["banner_icon"] = banner_icon
	var actions := Kit.flow(info, 6, 6)
	m.start_button = Kit.primary(actions, "Start clock", func(): m.game.start_clock(), "clock")
	m.pause_button = Kit.secondary(actions, "Pause", func(): m.game.set_paused(not m.game.paused))
	m.undo_button = Kit.button(actions, "Undo", func(): m.opponent.undo(), "", "", "Local practice only. Restores the previous move and clock checkpoint.")
	Kit.danger(actions, "Resign", m._confirm_resign, "flag")
	m.claim_button = Kit.secondary(info, "Draw options", m._show_draw)
	Kit.section_header(info, "Move history", "list")
	var history_frame := PanelContainer.new()
	history_frame.theme_type_variation = "InsetPanel"
	history_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.add_child(history_frame)
	m.history_text = RichTextLabel.new()
	m.history_text.bbcode_enabled = true
	m.history_text.selection_enabled = true
	m.history_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	m.history_text.custom_minimum_size = Vector2(0, 90)
	m.history_text.focus_mode = Control.FOCUS_NONE
	history_frame.add_child(m.history_text)
	var hint := Kit.label(info, "Select a piece to see legal moves. Touch: tap a piece, then a square.", "Muted")
	hint.add_theme_font_size_override("font_size", T.FS_SMALL)
	var animate := Kit.toggle_row(info, "Animate moves", AppSettings.animations, func(on):
		m.board_2d.animation_enabled = on
		m.board_3d.animation_enabled = on
		AppSettings.animations = on
		AppSettings.save_preferences(), "")
	animate.tooltip_text = "Turn off movement animations."
	m.hud["animate"] = animate

## Puts the card of the side shown at the bottom (the one the board faces) last.
static func arrange(m: Control, flipped: bool) -> void:
	var players: VBoxContainer = m.hud.get("players")
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
