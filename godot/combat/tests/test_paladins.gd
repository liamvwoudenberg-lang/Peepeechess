extends RefCounted
## The rigged paladin models as combat fighters: procedural clips, side textures, the PaladinFighter presentation inside a real arena.

const ARENA := "res://combat/arena.tscn"
const ROLES := ["p", "n", "b", "r", "q", "k"]
const REQUIRED := ["idle", "walk", "run", "strafe_left", "strafe_right", "light_1", "light_2", "light_3", "heavy", "block", "parry",
		"dodge", "stagger", "ability", "defeat", "victory", "hit_react_light", "hit_react_heavy", "climb", "ladder_idle", "drop_fall"]


static func run(h, tree: SceneTree) -> void:
	_models(h, tree)
	_remap(h)
	await _arena(h, tree)
	_config(h, tree)
	_hitbox_rules(h)
	await _debug_overlay(h, tree)


static func _models(h, tree: SceneTree) -> void:
	h.begin("paladins: every role in both colours has the full clip set, a skeleton and a sword")
	for role in ROLES:
		h.check(PaladinModel.available(role), "model file for %s exists" % role)
		var textures := {}
		for side in ["w", "b"]:
			var fighter := PaladinFighter.new()
			tree.root.add_child(fighter)
			if not h.check(fighter.setup_free(role, 0, side), "%s/%s sets up" % [role, side]):
				fighter.queue_free()
				continue
			var missing := []
			for clip in REQUIRED:
				if not fighter.has_clip(clip):
					missing.append(clip)
			h.eq(missing, [], "%s/%s has every clip" % [role, side])
			for clip in ["light_1", "light_2", "light_3", "heavy", "parry", "dodge", "stagger", "ability", "defeat"]:
				var length: float = fighter.player.get_animation(clip).length if fighter.has_clip(clip) else 0.0
				h.check(length > 0.3 and length < 3.0, "%s/%s %s length %.2f s is sane" % [role, side, clip, length])
			for clip in ["idle", "walk", "run", "block", "climb"]:
				h.check(fighter.has_clip(clip) and fighter.player.get_animation(clip).loop_mode == Animation.LOOP_LINEAR, "%s/%s %s loops" % [role, side, clip])
			h.check(fighter.socket("WeaponSocket_R") != null, "%s/%s has a sword socket" % [role, side])
			var mesh_instance: MeshInstance3D = (fighter.model as PaladinModel).meshes[0]
			var material := mesh_instance.get_surface_override_material(0) as StandardMaterial3D
			textures[side] = material.albedo_texture if material != null else null
			fighter.set_props_stowed(1.0)
			var sword: Node3D = fighter.socket("WeaponSocket_R").get_child(0)
			h.check(not sword.visible, "%s/%s the sword is stowed for the ladder" % [role, side])
			fighter.set_props_stowed(0.0)
			h.check(sword.visible and sword.scale.is_equal_approx(Vector3.ONE), "%s/%s ...and drawn again" % [role, side])
			fighter.queue_free()
		h.check(textures.get("w") != null and textures.get("b") != null and textures["w"] != textures["b"], "%s: the white and the black version use different textures" % role)


static func _remap(h) -> void:
	h.begin("paladins: the sim's hit window opens exactly on the clip's strike pose")
	var fighter := PaladinFighter.new()
	var s := PaladinClips.STRIKE
	for startup_end in [0.2, 0.35, 0.5, 0.7]:
		var at: Vector2 = fighter._remap_clip_time("light_1", startup_end, startup_end)
		h.check(absf(at.x - s) < 1e-5, "startup_end %.2f -> strike pose at %.2f of the clip" % [startup_end, at.x])
		h.eq(fighter._remap_clip_time("light_1", 0.0, startup_end).x, 0.0, "the clip starts with the attack")
		h.check(absf(fighter._remap_clip_time("light_1", 1.0, startup_end).x - 1.0) < 1e-5, "...and ends with it")
		var previous := -1.0
		var monotonic := true
		for i in 21:
			var x: float = fighter._remap_clip_time("heavy", float(i) / 20.0, startup_end).x
			monotonic = monotonic and x >= previous
			previous = x
		h.check(monotonic, "the remap is monotonic")
	h.eq(fighter._remap_clip_time("block", 0.4, 0.35), Vector2(0.4, 1.0), "other clips are not remapped")
	fighter.free()


static func _arena(h, tree: SceneTree) -> void:
	h.begin("paladins: a real arena fights with paladin visuals (both colours), clips follow the simulation, no fallback clip is used")
	PaladinFighter.prefer_paladins = true
	CharacterModel.fallback_counts.clear()
	var arena: CombatArena = (load(ARENA) as PackedScene).instantiate()
	tree.root.add_child(arena)
	arena.configure_seats({"player-white": {"type": "ai", "skill": 0.7}, "player-black": {"type": "ai", "skill": 0.6}})
	var reply: Dictionary = arena.start_battle(FighterRoster.build_request("n", "q", "w", "paladins-1", 7, 0))
	h.check(reply.get("ok", false), "the battle starts")
	var visuals: Array = arena._fighter_visuals
	h.eq(visuals.size(), 2, "two fighter visuals")
	var all_paladins := true
	for v in visuals:
		all_paladins = all_paladins and v is PaladinFighter
	h.check(all_paladins, "both are PaladinFighters")
	if all_paladins:
		var seen := {}
		for _i in 900:
			await tree.physics_frame
			for v in visuals:
				seen[(v as PaladinFighter)._current] = true
			if not arena.sim.is_running():
				break
		h.check(seen.has("idle") or seen.has("walk") or seen.has("run"), "locomotion clips played (%s)" % ", ".join(seen.keys()))
		h.check(seen.size() >= 3, "several different clips played during the fight (%d)" % seen.size())
		h.eq(CharacterModel.fallback_counts, {}, "no clip fell back to idle / flinch")
		var white_texture: Texture2D = (((visuals[0] as PaladinFighter).model as PaladinModel).meshes[0].get_surface_override_material(0) as StandardMaterial3D).albedo_texture
		var black_texture: Texture2D = (((visuals[1] as PaladinFighter).model as PaladinModel).meshes[0].get_surface_override_material(0) as StandardMaterial3D).albedo_texture
		h.check(white_texture != black_texture, "the two seats are the white and the black version")
	PaladinFighter.prefer_paladins = false
	arena.queue_free()
	await tree.process_frame


## Per-role configuration: heights agree with the fighter, the measured bodies are plausible, the models have no root motion (no sliding).
static func _config(h, tree: SceneTree) -> void:
	h.begin("paladins: per-role config (heights, measured bodies), the audit numbers and no root motion in the locomotion clips")
	h.eq(PaladinConfig.roles().size(), 6, "a config entry for every role")
	for role in ROLES:
		h.eq(PaladinConfig.height(role), float(PaladinFighter.HEIGHTS[role]), "%s: config height equals the fighter's height" % role)
		var r := PaladinConfig.body_radius(role)
		h.check(r > 0.10 and r < 0.30, "%s: measured body radius %.3f m is plausible" % [role, r])
		var audit := PaladinConfig.audit(role)
		h.check(float(audit["sim_radius"]) > 0.0 and float(audit["sim_reach"]) > 0.0, "%s: audit reads the simulation's radius %.2f and reach %.2f" % [role, audit["sim_radius"], audit["sim_reach"]])
		var model := PaladinModel.create(role, "w", PaladinConfig.height(role))
		tree.root.add_child(model)
		for clip in ["Walking", "Running"]:
			var anim := model.player.get_animation(clip)
			var drift := Vector2.ZERO
			for track in anim.get_track_count():
				if anim.track_get_type(track) == Animation.TYPE_POSITION_3D and String(anim.track_get_path(track)).ends_with(":mixamorig_Hips"):
					var a: Vector3 = anim.track_get_key_value(track, 0)
					var b: Vector3 = anim.track_get_key_value(track, anim.track_get_key_count(track) - 1)
					drift = Vector2(b.x - a.x, b.z - a.z)
			h.check(drift.length() < 0.05, "%s: %s has no root motion (hips drift %.3f)" % [role, clip, drift.length()])
		model.queue_free()


## Hit detection rules of the simulation: only in the ACTIVE frames, once per swing per target, never against oneself.
static func _hitbox_rules(h) -> void:
	h.begin("combat audit: hit sector only while ACTIVE, one hit per swing and target, no self-hit, facing")
	var near := Vector3(1.0, 0.0, 0.0)
	h.check(HitboxController.in_sector(Vector3.ZERO, PI * 0.5, 1.6, 100.0, near, 0.4), "a target straight ahead inside reach is hit")
	h.check(not HitboxController.in_sector(Vector3.ZERO, -PI * 0.5, 1.6, 100.0, near, 0.4), "a target behind the attacker is not hit")
	h.check(not HitboxController.in_sector(Vector3.ZERO, PI * 0.5, 1.6, 100.0, Vector3(4.0, 0, 0), 0.4), "a target beyond reach is not hit")
	var sim := CombatSimulation.new()
	var request := FighterRoster.build_request("p", "n", "w", "audit", 11, 0)
	h.check(sim.start(request, {"attacker_edge": false}).get("ok", false), "a bare simulation starts")
	var a: FighterController = sim.attacker()
	var d: FighterController = sim.defender()
	a.teleport(Vector3(0, 0, 0), PI * 0.5)
	d.teleport(Vector3(1.2, 0, 0), -PI * 0.5)
	h.check(not a.hitbox.try_hit(a, d), "no hit while the attacker is not in an ACTIVE attack state")
	h.check(not a.hitbox.shape(a).get("active", false), "the live hit shape is inactive outside the active frames")
	sim.free()


## The developer overlay: off by default, switchable, describes the combat state, draws the live hit sector only on active frames.
static func _debug_overlay(h, tree: SceneTree) -> void:
	h.begin("combat debug: overlay is off by default, toggles, describes state and shows the live hit sector only on active frames")
	CombatDebug.set_enabled(false)
	PaladinFighter.prefer_paladins = true
	var arena: CombatArena = (load(ARENA) as PackedScene).instantiate()
	tree.root.add_child(arena)
	arena.configure_seats({"player-white": {"type": "ai", "skill": 0.9}, "player-black": {"type": "ai", "skill": 0.9}})
	arena.start_battle(FighterRoster.build_request("n", "p", "w", "debug-1", 5, 0))
	var overlay: CombatDebug = arena.get_node_or_null("CombatDebug")
	if not h.check(overlay != null, "the arena carries a CombatDebug node"):
		arena.queue_free()
		return
	await tree.physics_frame
	await tree.process_frame
	h.check(not CombatDebug.enabled and not overlay._lines.visible and not overlay._layer.visible, "off by default: nothing is drawn")
	CombatDebug.set_enabled(true)
	var saw_active := false
	var saw_inactive := false
	var consistent := true
	for _i in 900:
		await tree.physics_frame
		await tree.process_frame
		var f: FighterController = arena.sim.fighters[0]
		var active: bool = f.hitbox.shape(f).get("active", false)
		saw_active = saw_active or active
		saw_inactive = saw_inactive or not active
		# the overlay's text reports ACTIVE exactly when the simulation's attack is active
		var text := CombatDebug.describe(f, "x")
		if (" ACTIVE" in text) != f.sm.attack_active():
			consistent = false
		if not arena.sim.is_running():
			break
	h.check(overlay._lines.visible and overlay._layer.visible and overlay._label.text.length() > 20, "on: lines and the state panel are shown")
	h.check(saw_active and saw_inactive, "the fight had both active and inactive swing frames")
	h.check(consistent, "the panel marks ACTIVE exactly on the simulation's active attack frames")
	var line: String = CombatDebug.describe(arena.sim.fighters[0], "idle")
	for needle in ["hp ", "stam ", "combo ", "swing #", "clip idle"]:
		h.check(needle in line, "the panel shows '%s'" % needle)
	CombatDebug.set_enabled(false)
	PaladinFighter.prefer_paladins = false
	arena.queue_free()
	await tree.process_frame
