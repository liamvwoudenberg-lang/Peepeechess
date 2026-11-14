class_name CourtyardCombatHud
extends CombatHud
## Compact observer used by the courtyard host. The existing simulation, event channel and
## F1 control overlay remain in charge; this layer only draws their current values.

const Icons = preload("res://ui/theme/ui_icons.gd")
const DAMAGE_SECONDS := 0.85
const MAX_DAMAGE_LABELS := 8
const ICONS := ["sword", "sword", "shield", "crown"]
const ACTION_NAMES := ["Light", "Heavy", "Guard", "Special"]
var view_camera: Camera3D
## Optional mapping when a host supplies a separate presentation transform.
var fighter_position: Callable
## A split-screen host may project into its first player viewport rather than the hidden world camera.
var damage_projection: Callable
var local_player_id := ""
var _surface: Control
var _damage: Array[Dictionary] = []
var _last_event_id := 0
var _result_age := -1.0
var _icon_textures: Array[Texture2D] = []


func setup(p_sim: CombatSimulation, _human_hint: String) -> void:
	sim = p_sim
	layer = 10
	_surface = _Surface.new()
	_surface.hud = self
	_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_surface)
	for kind in ICONS:
		_icon_textures.append(Icons.texture(kind, 32))
	_timer_label = _label(24, Control.PRESET_TOP_LEFT)
	_center_label = _label(42, Control.PRESET_TOP_LEFT)
	_center_label.visible = false
	_result_label = _label(18, Control.PRESET_TOP_LEFT)
	_result_label.visible = false
	_layout()


func set_context(text: String) -> void:
	if _context_label == null:
		_context_label = _label(12, Control.PRESET_TOP_LEFT)
	_context_label.text = text
	_context_label.visible = not text.is_empty()
	_layout()


func show_result(text: String) -> void:
	_result_age = 0.0
	_result_label.text = text.get_slice("\n", 0)
	_result_label.visible = true


func hide_result() -> void:
	_result_age = -1.0
	if _result_label != null:
		_result_label.visible = false


## Event IDs are monotonic within one duel. Duplicate snapshots cannot duplicate damage.
func on_event(event: Dictionary) -> void:
	var id := int(event.get("eventId", 0))
	if id <= _last_event_id:
		return
	_last_event_id = id
	if event.get("type", "") != "hit" or int(event.get("damage", 0)) <= 0:
		return
	var target_id := String(event.get("targetPlayerId", ""))
	if sim == null or sim.fighter_by_id(target_id) == null:
		return
	var label := _label(24, Control.PRESET_TOP_LEFT)
	label.text = str(int(event.damage))
	label.add_theme_color_override("font_color", Color("ffd59a"))
	label.visible = false  # no screen-centre fallback while the camera is unavailable
	_damage.append({"label": label, "target": target_id, "age": 0.0, "offset": (_last_event_id % 3 - 1) * 14.0})
	while _damage.size() > MAX_DAMAGE_LABELS:
		var oldest: Dictionary = _damage.pop_front()
		oldest.label.queue_free()


## Compatibility for callers that post cosmetic text. Text belongs beside a fighter, never
## in a persistent centre-screen message stack, so non-damage event prose is omitted here.
func post(_text: String, _color: Color = Color.WHITE) -> void:
	pass


func _layout() -> void:
	if _timer_label == null:
		return
	var extent := get_viewport().get_visible_rect().size
	_timer_label.position = Vector2(extent.x * 0.5 - 32, 12)
	_timer_label.size = Vector2(64, 34)
	_center_label.position = Vector2(extent.x * 0.5 - 50, 92)
	_center_label.size = Vector2(100, 54)
	_result_label.position = Vector2(14, 87)
	_result_label.size = Vector2(maxf(1, extent.x - 28), 30)
	_result_label.clip_text = true
	if _context_label != null:
		_context_label.position = Vector2(14, 68)
		_context_label.size = Vector2(maxf(1, extent.x - 28), 18)
		_context_label.clip_text = true


func _process(delta: float) -> void:
	if sim == null or sim.request.is_empty() or _surface == null:
		return
	_layout()
	_timer_label.text = str(ceili(float(sim.duration_remaining) / 60.0))
	var countdown := sim.phase == CombatSimulation.Phase.COUNTDOWN
	_center_label.visible = countdown
	_center_label.text = str(ceili(float(sim.countdown_remaining) / 60.0)) if countdown else ""
	if _result_age >= 0.0:
		_result_age += delta
		_result_label.modulate.a = clampf((1.4 - _result_age) * 3.0, 0.0, 1.0)
		if _result_age >= 1.4:
			hide_result()
	_update_damage(delta)
	_surface.queue_redraw()


func _update_damage(delta: float) -> void:
	var camera := view_camera if is_instance_valid(view_camera) else get_viewport().get_camera_3d()
	for index in range(_damage.size() - 1, -1, -1):
		var entry: Dictionary = _damage[index]
		entry.age += delta
		if entry.age >= DAMAGE_SECONDS:
			entry.label.queue_free()
			_damage.remove_at(index)
			continue
		var f := sim.fighter_by_id(entry.target)
		if f != null and damage_projection.is_valid():
			var projected: Dictionary = damage_projection.call(f)
			entry.label.visible = bool(projected.get("visible", false))
			if entry.label.visible:
				entry.label.position = Vector2(projected.position) + Vector2(entry.offset - 16, -12 - float(entry.age) * 52)
				entry.label.modulate.a = clampf((DAMAGE_SECONDS - float(entry.age)) * 3.5, 0.0, 1.0)
			continue
		if f == null or camera == null:
			entry.label.visible = false
			continue
		var point: Vector3 = fighter_position.call(f) if fighter_position.is_valid() else f.global_position
		point += Vector3.UP * 1.7
		entry.label.visible = not camera.is_position_behind(point)
		if entry.label.visible:
			var projected := camera.unproject_position(point)
			entry.label.position = projected + Vector2(entry.offset - 16, -12 - float(entry.age) * 52)
			entry.label.modulate.a = clampf((DAMAGE_SECONDS - float(entry.age)) * 3.5, 0.0, 1.0)


func viewer() -> FighterController:
	if sim == null or sim.fighters.is_empty():
		return null
	var chosen := sim.fighter_by_id(local_player_id) if local_player_id != "" else null
	return chosen if chosen != null else sim.fighters[0]


class _Surface extends Control:
	var hud: CourtyardCombatHud
	const GOLD := Color("e5c17d")
	const BACK := Color(0.035, 0.045, 0.055, 0.87)
	var _style: StyleBoxFlat

	func _draw() -> void:
		if hud.sim == null or hud.sim.fighters.size() < 2:
			return
		var extent := get_viewport_rect().size
		var w := minf(290.0, (extent.x - 112.0) * 0.5)
		var own := hud.viewer()
		if own == null:
			return
		var enemy := hud.sim.opponent_of(own)
		_draw_fighter(own, Rect2(12, 12, w, 52), false)
		if enemy != null:
			_draw_fighter(enemy, Rect2(extent.x - w - 12, 12, w, 52), true)
		_draw_actions(own, extent)

	func _draw_fighter(f: FighterController, rect: Rect2, enemy: bool) -> void:
		var font := ThemeDB.fallback_font
		draw_style_box(_box(), rect)
		var x := rect.position.x + 9
		var w := rect.size.x - 18
		var title := "%s · %s" % [FighterRoster.display_name(f.role), "Black" if f.color == "b" else "White"]
		draw_string(font, Vector2(x, rect.position.y + 16), title, HORIZONTAL_ALIGNMENT_LEFT, w, 12, Color("f3e7d0"))
		var hp := Rect2(x, rect.position.y + 22, w, 12)
		_bar(hp, f.health.ratio(), Color("bd6254") if enemy else Color("72a78d"))
		draw_string(font, hp.position + Vector2(4, 10), "%d/%d" % [f.health.current, f.health.maximum], HORIZONTAL_ALIGNMENT_LEFT, w, 10, Color.WHITE)
		_bar(Rect2(x, rect.position.y + 39, w, 5), f.stamina.ratio(), GOLD if not f.stamina.exhausted else Color("986743"))

	func _draw_actions(f: FighterController, extent: Vector2) -> void:
		var cell := 44.0
		var gap := 8.0
		var start := Vector2((extent.x - cell * 4 - gap * 3) * 0.5, extent.y - 72)
		var font := ThemeDB.fallback_font
		for i in 4:
			var rect := Rect2(start + Vector2(i * (cell + gap), 0), Vector2(cell, cell))
			draw_style_box(_box(), rect)
			var ratio := 1.0
			if i == 3:
				ratio = 1.0 - float(f.ability.cooldown_remaining) / maxf(1, f.ability.cooldown_total)
			elif i < 2 and f.sm.attack != null:
				ratio = clampf(float(f.sm.state_ticks) / maxf(1, f.sm.attack_total), 0, 1)
			elif i == 2 and f.stamina.exhausted:
				ratio = 0.0
			var tint := GOLD if ratio >= 0.999 else Color("8b8a82")
			var icon_rect := Rect2(rect.position + Vector2(10, 7), Vector2(24, 24))
			if i == 1:
				icon_rect = Rect2(rect.position + Vector2(7, 4), Vector2(30, 30))
			draw_texture_rect(hud._icon_textures[i], icon_rect, false, tint)
			if ratio < 0.999:
				draw_rect(Rect2(rect.position + Vector2(2, cell * ratio), Vector2(cell - 4, (cell - 2) * (1 - ratio))), Color(0.0, 0.0, 0.0, 0.5))
			if i == 3 and f.ability.cooldown_remaining > 0:
				draw_string(font, rect.position + Vector2(1, 31), str(ceili(float(f.ability.cooldown_remaining) / 60.0)), HORIZONTAL_ALIGNMENT_CENTER, cell - 2, 13, Color.WHITE)
			draw_string(font, rect.position + Vector2(0, 57), ACTION_NAMES[i], HORIZONTAL_ALIGNMENT_CENTER, cell, 11, Color("e4d7bd"))

	func _bar(rect: Rect2, ratio: float, color: Color) -> void:
		draw_rect(rect, Color(0, 0, 0, 0.7))
		draw_rect(Rect2(rect.position, Vector2(rect.size.x * clampf(ratio, 0, 1), rect.size.y)), color)

	func _box() -> StyleBoxFlat:
		if _style == null:
			_style = StyleBoxFlat.new()
			_style.bg_color = BACK
			_style.border_color = Color(0.65, 0.5, 0.28, 0.75)
			_style.set_border_width_all(1)
			_style.set_corner_radius_all(5)
		return _style
