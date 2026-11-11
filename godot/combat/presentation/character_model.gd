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
const LOOPING := ["idle", "walk", "run", "strafe_left", "strafe_right", "block", "climb", "ladder_idle", "drop_fall"]
const NOMINAL_SPEED := {"walk": 2.2, "run": 5.0, "strafe_left": 2.0, "strafe_right": 2.0}
const BLEND := 0.08
const LOCOMOTION := ["idle", "walk", "run", "strafe_left", "strafe_right"]
## Anticipation: the wind-up is played slower at first and faster toward the strike (the strike frame and the clip end
## stay exactly on the simulation's ticks). Exponent per attack kind; 1.0 = linear.
const ANTICIPATION_LIGHT := 1.12
const ANTICIPATION_HEAVY := 1.25
const MIN_WARP_SPEED := 0.35
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
var _meshes: Array[MeshInstance3D] = []
var _model_base: Transform3D = Transform3D.IDENTITY
var _loco_speed: float = 0.0
var _hold_frames: int = 0
var _hold_resync: bool = false
var _outcome: String = ""           # "", "win", "lose" (presentation only)
var _react_clip: String = ""
var _react_left: float = 0.0
var _flinch: float = 0.0
var _flinch_dir: Vector3 = Vector3.ZERO
var _flash_mat: StandardMaterial3D = null
var _flash_color: Color = Color.WHITE
var _flash_t: float = 0.0
var _flash_len: float = 0.16
var _weapon_cache: Array = []
var _weapon_cached: bool = false


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
	_model_base = model.transform
	_meshes.clear()
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(mi)


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


## Cross-fade length between two clips (seconds). Short into attacks/reactions so they read instantly, longer between
## locomotion clips so feet do not pop. Pure presentation.
static func blend_time(from_clip: String, to_clip: String) -> float:
	if from_clip == to_clip:
		return 0.0
	var from_loco := from_clip in LOCOMOTION
	if from_loco and to_clip in LOCOMOTION:
		return 0.18 if (from_clip == "idle" or to_clip == "idle") else 0.14
	if to_clip.begins_with("light_") or to_clip == "heavy":
		return 0.05 if (from_loco or from_clip == "block") else 0.03
	match to_clip:
		"stagger":
			return 0.02
		"hit_react_light", "hit_react_heavy":
			return 0.03
		"parry":
			return 0.02
		"dodge":
			return 0.03
		"block":
			return 0.07
		"defeat":
			return 0.06
		"victory":
			return 0.2
		"ability":
			return 0.05
	if from_clip == "block":
		return 0.1
	if from_clip == "stagger" or from_clip.begins_with("hit_react"):
		return 0.12
	return BLEND


func play_clip(clip_name: String, speed: float = 1.0, blend: float = BLEND) -> void:
	if player == null or not player.has_animation(clip_name):
		return
	_current = clip_name
	player.play(clip_name, blend, speed)


# ---- presentation hooks (all optional for callers; see CombatVfx) ------------------------------
## Freezes animation for `frames` display frames (hitstop). The simulation is unaffected; the clip re-seeks to the
## simulation's `state_ticks` afterwards.
func hold(frames: int) -> void:
	_hold_frames = maxi(_hold_frames, clampi(frames, 0, 6))


## Hit reaction. A real `hit_react_*` clip plays only when the fighter is otherwise free (Idle/Moving); in any other
## state (staggered, blocking, attacking with armour) a short procedural flinch is added instead, so no clip is
## overridden and the simulation-paced timelines stay intact.
func react(kind: String, damage: int, from_dir: Vector3) -> void:
	if fighter == null:
		return
	var power := clampf(float(damage) / 40.0, 0.2, 1.0)
	var local := from_dir.rotated(Vector3.UP, -rotation.y)
	_flinch_dir = Vector3(local.x, 0.0, local.z).normalized() if local.length() > 0.01 else Vector3.ZERO
	var state := fighter.sm.state
	var free_state := state == S.IDLE or state == S.MOVING
	var clip := "hit_react_heavy" if damage >= 20 else "hit_react_light"
	if free_state and has_clip(clip):
		_react_clip = clip
		_react_left = player.get_animation(clip).length
		_flinch = 0.35 * power
	else:
		_react_clip = ""
		_react_left = 0.0
		_flinch = power
	_flash_start(Color(1.0, 0.92, 0.75), 0.15 + 0.2 * power, 0.1)


## Short additive colour flash over the whole model (parry gold, block blue, guard-break red).
func flash(color: Color, strength: float = 0.5) -> void:
	_flash_start(color, strength, 0.16)


func _flash_start(color: Color, strength: float, length: float) -> void:
	if _meshes.is_empty():
		return
	if _flash_mat == null:
		_flash_mat = StandardMaterial3D.new()
		_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		# MIX (not ADD): tints toward the colour instead of blowing bright armour out to white.
		_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	_flash_color = Color(color.r, color.g, color.b, clampf(strength, 0.0, 0.45))
	_flash_len = length
	if _flash_t <= 0.0:
		for mi in _meshes:
			mi.material_overlay = _flash_mat
	_flash_t = length
	_flash_mat.albedo_color = _flash_color


## Outcome pose: the winner celebrates (`victory` clip, idle if absent), the loser plays `defeat`.
## A fighter whose simulation state is already DEFEATED keeps its own defeat timeline.
func set_outcome(win: bool) -> void:
	_outcome = "win" if win else "lose"


func outcome() -> String:
	return _outcome


## World-space grip/tip segment of each weapon prop (longest local axis of the prop's mesh), for trail ribbons.
## Returns [{"base": Vector3, "tip": Vector3}]; the base sits 35% along the blade so the ribbon stays slim.
func weapon_segments() -> Array:
	if not _weapon_cached:
		_weapon_cached = true
		for bone in ["WeaponSocket_R", "WeaponSocket_L"]:
			var att: BoneAttachment3D = _sockets.get(bone, null)
			if att == null:
				continue
			var meshes := att.find_children("*", "MeshInstance3D", true, false)
			if meshes.is_empty():
				continue
			var prop: MeshInstance3D = meshes[0]
			var box := prop.get_aabb()
			var axis := 0
			for i in 3:
				if box.size[i] > box.size[axis]:
					axis = i
			var a := box.get_center()
			var b := box.get_center()
			a[axis] = box.position[axis]
			b[axis] = box.position[axis] + box.size[axis]
			_weapon_cache.append({"att": att, "prop": prop, "a": a, "b": b})
	var out: Array = []
	for w in _weapon_cache:
		var prop: MeshInstance3D = w["prop"]
		if not is_instance_valid(prop) or not prop.is_inside_tree():
			continue
		var pa: Vector3 = prop.global_transform * w["a"]
		var pb: Vector3 = prop.global_transform * w["b"]
		var origin: Vector3 = (w["att"] as Node3D).global_position
		var grip := pa
		var tip := pb
		if pb.distance_to(origin) < pa.distance_to(origin):
			grip = pb
			tip = pa
		out.append({"base": grip.lerp(tip, 0.35), "tip": tip})
	return out


# ---- following a fighter ---------------------------------------------------------------------
func _process(delta: float) -> void:
	if fighter == null or player == null:
		return
	if not is_instance_valid(fighter) or not fighter.is_inside_tree():
		return
	var alpha := Engine.get_physics_interpolation_fraction()
	global_position = fighter.prev_position.lerp(fighter.global_position, alpha)
	rotation.y = lerp_angle(fighter.prev_yaw, fighter.yaw, alpha)
	if _hold_frames > 0:
		_hold_frames -= 1
		_hold_resync = true
		player.speed_scale = 0.0
		_step_flash(0.0)
		_step_flinch(0.0)
		_update_hitbox_fx()
		return
	_drive(alpha, delta)
	_step_flash(delta)
	_step_flinch(delta)
	_update_hitbox_fx()


func _exit_tree() -> void:
	# Never leave the shared overlay on meshes that outlive this node's bookkeeping.
	if _flash_t > 0.0:
		_flash_t = 0.0
		for mi in _meshes:
			if is_instance_valid(mi):
				mi.material_overlay = null


func _step_flash(dt: float) -> void:
	if _flash_t <= 0.0:
		return
	_flash_t -= dt
	if _flash_t <= 0.0:
		_flash_t = 0.0
		for mi in _meshes:
			mi.material_overlay = null
		return
	var k := _flash_t / _flash_len
	_flash_mat.albedo_color = Color(_flash_color.r, _flash_color.g, _flash_color.b, _flash_color.a * k * k)


## Decaying positional / lean offset on the model node (never on the fighter): a hit shoves and tilts the body a little.
func _step_flinch(dt: float) -> void:
	if model == null:
		return
	if _flinch <= 0.001:
		if _flinch != 0.0:
			_flinch = 0.0
			model.transform = _model_base
		return
	_flinch *= exp(-14.0 * dt)
	var offset := _flinch_dir * 0.1 * _flinch
	var basis := _model_base.basis
	if _flinch_dir.length() > 0.01:
		var axis := Vector3.UP.cross(_flinch_dir).normalized()
		basis = Basis(axis, 0.22 * _flinch) * basis
	model.transform = Transform3D(basis, _model_base.origin + offset)


func _drive(alpha: float, delta: float = 1.0 / 60.0) -> void:
	var f := fighter
	var sm := f.sm
	# Outcome pose overrides everything except an existing simulation defeat.
	if _outcome != "" and sm.state != S.DEFEATED:
		var clip_out := "victory" if _outcome == "win" else "defeat"
		if not has_clip(clip_out):
			clip_out = "idle"
		if clip_out != _current:
			var blend_out := blend_time(_current, clip_out)
			_current = clip_out
			player.play(clip_out, blend_out, 1.0)
			player.speed_scale = 1.0
		return
	var clip := "idle"
	var speed := 1.0
	var total := 0
	var startup_end := -1.0
	var warp_p := 1.0
	_react_left = maxf(0.0, _react_left - delta)
	var react_active := _react_clip != "" and _react_left > 0.0 and (sm.state == S.IDLE or sm.state == S.MOVING)
	match sm.state:
		S.MOVING:
			var local := f.velocity.rotated(Vector3.UP, -f.yaw)
			# Smoothed speed keeps clip rates from jittering with the 60 Hz velocity steps.
			_loco_speed = lerpf(_loco_speed, f.velocity.length(), 1.0 - exp(-12.0 * delta))
			if f.sprinting:
				clip = "run"
			elif absf(local.x) > absf(local.z) * 0.8:
				clip = "strafe_left" if local.x > 0.0 else "strafe_right"
			else:
				clip = "walk"
				if local.z < -0.3:
					speed = -1.0
			speed *= clampf(_loco_speed / float(NOMINAL_SPEED[clip]), 0.4, 1.8)
		S.ATTACKING:
			if sm.attack != null:
				total = sm.attack_total
				# Links 4 and 5 (Queen's Royal Fury chain) reuse the light_1 / light_2 clips.
				var heavy := sm.attack.kind == AttackDefinition.Kind.HEAVY
				clip = "heavy" if heavy else "light_%d" % (maxi(sm.combo_index, 0) % 3 + 1)
				startup_end = sm.attack.startup_end
				warp_p = ANTICIPATION_HEAVY if heavy else ANTICIPATION_LIGHT
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
		_:
			_loco_speed = lerpf(_loco_speed, 0.0, 1.0 - exp(-12.0 * delta))
	if react_active and has_clip(_react_clip) and (sm.state == S.IDLE or sm.state == S.MOVING):
		clip = _react_clip
		total = 0
		speed = 1.0
	if not player.has_animation(clip):
		clip = "idle"
		total = 0
	var length := player.get_animation(clip).length
	var expected := -1.0
	if total > 0:
		var base_speed := length / (float(total) / float(CombatConstants.TICK_RATE))
		var u := clampf((float(sm.state_ticks) + alpha) / float(total), 0.0, 1.0)
		var warped := u
		var rate := 1.0
		if startup_end > 0.05 and startup_end < 0.95 and warp_p > 1.001 and u < startup_end:
			var r := u / startup_end
			warped = startup_end * pow(r, warp_p)
			rate = clampf(warp_p * pow(r, warp_p - 1.0), MIN_WARP_SPEED, 2.0)
		speed = base_speed * rate
		expected = minf(warped * length, length)
	if clip != _current:
		var blend := blend_time(_current, clip)
		_current = clip
		# speed_scale is the only rate (custom_speed stays 1) so rates never compound.
		player.play(clip, blend, 1.0, speed < 0.0)
		player.speed_scale = speed
		if expected >= 0.0:
			player.seek(expected, false)
	else:
		player.speed_scale = speed
		if expected >= 0.0 and clip != "defeat" and (_hold_resync or absf(player.current_animation_position - expected) > 0.05):
			player.seek(expected, false)
	_hold_resync = false


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
