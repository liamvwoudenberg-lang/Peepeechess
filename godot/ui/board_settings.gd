class_name BoardSettingsPage
extends RefCounted
## "Board & pieces" card for the application Settings page: board theme, move highlights, coordinates, piece set,
## animation speed and piece shadow quality, with a live 2D and 3D preview. Changes apply immediately through
## BoardTheme (every open board redraws) and are saved to preferences. Added to application.gd with one call:
## `BoardSettingsPage.build(self)`.
const Settings = preload("res://ui/application_settings.gd")
const Models = preload("res://boards/piece_meshes.gd")
const ATLAS = preload("res://assets/board/legions-drawn.png")
const GOLD = Color("e5c586")
const MUTED = Color("b6c4b5")
const ROLES = "pnbrqk"
## Sample position for the 2D preview and the squares its selected knight (f3) can reach.
const SAMPLE = {"e1": "K", "d1": "Q", "a1": "R", "h1": "R", "f3": "N", "c4": "B", "e4": "P", "d2": "P", "g2": "P", "e5": "p", "d7": "p", "f7": "p", "e8": "k", "d8": "q", "g8": "n", "a8": "r"}
const SAMPLE_MOVES = ["e5", "g5", "h4", "d4", "g1", "h2", "d2x"]

## Small 8x8 preview painted with the same BoardTheme helpers as the real 2D board.
class Preview2D:
	extends Control
	func _init() -> void:
		name = "BoardPreview2D"
		custom_minimum_size = Vector2(300, 300)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		BoardTheme.events().changed.connect(queue_redraw)
	func _draw() -> void:
		var extent = minf(size.x, size.y) - 28.0
		var rect = Rect2((size - Vector2.ONE * extent) * 0.5, Vector2.ONE * extent)
		var pitch = rect.size.x / 8.0
		var frame = StyleBoxFlat.new()
		frame.bg_color = BoardTheme.color("frame")
		frame.set_corner_radius_all(8)
		frame.set_border_width_all(1)
		frame.border_color = BoardTheme.color("frame_border")
		draw_style_box(frame, rect.grow(5))
		for at in range(64):
			var cell = Vector2i(at % 8, 7 - at / 8)
			var tile = Rect2(rect.position + Vector2(cell) * pitch, Vector2.ONE * pitch)
			draw_rect(tile, BoardTheme.tile_color((at % 8 + at / 8) % 2 == 1))
			var name_at = ClassicChess.square(at)
			if name_at == "f3":
				draw_rect(tile, Color(0.96, 0.79, 0.37, 0.65))
			for move in BoardSettingsPage.SAMPLE_MOVES:
				if move.trim_suffix("x") == name_at:
					BoardTheme.draw_destination_2d(self, tile, SAMPLE.has(name_at) and SAMPLE[name_at] == SAMPLE[name_at].to_lower())
		for name_at in SAMPLE:
			var at = ClassicChess.index(name_at)
			var piece: String = SAMPLE[name_at]
			var cell2 = Vector2i(at % 8, 7 - at / 8)
			var source = Rect2(ROLES.find(piece.to_lower()) * 192, (0 if piece == piece.to_upper() else 1) * 192, 192, 192)
			draw_texture_rect_region(ATLAS, Rect2(rect.position + (Vector2(cell2) + Vector2.ONE * 0.04) * pitch, Vector2.ONE * pitch * 0.92), source)
		if BoardTheme.coordinates:
			var font = ThemeDB.fallback_font
			for i in range(8):
				draw_string(font, Vector2(rect.position.x + pitch * (i + 0.5) - 3, rect.end.y + 14), "abcdefgh"[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, BoardTheme.color("label"))
				draw_string(font, Vector2(rect.position.x - 14, rect.position.y + pitch * (i + 0.5) + 4), str(8 - i), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, BoardTheme.color("label"))

## Two tiles, a white king and a black knight in a private 3D world: shows piece set, tile colours and shadows.
class Preview3D:
	extends SubViewportContainer
	var _stage: Node3D
	var _light: DirectionalLight3D
	func _init() -> void:
		name = "BoardPreview3D"
		custom_minimum_size = Vector2(300, 300)
		stretch = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var viewport = SubViewport.new()
		viewport.own_world_3d = true
		viewport.size = Vector2i(300, 300)
		viewport.msaa_3d = Viewport.MSAA_2X
		add_child(viewport)
		var root = Node3D.new()
		viewport.add_child(root)
		var environment_node = WorldEnvironment.new()
		var environment = Environment.new()
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = Color("14272e")
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = Color("b5d0d1")
		environment.ambient_light_energy = 0.35
		environment_node.environment = environment
		root.add_child(environment_node)
		_light = DirectionalLight3D.new()
		_light.rotation_degrees = Vector3(-50, -30, 0)
		_light.light_energy = 0.9
		root.add_child(_light)
		var camera = Camera3D.new()
		camera.fov = 38
		root.add_child(camera)
		camera.look_at_from_position(Vector3(0.0, 2.4, 3.4), Vector3(0, 0.45, 0))
		_stage = Node3D.new()
		root.add_child(_stage)
		BoardTheme.events().changed.connect(_rebuild)
		_rebuild()
	func _rebuild() -> void:
		for child in _stage.get_children():
			_stage.remove_child(child)
			child.queue_free()
		_light.shadow_enabled = BoardTheme.shadows == "high"
		var light_tile = Models.material(BoardTheme.color("light_3d"))
		var dark_tile = Models.material(BoardTheme.color("dark_3d"))
		Models.box(_stage, Vector3(0.995, 0.08, 0.995), Vector3(-0.5, 0, 0), light_tile)
		Models.box(_stage, Vector3(0.995, 0.08, 0.995), Vector3(0.5, 0, 0), dark_tile)
		var king = Models.build("k", "w")
		king.position = Vector3(-0.5, 0.04, 0)
		_stage.add_child(king)
		var knight = Models.build("n", "b")
		knight.position = Vector3(0.5, 0.04, 0)
		knight.rotation.y = PI
		_stage.add_child(knight)

static func _label(parent: Node, text: String, size_px: int = 15, color: Color = MUTED) -> Label:
	var label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

static func _swatch(theme_id: String) -> ImageTexture:
	var palette: Dictionary = BoardTheme.THEMES[theme_id]
	var image = Image.create(40, 24, false, Image.FORMAT_RGB8)
	image.fill(Color(palette.dark))
	image.fill_rect(Rect2i(0, 0, 20, 12), Color(palette.light))
	image.fill_rect(Rect2i(20, 12, 20, 12), Color(palette.light))
	return ImageTexture.create_from_image(image)

## Row of mutually exclusive toggle buttons; `apply` receives the chosen key.
static func _choices(parent: Node, keys: Array, labels: Dictionary, current: String, prefix: String, apply: Callable, swatches: bool = false) -> HFlowContainer:
	var flow = HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	parent.add_child(flow)
	var group = ButtonGroup.new()
	for key in keys:
		var chosen: String = key
		var button = Button.new()
		button.name = prefix + chosen
		button.text = labels.get(chosen, chosen.capitalize())
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = chosen == current
		button.custom_minimum_size.y = 44
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		OpponentUI.style_toggle(button)
		if swatches:
			button.icon = _swatch(chosen)
		button.pressed.connect(func(): apply.call(chosen))
		flow.add_child(button)
	return flow

static func _commit(values: Dictionary) -> void:
	BoardTheme.apply(values)
	# The pre-existing "Piece animations" switch keeps working: "off" turns it off, any speed turns it on.
	if values.has("animation"):
		Settings.animations = values.animation != "off"
	Settings.save_preferences()

## Build the card into the application's settings page. `app` is the application Control (uses its _card helper).
static func build(app: Control) -> VBoxContainer:
	var card: VBoxContainer = app._card(app.content)
	card.name = "BoardSettings"
	_label(card, "Board & pieces", 24, GOLD)
	_label(card, "Looks only. Changes apply to every board straight away and are saved on this device.", 14)
	var previews = HFlowContainer.new()
	previews.add_theme_constant_override("h_separation", 16)
	previews.add_theme_constant_override("v_separation", 12)
	card.add_child(previews)
	previews.add_child(Preview2D.new())
	previews.add_child(Preview3D.new())
	_label(card, "Board theme", 18, GOLD)
	var theme_labels: Dictionary = {}
	for key in BoardTheme.THEME_ORDER:
		theme_labels[key] = BoardTheme.THEMES[key].name
	_choices(card, BoardTheme.THEME_ORDER, theme_labels, BoardTheme.theme_id, "Theme_", func(key): _commit({"theme": key}), true)
	_label(card, "Move highlights", 18, GOLD)
	_choices(card, BoardTheme.HIGHLIGHT_ORDER, BoardTheme.HIGHLIGHTS, BoardTheme.highlight, "Highlight_", func(key): _commit({"highlight": key}))
	var coordinates = CheckButton.new()
	coordinates.name = "Coordinates"
	coordinates.text = "Show coordinates (a-h, 1-8)"
	coordinates.custom_minimum_size.y = 48
	coordinates.button_pressed = BoardTheme.coordinates
	coordinates.toggled.connect(func(on): _commit({"coordinates": on}))
	card.add_child(coordinates)
	_label(card, "Piece set (3D board)", 18, GOLD)
	_choices(card, BoardTheme.PIECE_SET_ORDER, BoardTheme.PIECE_SETS, BoardTheme.piece_set, "Pieces_", func(key): _commit({"pieces": key}))
	_label(card, "The 2D board always uses the illustrated pieces. If the carved set files are missing the built-in set is used.", 13)
	_label(card, "Animation speed", 18, GOLD)
	_choices(card, BoardTheme.SPEED_ORDER, {"off": "Off", "normal": "Normal", "fast": "Fast"}, BoardTheme.animation_speed, "Speed_", func(key): _commit({"animation": key}))
	_label(card, "Piece shadows (3D board)", 18, GOLD)
	_choices(card, BoardTheme.SHADOW_ORDER, {"low": "Low · off, fastest", "high": "High · soft shadows"}, BoardTheme.shadows, "Shadows_", func(key): _commit({"shadows": key}))
	var reset = Button.new()
	reset.name = "ResetBoardSettings"
	reset.text = "Restore board defaults"
	reset.custom_minimum_size.y = 48
	reset.pressed.connect(func():
		_commit(BoardTheme.defaults())
		app.navigate("settings"))  # rebuild the page so the toggle buttons show the restored choices
	card.add_child(reset)
	return card
