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
var animation_enabled = true:
	set(value):
		animation_enabled = value
		if world != null:
			world.set_animate(value)
## The persistent pit world hosting this board (godot/world/README.md).
var world: BattleWorld
var tiles: Array = []
## true = the "2D" view: straight-down narrow-FOV camera on this same board.
var top_down = false
## While a battle presentation runs, chess state changes are applied only after it (see PitSequence).
var sync_hold = false
const TILE_PHYSICS_LAYER = 128
var _flipped = false
var _view_initialized = false
var _sync_pending = false
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
var _leaving: Array = []   # captured pieces still on screen until the capturing piece has arrived
var _last_ply = 0

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
	# The chess board lives inside the persistent pit world (godot/world/): board on top, arena chamber
	# below, one camera. The board itself is built exactly as before, into world.board_root.
	world = BattleWorld.new()
	viewport_3d.add_child(world)
	scene = world.board_root
	camera = world.rig.camera
	world.rig.snap_to(CameraRig.State.CHESS_PERSPECTIVE)
	world.set_animate(animation_enabled)
	var plinth = Models.material(Color("263b42"), 0.3)
	var plinth_node = Models.box(scene, WorldConstants.PLINTH_SIZE, WorldConstants.PLINTH_CENTER, plinth)
	var frame_node = Models.box(scene, WorldConstants.FRAME_SIZE, WorldConstants.FRAME_CENTER, Models.material(Color("c39c5d"), 0.7))
	var light = Models.material(Color("b7b9a5"))
	var dark = Models.material(Color("496e70"))
	for at in range(64):
		var center = Interaction.world_position(at)
		var tile = Models.box(scene, Vector3(0.995, 0.08, 0.995), center, light if (at % 8 + at / 8) % 2 else dark)
		tiles.append(tile)
		var body = StaticBody3D.new()
		body.set_meta("square", at)
		body.collision_layer = TILE_PHYSICS_LAYER  # keeps tile pickers away from the arena's fighters
		body.collision_mask = 0
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
	BattleWorld.tag_board(scene)
	world.bind_board(self, tiles, [plinth_node, frame_node])
	interaction.selection_changed.connect(update_marks)
	game.changed.connect(sync_state)
	resized.connect(_update_camera)
	sync_state()
	_update_camera()
	BoardThemeView.attach_3d(self)  # board theme / piece set / shadows (boards/board_theme_view.gd)

func _exit_tree() -> void:
	for node in _leaving:
		if is_instance_valid(node):
			node.queue_free()
	# (the paladin template cache is released once, at engine exit, by PaladinModel.release_all)

func set_flipped(value: bool) -> void:
	_flipped = value
	yaw = PI if value else 0.0
	if world != null:
		world.rig.set_flipped(value)
	_update_camera()

func reset_camera() -> void:
	yaw = 0.0
	elevation = 0.88
	distance = 13.5
	_update_camera()

## Switches between the straight-down "2D" view and the orbiting perspective view (glides).
func set_top_down(value: bool) -> void:
	top_down = value
	if world == null:
		return
	world.rig.set_flipped(_flipped)
	_update_camera()
	var wanted = CameraRig.State.CHESS_TOP_DOWN if value else CameraRig.State.CHESS_PERSPECTIVE
	if not world.pit.is_idle():
		world.rig.chess_view = wanted  # restored when the battle presentation ends
	elif not _view_initialized or not is_visible_in_tree():
		world.rig.snap_to(wanted)
	elif world.rig.transition_target() != wanted:
		world.rig.go(wanted)
	_view_initialized = true

func _update_camera() -> void:
	if camera == null or world == null:
		return
	world.rig.set_aspect(size.x / maxf(1, size.y))
	world.rig.set_orbit(yaw, elevation, distance)

func set_sync_hold(value: bool) -> void:
	sync_hold = value
	if not value and _sync_pending:
		_sync_pending = false
		sync_state()

func sync_state() -> void:
	if scene == null:
		return
	if sync_hold:
		_sync_pending = true
		return
	for tween in _moves:
		if tween.is_valid():
			tween.kill()
	_moves.clear()
	for leaving in _leaving:
		if is_instance_valid(leaving):
			leaving.queue_free()
	_leaving.clear()
	for node in pieces.values():
		if node is PaladinPiece:
			node.stop_walk()
	var state = game.chess_state()
	var fresh_match = _last_match_id != game.match_id
	_last_match_id = game.match_id
	# Paladin pieces WALK only for one new ply forward; undo, a new game, FEN load, flip and reloads snap into place.
	var ply: int = game.engine.history.size()
	var forward_move: bool = ply == _last_ply + 1 and not fresh_match
	_last_ply = ply
	var walk_ok: bool = forward_move and animation_enabled and BoardTheme.anim_scale() > 0.0
	var longest := 0.0
	var swaps: Array = []
	var active: Array = []
	for p in state.pieces:
		var id: String = p.pieceId
		active.append(id)
		var old_position = Vector3.ZERO
		var replaced = false
		if pieces.has(id) and _piece_roles[id] != p.role:
			if walk_ok and pieces[id] is PaladinPiece:
				swaps.append(p)  # promotion: the pawn walks first, the new piece appears on arrival
			else:
				old_position = pieces[id].position
				scene.remove_child(pieces[id])
				pieces[id].queue_free()
				pieces.erase(id)
				replaced = true
		if not pieces.has(id):
			_spawn(id, p.role, p.color, old_position if replaced else Interaction.world_position(Rules.index(p.square)))
		var target = Interaction.world_position(Rules.index(p.square))
		var node = pieces[id]
		if node is PaladinPiece:
			if walk_ok and not node.position.is_equal_approx(target):
				longest = maxf(longest, node.walk_along(PaladinPiece.path_between(_piece_roles[id], node.position, target), BoardTheme.anim_seconds(1.0)))
			else:
				node.position = target
		elif animation_enabled and BoardTheme.anim_scale() > 0.0 and not fresh_match and not node.position.is_equal_approx(target):
			var tween = create_tween()
			tween.tween_property(node, "position", target, BoardTheme.anim_seconds(0.24)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			_moves.append(tween)
		else:
			node.position = target
	for id in pieces.keys():
		if id not in active:
			var gone: Node3D = pieces[id]
			pieces.erase(id)
			_piece_roles.erase(id)
			if longest > 0.0 and gone is PaladinPiece:
				# captured: it stays until the mover has arrived, then sinks away
				_leaving.append(gone)
				var fall = create_tween()
				fall.tween_interval(longest * 0.85)
				fall.tween_property(gone, "scale", Vector3(0.01, 0.01, 0.01), 0.3).set_ease(Tween.EASE_IN)
				fall.tween_callback(func():
					if is_instance_valid(gone):
						gone.queue_free()
					_leaving.erase(gone))
				_moves.append(fall)
			else:
				scene.remove_child(gone)
				gone.queue_free()
	for p in swaps:
		var swap = create_tween()
		swap.tween_interval(longest)
		swap.tween_callback(_swap_piece.bind(p))
		_moves.append(swap)
	update_marks()

func _spawn(id: String, role: String, color: String, at_position: Vector3) -> void:
	pieces[id] = Models.build(role, color)
	pieces[id].name = id
	_piece_roles[id] = role
	scene.add_child(pieces[id])
	BattleWorld.tag_board(pieces[id])
	pieces[id].position = at_position
	pieces[id].rotation.y = PI if color == "b" else 0.0

func _swap_piece(p: Dictionary) -> void:
	var id: String = p.pieceId
	if not pieces.has(id):
		return
	var at_position: Vector3 = pieces[id].position
	scene.remove_child(pieces[id])
	pieces[id].queue_free()
	pieces.erase(id)
	_spawn(id, p.role, p.color, at_position)
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
	Models.add(marks, disc, Interaction.world_position(at) + Vector3(0, 0.055, 0), mat).layers = WorldConstants.LAYER_BOARD

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
		BoardThemeView.destination_3d(self, m.to, not game.engine.board[m.to].is_empty() or m.flag == "ep")  # highlight style (board settings)
	if game.engine.in_check():
		var at = game.engine.board.find("K" if game.engine.turn == "w" else "k")
		_mark(at, Color(1, 0.2, 0.2, 0.85), 0.48)

func square_at(point: Vector2) -> int:
	if camera == null or viewport_3d.size.x < 1:
		return -1
	var scaled = point * Vector2(viewport_3d.size) / size
	var origin = camera.project_ray_origin(scaled)
	var end = origin + camera.project_ray_normal(scaled) * 400
	var query = PhysicsRayQueryParameters3D.create(origin, end)
	var hit = viewport_3d.find_world_3d().direct_space_state.intersect_ray(query)
	return hit.collider.get_meta("square", -1) if not hit.is_empty() else -1

func _presenting() -> bool:
	return world != null and not world.pit.is_idle()

func _gui_input(event: InputEvent) -> void:
	if _presenting():
		return
	# Touch has its own gesture path; avoid replaying its emulated mouse events.
	if (event is InputEventMouseButton or event is InputEventMouseMotion) and event.device == -1:
		return
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_orbiting = event.pressed
		elif event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			if top_down:
				accept_event()
				return
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
	if top_down:
		return
	yaw -= delta.x * 0.008
	elevation = clampf(elevation + delta.y * 0.006, 0.4, 1.42)
	_update_camera()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or camera == null or _presenting():
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
