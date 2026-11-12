extends RefCounted
## Runtime half of the animation audit (group h): real seeded AI-vs-AI fights through the real presentation (CombatArena +
## CombatVfx + CharacterModel on the imported GLBs). The arena's physics step, every CharacterModel and its AnimationPlayer
## are advanced BY HAND, one simulation tick per call, so the run is deterministic and each fighter's state can be compared
## with the clip the model chose at exactly that tick.
##
## Asserted per fight and class (see anim_audit.gd `check()` for the severities):
##   * the model's clip matches the fighter state within one frame (hitstop frames excluded);
##   * an attack/ability clip is never replaced before the swing leaves its active window;
##   * the playback position follows the clip time the model is supposed to show (|error| <= 0.07 s);
##   * the playback rate is applied once (get_playing_speed == clip length / sim ticks x anticipation rate);
##   * nothing falls back silently (CharacterModel.fallback_counts stays empty);
##   * after the fight hold / react / flash are cleared and the outcome clips settle (victory plays, defeat reaches its last pose).
## It also records every clip each class played, so a clip that never ran in a fight is visible (coverage table).

const Audit := preload("res://combat/tools/anim_audit.gd")
const S := CombatConstants.State
const DT := 1.0 / 60.0
## [white role, black role, seed, white style, black style]; chosen so all six classes, the Queen's Royal Fury chain and the King's Royal
## Counter appear, and the `ability` style makes the AI use its signature move early.
const FIGHTS := [
	["p", "n", 211, "ability", "aggressive"],
	["b", "r", 212, "ability", "defensive"],
	["q", "k", 213, "ability", "ability"],
	["k", "q", 214, "defensive", "ability"],
	["n", "b", 215, "ability", "balanced"],
	["r", "p", 216, "aggressive", "ability"],
]
const STATE_FAMILY := {
	S.IDLE: ["idle"], S.MOVING: ["walk", "run", "strafe_left", "strafe_right"], S.BLOCKING: ["block"], S.PARRYING: ["parry"],
	S.DODGING: ["dodge"], S.STAGGERED: ["stagger"], S.ABILITY_CASTING: ["ability"], S.DEFEATED: ["defeat"],
}
## Independent of CharacterModel: attack tag -> the clip a viewer expects to see.
const TAG_CLIP := {"thrust": "light_1", "slash_right": "light_1", "thrust_low": "light_2", "slash_left": "light_2",
		"sweep": "light_3", "overhead": "light_3"}


static func intended_attack_clip(def: AttackDefinition) -> String:
	if def.kind == AttackDefinition.Kind.HEAVY:
		return "heavy"
	if def.kind == AttackDefinition.Kind.ABILITY:
		return "ability"
	return String(TAG_CLIP.get(def.animation, "?"))


static func run(tree: SceneTree, rep: Dictionary, opts: Dictionary) -> Dictionary:
	var out := {"fights": [], "clips_played": {}, "clip_starts": {}, "never_played": {}}
	CharacterModel.fallback_counts.clear()
	CharacterModel.trace_enabled = true
	var fights: Array = opts.get("fights", FIGHTS)
	for spec in fights:
		var res: Dictionary = await _fight(tree, rep, spec, out)
		out["fights"].append(res)
	if bool(opts.get("scripted", true)):
		for cls in opts.get("classes", Audit.CLASSES):
			var role: String = Audit.ROLE[cls]
			var res: Dictionary = await _fight(tree, rep, [role, role, 300 + Audit.CLASSES.find(cls), "scripted", "scripted"], out)
			out["fights"].append(res)
	CharacterModel.trace_enabled = false
	var fb: Dictionary = CharacterModel.fallback_counts.duplicate()
	out["fallbacks"] = fb
	for cls in Audit.CLASSES:
		if out["clips_played"].has(cls):
			Audit.check(rep, "h", cls, 0, "", "no silent clip fallback during the fights", not _any_key_starts(fb, cls), 0, 0, "high", str(fb))
			var never: Array = []
			for clip in ["idle", "walk", "run", "strafe_left", "strafe_right", "light_1", "light_2", "light_3", "heavy", "block", "parry", "dodge", "stagger", "ability",
					"defeat", "victory", "hit_react_light", "hit_react_heavy"]:
				if not out["clips_played"][cls].has(clip):
					never.append(clip)
			out["never_played"][cls] = never
	return out


static func _any_key_starts(d: Dictionary, cls: String) -> bool:
	for k in d:
		if String(k).begins_with(cls + ":"):
			return true
	return false


static func _fight(tree: SceneTree, rep: Dictionary, spec: Array, out: Dictionary) -> Dictionary:
	var white: String = spec[0]
	var black: String = spec[1]
	var seed_value: int = spec[2]
	var arena: CombatArena = (load("res://combat/arena.tscn") as PackedScene).instantiate()
	arena.presentation_enabled = true
	tree.root.add_child(arena)
	var scripted: bool = spec[3] == "scripted"
	arena.configure_seats({"player-white": {"type": "ai", "skill": 0.8, "style": "balanced" if scripted else spec[3]}, "player-black": {"type": "ai", "skill": 0.8, "style": "balanced" if scripted else spec[4]}})
	var request := FighterRoster.build_request(white, black, "w", "anim-audit-%d" % seed_value, seed_value, 0)
	var reply: Dictionary = arena.start_battle(request, {"allow_experimental_roles": true})
	var res := {"white": white, "black": black, "seed": seed_value, "ok": bool(reply["ok"]), "scripted": spec[3] == "scripted"}
	if not reply["ok"]:
		arena.queue_free()
		Audit.check(rep, "h", Audit.CLASSES[0], 0, "", "fight %s-%s starts" % [white, black], false, str(reply), "ok", "high")
		return res
	arena.set_physics_process(false)
	var script_state := {}
	if scripted:
		arena._ais.clear()    # the scenario below submits the inputs itself
		script_state = {"plan": _plan(white), "base": -1, "block": false, "move": Vector2.ZERO,
				"b0": CombatInputBuilder.new(request["matchId"], request["battleId"], "player-white"),
				"b1": CombatInputBuilder.new(request["matchId"], request["battleId"], "player-black")}
	var models: Array = arena._fighter_visuals.duplicate()
	var classes: Array = []
	var ok_models := true
	for i in 2:
		var m = models[i]
		if not (m is CharacterModel):
			ok_models = false
			continue
		(m as CharacterModel).set_process(false)
		(m as CharacterModel).alpha_override = 0.0
		(m as CharacterModel).player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		classes.append((m as CharacterModel).class_name_str)
	if not ok_models:
		Audit.check(rep, "h", Audit.CLASSES[0], 0, "", "fight %s-%s mounts CharacterModels" % [white, black], false, 0, 1, "high")
		arena.stop_battle()
		arena.queue_free()
		return res
	await tree.process_frame

	var viol: Array = [{}, {}]
	var worst: Array = [{"pos": 0.0, "speed": 0.0}, {"pos": 0.0, "speed": 0.0}]
	var mismatch_run: Array = [0, 0]
	var started_states: Array = [{}, {}]
	var tick := 0
	var max_ticks := 3400 if not scripted else 1600
	while arena.sim.is_running() and tick < max_ticks:
		if scripted:
			_script_tick(arena, script_state)
		arena._physics_process(DT)
		tick += 1
		for i in 2:
			_observe(arena, models[i], arena.sim.fighters[i], viol[i], worst[i], mismatch_run, i, out, classes[i], started_states[i])
	res["ticks"] = tick
	res["result"] = String(arena.sim.result.get("reason", "unfinished"))
	# settle: no more simulation, the presentation runs on
	for _k in 240:
		for i in 2:
			var m: CharacterModel = models[i]
			m._process(DT)
			m.player.advance(DT)
			var played: Dictionary = out["clips_played"][classes[i]]
			played[m._current] = int(played.get(m._current, 0)) + 1
	var settle := {}
	for i in 2:
		settle[classes[i]] = _settle_checks(rep, arena, models[i], arena.sim.fighters[i], classes[i])
	res["settle"] = settle
	for i in 2:
		var cls: String = classes[i]
		for name in viol[i]:
			Audit.check(rep, "h", cls, 0, "", "%s [%s-%s seed %d]" % [name, white, black, seed_value], int(viol[i][name]["count"]) == 0, int(viol[i][name]["count"]), 0,
					String(viol[i][name]["severity"]), String(viol[i][name]["first"]))
		res["%s_worst" % cls] = {"pos_err_s": Audit._r(worst[i]["pos"], 4), "speed_ratio_err": Audit._r(worst[i]["speed"], 4)}
		Audit.check(rep, "h", cls, 0, "", "playback position follows the sim [%s-%s seed %d]" % [white, black, seed_value], worst[i]["pos"] <= 0.07, worst[i]["pos"], 0.07, "medium")
		Audit.check(rep, "h", cls, 0, "", "playback rate applied once [%s-%s seed %d]" % [white, black, seed_value], worst[i]["speed"] <= 0.06, worst[i]["speed"], 0.06, "medium")
	arena.stop_battle()
	arena.queue_free()
	await tree.process_frame
	return res


static func _add(plan: Dictionary, t: int, op: Array) -> void:
	if not plan.has(t):
		plan[t] = []
	plan[t].append(op)


## Scenario script (ticks after the countdown): a light chain mash (3 links, or 5 once Royal Fury runs), heavy, parry, both dodges,
## block, the signature ability, a forced stagger, hits on the subject (hit reactions), then a knockout (victory / defeat).
static func _plan(role: String) -> Dictionary:
	var p := {}
	for k in 26:
		_add(p, 5 + 6 * k, ["press", "light"])
	_add(p, 200, ["press", "heavy"])
	_add(p, 300, ["press", "parry"])
	_add(p, 360, ["move", 1.0, 0.0])
	_add(p, 360, ["press", "dodge"])
	_add(p, 420, ["press", "dodge"])
	_add(p, 470, ["block", true])
	_add(p, 530, ["block", false])
	if role == "p":
		_add(p, 560, ["hp", 0.3])
	_add(p, 565, ["press", "ability"])
	if role == "k":
		_add(p, 568, ["dummy", "light"])
	if role == "q":
		for k in 18:
			_add(p, 590 + 6 * k, ["press", "light"])
	_add(p, 700, ["hp", 1.0])
	_add(p, 702, ["stagger"])
	_add(p, 760, ["dummy", "light"])
	_add(p, 840, ["dummy", "heavy"])
	_add(p, 930, ["hp_dummy", 1.0])
	for k in 10:
		_add(p, 940 + 8 * k, ["press", "light"])
	return p


static func _script_tick(arena: CombatArena, st: Dictionary) -> void:
	var sim := arena.sim
	var f0: FighterController = sim.fighters[0]
	var f1: FighterController = sim.fighters[1]
	if sim.phase == CombatSimulation.Phase.ACTIVE and int(st["base"]) < 0:
		st["base"] = sim.server_tick
	var t: int = sim.server_tick - int(st["base"]) if int(st["base"]) >= 0 else -1
	var b0: CombatInputBuilder = st["b0"]
	var b1: CombatInputBuilder = st["b1"]
	var move: Vector2 = Vector2.ZERO
	var ops: Array = st["plan"].get(t, []) if t >= 0 else []
	for op in ops:
		match String(op[0]):
			"press":
				b0.press(String(op[1]))
			"dummy":
				b1.press(String(op[1]))
			"block":
				st["block"] = bool(op[1])
			"move":
				move = Vector2(float(op[1]), float(op[2]))
			"hp":
				f0.health.current = maxi(1, int(float(f0.health.maximum) * float(op[1])))
			"hp_dummy":
				f1.health.current = int(op[1])
			"stagger":
				f0.sm.enter_staggered(36, "hit")
	# keep both on the spot facing each other, the subject fed and the dummy alive until the finishing blows
	f0.stamina.current = f0.stamina.maximum
	f0.stamina.exhausted = false
	if t >= 0 and t < 930:
		f1.health.current = f1.health.maximum
	if sim.phase == CombatSimulation.Phase.ACTIVE:
		f0.teleport(Vector3(0.0, 0.0, -0.8), 0.0)
		f1.teleport(Vector3(0.0, 0.0, 0.8), PI)
	sim.submit_input(b0.build(move.x, move.y, 0.0, true, false, bool(st["block"])))
	sim.submit_input(b1.build(0.0, 0.0, PI, true, false, false))


static func _note(viol: Dictionary, name: String, severity: String, detail: String) -> void:
	if not viol.has(name):
		viol[name] = {"count": 0, "severity": severity, "first": detail}
	viol[name]["count"] = int(viol[name]["count"]) + 1


## One fighter, one tick: compare the state with what the model shows.
static func _observe(arena: CombatArena, m: CharacterModel, f: FighterController, viol: Dictionary, worst: Dictionary, mismatch_run: Array, i: int, out: Dictionary,
		cls: String, started: Dictionary) -> void:
	var sm := f.sm
	var held := m._hold_frames > 0
	m._process(DT)
	m.player.advance(DT)
	var clip := m._current
	if not out["clips_played"].has(cls):
		out["clips_played"][cls] = {}
		out["clip_starts"][cls] = {}
	var played: Dictionary = out["clips_played"][cls]
	played[clip] = int(played.get(clip, 0)) + 1
	if held:
		return
	var react_ok := (clip == "hit_react_light" or clip == "hit_react_heavy") and (sm.state == S.IDLE or sm.state == S.MOVING)
	var outcome_ok := m.outcome() != "" and sm.state != S.DEFEATED
	var expected: Array = STATE_FAMILY.get(sm.state, [])
	var attacking := false
	if sm.state == S.ATTACKING and sm.attack != null:
		attacking = true
		expected = [intended_attack_clip(sm.attack)]
	var ok: bool = clip in expected or react_ok or outcome_ok
	if ok:
		mismatch_run[i] = 0
	else:
		mismatch_run[i] = int(mismatch_run[i]) + 1
		if int(mismatch_run[i]) > 1:
			_note(viol, "clip matches the fighter state within one frame", "high", "tick %d state %s plays '%s', expected %s" % [sm.state_ticks, CombatConstants.state_name(sm.state), clip, str(expected)])
	if attacking or (sm.state == S.ABILITY_CASTING and sm.attack != null):
		var phase := sm.attack.phase_at(sm.state_ticks, sm.attack_total)
		if phase != AttackDefinition.Phase.RECOVERY and sm.state_ticks > 0 and not ok:
			_note(viol, "an attack clip is never cut off before its active window ends", "high", "%s tick %d/%d phase %d plays '%s'" % [sm.attack.id, sm.state_ticks, sm.attack_total, phase, clip])
	# playback position / rate vs what the model should be showing
	if not m.player.has_animation(clip):
		return
	var length: float = m.player.get_animation(clip).length
	var total := 0
	var startup_end := -1.0
	var warp_p := 1.0
	match sm.state:
		S.ATTACKING:
			if sm.attack != null:
				total = sm.attack_total
				startup_end = sm.attack.startup_end
				warp_p = Audit.warp_p_for(sm.attack)
		S.ABILITY_CASTING:
			total = sm.attack_total if sm.attack != null else sm.cast_total
		S.PARRYING:
			total = sm.parry_total
		S.DODGING:
			total = sm.dodge_total
		S.STAGGERED:
			total = sm.stun_total
	if total <= 0 or clip == "defeat" or react_ok or outcome_ok or not ok:
		return
	var u := clampf(float(sm.state_ticks) / float(total), 0.0, 1.0)
	var wp := CharacterModel.warp_progress(u, startup_end, warp_p)
	var start_s := CharacterModel.span_start(sm.attack) if sm.state == S.ABILITY_CASTING else 0.0
	var expected_t := minf(start_s + wp.x * (length - start_s), length)
	var err := absf(m.player.current_animation_position - expected_t)
	if sm.state_ticks > 0 and err > worst["pos"]:
		worst["pos"] = err
		if err > 0.07:
			_note(viol, "playback position stays near the sim-driven clip time", "medium", "%s tick %d/%d at %.3f s, expected %.3f s" % [clip, sm.state_ticks, total, m.player.current_animation_position, expected_t])
	var want_speed: float = ((length - start_s) / (float(total) / 60.0)) * wp.y
	var got := m.player.get_playing_speed()
	if want_speed > 0.0 and sm.state_ticks > 1 and sm.state_ticks < total - 1:
		var rerr := absf(got / want_speed - 1.0)
		# the anticipation warp changes the rate every tick; compare only where the rate is the plain clip/ticks ratio
		if wp.y == 1.0 and rerr > worst["speed"]:
			worst["speed"] = rerr


static func _settle_checks(rep: Dictionary, arena: CombatArena, m: CharacterModel, f: FighterController, cls: String) -> Dictionary:
	var info := {}
	var sm := f.sm
	var expect_clip := ""
	if sm.state == S.DEFEATED or m.outcome() == "lose":
		expect_clip = "defeat"
	elif m.outcome() == "win":
		expect_clip = "victory"
	info["outcome"] = m.outcome()
	info["state"] = CombatConstants.state_name(sm.state)
	info["clip"] = m._current
	Audit.check(rep, "h", cls, 0, expect_clip, "outcome settles on the right clip (%s)" % expect_clip, expect_clip == "" or m._current == expect_clip, m._current, expect_clip, "high")
	Audit.check(rep, "h", cls, 0, "", "hitstop hold is released after the fight", m._hold_frames == 0 and m.player.speed_scale != 0.0, m._hold_frames, 0, "high")
	var overlay_left := false
	for mi in m._meshes:
		if mi.material_overlay != null:
			overlay_left = true
	Audit.check(rep, "h", cls, 0, "", "hit flash overlay is cleared after the fight", not overlay_left and m._flash_t == 0.0, m._flash_t, 0.0, "medium")
	Audit.check(rep, "h", cls, 0, "", "flinch offset is cleared (model transform back at rest)", m._flinch == 0.0 and m.model.transform.is_equal_approx(m._model_base), m._flinch, 0.0, "medium")
	if expect_clip != "" and m.player.has_animation(expect_clip):
		var anim := m.player.get_animation(expect_clip)
		var pos := m.player.current_animation_position
		var settled := not m.player.is_playing() or anim.loop_mode != Animation.LOOP_NONE or pos >= anim.length - 0.02
		info["position"] = Audit._r(pos, 3)
		info["length"] = Audit._r(anim.length, 3)
		Audit.check(rep, "h", cls, 0, expect_clip, "%s settles on its final pose (position %.2f of %.2f s)" % [expect_clip, pos, anim.length], settled or expect_clip == "victory", pos, anim.length, "medium")
		# the skeleton really is at the clip's last frame, not stuck mid-blend
		var rig_pose := Audit.snap_node(m)
		var last := _last_pose(m, expect_clip)
		if not last.is_empty() and not rig_pose.is_empty():
			var d := _quat_rms(rig_pose, last)
			info["final_pose_delta_deg"] = Audit._r(d, 2)
			if d > 3.0 and OS.get_environment("AA_DEBUG") != "":
				for bi in rig_pose.size():
					var ang := rad_to_deg((rig_pose[bi] as Quaternion).angle_to(last[bi]))
					if ang > 5.0:
						print("   settle diff ", cls, " ", m.skeleton.get_bone_name(bi), " ", ang, " playing=", m.player.is_playing(), " cur=", m.player.current_animation, " _current=", m._current, " pos=", m.player.current_animation_position)
			Audit.check(rep, "h", cls, 0, expect_clip, "final skeleton pose equals the last frame of %s (no stuck blend)" % expect_clip, d <= 3.0, d, 3.0, "medium")
	return info


static func _last_pose(m: CharacterModel, clip: String) -> Array:
	var anim := m.player.get_animation(clip)
	var out: Array = []
	var skeleton := m.skeleton
	# sample the last key from the tracks directly: the player is left untouched
	for i in skeleton.get_bone_count():
		out.append(skeleton.get_bone_rest(i).basis.get_rotation_quaternion())   # un-animated bones keep their rest rotation
	var any := false
	for t in anim.get_track_count():
		if anim.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		var path := String(anim.track_get_path(t))
		var bone := path.substr(path.rfind(":") + 1)
		var bi := skeleton.find_bone(bone)
		if bi < 0:
			continue
		out[bi] = anim.rotation_track_interpolate(t, anim.length)
		any = true
	return out if any else []


static func _quat_rms(a: Array, b: Array) -> float:
	var sum := 0.0
	var n := 0
	for i in a.size():
		var ang := rad_to_deg((a[i] as Quaternion).angle_to(b[i]))
		sum += ang * ang
		n += 1
	return sqrt(sum / float(maxi(n, 1)))
