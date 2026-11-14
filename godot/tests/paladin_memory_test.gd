extends SceneTree
## Resource budget regression for Android: real imported textures and a full 32-piece roster.
const Model = preload("res://paladins/paladin_model.gd")
var failures: Array[String] = []
var checks := 0

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var texture_bytes := 0
	var source_bytes := 0
	for role in Model.FILES:
		var stem: String = Model.FILES[role]
		var paths: Array[String] = []
		for index in 3:
			paths.append("res://assets/paladins/%s_Image_%d.jpg" % [stem, index])
		for side in ["w", "b"]:
			paths.append("res://assets/paladins/textures/%s_%s.jpg" % [stem, side])
		for path in paths:
			var texture := load(path) as Texture2D
			expect(texture != null, path + " loads")
			if texture == null:
				continue
			var image := texture.get_image()
			expect(image != null, path + " has imported image data")
			if image == null:
				continue
			expect(maxi(image.get_width(), image.get_height()) <= 1024, path + " stays inside 1024px budget")
			expect(image.has_mipmaps(), path + " has filtered distance levels")
			texture_bytes += image.get_data_size()
			source_bytes += 2048 * 2048 * 4
	# Even an uncompressed driver fallback is bounded; supported ETC2/S3TC is substantially smaller.
	expect(texture_bytes <= 30 * 1024 * 1024 * 4 * 4 / 3, "all 30 model maps fit a 160MiB uncompressed ceiling")
	print("Paladin imported texture bytes: %d; previous RGBA base-level budget: %d" % [texture_bytes, source_bytes])
	var roster := Node3D.new()
	root.add_child(roster)
	var pawns: Array[PaladinModel] = []
	for side in ["w", "b"]:
		for role in ["r", "n", "b", "q", "k", "b", "n", "r", "p", "p", "p", "p", "p", "p", "p", "p"]:
			var piece := Model.create(role, side, 1.1)
			expect(piece != null, "32-piece roster model available")
			if piece == null:
				continue
			piece.play("idle") # off-tree setup, as in the real board
			roster.add_child(piece)
			if role == "p":
				pawns.append(piece)
	await process_frame
	expect(roster.get_child_count() == 32, "opening position contains all 32 models")
	expect(Model._templates.size() == 12, "one cached template per role and side")
	expect(Model._textures.size() == 12, "one shared side atlas per role and side")
	for piece in pawns:
		expect(piece.current == "idle" and not piece.player.is_playing(), "idle board skeleton is paused after joining tree")
		var first: PaladinModel = pawns[0] if piece.side == "w" else pawns[8]
		expect(piece.meshes[0].mesh == first.meshes[0].mesh, "repeated pawns share mesh resources")
		expect(piece.meshes[0].get_surface_override_material(0) == first.meshes[0].get_surface_override_material(0), "repeated pawns share material resources")
	# Opposing sides share geometry while retaining clearly separate livery textures.
	expect(pawns[0].meshes[0].mesh == pawns[8].meshes[0].mesh, "both teams share their role's geometry")
	expect(pawns[0].meshes[0].get_surface_override_material(0).albedo_texture != pawns[8].meshes[0].get_surface_override_material(0).albedo_texture, "teams keep distinct texture variants")
	root.remove_child(roster)
	roster.free()
	Model.release_all()
	expect(Model._templates.is_empty() and Model._textures.is_empty(), "leaving the board releases cached templates and side atlases")
	await process_frame
	if failures.is_empty():
		print("PASS: paladin Android resource budget (%d checks)" % checks)
	quit(0 if failures.is_empty() else 1)
