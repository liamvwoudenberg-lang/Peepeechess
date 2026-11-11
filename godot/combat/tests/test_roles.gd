extends RefCounted
## Bishop, Rook and Queen: attack timing/damage/costs from the approved c0 stats, block/parry/dodge with
## role numbers, the three abilities (Blink, Fortress Guard, Royal Fury) measured, contract acceptance
## for every p/n/b/r/q pairing, endings, and an AI-vs-AI soak over all 25 pairings.
## Every action goes through the real CombatInput channel (see test_support.gd).

const Support := preload("res://combat/tests/test_support.gd")
const Attacks := preload("res://combat/tests/test_attacks.gd")
const Defense := preload("res://combat/tests/test_defense.gd")
const Soak := preload("res://combat/tests/test_soak.gd")
const Codec := preload("res://contracts/codec.gd")
const S := CombatConstants.State

const NEW_ROLES := ["b", "r", "q"]
const ALL_ROLES := ["p", "n", "b", "r", "q"]
# Light 1 against a Pawn target (armour 0): first active tick, total ticks, damage, stamina cost.
const L1 := {
	"b": {"first": 10, "total": 29, "dmg": 18, "cost": 12.0},
	"r": {"first": 18, "total": 42, "dmg": 25, "cost": 18.0},
	"q": {"first": 9, "total": 29, "dmg": 24, "cost": 9.0},
}
const HEAVY := {
	"b": {"first": 31, "total": 59, "dmg": 34, "cost": 28.0},
	"r": {"first": 43, "total": 74, "dmg": 55, "cost": 34.0},
	"q": {"first": 28, "total": 58, "dmg": 46, "cost": 24.0},
}
const MAX_STAMINA := {"b": 115.0, "r": 90.0, "q": 115.0}


static func run(h, tree: SceneTree) -> void:
	_support(h)
	await _contracts(h, tree)
	for role in NEW_ROLES:
		await _attacks(h, tree, role)
	await _chains(h, tree)
	for role in NEW_ROLES:
		await _defence(h, tree, role)
	await _blink(h, tree)
	await _fortress_guard(h, tree)
	await _royal_fury(h, tree)
	await _endings(h, tree)
	await _soak(h, tree)


# ---- capability, stats, contracts ----------------------------------------------------------
static func _support(h) -> void:
	h.begin("roles: supports_role (the function Codex's adapter calls) and approved stats")
	for role in ALL_ROLES:
		h.check(FighterProfile.supports_role(role), "FighterProfile supports %s" % role)
		h.check(AttackLibrary.supports_role(role), "AttackLibrary supports %s" % role)
	for role in ["k", "x", ""]:
		h.check(not FighterProfile.supports_role(role), "FighterProfile refuses '%s'" % role)
		h.check(not AttackLibrary.supports_role(role), "AttackLibrary refuses '%s'" % role)
	var c0: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://chess/battle_stats.json"))
	for role in NEW_ROLES:
		var stats := FighterRoster.stats_for(role)
		h.eq(stats["statsId"], "c0-balance-v1.%s" % role, "%s uses the approved c0 stats" % role)
		for key in ["maxHp", "maxStamina", "baseDamage", "moveSpeedMps", "reachM", "lightTicks", "heavyTicks", "parryTicks", "cooldownTicks", "abilityId"]:
			h.eq(stats[key], c0[role][key], "%s.%s matches battle_stats.json" % [role, key])
		h.eq(typeof(stats["lightTicks"]), TYPE_INT, "tick fields are ints")
	h.eq(FighterRoster.stats_for("p")["statsId"], "combat-proto-v1.p", "Pawn prototype stats are unchanged")
	h.eq(FighterRoster.ability_name("b"), "Blink", "ability names")


static func _contracts(h, tree: SceneTree) -> void:
	h.begin("roles: every p/n/b/r/q pairing, both attacker colours, is a valid BattleRequest and starts")
	var codec = Codec.new()
	var sim := CombatSimulation.new()
	tree.root.add_child(sim)
	var failures := 0
	var pairs := 0
	for white in ALL_ROLES:
		for black in ALL_ROLES:
			for attacker in ["w", "b"]:
				var request := FighterRoster.build_request(white, black, attacker, "c-%d" % pairs, pairs, 0)
				pairs += 1
				if not codec.valid("BattleRequest", request):
					failures += 1
					printerr("  invalid request ", white, " ", black, " ", attacker)
					continue
				var reply: Dictionary = sim.start(request)
				if not reply["ok"] or not codec.valid("CombatSnapshot", sim.snapshot()):
					failures += 1
					printerr("  start failed ", white, " ", black, " ", attacker, " ", reply)
				sim.stop()
	h.eq(pairs, 50, "50 requests built")
	h.eq(failures, 0, "all of them validate and start")
	var king := FighterRoster.build_request("p", "n")
	king["defender"]["role"] = "k"
	h.check(not codec.valid("BattleRequest", king), "a king is rejected by the schema itself")
	sim.queue_free()


# ---- attacks --------------------------------------------------------------------------------
static func _target(tree: SceneTree, role: String):
	var rig = await Support.make_rig(tree, role, "p")
	rig.face_off()
	rig.to_live()
	return rig


static func _attacks(h, tree: SceneTree, role: String) -> void:
	var l1: Dictionary = L1[role]
	var hv: Dictionary = HEAVY[role]
	h.begin("roles/%s: light 1 timing, damage and cost come from the c0 stats" % role)
	var rig = await _target(tree, role)
	var def := AttackLibrary.light(role, 0)
	var stats := FighterRoster.stats_for(role)
	h.eq(def.total_ticks(stats), int(l1["total"]), "light 1 lasts round(lightTicks) = %d" % l1["total"])
	h.eq(def.active_window(int(l1["total"])).x, int(l1["first"]), "first active tick %d" % l1["first"])
	rig.w.press("light")
	rig.tick()
	var started: int = rig.sim.server_tick
	h.eq(rig.white().sm.attack_total, int(l1["total"]), "simulation uses that length")
	h.near(rig.white().stamina.current, MAX_STAMINA[role] - float(l1["cost"]), 0.01, "light 1 costs %.0f stamina" % l1["cost"])
	rig.until(func(): return rig.events_of("hit").size() > 0, 80)
	var hit: Dictionary = rig.events_of("hit")[0]
	h.eq(int(hit["tick"]) - started, int(l1["first"]), "damage lands on the first active tick")
	h.eq(int(hit["damage"]), int(l1["dmg"]), "damage %d = baseDamage x 1.0 vs a Pawn" % l1["dmg"])
	rig.tick(80)
	h.eq(rig.events_of("hit").size(), 1, "one hit per swing")
	rig.dispose()

	h.begin("roles/%s: heavy timing, damage and cost" % role)
	rig = await _target(tree, role)
	rig.w.press("heavy")
	rig.tick()
	started = rig.sim.server_tick
	h.eq(rig.white().sm.attack_total, int(hv["total"]), "heavy lasts heavyTicks = %d" % hv["total"])
	h.near(rig.white().stamina.current, MAX_STAMINA[role] - float(hv["cost"]), 0.01, "heavy costs %.0f" % hv["cost"])
	rig.until(func(): return rig.events_of("hit").size() > 0, 120)
	hit = rig.events_of("hit")[0]
	h.eq(int(hit["tick"]) - started, int(hv["first"]), "heavy hits on its first active tick")
	h.eq(int(hit["damage"]), int(hv["dmg"]), "heavy damage %d" % hv["dmg"])
	h.eq(rig.black().sm.state, S.STAGGERED, "a heavy breaks a Pawn's poise")
	rig.dispose()

	h.begin("roles/%s: stamina gates attacks and exhaustion locks them out" % role)
	rig = await _target(tree, role)
	rig.white().stamina.lose(MAX_STAMINA[role] - 3.0)
	rig.w.press("light")
	rig.tick(3)
	h.check(rig.white().sm.state != S.ATTACKING, "3 stamina cannot pay for a swing")
	h.eq(rig.white().sm.last_denied, "stamina", "reason recorded")
	rig.white().stamina.lose(999.0)
	rig.w.press("heavy")
	rig.tick(5)
	h.check(rig.white().stamina.exhausted and rig.white().sm.state != S.ATTACKING, "exhausted: no heavy either")
	rig.dispose()


static func _chains(h, tree: SceneTree) -> void:
	h.begin("roles: three-link chain damage per role (Bishop 18/20/25, Rook 25/28/38, Queen 24/25/32)")
	var expected := {"b": [18, 20, 25], "r": [25, 28, 38], "q": [24, 25, 32]}
	for role in NEW_ROLES:
		var rig = await _target(tree, role)
		rig.black().poise = 1000.0  # keep the target in place; stagger is tested elsewhere
		rig.black().health.maximum = 1000
		rig.black().health.current = 1000
		rig.w.press("light")
		rig.tick()
		await Attacks._link(rig, 1)
		await Attacks._link(rig, 2)
		rig.tick(60)
		var hits: Array = rig.events_of("hit")
		h.eq(hits.size(), 3, "%s: all three links connect" % role)
		if hits.size() == 3:
			h.eq([int(hits[0]["damage"]), int(hits[1]["damage"]), int(hits[2]["damage"])], expected[role], "%s: link damage %s" % [role, expected[role]])
		rig.dispose()


# ---- defence --------------------------------------------------------------------------------
static func _defence(h, tree: SceneTree, role: String) -> void:
	var window: int = {"b": 11, "r": 10, "q": 11}[role]
	var low: int = 7 - (window - 1)  # earliest press (relative to White's swing) whose window still covers the hit on step 7
	var guard_cost := {"b": 13.2, "r": 6.6, "q": 15.6}
	var stagger := {"b": 40, "r": 38, "q": 42}
	var parry_net := {"b": -1.0, "r": -6.0, "q": -1.0}  # parry_cost - refund
	var riposte := {"b": 23, "r": 33, "q": 32}

	h.begin("roles/%s: block costs stamina x the role's guard multiplier" % role)
	var rig = await Defense._fresh(tree, "p", role)
	rig.b.block = true
	Defense._exchange(rig, {})
	h.eq(rig.events_of("block").size(), 1, "the Pawn's swing is blocked")
	h.near(rig.black().stamina.current, MAX_STAMINA[role] - float(guard_cost[role]), 0.01, "pays 12 x guard multiplier = %.1f" % guard_cost[role])
	rig.dispose()

	h.begin("roles/%s: parry window is FighterStats.parryTicks (%d): exact boundaries" % [role, window])
	for case in [[low, true], [low - 1, false], [7, true], [8, false]]:
		rig = await Defense._fresh(tree, "p", role)
		Defense._exchange(rig, {case[0]: "parry"})
		var parried: bool = rig.events_of("parry").size() == 1
		h.eq(parried, case[1], "press at step %d %s" % [case[0], "parries" if case[1] else "is too early/late"])
		if case[0] == low:
			h.eq(rig.white().sm.stun_total, stagger[role], "parry staggers the attacker for %d ticks" % stagger[role])
			h.eq(rig.white().sm.stun_kind, "parried", "stagger kind")
		rig.dispose()

	h.begin("roles/%s: parry refund and riposte multiplier" % role)
	rig = await Defense._fresh(tree, "p", role)
	rig.b.press("parry")
	rig.tick()
	rig.w.press("light")
	rig.tick()
	rig.until(func(): return rig.events_of("parry").size() > 0, 40)
	h.near(rig.black().stamina.current, MAX_STAMINA[role] + float(parry_net[role]), 0.01, "net stamina after parry")
	rig.b.press("light")
	rig.tick()
	rig.until(func(): return rig.events_of("hit").size() > 0, 60)
	h.eq(int(rig.events_of("hit")[0]["damage"]), int(riposte[role]), "riposte damage %d" % riposte[role])
	rig.dispose()

	h.begin("roles/%s: dodge cost, distance and invulnerable ticks" % role)
	var cost := {"b": 20.0, "r": 28.0, "q": 16.0}
	var dist := {"b": 3.4, "r": 2.4, "q": 3.9}
	var total := {"b": 24, "r": 30, "q": 20}
	var iframes := {"b": [3, 13], "r": [5, 13], "q": [3, 12]}
	rig = await Support.make_rig(tree, role, "p")
	rig.place(Vector3(-1.0, 0.0, -1.0), Vector3(2.0, 0.0, 4.0))
	rig.to_live()
	rig.w.lock = false
	rig.w.yaw = 0.0
	rig.w.move = Vector2(1.0, 0.0)
	rig.w.press("dodge")
	var start: Vector3 = rig.white().global_position
	rig.tick()
	h.near(rig.white().stamina.current, MAX_STAMINA[role] - float(cost[role]), 0.01, "dodge costs %.0f" % cost[role])
	var ticks: Array = []
	for _i in int(total[role]):
		if rig.white().sm.iframes_active():
			ticks.append(rig.white().sm.state_ticks)
		rig.tick()
	h.eq(ticks[0], iframes[role][0], "i-frames start on dodge tick %d" % iframes[role][0])
	h.eq(ticks[ticks.size() - 1], iframes[role][1], "i-frames end after dodge tick %d" % iframes[role][1])
	h.near((rig.white().global_position - start).x, float(dist[role]), 0.1, "dodges %.1f m" % dist[role])
	rig.dispose()


# ---- Bishop: Blink --------------------------------------------------------------------------
static func _blink(h, tree: SceneTree) -> void:
	var codec = Codec.new()
	h.begin("Blink: forward by default, 4 m, i-frames, cost, ability event, every snapshot stays schema-valid")
	var rig = await Support.make_rig(tree, "b", "p")
	rig.place(Vector3(0.0, 0.0, -5.0), Vector3(5.0, 0.0, 5.0))
	rig.to_live()
	rig.w.lock = false
	rig.w.yaw = 0.0
	rig.w.press("ability")
	rig.tick()
	h.eq(rig.white().sm.state, S.ABILITY_CASTING, "casting")
	h.eq(rig.white().sm.cast_kind, "blink", "a blink cast")
	h.near(rig.white().stamina.current, 115.0 - 20.0, 0.01, "Blink costs 20 stamina")
	h.eq(rig.white().ability.cooldown_remaining, 479, "cooldown = FighterStats.cooldownTicks (480)")
	h.eq(rig.events_of("ability").size(), 1, "an ability event")
	var z0: float = rig.white().global_position.z
	var worst_speed := 0.0
	var invalid := 0
	var iframe_ticks: Array = []
	for _i in 22:
		if rig.white().sm.iframes_active():
			iframe_ticks.append(rig.white().sm.state_ticks)
		rig.tick()
		var snap: Dictionary = rig.sim.snapshot()
		if not codec.valid("CombatSnapshot", snap):
			invalid += 1
		worst_speed = maxf(worst_speed, rig.white().velocity.length())
	h.near(rig.white().global_position.z - z0, 4.0, 0.05, "teleported 4 m straight ahead")
	h.near(rig.white().global_position.x, 0.0, 0.01, "without drifting sideways")
	# Sampled between ticks, so the activation tick itself (cast tick 0) is not in this list; the exchange
	# test below proves it is covered. Samples are the cast ticks whose resolution is still to come: 1..9.
	h.eq(iframe_ticks.size(), 9, "cast ticks 1..9 are invulnerable (tick 0 is covered by the exchange test)")
	h.eq(iframe_ticks[0], 1, "first sampled tick")
	h.eq(iframe_ticks[iframe_ticks.size() - 1], 9, "invulnerability ends after cast tick 9")
	h.eq(invalid, 0, "no snapshot during the teleport violates the schema (velocity stays small: max %.1f m/s)" % worst_speed)
	h.check(worst_speed < 10.0, "the teleport is not reported as a 240 m/s velocity")
	h.eq(rig.white().sm.state, S.IDLE, "recovered after 20 ticks")
	rig.dispose()

	h.begin("Blink: follows the held move direction")
	rig = await Support.make_rig(tree, "b", "p")
	rig.place(Vector3(-5.0, 0.0, 0.0), Vector3(5.0, 0.0, 5.0))
	rig.to_live()
	rig.w.lock = false
	rig.w.yaw = 0.0
	rig.w.move = Vector2(1.0, 0.0)
	rig.w.press("ability")
	rig.tick(15)  # the teleport happened on cast tick 3; stop before the cast ends and the walk resumes
	h.near(rig.white().global_position.x, -5.0 + 4.0, 0.15, "blinked 4 m along +X")
	rig.dispose()

	h.begin("Blink: never through or into the opponent, never through a wall")
	rig = await Support.make_rig(tree, "b", "p")
	rig.place(Vector3(0.0, 0.0, -2.6), Vector3(0.0, 0.0, 0.0))
	rig.to_live()
	rig.w.lock = false
	rig.w.yaw = 0.0
	rig.b.lock = false
	rig.b.yaw = PI
	rig.w.press("ability")
	rig.tick(25)
	var gap: float = rig.white().global_position.distance_to(rig.black().global_position)
	h.check(gap >= 0.78 and gap <= 0.9, "stopped against the opponent (gap %.2f, bodies 0.40 + 0.38)" % gap)
	h.check(rig.white().global_position.z < rig.black().global_position.z, "still on its own side of the opponent")
	rig.dispose()
	rig = await Support.make_rig(tree, "b", "p")
	rig.place(Vector3(0.0, 0.0, 5.5), Vector3(-5.0, 0.0, -5.0))
	rig.to_live()
	rig.w.lock = false
	rig.w.yaw = 0.0
	rig.w.press("ability")
	rig.tick(25)
	var radius := Vector2(rig.white().global_position.x, rig.white().global_position.z).length()
	h.check(radius <= 7.1 - 0.39 and radius >= 6.4, "stopped at the wall (radius %.2f, wall face 7.1 - 0.40)" % radius)
	rig.dispose()

	h.begin("Blink: invulnerable from the first cast tick; a cast one tick too late is hit (12 x 0.95 armour = 11)")
	for case in [[7, true, "cast on the swing's impact tick: evaded"], [5, true, "cast two ticks before impact (not yet teleported): evaded"],
			[8, false, "cast one tick too late: the hit lands"]]:
		rig = await Defense._fresh(tree, "p", "b")
		rig.b.lock = false
		rig.b.yaw = PI
		rig.b.move = Vector2(0.0, 1.0)  # blink away from White
		Defense._exchange(rig, {case[0]: "ability"})
		if case[1]:
			h.check(rig.events_of("dodge").size() == 1 and rig.black().health.current == 90, String(case[2]))
		else:
			h.check(rig.events_of("hit").size() == 1 and rig.black().health.current == 79, String(case[2]))
		rig.dispose()

	h.begin("Blink: cooldown boundary is exact, denied when staggered, gated by stamina")
	rig = await Support.make_rig(tree, "b", "p")
	rig.place(Vector3(-4.0, 0.0, 0.0), Vector3(4.0, 0.0, 0.0))
	rig.to_live()
	rig.w.press("ability")
	rig.tick()
	rig.tick(478)
	rig.w.press("ability")
	rig.tick()
	h.eq(rig.events_of("ability").size(), 1, "one tick early: refused")
	h.eq(rig.white().sm.last_denied, "cooldown", "reason cooldown")
	rig.w.press("ability")
	rig.tick()
	h.eq(rig.events_of("ability").size(), 2, "exactly 480 ticks after the first cast: accepted")
	rig.dispose()
	rig = await Support.make_rig(tree, "b", "p")
	rig.place(Vector3(-4.0, 0.0, 0.0), Vector3(4.0, 0.0, 0.0))
	rig.to_live()
	rig.white().stamina.lose(100.0)
	rig.w.press("ability")
	rig.tick(3)
	h.check(rig.white().sm.state != S.ABILITY_CASTING, "15 stamina cannot pay for Blink")
	h.eq(rig.white().sm.last_denied, "stamina", "reason stamina")
	rig.white().stamina.setup(115.0, 0.4, 36)
	rig.white().sm.enter_staggered(30, "hit")
	rig.w.press("ability")
	rig.tick(5)
	h.eq(rig.events_of("ability").size(), 0, "no Blink while staggered")
	rig.dispose()


# ---- Rook: Fortress Guard -------------------------------------------------------------------
static func _fortress_guard(h, tree: SceneTree) -> void:
	h.begin("Fortress Guard: cost, cooldown from stats, buff length, armoured cast")
	var rig = await Support.make_rig(tree, "r", "p")
	rig.place(Vector3(-4.0, 0.0, 0.0), Vector3(4.0, 0.0, 0.0))
	rig.to_live()
	rig.w.press("ability")
	rig.tick()
	h.eq(rig.white().sm.state, S.ABILITY_CASTING, "casting")
	h.near(rig.white().stamina.current, 90.0 - 10.0, 0.01, "costs 10 stamina")
	h.eq(rig.white().ability.cooldown_remaining, 719, "cooldown = FighterStats.cooldownTicks (720)")
	h.check(rig.white().sm.has_armor(), "the cast is armoured")
	rig.tick(120)
	h.check(rig.white().ability.buff_active(), "still active well inside 240 ticks")
	rig.dispose()

	rig = await Support.make_rig(tree, "r", "p")
	rig.place(Vector3(-4.0, 0.0, 0.0), Vector3(4.0, 0.0, 0.0))
	rig.to_live()
	rig.w.press("ability")
	rig.tick()
	rig.tick(238)
	h.check(rig.white().ability.buff_active(), "active on the 240th tick")
	rig.tick()
	h.check(not rig.white().ability.buff_active(), "gone after 240 ticks")
	rig.tick()  # the role tuning is restored at the start of the next tick, before any decision or hit
	h.near(float(rig.white().profile["poise"]), 110.0, 0.001, "poise pool back to normal")
	h.near(float(rig.white().profile["block_cost_mult"]), 0.55, 0.001, "guard multiplier back to normal")
	rig.dispose()

	h.begin("Fortress Guard: poise x3 and slower movement while active")
	rig = await Support.make_rig(tree, "r", "p")
	rig.place(Vector3(-4.0, 0.0, 0.0), Vector3(4.0, 0.0, 0.0))
	rig.to_live()
	rig.w.lock = false
	rig.w.yaw = 0.0
	rig.w.move = Vector2(1.0, 0.0)
	rig.tick(30)
	var x0: float = rig.white().global_position.x
	rig.tick(30)
	var normal_speed: float = (rig.white().global_position.x - x0) / 0.5
	h.near(normal_speed, 2.21, 0.04, "Rook walks at 2.21 m/s")
	rig.w.move = Vector2.ZERO
	rig.place(Vector3(-4.0, 0.0, 0.0), Vector3(4.0, 0.0, 0.0))
	rig.w.press("ability")
	rig.tick(30)
	h.near(rig.white().poise, 330.0, 0.5, "poise pool 110 x 3 = 330")
	h.near(float(rig.white().profile["poise"]), 330.0, 0.001, "and the reset value scales with it")
	rig.w.move = Vector2(1.0, 0.0)
	rig.tick(10)
	x0 = rig.white().global_position.x
	rig.tick(30)
	h.near((rig.white().global_position.x - x0) / 0.5, 2.21 * 0.7, 0.05, "buffed Rook moves at 70% speed")
	rig.dispose()

	h.begin("Fortress Guard: guard cannot be broken and costs no stamina; without it the same hit breaks the guard")
	rig = await Defense._fresh(tree, "p", "r")
	rig.black().stamina.lose(85.0)  # 5 left
	rig.b.block = true
	Defense._exchange(rig, {})
	h.eq(rig.events_of("guardbreak").size(), 1, "control: without the buff 5 stamina breaks under a 6.6 guard cost")
	rig.dispose()

	rig = await Defense._fresh(tree, "p", "r")
	rig.b.press("ability")
	rig.tick(25)  # cast (18 ticks) is over
	rig.black().stamina.lose(rig.black().stamina.current - 5.0)  # 5 left
	rig.b.block = true
	rig.tick(6)
	rig.w.press("heavy")  # heavy: 24 x 1.8 x guard multiplier would be 23.8 without the buff
	rig.tick()
	rig.until(func(): return rig.events_of("block").size() + rig.events_of("guardbreak").size() + rig.events_of("hit").size() > 0, 120)
	h.eq(rig.events_of("block").size(), 1, "the heavy is blocked")
	h.eq(rig.events_of("guardbreak").size(), 0, "no guard break")
	h.eq(rig.black().health.current, 190, "no damage")
	h.eq(rig.black().sm.state, S.BLOCKING, "still guarding")
	h.near(rig.black().stamina.current, 5.0, 0.6, "and the block cost nothing")
	h.check(not rig.black().stamina.exhausted, "never exhausted while the buff lasts")
	rig.dispose()

	h.begin("Fortress Guard: even an exhausted Rook can raise an unbreakable guard")
	rig = await Defense._fresh(tree, "p", "r")
	rig.b.press("ability")
	rig.tick(25)
	rig.black().stamina.lose(999.0)
	rig.b.block = true
	rig.tick(6)
	h.eq(rig.black().sm.state, S.BLOCKING, "guarding at 0 stamina")
	rig.w.press("light")
	rig.tick(40)
	h.eq(rig.events_of("block").size(), 1, "the swing is blocked")
	h.eq(rig.black().health.current, 190, "unharmed")
	rig.dispose()


# ---- Queen: Royal Fury ----------------------------------------------------------------------
static func _royal_fury(h, tree: SceneTree) -> void:
	h.begin("Royal Fury: cost, cooldown, 360-tick buff, regeneration multiplier")
	var rig = await Support.make_rig(tree, "q", "p")
	rig.place(Vector3(-4.0, 0.0, 0.0), Vector3(4.0, 0.0, 0.0))
	rig.to_live()
	h.near(rig.white().stamina.regen_multiplier, 1.0, 0.0001, "normal regeneration before")
	rig.w.press("ability")
	rig.tick()
	h.near(rig.white().stamina.current, 115.0 - 15.0, 0.01, "costs 15 stamina")
	h.eq(rig.white().ability.cooldown_remaining, 839, "cooldown = FighterStats.cooldownTicks (840)")
	rig.tick(20)
	h.near(rig.white().stamina.regen_multiplier, 1.5, 0.0001, "regeneration x1.5")
	rig.tick(338)
	h.check(rig.white().ability.buff_active(), "active on the 360th tick")
	rig.tick()
	h.check(not rig.white().ability.buff_active(), "gone after 360 ticks")
	rig.tick(2)
	h.near(rig.white().stamina.regen_multiplier, 1.0, 0.0001, "regeneration back to normal")
	rig.dispose()

	h.begin("Royal Fury: faster and stronger attacks")
	rig = await _target(tree, "q")
	rig.w.press("light")
	rig.tick()
	h.eq(rig.white().sm.attack_total, 29, "control: a light attack lasts 29 ticks")
	rig.dispose()
	rig = await _target(tree, "q")
	rig.w.press("ability")
	rig.tick(16)
	rig.w.press("light")
	rig.tick()
	h.eq(rig.white().sm.attack_total, 22, "with fury a light attack lasts ceil(29 / 1.35) = 22 ticks")
	rig.until(func(): return rig.events_of("hit").size() > 0, 60)
	h.eq(int(rig.events_of("hit")[0]["damage"]), 26, "24 x 1.1 = 26 damage")
	rig.dispose()

	h.begin("Royal Fury: the chain is 3 links normally and 5 links during the buff")
	rig = await _target(tree, "q")
	rig.black().poise = 1000.0
	rig.black().health.maximum = 2000
	rig.black().health.current = 2000
	rig.w.press("light")
	rig.tick()
	await Attacks._link(rig, 1)
	await Attacks._link(rig, 2)
	await Attacks._link(rig, 0)
	h.eq(rig.white().sm.attack.id, "queen.light.1", "without fury the 4th press wraps to link 1")
	rig.dispose()

	rig = await _target(tree, "q")
	rig.black().poise = 1000.0
	rig.black().health.maximum = 2000
	rig.black().health.current = 2000
	rig.w.press("ability")
	rig.tick(16)
	rig.w.press("light")
	rig.tick()
	var ids: Array = [rig.white().sm.attack.id]
	for index in [1, 2, 3, 4]:
		await Attacks._link(rig, index)
		ids.append(rig.white().sm.attack.id)
	h.eq(ids, ["queen.light.1", "queen.light.2", "queen.light.3", "queen.light.4", "queen.light.5"], "five links are reachable")
	h.near(rig.white().stamina.current, 100.0 - 9.0 - 9.0 - 13.0 - 11.0 - 16.0, 0.6, "link costs 9, 9, 13, 11, 16")
	await Attacks._link(rig, 0)
	h.eq(rig.white().sm.attack.id, "queen.light.1", "after link 5 the chain wraps")
	rig.dispose()


# ---- endings --------------------------------------------------------------------------------
static func _endings(h, tree: SceneTree) -> void:
	var codec = Codec.new()
	h.begin("roles: knockouts and timeouts with the new roles (exact cross-multiplication of HP percentages)")
	for role in NEW_ROLES:
		var rig = await _target(tree, role)
		rig.black().health.current = 5
		rig.w.press("light")
		rig.tick()
		rig.until(func(): return rig.sim.phase == CombatSimulation.Phase.FINISHED, 120)
		h.eq(rig.sim.result["outcome"], "attacker", "%s knocks out the Pawn" % role)
		h.eq(rig.sim.result["reason"], "knockout", "reason")
		h.check(codec.valid("BattleResult", rig.sim.result), "valid BattleResult")
		rig.dispose()
	var rig = await Support.make_rig(tree, "p", "r")  # Pawn attacks, Rook defends and is knocked out
	rig.face_off()
	rig.to_live()
	rig.black().health.current = 5
	rig.w.press("light")
	rig.tick()
	rig.until(func(): return rig.sim.phase == CombatSimulation.Phase.FINISHED, 120)
	h.eq(rig.sim.result["defenderHp"], 0, "a 25%-armoured Rook still dies to 5 HP + a 9-damage hit")
	rig.dispose()

	for case in [["r", "b", 95, 45, "defender", "timeout_tie", "95/190 == 45/90"], ["q", "r", 27, 38, "defender", "timeout_tie", "27/135 == 38/190"],
			["b", "r", 46, 96, "attacker", "timeout_hp", "46/90 beats 96/190"], ["r", "q", 96, 135, "defender", "timeout_hp", "96/190 loses to a full Queen"]]:
		rig = await Support.make_rig(tree, case[0], case[1], "w", 300)
		rig.place(Vector3(-4.0, 0.0, 0.0), Vector3(4.0, 0.0, 0.0))
		rig.white().health.current = case[2]
		rig.black().health.current = case[3]
		rig.to_live()
		rig.tick(CombatConstants.DURATION_TICKS)
		h.eq(rig.sim.result["outcome"], case[4], "%s vs %s: %s -> %s" % [case[0], case[1], case[6], case[4]])
		h.eq(rig.sim.result["reason"], case[5], "reason %s" % case[5])
		h.eq(rig.sim.result["resolvedTick"], 5880, "resolved at startTick + 180 + 5400")
		rig.dispose()


# The 24-sided wall's inner faces are tangent to the 7.1 m circle, so a fighter can legitimately stand in a corner
# up to 7.1 / cos(pi/24) from the centre minus their radius (the old circle bound 7.1 assumed they never reached one).
const WALL_VERTEX_RADIUS := 7.1 / 0.99144486  # cos(PI / 24)


# ---- AI soak over every pairing -------------------------------------------------------------
static func _soak(h, tree: SceneTree) -> void:
	h.begin("roles: AI-vs-AI soak over all 25 pairings (valid results, no rejected input, bounds, no overlap)")
	var outcomes := {}
	var wins := {"p": 0, "n": 0, "b": 0, "r": 0, "q": 0}
	var timeouts := 0
	var seed_value := 500
	var failures: Array = []
	for white in ALL_ROLES:
		for black in ALL_ROLES:
			seed_value += 1
			var attacker := "w" if seed_value % 2 == 0 else "b"
			var report: Dictionary = await Soak._play(tree, white, black, attacker, seed_value)
			var label := "%s(w) vs %s(b) attacker %s" % [white, black, attacker]
			var ok: bool = report["started"] and not report["result"].is_empty() and report["result_valid"] and report["rejected"] == 0 \
					and report["invalid_snapshots"] == 0 and report["out_of_bounds"] == 0 and float(report["min_gap"]) >= 0.74 \
					and float(report["max_radius"]) <= WALL_VERTEX_RADIUS - 0.37 and int(report["total_events"]) > 3
			if not ok:
				var detail := {}
				for key in ["started", "rejected", "invalid_snapshots", "out_of_bounds", "min_gap", "max_radius", "total_events", "result_valid"]:
					detail[key] = report[key]
				failures.append("%s: %s" % [label, str(detail)])
				continue
			var result: Dictionary = report["result"]
			var winner_role: String = white if (result["winnerPlayerId"] == "player-white") else black
			wins[winner_role] += 1
			if String(result["reason"]).begins_with("timeout"):
				timeouts += 1
	h.eq(failures.size(), 0, "all 25 pairings pass every invariant" + ("" if failures.is_empty() else ": " + "; ".join(failures)))
	print("  roles soak (informational, NOT a balance claim): wins by role %s, timeouts %d of 25" % [str(wins), timeouts])

	h.begin("roles: identical inputs reproduce the identical fight for Bishop vs Rook")
	var a: Dictionary = await Soak._play(tree, "b", "r", "w", 777)
	var b: Dictionary = await Soak._play(tree, "b", "r", "w", 777)
	h.eq(a["final_snapshot"], b["final_snapshot"], "final snapshots are byte-identical")
	h.eq(JSON.stringify(a["result"]), JSON.stringify(b["result"]), "results are identical")
	var c: Dictionary = await Soak._play(tree, "q", "b", "b", 778)
	var d: Dictionary = await Soak._play(tree, "q", "b", "b", 778)
	h.eq(c["final_snapshot"], d["final_snapshot"], "Queen vs Bishop is deterministic too")
