extends SceneTree
## Dev tool: how does the winning fighter fit the 1 m opening while it climbs the ladder out of the pit?
## It drives the REAL capture flow (BattleFlow -> PitSequence -> CombatArena) once per winning role, forces the attacker to win by
## damaging the defender in the real simulation, and during the CLIMB phase samples the fighter every frame (see climb_fit.gd:
## bones padded by BONE_RADIUS plus the corners of every visible prop). Per role it reports how far those samples reach outside
## the opening where the fighter is level with the chamber ceiling slab and the board slab, and which bone or prop did it; with
## `shots` it also saves what the player's camera sees at fixed points of the climb.
## The numbers need no rendering, so run headless (about 15 s per role):
##   godot --headless --path godot --script res://combat/tools/climb_audit.gd -- OUT_DIR [roles=pnbrq]
## Screenshots need a renderer (slow in software GL; pass few roles):
##   xvfb-run -a -s "-screen 0 1280x800x24" godot --path godot --rendering-driver opengl3 \
##       --script res://combat/tools/climb_audit.gd -- OUT_DIR shots roles=r
## Writes OUT_DIR/climb_audit.json (and climb_<role>_<n>.png with `shots`). Positive numbers are metres OUTSIDE the opening.
const Main := preload("res://app/main.tscn")
const W := preload("res://world/world_constants.gd")
const Fit := preload("res://combat/tools/climb_fit.gd")
const DT := 1.0 / 60.0
const BONE_RADIUS := 0.10   # a limb is not a point: pad every bone sample (the test uses 0: bone centres must be inside)
## case -> [FEN, from, to, winner?]: one capture by that role; the attacker wins unless the 4th entry is "defender"
## (then the Black pawn on e5 wins and walks in from the far side, z = +2.6). Same positions as pit_climb test.
const CASES := {
	"p": ["4k3/8/8/4p3/3P4/8/8/4K3 w - - 0 1", "d4", "e5"],
	"n": ["4k3/8/8/4p3/8/5N2/8/4K3 w - - 0 1", "f3", "e5"],
	"b": ["4k3/8/8/4p3/8/2B5/8/4K3 w - - 0 1", "c3", "e5"],
	"r": ["4k3/8/8/4p3/8/8/8/4RK2 w - - 0 1", "e1", "e5"],
	"q": ["4k3/8/8/4p3/8/8/1Q6/4K3 w - - 0 1", "b2", "e5"],
	"pd": ["4k3/8/8/4p3/8/5N2/8/4K3 w - - 0 1", "f3", "e5", "defender"],
}
var out_dir := "."
var want_shots := false
var report := {}


func _initialize() -> void:
	await process_frame
	var roles := ["p", "n", "b", "r", "q"]
	for arg in OS.get_cmdline_user_args():
		if arg == "shots":
			want_shots = true
		elif arg.begins_with("roles="):
			roles = arg.trim_prefix("roles=").split(",") if arg.contains(",") else Array(arg.trim_prefix("roles=").split(""))
		elif not arg.contains("="):
			out_dir = arg
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1200, 800)
	Engine.physics_ticks_per_second = 600  # the arena ticks one logical 60 Hz tick per physics frame
	for role in roles:
		if CASES.has(role):
			report[role] = await _run_role(role)
			_save()  # keep partial results if a later role is slow or the run is cut off
	for role in report:
		print(JSON.stringify({"role": role, "worst": report[role]["worst"], "offenders": report[role]["offenders"]}))
	quit()


func _save() -> void:
	var file := FileAccess.open(out_dir.path_join("climb_audit.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()


func _run_role(role: String) -> Dictionary:
	var spec: Array = CASES[role]
	var app = Main.instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	app._switch_mode(1)
	app.game.new_game(0, 0, spec[0])
	app.board_3d.animation_enabled = false
	var world: BattleWorld = app.board_3d.world
	world.auto_advance = false
	await process_frame
	app.game.play(spec[1], spec[2])
	await process_frame
	var pit: PitSequence = world.pit
	app._start_battle_pressed()
	var result := {"role": role, "frames": 0, "samples": 0}
	var worst := {}      # "<band>_<width|depth>" -> metres outside the opening
	var offender := {}   # same key -> what reached furthest, where and when
	var forced := false
	var shot_marks := [0.12, 0.32, 0.55, 0.62, 0.74, 0.88]  # fractions of the ladder climb; ~0.7 is the ceiling slab, ~0.98 the board
	var shot_index := 0
	var frames := 0
	while frames < 4000:
		frames += 1
		world.advance(DT)
		await process_frame
		if pit.phase == PitSequence.Phase.COMBAT and not forced:
			forced = true
			var arena: CombatArena = world.chamber.arena_mount.get_child(0)
			var loser = arena.sim.attacker() if spec.size() > 3 and spec[3] == "defender" else arena.sim.defender()
			loser.health.apply_damage(100000)  # the other side wins
		if pit.phase == PitSequence.Phase.CLIMB and pit._winner_visual != null and is_instance_valid(pit._winner_visual):
			result["frames"] += 1
			var points := Fit.samples(pit._winner_visual, BONE_RADIUS)
			result["samples"] = points.size()
			var fraction := snappedf((pit._time - float(pit._climb["t_walk"])) / float(pit._climb["t_climb"]), 0.01)
			for band in Fit.BANDS:
				var over := Fit.overshoot(points, band)
				for axis in ["width", "depth"]:
					var key: String = band + "_" + axis
					if over[axis] > worst.get(key, -INF):
						worst[key] = over[axis]
						var at: Vector3 = over[axis + "_at"]
						offender[key] = {"item": over[axis + "_item"], "at": [snappedf(at.x, 0.01), snappedf(at.y, 0.01), snappedf(at.z, 0.01)], "climb_fraction": fraction}
			if want_shots and shot_index < shot_marks.size() and fraction >= shot_marks[shot_index]:
				for _i in 2:
					await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(out_dir.path_join("climb_%s_%d.png" % [role, shot_index]))
				shot_index += 1
		if pit.phase == PitSequence.Phase.RETURN and world.chamber.arena_mount.get_child_count() > 0 and pit._return_ready_sent:
			var arena = world.chamber.arena_mount.get_child(0)
			arena.stop_battle()
			world.chamber.arena_mount.remove_child(arena)
			arena.queue_free()
		if pit.is_idle() and frames > 30 and forced:
			break
	for key in worst:
		worst[key] = snappedf(worst[key], 0.001)
	result["worst"] = worst
	result["offenders"] = offender
	result["finished"] = pit.is_idle()
	app.queue_free()
	await process_frame
	await process_frame
	return result
