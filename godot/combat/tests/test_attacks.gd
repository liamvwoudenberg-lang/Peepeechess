extends RefCounted
## Attacks: animation-driven timing, hitbox/hurtbox detection, three-hit combo, heavy attacks,
## damage and stamina costs.

const Support := preload("res://combat/tests/test_support.gd")
const S := CombatConstants.State


static func run(h, tree: SceneTree) -> void:
	await _timing(h, tree)
	await _geometry(h, tree)
	await _combo(h, tree)
	await _heavy(h, tree)
	await _costs(h, tree)


static func _timing(h, tree: SceneTree) -> void:
	h.begin("timing: damage lands on the first active tick, exactly once per swing")
	var rig = await Support.make_rig(tree, "p", "p")
	rig.face_off()
	rig.to_live()
	rig.w.press("light")
	rig.tick()
	var started: int = rig.sim.server_tick
	h.eq(rig.white().sm.state, S.ATTACKING, "the press starts an attack")
	var landed: int = rig.until(func(): return rig.events_of("hit").size() > 0, 40)
	h.check(landed >= 0, "the swing connects")
	var hit: Dictionary = rig.events_of("hit")[0]
	h.eq(int(hit["tick"]) - started, 7, "pawn light 1: first active tick is 7 ticks after the attack began")
	h.eq(hit["damage"], 12, "pawn deals its base damage 12 with light 1")
	h.eq(hit["actorPlayerId"], "player-white", "the attacker is the actor")
	h.eq(hit["targetPlayerId"], "player-black", "the other seat is the target")
	h.eq(rig.black().health.current, 68, "80 - 12")
	rig.tick(40)
	h.eq(rig.events_of("hit").size(), 1, "the 5-tick active window produced one hit, not five")
	h.eq(rig.white().sm.state, S.IDLE, "the swing ended after exactly its 24 ticks")
	h.eq(rig.black().sm.state, S.IDLE, "a light poke only flinches (poise 30 - 9 = 21)")
	h.near(rig.black().poise, 21.0, 0.6, "poise absorbed the hit")
	rig.dispose()

	h.begin("timing: a swing that connects with nothing is a whiff")
	rig = await Support.make_rig(tree, "p", "p")
	rig.place(Vector3(0.0, 0.0, -2.0), Vector3(0.0, 0.0, 2.0))
	rig.to_live()
	rig.w.press("light")
	rig.tick()
	started = rig.sim.server_tick
	rig.tick(40)
	h.eq(rig.events_of("hit").size(), 0, "out of reach: no hit")
	h.eq(rig.black().health.current, 80, "no damage")
	var whiffs: Array = rig.events_of("whiff")
	h.eq(whiffs.size(), 1, "one whiff event")
	h.eq(int(whiffs[0]["tick"]) - started, 24, "reported when the swing ends (24 ticks)")
	rig.dispose()


static func _geometry(h, tree: SceneTree) -> void:
	h.begin("hitbox: facing, arc and reach decide who is hit")
	var rig = await Support.make_rig(tree, "p", "p")
	rig.place(Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, -1.8))
	rig.to_live()
	rig.w.lock = false
	rig.w.yaw = 0.0
	rig.w.press("light")
	rig.tick(40)
	h.eq(rig.events_of("hit").size(), 0, "a target behind the attacker is never hit")
	rig.dispose()

	for case in [[15.0, true, "15 deg off-axis is inside a 36 deg thrust"], [40.0, false, "40 deg off-axis misses a 36 deg thrust"], [90.0, false, "a target at the side is missed"]]:
		rig = await Support.make_rig(tree, "p", "p")
		var angle: float = deg_to_rad(case[0])
		rig.place(Vector3(0.0, 0.0, 0.0), Vector3(sin(angle) * 1.8, 0.0, cos(angle) * 1.8))
		rig.to_live()
		rig.w.lock = false
		rig.w.yaw = 0.0
		rig.w.press("light")
		rig.tick(40)
		h.eq(rig.events_of("hit").size() > 0, case[1], case[2])
		rig.dispose()

	h.begin("hitbox: reach grows with FighterStats.reachM")
	rig = await Support.make_rig(tree, "p", "n")
	# 2.35 m apart. Spear: 1.95 + 0.38 reach, minus ~0.18 m of step-in before its active frames, reaches.
	# Sword: 1.65 + 0.38 reach, only ~0.19 m of step-in, does not.
	rig.place(Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, 2.35))
	rig.to_live()
	rig.w.lock = false
	rig.w.yaw = 0.0
	rig.b.lock = false
	rig.b.yaw = PI
	rig.w.press("light")
	rig.tick(40)
	h.check(rig.events_of("hit").size() > 0, "the pawn's spear connects at 2.35 m")
	rig.dispose()
	rig = await Support.make_rig(tree, "p", "n")
	rig.white().teleport(Vector3(0.0, 0.0, 2.35), PI)
	rig.black().teleport(Vector3(0.0, 0.0, 0.0), 0.0)
	rig.to_live()
	rig.b.lock = false
	rig.b.yaw = 0.0
	rig.w.lock = false
	rig.w.yaw = PI
	rig.b.press("light")
	rig.tick(60)
	h.eq(rig.events_of("hit").size(), 0, "the knight's sword cannot reach 2.35 m")
	rig.dispose()


static func _chain_press(rig) -> void:
	var sm: CombatStateMachine = rig.white().sm
	var cancel: int = sm.attack.cancel_tick(sm.attack_total)
	rig.until(func(): return sm.state_ticks >= cancel - 2, 80)
	rig.w.press("light")
	rig.tick()


## Presses light just before the cancel point and waits for link `index` to begin.
static func _link(rig, index: int) -> void:
	_chain_press(rig)
	rig.until(func(): return rig.white().sm.combo_index == index and rig.white().sm.state == S.ATTACKING and rig.white().sm.state_ticks <= 2, 30)


static func _combo(h, tree: SceneTree) -> void:
	h.begin("combo: light x3 chains with rising damage, cost and a poise-breaking finisher")
	var rig = await Support.make_rig(tree, "p", "p")
	rig.face_off()
	rig.to_live()
	rig.w.press("light")
	rig.tick()
	h.eq(rig.white().sm.combo_index, 0, "link 1")
	_link(rig, 1)
	h.eq(rig.white().sm.combo_index, 1, "link 2")
	_link(rig, 2)
	h.eq(rig.white().sm.combo_index, 2, "link 3 (finisher)")
	h.near(rig.white().stamina.current, 120.0 - 10.0 - 11.0 - 16.0, 0.01, "costs rise per link: 10 + 11 + 16")
	rig.until(func(): return rig.black().sm.state == S.STAGGERED, 40)
	var hits: Array = rig.events_of("hit")
	h.eq(hits.size(), 3, "all three links landed")
	h.eq(int(hits[0]["damage"]), 12, "link 1 damage 12")
	h.eq(int(hits[1]["damage"]), 13, "link 2 damage 13 (x1.1)")
	h.eq(int(hits[2]["damage"]), 17, "finisher damage 17 (x1.45)")
	h.eq(rig.black().health.current, 80 - 12 - 13 - 17, "total 42 damage")
	h.eq(rig.black().sm.state, S.STAGGERED, "the finisher breaks the pawn's poise")
	h.eq(rig.black().sm.stun_total, 22, "finisher hitstun is 22 ticks")
	h.eq(rig.black().sm.stun_kind, "hit", "stagger caused by a hit")
	rig.dispose()

	h.begin("combo: after the finisher a new light press starts a fresh chain")
	rig = await Support.make_rig(tree, "p", "p")
	rig.face_off()
	rig.to_live()
	rig.w.press("light")
	rig.tick()
	_link(rig, 1)
	_link(rig, 2)
	_link(rig, 0)  # a press at the finisher's cancel point starts a NEW chain
	h.eq(rig.white().sm.combo_index, 0, "the chain wrapped back to link 1 (no endless chain)")
	h.eq(rig.white().sm.attack.id, "pawn.light.1", "...and it is really the first attack again")
	rig.dispose()

	h.begin("combo: a light can be cancelled into a heavy at the cancel point")
	rig = await Support.make_rig(tree, "p", "p")
	rig.face_off()
	rig.to_live()
	rig.w.press("light")
	rig.tick()
	var sm: CombatStateMachine = rig.white().sm
	rig.until(func(): return sm.state_ticks >= sm.attack.cancel_tick(sm.attack_total) - 2, 40)
	rig.w.press("heavy")
	rig.tick(4)
	h.eq(sm.attack.kind, AttackDefinition.Kind.HEAVY, "light -> heavy branch")
	h.eq(sm.combo_index, -1, "a heavy ends the light chain")
	rig.dispose()


static func _heavy(h, tree: SceneTree) -> void:
	h.begin("heavy: slow, expensive, hits harder, breaks poise")
	var rig = await Support.make_rig(tree, "p", "p")
	rig.face_off()
	rig.to_live()
	rig.w.press("heavy")
	rig.tick()
	var started: int = rig.sim.server_tick
	h.eq(rig.white().sm.attack_total, 53, "heavy lasts FighterStats.heavyTicks (53)")
	h.near(rig.white().stamina.current, 120.0 - 26.0, 0.01, "heavy costs 26 stamina")
	rig.until(func(): return rig.events_of("hit").size() > 0, 80)
	var hit: Dictionary = rig.events_of("hit")[0]
	h.eq(int(hit["tick"]) - started, AttackLibrary.heavy("p").active_window(53).x, "heavy hits on its first active tick")
	h.eq(int(hit["tick"]) - started, 27, "...which is tick 27 for the pawn")
	h.eq(hit["damage"], 24, "heavy deals 2.0x base damage")
	h.eq(rig.black().sm.state, S.STAGGERED, "poise 30 - 32 breaks: the heavy staggers")
	h.eq(rig.black().sm.stun_total, 30, "heavy hitstun is 30 ticks")
	rig.dispose()


static func _costs(h, tree: SceneTree) -> void:
	h.begin("stamina: an attack you cannot afford does not happen and costs nothing")
	var rig = await Support.make_rig(tree, "p", "p")
	rig.face_off()
	rig.to_live()
	rig.white().stamina.lose(115.0)
	rig.w.press("light")
	rig.tick(3)
	h.check(rig.white().sm.state != S.ATTACKING, "5 stamina cannot pay for a 10-stamina swing")
	h.near(rig.white().stamina.current, 5.0, 0.001, "nothing was spent")
	h.eq(rig.white().sm.last_denied, "stamina", "the reason is recorded for the HUD")
	rig.dispose()

	h.begin("stamina: exhaustion locks out attacks until partly recovered")
	rig = await Support.make_rig(tree, "p", "p")
	rig.face_off()
	rig.to_live()
	rig.white().stamina.lose(999.0)
	h.check(rig.white().stamina.exhausted, "emptied stamina exhausts the fighter")
	rig.w.press("light")
	rig.tick(5)
	h.check(rig.white().sm.state != S.ATTACKING, "cannot attack while exhausted")
	rig.tick(150)
	h.check(not rig.white().stamina.exhausted, "recovers after the (doubled) regeneration delay")
	rig.w.press("light")
	rig.tick()
	h.eq(rig.white().sm.state, S.ATTACKING, "and can attack again")
	rig.dispose()

	h.begin("stamina: regeneration waits after spending and pauses while guarding")
	rig = await Support.make_rig(tree, "p", "p")
	rig.place(Vector3(-4.0, 0.0, 0.0), Vector3(4.0, 0.0, 0.0))
	rig.to_live()
	rig.w.press("heavy")
	rig.tick()
	var after_spend: float = rig.white().stamina.current
	rig.tick(30)
	h.near(rig.white().stamina.current, after_spend, 0.001, "no regeneration for 36 ticks after a spend")
	rig.tick(80)
	h.check(rig.white().stamina.current > after_spend + 10.0, "regeneration resumes afterwards")
	rig.white().stamina.lose(60.0)
	var guarded: float = rig.white().stamina.current
	rig.w.block = true
	rig.tick(180)  # far longer than the 36-tick delay
	h.eq(rig.white().sm.state, S.BLOCKING, "the fighter is guarding")
	h.near(rig.white().stamina.current, guarded, 0.001, "stamina does not regenerate while holding block")
	rig.w.block = false
	rig.tick(60)
	h.check(rig.white().stamina.current > guarded + 5.0, "it regenerates again once the guard is lowered")
	rig.dispose()
