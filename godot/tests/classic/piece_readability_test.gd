extends SceneTree
## Board-only presentation invariants: model/animation preservation, bounded footprint, class crests
## and distinct royal headgear. Run after import with --script res://tests/classic/piece_readability_test.gd.
const ORIGINAL_HEIGHTS := {"p": 1.1, "n": 1.3, "b": 1.36, "r": 1.24, "q": 1.44, "k": 1.52}
var failures: Array[String] = []
var checks := 0

func _init() -> void:
	call_deferred("run")

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL: ", message)

func run() -> void:
	var shapes := {}
	var white_crest: Mesh
	var black_crest: Mesh
	for role in ORIGINAL_HEIGHTS:
		for side in ["w", "b"]:
			var piece := PaladinPiece.create(role, side)
			expect(piece != null, "%s/%s uses its original Meshy model" % [role, side])
			if piece == null:
				continue
			root.add_child(piece)
			await process_frame
			piece.model.play("idle")
			expect(is_equal_approx(piece.model.height, float(ORIGINAL_HEIGHTS[role]) * 1.3), "%s/%s standing height increases exactly 30%%" % [role, side])
			expect(piece.position == Vector3.ZERO and piece.scale == Vector3.ONE, "%s/%s preserves its chess root transform" % [role, side])
			expect(float(piece.model.get_meta("board_footprint_radius")) <= 0.4351, "%s/%s fits within a square at every yaw" % [role, side])
			expect(piece.model.player.has_animation("Walking") and piece.model.player.has_animation("Running"), "%s/%s retains supplied locomotion clips" % [role, side])
			var crest := piece.get_node("ClassCrest") as MeshInstance3D
			expect(crest != null and crest.mesh.get_surface_count() == 1, "%s/%s has one batched class pedestal" % [role, side])
			expect(crest.mesh.get_aabb().size.x <= 0.881 and crest.mesh.get_aabb().size.z <= 0.881, "%s/%s pedestal fits inside its square" % [role, side])
			expect(piece.find_children("*", "CollisionObject3D", true, false).is_empty(), "%s/%s heraldry never adds gameplay colliders" % [role, side])
			if role == "k":
				expect(piece.find_child("KingCross", true, false) != null and piece.find_child("QueenFivePointCrown", true, false) == null, "%s king has an attached cross crown" % side)
			if role == "q":
				expect(piece.find_child("QueenFivePointCrown", true, false) != null and piece.find_child("KingCross", true, false) == null, "%s queen has an attached five-point crown" % side)
			if side == "w":
				shapes[role] = crest.mesh.get_surface_count() * 100000 + crest.mesh.surface_get_array_len(0)
				white_crest = crest.mesh
			else:
				black_crest = crest.mesh
			piece.free()
	var unique := {}
	for shape in shapes.values():
		unique[shape] = true
	expect(unique.size() == 6, "all six class glyphs have distinct geometry")
	expect(white_crest != black_crest, "white and black use separate contrasting pedestal colours")
	PaladinModel.release_all()
	print("Piece readability: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
