extends RefCounted
## Abilities in the live simulation: Pawn "Last Stand" and Knight "Lunging Strike" - gating,
## cooldowns from FighterStats, stamina, effects and how the opponent can answer the lunge.

const Support := preload("res://combat/tests/test_support.gd")
const S := CombatConstants.State


static func run(h, tree: SceneTree) -> void:
	await _last_stand(h, tree)
	await _last_stand_cooldown(h, tree)
	await _lunge(h, tree)
	await _lunge_answers(h, tree)


static func _last_stand(h, tree: SceneTree) -> void:
	h.begin("Last Stand: refused above 35% HP, no cooldown consumed")
	var rig = await Support.make_rig(tree, "p", "n")
	rig.place(Vector3(-4.0, 0.0, 0.0), Vector3(4.0, 0.0, 0.0))
	rig.to_live()
	rig.w.press("ability")
	rig.tick(3)
	h.check(rig.white().sm.state != S.ABILITY_CASTING, "full HP: Last Stand is not available")
	h.eq(rig.white().sm.last_denied, "condition", "the HUD is told why")
	h.eq(rig.white().ability.cooldown_remaining, 0, "a refused cast does not start the cooldown")
	h.eq(rig.events_of("ability").size(), 0, "no ability event")
	rig.dispose()

	h.begin("Last Stand: below 35% HP it grants speed, attack speed and damage for 5 s")
	rig = await Support.make_rig(tree, "p", "n")
	rig.place(Vector3(-4.0, 0.0, 0.0), Vector3(4.0, 0.0, 0.0))
	rig.to_live()
	rig.white().health.current = 28  # 35% of 80
	rig.w.lock = false
	rig.w.yaw = 0.0
	rig.w.press("ability")
	rig.tick()
	h.eq(rig.white().sm.state, S.ABILITY_CASTING, "casting")
	h.eq(rig.events_of("ability").size(), 1, "an ability event is emitted")
	h.eq(rig.white().ability.cooldown_remaining, 899, "cooldown = FighterStats.cooldownTicks (900), one tick elapsed")
	h.check(rig.white().sm.has_armor(), "the shout cannot be interrupted by ordinary hits")
	rig.tick(12)
	h.check(rig.white().sm.state != S.ABILITY_CASTING, "the cast lasts 12 ticks")
	h.check(rig.white().ability.buff_active(), "the buff is up")

	rig.w.move = Vector2(1.0, 0.0)
	rig.tick(10)
	var x0: float = rig.white().global_position.x
	rig.tick(30)
	h.near((rig.white().global_position.x - x0) / 0.5, 3.66 * 1.3, 0.06, "movement is 30% faster (4.76 m/s)")
	rig.w.move = Vector2.ZERO
	rig.tick(30)
	rig.w.press("light")
	rig.tick()
	h.eq(rig.white().sm.attack_total, 19, "a light attack takes 19 ticks instead of 24")
	rig.place(Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.8))
	rig.tick(30)
	var hits: Array = rig.events_of("hit")
	h.check(hits.size() > 0, "the empowered swing connects")
	if hits.size() > 0:
		h.eq(int(hits[0]["damage"]), 12, "12 x 1.15 = 13.8 -> 14, then -12% knight armour -> 12")
	rig.dispose()

	h.begin("Last Stand: expires after 300 ticks and works while exhausted")
	rig = await Support.make_rig(tree, "p", "n")
	rig.place(Vector3(-4.0, 0.0, 0.0), Vector3(4.0, 0.0, 0.0))
	rig.to_live()
	rig.white().health.current = 10
	rig.white().stamina.lose(999.0)
	h.check(rig.white().stamina.exhausted, "the pawn is exhausted")
	rig.w.press("ability")
	rig.tick()
	h.eq(rig.white().sm.state, S.ABILITY_CASTING, "Last Stand costs no stamina, so exhaustion cannot stop it")
	rig.tick(298)  # the cast tick + 298 more = 299 ticks: one tick of buff remains
	h.check(rig.white().ability.buff_active(), "still active on the 300th tick")
	rig.tick()
	h.check(not rig.white().ability.buff_active(), "gone once 300 ticks have passed")
	rig.dispose()


static func _last_stand_cooldown(h, tree: SceneTree) -> void:
	h.begin("Last Stand: 900-tick cooldown is exact")
	var rig = await Support.make_rig(tree, "p", "n")
	rig.place(Vector3(-4.0, 0.0, 0.0), Vector3(4.0, 0.0, 0.0))
	rig.to_live()
	rig.white().health.current = 10
	rig.w.press("ability")
	rig.tick()  # step N: cast accepted, cooldown 900 -> 899 after the tick
	rig.tick(898)  # steps N+1 .. N+898
	rig.w.press("ability")
	rig.tick()  # step N+899: cooldown_remaining is 1 when it thinks
	h.eq(rig.events_of("ability").size(), 1, "one tick before the cooldown ends: refused")
	h.eq(rig.white().sm.last_denied, "cooldown", "reason: cooldown")
	rig.w.press("ability")
	rig.tick()  # step N+900: cooldown_remaining is 0
	h.eq(rig.events_of("ability").size(), 2, "exactly 900 ticks after the first cast: accepted")
	h.eq(rig.white().ability.cooldown_remaining, 899, "and the new cooldown starts")
	rig.dispose()


static func _lunge(h, tree: SceneTree) -> void:
	h.begin("Lunging Strike: costs stamina, telegraphs, charges 4.2 m, hits for 2.2x")
	var rig = await Support.make_rig(tree, "n", "p")
	rig.place(Vector3(0.0, 0.0, -3.0), Vector3(5.0, 0.0, 3.0))
	rig.to_live()
	rig.w.lock = false
	rig.w.yaw = 0.0
	rig.w.press("ability")
	rig.tick()
	h.eq(rig.white().sm.state, S.ABILITY_CASTING, "the knight commits to the lunge")
	h.eq(rig.white().sm.attack_total, 72, "72 ticks end to end")
	h.near(rig.white().stamina.current, 110.0 - 28.0, 0.01, "costs 28 stamina")
	h.eq(rig.white().ability.cooldown_remaining, 539, "cooldown = FighterStats.cooldownTicks (540)")
	h.check(rig.white().sm.has_armor(), "armoured during the windup and charge")
	var z0: float = rig.white().global_position.z
	rig.tick(80)
	h.near(rig.white().global_position.z - z0, 4.2, 0.1, "charged 4.2 m forward, with no leftover momentum")
	h.eq(rig.white().sm.state, S.IDLE, "recovered after 72 ticks")
	rig.dispose()

	rig = await Support.make_rig(tree, "n", "p")
	rig.place(Vector3(0.0, 0.0, -3.0), Vector3(0.0, 0.0, 1.5))
	rig.to_live()
	rig.w.lock = false
	rig.w.yaw = 0.0
	rig.b.lock = false
	rig.b.yaw = PI
	rig.w.press("ability")
	rig.tick()
	var started: int = rig.sim.server_tick
	rig.until(func(): return rig.events_of("hit").size() > 0, 90)
	var hit: Dictionary = rig.events_of("hit")[0]
	h.eq(hit["damage"], 48, "22 x 2.2 = 48.4 -> 48")
	h.eq(rig.black().health.current, 32, "80 - 48")
	var active_first: int = AttackLibrary.ability_attack("n", "lunging-strike").active_window(72).x
	h.check(int(hit["tick"]) - started >= active_first, "it cannot land before its active frames (tick %d)" % active_first)
	h.eq(rig.black().sm.state, S.STAGGERED, "poise 60 breaks the pawn's stance")
	rig.dispose()

	h.begin("Lunging Strike: gated by stamina and cooldown")
	rig = await Support.make_rig(tree, "n", "p")
	rig.place(Vector3(-4.0, 0.0, 0.0), Vector3(4.0, 0.0, 0.0))
	rig.to_live()
	rig.white().stamina.lose(95.0)  # 15 left
	rig.w.press("ability")
	rig.tick(3)
	h.check(rig.white().sm.state != S.ABILITY_CASTING, "15 stamina cannot pay for the 28-stamina lunge")
	h.eq(rig.white().sm.last_denied, "stamina", "reason: stamina")
	h.eq(rig.white().ability.cooldown_remaining, 0, "no cooldown was burned")
	rig.dispose()


## Finds the absolute tick at which an undefended lunge connects, then replays the identical
## fight with a defence timed relative to that tick (the simulation is deterministic).
static func _lunge_hit_tick(tree: SceneTree) -> int:
	var rig = await Support.make_rig(tree, "n", "p")
	rig.place(Vector3(0.0, 0.0, -3.0), Vector3(0.0, 0.0, 1.5))
	rig.to_live()
	rig.w.lock = false
	rig.w.yaw = 0.0
	rig.b.lock = false
	rig.b.yaw = PI
	rig.w.press("ability")
	rig.tick()
	rig.until(func(): return rig.events_of("hit").size() > 0, 90)
	var tick_of_hit: int = int(rig.events_of("hit")[0]["tick"])
	rig.dispose()
	return tick_of_hit


static func _lunge_rig(tree: SceneTree):
	var rig = await Support.make_rig(tree, "n", "p")
	rig.place(Vector3(0.0, 0.0, -3.0), Vector3(0.0, 0.0, 1.5))
	rig.to_live()
	rig.w.lock = false
	rig.w.yaw = 0.0
	rig.b.lock = false
	rig.b.yaw = PI
	return rig


static func _lunge_answers(h, tree: SceneTree) -> void:
	h.begin("Lunging Strike: it can be parried, dodged, and it breaks a pawn's guard")
	var impact: int = await _lunge_hit_tick(tree)

	var rig = await _lunge_rig(tree)
	rig.w.press("ability")
	rig.tick()
	while rig.sim.server_tick < impact - 5:
		rig.tick()
	rig.b.press("parry")  # window of 11 ticks covers the impact tick
	rig.until(func(): return rig.events_of("parry").size() + rig.events_of("hit").size() > 0, 40)
	h.eq(rig.events_of("parry").size(), 1, "a well-timed parry stops the lunge")
	h.eq(rig.black().health.current, 80, "no damage")
	h.eq(rig.white().sm.state, S.STAGGERED, "the knight is staggered by the parry")
	rig.dispose()

	rig = await _lunge_rig(tree)
	rig.w.press("ability")
	rig.tick()
	while rig.sim.server_tick < impact - 8:
		rig.tick()
	rig.b.move = Vector2(1.0, 0.0)
	rig.b.press("dodge")  # impact lands on dodge tick 7: inside the 3..13 invulnerable window
	rig.tick(60)
	# Dodging sideways also carries the pawn ~2 m out of the lunge's hitbox before impact, so the
	# evasion may be by position (a whiff) rather than by i-frames. Either way no damage lands.
	h.eq(rig.events_of("hit").size(), 0, "dodging the charge avoids the hit")
	h.eq(rig.black().health.current, 80, "no damage")
	h.check(rig.events_of("dodge").size() + rig.events_of("whiff").size() > 0, "the lunge was recorded as dodged or whiffed")
	rig.dispose()

	rig = await _lunge_rig(tree)
	rig.b.block = true
	rig.w.press("ability")
	rig.tick()
	rig.until(func(): return rig.events_of("block").size() + rig.events_of("guardbreak").size() + rig.events_of("hit").size() > 0, 90)
	h.eq(rig.events_of("guardbreak").size(), 1, "blocking the lunge costs 48 x 2.0 x 1.35 = 129.6 > 120: the guard breaks")
	h.eq(rig.black().sm.stun_kind, "guardbreak", "and the pawn is staggered")
	h.eq(rig.black().health.current, 80 - 24, "with half the damage as chip (24)")
	rig.dispose()
