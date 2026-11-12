extends RefCounted
## Defence: blocking, guard break, perfect parry windows (pawn 11 ticks vs knight 13), riposte,
## dodge invulnerability, stagger / poise / immunity and armour frames.
##
## Timing convention in these tests: relative step 0 is the tick on which White's light attack
## is processed (its state_ticks = 0). Its first active tick, and so the hit, is step 7.

const Support := preload("res://combat/tests/test_support.gd")
const S := CombatConstants.State


## Runs a scripted exchange: White swings at step 0; Black acts at the listed relative steps.
## Returns the absolute server tick of step 0.
static func _exchange(rig, black_script: Dictionary, steps_after: int = 45) -> int:
	var first := 0
	for key in black_script:
		first = mini(first, int(key))
	var start_tick := -1
	for r in range(first, steps_after):
		if r == 0:
			rig.w.press("light")
		if black_script.has(r):
			match String(black_script[r]):
				"parry":
					rig.b.press("parry")
				"dodge":
					rig.b.press("dodge")
				"block":
					rig.b.block = true
				"light":
					rig.b.press("light")
				"ability":
					rig.b.press("ability")
		rig.tick()
		if r == 0:
			start_tick = rig.sim.server_tick
	return start_tick


static func _fresh(tree: SceneTree, white_role: String, black_role: String):
	var rig = await Support.make_rig(tree, white_role, black_role)
	rig.face_off()
	rig.to_live()
	return rig


static func run(h, tree: SceneTree) -> void:
	await _block(h, tree)
	await _guard_break(h, tree)
	await _parry_windows(h, tree)
	await _parry_effects(h, tree)
	await _dodge(h, tree)
	await _stagger(h, tree)
	await _armour(h, tree)


static func _block(h, tree: SceneTree) -> void:
	h.begin("block: absorbs a frontal hit for stamina; pawn guard is weaker than the knight's")
	var rig = await _fresh(tree, "p", "p")
	rig.b.block = true
	_exchange(rig, {})
	h.eq(rig.events_of("block").size(), 1, "a block event is emitted")
	h.eq(rig.events_of("hit").size(), 0, "no damage event")
	h.eq(rig.black().health.current, 80, "no HP lost")
	h.near(rig.black().stamina.current, 120.0 - 12.0 * 1.35, 0.01, "pawn pays 12 x 1.35 = 16.2 stamina")
	h.eq(rig.black().sm.state, S.BLOCKING, "still guarding")
	rig.dispose()

	rig = await _fresh(tree, "p", "n")
	rig.b.block = true
	_exchange(rig, {})
	h.near(rig.black().stamina.current, 110.0 - 12.0 * 0.8, 0.01, "knight pays only 12 x 0.8 = 9.6 stamina")
	rig.dispose()

	h.begin("block: a guard needs a few ticks to come up")
	rig = await _fresh(tree, "p", "p")
	_exchange(rig, {4: "block"})
	h.eq(rig.events_of("block").size(), 1, "guard raised 3 ticks before impact holds")
	rig.dispose()
	rig = await _fresh(tree, "p", "p")
	_exchange(rig, {5: "block"})
	h.eq(rig.events_of("block").size(), 0, "guard raised only 2 ticks before impact is too late")
	h.eq(rig.black().health.current, 68, "...and the hit lands")
	rig.dispose()

	h.begin("block: only covers the front arc")
	rig = await _fresh(tree, "p", "p")
	rig.b.lock = false
	rig.b.yaw = 0.0  # Black faces +Z, away from White who is at -Z
	rig.b.block = true
	_exchange(rig, {})
	h.eq(rig.events_of("block").size(), 0, "a hit from behind is not blocked")
	h.eq(rig.black().health.current, 68, "full damage from behind")
	rig.dispose()


static func _guard_break(h, tree: SceneTree) -> void:
	h.begin("guard break: out of stamina the guard collapses - chip damage, stagger, exhaustion")
	var rig = await _fresh(tree, "p", "p")
	rig.black().stamina.lose(115.0)  # 5 left
	rig.b.block = true
	_exchange(rig, {})
	h.eq(rig.events_of("guardbreak").size(), 1, "a guardbreak event is emitted")
	h.eq(int(rig.events_of("guardbreak")[0]["damage"]), 6, "chip damage is half of the hit (6)")
	h.eq(rig.black().health.current, 74, "HP 80 - 6")
	h.eq(rig.black().sm.stun_kind, "guardbreak", "stagger kind")
	h.eq(rig.black().sm.stun_total, 50, "pawn guard-break stun is 50 ticks")
	h.near(rig.black().stamina.current, 0.0, 0.5, "stamina emptied")
	h.check(rig.black().stamina.exhausted, "and the fighter is exhausted")
	rig.dispose()

	h.begin("guard break: heavy attacks cost a blocker more (x1.8)")
	rig = await _fresh(tree, "p", "p")
	rig.b.block = true
	rig.tick(6)
	rig.w.press("heavy")
	rig.tick()
	rig.until(func(): return rig.events_of("block").size() + rig.events_of("guardbreak").size() > 0, 80)
	h.near(rig.black().stamina.current, 120.0 - 24.0 * 1.8 * 1.35, 0.5, "heavy blocked costs 24 x 1.8 x 1.35 = 58.3")
	rig.dispose()


## Runs the swing with one Black parry press at `offset` and reports what happened.
static func _parry_case(tree: SceneTree, black_role: String, offset: int) -> Dictionary:
	var rig = await _fresh(tree, "p", black_role)
	_exchange(rig, {offset: "parry"})
	var out := {
		"parried": rig.events_of("parry").size() == 1,
		"hit": rig.events_of("hit").size() == 1,
		"white_hp": rig.white().health.current,
		"black_hp": rig.black().health.current,
		"stun_kind": rig.white().sm.stun_kind,
		"stun_total": rig.white().sm.stun_total,
	}
	rig.dispose()
	return out


static func _parry_windows(h, tree: SceneTree) -> void:
	h.begin("parry (pawn, 11-tick window): exact boundaries around the hit on step 7")
	var early_edge: Dictionary = await _parry_case(tree, "p", -3)
	h.check(early_edge["parried"] and not early_edge["hit"], "pressed 10 ticks before impact: still parries (window tick 10)")
	var too_early: Dictionary = await _parry_case(tree, "p", -4)
	h.check(not too_early["parried"] and too_early["hit"], "pressed 11 ticks before impact: window already closed, hit lands")
	var late_edge: Dictionary = await _parry_case(tree, "p", 7)
	h.check(late_edge["parried"] and not late_edge["hit"], "pressed on the impact tick: parries (think precedes resolution)")
	var too_late: Dictionary = await _parry_case(tree, "p", 8)
	h.check(not too_late["parried"] and too_late["hit"], "pressed one tick after impact: too late")

	h.begin("parry (knight, 13-tick window) is more forgiving than the pawn's")
	var k_early: Dictionary = await _parry_case(tree, "n", -5)
	h.check(k_early["parried"], "knight still parries 12 ticks early (pawn could not)")
	var k_too_early: Dictionary = await _parry_case(tree, "n", -6)
	h.check(not k_too_early["parried"] and k_too_early["hit"], "but not 13 ticks early")


static func _parry_effects(h, tree: SceneTree) -> void:
	h.begin("parry: negates damage, staggers the attacker, refunds stamina, opens a riposte")
	var rig = await _fresh(tree, "p", "p")
	rig.b.press("parry")
	rig.tick(1)
	rig.w.press("light")
	rig.tick()
	rig.until(func(): return rig.events_of("parry").size() > 0, 40)
	h.eq(rig.black().health.current, 80, "no damage taken")
	h.eq(rig.white().sm.state, S.STAGGERED, "the attacker is staggered")
	h.eq(rig.white().sm.stun_kind, "parried", "stagger kind is parried")
	h.eq(rig.white().sm.stun_total, 34, "pawn parry stagger lasts 34 ticks")
	h.near(rig.black().stamina.current, 120.0 - 10.0 + 8.0, 0.01, "10 spent, 8 refunded")
	h.check(rig.black().sm.riposte_ticks > 0, "a riposte window is open")
	var event: Dictionary = rig.events_of("parry")[0]
	h.eq(event["damage"], 0, "parry event carries no damage")
	h.eq(event["actorPlayerId"], "player-white", "actor is the initiator whose attack was parried")
	h.eq(event["targetPlayerId"], "player-black", "target is the parrier")
	rig.dispose()

	h.begin("riposte: pawn x1.25, knight x1.6 on the counter-attack")
	rig = await _fresh(tree, "p", "p")
	rig.b.press("parry")
	rig.tick()
	rig.w.press("light")
	rig.tick()
	rig.until(func(): return rig.events_of("parry").size() > 0, 40)
	rig.b.press("light")  # riposte immediately
	rig.tick()
	rig.until(func(): return rig.events_of("hit").size() > 0, 40)
	h.eq(int(rig.events_of("hit")[0]["damage"]), 15, "pawn riposte: 12 x 1.25 = 15")
	h.eq(rig.white().health.current, 65, "White 80 - 15")
	rig.dispose()

	rig = await _fresh(tree, "p", "n")
	rig.b.press("parry")
	rig.tick()
	rig.w.press("light")
	rig.tick()
	rig.until(func(): return rig.events_of("parry").size() > 0, 40)
	h.eq(rig.white().sm.stun_total, 60, "knight parry staggers for 60 ticks (strong parry)")
	rig.b.press("light")
	rig.tick()
	rig.until(func(): return rig.events_of("hit").size() > 0, 40)
	h.eq(int(rig.events_of("hit")[0]["damage"]), 35, "knight riposte: 22 x 1.6 = 35")
	h.eq(rig.white().health.current, 45, "White pawn 80 - 35")
	rig.dispose()

	h.begin("parry: only frontal, committed, and cannot be spammed")
	rig = await _fresh(tree, "p", "p")
	rig.b.lock = false
	rig.b.yaw = 0.0  # facing away from White
	_exchange(rig, {-1: "parry"})
	h.eq(rig.events_of("parry").size(), 0, "no parry against an attacker behind you")
	h.eq(rig.black().health.current, 68, "the hit lands")
	rig.dispose()

	rig = await _fresh(tree, "p", "p")
	rig.place(Vector3(-4.0, 0.0, 0.0), Vector3(4.0, 0.0, 0.0))
	rig.b.press("parry")
	rig.tick()
	var after_first: float = rig.black().stamina.current
	rig.tick(11)
	rig.b.press("parry")  # during recovery / cooldown
	rig.tick(30)
	# 42 ticks passed: regeneration resumed after its 36-tick delay (+2.7). A second spend (-10)
	# would leave the pool near 102.7, so "never below the post-spend level" proves it was refused.
	h.check(rig.black().stamina.current >= after_first, "the second press was refused: nothing more was spent")
	h.eq(rig.black().sm.last_denied, "", "a cooldown refusal is not recorded as a stamina denial")
	rig.dispose()

	h.begin("parry: a whiffed parry leaves you committed and open")
	rig = await _fresh(tree, "p", "p")
	rig.b.press("parry")
	rig.tick()
	rig.tick(13)  # window (11) is over, recovery still running
	h.eq(rig.black().sm.state, S.PARRYING, "still locked in parry recovery")
	h.check(not rig.black().sm.parry_window_open(), "but the window is closed")
	rig.dispose()


static func _dodge(h, tree: SceneTree) -> void:
	h.begin("dodge: invulnerable on dodge ticks 3..13 only (event 'dodge', no damage)")
	var cases := [
		[4, true, "dodge pressed 3 ticks before impact: tick 3 of the dodge is invulnerable"],
		[5, false, "dodge pressed 2 ticks before impact: tick 2 is still vulnerable"],
		[-6, true, "dodge 13 ticks old at impact: still invulnerable"],
		[-7, false, "dodge 14 ticks old at impact: invulnerability is over"],
	]
	for case in cases:
		var rig = await _fresh(tree, "p", "p")
		rig.b.lock = false
		rig.b.yaw = PI
		rig.b.move = Vector2(0.0, -1.0)  # toward White: stays inside her reach, so only i-frames decide
		_exchange(rig, {case[0]: "dodge"})
		var dodged: bool = rig.events_of("dodge").size() == 1 and rig.black().health.current == 80
		h.eq(dodged, case[1], String(case[2]))
		rig.dispose()


static func _stagger(h, tree: SceneTree) -> void:
	h.begin("stagger: a single light poke flinches; knight armour reduces damage")
	var rig = await _fresh(tree, "p", "n")
	_exchange(rig, {})
	var hit: Dictionary = rig.events_of("hit")[0]
	h.eq(hit["damage"], 11, "12 x (1 - 0.12 armour) = 10.56 -> 11 against the knight")
	h.eq(rig.black().sm.state, S.IDLE, "the knight (poise 70) is not staggered by a poke")
	rig.dispose()

	h.begin("stagger: forced stagger blocks every action and clears buffered presses")
	rig = await _fresh(tree, "p", "p")
	rig.black().sm.enter_staggered(20, "hit")
	rig.b.press("light")
	rig.b.press("dodge")
	var acted := false
	for _i in 19:
		rig.tick()
		if rig.black().sm.state == S.ATTACKING or rig.black().sm.state == S.DODGING:
			acted = true
	h.check(not acted, "no attack or dodge during the stagger")
	rig.tick(6)
	h.eq(rig.black().sm.state, S.IDLE, "recovers to Idle afterwards")
	h.near(rig.black().stamina.current, 120.0, 0.001, "and does not fire the presses made while staggered")
	rig.dispose()

	h.begin("stagger: brief immunity afterwards prevents stun-locks")
	rig = await _fresh(tree, "p", "p")
	rig.black().sm.enter_staggered(10, "hit")
	rig.tick(12)
	h.eq(rig.black().sm.state, S.IDLE, "stagger over")
	h.check(rig.black().sm.stagger_immunity > 20, "immunity timer running")
	rig.black().poise = 1.0
	rig.w.press("light")
	rig.tick()
	rig.until(func(): return rig.events_of("hit").size() > 0, 30)
	h.eq(rig.black().sm.state, S.IDLE, "a hit that WOULD break poise only damages while immune")
	h.eq(rig.black().health.current, 68, "damage still applies")
	rig.tick(60)  # immunity ends, combo chain resets
	rig.black().poise = 1.0
	rig.w.press("light")
	rig.tick()
	rig.until(func(): return rig.events_of("hit").size() > 1, 30)
	h.eq(rig.black().sm.state, S.STAGGERED, "after the immunity the same hit staggers")
	rig.dispose()


static func _armour(h, tree: SceneTree) -> void:
	h.begin("armour: a knight heavy shrugs off a stagger during its armour frames, not before")
	var rig = await _fresh(tree, "p", "n")
	rig.b.press("heavy")
	rig.tick()  # knight heavy begins (its state_ticks 0)
	rig.black().poise = 1.0
	rig.tick(17)  # knight state_ticks 18
	rig.w.press("light")  # pawn light lands 7 ticks later: knight state_ticks 25, inside armour [19,42)
	rig.tick()
	rig.until(func(): return rig.events_of("hit").size() > 0 and rig.events_of("hit")[0]["targetPlayerId"] == "player-black", 30)
	h.eq(rig.black().health.current, 125 - 11, "the hit still does damage")
	h.eq(rig.black().sm.state, S.ATTACKING, "but the knight is not interrupted")
	rig.dispose()

	rig = await _fresh(tree, "p", "n")
	rig.b.press("heavy")
	rig.tick()
	rig.black().poise = 1.0
	rig.w.press("light")  # lands at knight state_ticks 8: before the armour frames
	rig.tick()
	rig.until(func(): return rig.events_of("hit").size() > 0, 30)
	h.eq(rig.black().sm.state, S.STAGGERED, "the same hit in the unarmoured windup interrupts the heavy")
	h.eq(rig.black().sm.attack, null, "the interrupted heavy is cancelled")
	rig.dispose()
