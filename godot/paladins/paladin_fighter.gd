class_name PaladinFighter
extends CharacterModel
## A fighter presentation built from the rigged paladin models (PaladinModel + procedural PaladinClips).
## It IS a CharacterModel (same duck-typed interface: follows a FighterController, plays clips by simulation state, hit flash,
## flinch, hitstop hold, stowable weapon, weapon trail segments), so the arena, the VFX and the pit world treat it like the
## old characters. Differences: the model comes from godot/assets/paladins, the colour is the fighter's side (white / black texture),
## the clip set is authored at run time (godot/paladins/paladin_clips.gd) and the strike pose is remapped to the simulation's hit window.

## Master switch read by CombatArena: use the paladins when their models exist. Old CharacterModel characters stay the fallback
## ; the old suites (combat test runner) switch the paladins off and assert those characters.
static var prefer_paladins: bool = true
## Standing height per role (m); every supplied model is 1.7 m tall, so these only scale them.
const HEIGHTS := {"p": 1.5, "n": 1.7, "b": 1.75, "r": 1.65, "q": 1.8, "k": 1.9}
const STRIKE_CLIPS := ["light_1", "light_2", "light_3", "heavy"]


static func wanted(role: String) -> bool:
	return prefer_paladins and PaladinModel.available(role)


func setup_free(role: String, _lod_level: int = 0, team: String = "w") -> bool:
	class_name_str = CLASS_NAMES.get(role, "")
	var body := PaladinModel.create(role, team, float(HEIGHTS.get(role, 1.7)))
	if body == null or body.player == null or body.skeleton == null:
		return false
	model = body
	add_child(model)
	PaladinClips.ensure(body.player, body.skeleton)
	_add_sword(body, team)
	_bind(team)
	return true


## Same contract as CharacterModel. The pit stows the weapon for the ladder climb; the paladins' broad armour also needs to slim down a
## little (a few percent of body width and depth) to fit the 1 m shaft, which is hardly visible while they climb.
func set_props_stowed(amount: float) -> void:
	super.set_props_stowed(amount)
	if model != null:
		model.scale = Vector3(1.0 - 0.14 * stowed, 1.0, 1.0 - 0.18 * stowed)
		_model_base.basis = Basis.from_scale(model.scale)   # the hit flinch restores the base transform: keep it slim too


func _nominal_speed(clip: String) -> float:
	var base: float = float(PaladinModel.NOMINAL_SPEED["run" if clip == "run" else "walk"])
	return base * float(HEIGHTS.get(fighter.role if fighter != null else "p", 1.7)) / PaladinModel.SOURCE_HEIGHT


## The strike pose of the authored clips sits at PaladinClips.STRIKE of the clip; the simulation opens the hit window at startup_end.
func _remap_clip_time(clip: String, u: float, startup_end: float) -> Vector2:
	if not (clip in STRIKE_CLIPS) or startup_end < 0.05 or startup_end > 0.95:
		return Vector2(u, 1.0)
	var s := PaladinClips.STRIKE
	if u <= startup_end:
		return Vector2(u / startup_end * s, s / startup_end)
	return Vector2(s + (u - startup_end) / (1.0 - startup_end) * (1.0 - s), (1.0 - s) / (1.0 - startup_end))


# ---- the sword ------------------------------------------------------------------------------------------------------------------
## A plain procedural longsword in the right hand (the models carry none). Registered as "WeaponSocket_R" so the stow logic, the
## trail ribbons and the flash treat it like the old weapon sockets.
func _add_sword(body: PaladinModel, team: String) -> void:
	var sk := body.skeleton
	var hand := sk.find_bone("mixamorig_RightHand")
	if hand < 0:
		return
	# In the A-pose the hand hangs with its fingers pointing down. The blade is aimed in SKELETON space (down and a little forward: it then points forward when the arm is thrust forward; held
	# at the ready) and converted into the hand's own frame, so it does not depend on how the rig's bone axes happen to point.
	var to_local := sk.get_bone_global_rest(hand).basis.orthonormalized().inverse()
	var z_dir: Vector3 = to_local * Vector3(0.0, -0.82, 0.57).normalized()
	var x_dir: Vector3 = to_local * Vector3(1.0, 0.0, 0.0)
	var y_dir := z_dir.cross(x_dir).normalized()
	x_dir = y_dir.cross(z_dir).normalized()
	var grip_offset: Vector3 = to_local * Vector3(0.0, -0.05, 0.0)
	var attachment := BoneAttachment3D.new()
	attachment.name = "WeaponSocket_R"
	attachment.bone_name = "mixamorig_RightHand"
	sk.add_child(attachment)
	var sword := Node3D.new()
	sword.name = "Sword"
	sword.transform = Transform3D(Basis(x_dir, y_dir, z_dir), grip_offset)
	attachment.add_child(sword)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.82, 0.84, 0.88) if team == "w" else Color(0.26, 0.28, 0.33)
	steel.metallic = 0.9
	steel.roughness = 0.28
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.86, 0.68, 0.24)
	gold.metallic = 0.8
	gold.roughness = 0.35
	_part(sword, "Blade", Vector3(0.06, 0.016, 0.86), Vector3(0, 0, 0.50), steel)   # first mesh: weapon_segments() measures it
	_part(sword, "Guard", Vector3(0.24, 0.03, 0.035), Vector3(0, 0, 0.065), gold)
	_part(sword, "Grip", Vector3(0.032, 0.032, 0.17), Vector3(0, 0, -0.035), gold)
	_part(sword, "Pommel", Vector3(0.05, 0.05, 0.05), Vector3(0, 0, -0.13), gold)
	_sockets["WeaponSocket_R"] = attachment


func _part(parent: Node3D, part_name: String, size: Vector3, at: Vector3, material: Material) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = part_name
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.material_override = material
	mesh_instance.position = at
	parent.add_child(mesh_instance)
