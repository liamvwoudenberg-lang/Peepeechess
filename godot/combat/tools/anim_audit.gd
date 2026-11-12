extends SceneTree
## Animation integrity audit for the six fighter classes (LOD0 + LOD1), run through the REAL CharacterModel /
## AnimationPlayer. Measures numbers and returns them (JSON); nothing here edits an asset.
##
##   godot --headless --path godot --script res://combat/tools/anim_audit.gd -- \
##       [--out res://assets/combat/manifest/animation_audit.json] [--md path.md] [--classes pawn,knight] \
##       [--lod 0|1|both] [--no-runtime] [--no-blends] [--assets DIR/characters   (a scratch build: build_all.py --out DIR)]
##
## Groups (the letters match ANIMATION_INTEGRITY.md):
##   a  coverage / silent fallbacks      every clip the game can request exists and resolves to itself
##   b  timing vs frame data             clip length vs sim ticks, weapon contact vs the active window, reach, anticipation, recovery
##   c  loops                            seam delta of the looping clips vs the mean per-frame delta
##   d  skeleton sanity                  finite values, bone lengths, rotation pops, joint limits, root motion, foot slide, ground
##   e  weapons / sockets                socket nodes, props stay on the hand, no deep body intersection
##   f  LOD parity                       LOD1 has the same clips, lengths, sockets and poses as LOD0
##   g  blends                           pose delta at the boundary of the common transitions, given CharacterModel.blend_time
##   h  runtime                          real seeded AI-vs-AI fights through the presentation (anim_audit_runtime.gd)
##
## Every measurement is by sampling the AnimationPlayer (seek + advance(0), then the Skeleton3D pose), never by reading the
## Blender sources. Frame-time facts: 60 fps, one animation frame == one simulation tick.

const Balance := preload("res://combat/data/balance_data.gd")

const CLASSES := ["pawn", "knight", "bishop", "rook", "queen", "king"]
const ROLE := {"pawn": "p", "knight": "n", "bishop": "b", "rook": "r", "queen": "q", "king": "k"}
const FPS := 60.0
const SEVERITY_ORDER := {"high": 0, "medium": 1, "low": 2}

## Every threshold in one place; the JSON report embeds this table.
const TH := {
	"length_tol_frames": 1.0,          # clip frames vs the sim's ticks of the attack that plays it (b)
	"length_tol_frames_loose": 6.0,    # shared clips played for a differently timed link (Queen 3/4/5)
	"speed_ratio_min": 0.75,           # runtime playback rate of a time-driven clip stays within this band ...
	"speed_ratio_max": 1.35,           # ... (clip length / sim ticks), else the clip visibly drags or rushes
	"contact_tol_ticks": 3,            # weapon peak speed must fall inside the active window +- this many ticks
	"reach_min_ratio": 0.80,           # max horizontal tip distance in the active window / sim reach
	"reach_max_over_m": 1.10,          # ... and not more than reach + this
	"anticipation_min_ratio": 0.12,    # wind-up draw-back (against the strike direction) / strike travel
	"anticipation_min_m": 0.08,
	"recovery_rms_deg": 6.0,           # pose distance of the last frame from the ready pose
	"loop_seam_ratio": 2.0,            # seam step / mean step
	"loop_seam_abs_deg": 4.0,          # ... unless the seam step is below this many degrees RMS
	"loop_closure_deg": 1.0,           # last key == first key (RMS degrees)
	"bone_len_drift": 0.01,
	"step_cap_deg": 75.0,              # one bone, one frame (a fast strike is sustained, see pop_min_deg for isolated jumps)
	"pop_min_deg": 18.0,               # an isolated one-frame jump at least this big (and 3x its neighbours) is a pop
	"knee_min_deg": -4.0,
	"knee_max_deg": 150.0,
	"elbow_max_deg": 155.0,
	"hips_xz_loco_m": 0.05,            # horizontal Hips excursion in a loop clip (root motion stripped)
	"hips_xz_attack_m": 0.75,
	"loop_drift_m": 0.004,
	"ground_pen_m": 0.03,
	"foot_slide_ratio": 0.15,          # implied clip speed vs nominal ground speed (|ratio - 1|)
	"foot_slide_mps": 0.45,            # worst stance-foot velocity error (m/s)
	"idle_foot_move_m": 0.03,
	"grip_dist_m": 0.14,
	"offhand_shaft_m": 0.12,
	"shield_dist_m": 0.45,
	"body_pen_m": 0.10,
	"weapon_ground_m": 0.12,
	"blend_rate_deg": 7.0,             # RMS pose delta per frame while the cross-fade runs
	"blend_rate_reaction_deg": 14.0,   # ... when the target is a reaction / defensive snap (stagger, hit reaction, parry, dodge)
	"lod_pose_m": 0.002,
}

const GROUNDED_SKIP := ["dodge", "defeat", "drop_fall", "climb", "ladder_idle", "land", "victory"]
const LOOPS := ["idle", "walk", "run", "strafe_left", "strafe_right", "block", "ladder_idle", "climb", "drop_fall"]
const LOCO_DIR := {"walk": Vector3(0, 0, 1), "run": Vector3(0, 0, 1), "strafe_left": Vector3(1, 0, 0), "strafe_right": Vector3(-1, 0, 0)}
const EXPECT_PROPS := {
	"pawn": {"WeaponSocket_R": "Pawn_Spear"},
	"knight": {"WeaponSocket_R": "Knight_Sword", "ShieldSocket_L": "Knight_Shield"},
	"bishop": {"WeaponSocket_R": "Bishop_Staff"},
	"rook": {"WeaponSocket_R": "Rook_Warhammer", "ShieldSocket_L": "Rook_TowerShield"},
	"queen": {"WeaponSocket_R": "Queen_Blade_R", "WeaponSocket_L": "Queen_Blade_L"},
	"king": {"WeaponSocket_R": "King_Longsword"},
}
const SOCKET_BONES := ["WeaponSocket_R", "WeaponSocket_L", "ShieldSocket_L", "BackSocket", "HeadTop"]
const NON_POSE := ["Root", "WeaponSocket_R", "WeaponSocket_L", "ShieldSocket_L", "BackSocket", "HeadTop"]


# =============================================================================================================
# Rig: one loaded CharacterModel plus cached skeleton facts
# =============================================================================================================
class Rig extends RefCounted:
	var cls: String = ""
	var role: String = ""
	var lod: int = 0
	var cm: CharacterModel
	var holder: Node3D
	var sk: Skeleton3D
	var player: AnimationPlayer
	var nb: int = 0
	var names: PackedStringArray = PackedStringArray()
	var idx: Dictionary = {}
	var pose_bones: Array = []
	var rest_g: Array = []
	var to_model: Transform3D = Transform3D.IDENTITY
	var props: Array = []
	var torso: Dictionary = {}
	var clips: Dictionary = {}          # clip -> Array of frame snapshots (0..n inclusive)
	var scale_k: float = 1.0
	var sole_ready: bool = false
	var sole: Dictionary = {}

	func b(bone_name: String) -> int:
		return int(idx.get(bone_name, -1))

	func free_all() -> void:
		if holder != null and is_instance_valid(holder):
			holder.get_parent().remove_child(holder)
			holder.free()
		holder = null


static func make_rig(tree: SceneTree, cls: String, lod: int) -> Rig:
	var rig := Rig.new()
	rig.cls = cls
	rig.role = ROLE[cls]
	rig.lod = lod
	rig.holder = Node3D.new()
	tree.root.add_child(rig.holder)
	rig.cm = CharacterModel.new()
	rig.holder.add_child(rig.cm)
	if not rig.cm.setup_free(rig.role, lod):
		rig.free_all()
		return null
	rig.sk = rig.cm.skeleton
	rig.player = rig.cm.player
	if rig.sk == null or rig.player == null:
		rig.free_all()
		return null
	rig.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	rig.nb = rig.sk.get_bone_count()
	rig.to_model = rig.cm.global_transform.affine_inverse() * rig.sk.global_transform
	for i in rig.nb:
		var n := rig.sk.get_bone_name(i)
		rig.names.append(n)
		rig.idx[n] = i
		if not (n in NON_POSE):
			rig.pose_bones.append(i)
		rig.rest_g.append(rig.to_model * rig.sk.get_bone_global_rest(i))
	rig.scale_k = rig.sk.get_bone_global_rest(rig.b("Hips")).origin.y / 0.95
	_collect_props(rig)
	_measure_torso(rig)
	return rig


static func _collect_props(rig: Rig) -> void:
	for att in rig.sk.find_children("*", "BoneAttachment3D", true, false):
		for child in att.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = child
			var xf := Transform3D.IDENTITY
			var n: Node = mi
			while n != att and n != null:
				xf = (n as Node3D).transform * xf
				n = n.get_parent()
			var box := mi.get_aabb()
			var axis := 0
			for i in 3:
				if box.size[i] > box.size[axis]:
					axis = i
			var a := box.get_center()
			var c := box.get_center()
			a[axis] = box.position[axis]
			c[axis] = box.position[axis] + box.size[axis]
			var bone_i: int = rig.b(String(att.bone_name))
			var rest: Transform3D = rig.rest_g[bone_i]
			var hand: Vector3 = (rig.rest_g[rig.b("RightHand" if String(att.bone_name).ends_with("_R") else "LeftHand")] as Transform3D).origin
			if String(att.bone_name) == "ShieldSocket_L":
				hand = (rig.rest_g[rig.b("LeftLowerArm")] as Transform3D).origin
			var pa: Vector3 = rest * (xf * a)
			var pc: Vector3 = rest * (xf * c)
			var grip: Vector3 = a
			var tip: Vector3 = c
			if pc.distance_to(hand) < pa.distance_to(hand):
				grip = c
				tip = a
			var corners: Array = []
			for k in 8:
				corners.append(box.get_endpoint(k))
			rig.props.append({"name": String(mi.name), "bone": String(att.bone_name), "bi": bone_i, "xf": xf, "aabb": box,
					"grip": grip, "tip": tip, "length": box.size[axis], "shield": String(mi.name).contains("Shield"), "corners": corners})


## Torso half extents (x = side, z = depth) from the rest-pose body vertices skinned mostly to Spine/Chest/UpperChest.
static func _measure_torso(rig: Rig) -> void:
	var xs: Array = []
	var zs: Array = []
	var ys: Array = []
	var torso_names := ["Spine", "Chest", "UpperChest"]
	for mi_n in rig.cm.model.find_children("*Body*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = mi_n
		var skin: Skin = mi.skin
		if skin == null:
			continue
		var bind_names: Array = []
		for k in skin.get_bind_count():
			bind_names.append(String(skin.get_bind_name(k)))
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			if bones.size() < verts.size() * 4:
				continue
			for v in verts.size():
				var w_torso := 0.0
				for j in 4:
					var bi: int = bones[v * 4 + j]
					if bi >= 0 and bi < bind_names.size() and bind_names[bi] in torso_names:
						w_torso += weights[v * 4 + j]
				if w_torso > 0.6:
					xs.append(absf(verts[v].x))
					zs.append(absf(verts[v].z))
					ys.append(verts[v].y)
	if xs.is_empty():
		rig.torso = {"a": 0.20 * rig.scale_k, "b": 0.14 * rig.scale_k, "vertices": 0}
		return
	xs.sort()
	zs.sort()
	rig.torso = {"a": xs[int(xs.size() * 0.8)], "b": zs[int(zs.size() * 0.8)], "vertices": xs.size()}


# =============================================================================================================
# Sampling
# =============================================================================================================
static func snap(rig: Rig) -> Dictionary:
	var q: Array = []
	var gx: Array = []
	for i in rig.nb:
		q.append(rig.sk.get_bone_pose_rotation(i))
		gx.append(rig.to_model * rig.sk.get_bone_global_pose(i))
	return {"q": q, "gx": gx, "hips": rig.sk.get_bone_pose_position(rig.b("Hips")), "root": rig.sk.get_bone_pose_position(rig.b("Root"))}


## Local bone rotations of a CharacterModel's skeleton as it is right now.
static func snap_node(m: CharacterModel) -> Array:
	var out: Array = []
	if m.skeleton == null:
		return out
	for i in m.skeleton.get_bone_count():
		out.append(m.skeleton.get_bone_pose_rotation(i))
	return out


static func clip_frames(rig: Rig, clip: String) -> int:
	return roundi(rig.player.get_animation(clip).length * FPS)


## Poses at frames 0..n (inclusive) of a clip, looping disabled while sampling so the final key is reachable.
static func sample_clip(rig: Rig, clip: String) -> Array:
	if rig.clips.has(clip):
		return rig.clips[clip]
	var anim := rig.player.get_animation(clip)
	var old := anim.loop_mode
	anim.loop_mode = Animation.LOOP_NONE
	var out: Array = []
	var n := clip_frames(rig, clip)
	rig.player.play(clip, 0.0)
	for f in n + 1:
		rig.player.seek(minf(float(f) / FPS, anim.length), true)
		rig.player.advance(0.0)
		out.append(snap(rig))
	rig.player.stop()
	anim.loop_mode = old
	rig.clips[clip] = out
	return out


static func pose_at(rig: Rig, clip: String, t: float) -> Dictionary:
	var anim := rig.player.get_animation(clip)
	var old := anim.loop_mode
	anim.loop_mode = Animation.LOOP_NONE
	rig.player.play(clip, 0.0)
	rig.player.seek(clampf(t, 0.0, anim.length), true)
	rig.player.advance(0.0)
	var out := snap(rig)
	anim.loop_mode = old
	return out


## RMS (over the deform bones) of the rotation difference between two snapshots, in degrees.
static func pose_dist(rig: Rig, a: Dictionary, b: Dictionary) -> float:
	var sum := 0.0
	for i in rig.pose_bones:
		var ang := rad_to_deg((a["q"][i] as Quaternion).angle_to(b["q"][i]))
		sum += ang * ang
	return sqrt(sum / float(rig.pose_bones.size()))


static func prop_point(rig: Rig, s: Dictionary, prop: Dictionary, local_point: Vector3) -> Vector3:
	var bone_xf: Transform3D = s["gx"][prop["bi"]]
	return bone_xf * ((prop["xf"] as Transform3D) * local_point)


static func tip_of(rig: Rig, s: Dictionary, prop: Dictionary) -> Vector3:
	return prop_point(rig, s, prop, prop["tip"])


static func hand_of(rig: Rig, s: Dictionary, side: String) -> Vector3:
	return (s["gx"][rig.b(side + "Hand")] as Transform3D).origin


static func _horiz(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


static func _r(x: float, digits: int = 4) -> float:
	var m := pow(10.0, digits)
	return snappedf(x, 1.0 / m)


static func _finite(v: Variant) -> bool:
	if v is float:
		return is_finite(v)
	if v is Vector3:
		return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)
	if v is Quaternion:
		return is_finite(v.x) and is_finite(v.y) and is_finite(v.z) and is_finite(v.w)
	return true


# =============================================================================================================
# Report plumbing
# =============================================================================================================
static func new_report() -> Dictionary:
	return {"schema": 1, "thresholds": TH, "classes": {}, "coverage": {}, "lod_parity": {}, "blends": {}, "runtime": {},
			"checks": {}, "findings": []}


## Records one check. Failures become findings (kept in the report); passes are only counted.
static func check(rep: Dictionary, group: String, cls: String, lod: int, clip: String, name: String, ok: bool,
		value: Variant, limit: Variant, severity: String, detail: String = "") -> bool:
	var key := "%s/%s" % [group, cls]
	var counts: Dictionary = rep["checks"].get(key, {"pass": 0, "fail": 0})
	if ok:
		counts["pass"] = int(counts["pass"]) + 1
	else:
		counts["fail"] = int(counts["fail"]) + 1
		var v: Variant = _r(value) if value is float else value
		var l: Variant = _r(limit) if limit is float else limit
		rep["findings"].append({"group": group, "class": cls, "lod": lod, "clip": clip, "check": name, "severity": severity,
				"value": v, "limit": l, "detail": detail})
	rep["checks"][key] = counts
	return ok


# =============================================================================================================
# Frame data (the authoritative simulation numbers)
# =============================================================================================================
## Attack rows for one class: [{id, def, clip, total, a0, a1, cancel, index, kind, reach, arc}] straight from AttackLibrary
## with the stats the authority would send (FighterRoster / the approved c0 snapshot).
static func attack_rows(cls: String) -> Array:
	var role: String = ROLE[cls]
	var stats := FighterRoster.stats_for(role)
	var tables := AttackLibrary.for_role(role)
	var rows: Array = []
	if tables.is_empty():
		return rows
	var lights: Array = tables["light"]
	for i in lights.size():
		rows.append(_row(lights[i], i, stats))
	rows.append(_row(tables["heavy"], -1, stats))
	for id in tables["abilities"]:
		rows.append(_row(tables["abilities"][id], -1, stats))
	return rows


static func _row(def: AttackDefinition, index: int, stats: Dictionary) -> Dictionary:
	var total := def.total_ticks(stats, 1.0)
	var win := def.active_window(total)
	return {"id": def.id, "def": def, "index": index, "clip": CharacterModel.attack_clip(def, index), "total": total,
			"a0": win.x, "a1": win.y, "cancel": def.cancel_tick(total), "kind": def.kind, "animation": def.animation,
			"reach": float(stats["reachM"]) * def.reach_mult, "arc": def.arc_degrees, "stats": stats}


static func warp_p_for(def: AttackDefinition) -> float:
	if def.kind == AttackDefinition.Kind.HEAVY:
		return CharacterModel.ANTICIPATION_HEAVY
	if def.kind == AttackDefinition.Kind.LIGHT:
		return CharacterModel.ANTICIPATION_LIGHT
	return 1.0


## Clip time (seconds) the CharacterModel shows at sim tick `t` of an attack of `total` ticks (alpha = 0).
static func clip_time_at_tick(row: Dictionary, length: float, t: float) -> float:
	var def: AttackDefinition = row["def"]
	var u := clampf(t / float(row["total"]), 0.0, 1.0)
	var wp := CharacterModel.warp_progress(u, def.startup_end, warp_p_for(def))
	var start := CharacterModel.span_start(def)
	return minf(start + wp.x * (length - start), length)


# =============================================================================================================
# Per-class static audit
# =============================================================================================================
static func audit_class(tree: SceneTree, cls: String, lod: int, rep: Dictionary, opts: Dictionary = {}) -> Rig:
	var rig := make_rig(tree, cls, lod)
	var entry: Dictionary = rep["classes"].get(cls, {})
	var key := "lod%d" % lod
	if rig == null:
		check(rep, "a", cls, lod, "", "model loads", false, 0, 1, "high", "CharacterModel could not load the GLB")
		entry[key] = {"loaded": false}
		rep["classes"][cls] = entry
		return null
	var res := {"loaded": true, "clips": {}, "attacks": {}, "props": {}, "torso": {"a": _r(rig.torso["a"]), "b": _r(rig.torso["b"])}}
	_coverage(rep, rig, res)
	var clip_list: Array = rig.player.get_animation_list()
	clip_list.sort()
	for clip in clip_list:
		sample_clip(rig, clip)
	for clip in clip_list:
		res["clips"][clip] = _clip_metrics(rep, rig, clip)
	_props_audit(rep, rig, res)
	if lod == 0 or bool(opts.get("attacks_lod1", true)):
		_attack_audit(rep, rig, res)
	entry[key] = res
	rep["classes"][cls] = entry
	return rig


# ---- (a) coverage -------------------------------------------------------------------------------------------
static func _coverage(rep: Dictionary, rig: Rig, res: Dictionary) -> void:
	var cls := rig.cls
	var required: Array = []
	for c in CharacterModel.REQUIRED_CLIPS:
		required.append(c)
	for c in ["victory", "hit_react_light", "hit_react_heavy", "climb", "ladder_idle", "drop_fall", "land"]:
		required.append(c)
	for c in CharacterModel.LOOPING:
		if not (c in required):
			required.append(c)
	var missing: Array = []
	for c in required:
		if not check(rep, "a", cls, rig.lod, c, "clip exists", rig.player.has_animation(c), 0, 1, "high", "clip '%s' missing" % c):
			missing.append(c)
	# Every attack the simulation can start resolves to a clip that exists AND that the attack's tag names.
	var subs: Array = []
	for row in attack_rows(cls):
		var def: AttackDefinition = row["def"]
		var want: String = String(CharacterModel.ANIMATION_CLIP.get(def.animation, ""))
		if def.kind == AttackDefinition.Kind.HEAVY:
			want = "heavy"
		var played: String = row["clip"]
		var exists := rig.player.has_animation(played)
		check(rep, "a", cls, rig.lod, played, "attack %s resolves to an existing clip" % def.id, exists, 0, 1, "high")
		var intended_ok := want == "" or want == played or (def.kind == AttackDefinition.Kind.ABILITY and played == "ability")
		if not check(rep, "a", cls, rig.lod, played, "attack %s plays the clip its tag '%s' names" % [def.id, def.animation], intended_ok, played, want, "medium",
				"substitute clip: %s plays '%s' but the tag wants '%s'" % [def.id, played, want]):
			subs.append("%s:%s->%s" % [def.id, want, played])
	res["coverage"] = {"required": required.size(), "missing": missing, "substitutes": subs}


# ---- (c)(d) per clip ----------------------------------------------------------------------------------------
static func _clip_metrics(rep: Dictionary, rig: Rig, clip: String) -> Dictionary:
	var cls := rig.cls
	var lod := rig.lod
	var frames: Array = rig.clips[clip]
	var n: int = frames.size() - 1
	var m := {"frames": n}
	# finite + normalised
	var finite := true
	var worst_norm := 0.0
	for s in frames:
		for q in s["q"]:
			finite = finite and _finite(q)
			worst_norm = maxf(worst_norm, absf((q as Quaternion).length() - 1.0))
		for g in s["gx"]:
			finite = finite and _finite((g as Transform3D).origin)
	check(rep, "d", cls, lod, clip, "finite values", finite, 0, 1, "high")
	check(rep, "d", cls, lod, clip, "normalised quaternions", worst_norm < 1e-3, worst_norm, 1e-3, "high")
	m["quat_norm_err"] = _r(worst_norm, 6)
	if not finite:
		return m
	# bone lengths (drift vs rest), only along real joints
	var drift := 0.0
	for i in rig.nb:
		var p: int = rig.sk.get_bone_parent(i)
		if p < 0:
			continue
		if rig.names[i] in ["Root", "Hips"]:   # Hips translates (bob/sway/lunge) so its distance to Root is not a bone length
			continue
		var rest_len: float = ((rig.rest_g[i] as Transform3D).origin - (rig.rest_g[p] as Transform3D).origin).length()
		if rest_len < 0.03:
			continue
		for s in frames:
			var l: float = ((s["gx"][i] as Transform3D).origin - (s["gx"][p] as Transform3D).origin).length()
			drift = maxf(drift, absf(l / rest_len - 1.0))
	m["bone_len_drift"] = _r(drift, 5)
	check(rep, "d", cls, lod, clip, "bone lengths preserved", drift <= TH["bone_len_drift"], drift, TH["bone_len_drift"], "high")
	# rotation pops: an isolated one-frame jump of a bone (step >= 3x both neighbouring steps and >= pop_min_deg). Fast strikes are
	# sustained high angular speed (several consecutive big steps) and are NOT pops; their peak speed is reported separately.
	var worst_step := 0.0
	var worst_bone := ""
	var worst_frame := 0
	var pop_step := 0.0
	var pop_bone := ""
	var pop_frame := 0
	var steps: Array = []
	for i in rig.nb:
		steps.append(PackedFloat32Array())
	for i in rig.pose_bones:
		var arr := PackedFloat32Array()
		for f in n:
			arr.append(rad_to_deg((frames[f]["q"][i] as Quaternion).angle_to(frames[f + 1]["q"][i])))
		steps[i] = arr
		for f in n:
			var st: float = arr[f]
			if st > worst_step:
				worst_step = st
				worst_bone = rig.names[i]
				worst_frame = f
			var left: float = arr[f - 1] if f > 0 else arr[f + 1] if f + 1 < n else 0.0
			var right: float = arr[f + 1] if f + 1 < n else arr[f - 1] if f > 0 else 0.0
			if st >= TH["pop_min_deg"] and st >= 3.0 * maxf(left, right) and st > pop_step:
				pop_step = st
				pop_bone = rig.names[i]
				pop_frame = f
	m["max_step_deg"] = _r(worst_step, 2)
	m["max_step_bone"] = worst_bone
	m["max_step_frame"] = worst_frame
	m["pop_deg"] = _r(pop_step, 2)
	m["pop_bone"] = pop_bone
	m["pop_frame"] = pop_frame
	check(rep, "d", cls, lod, clip, "no isolated rotation pops", pop_step <= 0.0, pop_step, TH["pop_min_deg"], "medium", "%s at frame %d" % [pop_bone, pop_frame])
	check(rep, "d", cls, lod, clip, "no extreme per-frame rotation step", worst_step <= TH["step_cap_deg"], worst_step, TH["step_cap_deg"], "low", "%s at frame %d" % [worst_bone, worst_frame])
	# quaternion sign flips between consecutive imported keys: informational only (Godot slerps the short way, so a flipped sign is not a pop)
	var flips := _key_sign_flips(rig.player.get_animation(clip))
	m["key_sign_flips"] = flips
	# translation tracks only on Hips / Root; no scale tracks
	var anim := rig.player.get_animation(clip)
	var bad_tracks := 0
	var root_move := 0.0
	for t in anim.get_track_count():
		var kind := anim.track_get_type(t)
		var path := String(anim.track_get_path(t))
		if kind == Animation.TYPE_SCALE_3D:
			bad_tracks += 1
		elif kind == Animation.TYPE_POSITION_3D:
			if not (path.ends_with(":Hips") or path.ends_with(":Root")):
				bad_tracks += 1
			if path.ends_with(":Root"):
				for k in anim.track_get_key_count(t):
					root_move = maxf(root_move, (anim.track_get_key_value(t, k) as Vector3).length())
	check(rep, "d", cls, lod, clip, "only Hips/Root translate, no scale tracks", bad_tracks == 0, bad_tracks, 0, "high")
	m["root_track_m"] = _r(root_move)
	# root motion: Hips horizontal excursion from the rest position, loop drift
	var hips_rest: Vector3 = (rig.rest_g[rig.b("Hips")] as Transform3D).origin
	var xz_max := 0.0
	for s in frames:
		var o: Vector3 = (s["gx"][rig.b("Hips")] as Transform3D).origin
		xz_max = maxf(xz_max, Vector2(o.x - hips_rest.x, o.z - hips_rest.z).length())
	m["hips_xz_max_m"] = _r(xz_max)
	var is_loop := clip in LOOPS
	if clip in ["idle", "walk", "run", "strafe_left", "strafe_right", "block", "hit_react_light", "hit_react_heavy", "stagger", "parry"]:
		check(rep, "d", cls, lod, clip, "root motion stripped (Hips excursion)", xz_max <= TH["hips_xz_loco_m"] if is_loop else xz_max <= TH["hips_xz_attack_m"], xz_max,
				TH["hips_xz_loco_m"] if is_loop else TH["hips_xz_attack_m"], "medium")
	elif clip in ["light_1", "light_2", "light_3", "heavy", "ability"]:
		check(rep, "d", cls, lod, clip, "Hips travel within body-lean range", xz_max <= TH["hips_xz_attack_m"], xz_max, TH["hips_xz_attack_m"], "low")
	if is_loop:
		var a: Vector3 = (frames[0]["gx"][rig.b("Hips")] as Transform3D).origin
		var z: Vector3 = (frames[n]["gx"][rig.b("Hips")] as Transform3D).origin
		var drift_xz := Vector2(z.x - a.x, z.z - a.z).length()
		m["loop_drift_m"] = _r(drift_xz, 5)
		check(rep, "d", cls, lod, clip, "no net root drift over a loop", drift_xz <= TH["loop_drift_m"], drift_xz, TH["loop_drift_m"], "medium")
		_loop_metrics(rep, rig, clip, frames, m)
	_joint_metrics(rep, rig, clip, frames, m)
	if not (clip in GROUNDED_SKIP):
		_ground_metrics(rep, rig, clip, frames, m)
	if clip in LOCO_DIR:
		_foot_slide(rep, rig, clip, frames, m)
	if clip in ["idle", "block"]:
		_foot_planted(rep, rig, clip, frames, m)
	return m


static func _key_sign_flips(anim: Animation) -> int:
	var flips := 0
	for t in anim.get_track_count():
		if anim.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		var prev := Quaternion.IDENTITY
		for k in anim.track_get_key_count(t):
			var q: Quaternion = anim.track_get_key_value(t, k)
			if k > 0 and prev.dot(q) < 0.0:
				flips += 1
			prev = q
	return flips


static func _loop_metrics(rep: Dictionary, rig: Rig, clip: String, frames: Array, m: Dictionary) -> void:
	var n: int = frames.size() - 1
	# displayed sequence of a LOOP_LINEAR clip is frames 0..n-1 then 0 again: seam = d(n-1 -> 0)
	var total := 0.0
	for f in n - 2:
		total += pose_dist(rig, frames[f], frames[f + 1])
	var mean_step := total / float(maxi(n - 2, 1))
	var seam := pose_dist(rig, frames[n - 1], frames[0])
	var closure := pose_dist(rig, frames[n], frames[0])
	m["loop_seam_deg"] = _r(seam, 3)
	m["loop_mean_step_deg"] = _r(mean_step, 3)
	m["loop_closure_deg"] = _r(closure, 3)
	var ok: bool = seam <= maxf(mean_step * TH["loop_seam_ratio"], TH["loop_seam_abs_deg"])
	check(rep, "c", rig.cls, rig.lod, clip, "seamless loop (seam step vs mean step)", ok, seam, maxf(mean_step * TH["loop_seam_ratio"], TH["loop_seam_abs_deg"]), "medium",
			"seam %.2f deg vs mean step %.2f deg" % [seam, mean_step])
	check(rep, "c", rig.cls, rig.lod, clip, "last key equals first key", closure <= TH["loop_closure_deg"], closure, TH["loop_closure_deg"], "low")


static func _joint_metrics(rep: Dictionary, rig: Rig, clip: String, frames: Array, m: Dictionary) -> void:
	var knee_min := 999.0
	var knee_max := -999.0
	var elbow_max := 0.0
	var hips_i := rig.b("Hips")
	for s in frames:
		var hips_delta: Basis = (s["gx"][hips_i] as Transform3D).basis * (rig.rest_g[hips_i] as Transform3D).basis.inverse()
		var inv := hips_delta.inverse()
		for side in ["Left", "Right"]:
			var hip: Vector3 = (s["gx"][rig.b(side + "UpperLeg")] as Transform3D).origin
			var knee: Vector3 = (s["gx"][rig.b(side + "LowerLeg")] as Transform3D).origin
			var ankle: Vector3 = (s["gx"][rig.b(side + "Foot")] as Transform3D).origin
			var d1: Vector3 = inv * (knee - hip)
			var d2: Vector3 = inv * (ankle - knee)
			var flex := rad_to_deg(atan2(d1.z, -d1.y) - atan2(d2.z, -d2.y))
			knee_min = minf(knee_min, flex)
			knee_max = maxf(knee_max, flex)
		for side in ["Left", "Right"]:
			var sh: Vector3 = (s["gx"][rig.b(side + "UpperArm")] as Transform3D).origin
			var el: Vector3 = (s["gx"][rig.b(side + "LowerArm")] as Transform3D).origin
			var wr: Vector3 = (s["gx"][rig.b(side + "Hand")] as Transform3D).origin
			elbow_max = maxf(elbow_max, rad_to_deg((el - sh).normalized().angle_to((wr - el).normalized())))
	m["knee_flex_min_deg"] = _r(knee_min, 1)
	m["knee_flex_max_deg"] = _r(knee_max, 1)
	m["elbow_bend_max_deg"] = _r(elbow_max, 1)
	check(rep, "d", rig.cls, rig.lod, clip, "knee not hyper-extended", knee_min >= TH["knee_min_deg"], knee_min, TH["knee_min_deg"], "medium")
	check(rep, "d", rig.cls, rig.lod, clip, "knee flexion within limit", knee_max <= TH["knee_max_deg"], knee_max, TH["knee_max_deg"], "medium")
	check(rep, "d", rig.cls, rig.lod, clip, "elbow flexion within limit", elbow_max <= TH["elbow_max_deg"], elbow_max, TH["elbow_max_deg"], "medium")


## Two sole points per foot (heel under the ankle, toe tip), rigidly attached to the Foot / Toes bones, in model space.
static func _foot_points(rig: Rig, s: Dictionary, side: String) -> Dictionary:
	var fi := rig.b(side + "Foot")
	var ti := rig.b(side + "Toes")
	var ft: Transform3D = rig.rest_g[fi]
	var tt: Transform3D = rig.rest_g[ti]
	if not rig.sole_ready:
		rig.sole_ready = true
		var k := rig.scale_k
		for sd in ["Left", "Right"]:
			var f_rest: Transform3D = rig.rest_g[rig.b(sd + "Foot")]
			var t_rest: Transform3D = rig.rest_g[rig.b(sd + "Toes")]
			var heel_w := Vector3(f_rest.origin.x, 0.0, f_rest.origin.z)
			var dir := Vector3(0, 0, 1) * signf(t_rest.origin.z - f_rest.origin.z)
			var toe_w := Vector3(t_rest.origin.x, 0.0, t_rest.origin.z + dir.z * 0.10 * k)
			rig.sole[sd] = {"heel": f_rest.affine_inverse() * heel_w, "toe": t_rest.affine_inverse() * toe_w}
	var heel: Vector3 = (s["gx"][fi] as Transform3D) * rig.sole[side]["heel"]
	var toe: Vector3 = (s["gx"][ti] as Transform3D) * rig.sole[side]["toe"]
	return {"heel": heel, "toe": toe, "low": minf(heel.y, toe.y)}


static func _ground_metrics(rep: Dictionary, rig: Rig, clip: String, frames: Array, m: Dictionary) -> void:
	var lowest := 999.0
	for s in frames:
		for side in ["Left", "Right"]:
			var fp := _foot_points(rig, s, side)
			lowest = minf(lowest, float(fp["low"]))
	m["foot_min_dy_m"] = _r(lowest)
	check(rep, "d", rig.cls, rig.lod, clip, "feet do not sink below the ground", lowest >= -TH["ground_pen_m"], lowest, -TH["ground_pen_m"], "medium")


## Stance-foot velocity vs the ground speed the clip is played at (CharacterModel.NOMINAL_SPEED). The contact point of a foot is
## its lower sole point; a foot is planted while that point is within 2 cm of the floor in both frames.
static func _foot_slide(rep: Dictionary, rig: Rig, clip: String, frames: Array, m: Dictionary) -> void:
	var n: int = frames.size() - 1
	var dir: Vector3 = LOCO_DIR[clip]
	var nominal: float = float(CharacterModel.NOMINAL_SPEED[clip])
	var along_sum := 0.0
	var along_n := 0
	var err_sum := 0.0
	var err_max := 0.0
	var err_frame := 0
	var planted_frames := 0
	var drag_frames := 0
	var scrape_m := 0.0
	for f in n:
		var any_planted := false
		for side in ["Left", "Right"]:
			var a := _foot_points(rig, frames[f], side)
			var b := _foot_points(rig, frames[f + 1], side)
			var key: String = "heel" if float(a["heel"].y) <= float(a["toe"].y) else "toe"
			if float(a[key].y) > 0.02 or float(b[key].y) > 0.02:
				continue
			var v: Vector3 = ((b[key] as Vector3) - (a[key] as Vector3)) * FPS
			v.y = 0.0
			var along := -v.dot(dir)
			if along < -0.3 * nominal:
				# a foot skimming the floor while moving FORWARD relative to the body is not a stance foot: it is a dragged swing foot
				drag_frames += 1
				scrape_m += -along / FPS
				continue
			# stance = the whole sole (heel AND toe) on the floor in both frames; a foot pivoting on its toe is neither stance nor swing
			if maxf(float(a["heel"].y), float(a["toe"].y)) > 0.015 or maxf(float(b["heel"].y), float(b["toe"].y)) > 0.015:
				continue
			any_planted = true
			along_sum += along
			along_n += 1
			var err := (v + dir * nominal).length()
			err_sum += err
			if err > err_max:
				err_max = err
				err_frame = f
		if any_planted:
			planted_frames += 1
	var implied: float = along_sum / float(maxi(along_n, 1))
	m["foot_implied_speed_mps"] = _r(implied, 3)
	m["foot_nominal_speed_mps"] = nominal
	m["foot_speed_ratio"] = _r(implied / nominal, 3)
	m["foot_slide_mean_mps"] = _r(err_sum / float(maxi(along_n, 1)), 3)
	m["foot_slide_max_mps"] = _r(err_max, 3)
	m["foot_slide_worst_frame"] = err_frame
	m["planted_frame_fraction"] = _r(float(planted_frames) / float(n), 3)
	m["foot_drag_frames"] = drag_frames
	m["foot_drag_m"] = _r(scrape_m, 3)
	check(rep, "d", rig.cls, rig.lod, clip, "swing foot clears the floor (no dragging)", drag_frames <= 2, drag_frames, 2, "medium",
			"%d foot-frames skimming the floor while moving forward, %.2f m per cycle" % [drag_frames, scrape_m])
	check(rep, "d", rig.cls, rig.lod, clip, "foot lock: clip ground speed matches the nominal speed", absf(implied / nominal - 1.0) <= TH["foot_slide_ratio"], implied / nominal, 1.0, "medium",
			"implied %.2f m/s vs nominal %.2f m/s" % [implied, nominal])
	check(rep, "d", rig.cls, rig.lod, clip, "foot lock: worst stance-foot velocity error", err_max <= TH["foot_slide_mps"], err_max, TH["foot_slide_mps"], "low", "frame %d" % err_frame)
	if clip != "run":   # a run has flight phases
		check(rep, "d", rig.cls, rig.lod, clip, "a foot is planted in most frames", float(planted_frames) / float(n) >= 0.9, float(planted_frames) / float(n), 0.9, "low")


static func _foot_planted(rep: Dictionary, rig: Rig, clip: String, frames: Array, m: Dictionary) -> void:
	var worst := 0.0
	for side in ["Left", "Right"]:
		var first := _foot_points(rig, frames[0], side)
		for s in frames:
			var fp := _foot_points(rig, s, side)
			worst = maxf(worst, Vector2(fp["heel"].x - first["heel"].x, fp["heel"].z - first["heel"].z).length())
	m["planted_foot_move_m"] = _r(worst)
	check(rep, "d", rig.cls, rig.lod, clip, "feet stay planted", worst <= TH["idle_foot_move_m"], worst, TH["idle_foot_move_m"], "medium")


# ---- (e) props ----------------------------------------------------------------------------------------------
static func _props_audit(rep: Dictionary, rig: Rig, res: Dictionary) -> void:
	var cls := rig.cls
	var lod := rig.lod
	var expect: Dictionary = EXPECT_PROPS[cls]
	for bone in SOCKET_BONES:
		check(rep, "e", cls, lod, "", "socket bone %s exists" % bone, rig.b(bone) >= 0, 0, 1, "high")
	var found: Dictionary = {}
	for p in rig.props:
		found[p["bone"]] = p["name"]
	for bone in expect:
		check(rep, "e", cls, lod, "", "%s carries %s" % [bone, expect[bone]], String(found.get(bone, "")) == String(expect[bone]), String(found.get(bone, "")), String(expect[bone]), "high")
	check(rep, "e", cls, lod, "", "no unexpected props", found.size() == expect.size(), found.size(), expect.size(), "low", str(found))
	res["props"] = found
	# sockets sit under the hand / forearm they belong to
	for p in rig.props:
		var want_parent := "RightHand" if p["bone"] == "WeaponSocket_R" else "LeftHand" if p["bone"] == "WeaponSocket_L" else "LeftLowerArm"
		var have_parent := rig.sk.get_bone_name(rig.sk.get_bone_parent(int(p["bi"])))
		check(rep, "e", cls, lod, "", "%s is parented to %s" % [p["bone"], want_parent], have_parent == want_parent, have_parent, want_parent, "high")
	var worst_spread := {}
	var worst_off := {}
	var worst_pen := {}
	var worst_ground := {}
	var two_handed: bool = cls in ["pawn", "bishop"]
	# reference off-hand distance to the shaft (the shaft axis is the prop's longest AABB axis, so this is a constant offset at rest)
	var off_base := 0.0
	if two_handed:
		for p in rig.props:
			var s0: Dictionary = rig.clips["idle"][0]
			off_base = _seg_dist(hand_of(rig, s0, "Left"), prop_point(rig, s0, p, p["grip"]), tip_of(rig, s0, p))
	for clip in rig.clips:
		var frames: Array = rig.clips[clip]
		var spread_lo: Dictionary = {}
		var spread_hi: Dictionary = {}
		var off_delta := 0.0
		var pen_max := 0.0
		var ground_min := 999.0
		var pen_frame := 0
		for fi in frames.size():
			var s: Dictionary = frames[fi]
			for p in rig.props:
				var parent_i: int = rig.sk.get_bone_parent(int(p["bi"]))
				var d: float = ((s["gx"][p["bi"]] as Transform3D).origin - (s["gx"][parent_i] as Transform3D).origin).length()
				spread_lo[p["name"]] = minf(float(spread_lo.get(p["name"], 999.0)), d)
				spread_hi[p["name"]] = maxf(float(spread_hi.get(p["name"], 0.0)), d)
				if not p["shield"]:
					var tipw := tip_of(rig, s, p)
					ground_min = minf(ground_min, tipw.y)
					if two_handed and not (clip in ["climb", "ladder_idle", "drop_fall", "land", "victory"]):
						off_delta = maxf(off_delta, absf(_seg_dist(hand_of(rig, s, "Left"), prop_point(rig, s, p, p["grip"]), tipw) - off_base))
				var depth := _body_penetration(rig, s, p)
				if depth > pen_max:
					pen_max = depth
					pen_frame = fi
		var spread := 0.0
		for pn in spread_lo:
			spread = maxf(spread, float(spread_hi[pn]) - float(spread_lo[pn]))
		worst_spread[clip] = _r(spread, 5)
		worst_pen[clip] = [_r(pen_max), pen_frame]
		worst_ground[clip] = _r(ground_min)
		worst_off[clip] = _r(off_delta)
		check(rep, "e", cls, lod, clip, "props stay rigidly on their socket in every frame", spread <= 0.005, spread, 0.005, "high")
		check(rep, "e", cls, lod, clip, "props do not sink into the torso", pen_max <= TH["body_pen_m"], pen_max, TH["body_pen_m"], "medium", "deepest at frame %d" % pen_frame)
		check(rep, "e", cls, lod, clip, "weapon tip stays above the floor", ground_min >= -TH["weapon_ground_m"], ground_min, -TH["weapon_ground_m"], "low")
		if two_handed and not (clip in ["climb", "ladder_idle", "drop_fall", "land", "victory", "defeat", "stagger"]):   # those release the off hand on purpose
			check(rep, "e", cls, lod, clip, "off hand stays on the two-handed shaft", off_delta <= TH["offhand_shaft_m"], off_delta, TH["offhand_shaft_m"], "low")
	res["prop_socket_spread_m"] = worst_spread
	res["prop_body_pen_m"] = worst_pen
	res["prop_tip_min_y_m"] = worst_ground
	res["offhand_shaft_delta_m"] = worst_off


static func _seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.000001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Deepest point of a prop inside the torso (ellipse cylinder around the Spine..Neck axis, rest-frame extents).
static func _body_penetration(rig: Rig, s: Dictionary, p: Dictionary) -> float:
	var chest_i := rig.b("UpperChest")
	var hips_i := rig.b("Hips")
	var spine_i := rig.b("Spine")
	var neck_i := rig.b("Neck")
	var chest_x: Transform3D = s["gx"][chest_i]
	var rest_x: Transform3D = rig.rest_g[chest_i]
	var bottom: Vector3 = (s["gx"][spine_i] as Transform3D).origin
	var top: Vector3 = (s["gx"][neck_i] as Transform3D).origin
	# torso frame: the chest's rotation away from rest, positioned at the axis midpoint
	var delta: Basis = chest_x.basis * rest_x.basis.inverse()
	var inv := delta.inverse()
	var mid := (bottom + top) * 0.5
	var a: float = float(rig.torso["a"])
	var bb: float = float(rig.torso["b"])
	var half_h := maxf(bottom.distance_to(top) * 0.5, 0.05)
	var points: Array = []
	if p["shield"]:
		for c in p["corners"]:
			points.append(prop_point(rig, s, p, c))
	else:
		var g: Vector3 = prop_point(rig, s, p, p["grip"])
		var t: Vector3 = tip_of(rig, s, p)
		for k in 8:
			points.append(g.lerp(t, 0.25 + 0.75 * float(k) / 7.0))
	var deepest := 0.0
	for pt in points:
		var local: Vector3 = inv * (pt - mid)
		if absf(local.y) > half_h:
			continue
		var e := sqrt((local.x / a) * (local.x / a) + (local.z / bb) * (local.z / bb))
		if e < 1.0:
			deepest = maxf(deepest, (1.0 - e) * minf(a, bb))
	return deepest


# ---- (b) attacks --------------------------------------------------------------------------------------------
static func _striker(rig: Rig, row: Dictionary, trajectories: Dictionary) -> String:
	var best := ""
	var best_len := -1.0
	for pname in trajectories:
		var path: PackedVector3Array = trajectories[pname]
		var length := 0.0
		for t in range(int(row["a0"]), mini(int(row["a1"]), path.size() - 1)):
			length += path[t].distance_to(path[t + 1])
		if length > best_len:
			best_len = length
			best = pname
	return best


static func _attack_audit(rep: Dictionary, rig: Rig, res: Dictionary) -> void:
	var cls := rig.cls
	var lod := rig.lod
	var tol: int = TH["contact_tol_ticks"]
	var idle0: Dictionary = rig.clips["idle"][0]
	for row in attack_rows(cls):
		var def: AttackDefinition = row["def"]
		var clip: String = row["clip"]
		if not rig.player.has_animation(clip):
			continue
		var total: int = row["total"]
		var anim := rig.player.get_animation(clip)
		var frames_clip := clip_frames(rig, clip) - roundi(CharacterModel.span_start(def) * FPS)   # frames of the clip this attack actually plays
		var out := {"id": row["id"], "clip": clip, "total_ticks": total, "clip_frames": frames_clip, "active": [row["a0"], row["a1"]], "cancel": row["cancel"],
				"reach": _r(row["reach"], 3), "arc": row["arc"], "kind": ["light", "heavy", "ability"][row["kind"]]}
		# length
		var shared := 0
		for other in attack_rows(cls):
			if other["clip"] == clip and other["kind"] == AttackDefinition.Kind.LIGHT:
				shared += 1
		var tol_len: float = TH["length_tol_frames_loose"] if (row["kind"] == AttackDefinition.Kind.ABILITY or shared > 1) else TH["length_tol_frames"]
		var ok_len := absf(float(frames_clip) - float(total)) <= tol_len
		var ratio := float(frames_clip) / float(total)
		out["speed_ratio"] = _r(ratio, 3)
		check(rep, "b", cls, lod, clip, "%s clip length vs sim ticks (%d f vs %d t)" % [row["id"], frames_clip, total], ok_len, float(frames_clip), float(total), "medium",
				"played at %.2fx%s" % [ratio, " (clip shared by %d chain links, tolerance %.0f)" % [shared, tol_len] if shared > 1 else ""])
		check(rep, "b", cls, lod, clip, "%s playback rate stays in band" % row["id"], ratio >= TH["speed_ratio_min"] and ratio <= TH["speed_ratio_max"], ratio,
				"[%.2f, %.2f]" % [TH["speed_ratio_min"], TH["speed_ratio_max"]], "medium")
		# sim-domain trajectories: what the player sees at each sim tick
		var trajs: Dictionary = {}
		var hand_path := PackedVector3Array()
		var poses: Array = []
		for t in total + 1:
			var s := pose_at(rig, clip, clip_time_at_tick(row, anim.length, float(t)))
			poses.append(s)
			for p in rig.props:
				if p["shield"]:
					continue
				var arr: PackedVector3Array = trajs.get(p["name"], PackedVector3Array())
				arr.append(tip_of(rig, s, p))
				trajs[p["name"]] = arr
		var striker := _striker(rig, row, trajs)
		if striker == "":
			check(rep, "b", cls, lod, clip, "%s has a striking weapon prop" % row["id"], false, 0, 1, "high")
			continue
		out["striker"] = striker
		var tip: PackedVector3Array = trajs[striker]
		var speed: Array = []
		for t in total:
			speed.append(tip[t].distance_to(tip[t + 1]) * FPS)
		var peak_t := 0
		for t in total:
			if speed[t] > speed[peak_t]:
				peak_t = t
		var half := 0.5 * float(speed[peak_t])
		var c0 := peak_t
		var c1 := peak_t
		while c0 > 0 and speed[c0 - 1] >= half:
			c0 -= 1
		while c1 < total - 1 and speed[c1 + 1] >= half:
			c1 += 1
		out["peak_speed_tick"] = peak_t
		out["peak_speed_mps"] = _r(speed[peak_t], 2)
		out["contact_window"] = [c0, c1 + 1]
		var a0: int = row["a0"]
		var a1: int = row["a1"]
		var ok_peak: bool = peak_t >= a0 - tol and peak_t < a1 + tol
		var overlap: bool = c1 + 1 >= a0 - tol and c0 <= a1 + tol
		check(rep, "b", cls, lod, clip, "%s weapon peak speed inside the active window +-%d" % [row["id"], tol], ok_peak, peak_t,
				"[%d, %d]" % [a0 - tol, a1 + tol - 1], "high", "peak at tick %d, active %d..%d" % [peak_t, a0, a1])
		check(rep, "b", cls, lod, clip, "%s contact window overlaps the active window" % row["id"], overlap, "%d..%d" % [c0, c1 + 1], "%d..%d" % [a0, a1], "high")
		# max extension: first tick the tip is within 5% of its maximum forward reach
		var fwd_max := -999.0
		for t in total + 1:
			fwd_max = maxf(fwd_max, tip[t].z)
		var ext_t := 0
		for t in total + 1:
			if tip[t].z >= fwd_max - 0.05 * maxf(fwd_max, 0.2):
				ext_t = t
				break
		out["extension_tick"] = ext_t
		out["tip_forward_max_m"] = _r(fwd_max, 3)
		check(rep, "b", cls, lod, clip, "%s weapon reaches max extension no later than the active end +%d" % [row["id"], tol], ext_t <= a1 + tol, ext_t, a1 + tol, "medium",
				"extension at tick %d" % ext_t)
		# reach + arc during the active window
		var reach_tip := 0.0
		var in_sector := false
		var az_min := 999.0
		var az_max := -999.0
		for t in range(a0, mini(a1 + 1, total + 1)):
			reach_tip = maxf(reach_tip, _horiz(tip[t]))
			var az := rad_to_deg(atan2(tip[t].x, tip[t].z))
			az_min = minf(az_min, az)
			az_max = maxf(az_max, az)
			if _horiz(tip[t]) >= 0.6 * row["reach"] and absf(az) <= row["arc"] * 0.5 + 12.0:
				in_sector = true
		out["tip_reach_m"] = _r(reach_tip, 3)
		out["tip_azimuth_deg"] = [_r(az_min, 1), _r(az_max, 1)]
		check(rep, "b", cls, lod, clip, "%s tip reaches the sim hitbox (>= %.0f%% of %.2f m)" % [row["id"], TH["reach_min_ratio"] * 100.0, row["reach"]],
				reach_tip >= TH["reach_min_ratio"] * row["reach"], reach_tip, TH["reach_min_ratio"] * row["reach"], "medium")
		check(rep, "b", cls, lod, clip, "%s tip does not overshoot the hitbox by more than %.1f m" % [row["id"], TH["reach_max_over_m"]], reach_tip <= row["reach"] + TH["reach_max_over_m"],
				reach_tip, row["reach"] + TH["reach_max_over_m"], "low")
		check(rep, "b", cls, lod, clip, "%s tip is inside the hit sector at some active tick" % row["id"], in_sector, 0, 1, "medium",
				"azimuth %.0f..%.0f deg vs +-%.0f" % [az_min, az_max, row["arc"] * 0.5])
		# anticipation: draw-back against the strike direction before the contact window
		var strike_vec := tip[mini(c1 + 1, total)] - tip[c0]
		var strike_dir := strike_vec.normalized()
		var strike_travel := strike_vec.length()
		var draw := 0.0
		for t in range(0, c0 + 1):
			draw = maxf(draw, -(tip[t] - tip[0]).dot(strike_dir))
		out["anticipation_draw_m"] = _r(draw, 3)
		out["strike_travel_m"] = _r(strike_travel, 3)
		var need := maxf(TH["anticipation_min_m"], TH["anticipation_min_ratio"] * strike_travel)
		check(rep, "b", cls, lod, clip, "%s has anticipation (wind-up draw-back before the contact window)" % row["id"], draw >= need, draw, need, "medium",
				"draw-back %.2f m, strike %.2f m" % [draw, strike_travel])
		# a visible wind-up pose change before the active window
		var pre := 0.0
		for t in range(0, a0 + 1):
			pre = maxf(pre, pose_dist(rig, poses[0], poses[t]))
		out["windup_pose_delta_deg"] = _r(pre, 2)
		check(rep, "b", cls, lod, clip, "%s wind-up changes the pose before the active window" % row["id"], pre >= 6.0, pre, 6.0, "medium")
		# recovery returns toward idle
		var end_delta := pose_dist(rig, poses[total], idle0)
		var at_active_end := pose_dist(rig, poses[mini(a1, total)], idle0)
		out["recovery_end_delta_deg"] = _r(end_delta, 2)
		out["active_end_delta_deg"] = _r(at_active_end, 2)
		check(rep, "b", cls, lod, clip, "%s recovery returns to the ready pose" % row["id"], end_delta <= TH["recovery_rms_deg"], end_delta, TH["recovery_rms_deg"], "medium")
		check(rep, "b", cls, lod, clip, "%s is closer to ready at the cancel point than at the active end" % row["id"],
				pose_dist(rig, poses[mini(int(row["cancel"]), total)], idle0) <= at_active_end + 0.5, pose_dist(rig, poses[mini(int(row["cancel"]), total)], idle0), at_active_end, "low")
		# Hips lean vs the sim's forward motion
		var hips_fwd := 0.0
		var hips_rest: Vector3 = (rig.rest_g[rig.b("Hips")] as Transform3D).origin
		for s in poses:
			hips_fwd = maxf(hips_fwd, (s["gx"][rig.b("Hips")] as Transform3D).origin.z - hips_rest.z)
		out["hips_forward_max_m"] = _r(hips_fwd, 3)
		out["sim_forward_motion_m"] = _r(def.forward_motion_m, 3)
		res["attacks"][row["id"]] = out
	# other clips against their sim lengths
	_state_clip_lengths(rep, rig, res)


## dodge / parry / stagger / defeat / victory: clip frames vs the sim's tick counts and what the model does with them.
static func _state_clip_lengths(rep: Dictionary, rig: Rig, res: Dictionary) -> void:
	var cls := rig.cls
	var lod := rig.lod
	var role: String = ROLE[cls]
	var stats := FighterRoster.stats_for(role)
	var profile := FighterProfile.for_role(role)
	var rows := {
		"dodge": {"ticks": [int(profile["dodge_ticks"])], "what": "dodge_ticks"},
		"parry": {"ticks": [int(stats["parryTicks"]) + int(profile["parry_recovery_ticks"])], "what": "parryTicks + parry_recovery_ticks"},
		"defeat": {"ticks": [60], "what": "CharacterModel plays defeat over 60 ticks"},
	}
	# stagger: the stun lengths the simulation can produce (hit stun of each attack, parried, guard break, counter)
	var stuns: Array = [int(profile["parry_stagger_ticks"]), int(profile["guardbreak_stun"])]
	for row in attack_rows(cls):
		stuns.append((row["def"] as AttackDefinition).hitstun_ticks)
	stuns.sort()
	rows["stagger"] = {"ticks": stuns, "what": "hitstun / parried / guardbreak stuns"}
	var out := {}
	for clip in rows:
		if not rig.player.has_animation(clip):
			continue
		var frames := clip_frames(rig, clip)
		var ticks: Array = rows[clip]["ticks"]
		var worst_ratio := 1.0
		for t in ticks:
			var r := float(frames) / float(t)
			if absf(log(r)) > absf(log(worst_ratio)):
				worst_ratio = r
		out[clip] = {"frames": frames, "sim_ticks": ticks, "worst_rate": _r(worst_ratio, 3), "what": rows[clip]["what"]}
		if clip == "stagger":
			# stagger is a held reaction: the rate may vary with the stun length; only extreme rates are wrong
			check(rep, "b", cls, lod, clip, "stagger rate stays in [0.4, 3.0] for every stun length", worst_ratio >= 0.4 and worst_ratio <= 3.0, worst_ratio, "[0.4, 3.0]", "low")
		else:
			var ok := ticks.all(func(t): return absf(float(frames) - float(t)) <= TH["length_tol_frames"])
			check(rep, "b", cls, lod, clip, "%s clip frames vs sim ticks (%s)" % [clip, rows[clip]["what"]], ok, float(frames), str(ticks), "medium")
	# ability (non-attack casts: pawn last-stand, bishop blink, rook fortress-guard, queen royal-fury, king counter)
	var ability_id := String(stats["abilityId"]) if stats.has("abilityId") else ""
	if role == "k":
		ability_id = "royal-counter"
	var adef := Balance.ability(ability_id)
	if not adef.is_empty() and adef.has("cast_ticks"):
		var cast := int(adef["cast_ticks"])
		var frames := clip_frames(rig, "ability")
		out["ability_cast"] = {"frames": frames, "sim_ticks": cast, "ability": ability_id}
		check(rep, "b", cls, lod, "ability", "ability cast clip frames vs cast_ticks (%s)" % ability_id, absf(float(frames) - float(cast)) <= TH["length_tol_frames"],
				float(frames), float(cast), "medium", "%d frames played over %d ticks (%.2fx)" % [frames, cast, float(frames) / float(cast)])
		if role == "k":
			var cs := int(adef["counter_start"])
			var ce := int(adef["counter_end"])
			out["counter_window"] = [cs, ce]
	res["state_clips"] = out


# =============================================================================================================
# (f) LOD parity, (g) blends
# =============================================================================================================
static func lod_parity(rep: Dictionary, a: Rig, b: Rig) -> void:
	var cls := a.cls
	var out := {}
	var la: Array = a.player.get_animation_list()
	var lb: Array = b.player.get_animation_list()
	la.sort()
	lb.sort()
	check(rep, "f", cls, 1, "", "LOD1 has the same clip names", la == lb, lb.size(), la.size(), "high", "LOD0 %s vs LOD1 %s" % [str(la), str(lb)])
	var worst_len := 0.0
	for c in la:
		if b.player.has_animation(c):
			worst_len = maxf(worst_len, absf(a.player.get_animation(c).length - b.player.get_animation(c).length) * FPS)
	check(rep, "f", cls, 1, "", "LOD1 clip lengths equal LOD0", worst_len < 0.01, worst_len, 0.0, "high")
	check(rep, "f", cls, 1, "", "LOD1 has the same bone names", a.names == b.names, b.names.size(), a.names.size(), "high")
	var sa: Array = []
	var sb: Array = []
	for p in a.props:
		sa.append("%s@%s" % [p["name"], p["bone"]])
	for p in b.props:
		sb.append("%s@%s" % [p["name"], p["bone"]])
	sa.sort()
	sb.sort()
	check(rep, "f", cls, 1, "", "LOD1 has the same props on the same sockets", sa == sb, str(sb), str(sa), "high")
	var worst_pose := 0.0
	var worst_clip := ""
	if a.names == b.names:
		for c in la:
			if not b.player.has_animation(c) or not a.clips.has(c) or not b.clips.has(c):
				continue
			var fa: Array = a.clips[c]
			var fb: Array = b.clips[c]
			if fa.size() != fb.size():
				continue
			for f in range(0, fa.size(), 3):
				for bone in ["Hips", "RightHand", "LeftHand", "RightFoot", "LeftFoot", "Head"]:
					var d: float = ((fa[f]["gx"][a.b(bone)] as Transform3D).origin - (fb[f]["gx"][b.b(bone)] as Transform3D).origin).length()
					if d > worst_pose:
						worst_pose = d
						worst_clip = c
		for p in a.props:
			for q in b.props:
				if p["bone"] == q["bone"]:
					check(rep, "f", cls, 1, "", "LOD1 prop %s transform equals LOD0" % p["name"],
							((p["xf"] as Transform3D).origin - (q["xf"] as Transform3D).origin).length() < 0.001, 0.0, 0.001, "medium")
	out["max_pose_diff_m"] = _r(worst_pose, 6)
	out["worst_clip"] = worst_clip
	check(rep, "f", cls, 1, worst_clip, "LOD1 joint positions equal LOD0 in every sampled frame", worst_pose <= TH["lod_pose_m"], worst_pose, TH["lod_pose_m"], "high")
	out["props"] = sa
	rep["lod_parity"][cls] = out


## Cross-fade boundaries: RMS pose delta between where clip A leaves off and where clip B starts, spread over blend_time frames.
static func blends(rep: Dictionary, rig: Rig) -> void:
	var cls := rig.cls
	var out := {}
	var pairs: Array = []
	var loco := ["idle", "walk", "run", "strafe_left", "strafe_right"]
	for a in loco:
		for b in loco:
			if a != b:
				pairs.append([a, b, "loop"])
	for c in ["light_1", "light_2", "light_3", "heavy", "ability", "parry", "dodge"]:
		pairs.append(["idle", c, "start"])
		pairs.append(["walk", c, "start"])
		pairs.append(["block", c, "start"])
	for c in ["light_1", "light_2", "light_3", "heavy", "ability", "parry", "dodge", "stagger", "hit_react_light", "hit_react_heavy", "land"]:
		pairs.append([c, "idle", "end"])
		pairs.append([c, "walk", "end"])
	for c in ["hit_react_light", "hit_react_heavy", "stagger"]:
		pairs.append(["idle", c, "start"])
		pairs.append(["walk", c, "start"])
		pairs.append(["run", c, "start"])
		pairs.append(["block", c, "start"])
	pairs.append(["block", "parry", "start"])
	pairs.append(["idle", "block", "start"])
	pairs.append(["block", "idle", "loop"])
	pairs.append(["idle", "victory", "start"])
	pairs.append(["idle", "defeat", "start"])
	var worst_rate := 0.0
	var worst_pair := ""
	for p in pairs:
		var a: String = p[0]
		var b: String = p[1]
		if not rig.player.has_animation(a) or not rig.player.has_animation(b):
			continue
		var fa: Array = sample_clip(rig, a)
		var fb: Array = sample_clip(rig, b)
		var start: Dictionary = fb[0]
		var blend := CharacterModel.blend_time(a, b)
		var frames_blend := maxf(blend * FPS, 1.0)
		var worst := 0.0
		var sum := 0.0
		var cnt := 0
		var f_from: Array = []
		if p[2] == "end":
			f_from = [fa.size() - 1]
		elif p[2] == "start":
			f_from = range(0, mini(fa.size(), 40), 2) if a in ["walk", "run", "idle", "block", "strafe_left", "strafe_right"] else [0]
		else:
			f_from = range(0, fa.size() - 1, 2)
		for f in f_from:
			var d := pose_dist(rig, fa[f], start)
			worst = maxf(worst, d)
			sum += d
			cnt += 1
		var median_like := sum / float(maxi(cnt, 1))
		var rate := median_like / frames_blend
		out["%s>%s" % [a, b]] = {"blend_s": _r(blend, 3), "mean_delta_deg": _r(median_like, 2), "worst_delta_deg": _r(worst, 2), "rate_deg_per_frame": _r(rate, 2)}
		var limit: float = TH["blend_rate_reaction_deg"] if b in ["stagger", "hit_react_light", "hit_react_heavy", "parry", "dodge"] else TH["blend_rate_deg"]
		check(rep, "g", cls, rig.lod, "%s>%s" % [a, b], "blend %s -> %s (%.2fs): pose delta per blend frame" % [a, b, blend], rate <= limit, rate, limit, "medium",
				"mean delta %.1f deg over %.1f frames" % [median_like, frames_blend])
		if rate > worst_rate:
			worst_rate = rate
			worst_pair = "%s>%s" % [a, b]
	out["worst"] = [worst_pair, _r(worst_rate, 2)]
	rep["blends"][cls] = out


# =============================================================================================================
# Driver
# =============================================================================================================
static func run(tree: SceneTree, opts: Dictionary = {}) -> Dictionary:
	var rep := new_report()
	var classes: Array = opts.get("classes", CLASSES)
	var lods: Array = opts.get("lods", [0, 1])
	for cls in classes:
		var rigs: Dictionary = {}
		for lod in lods:
			rigs[lod] = audit_class(tree, cls, lod, rep, opts)
		if rigs.get(0) != null and rigs.get(1) != null:
			lod_parity(rep, rigs[0], rigs[1])
		if bool(opts.get("blends", true)):
			var main_rig: Rig = rigs.get(0) if rigs.get(0) != null else rigs.get(1)
			if main_rig != null:
				blends(rep, main_rig)
		for lod in rigs:
			if rigs[lod] != null:
				(rigs[lod] as Rig).free_all()
	rep["coverage"]["fallback_counts"] = CharacterModel.fallback_counts.duplicate()
	if bool(opts.get("runtime", true)):
		var runtime = load("res://combat/tools/anim_audit_runtime.gd")
		rep["runtime"] = await runtime.run(tree, rep, opts)
	return rep


static func sorted_findings(rep: Dictionary) -> Array:
	var list: Array = (rep["findings"] as Array).duplicate()
	list.sort_custom(func(x, y):
		var sx: int = SEVERITY_ORDER[x["severity"]]
		var sy: int = SEVERITY_ORDER[y["severity"]]
		if sx != sy:
			return sx < sy
		if x["class"] != y["class"]:
			return x["class"] < y["class"]
		return str(x["clip"]) + str(x["check"]) < str(y["clip"]) + str(y["check"]))
	return list


static func summary_table(rep: Dictionary) -> String:
	var lines: Array = ["| Class | " + " | ".join(["a coverage", "b timing", "c loops", "d skeleton", "e props", "f LOD", "g blends", "h runtime"]) + " |", "| --- | " + " | ".join(["---:", "---:", "---:", "---:", "---:", "---:", "---:", "---:"]) + " |"]
	for cls in CLASSES:
		var cells: Array = []
		for g in ["a", "b", "c", "d", "e", "f", "g", "h"]:
			var c: Dictionary = rep["checks"].get("%s/%s" % [g, cls], {})
			cells.append("%d / %d" % [int(c.get("pass", 0)), int(c.get("fail", 0))] if not c.is_empty() else "-")
		lines.append("| %s | %s |" % [cls, " | ".join(cells)])
	return "\n".join(lines)


func _initialize() -> void:
	await process_frame
	var opts := {}
	var out_path := ""
	var md_path := ""
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match String(args[i]):
			"--out":
				i += 1
				out_path = String(args[i])
			"--md":
				i += 1
				md_path = String(args[i])
			"--classes":
				i += 1
				opts["classes"] = String(args[i]).split(",")
			"--lod":
				i += 1
				opts["lods"] = [0, 1] if String(args[i]) == "both" else [int(args[i])]
			"--assets":
				i += 1
				CharacterModel.characters_root = String(args[i])
			"--no-runtime":
				opts["runtime"] = false
			"--no-blends":
				opts["blends"] = false
		i += 1
	var started := Time.get_ticks_msec()
	var rep := await run(self, opts)
	print("anim audit finished in %d ms" % (Time.get_ticks_msec() - started))
	print(summary_table(rep))
	var list := sorted_findings(rep)
	print("findings: %d (high %d, medium %d, low %d)" % [list.size(), list.filter(func(f): return f["severity"] == "high").size(),
			list.filter(func(f): return f["severity"] == "medium").size(), list.filter(func(f): return f["severity"] == "low").size()])
	for f in list:
		if f["severity"] != "low":
			print("  [%s] %s/lod%d %s: %s (value %s, limit %s) %s" % [f["severity"], f["class"], f["lod"], f["clip"], f["check"], str(f["value"]), str(f["limit"]), f["detail"]])
	if out_path != "":
		var file := FileAccess.open(out_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(rep, "\t", true) + "\n")
		file.close()
		print("wrote ", out_path)
	for child in root.get_children():
		child.queue_free()
	await process_frame
	await process_frame
	load("res://combat/audio/combat_audio.gd").clear_library()   # same cleanup as test_runner.gd: no leaked audio resources at exit
	await create_timer(0.5).timeout
	OS.delay_msec(400)
	quit(0)
