extends RefCounted
## Externalised tuning (godot/combat/data/balance_v1.json via balance_data.gd): loading, validation, typed values,
## identity (tuning_id + stable hash), the non-leaking override hook, defaults that reproduce the original numbers,
## and the per-role movement profiles FighterMovement consumes.

const Balance := preload("res://combat/data/balance_data.gd")
const Runner := preload("res://combat/tests/matchup_runner.gd")
const S := CombatConstants.State

## Pin of the shipped tuning. A balance change MUST update this on purpose: the stamp is what a server and its clients
## compare, so an accidental edit of balance_v1.json fails here instead of silently desynchronising a match.
const SHIPPED_ID := "balance-v1"
const SHIPPED_STAMP := "balance-v1:894711f5b35e3d38"   # changed on purpose 2026-11-13: attacker_edge table added (BALANCE.md)


static func run(h, tree: SceneTree) -> void:
	_identity(h)
	_defaults(h)
	_types(h)
	_validation(h)
	await _override(h, tree)
	await _movement_profiles(h, tree)
	_no_leak(h)


static func _identity(h) -> void:
	h.begin("balance: id, stable hash, roles")
	h.eq(Balance.tuning_id(), SHIPPED_ID, "tuning_id")
	var hash := Balance.tuning_hash()
	h.eq(hash.length(), 64, "the hash is a SHA-256 hex digest")
	h.eq(Balance.tuning_hash(), hash, "stable between calls")
	h.eq(Balance.stamp(), "%s:%s" % [SHIPPED_ID, hash.substr(0, 16)], "stamp = id:first 16 hex")
	h.eq(Balance.stamp(), SHIPPED_STAMP, "the shipped tuning is the pinned one (update SHIPPED_STAMP when balance_v1.json changes ON PURPOSE)")
	h.eq(Balance.roles().size(), 6, "six roles")
	for role in ["p", "n", "b", "r", "q", "k"]:
		h.check(Balance.has_role(role), "role %s has tuning" % role)
	h.check(not Balance.has_role("x"), "unknown role")
	h.check(not Balance.is_overridden(), "no override is active")
	h.check(Balance.validate(Balance.snapshot()).is_empty(), "the shipped data validates")
	# The hash covers values, not formatting: re-serialising the shipped data in another key order/indent is identical.
	var data := Balance.snapshot()
	var reparsed = JSON.parse_string(JSON.stringify(data, "    ", false))
	h.check(Balance.validate(reparsed).is_empty(), "round-tripped data still validates")
	h.eq(JSON.stringify(Balance.snapshot(), "", true), JSON.stringify(Balance.snapshot(), "", true), "canonical form is deterministic")
	print("  tuning stamp: %s" % Balance.stamp())


## The refactor must reproduce the original hard-coded numbers exactly (canaries from the pre-refactor tables).
static func _defaults(h) -> void:
	h.begin("balance: defaults reproduce the original tuning")
	var n := FighterProfile.for_role("n")
	h.eq(n["poise"], 70.0, "knight poise")
	h.eq(n["armor"], 0.12, "knight armour")
	h.eq(n["parry_stagger_ticks"], 60, "knight parry stagger")
	h.eq(n["riposte_mult"], 1.6, "knight riposte")
	var p := FighterProfile.for_role("p")
	h.eq([p["poise"], p["armor"], p["dodge_distance"], p["block_cost_mult"]], [30.0, 0.0, 3.8, 1.35], "pawn poise/armour/dodge/guard")
	var r := FighterProfile.for_role("r")
	h.eq([r["poise"], r["armor"], r["block_arc_deg"], r["radius"]], [110.0, 0.25, 150.0, 0.5], "rook")
	var q := FighterProfile.for_role("q")
	h.eq([q["poise"], q["sprint_mult"], q["dodge_cost"], q["riposte_mult"]], [28.0, 1.65, 16.0, 1.35], "queen")
	var b := FighterProfile.for_role("b")
	h.eq([b["poise"], b["armor"], b["dodge_iframe_end"]], [35.0, 0.05, 14], "bishop")
	h.eq(AttackLibrary.light("p", 2).damage_mult, 1.45, "pawn finisher x1.45")
	h.eq(AttackLibrary.light("p", 2).hitstun_ticks, 22, "pawn finisher hitstun")
	h.eq(AttackLibrary.heavy("n").poise_damage, 55.0, "knight heavy poise damage")
	h.eq(AttackLibrary.ability_attack("n", "lunging-strike").forward_motion_m, 4.2, "lunge distance")
	h.eq(AttackLibrary.ability_attack("n", "lunging-strike").absolute_ticks, 72, "lunge length")
	h.eq(AttackLibrary.for_role("q")["light"].size(), 5, "queen has five light links (royal fury)")
	h.eq(AttackLibrary.light("q", 4).id, "queen.light.5", "queen link 5")
	h.eq(AttackLibrary.heavy("r").armor_end, 0.7, "rook heavy armour end")
	h.eq(AttackLibrary.for_role("p")["abilities"], {}, "pawn has no attack ability")
	var d := AbilityComponent.DEFINITIONS
	h.eq(d["last-stand"]["buff_ticks"], 300, "last stand lasts 300 ticks")
	h.eq(d["last-stand"]["hp_threshold"], 0.35, "last stand threshold")
	h.eq(d["lunging-strike"]["stamina_cost"], 28.0, "lunge cost")
	h.eq([d["blink"]["blink_distance"], d["blink"]["iframe_ticks"]], [4.0, 10], "blink")
	h.eq([d["fortress-guard"]["poise_mult"], d["fortress-guard"]["guard_unbreakable"]], [3.0, true], "fortress guard")
	h.eq([d["royal-fury"]["combo_length"], d["royal-fury"]["attack_speed_mult"]], [5, 1.35], "royal fury")
	h.check(d.has("royal-counter") and d["royal-counter"]["role"] == "k", "royal-counter belongs to the king")
	h.check(AbilityComponent.is_known("last-stand") and not AbilityComponent.is_known("royal-counter"), "is_known keeps the experimental ability out by default")
	# Contract stats are NOT tuning: they only ever come from the BattleRequest.
	for role in Balance.roles():
		var profile := Balance.profile(role)
		for key in ["maxHp", "maxStamina", "baseDamage", "moveSpeedMps", "reachM", "lightTicks", "heavyTicks", "parryTicks", "cooldownTicks"]:
			h.check(not profile.has(key), "%s profile does not carry the contract stat %s" % [role, key])
	h.eq(FighterProfile.for_role("p"), Balance.profile("p"), "FighterProfile.for_role serves the loader")
	h.eq(AttackLibrary.for_role("zz"), {}, "unknown role: empty table")
	h.eq(FighterProfile.for_role("zz"), {}, "unknown role: empty profile")


static func _types(h) -> void:
	h.begin("balance: values are re-typed (JSON numbers are all floats)")
	var p := Balance.profile("p")
	for key in Balance.PROFILE_INT_KEYS:
		h.eq(typeof(p[key]), TYPE_INT, "profile.%s is an int" % key)
	for key in Balance.PROFILE_FLOAT_KEYS:
		h.eq(typeof(p[key]), TYPE_FLOAT, "profile.%s is a float" % key)
	var ability := Balance.ability("blink")
	h.eq(typeof(ability["cast_ticks"]), TYPE_INT, "ability ticks are ints")
	h.eq(typeof(ability["blink_distance"]), TYPE_FLOAT, "ability distances are floats")
	h.eq(typeof(Balance.ability("fortress-guard")["guard_unbreakable"]), TYPE_BOOL, "booleans stay booleans")
	var light := AttackLibrary.light("n", 0)
	h.eq(typeof(light.hitstun_ticks), TYPE_INT, "attack ticks are ints")
	h.eq(light.kind, AttackDefinition.Kind.LIGHT, "kind maps to the enum")
	h.eq(AttackLibrary.heavy("n").kind, AttackDefinition.Kind.HEAVY, "heavy kind")
	h.eq(AttackLibrary.ability_attack("n", "lunging-strike").kind, AttackDefinition.Kind.ABILITY, "ability kind")
	# Getters hand out copies: mutating one cannot change the active tuning.
	var copy := Balance.profile("n")
	copy["poise"] = 1.0
	h.eq(Balance.profile("n")["poise"], 70.0, "profile() returns a copy")
	var def_copy := Balance.ability("blink")
	def_copy["cast_ticks"] = 1
	h.eq(Balance.ability("blink")["cast_ticks"], 20, "ability() returns a copy")
	var snap := Balance.snapshot()
	snap["profiles"]["n"]["poise"] = 2.0
	h.eq(Balance.profile("n")["poise"], 70.0, "snapshot() is a deep copy")


static func _validation(h) -> void:
	h.begin("balance: validation rejects bad data and installs nothing")
	var stamp_before := Balance.stamp()
	var cases := [
		["negative poise", {"profiles": {"p": {"poise": -1.0}}}],
		["armour of 1", {"profiles": {"n": {"armor": 1.0}}}],
		["unknown profile key", {"profiles": {"p": {"mana": 3.0}}}],
		["string where a number belongs", {"profiles": {"p": {"radius": "wide"}}}],
		["dodge i-frames outside the dodge", {"profiles": {"p": {"dodge_iframe_end": 99}}}],
		["zero acceleration", {"profiles": {"r": {"accel": 0.0}}}],
		["unknown ability kind", {"abilities": {"blink": {"kind": "teleport"}}}],
		["counter window past the cast", {"abilities": {"royal-counter": {"counter_end": 99}}}],
		["attack timeline out of order", {"attacks": {"p": {"heavy": {"startup_end": 0.9, "active_end": 0.2}}}}],
		["unknown attack field", {"attacks": {"p": {"heavy": {"mystery": 1.0}}}}],
		["unknown attack kind", {"attacks": {"p": {"heavy": {"kind": "SPECIAL"}}}}],
		["schema version", {"schema": 2}],
		["empty tuning id", {"tuning_id": ""}],
	]
	for case in cases:
		var errors: Array = Balance.apply_override(case[1])
		h.check(not errors.is_empty(), "rejected: %s" % case[0])
		h.check(not Balance.is_overridden() and Balance.stamp() == stamp_before, "...and nothing was installed (%s)" % case[0])
	# A profile without its attack table, and an attack ability without its table entry, are refused too.
	var broken := Balance.snapshot()
	broken["attacks"].erase("b")
	h.check(not Balance.validate(broken).is_empty(), "a role without attacks is invalid")
	broken = Balance.snapshot()
	broken["attacks"]["k"]["abilities"].erase("royal-counter")
	h.check(not Balance.validate(broken).is_empty(), "an attack ability needs its AttackDefinition")


static func _override(h, tree: SceneTree) -> void:
	h.begin("balance: override hook (apply, effect on new fights, clear)")
	var base_stamp := Balance.stamp()
	var base_hash := Balance.tuning_hash()
	var rev := Balance.revision()
	var errors: Array = Balance.apply_override({"profiles": {"p": {"poise": 99, "dodge_ticks": 25.0}},
			"attacks": {"p": {"heavy": {"damage_mult": 3.0, "hitstun_ticks": 31}}}})
	h.eq(errors, [], "a valid patch installs")
	h.check(Balance.is_overridden(), "override is active")
	h.check(Balance.tuning_id().ends_with("+override"), "the id says so: %s" % Balance.tuning_id())
	h.check(Balance.stamp() != base_stamp and Balance.tuning_hash() != base_hash, "stamp and hash change")
	h.check(Balance.revision() > rev, "revision advanced")
	h.eq(FighterProfile.for_role("p")["poise"], 99.0, "profile reflects it (typed as float)")
	h.eq(typeof(FighterProfile.for_role("p")["poise"]), TYPE_FLOAT, "ints in a patch are re-typed")
	h.eq(typeof(FighterProfile.for_role("p")["dodge_ticks"]), TYPE_INT, "floats for tick keys are re-typed to int")
	h.eq(AttackLibrary.heavy("p").damage_mult, 3.0, "attack tables are rebuilt")
	h.eq(AttackLibrary.heavy("p").hitstun_ticks, 31, "attack ints")
	h.eq(AttackLibrary.heavy("p").stamina_cost, 26.0, "untouched fields keep their shipped value")
	h.eq(AttackLibrary.light("p", 0).damage_mult, 1.0, "other attacks are untouched")
	h.eq(FighterProfile.for_role("n")["poise"], 70.0, "other roles are untouched")
	var rig = await Runner.make_rig(tree, "p", "n")
	h.eq(rig.white().profile["poise"], 99.0, "a NEW fight uses the override")
	h.eq(rig.white().poise, 99.0, "...down to the starting poise")
	rig.dispose()
	# A patch carrying its own id keeps it, and identical numbers then hash identically (hash covers values only).
	Balance.clear_override()
	h.check(not Balance.is_overridden(), "cleared")
	h.eq(Balance.stamp(), base_stamp, "the stamp is back to the shipped one")
	h.eq(Balance.tuning_hash(), base_hash, "the hash is back")
	h.eq(FighterProfile.for_role("p")["poise"], 30.0, "profile restored")
	h.eq(AttackLibrary.heavy("p").damage_mult, 2.0, "attack tables restored")
	errors = Balance.apply_override({"tuning_id": SHIPPED_ID})
	h.eq(errors, [], "a patch that changes nothing installs")
	h.eq(Balance.tuning_hash(), base_hash, "same values, same hash")
	Balance.clear_override()
	# Lights are replaced as a whole array.
	var lights: Array = Balance.snapshot()["attacks"]["p"]["light"]
	lights[0]["damage_mult"] = 1.5
	h.eq(Balance.apply_override({"attacks": {"p": {"light": lights}}}), [], "light chain replacement installs")
	h.eq(AttackLibrary.light("p", 0).damage_mult, 1.5, "new first link")
	Balance.clear_override()
	h.eq(AttackLibrary.light("p", 0).damage_mult, 1.0, "restored after clear")
	# Running fights keep what they copied at setup.
	var live = await Runner.make_rig(tree, "p", "n")
	Balance.apply_override({"profiles": {"p": {"poise": 77.0}}})
	h.eq(live.white().profile["poise"], 30.0, "a running fight is not affected by a later override")
	Balance.clear_override()
	live.dispose()


static func _movement_profiles(h, tree: SceneTree) -> void:
	h.begin("balance: Pawn and Knight movement equals the original constants")
	for role in ["p", "n"]:
		var pr := FighterProfile.for_role(role)
		h.eq([pr["accel"], pr["decel"], pr["turn_free"], pr["turn_locked"]], [FighterMovement.ACCEL, FighterMovement.DECEL,
				FighterMovement.TURN_FREE, FighterMovement.TURN_LOCKED], "%s: accel/decel/turn" % role)
		h.eq([pr["turn_attack_startup"], pr["turn_attack_startup_locked"], pr["attack_steer_startup"], pr["attack_steer_other"],
				pr["parry_steer"]], [FighterMovement.TURN_ATTACK_STARTUP, FighterMovement.TURN_ATTACK_STARTUP_LOCKED,
				FighterMovement.ATTACK_STEER_STARTUP, FighterMovement.ATTACK_STEER_OTHER, FighterMovement.PARRY_STEER],
				"%s: attack/parry steering" % role)

	h.begin("balance: other roles move differently, and the simulation applies it")
	var seen := {}
	for role in ["b", "r", "q", "k"]:
		var pr := FighterProfile.for_role(role)
		var differs := false
		for key in ["accel", "decel", "turn_free", "turn_locked", "turn_attack_startup", "attack_steer_startup", "parry_steer"]:
			if not is_equal_approx(float(pr[key]), float(FighterProfile.for_role("p")[key])):
				differs = true
		h.check(differs, "%s has its own movement profile" % role)
		seen[str(pr["accel"]) + str(pr["turn_free"])] = true
	h.eq(seen.size(), 4, "the four profiles are mutually distinct")
	h.check(float(FighterProfile.for_role("r")["accel"]) < float(FighterProfile.for_role("p")["accel"]), "the Rook accelerates slower than the Pawn")
	h.check(float(FighterProfile.for_role("r")["turn_free"]) < float(FighterProfile.for_role("q")["turn_free"]), "the Rook turns slower than the Queen")

	# Behaviour: after ONE live tick of full forward input the planar speed is accel x dt; a half-turn is capped at turn_free.
	for role in ["p", "n", "b", "r", "q", "k"]:
		var rig = await Runner.make_rig(tree, role, "p" if role != "p" else "n")
		rig.place(Vector3(-5.0, 0.0, 0.0), Vector3(5.0, 0.0, 0.0))
		rig.to_live()
		var pr := FighterProfile.for_role(role)
		var fighter: FighterController = rig.white()
		rig.w.lock = false
		rig.w.yaw = fighter.yaw
		rig.w.move = Vector2(0.0, 0.0)
		rig.tick(3)
		var yaw_before := fighter.yaw
		rig.w.yaw = fighter.yaw + 2.0
		rig.tick()
		h.near(absf(CombatConstants.angle_diff(yaw_before, fighter.yaw)), float(pr["turn_free"]), 0.0005, "%s turns turn_free (%.2f rad) per tick" % [role, pr["turn_free"]])
		rig.w.yaw = fighter.yaw
		rig.w.move = Vector2(1.0, 0.0)
		rig.tick()
		var cap := minf(float(pr["accel"]) * CombatConstants.DT, float(fighter.stats["moveSpeedMps"]))
		h.near(fighter.velocity.length(), cap, 0.02, "%s: first-tick speed %.2f m/s = accel x dt" % [role, cap])
		rig.dispose()


static func _no_leak(h) -> void:
	h.begin("balance: no override leaks out of this suite")
	h.check(not Balance.is_overridden(), "tuning is the shipped one")
	h.eq(Balance.tuning_id(), SHIPPED_ID, "tuning id is the shipped one")
