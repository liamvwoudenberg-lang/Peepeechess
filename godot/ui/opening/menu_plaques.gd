extends Node3D
## Physical menu plaques stay in the castle camera while ordinary Buttons provide accessible input/text.
## Project each button's current rectangle into the camera plane so scaling and phone safe areas remain correct.
const Prefs = preload("res://ui/theme/ui_prefs.gd")
const Tokens = preload("res://ui/theme/ui_tokens.gd")
const DEPTH := 4.0
const FRAME_DEPTH := 4.7          ## page frames sit behind the action plaques
const LIFT := 0.2                 ## hover/focus: the plaque rises this far toward the camera
const TILT_Y := 0.11              ## radians of tilt toward the pointer on a hovered plaque
const TILT_X := 0.08
const ENTRY_TIME := 0.38          ## plaques rise into place when a page opens, staggered by ENTRY_STAGGER
const ENTRY_STAGGER := 0.045
var camera: Camera3D
var entries: Array[Dictionary] = []
var _time := 0.0

## `buttons`: key -> Button. `node_name` lets several sets share one camera ("MenuPlaques" is the title menu, "ChromePlaques" the page chrome).
func setup(view: Camera3D, buttons: Dictionary, node_name: String = "MenuPlaques") -> void:
	name = node_name
	camera = view
	var previous := camera.get_node_or_null(node_name)
	if previous != null:
		camera.remove_child(previous)
		previous.queue_free()
	camera.add_child(self)
	var order := 0
	for key in buttons:
		var button: Button = buttons[key]
		var plaque := Node3D.new()
		plaque.name = str(key).capitalize() + "Plaque"
		add_child(plaque)
		var rim := _material(Color("b59754"))
		var face := _material(Color("172632"))
		var shadow := _material(Color(0, 0, 0))
		var glow := _material(Color("ffd978"))
		glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		var shade := _box(plaque, shadow, "DropShadow")
		var halo := _box(plaque, glow, "Glow")
		var edge := _box(plaque, rim, "GiltFrame")
		var inset := _box(plaque, face, "StoneFace")
		var item := {"button": button, "root": plaque, "rim": rim, "face": face, "edge": edge, "inset": inset, "shadow": shadow, "shade": shade,
			"glow": glow, "halo": halo, "highlight": 0.0, "target": 0.0, "entry": 0.0, "delay": float(order) * ENTRY_STAGGER, "tilt": Vector2.ZERO, "depth": DEPTH, "frame": false}
		order += 1
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

## A page frame: one large slab behind a page (not a button). `rect_fn` returns the global rect to cover, so a frame can hug
## the centred page column while the scroll area behind it is wider.
func add_frame(control: Control, rect_fn: Callable, grow: float = 14.0) -> void:
	var plaque := Node3D.new()
	plaque.name = "PageFrame"
	add_child(plaque)
	var rim := _material(Color("8a7440"))
	var face := _material(Color("0e1822"))
	var edge := _box(plaque, rim, "GiltFrame")
	var inset := _box(plaque, face, "StoneFace")
	var item := {"button": control, "root": plaque, "rim": rim, "face": face, "edge": edge, "inset": inset, "highlight": 0.0, "target": 0.0,
		"entry": 0.0, "delay": 0.0, "tilt": Vector2.ZERO, "depth": FRAME_DEPTH, "frame": true, "rect_fn": rect_fn, "grow": grow}
	entries.append(item)

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

## The current page's navigation entry stays lit so the player always sees where they are.
func _rest_level(item: Dictionary) -> float:
	var button: Control = item.button
	return 0.55 if is_instance_valid(button) and button.theme_type_variation == "NavButtonActive" else 0.0

func _set_hover(item: Dictionary, value: bool) -> void:
	var button: Button = item.button
	item.target = 1.0 if value or button.has_focus() or button.is_hovered() else _rest_level(item)
	if Prefs.reduce_motion:
		item.highlight = item.target
		_color(item)

func _process(delta: float) -> void:
	if not is_instance_valid(camera):
		queue_free()
		return
	_time += minf(delta, 0.1)
	for item in entries.duplicate():
		if not is_instance_valid(item.button):
			item.root.queue_free()
			entries.erase(item)
			continue
		if not item.frame:
			var button: Button = item.button
			var live := button.has_focus() or button.is_hovered()
			item.target = 1.0 if live else _rest_level(item)
		var k_step := 1.0 if Prefs.reduce_motion else 1.0 - exp(-10.0 * minf(delta, 0.1))
		item.highlight = lerpf(item.highlight, item.target, k_step)
		if Prefs.reduce_motion:
			item.entry = 1.0
		else:
			item.entry = minf(1.0, item.entry + delta / ENTRY_TIME) if _time >= item.delay else 0.0
		_tilt(item, k_step)
		_color(item)
	if entries.is_empty():
		queue_free()
		return
	_sync()

func _color(item: Dictionary) -> void:
	var k: float = item.highlight
	var alpha := _effective_alpha(item.button) * _ease(item.entry)
	if item.frame:
		item.rim.albedo_color = Color(0.54, 0.455, 0.25, 0.92 * alpha)
		item.face.albedo_color = Color(0.055, 0.094, 0.133, 0.84 * alpha)   # dark enough for light text, light enough to show the castle
		return
	var rim_color := Color("b59754").lerp(Color("fff0a6"), k)
	var face_color := Color("172632").lerp(Color("34516a"), k)
	rim_color.a = alpha
	face_color.a = alpha
	item.rim.albedo_color = rim_color
	item.face.albedo_color = face_color
	item.shadow.albedo_color = Color(0, 0, 0, 0.42 * alpha)
	item.glow.albedo_color = Color(1.0, 0.82, 0.42, 0.28 * k * alpha)

static func _ease(t: float) -> float:
	return 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 3.0)

## A hovered plaque turns slightly toward the pointer (parallax depth); a focused one just lifts.
func _tilt(item: Dictionary, step: float) -> void:
	var want := Vector2.ZERO
	var button: Control = item.button
	if not item.frame and not Prefs.reduce_motion and button.is_hovered() and button.size.x > 1.0 and button.size.y > 1.0:
		var local := button.get_local_mouse_position()
		want = Vector2((local.x / button.size.x - 0.5) * 2.0, (local.y / button.size.y - 0.5) * 2.0).clamp(Vector2(-1, -1), Vector2(1, 1))
	item.tilt = (item.tilt as Vector2).lerp(want, step)

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
		var control: Control = item.button
		item.root.visible = control.is_visible_in_tree() and control.size.x > 1.0 and control.size.y > 1.0
		if not item.root.visible:
			continue
		var rect := control.get_global_rect()
		if item.frame:
			rect = (item.rect_fn as Callable).call().grow(item.grow as float)
		var depth: float = item.depth
		var center := camera.to_local(camera.project_position(rect.get_center(), depth))
		var left := camera.to_local(camera.project_position(rect.position, depth))
		var right := camera.to_local(camera.project_position(rect.end, depth))
		var width := absf(right.x - left.x)
		var height := absf(right.y - left.y)
		var rise := (1.0 - _ease(item.entry)) * 0.35   # entry: slides up into place
		var lift: float = 0.0 if item.frame else item.highlight * LIFT
		item.root.position = center + Vector3(0.0, -rise, lift)
		item.root.rotation = Vector3(-(item.tilt as Vector2).y * TILT_X, -(item.tilt as Vector2).x * TILT_Y, 0.0)
		item.edge.scale = Vector3(width, height, 0.08 if item.frame else 0.16)
		item.inset.scale = Vector3(maxf(0.001, width - 0.035), maxf(0.001, height - 0.035), 0.025 if item.frame else 0.06)
		item.inset.position.z = 0.052 if item.frame else 0.1
		if not item.frame:
			var depth_cue: float = 0.03 + item.highlight * 0.04
			item.shade.scale = Vector3(width, height, 0.02)
			item.shade.position = Vector3(depth_cue, -depth_cue * 1.4, -0.1 - item.highlight * 0.05)
			item.halo.scale = Vector3(width * 1.08, height * 1.25, 0.01)
			item.halo.position.z = -0.09
