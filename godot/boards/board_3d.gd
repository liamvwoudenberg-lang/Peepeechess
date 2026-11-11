class_name ChessBoard3D
extends SubViewportContainer
const Rules = preload("res://chess/chess_engine.gd")
const Interaction = preload("res://boards/board_interaction.gd")
const Models = preload("res://boards/piece_meshes.gd")
var game: ClassicMatch
var interaction: BoardInteraction
var viewport_3d: SubViewport
var scene: Node3D
var camera: Camera3D
var pieces: Dictionary = {}
var _piece_roles: Dictionary = {}
var marks: Node3D
var yaw = 0.0
var elevation = 0.88
var distance = 13.5
var animation_enabled = true
var _orbiting = false
var _press = Vector2.ZERO
var _pointer = Vector2.ZERO
var _mouse_down = false
var _drag_piece = -1
var _dragging = false
var _touches: Dictionary = {}
var _touch_distance = 0.0
var _touch_moved = false
var _last_match_id = ""
var _moves: Array[Tween] = []

func setup(match_game: ClassicMatch, controls: BoardInteraction) -> void:
	game = match_game
	interaction = controls
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "Click pieces to move · right-drag to orbit · wheel to zoom\nTouch: tap to move, swipe to orbit, pinch to zoom"
	viewport_3d = SubViewport.new()
	viewport_3d.own_world_3d = true
	viewport_3d.size = Vector2i(800, 600)
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport_3d)
	scene = Node3D.new()
	viewport_3d.add_child(scene)
	var environment_node = WorldEnvironment.new()
	var environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("14272e")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b5d0d1")
	environment.ambient_light_energy = 0.22
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	scene.add_child(environment_node)
	var key = DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-55, -25, 0)
	key.light_color = Color("fff0d5")
	key.light_energy = 0.55
	key.shadow_enabled = true
	scene.add_child(key)
	var fill = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30, 145, 0)
	fill.light_color = Color("a2c5df")
	fill.light_energy = 0.18
	scene.add_child(fill)
	camera = Camera3D.new()
	camera.fov = 45
	camera.near = 0.1
	camera.far = 100
	camera.current = true
	scene.add_child(camera)
	var plinth = Models.material(Color("263b42"), 0.3)
	Models.box(scene, Vector3(8.65, 0.38, 8.65), Vector3(0, -0.26, 0), plinth)
	Models.box(scene, Vector3(8.8, 0.06, 8.8), Vector3(0, -0.07, 0), Models.material(Color("c39c5d"), 0.7))
	var light = Models.material(Color("b7b9a5"))
	var dark = Models.material(Color("496e70"))
	for at in range(64):
		var center = Interaction.world_position(at)
		var tile = Models.box(scene, Vector3(0.995, 0.08, 0.995), center, light if (at % 8 + at / 8) % 2 else dark)
		var body = StaticBody3D.new()
		body.set_meta("square", at)
		var collider = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size = Vector3(0.995, 0.08, 0.995)
		collider.shape = shape
		body.add_child(collider)
		tile.add_child(body)
	for i in range(8):
		for edge in [-1, 1]:
			var label = Label3D.new()
			label.text = Rules.FILES[i]
			label.font_size = 32
			label.pixel_size = 0.009
			label.position = Vector3(i - 3.5, 0.02, edge * 4.2)
			label.rotation_degrees.x = -90
			label.modulate = Color("f1d69e")
			scene.add_child(label)
			var rank_label = Label3D.new()
			rank_label.text = str(8 - i)
			rank_label.font_size = 32
			rank_label.pixel_size = 0.009
			rank_label.position = Vector3(edge * 4.2, 0.02, i - 3.5)
			rank_label.rotation_degrees.x = -90
			rank_label.modulate = Color("f1d69e")
			scene.add_child(rank_label)
	marks = Node3D.new()
	scene.add_child(marks)
	interaction.selection_changed.connect(update_marks)
	game.changed.connect(sync_state)
	resized.connect(_update_camera)
	sync_state()
	_update_camera()

func set_flipped(value: bool) -> void:
	yaw = PI if value else 0.0
	_update_camera()

func reset_camera() -> void:
	yaw = 0.0
	elevation = 0.88
	distance = 13.5
	_update_camera()

func _update_camera() -> void:
	if camera == null:
		return
	# Add distance for portrait view so all board corners remain in frame.
	var aspect = size.x / maxf(1, size.y)
	var adjusted = distance * maxf(1, 1.0 / maxf(0.45, aspect))
	camera.position = Vector3(sin(yaw) * cos(elevation), sin(elevation), cos(yaw) * cos(elevation)) * adjusted
	camera.look_at(Vector3(0, 0.15, 0))

func sync_state() -> void:
	if scene == null:
		return
	for tween in _moves:
		if tween.is_valid():
			tween.kill()
	_moves.clear()
	var state = game.chess_state()
	var fresh_match = _last_match_id != game.match_id
	_last_match_id = game.match_id
	var active: Array = []
	for p in state.pieces:
		var id: String = p.pieceId
		active.append(id)
		var old_position = Vector3.ZERO
		var replaced = false
		if pieces.has(id) and _piece_roles[id] != p.role:
			old_position = pieces[id].position
			scene.remove_child(pieces[id])
			pieces[id].queue_free()
			pieces.erase(id)
			replaced = true
		if not pieces.has(id):
			pieces[id] = Models.build(p.role, p.color)
			pieces[id].name = id
			_piece_roles[id] = p.role
			scene.add_child(pieces[id])
			pieces[id].position = old_position if replaced else Interaction.world_position(Rules.index(p.square))
			pieces[id].rotation.y = PI if p.color == "b" else 0.0
		var target = Interaction.world_position(Rules.index(p.square))
		if animation_enabled and not fresh_match and not pieces[id].position.is_equal_approx(target):
			var tween = create_tween()
			tween.tween_property(pieces[id], "position", target, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			_moves.append(tween)
		else:
			pieces[id].position = target
	for id in pieces.keys():
		if id not in active:
			scene.remove_child(pieces[id])
			pieces[id].queue_free()
			pieces.erase(id)
			_piece_roles.erase(id)
	update_marks()

func _mark(at: int, color: Color, radius: float) -> void:
	var mat = Models.material(color)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var disc = CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.012
	disc.radial_segments = 32
	Models.add(marks, disc, Interaction.world_position(at) + Vector3(0, 0.055, 0), mat)

func update_marks() -> void:
	if marks == null:
		return
	for child in marks.get_children():
		marks.remove_child(child)
		child.queue_free()
	if not game.engine.history.is_empty():
		var h: Dictionary = game.engine.history[-1]
		_mark(Rules.index(h.from), Color(0.95, 0.76, 0.3, 0.55), 0.46)
		_mark(Rules.index(h.to), Color(0.95, 0.76, 0.3, 0.55), 0.46)
	if interaction.selected >= 0:
		_mark(interaction.selected, Color(1, 0.83, 0.4, 0.85), 0.47)
	for m in interaction.destinations:
		_mark(m.to, Color(0.3, 0.9, 0.75, 0.85), 0.17 if game.engine.board[m.to].is_empty() else 0.44)
	if game.engine.in_check():
		var at = game.engine.board.find("K" if game.engine.turn == "w" else "k")
		_mark(at, Color(1, 0.2, 0.2, 0.85), 0.48)

func square_at(point: Vector2) -> int:
	if camera == null or viewport_3d.size.x < 1:
		return -1
	var scaled = point * Vector2(viewport_3d.size) / size
	var origin = camera.project_ray_origin(scaled)
	var end = origin + camera.project_ray_normal(scaled) * 100
	var query = PhysicsRayQueryParameters3D.create(origin, end)
	var hit = viewport_3d.find_world_3d().direct_space_state.intersect_ray(query)
	return hit.collider.get_meta("square", -1) if not hit.is_empty() else -1

func _gui_input(event: InputEvent) -> void:
	# Touch has its own gesture path; avoid replaying its emulated mouse events.
	if (event is InputEventMouseButton or event is InputEventMouseMotion) and event.device == -1:
		return
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_orbiting = event.pressed
		elif event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			distance = clampf(distance + (-0.7 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.7), 9, 23)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_mouse_down = true
				_press = event.position
				_drag_piece = square_at(event.position)
				_dragging = false
			else:
				if _mouse_down:
					var at = square_at(event.position)
					if not _dragging or at != _drag_piece:
						interaction.click(at)
				_mouse_down = false
				_dragging = false
		accept_event()
	elif event is InputEventMouseMotion:
		if _orbiting:
			_orbit(event.relative)
		elif _mouse_down and _drag_piece >= 0 and event.position.distance_to(_press) > 8 and Rules.side(game.engine.board[_drag_piece]) == game.engine.turn:
			if not _dragging:
				interaction.select(_drag_piece)
			_dragging = true
		accept_event()

func _orbit(delta: Vector2) -> void:
	yaw -= delta.x * 0.008
	elevation = clampf(elevation + delta.y * 0.006, 0.4, 1.42)
	_update_camera()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or camera == null:
		return
	if event is InputEventScreenTouch:
		if event.pressed and get_global_rect().has_point(event.position):
			_touches[event.index] = event.position
			if _touches.size() == 1:
				_press = event.position
				_touch_moved = false
			else:
				_touch_moved = true
				var values = _touches.values()
				_touch_distance = values[0].distance_to(values[1])
			get_viewport().set_input_as_handled()
		elif not event.pressed and _touches.has(event.index):
			if _touches.size() == 1 and not _touch_moved:
				interaction.click(square_at(event.position - global_position))
			_touches.erase(event.index)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and _touches.has(event.index):
		_touches[event.index] = event.position
		if _touches.size() >= 2:
			var values = _touches.values()
			var next = values[0].distance_to(values[1])
			if _touch_distance > 0:
				distance = clampf(distance * _touch_distance / maxf(1, next), 9, 23)
			_touch_distance = next
			_update_camera()
		elif event.position.distance_to(_press) > 10:
			_touch_moved = true
			_orbit(event.relative)
		get_viewport().set_input_as_handled()
