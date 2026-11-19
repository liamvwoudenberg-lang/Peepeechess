extends SceneTree
## Live preferences on the actual shared 3D/pit board; shapes and chess authority remain intact.
const Prefs = preload("res://ui/theme/ui_prefs.gd")
const Tokens = preload("res://ui/theme/ui_tokens.gd")
var checks = 0
var failures: Array = []

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL: ", label)

func _init() -> void:
	call_deferred("run")

func rgb(color: Color) -> Color:
	return Color(color, 1.0)

func at(board: ChessBoard3D, square: String) -> MeshInstance3D:
	var point = BoardInteraction.world_position(ClassicChess.index(square))
	for mark in board.marks.get_children():
		if absf(mark.position.x - point.x) < 0.001 and absf(mark.position.z - point.z) < 0.001:
			return mark
	return null

func run() -> void:
	BoardTheme.apply({"pieces": "procedural"})
	Prefs.loaded = true
	Prefs.colorblind = false
	var listeners = Prefs._listeners.size()
	var game = ClassicMatch.new()
	expect(game.new_game(0, 0, "4k3/8/8/3p4/4P3/8/8/4K3 w - - 0 1").ok, "capture fixture loads")
	var interaction = BoardInteraction.new(game)
	var board = ChessBoard3D.new()
	root.add_child(board)
	board.setup(game, interaction)
	interaction.select(ClassicChess.index("e4"))
	var state = game.match_state()
	for top_down in [false, true]:
		board.set_top_down(top_down)
		for style in ["dots", "rings", "tint"]:
			BoardTheme.apply({"highlight": style})
			Prefs.set_colorblind(false)
			var original = rgb(at(board, "e5").material_override.albedo_color)
			Prefs.set_colorblind(true)
			var move_mark = at(board, "e5")
			var capture_mark = at(board, "d5")
			expect(rgb(move_mark.material_override.albedo_color).is_equal_approx(Tokens.CB_MOVE), "live safe move palette: %s / top-down %s" % [style, top_down])
			expect(rgb(capture_mark.material_override.albedo_color).is_equal_approx(Tokens.CB_CAPTURE), "live safe capture palette: %s / top-down %s" % [style, top_down])
			expect(move_mark.layers == WorldConstants.LAYER_BOARD and capture_mark.layers == WorldConstants.LAYER_BOARD, "markers remain on the board render layer")
			if style == "dots":
				# captures are a bold ring (TorusMesh, outer_radius) around the victim, moves a small disc (CylinderMesh, top_radius)
				var capture_size: float = capture_mark.mesh.outer_radius if capture_mark.mesh is TorusMesh else capture_mark.mesh.top_radius
				var move_size: float = move_mark.mesh.outer_radius if move_mark.mesh is TorusMesh else move_mark.mesh.top_radius
				expect(capture_size > move_size, "capture has a distinct shape size, independent of colour")
			Prefs.set_colorblind(false)
			expect(rgb(at(board, "e5").material_override.albedo_color).is_equal_approx(original), "disabling the preference restores the normal palette")
	expect(game.match_state() == state, "camera, style and accessibility changes never mutate the match")
	game.new_game(0, 0, "4k3/8/8/8/8/8/4r3/4K3 w - - 0 1")
	Prefs.set_colorblind(true)
	expect(rgb(at(board, "e1").material_override.albedo_color).is_equal_approx(Tokens.CB_CAPTURE), "checked king uses the safe warning palette")
	interaction.dispose()
	board.queue_free()
	await process_frame
	expect(Prefs._listeners.size() == listeners, "leaving the board removes its preference listener")
	Prefs.set_colorblind(false)
	BoardTheme.reset()
	print("ACCESSIBILITY: ", checks, " checks; failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
