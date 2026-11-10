extends RefCounted
## Input handling: cumulative counters become single edges, replays never retrigger,
## held controls neutralise after 15 stale ticks, the countdown swallows actions, and the
## short input buffer lets a follow-up fire at the cancel point (but not arbitrarily early).

const Support := preload("res://combat/tests/test_support.gd")
const S := CombatConstants.State


static func run(h, tree: SceneTree) -> void:
	await _edges(h, tree)
	await _neutralise(h, tree)
	await _countdown(h, tree)
	await _buffer(h, tree)
	await _vector(h, tree)


static func _edges(h, tree: SceneTree) -> void:
	h.begin("input: a counter jump of 3 is ONE swing; resent counters never retrigger")
	var rig = await Support.make_rig(tree, "p", "p")
	rig.face_off()
	rig.to_live()
	rig.w.press("light")
	rig.w.press("light")
	rig.w.press("light")
	rig.tick()
	h.eq(rig.white().sm.state, S.ATTACKING, "the press starts an attack")
	h.eq(rig.white().sm.combo_index, 0, "it is the first chain link")
	h.near(rig.white().stamina.current, 110.0, 0.001, "exactly one swing's stamina (10) was spent")
	rig.tick(80)
	h.eq(rig.events_of("hit").size(), 1, "exactly one hit landed, not three")
	h.check(rig.white().sm.state != S.ATTACKING, "the attack finished by itself")
	h.check(rig.white().stamina.current >= 119.0, "no phantom second attack drained stamina")
	h.eq(rig.submit_errors.size(), 0, "every packet was accepted")
	rig.dispose()


static func _neutralise(h, tree: SceneTree) -> void:
	h.begin("input: held controls neutralise 15 ticks after the last accepted packet")
	var rig = await Support.make_rig(tree, "p", "p")
	rig.place(Vector3(-4.0, 0.0, 0.0), Vector3(4.0, 0.0, 0.0))
	rig.to_live()
	rig.w.lock = false
	rig.w.yaw = 0.0
	rig.w.move = Vector2(0.0, 1.0)
	rig.tick(12)
	var z0: float = rig.white().global_position.z
	rig.w.autosend = false
	rig.tick(15)
	var z_fresh: float = rig.white().global_position.z
	h.check(z_fresh - z0 > 0.5, "the last move input keeps applying for the 15-tick grace period")
	rig.tick(2)  # now beyond the grace period -> neutral
	var z_settled: float = rig.white().global_position.z
	rig.tick(30)
	h.near(rig.white().global_position.z, z_settled, 0.001, "movement has stopped once inputs went stale")
	h.eq(rig.white().sm.state, S.IDLE, "a stale fighter is Idle, not stuck walking")

	h.begin("input: a stale stream cannot replay an old press after resuming")
	rig.dispose()
	rig = await Support.make_rig(tree, "p", "p")
	rig.face_off()
	rig.to_live()
	rig.w.press("light")
	rig.tick()
	rig.w.autosend = false
	rig.tick(60)
	var stamina_before: float = rig.white().stamina.current
	rig.w.autosend = true  # resumes with the SAME counters
	rig.tick(40)
	h.check(rig.white().sm.state != S.ATTACKING, "resuming does not re-trigger the old attack")
	h.check(rig.white().stamina.current >= stamina_before, "no stamina was spent after resuming")
	h.eq(rig.events_of("hit").size(), 1, "still only the original hit")
	rig.dispose()


static func _countdown(h, tree: SceneTree) -> void:
	h.begin("input: the countdown ignores movement and swallows presses")
	var rig = await Support.make_rig(tree, "p", "p")
	rig.w.move = Vector2(0.0, 1.0)
	rig.w.lock = false
	rig.w.press("light")
	rig.w.press("heavy")
	rig.w.press("dodge")
	rig.tick(100)
	h.eq(rig.sim.phase, CombatSimulation.Phase.COUNTDOWN, "still counting down")
	h.near(rig.white().global_position.z, -2.6, 0.0001, "nobody moves during the countdown")
	h.eq(rig.white().sm.state, S.IDLE, "nobody acts during the countdown")
	h.near(rig.white().stamina.current, 120.0, 0.0001, "no stamina spent during the countdown")
	rig.to_live()
	rig.tick(3)
	h.check(rig.white().sm.state != S.ATTACKING and rig.white().sm.state != S.DODGING, "presses made during the countdown do not fire when it ends")
	h.check(rig.white().global_position.z > -2.6, "movement works once the fight is live")
	rig.dispose()


static func _buffer(h, tree: SceneTree) -> void:
	h.begin("input buffer: a press just before the cancel point chains; an early one expires")
	var rig = await Support.make_rig(tree, "p", "p")
	rig.face_off()
	rig.to_live()
	rig.w.press("light")
	rig.tick()  # attack tick 0 processed; state_ticks now 1
	rig.tick(9)  # state_ticks now 10; cancel point is tick 17
	rig.w.press("light")
	rig.tick()
	# The press tick thought at attack tick 10; ticks thinking at 11..17 inclusive are 7 ticks,
	# and the one thinking at 17 (the cancel point) starts link 2.
	var waited: int = rig.until(func(): return rig.white().sm.combo_index == 1, 30)
	h.eq(waited, 7, "the buffered press fires exactly at the cancel point (tick 17)")
	h.near(rig.white().stamina.current, 120.0 - 10.0 - 11.0, 0.01, "second link costs 11 stamina")
	rig.dispose()

	rig = await Support.make_rig(tree, "p", "p")
	rig.face_off()
	rig.to_live()
	rig.w.press("light")
	rig.tick()
	rig.tick(2)  # state_ticks 3, far before the cancel point (14 ticks away, buffer is 9)
	rig.w.press("light")
	rig.tick(40)
	h.check(rig.white().sm.combo_index != 1 or rig.white().sm.state != S.ATTACKING, "a press 14 ticks early is NOT remembered")
	h.near(rig.white().stamina.current, 110.0, 5.0, "only the first swing was paid for")
	rig.dispose()

	h.begin("combo: a late press within the grace window continues the chain, later restarts it")
	rig = await Support.make_rig(tree, "p", "p")
	rig.face_off()
	rig.to_live()
	rig.w.press("light")
	rig.tick(25)  # attack (24 ticks) has ended; grace window (14) is open
	h.eq(rig.white().sm.combo_index, 0, "chain position is remembered after the swing ends")
	rig.w.press("light")
	rig.tick()
	h.eq(rig.white().sm.combo_index, 1, "pressing inside the grace window continues with link 2")
	rig.dispose()

	rig = await Support.make_rig(tree, "p", "p")
	rig.face_off()
	rig.to_live()
	rig.w.press("light")
	rig.tick(24 + 15)  # swing ended and the 14-tick grace window passed
	h.eq(rig.white().sm.combo_index, -1, "the chain resets after the grace window")
	rig.w.press("light")
	rig.tick()
	h.eq(rig.white().sm.combo_index, 0, "the next press starts a fresh chain")
	rig.dispose()


static func _vector(h, tree: SceneTree) -> void:
	h.begin("input: diagonal movement is clamped to unit length")
	var rig = await Support.make_rig(tree, "p", "p")
	rig.place(Vector3(-2.0, 0.0, -2.0), Vector3(0.0, 0.0, 5.5))
	rig.to_live()
	rig.w.lock = false
	rig.w.yaw = 0.0
	rig.w.move = Vector2(1.0, 1.0)  # not normalised by the client
	rig.tick(15)
	var a: Vector3 = rig.white().global_position
	rig.tick(30)
	var b: Vector3 = rig.white().global_position
	var speed: float = (b - a).length() / 0.5
	h.near(speed, 3.66, 0.05, "diagonal speed equals the stat (3.66 m/s), not 1.41x")
	h.eq(rig.sim.submit_input(rig.w.packet().merged({"moveX": 1.5}, true))["code"], "INVALID_PAYLOAD", "an out-of-range axis is refused outright")
	rig.dispose()
