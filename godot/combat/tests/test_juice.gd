extends RefCounted
## "Juice" tests: hit weight tiers (hitstop / shake / punch scale with the blow), the capture sweep, the king-falls camera style and
## the victory card. All presentation: the important checks are that none of it touches the simulation and that reduce motion
## switches the motion off.

const Polish := preload("res://combat/tests/test_polish.gd")
const CameraRigScript := preload("res://world/camera_rig.gd")
const UiPrefsScript := preload("res://ui/theme/ui_prefs.gd")
const CombatVfx := preload("res://combat/presentation/vfx/combat_vfx.gd")
const Kind := AttackDefinition.Kind


static func run(h, tree: SceneTree) -> void:
	_weights(h)
	await _vfx_tiers(h, tree)
	_sweep(h)
	await _king_camera(h, tree)
	_victory_card(h)
	await _victory_in_hud(h, tree)


static func _weights(h) -> void:
	h.begin("juice: heavier blows freeze longer, shake harder and punch the camera more (light < heavy < ability < finisher)")
	var T := HitWeight.Tier
	h.eq(HitWeight.tier_for(Kind.LIGHT, 5, false), T.LIGHT, "a light attack is a light blow")
	h.eq(HitWeight.tier_for(Kind.HEAVY, 5, false), T.HEAVY, "a heavy (charged) attack is a heavy blow even for small damage")
	h.eq(HitWeight.tier_for(Kind.ABILITY, 5, false), T.ABILITY, "an ability attack is an ability blow")
	h.eq(HitWeight.tier_for(Kind.LIGHT, 5, true), T.FINISHER, "a knockout is always a finisher")
	h.eq(HitWeight.tier_for(-1, 30, false), T.HEAVY, "no attack information: big felt damage reads heavy")
	h.eq(HitWeight.tier_for(-1, 6, false), T.LIGHT, "no attack information: small felt damage reads light")
	var last_stop := 0
	var last_shake := 0.0
	var last_punch := 0.0
	for tier in [T.LIGHT, T.HEAVY, T.ABILITY, T.FINISHER]:
		var stop := HitWeight.hitstop_frames(tier, 20)
		var shake := HitWeight.shake_amount(tier, 20)
		var punch := float(HitWeight.profile(tier)["punch"])
		h.check(stop >= last_stop and stop <= 5, "hitstop frames never shrink with weight and stay within 5 (tier %d: %d)" % [tier, stop])
		h.check(shake > last_shake, "camera shake grows with weight (tier %d: %.2f)" % [tier, shake])
		h.check(punch > last_punch, "the camera punch grows with weight (tier %d: %.2f)" % [tier, punch])
		last_stop = stop
		last_shake = shake
		last_punch = punch
	h.check(HitWeight.hitstop_frames(T.LIGHT, 20) < HitWeight.hitstop_frames(T.FINISHER, 20), "a finisher freezes longer than a light hit")
	h.check(HitWeight.shake_amount(T.LIGHT, 60) > HitWeight.shake_amount(T.LIGHT, 4), "a bigger number shakes more within a tier")
	h.check(HitWeight.hitstop_frames(T.FINISHER, 90) <= 5, "hitstop is capped at 5 display frames")


static func _vfx_tiers(h, tree: SceneTree) -> void:
	h.begin("juice: CombatVfx classifies each landed hit and never changes the simulation")
	var arena := Polish._make_arena(tree, true, "q", "p", 61, "juice-tiers")
	for _i in 3:
		await tree.physics_frame
	var vfx: CombatVfx = arena.vfx
	var sim: CombatSimulation = arena.sim
	var a := sim.fighters[0]
	var d := sim.fighters[1]
	a.sm.attack = null   # no attack in progress, so the blow's felt damage alone decides the tier
	var before: Array = Polish._fighters_digest(sim)
	var tick := sim.server_tick
	var scale_ticks := Engine.time_scale
	vfx.on_event(Polish._event("hit", a.player_id, d.player_id, 0, 9001))
	h.eq(vfx.last_tier, HitWeight.Tier.LIGHT, "a small hit with no attack in progress is light (tier %d)" % vfx.last_tier)
	vfx.on_event(Polish._event("hit", a.player_id, d.player_id, 90, 9002))
	h.check(vfx.last_tier >= HitWeight.Tier.HEAVY, "a big hit is at least heavy (tier %d)" % vfx.last_tier)
	h.check(vfx.hold_frames() > 0 and vfx.hold_frames() <= 5, "the hit requested a display hitstop of 1..5 frames (%d)" % vfx.hold_frames())
	h.eq(sim.server_tick, tick, "the simulation tick is untouched by impact feedback")
	h.eq(Polish._fighters_digest(sim), before, "fighter state is untouched by impact feedback")
	h.eq(Engine.time_scale, scale_ticks, "no global time scale change for an ordinary hit (hitstop is display only)")
	arena.stop_battle()
	arena.queue_free()
	await tree.process_frame


static func _sweep(h) -> void:
	h.begin("juice: the capture sweep swings out and back, is zero at both ends and is off with reduce motion")
	var rig = CameraRigScript.new()
	rig.origin = Vector3.ZERO
	rig.focus_tile = Vector3(1.5, 0.0, -0.5)
	var pose := {"p": Vector3(1.5, 9.0, -0.5), "q": Quaternion(Vector3.RIGHT, -PI * 0.5), "fov": 22.0}
	var start: Dictionary = rig.sweep_pose(pose, 0.0)
	var end: Dictionary = rig.sweep_pose(pose, 1.0)
	h.check((start["p"] as Vector3).is_equal_approx(pose["p"]) and (end["p"] as Vector3).is_equal_approx(pose["p"]), "no offset at t = 0 and t = 1 (the steady pose is untouched)")
	var mid: Dictionary = rig.sweep_pose(pose, 0.5)
	h.check((mid["p"] as Vector3).distance_to(pose["p"]) > 1.0, "mid-sweep the camera has swung out (%.2f m)" % (mid["p"] as Vector3).distance_to(pose["p"]))
	h.check(not (mid["q"] as Quaternion).is_equal_approx(pose["q"]), "mid-sweep the view tilts toward the tile")
	var forward: Vector3 = (mid["q"] as Quaternion) * Vector3.FORWARD
	var to_tile: Vector3 = ((rig.origin + rig.focus_tile) - (mid["p"] as Vector3)).normalized()
	h.check(forward.dot(to_tile) > 0.9, "the swept camera still looks at the contested tile (dot %.2f)" % forward.dot(to_tile))
	h.eq(mid["fov"], pose["fov"], "the sweep does not touch the field of view")
	var steady_rm := ThirdPersonCamera.reduce_motion
	ThirdPersonCamera.reduce_motion = true
	h.check(CameraRigScript._reduce_motion(), "reduce motion (camera flag) switches the sweep off")
	ThirdPersonCamera.reduce_motion = false
	UiPrefsScript.reduce_motion = true
	h.check(CameraRigScript._reduce_motion(), "reduce motion (Settings preference) switches the sweep off")
	UiPrefsScript.reduce_motion = false
	h.check(not CameraRigScript._reduce_motion(), "with both off the sweep plays")
	ThirdPersonCamera.reduce_motion = steady_rm
	rig.free()


static func _king_camera(h, tree: SceneTree) -> void:
	h.begin("juice: the king-falls camera style, and reduce motion keeps it still")
	var arena := Polish._make_arena(tree, true, "q", "p", 62, "juice-king")
	for _i in 3:
		await tree.physics_frame
	var cam: ThirdPersonCamera = arena.cameras[0]
	ThirdPersonCamera.reduce_motion = false
	cam.set_finish(arena.sim.fighters[1], "king_fall")
	h.eq(cam.finish_style, "king_fall", "the finish style is recorded")
	for _i in 12:
		await tree.process_frame
	h.check(cam._finish_t > 0.0, "the cutscene camera runs")
	cam.set_finish(arena.sim.fighters[0])
	h.eq(cam.finish_style, "", "a normal finish resets the style")
	cam._fov_kick_target = 0.0   # let the first (motion-on) zoom release before testing the reduce-motion case
	cam._fov_hold = 0.0
	for _i in 120:
		await tree.process_frame
	ThirdPersonCamera.reduce_motion = true
	cam.set_finish(arena.sim.fighters[1], "king_fall")
	await tree.process_frame
	h.near(cam.camera.fov, ThirdPersonCamera.BASE_FOV, 0.3, "--reduce-motion: no zoom-in for the king's fall")
	ThirdPersonCamera.reduce_motion = false
	arena.stop_battle()
	arena.queue_free()
	await tree.process_frame


static func _victory_card(h) -> void:
	h.begin("juice: the victory card summarises the duel (headline, reason, both fighters' health) and handles the King's fall")
	var names := func(role: String) -> String: return FighterRoster.display_name(role)
	var attacker := {"role": "q", "color": "w", "max_hp": 100}
	var defender := {"role": "p", "color": "b", "max_hp": 50}
	var win := VictoryCard.info_for({"outcome": "attacker", "reason": "knockout", "attackerHp": 62, "defenderHp": 0}, attacker, defender, names)
	h.eq(win["title"], "QUEEN WINS", "the headline names the winning piece")
	h.eq(win["subtitle"], "Knockout", "the reason is spelled out")
	h.eq((win["rows"] as Array).size(), 2, "one summary row per fighter")
	h.near(float(win["rows"][0]["fraction"]), 0.62, 0.001, "the attacker's health fraction")
	h.eq(win["rows"][1]["hp"], 0, "the defender's remaining health")
	h.check(bool(win["rows"][0]["winner"]) and not bool(win["rows"][1]["winner"]), "only the winner's row is marked")
	var hold := VictoryCard.info_for({"outcome": "defender", "reason": "double_knockout", "attackerHp": 0, "defenderHp": 0}, attacker, defender, names)
	h.check(not bool(hold["rows"][0]["winner"]) and not bool(hold["rows"][1]["winner"]), "a double knockout marks nobody as the winner")
	var king := VictoryCard.info_for({"outcome": "attacker", "reason": "knockout", "attackerHp": 40, "defenderHp": 0}, attacker, {"role": "k", "color": "b", "max_hp": 120}, names)
	h.eq(king["title"], "THE KING HAS FALLEN", "a knocked-out King gets the cutscene headline")
	var card := VictoryCard.new()
	card.show_info(win, 800.0)
	h.eq(card._title.text, "QUEEN WINS", "show_info fills the headline")
	h.check(card._rows[0][2].text == "62 HP", "show_info fills the health text (%s)" % card._rows[0][2].text)
	card.play_in(true)
	h.eq(card.modulate.a, 1.0, "reduce motion: the card appears at once")
	card.free()


static func _victory_in_hud(h, tree: SceneTree) -> void:
	h.begin("juice: a finished duel shows the victory card in the HUD and a rematch hides it again")
	var arena := Polish._make_arena(tree, true, "q", "p", 63, "juice-hud")
	for _i in 3:
		await tree.physics_frame
	h.check(arena.hud.victory_card() == null, "no victory card before the duel ends")
	# Feed the arena the authoritative result the way the simulation does when the battle finishes.
	var result := {"outcome": "attacker", "reason": "knockout", "winnerPlayerId": arena.sim.fighters[0].player_id, "attackerHp": 50, "defenderHp": 0}
	arena._on_finished(result)
	var card: VictoryCard = arena.hud.victory_card()
	h.check(card != null and card.visible, "the victory card is shown")
	h.check(card != null and card.get_parent() == arena.hud._result_box, "...inside the HUD's result panel, above the buttons")
	h.check(not arena.hud._result_label.visible, "the plain text headline gives way to the card")
	arena.hud.hide_result()
	h.check(not arena.hud._result_panel.visible and not card.visible, "hide_result hides the card with the panel")
	h.check(arena.hud._result_label.visible, "...and restores the text headline for the next use")
	arena.stop_battle()
	arena.queue_free()
	await tree.process_frame
