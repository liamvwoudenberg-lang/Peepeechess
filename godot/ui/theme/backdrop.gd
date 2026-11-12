extends Control
## Screen background: deep vertical gradient with edge vignette. In "home" mode it also animates a handful of
## drifting embers and four slowly rotating chess-piece silhouettes. In "scene" mode a 3D scene (the castle) shows behind
## the UI: nothing opaque is drawn, only a soft scrim (top and bottom bands plus a dim centre behind the menu). Cheap by design:
##   * CPU only, ~40 circles + 4 textured quads per frame, no shaders, no blur;
##   * state lives in preallocated Packed arrays updated in place (no per-frame allocations);
##   * redraws at <= 30 Hz and stops completely when motion is reduced, the node is hidden or mode is "page".
const T = preload("res://ui/theme/ui_tokens.gd")
const Icons = preload("res://ui/theme/ui_icons.gd")
const Prefs = preload("res://ui/theme/ui_prefs.gd")
const EMBERS := 36
const PIECE_KINDS := ["rook_piece", "knight", "bishop", "king"]
const STEP := 1.0 / 30.0
## 0..1: how strongly the centre of the screen is dimmed in "scene" mode (the menu fades it in).
var center_dim := 0.0:
	set(value):
		if not is_equal_approx(value, center_dim):
			center_dim = value
			if mode == "scene":
				queue_redraw()
var mode := "page":
	set(value):
		mode = value
		_sync_processing()
		queue_redraw()
var _pos := PackedVector2Array()
var _vel := PackedVector2Array()
var _life := PackedFloat32Array()
var _span := PackedFloat32Array()
var _radius := PackedFloat32Array()
var _piece_pos := PackedVector2Array()
var _piece_angle := PackedFloat32Array()
var _piece_speed := PackedFloat32Array()
var _piece_size := PackedFloat32Array()
var _textures: Array[ImageTexture] = []
var _scrim_texture: GradientTexture2D
var _accumulator := 0.0
var _rng := RandomNumberGenerator.new()
# cached geometry: rebuilt only when the size or mode changes, never per frame
var _cache_key := Vector3.ZERO
var _bg_points := PackedVector2Array()
var _bg_colors := PackedColorArray()
var _glow_points := PackedVector2Array()
var _glow_colors := PackedColorArray()

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	_rng.seed = 7021
	_pos.resize(EMBERS)
	_vel.resize(EMBERS)
	_life.resize(EMBERS)
	_span.resize(EMBERS)
	_radius.resize(EMBERS)
	for i in EMBERS:
		_respawn(i, Vector2(1280, 800), true)
	_piece_pos.resize(PIECE_KINDS.size())
	_piece_angle.resize(PIECE_KINDS.size())
	_piece_speed.resize(PIECE_KINDS.size())
	_piece_size.resize(PIECE_KINDS.size())
	for i in PIECE_KINDS.size():
		_piece_pos[i] = Vector2(0.12 + 0.25 * i + _rng.randf_range(-0.04, 0.04), 0.25 + 0.5 * float(i % 2) + _rng.randf_range(-0.08, 0.08))
		_piece_angle[i] = _rng.randf_range(-0.4, 0.4)
		_piece_speed[i] = _rng.randf_range(0.03, 0.07) * (1.0 if i % 2 == 0 else -1.0)
		_piece_size[i] = _rng.randf_range(150.0, 230.0)

func _ready() -> void:
	Prefs.add_listener(_sync_processing)
	_sync_processing()

func _exit_tree() -> void:
	Prefs.remove_listener(_sync_processing)

func _respawn(i: int, area: Vector2, scatter: bool) -> void:
	_pos[i] = Vector2(_rng.randf() * area.x, area.y * (_rng.randf() if scatter else 1.0 + _rng.randf() * 0.05))
	_vel[i] = Vector2(_rng.randf_range(-6.0, 6.0), -_rng.randf_range(12.0, 34.0))
	_span[i] = _rng.randf_range(5.0, 11.0)
	_life[i] = _rng.randf() * _span[i] if scatter else 0.0
	_radius[i] = _rng.randf_range(0.9, 2.4)

func animated() -> bool:
	return mode == "home" and not Prefs.reduce_motion and is_visible_in_tree()

func _sync_processing() -> void:
	set_process(animated())
	if mode == "home" and _textures.is_empty():
		for kind in PIECE_KINDS:
			_textures.append(Icons.texture(kind, 192))
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		_sync_processing()

func _process(delta: float) -> void:
	_accumulator += delta
	if _accumulator < STEP:
		return
	var step := _accumulator
	_accumulator = 0.0
	var area := size
	for i in EMBERS:
		_life[i] += step
		_pos[i] += _vel[i] * step
		if _life[i] >= _span[i] or _pos[i].y < -10.0:
			_respawn(i, area, false)
	for i in PIECE_KINDS.size():
		_piece_angle[i] += _piece_speed[i] * step
	queue_redraw()

func _draw_scene_scrim(rect: Rect2) -> void:
	var dark := Color(T.BG_DEEP.r, T.BG_DEEP.g, T.BG_DEEP.b, 0.0)
	var top_band := Color(T.BG_DEEP.r, T.BG_DEEP.g, T.BG_DEEP.b, 0.55)
	var bottom_band := Color(T.BG_DEEP.r, T.BG_DEEP.g, T.BG_DEEP.b, 0.62)
	var top_h := rect.size.y * 0.34
	draw_polygon(PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x, rect.position.y + top_h), Vector2(rect.position.x, rect.position.y + top_h)]), PackedColorArray([top_band, top_band, dark, dark]))
	var bottom_h := rect.size.y * 0.40
	draw_polygon(PackedVector2Array([Vector2(rect.position.x, rect.end.y - bottom_h), Vector2(rect.end.x, rect.end.y - bottom_h), rect.end, Vector2(rect.position.x, rect.end.y)]), PackedColorArray([dark, dark, bottom_band, bottom_band]))
	if center_dim > 0.003:
		# soft ellipse behind the menu so the wordmark and tagline stay readable over the lit castle
		if _scrim_texture == null:
			var gradient := Gradient.new()
			gradient.set_color(0, Color(T.BG_DEEP.r, T.BG_DEEP.g, T.BG_DEEP.b, 1.0))
			gradient.set_color(1, Color(T.BG_DEEP.r, T.BG_DEEP.g, T.BG_DEEP.b, 0.0))
			var texture := GradientTexture2D.new()
			texture.gradient = gradient
			texture.fill = GradientTexture2D.FILL_RADIAL
			texture.fill_from = Vector2(0.5, 0.5)
			texture.fill_to = Vector2(1.0, 0.5)
			texture.width = 128
			texture.height = 128
			_scrim_texture = texture
		var radius := Vector2(rect.size.x * 0.52, rect.size.y * 0.62)
		draw_texture_rect(_scrim_texture, Rect2(rect.get_center() - radius, radius * 2.0), false, Color(1, 1, 1, 0.66 * center_dim))

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return
	if mode == "scene":
		_draw_scene_scrim(rect)
		return
	var key := Vector3(rect.size.x, rect.size.y, 1.0 if mode == "home" else 0.0)
	if key != _cache_key:
		_cache_key = key
		var top := T.SURFACE if mode == "home" else T.BG
		_bg_colors = PackedColorArray([top, top, T.BG_DEEP, T.BG_DEEP])
		_bg_points = PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
		var glow := Color(T.EMBER.r, T.EMBER.g, T.EMBER.b, 0.07)
		var clear := Color(T.EMBER.r, T.EMBER.g, T.EMBER.b, 0.0)
		_glow_colors = PackedColorArray([clear, clear, glow, glow])
		_glow_points = PackedVector2Array([Vector2(0, rect.size.y * 0.55), Vector2(rect.size.x, rect.size.y * 0.55), rect.end, Vector2(0, rect.size.y)])
	draw_polygon(_bg_points, _bg_colors)   # slate gradient, lighter at the top on the title screen
	if mode != "home":
		return
	draw_polygon(_glow_points, _glow_colors)   # warm glow low in the frame
	for i in PIECE_KINDS.size():
		if i >= _textures.size():
			break
		var extent := _piece_size[i] * clampf(rect.size.y / 800.0, 0.6, 1.6)
		var centre := Vector2(_piece_pos[i].x * rect.size.x, _piece_pos[i].y * rect.size.y)
		draw_set_transform(centre, _piece_angle[i], Vector2.ONE)
		draw_texture_rect(_textures[i], Rect2(Vector2(-extent, -extent) * 0.5, Vector2(extent, extent)), false, Color(T.GOLD.r, T.GOLD.g, T.GOLD.b, 0.045))
	draw_set_transform_matrix(Transform2D.IDENTITY)
	for i in EMBERS:
		var age := _life[i] / _span[i]
		var alpha := sin(clampf(age, 0.0, 1.0) * PI) * 0.55
		draw_circle(_pos[i], _radius[i], Color(T.EMBER.r, T.EMBER.g + 0.1 * age, T.EMBER.b, alpha))
