extends RefCounted
## The 3D board shows the paladins and they WALK: pieces are PaladinPiece, white and black textures differ, a played move animates over time and
## ends exactly on its square, undo / new game snap, a captured piece stays until the mover has arrived, a promotion swaps on arrival, and the
## chess state itself never waits for the animation.

const Main := preload("res://app/main.tscn")
const Interaction := preload("res://boards/board_interaction.gd")
const Rules := preload("res://chess/chess_engine.gd")


static func run(h, tree: SceneTree) -> void:
	await _board(h, tree)


static func _wait(tree: SceneTree, frames: int) -> void:
	for _i in frames:
		await tree.process_frame


static func _albedo(piece) -> Texture2D:
	for node in piece.model.meshes:
		var material = node.get_surface_override_material(0)
		if material is StandardMaterial3D:
			return material.albedo_texture
	return null


static func _board(h, tree: SceneTree) -> void:
	h.begin("paladin board: pieces are paladins, moves walk to the exact square, undo snaps, captures and promotions wait for the mover")
	tree.root.size = Vector2i(1200, 800)
	var app = Main.instantiate()
	tree.root.add_child(app)
	await _wait(tree, 4)
	app.set_view(true)
	await _wait(tree, 3)
	var board = app.board_3d
	h.eq(BoardTheme.piece_set, "paladin", "the Paladins set is the default")
	var paladins := 0
	for piece in board.pieces.values():
		if piece is PaladinPiece:
			paladins += 1
	h.eq(paladins, 32, "all 32 pieces are paladins")
	var any_white = null
	var any_black = null
	for id in board.pieces:
		var piece = board.pieces[id]
		if piece.color == "w" and piece.role == "n":
			any_white = piece
		if piece.color == "b" and piece.role == "n":
			any_black = piece
	h.check(any_white != null and any_black != null and _albedo(any_white) != null and _albedo(any_white) != _albedo(any_black), "white and black knights use different textures")
	h.eq(any_white.rotation.y, 0.0, "a white piece rests unrotated at the root (faces -Z through its facer)")
	# --- a pawn walks e2 -> e4
	var pawn_id := ""
	for id in board.pieces:
		if board.pieces[id].role == "p" and board.pieces[id].position.is_equal_approx(Interaction.world_position(12)):
			pawn_id = id
	var pawn = board.pieces[pawn_id]
	var target: Vector3 = Interaction.world_position(28)
	app.game.play("e2", "e4")
	h.eq(app.game.engine.board[28], "P", "the rules applied the move at once, the animation never waits")
	await _wait(tree, 8)
	h.check(pawn.walking and not pawn.position.is_equal_approx(target) and pawn.position.distance_to(Interaction.world_position(12)) > 0.05, "after a few frames the pawn is on its way (walking, not teleported)")
	h.eq(pawn.model.current, "run", "it runs (a two-square move is longer than 1.6 m)")
	await _wait(tree, 200)
	h.check(pawn.position.is_equal_approx(target) and not pawn.walking, "it ends exactly on e4 and stops walking")
	h.eq(pawn.model.current, "idle", "...and goes back to idle")
	# --- a knight moves in an L (two legs), within the 2.5 s cap
	var path := PaladinPiece.path_between("n", Interaction.world_position(6), Interaction.world_position(21))
	h.eq(path.size(), 2, "a knight's path has a corner (an L)")
	var knight = null
	for id in board.pieces:
		if board.pieces[id].role == "n" and board.pieces[id].color == "b" and board.pieces[id].position.is_equal_approx(Interaction.world_position(62)):
			knight = board.pieces[id]
	var started := Time.get_ticks_msec()
	app.game.play("g8", "f6")
	await _wait(tree, 5)
	h.check(knight.walking, "the knight walks")
	await _wait(tree, 220)
	h.check(knight.position.is_equal_approx(Interaction.world_position(45)) and not knight.walking, "the knight ends on f6")
	# --- undo snaps: no walking
	app.game.undo()
	await _wait(tree, 2)
	h.check(not knight.walking and knight.position.is_equal_approx(Interaction.world_position(62)), "undo puts the knight back at once")
	# --- animate off: instant
	app.board_3d.animation_enabled = false
	app.game.play("g8", "f6")
	await _wait(tree, 2)
	h.check(not knight.walking and knight.position.is_equal_approx(Interaction.world_position(45)), "animation off: the move is instant")
	app.board_3d.animation_enabled = true
	# --- capture: the captured piece stays on screen until the mover has arrived
	app.game.new_game(0, 0, "7k/8/8/4p3/8/3N4/8/K7 w - - 0 1")
	await _wait(tree, 3)
	var captured = null
	for id in board.pieces:
		if board.pieces[id].position.is_equal_approx(Interaction.world_position(Rules.index("e5"))):
			captured = board.pieces[id]
	app.game.play("d3", "e5")
	await _wait(tree, 2)
	h.check(is_instance_valid(captured) and captured.get_parent() != null and board.pieces.values().has(captured) == false, "a captured piece is out of the piece table but still on screen while the mover walks")
	await _wait(tree, 260)
	h.check(not is_instance_valid(captured) or captured.get_parent() == null or captured.is_queued_for_deletion(), "...and gone after the mover arrived")
	app.game.new_game(0, 0, "7k/P7/8/8/8/8/8/K7 w - - 0 1")
	await _wait(tree, 3)
	var promo = null
	for id in board.pieces:
		if board.pieces[id].role == "p":
			promo = board.pieces[id]
	var promo_id := ""
	for id in board.pieces:
		if board.pieces[id] == promo:
			promo_id = id
	app.game.play("a7", "a8", "q")
	await _wait(tree, 4)
	h.eq(board.pieces[promo_id].role, "p", "mid-walk the promoting piece is still the pawn")
	await _wait(tree, 220)
	h.eq(board.pieces[promo_id].role, "q", "on arrival it becomes the queen")
	h.check(board.pieces[promo_id].position.is_equal_approx(Interaction.world_position(Rules.index("a8"))), "...standing on a8")
	app.queue_free()
	await _wait(tree, 3)
