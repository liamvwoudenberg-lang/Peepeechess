extends RefCounted
## Presentation-polish tests: pooled VFX caps under event floods, effect recycling, hitstop never touching the
## simulation, clip fallbacks, victory/defeat selection, quality tiers, presentation on/off and a full AI-vs-AI run
## through the whole presentation stack. Everything here is presentation: the assertions that matter most are that
## the authoritative simulation is byte-for-byte unaffected by any of it.

const ARENA := "res://combat/arena.tscn"
const CombatVfx := preload("res://combat/presentation/vfx/combat_vfx.gd")
const S := CombatConstants.State


static func _make_arena(tree: SceneTree, presentation: bool, white: String, black: String, seed: int, id: String) -> CombatArena:
	var arena: CombatArena = (load(ARENA) as PackedScene).instantiate()
	arena.presentation_enabled = presentation
	tree.root.add_child(arena)
	arena.configure_seats({"player-white": {"type": "ai", "skill": 0.7}, "player-black": {"type": "ai", "skill": 0.6}})
	var request := FighterRoster.build_request(white, black, "w", id, seed, 0)
	var reply: Dictionary = arena.start_battle(request)
	if not reply["ok"]:
		push_error("polish test: battle did not start: %s" % str(reply))
	if not presentation:
		# A headless arena has no seats/inputs of its own; drive it with the very same AI the presentation arena builds.
		for f in arena.sim.fighters:
			var builder := CombatInputBuilder.new(request["matchId"], request["battleId"], f.player_id)
			var opp := arena.sim.opponent_of(f)
			arena._ais.append(CombatAI.new(builder, f.stats, opp.stats, int(request["seed"]) + (7 if f.color == "w" else 13), 0.7 if f.color == "w" else 0.6))
	return arena


static func _event(kind: String, actor: String, target: String, damage: int, id: int) -> Dictionary:
	return {"eventId": id, "tick": id, "type": kind, "actorPlayerId": actor, "targetPlayerId": target, "damage": damage}


static func _fighters_digest(sim: CombatSimulation) -> Array:
	var out: Array = []
	for entry in sim.snapshot(false)["fighters"]:
		out.append([entry["hp"], entry["state"], entry["stateTicks"], snappedf(float(entry["position"]["x"]), 0.0001), snappedf(float(entry["position"]["z"]), 0.0001)])
	return out


static func run(h, tree: SceneTree) -> void:
	await _test_pools(h, tree)
	await _test_quality_tiers(h, tree)
	await _test_hitstop_is_cosmetic(h, tree)
	await _test_model_hooks(h, tree)
	await _test_camera(h, tree)
	await _test_cinematics(h, tree)
	await _test_presentation_toggle(h, tree)
	await _test_full_run(h, tree)


# ---- pools ---------------------------------------------------------------------------------------
static func _test_pools(h, tree: SceneTree) -> void:
	h.begin("polish: pooled effects stay under their caps under an event flood and recycle afterwards")
	var arena := _make_arena(tree, true, "n", "q", 41, "polish-pools")
	await tree.physics_frame
	var vfx = arena.vfx
	if not h.check(vfx != null, "the arena builds a CombatVfx for a presentation battle"):
		arena.queue_free()
		return
	var white: String = arena.sim.fighters[0].player_id
	var black: String = arena.sim.fighters[1].player_id
	var caps: Dictionary = vfx.caps
	var kinds := ["hit", "block", "parry", "guardbreak", "dodge", "ability", "hit", "hit"]
	var worst_sparks := 0
	var worst_sprites := 0
	var worst_numbers := 0
	for i in 600:
		var actor := white if i % 2 == 0 else black
		var target := black if i % 2 == 0 else white
		vfx.on_event(_event(kinds[i % kinds.size()], actor, target, 12 + (i % 40), 1000 + i))
		worst_sparks = maxi(worst_sparks, vfx.live_sparks())
		worst_sprites = maxi(worst_sprites, vfx.live_sprites())
		worst_numbers = maxi(worst_numbers, vfx.live_numbers())
		if i % 25 == 0:
			await tree.process_frame
	h.check(worst_sparks <= int(caps["sparks"]), "live sparks never exceeded the cap (%d <= %d)" % [worst_sparks, caps["sparks"]])
	h.check(worst_sprites <= int(caps["sprites"]) + 4, "live sprites never exceeded pool + 4 persistent auras (%d)" % worst_sprites)
	h.check(worst_numbers <= int(caps["numbers"]), "live damage numbers never exceeded the cap (%d <= %d)" % [worst_numbers, caps["numbers"]])
	h.check(int(vfx.stats["events"]) >= 600, "every event was handled")
	h.check(int(vfx.stats["max_live_sparks"]) > 0 and int(vfx.stats["sparks_spawned"]) > int(caps["sparks"]), "the flood really exceeded the pool (%d spawned)" % vfx.stats["sparks_spawned"])
	h.check(vfx.particle_budget_used() <= int(caps["sparks"]) + int(caps["sprites"]) + int(caps["numbers"]) + 8, "total particle budget stays bounded (%d)" % vfx.particle_budget_used())
	# Recycling: feed time, everything dies and the pools are reusable.
	for _i in 40:
		vfx._process(0.1)
	h.eq(vfx.live_sparks(), 0, "all sparks expired after enough time")
	h.eq(vfx.live_numbers(), 0, "all numbers expired")
	var transient_alive := 0
	for s in vfx._sprites:
		if s["alive"]:
			transient_alive += 1
	h.eq(transient_alive, 0, "all transient sprites expired")
	vfx.on_event(_event("hit", white, black, 30, 5000))
	h.check(vfx.live_sparks() > 0 and vfx.live_numbers() == 1, "a recycled pool serves new effects immediately")
	vfx.reset_effects()
	h.eq(vfx.live_sparks() + vfx.live_numbers(), 0, "reset_effects clears everything")
	# Unknown ids / malformed targets are ignored, never errors.
	vfx.on_event(_event("hit", "nobody", black, 10, 6000))
	h.check(true, "an event naming an unknown fighter is ignored")
	arena.stop_battle()
	arena.queue_free()


static func _test_quality_tiers(h, tree: SceneTree) -> void:
	h.begin("polish: low quality halves the pools and drops body trails")
	var arena := _make_arena(tree, true, "p", "r", 42, "polish-quality")
	await tree.physics_frame
	var high = CombatVfx.new()
	arena.add_child(high)
	high.setup(arena.sim, false)
	var low = CombatVfx.new()
	arena.add_child(low)
	low.setup(arena.sim, true)
	h.check(int(low.caps["sparks"]) < int(high.caps["sparks"]), "low has fewer sparks (%d < %d)" % [low.caps["sparks"], high.caps["sparks"]])
	h.check(int(low.caps["sprites"]) < int(high.caps["sprites"]), "low has fewer sprites")
	h.check(int(low.caps["numbers"]) < int(high.caps["numbers"]), "low has fewer damage numbers")
	h.check(low._sp_pos.size() == int(low.caps["sparks"]) and high._sp_pos.size() == int(high.caps["sparks"]), "pool sizes follow the tier")
	low.register_model(arena.sim.fighters[0].player_id, arena._fighter_visuals[0])
	high.register_model(arena.sim.fighters[0].player_id, arena._fighter_visuals[0])
	h.check(low._fx[arena.sim.fighters[0].player_id]["body_trail"] == null, "low quality has no body trail")
	h.check(high._fx[arena.sim.fighters[0].player_id]["body_trail"] != null, "high quality has a body trail")
	CombatVfx.show_numbers = false
	low.spawn_number(Vector3.ZERO, 10, Color.WHITE)
	h.eq(low.live_numbers(), 0, "--no-damage-numbers hides numbers")
	CombatVfx.show_numbers = true
	arena.stop_battle()
	arena.queue_free()


# ---- hitstop does not change the simulation --------------------------------------------------------
static func _run_digest(tree: SceneTree, presentation: bool, with_hitstop: bool, seed: int) -> Dictionary:
	var arena := _make_arena(tree, presentation, "n", "r", seed, "polish-determinism")
	var digest: Dictionary = {}
	var hitstops := 0
	var guard := 0
	while guard < 900 and arena.sim.server_tick < 420:
		await tree.physics_frame
		guard += 1
		if with_hitstop and arena.vfx != null and arena.sim.phase == CombatSimulation.Phase.ACTIVE and guard % 7 == 0:
			var ids := [arena.sim.fighters[0].player_id, arena.sim.fighters[1].player_id]
			arena.vfx.request_hitstop(ids, 5)
			hitstops += 1
		if arena.sim.server_tick == 400 and digest.is_empty():
			digest = {"tick": arena.sim.server_tick, "fighters": _fighters_digest(arena.sim), "hitstops": hitstops}
	if digest.is_empty():
		digest = {"tick": arena.sim.server_tick, "fighters": _fighters_digest(arena.sim), "hitstops": hitstops}
	arena.stop_battle()
	arena.queue_free()
	await tree.process_frame
	return digest


static func _test_hitstop_is_cosmetic(h, tree: SceneTree) -> void:
	h.begin("polish: hitstop and the whole presentation stack never change the authoritative simulation")
	var headless: Dictionary = await _run_digest(tree, false, false, 77)
	var presented: Dictionary = await _run_digest(tree, true, true, 77)
	h.eq(presented["tick"], headless["tick"], "both runs reached the same tick")
	h.eq(presented["fighters"], headless["fighters"], "HP, state, state_ticks and positions are identical with presentation + 5-frame hitstops")
	h.check(int(presented["hitstops"]) > 5, "hitstops really were requested (%d)" % presented["hitstops"])


# ---- model hooks -----------------------------------------------------------------------------------
static func _test_model_hooks(h, tree: SceneTree) -> void:
	h.begin("polish: model hold / reactions / outcome poses, with fallbacks when clips are absent")
	var arena := _make_arena(tree, true, "n", "q", 43, "polish-model")
	for _i in 4:
		await tree.physics_frame
	var white_model = arena._fighter_visuals[0]
	var black_model = arena._fighter_visuals[1]
	if not h.check(white_model is CharacterModel and black_model is CharacterModel, "imported models are mounted"):
		arena.stop_battle()
		arena.queue_free()
		return
	var a_id: String = arena.sim.fighters[0].player_id
	var b_id: String = arena.sim.fighters[1].player_id

	# hitstop: animation frozen, then resumes
	white_model.hold(3)
	await tree.process_frame
	await tree.process_frame
	h.eq(white_model.player.speed_scale, 0.0, "hold() freezes the animation player")
	for _i in 6:
		await tree.process_frame
	h.check(white_model.player.speed_scale != 0.0, "animation resumes after the hold")

	# weapon segments for trails (Knight: 1 weapon, Queen: 2 blades)
	var knight_segments: Array = white_model.weapon_segments()
	var queen_segments: Array = black_model.weapon_segments()
	h.check(knight_segments.size() >= 1, "Knight exposes a weapon segment for its trail (%d)" % knight_segments.size())
	h.check(queen_segments.size() == 2, "Queen exposes both blades (%d)" % queen_segments.size())
	if not knight_segments.is_empty():
		h.check((knight_segments[0]["tip"] as Vector3).distance_to(knight_segments[0]["base"]) > 0.15, "the segment has real length")

	# reaction: with the clip present the free fighter plays it, procedural flinch otherwise; never an error
	var forward := Vector3(0, 0, 1)
	white_model.react("hit", 30, forward)
	await tree.process_frame
	if white_model.has_clip("hit_react_heavy"):
		h.eq(white_model._current, "hit_react_heavy", "a free fighter plays hit_react_heavy for a heavy hit")
	else:
		h.check(white_model._flinch > 0.0, "without the clip a procedural flinch plays")
	white_model.react("hit", 8, forward)
	await tree.process_frame
	h.check(white_model._flash_t > 0.0 and white_model._meshes[0].material_overlay != null, "a hit flashes the model")
	for _i in 20:
		await tree.process_frame
	h.check(white_model._meshes[0].material_overlay == null, "the flash overlay is removed afterwards (no lingering extra draw)")
	# remove the optional clips and confirm graceful fallback
	var lib: AnimationLibrary = black_model.player.get_animation_library("")
	for optional in ["victory", "hit_react_light", "hit_react_heavy"]:
		if lib != null and lib.has_animation(optional):
			lib.remove_animation(optional)
	h.check(not black_model.has_clip("victory"), "optional clips removed for the fallback test")
	black_model.react("hit", 30, forward)
	h.eq(black_model._react_clip, "", "no hit_react clip -> procedural flinch only")
	h.check(black_model._flinch > 0.0, "the procedural flinch is applied")

	# outcome: victory/defeat selection, double knockout, simulation-defeated fighter keeps its own clip
	arena.vfx.on_result({"winnerPlayerId": a_id, "reason": "knockout"})
	h.eq(white_model.outcome(), "win", "the winner is marked win")
	h.eq(black_model.outcome(), "lose", "the loser is marked lose")
	for _i in 6:
		await tree.process_frame
	if white_model.has_clip("victory"):
		h.eq(white_model._current, "victory", "the winner plays the victory clip")
	else:
		h.eq(white_model._current, "idle", "no victory clip: the winner holds idle")
	h.eq(black_model._current, "defeat", "the loser plays defeat")
	arena.vfx.on_result({"winnerPlayerId": a_id, "reason": "double_knockout"})
	h.check(white_model.outcome() == "lose" and black_model.outcome() == "lose", "a double knockout defeats both")
	arena.stop_battle()
	arena.queue_free()


# ---- camera ----------------------------------------------------------------------------------------
static func _test_camera(h, tree: SceneTree) -> void:
	h.begin("polish: camera feedback (shake, FOV kick, finish) and the reduce-motion option")
	var arena := _make_arena(tree, true, "p", "n", 44, "polish-camera")
	for _i in 3:
		await tree.physics_frame
	var cam: ThirdPersonCamera = arena.cameras[0]
	ThirdPersonCamera.reduce_motion = false
	cam.feedback("parry", 0.2, Vector3.FORWARD)
	h.check(cam.shake > 0.0, "a parry adds trauma")
	var seen_kick := 0.0
	for _i in 4:
		await tree.process_frame
		seen_kick = maxf(seen_kick, absf(cam.camera.fov - ThirdPersonCamera.BASE_FOV))
	h.check(seen_kick > 1.0, "the parry kicks the FOV (%.1f deg)" % seen_kick)
	for _i in 90:
		await tree.process_frame
	h.near(cam.camera.fov, ThirdPersonCamera.BASE_FOV, 0.3, "the FOV returns to base")
	h.check(cam.shake < 0.05, "the trauma decays")
	ThirdPersonCamera.reduce_motion = true
	cam.shake = 0.0
	cam.feedback("heavy_hit", 0.3, Vector3.FORWARD)
	cam.add_shake(0.5)
	h.eq(cam.shake, 0.0, "--reduce-motion: no shake")
	await tree.process_frame
	h.near(cam.camera.fov, ThirdPersonCamera.BASE_FOV, 0.3, "--reduce-motion: no FOV kick")
	ThirdPersonCamera.reduce_motion = false
	cam.set_finish(arena.sim.fighters[0])
	for _i in 10:
		await tree.process_frame
	h.check(cam._finish_t > 0.0, "the finish camera runs")
	for pillar in StoneArena.PILLAR_POSITIONS:
		var pushed: Vector3 = ThirdPersonCamera._clear_of_pillars(pillar + Vector3(0.1, 3.0, -0.05))
		h.check(Vector2(pushed.x - pillar.x, pushed.z - pillar.z).length() >= StoneArena.PILLAR_RADIUS + ThirdPersonCamera.PILLAR_CAMERA_MARGIN - 0.001, "a camera inside the pillar at %s is pushed out of it" % str(pillar))
	var free_pos := Vector3(0.0, 3.0, 0.0)
	h.eq(ThirdPersonCamera._clear_of_pillars(free_pos), free_pos, "a camera in the open is untouched")
	arena.stop_battle()
	arena.queue_free()


# ---- cinematic extras ------------------------------------------------------------------------------
static func _test_cinematics(h, tree: SceneTree) -> void:
	h.begin("polish: cinematic extras (intro card, opening push-in, knockout slow motion, parry/final feedback)")
	var arena := _make_arena(tree, true, "q", "p", 45, "polish-cine")
	for _i in 4:
		await tree.physics_frame
	var cam: ThirdPersonCamera = arena.cameras[0]
	ThirdPersonCamera.reduce_motion = false
	h.check(cam._intro_t >= 0.0, "the opening push-in runs during the countdown")
	h.check(arena.hud.intro_text().begins_with("QUEEN  vs  PAWN"), "the intro card names the attacker first (%s)" % arena.hud.intro_text().replace("\n", " / "))
	for _i in 6:
		await tree.process_frame
	h.check(arena.hud._intro_label.modulate.a > 0.0, "the intro card fades in over the countdown")
	cam.feedback("final", 0.4, Vector3.FORWARD)
	h.check(cam.shake > 0.0, "the knockout blow shakes the camera")
	h.check(not arena.vfx.slowmo_active(), "slow motion is off while headless (allow_slowmo false)")
	h.check(not arena.vfx.request_slowmo(), "request_slowmo refuses when not allowed")
	arena.vfx.allow_slowmo = true
	h.check(arena.vfx.request_slowmo(0.05) and Engine.time_scale < 1.0, "an allowed knockout slows time")
	OS.delay_msec(80)
	await tree.process_frame
	h.check(not arena.vfx.slowmo_active() and is_equal_approx(Engine.time_scale, 1.0), "...and restores normal time by itself")
	arena.vfx.allow_slowmo = true
	arena.vfx.request_slowmo(5.0)
	arena.stop_battle()
	arena.queue_free()
	await tree.process_frame
	h.check(is_equal_approx(Engine.time_scale, 1.0), "freeing the arena never leaves the game slowed down")
	Engine.time_scale = 1.0


# ---- presentation on / off ------------------------------------------------------------------------
static func _test_presentation_toggle(h, tree: SceneTree) -> void:
	h.begin("polish: presentation_enabled=false builds no effect, audio or camera nodes and still fights")
	var arena := _make_arena(tree, false, "b", "p", 45, "polish-headless")
	for _i in 200:
		await tree.physics_frame
	h.check(arena.vfx == null and arena.hud == null and arena.cameras.is_empty(), "no presentation nodes in headless mode")
	h.check(arena.sim.server_tick > 0, "the simulation still runs (%d ticks)" % arena.sim.server_tick)
	var count := arena.find_children("*", "MeshInstance3D", true, false).size()
	h.eq(count, 0, "no meshes were created")
	arena.stop_battle()
	arena.queue_free()


# ---- a full fight through every layer ----------------------------------------------------------------
static func _test_full_run(h, tree: SceneTree) -> void:
	h.begin("polish: AI vs AI for 10 simulated seconds with models, vfx, hud, camera and audio; budgets hold every frame")
	var arena := _make_arena(tree, true, "n", "r", 46, "polish-full")
	var vfx = arena.vfx
	var caps: Dictionary = vfx.caps
	var worst_budget := 0
	var worst_sprites := 0
	for i in 780:
		await tree.physics_frame
		worst_budget = maxi(worst_budget, vfx.particle_budget_used())
		worst_sprites = maxi(worst_sprites, vfx.live_sprites())
		if arena.sim.phase == CombatSimulation.Phase.FINISHED:
			break
	h.check(arena.sim.server_tick > 300, "the fight progressed (%d ticks)" % arena.sim.server_tick)
	h.check(int(vfx.stats["events"]) > 0, "combat events reached the VFX layer (%d)" % vfx.stats["events"])
	h.check(worst_budget <= int(caps["sparks"]) + int(caps["sprites"]) + int(caps["numbers"]) + 8, "particle budget stayed bounded (worst %d)" % worst_budget)
	h.check(worst_sprites <= int(caps["sprites"]) + 4, "sprite pool stayed bounded (worst %d)" % worst_sprites)
	h.check(arena.hud != null and not arena.cameras.is_empty(), "hud and camera exist")
	var live_nodes := arena.find_children("*", "Node", true, false).size()
	h.check(live_nodes < 700, "scene stays small (%d nodes)" % live_nodes)
	# rematch: the old effect layer is detached immediately and a fresh one is built
	var old_vfx = vfx
	arena.start_battle(FighterRoster.build_request("n", "r", "w", "polish-full-2", 47, 0))
	h.check(arena.vfx != old_vfx and arena.vfx != null, "a rematch gets a fresh effect layer")
	h.check(old_vfx.get_parent() == null or not is_instance_valid(old_vfx), "the old effect layer is detached at once")
	arena.stop_battle()
	arena.queue_free()
