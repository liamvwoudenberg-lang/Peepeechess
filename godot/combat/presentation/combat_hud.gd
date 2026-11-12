class_name CombatHud
extends CanvasLayer
## Read-only heads-up display: HP / stamina / ability bars, countdown, timer, floating combat
## messages, result banner and a controls cheat-sheet. It observes the simulation and the
## cosmetic event stream; it cannot change combat.

signal rematch_requested
signal menu_requested

var sim: CombatSimulation
var _fonts_color := Color(0.95, 0.92, 0.85)
var _panels: Array[Control] = []
var _timer_label: Label
var _center_label: Label
var _message_box: VBoxContainer
var _result_panel: PanelContainer
var _result_label: Label
var _help_label: Label
var _names: Dictionary = {}
var _messages: Array = []


func setup(p_sim: CombatSimulation, human_hint: String) -> void:
	sim = p_sim
	layer = 10
	for i in 2:
		var panel := _BarPanel.new()
		panel.hud = self
		panel.side = i
		panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		panel.offset_bottom = 120.0
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(panel)
		_panels.append(panel)

	_timer_label = _label(34, Control.PRESET_CENTER_TOP)
	_timer_label.position.y = 10
	_center_label = _label(72, Control.PRESET_CENTER)
	_message_box = VBoxContainer.new()
	_message_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_message_box.position = Vector2(-120, 110)
	_message_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_message_box)

	_help_label = _label(15, Control.PRESET_BOTTOM_LEFT)
	_help_label.text = human_hint
	_help_label.position = Vector2(14, -92)
	_help_label.modulate = Color(1, 1, 1, 0.75)

	_result_panel = PanelContainer.new()
	_result_panel.visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_result_panel.add_child(box)
	_result_label = Label.new()
	_result_label.add_theme_font_size_override("font_size", 30)
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_result_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	box.add_child(row)
	var again := Button.new()
	again.text = "Rematch  [Enter / F5]"
	again.pressed.connect(func(): rematch_requested.emit())
	row.add_child(again)
	var menu := Button.new()
	menu.text = "Menu  [Esc]"
	menu.pressed.connect(func(): menu_requested.emit())
	row.add_child(menu)
	add_child(_result_panel)
	_result_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_result_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_result_panel.grow_vertical = Control.GROW_DIRECTION_BOTH


func _label(size: int, preset: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", _fonts_color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 6)
	l.set_anchors_preset(preset)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func set_names(names: Dictionary) -> void:
	_names = names


# --- BEGIN king's-last-stand edit -------------------------------------------------------------------
## Optional context line under the timer (battle-royal-v1: "LAST STAND / DUEL 2/3"). Presentation only; "" removes it.
## The King's carried HP needs no extra widget: its bar starts at the carried fraction and reads "hp / max".
var _context_label: Label

func set_context(text: String) -> void:
	if text.is_empty():
		if _context_label != null:
			_context_label.queue_free()
			_context_label = null
		return
	if _context_label == null:
		_context_label = _label(18, Control.PRESET_CENTER_TOP)
		_context_label.name = "ContextLabel"
		_context_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_context_label.position.y = 124  # under the two bar panels (they end at y = 120)
		_context_label.add_theme_color_override("font_color", Color(0.95, 0.78, 0.38))
	_context_label.text = text

func context_text() -> String:
	return _context_label.text if _context_label != null else ""
# --- END king's-last-stand edit ---------------------------------------------------------------------


func post(text: String, color: Color = Color(1, 1, 1)) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_message_box.add_child(l)
	_messages.append({"label": l, "age": 0.0})
	while _messages.size() > 5:
		var old = _messages.pop_front()
		old["label"].queue_free()


func on_event(event: Dictionary) -> void:
	var actor: String = _names.get(event["actorPlayerId"], "?")
	var target: String = _names.get(event["targetPlayerId"], "?")
	match String(event["type"]):
		"parry":
			post("%s PERFECT PARRY on %s!" % [target, actor], Color(1.0, 0.85, 0.3))
		"guardbreak":
			post("%s GUARD BREAK on %s!" % [actor, target], Color(1.0, 0.35, 0.25))
		"block":
			post("%s blocked %s" % [target, actor], Color(0.6, 0.8, 1.0))
		"dodge":
			post("%s dodged %s" % [target, actor], Color(0.7, 1.0, 0.7))
		"ability":
			post("%s uses %s" % [actor, _ability_name(event["actorPlayerId"])], Color(1.0, 0.6, 0.9))
		"hit":
			if int(event["damage"]) >= 20:
				post("%s hit for %d" % [actor, int(event["damage"])], Color(1.0, 0.6, 0.4))


func _ability_name(player_id: String) -> String:
	var f := sim.fighter_by_id(player_id)
	return FighterRoster.ability_name(f.role) if f != null else "Ability"


func show_result(text: String) -> void:
	_result_label.text = text
	_result_panel.visible = true


func hide_result() -> void:
	_result_panel.visible = false


func _process(delta: float) -> void:
	for entry in _messages.duplicate():
		entry["age"] += delta
		var age: float = entry["age"]
		entry["label"].modulate.a = clampf(2.6 - age, 0.0, 1.0)
		if age > 2.6:
			entry["label"].queue_free()
			_messages.erase(entry)
	if sim == null or sim.request.is_empty():
		return
	if sim.phase == CombatSimulation.Phase.COUNTDOWN:
		var seconds := ceili(float(sim.countdown_remaining) / 60.0)
		_center_label.text = str(seconds) if seconds > 0 else "FIGHT"
		_timer_label.text = "90"
	else:
		var remaining := ceili(float(sim.duration_remaining) / 60.0)
		_timer_label.text = str(remaining)
		_center_label.text = "FIGHT" if sim.duration_remaining > CombatConstants.DURATION_TICKS - 50 else ""
	for p in _panels:
		p.step(delta)
		p.queue_redraw()


## One fighter's bars, drawn with Control._draw so no theme/art is required.
class _BarPanel extends Control:
	var hud: CombatHud
	var side: int = 0
	## Health "ghost" (the chunk just lost, drains after a short delay) and a white flash when health drops.
	var ghost: float = 1.0
	var _ghost_delay: float = 0.0
	var _flash: float = 0.0
	var _last_hp: int = -1
	var _time: float = 0.0

	func step(delta: float) -> void:
		_time += delta
		var sim: CombatSimulation = hud.sim
		if sim == null or sim.fighters.size() < 2 or sim.fighters[side] == null:
			return
		var f: FighterController = sim.fighters[side]
		var hp: int = f.health.current
		var ratio: float = f.health.ratio()
		if _last_hp < 0 or hp > _last_hp:
			ghost = ratio  # first frame / rematch / healing: no ghost
		elif hp < _last_hp:
			_ghost_delay = 0.45
			_flash = 1.0
		_last_hp = hp
		_flash = maxf(0.0, _flash - delta * 5.0)
		if _ghost_delay > 0.0:
			_ghost_delay -= delta
		elif ghost > ratio:
			ghost = maxf(ratio, ghost - delta * 0.55)

	func _draw() -> void:
		var sim: CombatSimulation = hud.sim
		if sim == null or sim.fighters.size() < 2 or sim.fighters[side] == null:
			return
		var f: FighterController = sim.fighters[side]
		var w := 360.0
		var x := 24.0 if side == 0 else size.x - w - 24.0
		var font := ThemeDB.fallback_font
		var title := "%s  (%s)" % [FighterRoster.display_name(f.role), "White" if f.color == "w" else "Black"]
		var tag: String = hud._names.get(f.player_id, "")
		draw_string(font, Vector2(x, 24), title + ("   " + tag if tag != "" else ""), HORIZONTAL_ALIGNMENT_LEFT, w, 20, Color(1, 1, 1))
		_hp_bar(Vector2(x, 34), Vector2(w, 20), f, font)
		var pulse := 0.5 + 0.5 * sin(_time * 10.0)
		var stam_color := Color(0.95, 0.75, 0.2) if not f.stamina.exhausted else Color(0.55, 0.3 + 0.1 * pulse, 0.1)
		_bar(Vector2(x, 60), Vector2(w * 0.8, 12), f.stamina.ratio(), stam_color, "", font)
		if f.stamina.exhausted:
			draw_string(font, Vector2(x + 6, 70), "EXHAUSTED", HORIZONTAL_ALIGNMENT_LEFT, w * 0.8, 11, Color(1, 0.8, 0.6, 0.6 + 0.4 * pulse))
		if f.sm.parry_window_open():
			draw_string(font, Vector2(x + w - 70, 24), "PARRY", HORIZONTAL_ALIGNMENT_RIGHT, 70, 18, Color(1.0, 0.85, 0.3))
		var cd := f.ability.cooldown_remaining
		var total := maxi(1, f.ability.cooldown_total)
		var ready := cd == 0
		var label := "READY" if ready else "%.1fs" % (float(cd) / 60.0)
		if f.ability.buff_active():
			label = "ACTIVE"
		var ability_name := FighterRoster.ability_name(f.role)
		_bar(Vector2(x, 80), Vector2(w * 0.8, 12), 1.0 - float(cd) / float(total), Color(0.5, 0.35, 0.9) if not ready else Color(0.35, 0.85, 0.5), "", font)
		draw_string(font, Vector2(x, 106), "%s: %s" % [ability_name, label], HORIZONTAL_ALIGNMENT_LEFT, w, 14, Color(0.9, 0.9, 0.9))
		if f.sm.last_denied != "" and f.local_tick - f.sm.last_denied_tick < 45:
			draw_string(font, Vector2(x + w * 0.82, 72), "no %s" % f.sm.last_denied, HORIZONTAL_ALIGNMENT_LEFT, 120, 14, Color(1, 0.5, 0.4))

	func _hp_bar(pos: Vector2, dim: Vector2, f: FighterController, font: Font) -> void:
		var ratio := clampf(f.health.ratio(), 0.0, 1.0)
		draw_rect(Rect2(pos, dim), Color(0, 0, 0, 0.6))
		if ghost > ratio:
			draw_rect(Rect2(pos + Vector2(dim.x * ratio, 0), Vector2(dim.x * (clampf(ghost, 0.0, 1.0) - ratio), dim.y)), Color(0.95, 0.85, 0.7, 0.85))
		draw_rect(Rect2(pos, Vector2(dim.x * ratio, dim.y)), Color(0.8, 0.14, 0.14).lerp(Color(1, 1, 1), _flash * 0.7))
		draw_rect(Rect2(pos, dim), Color(1, 1, 1, 0.5), false, 1.5)
		draw_string(font, pos + Vector2(8, dim.y - 5), "%d / %d" % [f.health.current, f.health.maximum], HORIZONTAL_ALIGNMENT_LEFT, dim.x, 14, Color(1, 1, 1))

	func _bar(pos: Vector2, dim: Vector2, ratio: float, color: Color, text: String, font: Font) -> void:
		draw_rect(Rect2(pos, dim), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(pos, Vector2(dim.x * clampf(ratio, 0.0, 1.0), dim.y)), color)
		draw_rect(Rect2(pos, dim), Color(1, 1, 1, 0.5), false, 1.5)
		if text != "":
			draw_string(font, pos + Vector2(8, dim.y - 5), text, HORIZONTAL_ALIGNMENT_LEFT, dim.x, 14, Color(1, 1, 1))
