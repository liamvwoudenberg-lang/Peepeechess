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
