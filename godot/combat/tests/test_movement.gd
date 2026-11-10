extends RefCounted
## Movement: walk / strafe / sprint speeds from FighterStats, lock-on facing, turn rate,
## real engine collision with walls, pillars and the other fighter, directional dodge.

const Support := preload("res://combat/tests/test_support.gd")
const S := CombatConstants.State


static func run(h, tree: SceneTree) -> void:
	await _walk_and_sprint(h, tree)
	await _facing(h, tree)
	await _collision(h, tree)
	await _dodge(h, tree)
	await _attack_motion(h, tree)


static func _walk_and_sprint(h, tree: SceneTree) -> void:
	h.begin("movement: walking speed comes from FighterStats.moveSpeedMps")
	var rig = await Support.make_rig(tree, "p", "n")
	rig.place(Vector3(-2.0, 0.0, -2.6), Vector3(0.0, 0.0, 2.6))
	rig.to_live()
	rig.w.lock = false
	rig.w.yaw = 0.0
	rig.w.move = Vector2(1.0, 0.0)
	rig.tick(20)
	var x0: float = rig.white().global_position.x
	rig.tick(30)
	h.near((rig.white().global_position.x - x0) / 0.5, 3.66, 0.03, "pawn strafes at 3.66 m/s")
	rig.b.lock = false
	rig.b.yaw = PI
	rig.b.move = Vector2(-1.0, 0.0)
	rig.place(Vector3(-2.0, 0.0, -2.6), Vector3(2.0, 0.0, 2.6))
	rig.tick(20)
	var bx0: float = rig.black().global_position.x
	rig.tick(30)
	h.near((bx0 - rig.black().global_position.x) / 0.5, 3.08, 0.03, "knight walks at 3.08 m/s (slower than the pawn)")
	rig.dispose()

	h.begin("movement: sprint is faster, costs stamina, needs stamina and a move direction")
	rig = await Support.make_rig(tree, "p", "n")
	# Run along z=0: the pillars sit at |z|=3.4 and would deflect a route at z=-2.6.
	rig.place(Vector3(-5.5, 0.0, 0.0), Vector3(0.0, 0.0, 5.0))
	rig.to_live()
	rig.w.lock = false
	rig.w.yaw = 0.0
	rig.w.move = Vector2(1.0, 0.0)
	rig.w.sprint = true
	rig.tick(15)
	var sx0: float = rig.white().global_position.x
	var stamina0: float = rig.white().stamina.current
	rig.tick(30)
	h.near((rig.white().global_position.x - sx0) / 0.5, 3.66 * 1.6, 0.06, "pawn sprints at 1.6x")
	h.near(stamina0 - rig.white().stamina.current, 30.0 * 0.2, 0.05, "sprint drains 0.2 stamina per tick")
	rig.dispose()

	rig = await Support.make_rig(tree, "p", "n")
	rig.place(Vector3(-5.5, 0.0, 0.0), Vector3(0.0, 0.0, 5.0))
	rig.to_live()
	rig.w.lock = false
	rig.w.move = Vector2(1.0, 0.0)
	rig.w.sprint = true
	rig.white().stamina.lose(117.0)  # leaves 3 and starts the regeneration delay, like a real spend
	rig.tick(3)
	var lx0: float = rig.white().global_position.x
	rig.tick(25)
	h.near((rig.white().global_position.x - lx0) / (25.0 / 60.0), 3.66, 0.06, "with almost no stamina the pawn can only walk")
	rig.w.move = Vector2.ZERO
	rig.white().stamina.current = 100.0
	rig.white().stamina.exhausted = false
	rig.tick(5)
	var idle_stamina: float = rig.white().stamina.current
	rig.tick(30)
	h.check(rig.white().stamina.current >= idle_stamina, "sprint held without moving costs nothing")
	rig.dispose()


static func _facing(h, tree: SceneTree) -> void:
	h.begin("facing: lock-on tracks the opponent while strafing")
	var rig = await Support.make_rig(tree, "p", "n")
	rig.place(Vector3(-2.0, 0.0, -2.0), Vector3(0.0, 0.0, 2.0))
	rig.to_live()
	rig.w.lock = true
	rig.w.move = Vector2(1.0, 0.0)  # strafe sideways in world space
	var worst: float = 0.0
	for i in 50:
		rig.tick()
		if i > 8:
			var to_black: Vector3 = rig.black().global_position - rig.white().global_position
			var error: float = absf(CombatConstants.angle_diff(rig.white().yaw, CombatConstants.yaw_of(to_black)))
			worst = maxf(worst, error)
	h.check(worst < 0.15, "facing stays on the opponent while circling (worst error %.3f rad)" % worst)
	h.check(rig.white().global_position.x > -0.5, "and the fighter actually moved sideways")
	rig.dispose()

	h.begin("facing: free look turns at a bounded rate")
	rig = await Support.make_rig(tree, "p", "n")
	rig.to_live()
	rig.w.lock = false
	rig.w.yaw = PI
	rig.tick(5)
	h.near(rig.white().yaw, 1.5, 0.02, "5 ticks turn 1.5 rad (0.30 rad/tick)")
	rig.tick(7)
	h.near(absf(rig.white().yaw), PI, 0.01, "a 180 degree turn takes about 11 ticks")
	rig.dispose()


static func _collision(h, tree: SceneTree) -> void:
	h.begin("collision: wall, pillar and opponent stop fighters via engine collision")
	var rig = await Support.make_rig(tree, "p", "n")
	rig.place(Vector3(0.0, 0.0, -2.6), Vector3(0.0, 0.0, 2.6))
	rig.to_live()
	rig.w.lock = false
	rig.w.yaw = PI * 0.5
	rig.w.move = Vector2(1.0, 0.0)
	var max_radius: float = 0.0
	for _i in 300:
		rig.tick()
		var p: Vector3 = rig.white().global_position
		max_radius = maxf(max_radius, Vector2(p.x, p.z).length())
	h.near(max_radius, 7.1 - 0.38, 0.06, "the pawn stops against the wall (inner face 7.1 minus its 0.38 radius)")
	h.check(max_radius < CombatConstants.ARENA_WALK_RADIUS, "the analytic backstop never had to fire")
	rig.dispose()

	rig = await Support.make_rig(tree, "p", "n")
	rig.place(Vector3(3.4, 0.0, 1.0), Vector3(-5.0, 0.0, 0.0))
	rig.to_live()
	rig.w.lock = false
	rig.w.yaw = 0.0
	rig.w.move = Vector2(0.0, 1.0)  # straight at the pillar on (3.4, 3.4)
	var nearest: float = 99.0
	for _i in 150:
		rig.tick()
		var q: Vector3 = rig.white().global_position
		nearest = minf(nearest, Vector2(q.x - 3.4, q.z - 3.4).length())
	h.near(nearest, 0.55 + 0.38, 0.05, "the pawn stops at the pillar's surface (0.55 + 0.38)")
	rig.dispose()

	rig = await Support.make_rig(tree, "p", "p")
	rig.place(Vector3(0.0, 0.0, -2.0), Vector3(0.0, 0.0, 2.0))
	rig.to_live()
	rig.w.lock = false
	rig.w.yaw = 0.0
	rig.w.move = Vector2(0.0, 1.0)
	rig.b.lock = false
	rig.b.yaw = PI
	var closest: float = 99.0
	for _i in 200:
		rig.tick()
		closest = minf(closest, rig.white().global_position.distance_to(rig.black().global_position))
	h.near(closest, 0.76, 0.05, "two pawns cannot overlap (0.38 + 0.38)")
	rig.dispose()


static func _dodge(h, tree: SceneTree) -> void:
	h.begin("dodge: directional, covers the profile distance, costs stamina, has i-frames then a cooldown")
	var rig = await Support.make_rig(tree, "p", "n")
	rig.place(Vector3(-1.0, 0.0, -1.0), Vector3(2.0, 0.0, 4.0))
	rig.to_live()
	rig.w.lock = false
	rig.w.yaw = 0.0
	rig.w.move = Vector2(1.0, 0.0)
	rig.w.press("dodge")
	var start: Vector3 = rig.white().global_position
	rig.tick()
	h.eq(rig.white().sm.state, S.DODGING, "the press starts a dodge")
	h.near(rig.white().stamina.current, 120.0 - 18.0, 0.01, "pawn dodge costs 18 stamina")
	var iframe_ticks: Array = []
	for _i in 22:
		if rig.white().sm.iframes_active():
			iframe_ticks.append(rig.white().sm.state_ticks)
		rig.tick()
	h.eq(iframe_ticks.size(), 11, "11 invulnerable ticks")
	h.eq(iframe_ticks[0], 3, "invulnerability starts on dodge tick 3")
	h.eq(iframe_ticks[iframe_ticks.size() - 1], 13, "and ends after dodge tick 13")
	var moved: Vector3 = rig.white().global_position - start
	h.near(moved.x, 3.8, 0.1, "dodged 3.8 m in the commanded direction (+X)")
	h.near(moved.z, 0.0, 0.05, "with no sideways drift")
	rig.dispose()

	rig = await Support.make_rig(tree, "p", "n")
	rig.place(Vector3(0.0, 0.0, -1.0), Vector3(4.0, 0.0, 4.0))
	rig.to_live()
	rig.w.lock = false
	rig.w.yaw = 0.0
	rig.w.press("dodge")
	rig.tick(30)
	h.near(rig.white().global_position.z, -1.0 - 3.8, 0.1, "with no direction held the dodge goes backwards")
	rig.dispose()

	h.begin("dodge: cooldown and stamina gating")
	rig = await Support.make_rig(tree, "p", "n")
	rig.place(Vector3(0.0, 0.0, -1.0), Vector3(4.0, 0.0, 4.0))
	rig.to_live()
	rig.w.lock = false
	rig.w.yaw = 0.0
	rig.w.move = Vector2(1.0, 0.0)
	rig.w.press("dodge")
	rig.tick()
	rig.tick(4)
	rig.w.press("dodge")  # buffered for 9 ticks, but the dodge lasts 22 + 8 cooldown
	rig.tick(40)
	h.near(rig.white().stamina.current, 120.0 - 18.0, 8.0, "an early second press is dropped, one dodge only")
	rig.dispose()

	rig = await Support.make_rig(tree, "p", "n")
	rig.place(Vector3(0.0, 0.0, -1.0), Vector3(4.0, 0.0, 4.0))
	rig.to_live()
	rig.w.lock = false
	rig.w.yaw = 0.0
	rig.w.move = Vector2(1.0, 0.0)
	rig.w.press("dodge")
	rig.tick()
	rig.tick(24)  # 25 ticks in: dodge is over (22) but cooldown (8) still running until tick 30
	rig.w.press("dodge")
	rig.tick()
	var again: int = rig.until(func(): return rig.white().sm.state == S.DODGING, 15)
	h.check(again >= 0, "a press made during the cooldown is remembered and fires when it ends")
	rig.dispose()

	rig = await Support.make_rig(tree, "p", "n")
	rig.to_live()
	rig.white().stamina.current = 10.0
	rig.w.press("dodge")
	rig.tick(5)
	h.check(rig.white().sm.state != S.DODGING, "not enough stamina: no dodge")
	h.check(rig.white().stamina.current >= 10.0 and rig.white().stamina.current < 18.0, "and no stamina was taken (it only regenerated)")
	h.eq(rig.white().sm.last_denied, "stamina", "the denial reason is recorded for the HUD")
	rig.dispose()


static func _attack_motion(h, tree: SceneTree) -> void:
	h.begin("attack motion: a light thrust steps forward the authored distance")
	var rig = await Support.make_rig(tree, "p", "n")
	rig.place(Vector3(0.0, 0.0, -3.0), Vector3(5.0, 0.0, 4.0))
	rig.to_live()
	rig.w.lock = false
	rig.w.yaw = 0.0
	var z0: float = rig.white().global_position.z
	rig.w.press("light")
	rig.tick(30)
	h.near(rig.white().global_position.z - z0, 0.35, 0.06, "light 1 advances ~0.35 m")
	rig.dispose()
