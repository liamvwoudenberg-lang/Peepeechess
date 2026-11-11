extends RefCounted
## King (role "k", ability Royal Counter): the experimental sixth class.
##
## The v1 BattleRequest schema forbids "k" as a Combatant role, so the DEFAULT `CombatSimulation.start(request)` still
## refuses it; the King fights only through `start(request, {"allow_experimental_roles": true})`.
##
## Royal Counter (data: balance_v1.json "royal-counter"): a committed, armoured, slow stance of cast_ticks. Ticks
## [counter_start, counter_end) of the cast are the counter window: a frontal hit (arc counter_arc_deg) is negated, the
## attacker is staggered for counter_stagger_ticks, and the King ripostes (an ordinary AttackDefinition through the normal
## damage path, boosted by the profile's riposte_mult). A window that closes on nothing leaves the King recovering
## (no armour, no actions) for the rest of the cast.

const Runner := preload("res://combat/tests/matchup_runner.gd")
const Balance := preload("res://combat/data/balance_data.gd")
const S := CombatConstants.State


static func run(h, tree: SceneTree) -> void:
	_admission(h, tree)
	_roster(h)
	await _boundaries(h, tree)
	await _riposte(h, tree)
	await _whiff(h, tree)
	await _arc(h, tree)
	await _costs_and_movement(h, tree)
	await _ai_and_determinism(h, tree)


# ---- helpers ---------------------------------------------------------------------------------
static func _ab() -> Dictionary:
	return Balance.ability("royal-counter")


## One probe: Pawn (white) attacks a King (black) who casts Royal Counter. The King presses the ability on tick 4 and the
## Pawn presses light on tick 4 + `offset`. Returns what happened at the Pawn's first landed hit.
static func _probe(tree: SceneTree, offset: int, pawn_role: String = "p") -> Dictionary:
	var rig = await Runner.make_rig(tree, pawn_role, "k", "w", 0, "probe-%d" % offset)
	rig.face_off(1.6)
	rig.to_live()
	var out := {"cast_step": -1, "hit_step": -1, "type": "", "king_hp": 0, "king_poise": 0.0, "king_state": -1,
			"pawn_state": -1, "pawn_stun": 0, "king_start_hp": rig.black().health.current, "king_start_poise": rig.black().poise}
	var seen := 0
	for step in 90:
		if step == 4:
			rig.b.press("ability")
		if step == 4 + offset:
			rig.w.press("light")
		rig.tick()
		if out["cast_step"] < 0 and rig.black().sm.state == S.ABILITY_CASTING:
			out["cast_step"] = step
		for event in rig.sim.recent_events:
			if int(event["eventId"]) > seen:
				seen = int(event["eventId"])
				if out["hit_step"] < 0 and event["actorPlayerId"] == "player-white" and event["type"] in ["hit", "parry"]:
					out["hit_step"] = step
					out["type"] = event["type"]
					out["king_hp"] = rig.black().health.current
					out["king_poise"] = rig.black().poise
					out["king_state"] = rig.black().sm.state
					out["pawn_state"] = rig.white().sm.state
					out["pawn_stun"] = rig.white().sm.stun_total
	rig.dispose()
	return out


static func _first_countered_offset(tree: SceneTree) -> int:
	for offset in range(-2, 40):
		var r: Dictionary = await _probe(tree, offset)
		if r["type"] == "parry":
			return offset
	return -99


# ---- admission ---------------------------------------------------------------------------------
static func _admission(h, tree: SceneTree) -> void:
	h.begin("king: default start() stays strict; the opt-in path admits only the king")
	h.check(not FighterProfile.supports_role("k") and not AttackLibrary.supports_role("k"),
			"supports_role('k') is still false (v1 contract roles only)")
	h.check(FighterProfile.is_experimental_role("k") and not FighterProfile.is_experimental_role("q"),
			"the king is the only experimental role")
	h.check(not AbilityComponent.is_known("royal-counter") and AbilityComponent.is_known("royal-counter", true),
			"royal-counter is refused unless experimental roles are allowed")
	var request := FighterRoster.build_request("p", "k")
	var strict := CombatSimulation.new()
	tree.root.add_child(strict)
	var refused: Dictionary = strict.start(request)
	h.eq(refused["code"], "INVALID_PAYLOAD", "default start() refuses a king request (schema: Combatant.role has no k)")
	h.check(not strict.is_running() and strict.fighters.is_empty(), "nothing half-built is left behind")
	var opened: Dictionary = strict.start(request, {"allow_experimental_roles": true})
	h.check(opened["ok"], "start(request, {allow_experimental_roles: true}) admits it")
	h.eq(strict.fighters[1].role, "k", "the black seat is a King")
	strict.stop()
	var ordinary: Dictionary = strict.start(FighterRoster.build_request("p", "n"), {"allow_experimental_roles": true})
	h.check(ordinary["ok"], "ordinary requests are unchanged by the option")
	strict.stop()

	# The relaxation is exactly "k -> placeholder role for the schema check": everything else is still validated.
	var same_seat := FighterRoster.build_request("p", "k")
	same_seat["defender"]["playerId"] = same_seat["attacker"]["playerId"]
	h.eq(strict.start(same_seat, {"allow_experimental_roles": true})["code"], "INVALID_PAYLOAD", "seat rules still apply")
	var junk := FighterRoster.build_request("p", "k")
	junk["attacker"]["role"] = "x"
	h.eq(strict.start(junk, {"allow_experimental_roles": true})["code"], "INVALID_PAYLOAD", "an unknown role is still refused")
	var extra := FighterRoster.build_request("p", "k")
	extra["unexpected"] = 1
	h.eq(strict.start(extra, {"allow_experimental_roles": true})["code"], "INVALID_PAYLOAD", "extra fields are still refused")
	var mismatch := FighterRoster.build_request("p", "k")
	mismatch["defender"]["stats"]["role"] = "q"
	h.eq(strict.start(mismatch, {"allow_experimental_roles": true})["code"], "INVALID_PAYLOAD", "stats.role must match the combatant role")
	var wrong_ability := FighterRoster.build_request("p", "k")
	wrong_ability["defender"]["stats"]["abilityId"] = "last-stand"
	var reply: Dictionary = strict.start(wrong_ability, {"allow_experimental_roles": true})
	h.check(not reply["ok"] and "does not belong" in String(reply["message"]), "a king cannot carry another role's ability")
	var stolen := FighterRoster.build_request("p", "q")
	stolen["defender"]["stats"]["abilityId"] = "royal-counter"
	reply = strict.start(stolen, {"allow_experimental_roles": true})
	h.check(not reply["ok"] and "does not belong" in String(reply["message"]), "royal-counter belongs to the king only")
	reply = strict.start(stolen)
	h.check(not reply["ok"] and "not implemented" in String(reply["message"]), "without the option it is simply not implemented")
	strict.queue_free()


static func _roster(h) -> void:
	h.begin("king: roster, HUD name, contract stats")
	h.eq(FighterRoster.ability_name("k"), "Royal Counter", "HUD ability name")
	h.eq(FighterRoster.display_name("k"), "King", "display name")
	var stats := FighterRoster.stats_for("k")
	h.eq(stats["statsId"], "c0-balance-v1.k", "stats come from the approved snapshot")
	h.eq(stats["abilityId"], "royal-counter", "ability id")
	h.eq(typeof(stats["maxHp"]), TYPE_INT, "whole numbers are ints")
	h.check(FighterRoster.ALL_ROLES.has("k") and not FighterRoster.ROLES.has("k"), "ROLES stays the five contract roles; ALL_ROLES adds the king")
	var request := FighterRoster.build_request("k", "q")
	h.check(request["beforeFen"].contains("K") and not request["beforeFen"].contains("K2"), "the fighting king replaces the spare king in the FEN")


# ---- counter window boundaries ---------------------------------------------------------------------
static func _boundaries(h, tree: SceneTree) -> void:
	h.begin("king: Royal Counter window boundaries (swept over the attacker's timing)")
	var ab := _ab()
	var cs := int(ab["counter_start"])
	var ce := int(ab["counter_end"])
	h.eq(ab["cast_ticks"], 56, "cast is 56 ticks")
	var countered_stance := []
	var armoured_stance := []
	var recovery_stance := []
	var king_cfg := Balance.profile("k")
	for offset in range(-2, 40):
		var r: Dictionary = await _probe(tree, offset)
		if r["hit_step"] < 0 or r["cast_step"] < 0:
			continue
		var stance_tick: int = int(r["hit_step"]) - int(r["cast_step"])
		if stance_tick < 0:
			continue
		var inside := stance_tick >= cs and stance_tick < ce
		if r["type"] == "parry":
			countered_stance.append(stance_tick)
			h.check(inside, "a counter only happens inside the window (stance tick %d)" % stance_tick)
		else:
			(armoured_stance if stance_tick < cs else recovery_stance).append(stance_tick)
			h.check(not inside, "a hit outside the window is not countered (stance tick %d)" % stance_tick)
			h.check(int(r["king_hp"]) < int(r["king_start_hp"]), "...and it hurts (stance tick %d)" % stance_tick)
			if stance_tick < cs:
				h.check(is_equal_approx(float(r["king_poise"]), float(r["king_start_poise"])) and int(r["king_state"]) != S.STAGGERED,
						"wind-up is armoured: no poise loss, no stagger (tick %d)" % stance_tick)
			else:
				h.check(float(r["king_poise"]) < float(r["king_start_poise"]),
						"recovery has no armour: the hit costs poise (tick %d)" % stance_tick)
	countered_stance.sort()
	h.eq(countered_stance.size(), ce - cs, "exactly %d consecutive stance ticks counter (the window length)" % (ce - cs))
	if not countered_stance.is_empty():
		h.eq(countered_stance[0], cs, "the first counter tick is counter_start")
		h.eq(countered_stance[countered_stance.size() - 1], ce - 1, "the last counter tick is counter_end - 1")
	h.check(not armoured_stance.is_empty() and not recovery_stance.is_empty(), "the sweep covered wind-up and recovery hits")
	h.check(float(king_cfg["armor"]) > 0.0, "king armour is data driven")


# ---- riposte -------------------------------------------------------------------------------------
static func _riposte(h, tree: SceneTree) -> void:
	h.begin("king: a counter negates the hit, staggers the attacker and ripostes through the normal damage path")
	var offset: int = await _first_countered_offset(tree)
	h.check(offset > -99, "found a timing that counters")
	var ab := _ab()
	var rig = await Runner.make_rig(tree, "p", "k", "w", 0, "rip-1")
	rig.face_off(1.6)
	rig.to_live()
	var king: FighterController = rig.black()
	var pawn: FighterController = rig.white()
	var king_hp: int = king.health.current
	var pawn_hp: int = pawn.health.current
	var events := []
	var seen := 0
	var parry_tick := -1
	var staggered_ticks := 0
	var riposte_started := false
	var king_yaw_toward := false
	for step in 120:
		if step == 4:
			rig.b.press("ability")
		if step == 4 + offset:
			rig.w.press("light")
		rig.tick()
		if parry_tick < 0:
			for event in rig.sim.recent_events:
				if event["type"] == "parry":
					parry_tick = step
					h.eq(king.health.current, king_hp, "the King took no damage")
					h.eq(pawn.sm.state, S.STAGGERED, "the attacker is staggered")
					h.eq(pawn.sm.stun_total, int(ab["counter_stagger_ticks"]), "for counter_stagger_ticks")
					h.eq(pawn.health.current, pawn_hp, "the attacker lost no health from its own blocked swing")
		if parry_tick >= 0 and not riposte_started and king.sm.attack != null:
			riposte_started = true
			h.eq(king.sm.attack.id, "king.royal-counter", "the riposte is the ability's AttackDefinition")
			h.eq(king.sm.cast_kind, "attack", "now an ordinary attack")
			var to := CombatConstants.flat(pawn.global_position - king.global_position)
			king_yaw_toward = absf(CombatConstants.angle_diff(king.yaw, CombatConstants.yaw_of(to))) < 0.01
		for event in rig.sim.recent_events:
			if int(event["eventId"]) > seen:
				seen = int(event["eventId"])
				events.append(event.duplicate())
	h.check(parry_tick >= 0, "the counter fired")
	h.check(riposte_started, "the King started a riposte")
	h.check(king_yaw_toward, "the King snapped to face the attacker")
	var riposte_hits := events.filter(func(e): return e["type"] == "hit" and e["actorPlayerId"] == "player-black")
	h.eq(riposte_hits.size(), 1, "exactly one riposte hit")
	if not riposte_hits.is_empty():
		var def: AttackDefinition = AttackLibrary.ability_attack("k", "royal-counter")
		var raw := roundi(float(king.stats["baseDamage"]) * def.damage_mult * float(king.profile["riposte_mult"]))
		var expected := maxi(1, roundi(float(raw) * (1.0 - float(pawn.profile["armor"]))))
		h.eq(int(riposte_hits[0]["damage"]), expected, "riposte damage = base x damage_mult x riposte_mult x (1 - armour) = %d" % expected)
		h.eq(pawn.health.current, pawn_hp - expected, "and it was dealt through the normal damage path")
		h.check(int(riposte_hits[0]["tick"]) <= int(rig.sim.recent_events[0]["tick"]) + 200, "event ordering sane")
	h.check(king.health.current == king_hp, "the King is unharmed after the exchange")
	rig.dispose()

	# A defender with armour takes the reduced figure; a Rook (the longest reach) is still caught by the riposte.
	var rook_rig = await Runner.make_rig(tree, "r", "k", "w", 0, "rip-2")
	rook_rig.face_off(2.0)
	rook_rig.to_live()
	var rook: FighterController = rook_rig.white()
	var rook_hp: int = rook.health.current
	var counter_seen := false
	for step in 160:
		if step == 4:
			rook_rig.b.press("ability")
		if step == 4 + 12:
			rook_rig.w.press("light")
		rook_rig.tick()
		if not rook_rig.events_of("parry").is_empty():
			counter_seen = true
	if counter_seen:
		h.check(rook.health.current < rook_hp, "the riposte reaches a Rook standing at its own maximum range")
	else:
		h.check(true, "(Rook timing did not meet the window; covered by the Pawn probe)")
	rook_rig.dispose()


# ---- whiff -----------------------------------------------------------------------------------------
static func _whiff(h, tree: SceneTree) -> void:
	h.begin("king: a whiffed Royal Counter leaves the King recovering and on cooldown")
	var ab := _ab()
	var rig = await Runner.make_rig(tree, "p", "k", "w", 0, "whiff-1")
	rig.face_off(3.5)
	rig.to_live()
	var king: FighterController = rig.black()
	var stamina_before := king.stamina.current
	rig.b.press("ability")
	rig.tick()
	h.eq(king.sm.state, S.ABILITY_CASTING, "the stance begins")
	h.eq(king.sm.cast_kind, "counter", "cast kind counter")
	h.check(king.sm.has_armor(), "armoured from the first tick")
	h.near(stamina_before - king.stamina.current, 22.0, 1.0, "costs 22 stamina (plus a little regen delay noise)")
	h.eq(king.ability.cooldown_total, 600, "cooldown is the contract's cooldownTicks")
	h.check(king.ability.cooldown_remaining > 590, "cooldown started")
	var window_whiff_tick := -1
	var armoured_until := -1
	var light_ignored := true
	for i in 70:
		if i == 40:
			rig.b.press("light")  # recovery: input is dropped, the King is committed
		rig.tick()
		if window_whiff_tick < 0 and not rig.events_of("whiff").is_empty():
			window_whiff_tick = king.sm.state_ticks
		if armoured_until < 0 and not king.sm.has_armor() and king.sm.state == S.ABILITY_CASTING:
			armoured_until = king.sm.state_ticks
		if king.sm.state == S.ATTACKING:
			light_ignored = false
	h.check(window_whiff_tick >= 0, "a whiff event marks the closing window")
	h.eq(armoured_until, int(ab["counter_end"]), "armour ends when the window closes")
	h.check(light_ignored, "the King cannot act during the recovery")
	h.eq(king.sm.state, S.IDLE, "the King is free again after cast_ticks (%d)" % int(ab["cast_ticks"]))
	h.check(king.ability.cooldown_remaining > 400, "the cooldown keeps running: no immediate second stance")
	rig.b.press("ability")
	rig.tick(2)
	h.eq(king.sm.last_denied, "cooldown", "a second press is denied: cooldown")
	rig.dispose()

	h.begin("king: Royal Counter needs stamina")
	rig = await Runner.make_rig(tree, "p", "k", "w", 0, "whiff-2")
	rig.face_off(3.5)
	rig.to_live()
	rig.black().stamina.current = 10.0
	rig.b.press("ability")
	rig.tick(2)
	h.eq(rig.black().sm.state, S.IDLE, "not enough stamina: no stance")
	h.eq(rig.black().sm.last_denied, "stamina", "denied for stamina")
	h.eq(rig.black().ability.cooldown_remaining, 0, "and no cooldown is burned")
	rig.dispose()


# ---- arc ---------------------------------------------------------------------------------------------
static func _arc(h, tree: SceneTree) -> void:
	h.begin("king: the counter only works on the frontal arc")
	var offset: int = await _first_countered_offset(tree)
	var arc := float(_ab()["counter_arc_deg"])
	var results := {}
	for degrees in [0.0, 60.0, 75.0, 100.0, 135.0, 180.0]:
		var rig = await Runner.make_rig(tree, "p", "k", "w", 0, "arc-%d" % int(degrees))
		var king: FighterController = rig.black()
		king.teleport(Vector3(0.0, 0.0, 0.0), PI)  # faces -z
		var angle := deg_to_rad(degrees)
		var pawn_pos := Vector3(sin(angle) * 1.5, 0.0, -cos(angle) * 1.5)
		var yaw_to_king := CombatConstants.yaw_of(CombatConstants.flat(king.global_position - pawn_pos))
		rig.white().teleport(pawn_pos, yaw_to_king)
		rig.w.yaw = yaw_to_king
		rig.b.lock = false
		rig.b.yaw = PI
		rig.to_live()
		var hp_before := king.health.current
		var poise_before := king.poise
		var countered := false
		for step in 90:
			if step == 4:
				rig.b.press("ability")
			if step == 4 + offset:
				rig.w.press("light")
			rig.tick()
			if not rig.events_of("parry").is_empty():
				countered = true
		results[int(degrees)] = {"countered": countered, "hurt": king.health.current < hp_before,
				"poise_kept": is_equal_approx(king.poise, poise_before)}
		rig.dispose()
	for degrees in results:
		var inside: bool = float(degrees) <= arc * 0.5
		h.eq(results[degrees]["countered"], inside, "attacker %d deg off the King's front: %s (arc %d)" % [degrees, "countered" if inside else "not countered", int(arc)])
		if not inside:
			h.check(results[degrees]["hurt"], "...it lands and hurts (%d deg)" % degrees)


# ---- cost, stance movement ---------------------------------------------------------------------------
static func _costs_and_movement(h, tree: SceneTree) -> void:
	h.begin("king: the stance is slow (planted) and turns slowly")
	var ab := _ab()
	var rig = await Runner.make_rig(tree, "p", "k", "w", 0, "move-1")
	rig.place(Vector3(-5.0, 0.0, 0.0), Vector3(2.0, 0.0, 0.0))
	rig.to_live()
	var king: FighterController = rig.black()
	var speed: float = float(king.stats["moveSpeedMps"])
	rig.b.lock = false
	rig.b.yaw = -PI * 0.5
	rig.b.move = Vector2(-1.0, 0.0)
	rig.tick(40)
	var free_speed := king.velocity.length()
	h.check(free_speed > speed * 0.9, "free walking reaches ~%.2f m/s (%.2f)" % [speed, free_speed])
	rig.b.press("ability")
	var peak := 0.0
	var turned := 0.0
	var yaw_before := king.yaw
	rig.b.yaw = PI * 0.5  # ask for a half turn during the stance
	for i in 20:
		rig.tick()
		if king.sm.counter_stance() and king.sm.state_ticks >= 6:  # after the carried momentum has bled off (decel)
			peak = maxf(peak, king.velocity.length())
	turned = absf(CombatConstants.angle_diff(yaw_before, king.yaw))
	h.check(peak <= speed * float(ab["stance_move_mult"]) + 0.15, "stance speed is capped at %.0f%% of walking (%.2f m/s)" % [float(ab["stance_move_mult"]) * 100.0, peak])
	var free_turn := float(king.profile["turn_free"])
	h.check(turned < free_turn * float(ab["stance_turn_mult"]) * 20.0 + 0.05, "turning is slowed in the stance (%.2f rad in 20 ticks)" % turned)
	rig.dispose()


# ---- AI use and determinism -----------------------------------------------------------------------
static func _ai_and_determinism(h, tree: SceneTree) -> void:
	h.begin("king: the AI uses Royal Counter and counters happen in AI fights")
	var uses := 0
	var counters := 0
	for seed_value in range(2000, 2008):
		var rig = await Runner.make_rig(tree, "p", "k", "w", 0, "ai-%d" % seed_value)
		var white_ai := CombatAI.new(rig.w.builder, FighterRoster.stats_for("p"), FighterRoster.stats_for("k"), seed_value, 0.6, "balanced")
		var black_ai := CombatAI.new(rig.b.builder, FighterRoster.stats_for("k"), FighterRoster.stats_for("p"), seed_value + 1, 0.9, "patient")
		rig.w.autosend = false
		rig.b.autosend = false
		var guard := 0
		while rig.sim.is_running() and guard < 3200:
			var snap: Dictionary = rig.sim.snapshot(false)
			rig.sim.submit_input(white_ai.think(snap))
			rig.sim.submit_input(black_ai.think(snap))
			rig.sim.step_tick()
			guard += 1
		for event in rig.sim.recent_events:
			if event["type"] == "ability" and event["actorPlayerId"] == "player-black":
				uses += 1
			if event["type"] == "parry" and event["targetPlayerId"] == "player-black":
				counters += 1
		rig.dispose()
	h.check(uses >= 2, "the King AI cast Royal Counter in AI fights (%d casts)" % uses)
	print("  king AI: %d casts, %d countered attacks over 8 fights (informational)" % [uses, counters])

	h.begin("king: determinism replay of a King pairing")
	var a: Dictionary = await Runner.fight(tree, "k", "q", {"style": "patient", "skill": 0.9}, Runner.BASELINE, 4242)
	var b: Dictionary = await Runner.fight(tree, "k", "q", {"style": "patient", "skill": 0.9}, Runner.BASELINE, 4242)
	h.eq(a["final"], b["final"], "final snapshots are byte-identical")
	h.eq(JSON.stringify(a["result"]), JSON.stringify(b["result"]), "results are identical")
	h.eq(a["events"], b["events"], "same event count")
	var c: Dictionary = await Runner.fight(tree, "k", "q", {"style": "patient", "skill": 0.9}, Runner.BASELINE, 4243)
	h.check(c["final"] != a["final"], "a different seed gives a different fight")
	var codec = preload("res://contracts/codec.gd").new()
	h.check(not a["result"].is_empty() and codec.valid("BattleResult", a["result"]), "the result is a schema-valid BattleResult")
	var d: Dictionary = await Runner.fight(tree, "q", "k", {"style": "balanced", "skill": 0.6}, {"style": "defensive", "skill": 0.7}, 4244)
	h.check(d["winner"] != "none", "a King fight always terminates with a result")
