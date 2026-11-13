class_name PaladinModel
extends Node3D
## One rigged paladin (Meshy mesh, Mixamo skeleton) used as a chess piece / fighter, white or black.
##
##   var m := PaladinModel.create("n", "w", 0.95)   # role p n b r q k, side "w" / "b", standing height in metres
##   add_child(m); m.play("walk", 1.0)               # "idle" "walk" "run" ... (see CLIPS); faces +Z like the other models
##
## Loading: the imported PackedScene when the editor import has run (exports always have it), otherwise the GLB is parsed at run time
## (GLTFDocument), exactly like CharacterModel, so a fresh checkout works before an import. Per (role, side) one template is built
## and every piece is a duplicate of it (shared meshes, textures and animations).
## Textures: the GLB carries one silver-and-gold atlas; the white and black versions are albedo overrides built by
## tools/paladins/build_textures.py (the gold trim stays gold in both).

const ROOT := "res://assets/paladins"
const FILES := {"p": "pawn", "n": "knight", "b": "bishop", "r": "rook", "q": "queen", "k": "king"}
const SOURCE_HEIGHT := 1.7           # every supplied model is 1.7 m tall (bounding box)
## Names of the clips inside the supplied GLBs.
const GLB_CLIPS := {"walk": "Walking", "run": "Running", "slash": "Charged_Slash", "climb": "Fast_Ladder_Climb", "casual_walk": "Casual_Walk"}
## Ground speed (m/s at SOURCE_HEIGHT) the walk and run clips are foot-locked at; scaled by height / SOURCE_HEIGHT.
const NOMINAL_SPEED := {"walk": 1.35, "run": 3.6}

static var _templates: Dictionary = {}   # "role_side" -> Node3D (never in the tree)
static var _textures: Dictionary = {}

var role: String = "p"
var side: String = "w"
var height: float = 1.7
var skeleton: Skeleton3D
var player: AnimationPlayer
var meshes: Array[MeshInstance3D] = []
var current: String = ""


static func placeholder(_role_code: String) -> bool:
	return false   # every role has its own model now


static func path_for(role_code: String) -> String:
	return "%s/%s.glb" % [ROOT, String(FILES.get(role_code, ""))]


static func available(role_code: String) -> bool:
	var path := path_for(role_code)
	return FILES.has(role_code) and (ResourceLoader.exists(path) or FileAccess.file_exists(path))


static func create(role_code: String, side_code: String = "w", standing_height: float = 1.0) -> PaladinModel:
	var template := _template(role_code, side_code)
	if template == null:
		return null
	var instance := PaladinModel.new()
	instance.role = role_code
	instance.side = side_code
	instance.height = standing_height
	var body: Node3D = template.duplicate()
	body.name = "Body"
	body.scale = Vector3.ONE * (standing_height / SOURCE_HEIGHT)
	instance.add_child(body)
	instance.skeleton = _first(body, "Skeleton3D") as Skeleton3D
	instance.player = _first(body, "AnimationPlayer") as AnimationPlayer
	for node in body.find_children("*", "MeshInstance3D", true, false):
		instance.meshes.append(node)
	instance._prepare_clips()
	PaladinClips.ensure(instance.player, instance.skeleton)   # real idle and the combat clips (shared per template)
	return instance


static func _first(node: Node, klass: String) -> Node:
	var found := node.find_children("*", klass, true, false)
	return found[0] if found.size() > 0 else null


static var _exit_hooked := false


## Frees every cached template, texture and generated clip library (none of them is ever in the tree, so the engine would report
## them as leaked at exit). Hooked to the SceneTree's exit the first time a template is built; the next piece simply rebuilds the cache.
static func release_all() -> void:
	for template in _templates.values():
		if is_instance_valid(template):
			template.free()
	_templates.clear()
	_textures.clear()
	PaladinClips.clear_caches()


static func _template(role_code: String, side_code: String) -> Node3D:
	var key := role_code + "_" + side_code
	if _templates.has(key):
		return _templates[key]
	if not _exit_hooked:
		var loop := Engine.get_main_loop() as SceneTree
		if loop != null:
			loop.root.tree_exiting.connect(release_all)
			_exit_hooked = true
	if not available(role_code):
		return null
	var path := path_for(role_code)
	var root: Node3D = null
	if ResourceLoader.exists(path):
		var scene = load(path)
		if scene is PackedScene:
			root = scene.instantiate()
	if root == null:
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(ProjectSettings.globalize_path(path), state) != OK:
			return null
		root = doc.generate_scene(state)
	if root == null:
		return null
	_apply_side(root, role_code, side_code)
	_templates[key] = root
	return root


static func _texture(role_code: String, side_code: String) -> Texture2D:
	var name_: String = String(FILES.get(role_code, "")) + "_" + side_code
	if _textures.has(name_):
		return _textures[name_]
	var path := "%s/textures/%s.jpg" % [ROOT, name_]
	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		texture = load(path)
	elif FileAccess.file_exists(path):
		var image := Image.load_from_file(ProjectSettings.globalize_path(path))
		if image != null:
			image.generate_mipmaps()
			texture = ImageTexture.create_from_image(image)
	_textures[name_] = texture
	return texture


static func _apply_side(root: Node, role_code: String, side_code: String) -> void:
	var texture := _texture(role_code, side_code)
	if texture == null:
		return
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		for surface in mesh_instance.mesh.get_surface_count():
			var base := mesh_instance.mesh.surface_get_material(surface)
			var material: StandardMaterial3D = base.duplicate() if base is StandardMaterial3D else StandardMaterial3D.new()
			material.albedo_texture = texture
			material.albedo_color = Color.WHITE
			mesh_instance.set_surface_override_material(surface, material)


# ---- animation ---------------------------------------------------------------------------------------------------
func _prepare_clips() -> void:
	if player == null:
		return
	for clip in ["Walking", "Running", "Casual_Walk", "Charged_Slash", "Fast_Ladder_Climb"]:
		if player.has_animation(clip):
			player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR if clip != "Charged_Slash" else Animation.LOOP_NONE


## Plays "idle", "walk", "run" (and "slash" / "climb" where the model has them). `speed` is a playback multiplier. "idle" holds the
## standing pose of the authored idle clip (frame 0, paused: a board of 32 pieces must not evaluate 32 skeletons every frame).
func play(clip: String, speed: float = 1.0, blend: float = 0.15) -> void:
	current = clip
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		return   # (a piece being removed from the board: nothing to pose)
	var anim_name: String = clip if player.has_animation(clip) else String(GLB_CLIPS.get(clip, ""))
	if anim_name == "" or not player.has_animation(anim_name):
		anim_name = "idle" if player.has_animation("idle") else "Walking"
		clip = "idle"
	if clip == "idle":
		current = "idle"
		if player.has_animation(anim_name):
			player.play(anim_name, 0.0)
			player.seek(0.0, true)
			player.pause()
		return
	player.play(anim_name, blend, speed)


## Playback speed that keeps the feet on the ground while the piece moves at `metres_per_second`.
func locomotion_speed(clip: String, metres_per_second: float) -> float:
	var nominal: float = float(NOMINAL_SPEED.get(clip, 1.0)) * height / SOURCE_HEIGHT
	return metres_per_second / maxf(nominal, 0.01)
