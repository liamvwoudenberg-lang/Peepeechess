class_name RoyalPresenter
extends Node
## battle-royal-v1 ("the King's last stand") overlay for the local game screen (app/main.gd). It only LISTENS to BattleFlow's
## re-emitted match signals (sequence_started, duel_started, duel_finished, sequence_finished) and the flow phase; it never
## touches the match, the combat or the pit:
##
##   * the banner "KING'S LAST STAND - duel i of n" with the King's carried HP / stamina / ability cooldown while the flow shows
##     the mandatory preview of a duel (the carried state is read from the match's RoyalSequenceProgress, which is fed by the
##     trusted simulation, never from a client);
##   * the combat HUD context line "LAST STAND / DUEL i/n" (CombatHud.set_context) for the duel that is being fought;
##   * a toast when the sequence ends and the note for the result screen ("the King fell in duel 2 of 3 against the Rook").
const Kit = preload("res://ui/theme/ui_kit.gd")
const Tokens = preload("res://ui/theme/ui_tokens.gd")
const ROLE_NAMES = {"p": "Pawn", "n": "Knight", "b": "Bishop", "r": "Rook", "q": "Queen", "k": "King"}
const HP_COLOR = Color("c93a3a")
const STAMINA_COLOR = Color("e8bd3a")
const COOLDOWN_COLOR = Color("8a62e0")
var main: Control
var flow: BattleFlow
var adapter: Node
var banner: PanelContainer
var last_summary: Dictionary = {}
var last_roles: Array = []
var _title: Label
var _subtitle: Label
var _hint: Label
var _hp: Bar
var _stamina: Bar
var _cooldown: Bar
var _hud_context: Object = null
var _roles: Array = []

## One labelled bar (ratio + "value / max" text), drawn with Control._draw.
class Bar extends Control:
	var caption = ""
	var value = 0.0
	var maximum = 1.0
	var text = ""
	var color = Color.WHITE
	func _init() -> void:
		custom_minimum_size = Vector2(300, 22)
	func set_state(p_caption: String, p_value: float, p_max: float, p_text: String, p_color: Color) -> void:
		caption = p_caption
		value = p_value
		maximum = maxf(p_max, 0.0001)
		text = p_text
		color = p_color
		queue_redraw()
	func ratio() -> float:
		return clampf(value / maximum, 0.0, 1.0)
	func _draw() -> void:
		var font = ThemeDB.fallback_font
		var label_w = 86.0
		draw_string(font, Vector2(0, size.y - 6), caption, HORIZONTAL_ALIGNMENT_LEFT, label_w, 14, Color(0.92, 0.9, 0.82))
		var rect = Rect2(label_w, 2, size.x - label_w, size.y - 4)
		draw_rect(rect, Color(0, 0, 0, 0.55))
		draw_rect(Rect2(rect.position, Vector2(rect.size.x * ratio(), rect.size.y)), color)
		draw_rect(rect, Color(1, 1, 1, 0.45), false, 1.5)
		draw_string(font, rect.position + Vector2(8, rect.size.y - 4), text, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 12, 14, Color(1, 1, 1))

func setup(host: Control, battle_flow: BattleFlow, battle_adapter: Node) -> void:
	main = host
	flow = battle_flow
	adapter = battle_adapter
	name = "RoyalPresenter"
	_build_banner()
	flow.phase_changed.connect(_on_phase)
	flow.sequence_started.connect(_on_sequence_started)
	flow.duel_started.connect(_on_duel_started)
	flow.sequence_finished.connect(_on_sequence_finished)

func dispose() -> void:
	if is_instance_valid(flow):
		for pair in [[flow.phase_changed, _on_phase], [flow.sequence_started, _on_sequence_started], [flow.duel_started, _on_duel_started], [flow.sequence_finished, _on_sequence_finished]]:
			if pair[0].is_connected(pair[1]):
				pair[0].disconnect(pair[1])
	flow = null
	if is_instance_valid(banner):
		banner.queue_free()
	banner = null

func _exit_tree() -> void:
	dispose()

func _build_banner() -> void:
	var overlay: Control = main.battle_overlay
	banner = PanelContainer.new()
	banner.name = "RoyalBanner"
	banner.theme_type_variation = "RaisedPanel"
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.visible = false
	overlay.add_child(banner)
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner.offset_top = 96
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	banner.add_child(column)
	_title = Kit.label(column, "KING'S LAST STAND", "H2", false)
	_title.name = "Title"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_color", Tokens.GOLD)
	_subtitle = Kit.label(column, "", "H3", false)
	_subtitle.name = "Subtitle"
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp = Bar.new()
	_hp.name = "KingHp"
	column.add_child(_hp)
	_stamina = Bar.new()
	_stamina.name = "KingStamina"
	column.add_child(_stamina)
	_cooldown = Bar.new()
	_cooldown.name = "KingCooldown"
	column.add_child(_cooldown)
	_hint = Kit.label(column, "", "Muted", true)
	_hint.name = "Hint"
	_hint.custom_minimum_size.x = 300
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

## "KING'S LAST STAND - duel 2 of 3" (index is 0-based).
static func banner_title(index: int, total: int) -> String:
	return "KING'S LAST STAND - duel %d of %d" % [index + 1, total]

## "DUEL 2/3" context line of the combat HUD (index is 0-based).
static func hud_context(index: int, total: int) -> String:
	return "LAST STAND\nDUEL %d/%d" % [index + 1, total]

func _on_sequence_started(info: Dictionary) -> void:
	_roles.clear()
	for entry in info.get("attackers", []):
		_roles.append(str(entry.get("role", "")))

func _on_phase(value: String) -> void:
	if banner == null or not is_instance_valid(banner):
		return
	var show = value == "preview" and flow.is_royal_duel()
	banner.visible = show
	if show:
		refresh()

func _on_duel_started(_index: int, _total: int, _king_hp: int) -> void:
	if is_instance_valid(banner) and banner.visible:
		refresh()

## Re-reads the banner content from the match (RoyalSequenceProgress / RoyalSequenceRequest of the running sequence).
func refresh() -> void:
	var game = flow.game
	var progress: Dictionary = game.royal_progress() if game.has_method("royal_progress") else {}
	if progress.is_empty():
		return
	var request: Dictionary = game.royal_request()
	var index = int(progress.duelIndex)
	var total = int(progress.duelCount)
	var king: Dictionary = progress.king
	var stats: Dictionary = request.king.stats
	var color_name = "White" if request.king.color == "w" else "Black"
	var checker_role = str(request.attackers[index].role) if index < request.attackers.size() else ""
	_title.text = banner_title(index, total)
	_subtitle.text = "The %s King faces the %s %s" % [color_name, "Black" if request.king.color == "w" else "White", ROLE_NAMES.get(checker_role, "piece")]
	var max_hp = float(stats.maxHp)
	var max_stamina = float(stats.maxStamina)
	var max_cooldown = float(stats.cooldownTicks)
	_hp.set_state("King HP", float(king.hp), max_hp, "%d / %d" % [int(king.hp), int(max_hp)], HP_COLOR)
	_stamina.set_state("Stamina", float(king.stamina), max_stamina, "%d / %d" % [roundi(float(king.stamina)), roundi(max_stamina)], STAMINA_COLOR)
	var ticks = float(king.cooldownTicks)
	_cooldown.set_state("Ability", max_cooldown - ticks, max_cooldown, "ready" if ticks <= 0 else "%.1f s to ready" % (ticks / 60.0), COOLDOWN_COLOR)
	_hint.text = ("The King starts rested." if index == 0 else "Carried over: health, stamina and ability cooldown do not recover between duels.")
	_hud_context = null

func _on_sequence_finished(summary: Dictionary) -> void:
	last_summary = summary.duplicate(true)
	last_roles = _roles.duplicate()
	if is_instance_valid(banner):
		banner.visible = false
	var text = sequence_text(summary)
	if main != null and is_instance_valid(main):
		main._message(text)
		Kit.toast(main, text, "info" if summary.get("outcome", "") == "king_survived" else "warning")

static func sequence_text(summary: Dictionary) -> String:
	var duels: Array = summary.get("duels", [])
	match str(summary.get("outcome", "")):
		"king_survived":
			return "The King survived its last stand: %d duel%s won, the checking pieces are removed." % [duels.size(), "" if duels.size() == 1 else "s"]
		"king_fell":
			return "The King fell in duel %d: it is checkmate." % duels.size()
		"abandoned":
			return "The King's last stand was abandoned."
	return "The King's last stand could not be fought: checkmate stands."

## Result-screen paragraph for a match that ended through a last stand ("" otherwise).
func result_note() -> String:
	if last_summary.is_empty() or main == null or last_summary.get("outcome", "") not in ["king_fell", "unplayable"]:
		return ""
	if flow == null or flow.game.engine.result.is_empty():
		return ""
	var duels: Array = last_summary.get("duels", [])
	if last_summary.outcome == "unplayable":
		return "King's last stand: the duel could not be fought, so the checkmate stands."
	var fell = duels.size()
	var role = str(last_roles[fell - 1]) if fell - 1 < last_roles.size() and fell > 0 else ""
	var total = last_roles.size()
	var piece = ROLE_NAMES.get(role, "checking piece")
	var won = fell - 1
	var tail = "" if won <= 0 else " It had won %d duel%s before." % [won, "" if won == 1 else "s"]
	return "King's last stand: the mated King fought the checking pieces and fell in duel %d of %d against the %s, so the checkmate stands.%s" % [fell, maxi(total, fell), piece, tail]

func _process(_delta: float) -> void:
	# Attach the context line to the combat HUD of the duel that is being fought (the HUD is rebuilt for every duel).
	if flow == null or not is_instance_valid(adapter) or flow.phase not in ["countdown", "combat", "aftermath"]:
		return
	var arena = adapter.get("arena")
	if arena == null or not is_instance_valid(arena):
		return
	var hud = arena.get("hud")
	if hud == null or not is_instance_valid(hud) or hud == _hud_context or not hud.has_method("set_context"):
		return
	var progress: Dictionary = flow.game.royal_progress() if flow.game.has_method("royal_progress") else {}
	if progress.is_empty():
		return
	_hud_context = hud
	hud.call("set_context", hud_context(int(progress.duelIndex), int(progress.duelCount)))
