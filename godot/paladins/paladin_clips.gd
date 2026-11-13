class_name PaladinClips
extends RefCounted
## Procedural combat clips for the supplied paladin models (Mixamo skeleton, bones `mixamorig_<Name>`, A-pose, facing +Z).
## The GLBs only carry Walking / Running (the Pawn also Charged_Slash and Fast_Ladder_Climb), so every other clip of the
## CharacterModel contract is authored here as rotation keyframes and added to the model's AnimationPlayer once.
##
## Authoring space: every key lists rotation deltas in DEGREES in SKELETON space (x = the character's left, y = up, z = forward;
## about x: +ve tips "up" towards "forward", so a hanging arm raised forward is NEGATIVE x; about z: +ve lifts a LEFT arm outwards and
## lowers a RIGHT arm inwards; about y: +ve turns the front towards the left). `ensure()` converts each delta to the bone's local frame
## (local = rest_local * rest_global^-1 * D * rest_global), so poses do not depend on the rig's bone axes.
## Every clip gets a track for EVERY bone: a clip that leaves a bone out would otherwise keep the previous clip's pose on it.
## Bones the rig lacks (the Rook model has 36 joints, no fingers) are skipped.

const STRIKE := 0.36        # clip fraction (0..1) at which attack clips show their impact pose; PaladinFighter remaps sim time to it
const SHORT := {
	"Hips": "Hips", "Spine": "Spine", "Spine1": "Spine1", "Spine2": "Spine2", "Neck": "Neck", "Head": "Head",
	"LSh": "LeftShoulder", "LArm": "LeftArm", "LFore": "LeftForeArm", "LHand": "LeftHand",
	"RSh": "RightShoulder", "RArm": "RightArm", "RFore": "RightForeArm", "RHand": "RightHand",
	"LUp": "LeftUpLeg", "LLeg": "LeftLeg", "LFoot": "LeftFoot", "RUp": "RightUpLeg", "RLeg": "RightLeg", "RFoot": "RightFoot",
}
## Arms lowered from the A-pose and a little bent: the base of every pose.
const BASE := {"LArm": Vector3(0, 0, -26), "RArm": Vector3(0, 0, 26), "LFore": Vector3(-14, 0, 0), "RFore": Vector3(-14, 0, 0)}
const CLIPS := ["idle", "walk", "run", "strafe_left", "strafe_right", "light_1", "light_2", "light_3", "heavy", "block", "parry",
		"dodge", "stagger", "ability", "defeat", "victory", "hit_react_light", "hit_react_heavy", "climb", "ladder_idle", "drop_fall"]
const LOOPING := ["idle", "walk", "run", "strafe_left", "strafe_right", "block", "climb", "ladder_idle", "drop_fall"]


## Adds every missing clip to `player` (shared by all instances of the same template). Safe to call repeatedly.
static func ensure(player: AnimationPlayer, skeleton: Skeleton3D) -> void:
	if player == null or skeleton == null:
		return
	var library: AnimationLibrary = player.get_animation_library("")
	if library == null:
		library = AnimationLibrary.new()
		player.add_animation_library("", library)
	if library.has_animation("idle") and library.has_animation("light_1"):
		return
	var prefix := _track_prefix(player)
	var ctx := _context(skeleton, prefix)
	# locomotion: the model's own Walking / Running clips (the Pawn's GLB also has more).
	_alias(library, "walk", "Walking")
	_alias(library, "run", "Running")
	_alias(library, "strafe_left", "Walking")
	_alias(library, "strafe_right", "Walking")
	# (the Pawn's own Fast_Ladder_Climb is wider than the 1 m shaft: every role climbs with the compact procedural clip below)
	var specs := _specs()
	for clip_name in specs:
		if library.has_animation(clip_name):
			continue
		var spec: Dictionary = specs[clip_name]
		var anim := _build(ctx, spec["keys"], float(spec["len"]), clip_name in LOOPING)
		library.add_animation(clip_name, anim)
	for clip_name in ["walk", "run", "strafe_left", "strafe_right", "climb"]:
		if library.has_animation(clip_name):
			library.get_animation(clip_name).loop_mode = Animation.LOOP_LINEAR


## Frees the cached model templates and textures (never in the tree) so a headless run exits without leaked-resource errors.
static func clear_caches() -> void:
	for key in PaladinModel._templates:
		var template = PaladinModel._templates[key]
		if is_instance_valid(template):
			template.free()
	PaladinModel._templates.clear()
	PaladinModel._textures.clear()


static func _alias(library: AnimationLibrary, to: String, source: String) -> void:
	if library.has_animation(to) or not library.has_animation(source):
		return
	library.add_animation(to, library.get_animation(source).duplicate())


static func _track_prefix(player: AnimationPlayer) -> String:
	for source in ["Walking", "Running"]:
		if player.has_animation(source):
			var anim := player.get_animation(source)
			if anim.get_track_count() > 0:
				var path := String(anim.track_get_path(0))
				return path.substr(0, path.find(":") + 1)
	return "Skeleton3D:"


static func _context(skeleton: Skeleton3D, prefix: String) -> Dictionary:
	var bones := {}
	for short in SHORT:
		var index := skeleton.find_bone("mixamorig_" + SHORT[short])
		if index >= 0:
			bones[short] = index
	var rest := []
	for i in skeleton.get_bone_count():
		var local := skeleton.get_bone_rest(i)
		var global := skeleton.get_bone_global_rest(i)
		rest.append({"name": skeleton.get_bone_name(i), "local": local, "lq": local.basis.orthonormalized().get_rotation_quaternion(),
				"gq": global.basis.orthonormalized().get_rotation_quaternion()})
	return {"prefix": prefix, "bones": bones, "rest": rest}


# ---- keyframe builder ----------------------------------------------------------------------------
## keys: [[t_seconds, hips_offset Vector3, pose {short bone: Vector3 degrees}], ...]; the first key is at 0, the last at `length`.
static func _build(ctx: Dictionary, keys: Array, length: float, loop: bool) -> Animation:
	var anim := Animation.new()
	anim.length = length
	anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var bones: Dictionary = ctx["bones"]
	var rest: Array = ctx["rest"]
	var index_of := {}
	for short in bones:
		index_of[bones[short]] = short
	for i in rest.size():
		var entry: Dictionary = rest[i]
		var track := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(track, NodePath(String(ctx["prefix"]) + String(entry["name"])))
		anim.track_set_interpolation_type(track, Animation.INTERPOLATION_LINEAR)
		var short: String = index_of.get(i, "")
		if short == "":
			anim.rotation_track_insert_key(track, 0.0, entry["lq"])
			continue
		for key in keys:
			var pose: Dictionary = key[2]
			var delta: Vector3 = pose.get(short, Vector3.ZERO)
			var d := Quaternion.from_euler(Vector3(deg_to_rad(delta.x), deg_to_rad(delta.y), deg_to_rad(delta.z)))
			var gq: Quaternion = entry["gq"]
			anim.rotation_track_insert_key(track, float(key[0]), (entry["lq"] * gq.inverse() * d * gq).normalized())
	if bones.has("Hips"):
		var hips_index: int = bones["Hips"]
		var track := anim.add_track(Animation.TYPE_POSITION_3D)
		anim.track_set_path(track, NodePath(String(ctx["prefix"]) + String(rest[hips_index]["name"])))
		var origin: Vector3 = (rest[hips_index]["local"] as Transform3D).origin
		for key in keys:
			anim.position_track_insert_key(track, float(key[0]), origin + (key[1] as Vector3))
	return anim


static func _mix(base: Dictionary, over: Dictionary) -> Dictionary:
	var out := base.duplicate()
	for k in over:
		out[k] = over[k]
	return out


static func _k(t: float, hips: Vector3, over: Dictionary) -> Array:
	return [t, hips, _mix(BASE, over)]


static func _specs() -> Dictionary:
	var z := Vector3.ZERO
	var specs := {}
	# --- idle: breathing, a slight weight shift -------------------------------------------------------------------------
	specs["idle"] = {"len": 2.6, "keys": [
		_k(0.0, z, {"Spine": Vector3(1, 0, 0), "Head": Vector3(0, 0, 0)}),
		_k(1.3, Vector3(0, 0.012, 0), {"Spine": Vector3(-1.5, 1, 0), "Spine2": Vector3(-1.5, 0, 0), "Head": Vector3(1, -2, 0), "LArm": Vector3(0, 0, -27), "RArm": Vector3(0, 0, 27)}),
		_k(2.6, z, {"Spine": Vector3(1, 0, 0), "Head": Vector3(0, 0, 0)})]}
	# --- light 1: horizontal slash right to left ------------------------------------------------------------------------
	var l1_wind := {"RArm": Vector3(-20, 0, -78), "RFore": Vector3(-75, 0, 0), "Spine": Vector3(-6, -24, 0), "Spine2": Vector3(0, -12, 0), "LArm": Vector3(-10, 0, -10), "LFore": Vector3(-50, 0, 0),
			"LUp": Vector3(10, 0, 0), "RUp": Vector3(-10, 0, 0)}
	var l1_hit := {"RArm": Vector3(-72, 0, -6), "RFore": Vector3(-12, 0, 0), "Spine": Vector3(6, 30, 0), "Spine2": Vector3(0, 14, 0), "LArm": Vector3(0, 0, -40), "LFore": Vector3(-20, 0, 0),
			"LUp": Vector3(-24, 0, 0), "RUp": Vector3(14, 0, 0), "LLeg": Vector3(22, 0, 0), "Head": Vector3(0, -8, 0)}
	var l1_follow := _mix(l1_hit, {"RArm": Vector3(-45, 0, 40), "Spine": Vector3(8, 40, 0), "Spine2": Vector3(0, 18, 0)})
	specs["light_1"] = {"len": 1.0, "keys": [_k(0.0, z, {}), _k(0.2, Vector3(0, -0.02, -0.04), l1_wind), _k(STRIKE, Vector3(0, -0.04, 0.12), l1_hit),
			_k(0.5, Vector3(0, -0.04, 0.14), l1_follow), _k(1.0, z, {})]}
	# --- light 2: thrust ---------------------------------------------------------------------------------------------------
	var l2_wind := {"RArm": Vector3(25, 0, -10), "RFore": Vector3(-100, 0, 0), "Spine": Vector3(-4, -14, 0), "LArm": Vector3(-30, 0, -20), "LFore": Vector3(-40, 0, 0), "RUp": Vector3(14, 0, 0), "LUp": Vector3(-12, 0, 0)}
	var l2_hit := {"RArm": Vector3(-88, 0, -8), "RFore": Vector3(-4, 0, 0), "Spine": Vector3(12, 12, 0), "LArm": Vector3(-20, 0, -30), "LFore": Vector3(-30, 0, 0),
			"LUp": Vector3(-38, 0, 0), "LLeg": Vector3(40, 0, 0), "RUp": Vector3(18, 0, 0), "RLeg": Vector3(8, 0, 0)}
	specs["light_2"] = {"len": 1.0, "keys": [_k(0.0, z, {}), _k(0.22, Vector3(0, -0.03, -0.05), l2_wind), _k(STRIKE, Vector3(0, -0.07, 0.24), l2_hit),
			_k(0.55, Vector3(0, -0.07, 0.24), l2_hit), _k(1.0, z, {})]}
	# --- light 3: rising backhand sweep ----------------------------------------------------------------------------------------
	var l3_wind := {"RArm": Vector3(24, 0, 34), "RFore": Vector3(-30, 0, 0), "Spine": Vector3(10, 18, 0), "RUp": Vector3(12, 0, 0), "LUp": Vector3(-14, 0, 0), "LLeg": Vector3(30, 0, 0)}
	var l3_hit := {"RArm": Vector3(-62, 0, -36), "RFore": Vector3(-14, 0, 0), "Spine": Vector3(-4, -30, 0), "Spine2": Vector3(0, -12, 0), "LUp": Vector3(-26, 0, 0), "LLeg": Vector3(30, 0, 0), "RUp": Vector3(10, 0, 0)}
	specs["light_3"] = {"len": 1.0, "keys": [_k(0.0, z, {}), _k(0.2, Vector3(0, -0.11, -0.03), l3_wind), _k(STRIKE, Vector3(0, -0.06, 0.14), l3_hit),
			_k(0.55, Vector3(0, -0.05, 0.14), _mix(l3_hit, {"RArm": Vector3(-95, 0, -20)})), _k(1.0, z, {})]}
	# --- heavy: overhead smash ------------------------------------------------------------------------------------------------
	var h_wind := {"RArm": Vector3(-165, 0, -22), "RFore": Vector3(-35, 0, 0), "LArm": Vector3(-150, 0, -8), "LFore": Vector3(-40, 0, 0), "Spine": Vector3(-16, 0, 0), "Spine2": Vector3(-8, 0, 0), "Head": Vector3(-8, 0, 0),
			"LUp": Vector3(10, 0, 0), "RUp": Vector3(-8, 0, 0)}
	var h_hit := {"RArm": Vector3(-55, 0, -8), "RFore": Vector3(-6, 0, 0), "LArm": Vector3(-50, 0, -6), "LFore": Vector3(-10, 0, 0), "Spine": Vector3(32, 0, 0), "Spine2": Vector3(10, 0, 0), "Head": Vector3(10, 0, 0),
			"LUp": Vector3(-42, 0, 0), "LLeg": Vector3(50, 0, 0), "RUp": Vector3(20, 0, 0), "RLeg": Vector3(10, 0, 0)}
	specs["heavy"] = {"len": 1.2, "keys": [_k(0.0, z, {}), _k(0.3, Vector3(0, 0.02, -0.06), h_wind), _k(STRIKE * 1.2, Vector3(0, -0.14, 0.26), h_hit),
			_k(0.62, Vector3(0, -0.14, 0.26), h_hit), _k(1.2, z, {})]}
	# --- block: guard up, small sway ---------------------------------------------------------------------------------------------
	var guard := {"RArm": Vector3(-60, 0, -12), "RFore": Vector3(-105, 0, 0), "LArm": Vector3(-55, 0, 16), "LFore": Vector3(-100, 0, 0), "Spine": Vector3(8, 0, 0), "Head": Vector3(6, 0, 0),
			"LUp": Vector3(-14, 0, 0), "LLeg": Vector3(22, 0, 0), "RUp": Vector3(10, 0, 0), "RLeg": Vector3(14, 0, 0)}
	specs["block"] = {"len": 1.4, "keys": [_k(0.0, Vector3(0, -0.05, 0.02), guard), _k(0.7, Vector3(0, -0.06, 0.02), _mix(guard, {"Spine": Vector3(9.5, 1, 0)})), _k(1.4, Vector3(0, -0.05, 0.02), guard)]}
	# --- parry: a sharp deflecting flick ----------------------------------------------------------------------------------------------
	specs["parry"] = {"len": 0.7, "keys": [_k(0.0, z, {}), _k(0.12, Vector3(0, -0.04, 0.0), _mix(guard, {"RArm": Vector3(-50, 0, -60), "RFore": Vector3(-60, 0, 0)})),
			_k(0.3, Vector3(0, -0.05, 0.08), _mix(guard, {"RArm": Vector3(-82, 0, 18), "RFore": Vector3(-20, 0, 0), "Spine": Vector3(4, 24, 0)})), _k(0.7, z, {})]}
	# --- dodge: duck low and lean away -----------------------------------------------------------------------------------------------
	var duck := {"Spine": Vector3(28, 0, 0), "Spine2": Vector3(10, 0, 0), "Head": Vector3(-14, 0, 0), "LUp": Vector3(-62, 0, 0), "LLeg": Vector3(84, 0, 0), "RUp": Vector3(-48, 0, 0), "RLeg": Vector3(70, 0, 0),
			"RArm": Vector3(-30, 0, 40), "LArm": Vector3(-30, 0, -40), "LFore": Vector3(-30, 0, 0), "RFore": Vector3(-30, 0, 0)}
	specs["dodge"] = {"len": 0.7, "keys": [_k(0.0, z, {}), _k(0.18, Vector3(0, -0.34, -0.05), duck), _k(0.45, Vector3(0, -0.3, -0.05), duck), _k(0.7, z, {})]}
	# --- stagger / hit reactions ----------------------------------------------------------------------------------------------------------
	var stag := {"Spine": Vector3(-20, 0, 8), "Spine2": Vector3(-8, 0, 0), "Head": Vector3(-24, 6, 0), "LArm": Vector3(-20, 0, -48), "RArm": Vector3(-20, 0, 48), "LFore": Vector3(-30, 0, 0), "RFore": Vector3(-30, 0, 0),
			"LUp": Vector3(14, 0, 0), "RUp": Vector3(-10, 0, 0), "LLeg": Vector3(14, 0, 0)}
	specs["stagger"] = {"len": 1.0, "keys": [_k(0.0, z, {}), _k(0.12, Vector3(0, -0.04, -0.12), stag), _k(0.5, Vector3(0, -0.05, -0.1), _mix(stag, {"Spine": Vector3(-14, 0, 6)})), _k(1.0, z, {})]}
	specs["hit_react_light"] = {"len": 0.5, "keys": [_k(0.0, z, {}), _k(0.08, Vector3(0, -0.01, -0.05), _mix(stag, {"Spine": Vector3(-10, 0, 4), "Head": Vector3(-12, 3, 0)})), _k(0.5, z, {})]}
	specs["hit_react_heavy"] = {"len": 0.7, "keys": [_k(0.0, z, {}), _k(0.1, Vector3(0, -0.05, -0.14), stag), _k(0.7, z, {})]}
	# --- ability: arms thrown up, then slammed down -------------------------------------------------------------------------------------------
	var a_up := {"RArm": Vector3(-170, 0, -30), "LArm": Vector3(-170, 0, 30), "RFore": Vector3(-20, 0, 0), "LFore": Vector3(-20, 0, 0), "Spine": Vector3(-16, 0, 0), "Head": Vector3(-14, 0, 0), "LUp": Vector3(8, 0, 0), "RUp": Vector3(-8, 0, 0)}
	var a_down := {"RArm": Vector3(-35, 0, -20), "LArm": Vector3(-35, 0, 20), "RFore": Vector3(-30, 0, 0), "LFore": Vector3(-30, 0, 0), "Spine": Vector3(30, 0, 0), "Head": Vector3(12, 0, 0), "LUp": Vector3(-44, 0, 0), "LLeg": Vector3(60, 0, 0), "RUp": Vector3(-30, 0, 0), "RLeg": Vector3(46, 0, 0)}
	specs["ability"] = {"len": 1.4, "keys": [_k(0.0, z, {}), _k(0.4, Vector3(0, 0.03, 0), a_up), _k(0.6, Vector3(0, -0.2, 0.08), a_down), _k(0.85, Vector3(0, -0.2, 0.08), a_down), _k(1.4, z, {})]}
	# --- defeat: collapse and stay down; victory: weapon arm raised --------------------------------------------------------------------------------
	var down := {"Spine": Vector3(46, 0, 0), "Spine2": Vector3(16, 0, 0), "Head": Vector3(28, 0, 0), "LUp": Vector3(-96, 0, 6), "LLeg": Vector3(112, 0, 0), "RUp": Vector3(-72, 0, -8), "RLeg": Vector3(100, 0, 0),
			"LArm": Vector3(10, 0, -34), "RArm": Vector3(10, 0, 34), "LFore": Vector3(-10, 0, 0), "RFore": Vector3(-10, 0, 0), "LFoot": Vector3(-20, 0, 0), "RFoot": Vector3(-20, 0, 0)}
	specs["defeat"] = {"len": 1.1, "keys": [_k(0.0, z, {}), _k(0.28, Vector3(0, -0.28, -0.1), _mix(stag, {"LLeg": Vector3(50, 0, 0), "RLeg": Vector3(50, 0, 0)})), _k(1.1, Vector3(0, -0.66, -0.08), down)]}
	var vic := {"RArm": Vector3(-30, 0, -150), "RFore": Vector3(-20, 0, 0), "LArm": Vector3(0, 0, -20), "Spine": Vector3(-6, 0, 0), "Head": Vector3(-10, 0, 0)}
	specs["victory"] = {"len": 1.2, "keys": [_k(0.0, z, {}), _k(0.5, Vector3(0, 0.03, 0), vic), _k(1.2, Vector3(0, 0.02, 0), vic)]}
	# --- pit: ladder ------------------------------------------------------------------------------------------------------------------------------
	var up_a := {"RArm": Vector3(-160, 0, 16), "RFore": Vector3(-30, 0, 0), "LArm": Vector3(-105, 0, 26), "LFore": Vector3(-70, 0, 0), "LUp": Vector3(-70, 0, 0), "LLeg": Vector3(80, 0, 0), "RUp": Vector3(6, 0, 0), "Spine": Vector3(8, 0, 0)}
	var up_b := {"LArm": Vector3(-160, 0, -16), "LFore": Vector3(-30, 0, 0), "RArm": Vector3(-105, 0, -26), "RFore": Vector3(-70, 0, 0), "RUp": Vector3(-70, 0, 0), "RLeg": Vector3(80, 0, 0), "LUp": Vector3(6, 0, 0), "Spine": Vector3(8, 0, 0)}
	specs["climb"] = {"len": 0.8, "keys": [_k(0.0, Vector3(0, 0, 0.1), up_a), _k(0.4, Vector3(0, 0.04, 0.1), up_b), _k(0.8, Vector3(0, 0, 0.1), up_a)]}
	specs["ladder_idle"] = {"len": 2.0, "keys": [_k(0.0, Vector3(0, 0, 0.1), up_a), _k(1.0, Vector3(0, 0.01, 0.1), _mix(up_a, {"Spine": Vector3(6, 0, 0)})), _k(2.0, Vector3(0, 0, 0.1), up_a)]}
	var fall_a := {"RArm": Vector3(-120, 0, -60), "LArm": Vector3(-120, 0, 60), "RFore": Vector3(-20, 0, 0), "LFore": Vector3(-20, 0, 0), "Spine": Vector3(-6, 0, 0), "LUp": Vector3(-20, 0, 12), "RUp": Vector3(-10, 0, -12), "LLeg": Vector3(30, 0, 0), "RLeg": Vector3(20, 0, 0)}
	specs["drop_fall"] = {"len": 0.8, "keys": [_k(0.0, z, fall_a), _k(0.4, Vector3(0, 0.02, 0), _mix(fall_a, {"RArm": Vector3(-130, 0, -50), "LArm": Vector3(-110, 0, 70)})), _k(0.8, z, fall_a)]}
	return specs
