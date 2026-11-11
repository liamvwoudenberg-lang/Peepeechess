class_name CharacterModel
extends Node3D
## Imported (Blender-generated) character: follows a FighterController and plays the right clip.
##
## Loading: the imported PackedScene if the editor import has run, otherwise the GLB is parsed at
## runtime (GLTFDocument), so a fresh checkout works before any import. If the file is missing
## entirely, `available()` is false and the caller uses the procedural placeholder (FighterVisual).
##
## Animation sync: attack/parry/dodge/stagger/ability/defeat clips are paced to the simulation's tick
## counts (clip length == sim ticks for attacks, see tools/blender/.../animation/spec.py) and
## re-synchronised from `state_ticks` when drift appears. Locomotion clips scale with real speed.
## The model faces +Z natively (Blender -Y -> glTF +Z), so rotation.y = gameplay yaw directly.

const S := CombatConstants.State
const CLASS_NAMES := {"p": "pawn", "n": "knight", "b": "bishop", "r": "rook", "q": "queen", "k": "king"}
const LOOPING := ["idle", "walk", "run", "strafe_left", "strafe_right", "block"]
const NOMINAL_SPEED := {"walk": 2.2, "run": 5.0, "strafe_left": 2.0, "strafe_right": 2.0}
const BLEND := 0.08
const REQUIRED_CLIPS := ["idle", "walk", "run", "strafe_left", "strafe_right", "light_1", "light_2", "light_3",
		"heavy", "block", "parry", "dodge", "stagger", "ability", "defeat"]
const TEAM_ACCENT := {"w": Color(0.9, 0.74, 0.28), "b": Color(0.55, 0.08, 0.22)}

static var show_hitbox: bool = false
static var prefer_lod1: bool = false

var fighter: FighterController
var model: Node3D
var skeleton: Skeleton3D
var player: AnimationPlayer
var class_name_str: String = ""
var lod: int = 0
var arc_fx: MeshInstance3D
var _current: String = ""
var _arc_key: String = ""
var _sockets: Dictionary = {}


static func path_for(role: String, lod_level: int = 0) -> String:
	var cls: String = CLASS_NAMES.get(role, "")
	if cls == "":
		return ""
	return "res://assets/combat/characters/%s/%s%s.glb" % [cls, cls, "_lod1" if lod_level > 0 else ""]


static func available(role: String, lod_level: int = 0) -> bool:
	var path := path_for(role, lod_level)
	return path != "" and (ResourceLoader.exists(path) or FileAccess.file_exists(path))


## Loads the model scene: imported resource when present, runtime GLB parse otherwise.
static func load_scene(path: String) -> Node3D:
	if ResourceLoader.exists(path):
		var packed = load(path)
		if packed is PackedScene:
			return packed.instantiate()
	if FileAccess.file_exists(path):
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(path, state) == OK:
			return doc.generate_scene(state)
	return null


## Free mode (gallery/tests): no fighter, call play_clip().
func setup_free(role: String, lod_level: int = 0, team: String = "w") -> bool:
	lod = lod_level
	class_name_str = CLASS_NAMES.get(role, "")
	model = load_scene(path_for(role, lod_level))
	if model == null:
		return false
	add_child(model)
	_bind(team)
	return true


func setup(f: FighterController) -> bool:
	fighter = f
	if not setup_free(f.role, 1 if prefer_lod1 else 0, f.color):
		return false
	arc_fx = MeshInstance3D.new()
	var arc_mat := StandardMaterial3D.new()
	arc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	arc_mat.albedo_color = Color(1.0, 0.85, 0.5, 0.28)
	arc_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	arc_fx.material_override = arc_mat
	arc_fx.position = Vector3(0.0, 0.9, 0.0)
	arc_fx.visible = false
	add_child(arc_fx)
	return true


func _bind(team: String) -> void:
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0] if not model.find_children("*", "Skeleton3D", true, false).is_empty() else null
	var players := model.find_children("*", "AnimationPlayer", true, false)
	player = players[0] if not players.is_empty() else null
	if player != null:
		for clip_name in player.get_animation_list():
			var anim := player.get_animation(clip_name)
			anim.loop_mode = Animation.LOOP_LINEAR if clip_name in LOOPING else Animation.LOOP_NONE
	for att in model.find_children("*", "BoneAttachment3D", true, false):
		_sockets[att.bone_name] = att
	_tint_accent(model, TEAM_ACCENT.get(team, TEAM_ACCENT["w"]))


## Team tint: surfaces whose material name ends with "_Accent" take the team colour.
func _tint_accent(node: Node, color: Color) -> void:
	for mesh_node in node.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = mesh_node.mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i)
			if mat is StandardMaterial3D and String(mat.resource_name).ends_with("_Accent"):
				var tinted := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				tinted.albedo_color = color
				mesh_node.set_surface_override_material(i, tinted)


func socket(bone_name: String) -> BoneAttachment3D:
	return _sockets.get(bone_name, null)


func has_clip(clip_name: String) -> bool:
	return player != null and player.has_animation(clip_name)


func play_clip(clip_name: String, speed: float = 1.0, blend: float = BLEND) -> void:
	if player == null or not player.has_animation(clip_name):
		return
	_current = clip_name
	player.play(clip_name, blend, speed)


# ---- following a fighter ---------------------------------------------------------------------
func _process(_delta: float) -> void:
	if fighter == null or player == null:
		return
	if not is_instance_valid(fighter) or not fighter.is_inside_tree():
		return
	var alpha := Engine.get_physics_interpolation_fraction()
	global_position = fighter.prev_position.lerp(fighter.global_position, alpha)
	rotation.y = lerp_angle(fighter.prev_yaw, fighter.yaw, alpha)
	_drive(alpha)
	_update_hitbox_fx()


func _drive(alpha: float) -> void:
	var f := fighter
	var sm := f.sm
	var clip := "idle"
	var speed := 1.0
	var total := 0
	match sm.state:
		S.MOVING:
			var local := f.velocity.rotated(Vector3.UP, -f.yaw)
			var v := f.velocity.length()
			if f.sprinting:
				clip = "run"
			elif absf(local.x) > absf(local.z) * 0.8:
				clip = "strafe_left" if local.x > 0.0 else "strafe_right"
			else:
				clip = "walk"
				if local.z < -0.3:
					speed = -1.0
			speed *= clampf(v / float(NOMINAL_SPEED[clip]), 0.4, 1.8)
		S.ATTACKING:
			if sm.attack != null:
				total = sm.attack_total
				# Links 4 and 5 (Queen's Royal Fury chain) reuse the light_1 / light_2 clips.
				clip = "heavy" if sm.attack.kind == AttackDefinition.Kind.HEAVY else "light_%d" % (maxi(sm.combo_index, 0) % 3 + 1)
		S.ABILITY_CASTING:
			clip = "ability"
			total = sm.attack_total if sm.attack != null else sm.cast_total
		S.BLOCKING:
			clip = "block"
		S.PARRYING:
			clip = "parry"
			total = sm.parry_total
		S.DODGING:
			clip = "dodge"
			total = sm.dodge_total
		S.STAGGERED:
			clip = "stagger"
			total = sm.stun_total
		S.DEFEATED:
			clip = "defeat"
			total = 60
	if not player.has_animation(clip):
		clip = "idle"
		total = 0
	var length := player.get_animation(clip).length
	var expected := -1.0
	if total > 0:
		speed = length / (float(total) / float(CombatConstants.TICK_RATE))
		expected = minf((float(sm.state_ticks) + alpha) / float(total) * length, length)
	if clip != _current:
		_current = clip
		player.play(clip, BLEND, speed, speed < 0.0)
		if expected >= 0.0:
			player.seek(expected, false)
	else:
		player.speed_scale = speed
		if expected >= 0.0 and absf(player.current_animation_position - expected) > 0.05 and clip != "defeat":
			player.seek(expected, false)


func _update_hitbox_fx() -> void:
	if arc_fx == null:
		return
	var shape := fighter.hitbox.shape(fighter)
	var active: bool = show_hitbox and shape.get("active", false)
	arc_fx.visible = active
	if active:
		arc_fx.rotation.y = 0.0
		var key := "%.2f_%.0f" % [float(shape["reach"]), float(shape["arc_degrees"])]
		if key != _arc_key:
			_arc_key = key
			arc_fx.mesh = FighterVisual._sector_mesh(float(shape["reach"]), float(shape["arc_degrees"]))
