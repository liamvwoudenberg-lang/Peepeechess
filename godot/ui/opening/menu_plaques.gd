extends Node3D
## Physical menu plaques stay in the castle camera while ordinary Buttons provide accessible input/text.
## Project each button's current rectangle into the camera plane so scaling and phone safe areas remain correct.
const Prefs = preload("res://ui/theme/ui_prefs.gd")
const Tokens = preload("res://ui/theme/ui_tokens.gd")
const DEPTH := 4.0
var camera: Camera3D
var entries: Array[Dictionary] = []

func setup(view: Camera3D, buttons: Dictionary) -> void:
	name = "MenuPlaques"
	camera = view
	var previous := camera.get_node_or_null("MenuPlaques")
	if previous != null:
		camera.remove_child(previous)
		previous.queue_free()
	camera.add_child(self)
	for key in buttons:
		var button: Button = buttons[key]
		var plaque := Node3D.new()
		plaque.name = str(key).capitalize() + "Plaque"
		add_child(plaque)
		var rim := _material(Color("b59754"))
		var face := _material(Color("172632"))
		var edge := _box(plaque, rim, "GiltFrame")
		var inset := _box(plaque, face, "StoneFace")
		var item := {"button": button, "root": plaque, "rim": rim, "face": face, "edge": edge, "inset": inset, "highlight": 0.0, "target": 0.0}
		entries.append(item)
		button.mouse_entered.connect(_set_hover.bind(item, true))
		button.mouse_exited.connect(_set_hover.bind(item, false))
		button.focus_entered.connect(_set_hover.bind(item, true))
		button.focus_exited.connect(_set_hover.bind(item, false))
		# Focus outline is preserved; only the flat 2D backgrounds are replaced by the modeled plaque.
		var transparent := StyleBoxFlat.new()
		transparent.bg_color = Color.TRANSPARENT
		transparent.content_margin_left = 18
		transparent.content_margin_right = 18
		transparent.content_margin_top = 11
		transparent.content_margin_bottom = 11
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
			button.add_theme_stylebox_override(state, transparent)
		# Primary buttons normally use dark ink on a gold 2D background. Here
		# the background is a dark physical plaque, so use light lettering.
		if button.theme_type_variation == "PrimaryButton":
			for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
				button.add_theme_color_override(state, Tokens.TEXT)
			for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
				button.add_theme_color_override(state, Tokens.TEXT)
	_sync()

func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.roughness = 0.72
	return mat

func _box(parent: Node3D, material: Material, node_name: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = BoxMesh.new()
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

func _set_hover(item: Dictionary, value: bool) -> void:
	var button: Button = item.button
	item.target = 1.0 if value or button.has_focus() or button.is_hovered() else 0.0
	if Prefs.reduce_motion:
		item.highlight = item.target
		_color(item)

func _process(delta: float) -> void:
	if not is_instance_valid(camera):
		queue_free()
		return
	for item in entries.duplicate():
		if not is_instance_valid(item.button):
			item.root.queue_free()
			entries.erase(item)
			continue
		item.highlight = lerpf(item.highlight, item.target, 1.0 if Prefs.reduce_motion else 1.0 - exp(-10.0 * minf(delta, 0.1)))
		_color(item)
	if entries.is_empty():
		queue_free()
		return
	_sync()

func _color(item: Dictionary) -> void:
	var k: float = item.highlight
	var alpha := _effective_alpha(item.button)
	var rim_color := Color("b59754").lerp(Color("fff0a6"), k)
	var face_color := Color("172632").lerp(Color("34516a"), k)
	rim_color.a = alpha
	face_color.a = alpha
	item.rim.albedo_color = rim_color
	item.face.albedo_color = face_color

func _effective_alpha(control: Control) -> float:
	var alpha := 1.0
	var node: Node = control
	while node is CanvasItem:
		alpha *= (node as CanvasItem).modulate.a
		node = node.get_parent()
	return alpha

func _sync() -> void:
	if not is_instance_valid(camera) or not camera.is_inside_tree():
		return
	for item in entries:
		if not is_instance_valid(item.button):
			item.root.visible = false
			continue
		var button: Button = item.button
		item.root.visible = button.is_visible_in_tree() and button.size.x > 1.0 and button.size.y > 1.0
		if not item.root.visible:
			continue
		var rect := button.get_global_rect()
		var center := camera.to_local(camera.project_position(rect.get_center(), DEPTH))
		var left := camera.to_local(camera.project_position(rect.position, DEPTH))
		var right := camera.to_local(camera.project_position(rect.end, DEPTH))
		var width := absf(right.x - left.x)
		var height := absf(right.y - left.y)
		item.root.position = center
		item.edge.scale = Vector3(width, height, 0.08)
		item.inset.scale = Vector3(maxf(0.001, width - 0.035), maxf(0.001, height - 0.035), 0.025)
		item.inset.position.z = 0.052
