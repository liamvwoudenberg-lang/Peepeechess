class_name CombatDebug
extends Node3D
## Developer debug mode for the fighting arena. OFF by default and not part of any menu.
##   * available: the editor, `--combat-debug` on the command line, or PEEPEECHESS_COMBAT_DEBUG=1 in the environment.
##   * F3 toggles it while available (also `CombatDebug.set_enabled(true)` from tests/tools).
## Draws, per fighter: the simulation's hurt circle (cyan: what attacks test against), the visible body circle (green: what is drawn,
## from paladin_configs.json), the maximum reach arc (yellow, thin) and the live hit sector in RED only while the swing is in its
## ACTIVE frames. A text panel lists the combat state, state ticks, clip, stamina, hp, combo index and the last hit / swing ids.
static var enabled: bool = false

var arena: Node
var _mesh := ImmediateMesh.new()
var _lines: MeshInstance3D
var _label: Label
var _layer: CanvasLayer
var _material := StandardMaterial3D.new()


static func available() -> bool:
	return OS.has_feature("editor") or "--combat-debug" in OS.get_cmdline_args() or "--combat-debug" in OS.get_cmdline_user_args() \
			or OS.get_environment("PEEPEECHESS_COMBAT_DEBUG") == "1"


static func set_enabled(value: bool) -> void:
	enabled = value
	CharacterModel.show_hitbox = value   # the models' own hit-sector fx follows


## Adds the overlay to an arena (once). Cheap when disabled: nothing is drawn or evaluated.
static func attach(target: Node) -> CombatDebug:
	var existing := target.get_node_or_null("CombatDebug")
	if existing != null:
		return existing
	var node := CombatDebug.new()
	node.name = "CombatDebug"
	node.arena = target
	target.add_child(node)
	return node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.no_depth_test = true
	_material.render_priority = 100
	_lines = MeshInstance3D.new()
	_lines.mesh = _mesh
	_lines.material_override = _material
	_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_lines)
	_layer = CanvasLayer.new()
	_layer.layer = 90
	add_child(_layer)
	_label = Label.new()
	_label.position = Vector2(12, 96)
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 5)
	_layer.add_child(_label)
	_apply_visibility()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3 and available():
		set_enabled(not enabled)
		get_viewport().set_input_as_handled()


func _apply_visibility() -> void:
	_lines.visible = enabled
	_layer.visible = enabled


func _process(_delta: float) -> void:
	_apply_visibility()
	if not enabled or arena == null or not ("sim" in arena) or arena.sim == null:
		_mesh.clear_surfaces()
		return
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var text := ""
	for f in arena.sim.fighters:
		_draw_fighter(f)
		text += describe(f, _clip_of(f)) + "\n"
	_mesh.surface_end()
	_label.text = text


func _clip_of(f: FighterController) -> String:
	for model in arena.find_children("*", "CharacterModel", false, false):
		if (model as CharacterModel).fighter == f:
			return str((model as CharacterModel)._current)
	return "(placeholder)"


## One text block for a fighter (also used by tests).
static func describe(f: FighterController, clip: String) -> String:
	var sm := f.sm
	var state_name: String = CombatConstants.STATE_NAMES[sm.state] if sm.state >= 0 and sm.state < CombatConstants.STATE_NAMES.size() else str(sm.state)
	var attack_id: String = sm.attack.id if sm.attack != null else "-"
	return "%s %s | %s t=%d | clip %s | hp %d/%d | stam %.0f/%.0f | combo %d | attack %s%s | swing #%d%s" % [
			f.color.to_upper(), f.role.to_upper(), state_name, sm.state_ticks, clip, f.health.current, f.health.maximum,
			f.stamina.current, f.stamina.maximum, sm.combo_index, attack_id, " ACTIVE" if sm.attack_active() else "",
			f.hitbox.swing_serial, " (hit landed)" if f.hitbox.hit_anything else ""]


func _draw_fighter(f: FighterController) -> void:
	var p := f.global_position + Vector3(0, 0.05, 0)
	_circle(p, f.hurt_radius(), Color(0.2, 0.9, 1.0))                      # simulation hurt circle
	_circle(p, PaladinConfig.body_radius(f.role), Color(0.3, 1.0, 0.3))      # drawn body
	var reach := float(f.stats["reachM"])
	var shape := f.hitbox.shape(f)
	var arc := 120.0
	if shape.get("active", false):
		arc = float(shape["arc_degrees"])
		_sector(p, f.yaw, float(shape["reach"]), arc, Color(1.0, 0.15, 0.1))   # live hit sector: ACTIVE frames only
	_sector(p, f.yaw, reach, arc, Color(1.0, 0.9, 0.2, 0.55), false)          # maximum reach arc, thin


func _circle(center: Vector3, radius: float, color: Color) -> void:
	var segments := 40
	for i in segments:
		var a0 := TAU * float(i) / segments
		var a1 := TAU * float(i + 1) / segments
		_line(center + Vector3(sin(a0), 0, cos(a0)) * radius, center + Vector3(sin(a1), 0, cos(a1)) * radius, color)


func _sector(origin: Vector3, yaw: float, reach: float, arc_degrees: float, color: Color, edges: bool = true) -> void:
	var half := deg_to_rad(arc_degrees * 0.5)
	var steps := 14
	var prev := origin + Vector3(sin(yaw - half), 0, cos(yaw - half)) * reach
	if edges:
		_line(origin, prev, color)
	for i in range(1, steps + 1):
		var a := yaw - half + 2.0 * half * float(i) / steps
		var point := origin + Vector3(sin(a), 0, cos(a)) * reach
		_line(prev, point, color)
		prev = point
	if edges:
		_line(prev, origin, color)


func _line(a: Vector3, b: Vector3, color: Color) -> void:
	_mesh.surface_set_color(color)
	_mesh.surface_add_vertex(a)
	_mesh.surface_set_color(color)
	_mesh.surface_add_vertex(b)
