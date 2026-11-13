extends RefCounted
## The winner's walk and ladder climb in the pit world (godot/world/pit_sequence.gd) must not pass through the environment.
##  * walk_path: the walk to the ladder foot clears the arena's pillars from anywhere in the arena (a straight line crosses a
##    pillar when the duel ended in the corner behind it);
##  * the real flow, once per winning role: weapon and shield are stowed before the climb starts (unstowed they reach 0.2-0.5 m
##    sideways and up to 0.76 m front-to-back beyond the 1 m opening: through the ceiling slab, the shaft wall and the ladder),
##    the body stays inside the opening, the facing never snaps and the position never jumps.
## Measuring is shared with the climb audit tool (res://combat/tools/climb_audit.gd, climb_fit.gd).

const Main := preload("res://app/main.tscn")
const W := preload("res://world/world_constants.gd")
const Fit := preload("res://combat/tools/climb_fit.gd")
const DT := 1.0 / 60.0
## case -> [FEN, from, to, winner]: one capture and who wins it (the defender is a pawn on e5). Same positions as climb_audit.gd.
## "pd": the DEFENDER wins: the Black pawn spawns on the far side (z=+2.6) and walks in facing -Z, then must turn to face the ladder
## (the old walk snapped through 180 degrees at 80% of the way, only visible for a Black winner).
const CASES := {
	"p": ["4k3/8/8/4p3/3P4/8/8/4K3 w - - 0 1", "d4", "e5"],
	"n": ["4k3/8/8/4p3/8/5N2/8/4K3 w - - 0 1", "f3", "e5"],
	"b": ["4k3/8/8/4p3/8/2B5/8/4K3 w - - 0 1", "c3", "e5"],
	"r": ["4k3/8/8/4p3/8/8/8/4RK2 w - - 0 1", "e1", "e5"],
	"q": ["4k3/8/8/4p3/8/8/1Q6/4K3 w - - 0 1", "b2", "e5"],
	"pd": ["4k3/8/8/4p3/8/5N2/8/4K3 w - - 0 1", "f3", "e5", "defender"],
}
## Bone centres may touch the opening's edge by this much: the hands grip rungs 0.06 m from the shaft wall by design, toes reach
## the rim's edge on the last step.
const EDGE_TOLERANCE := 0.03
const MAX_TURN_PER_FRAME := 0.25    # rad; the old walk snapped up to 3.14 in one frame
const MAX_STEP_PER_FRAME := 0.12    # m; the walk peaks near 3.3 m/s (0.055 m per frame)


static func run(h, tree: SceneTree) -> void:
	_walk_path(h)
	await _flow(h, tree)


# ---- the walk to the ladder foot -------------------------------------------------------------------------------------------
static func _distance_to_pillars(p: Vector3) -> float:
	var nearest := INF
	for pillar in StoneArena.PILLAR_POSITIONS:
		nearest = minf(nearest, Vector2(p.x - pillar.x, p.z - pillar.z).length())
	return nearest


static func _walk_path(h) -> void:
	var foot := Vector3.ZERO
	var clearance := StoneArena.PILLAR_RADIUS + W.WALK_BODY_RADIUS
	h.begin("pit climb: the walk to the ladder foot never crosses a pillar")
	# The spawn points are on the z axis, between the pillars: nothing to avoid, so the walk stays a straight line.
	for z in [-2.6, 2.6]:
		var direct := PitSequence.walk_path(Vector3(0, 0, z), foot)
		h.eq(direct.size(), 2, "from the spawn point at z=%.1f the walk stays a straight line" % z)
	# Behind a pillar: the straight line goes through its centre.
	var behind := PitSequence.walk_path(Vector3(5.4, 0, 5.4), foot)
	h.check(behind.size() > 2, "from the corner behind a pillar the walk detours (%d points)" % behind.size())
	h.check(behind[0] == Vector3(5.4, 0, 5.4) and behind[behind.size() - 1] == foot, "the detour starts where the fight ended and ends at the ladder foot")
	var length: float = PitSequence.path_length(behind)
	var straight := Vector2(5.4, 5.4).length()
	h.check(length >= straight and length < straight * 1.2, "the detour is short (%.2f m for %.2f m direct)" % [length, straight])
	# Exhaustive: every start the fighters can reach (inside the walk radius, outside the pillars) gets a path that clears all four
	# pillars along its whole length, begins and ends where it should, and is never much longer than the straight line.
	var worst_clear := INF
	var worst_ratio := 0.0
	var paths := 0
	var bad_ends := 0
	var x := -6.5
	while x <= 6.5:
		var z := -6.5
		while z <= 6.5:
			var start := Vector3(x, 0, z)
			if Vector2(x, z).length() <= CombatConstants.ARENA_WALK_RADIUS and _distance_to_pillars(start) >= clearance + 0.05:
				var path := PitSequence.walk_path(start, foot)
				paths += 1
				if path[0] != start or path[path.size() - 1] != foot:
					bad_ends += 1
				var total: float = PitSequence.path_length(path)
				if Vector2(x, z).length() > 0.5:
					worst_ratio = maxf(worst_ratio, total / Vector2(x, z).length())
				var s := 0.0
				while s <= total:
					worst_clear = minf(worst_clear, _distance_to_pillars(PitSequence.path_point(path, s)))
					s += 0.05
			z += 0.5
		x += 0.5
	h.check(paths > 200, "%d start positions checked" % paths)
	h.eq(bad_ends, 0, "every path starts at its start and ends at the ladder foot")
	h.check(worst_clear >= clearance - 0.02, "closest approach to any pillar centre over all paths: %.3f m (pillar %.2f + body %.2f = %.2f)" % [worst_clear, StoneArena.PILLAR_RADIUS, W.WALK_BODY_RADIUS, clearance])
	h.check(worst_ratio < 1.35, "no path is much longer than the straight line (worst %.2fx)" % worst_ratio)
	var path := PitSequence.walk_path(Vector3(1, 0, 1), foot)
	h.check(PitSequence.path_point(path, -1.0) == path[0] and PitSequence.path_point(path, 99.0) == foot, "path_point clamps to the ends")


# ---- the real flow, once per winning role -----------------------------------------------------------------------------------
static func _flow(h, tree: SceneTree) -> void:
	var saved_rate := Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = 600   # the arena ticks one logical 60 Hz tick per physics frame
	for role in CASES:
		var spec: Array = CASES[role]
		h.begin("pit climb: case %s climbs out without clipping the opening, weapons stowed, no snaps" % role)
		var app = Main.instantiate()
		tree.root.size = Vector2i(1200, 800)
		tree.root.add_child(app)
		await tree.process_frame
		await tree.process_frame
		app._switch_mode(1)
		app.game.new_game(0, 0, spec[0])
		app.board_3d.animation_enabled = false
		var world: BattleWorld = app.board_3d.world
		world.auto_advance = false
		await tree.process_frame
		app.game.play(spec[1], spec[2])
		await tree.process_frame
		var pit: PitSequence = world.pit
		app._start_battle_pressed()
		var forced := false
		var frames := 0
		var climb_frames := 0
		var armed_before_stow := false
		var props_visible_while_climbing := 0
		var worst_width := -INF
		var worst_depth := -INF
		var worst_item := ""
		var max_turn := 0.0
		var max_step := 0.0
		var last_yaw := NAN
		var last_pos := Vector3.INF
		while frames < 4000:
			frames += 1
			world.advance(DT)
			await tree.process_frame
			if pit.phase == PitSequence.Phase.COMBAT and not forced:
				forced = true
				var arena: CombatArena = world.chamber.arena_mount.get_child(0)
				var loser = arena.sim.attacker() if spec.size() > 3 and spec[3] == "defender" else arena.sim.defender()
				loser.health.apply_damage(100000)
			if pit.phase == PitSequence.Phase.CLIMB and pit._winner_visual != null and is_instance_valid(pit._winner_visual):
				climb_frames += 1
				var visual: Node3D = pit._winner_visual
				var t_walk: float = pit._climb["t_walk"]
				var points := Fit.samples(visual, 0.0)
				var props := points.filter(func(sample): return String(sample[2]).begins_with("prop "))
				if pit._time < t_walk - W.STOW_TIME - 0.05:
					armed_before_stow = armed_before_stow or not props.is_empty()   # they are carried until the stow begins
				if pit._time >= t_walk:
					props_visible_while_climbing += props.size()
					for band in Fit.BANDS:
						var over := Fit.overshoot(points, band)
						if over["width"] > worst_width:
							worst_width = over["width"]
							worst_item = "%s %s" % [band, over["width_item"]]
						worst_depth = maxf(worst_depth, over["depth"])
				if not is_nan(last_yaw):
					max_turn = maxf(max_turn, absf(angle_difference(last_yaw, visual.rotation.y)))
				if last_pos != Vector3.INF:
					max_step = maxf(max_step, visual.global_position.distance_to(last_pos))
				last_yaw = visual.rotation.y
				last_pos = visual.global_position
			if pit.phase == PitSequence.Phase.RETURN and world.chamber.arena_mount.get_child_count() > 0 and pit._return_ready_sent:
				var done_arena = world.chamber.arena_mount.get_child(0)
				done_arena.stop_battle()
				world.chamber.arena_mount.remove_child(done_arena)
				done_arena.queue_free()
			if pit.is_idle() and frames > 30 and forced:
				break
		h.check(forced and pit.is_idle() and climb_frames > 100, "%s: the sequence ran to the end (%d frames, %d in the climb)" % [role, frames, climb_frames])
		h.check(armed_before_stow, "%s: the winner still carries its props while it walks (they are stowed only at the ladder)" % role)
		h.eq(props_visible_while_climbing, 0, "%s: no weapon or shield is visible once the climb starts" % role)
		h.check(worst_width <= EDGE_TOLERANCE, "%s: body inside the opening across it (%.3f m over; %s)" % [role, worst_width, worst_item])
		h.check(worst_depth <= EDGE_TOLERANCE, "%s: body inside the opening front-to-back (%.3f m over)" % [role, worst_depth])
		h.check(max_turn < MAX_TURN_PER_FRAME, "%s: the facing never snaps (largest turn %.3f rad in one frame)" % [role, max_turn])
		h.check(max_step < MAX_STEP_PER_FRAME, "%s: the position never jumps (largest step %.3f m in one frame)" % [role, max_step])
		app.queue_free()
		await tree.process_frame
		await tree.process_frame
	Engine.physics_ticks_per_second = saved_rate
