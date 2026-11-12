extends SceneTree
## Dev tool: screenshots of the King's last stand (battle-royal-v1) in the real application screen. It plays real sequences through
## the real flow, bridge, pit world and CombatArena at wall-clock speed (the simulation is shortened by damaging a fighter, exactly
## like the headless suite does) and saves PNGs at fixed moments.
##   xvfb-run -a -s "-screen 0 1280x800x24" godot --path godot --rendering-driver opengl3 \
##       --script res://combat/tools/royal_flow_shots.gd -- OUT_DIR
## Files: toggle_dialog, toggle_play, banner_duel2, descent_duel1, chamber_duel2, climb, defeat_result (.png)
const Main := preload("res://app/main.tscn")
const Application := preload("res://ui/application.tscn")
const BOTH := "R3k3/3p1p2/8/8/8/8/8/4R1K1 b - - 0 1"
var out_dir := "."


func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else "."
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1280, 800)
	RoyalOption.persist = false
	Engine.physics_ticks_per_second = 120
	await _toggle_shots()
	await _sequence_shots()
	await _defeat_shots()
	quit()


func _shot(name: String) -> void:
	for _i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])
	print("saved ", name)


func _toggle_shots() -> void:
	var app = Main.instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	app.set_view(true)
	app._switch_mode(1)
	app.opponent.royal_state["royal"] = true
	app.opponent.selection = {"kind": "computer", "level": 3, "color": "w"}
	app.opponent.prepare_new_dialog()
	app.new_dialog.popup(Rect2i(380, 90, 460, 560))
	for _i in 12:
		await process_frame
	await _shot("toggle_dialog")
	app.queue_free()
	await process_frame
	await process_frame
	var page = Application.instantiate()
	root.add_child(page)
	await process_frame
	await process_frame
	page.selected_mode = "battle"
	page.ruleset["royal"] = true
	page.navigate("play")
	for _i in 8:
		await process_frame
	await _shot("toggle_play")
	page.queue_free()
	await process_frame


func _boot(fen: String, human_color: String) -> Dictionary:
	var app = Main.instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	app.set_view(false)
	app._switch_mode(1, true)
	app.game.new_game(0, 0, fen)
	app.opponent.start_computer({"kind": "computer", "level": 3, "color": human_color})
	await process_frame
	return {"app": app, "world": app.board_3d.world, "pit": app.board_3d.world.pit, "flow": app.battle_flow, "game": app.game, "adapter": app.battle_adapter}


## Applies `plan` to the real simulation of the duel the match has pending as soon as that arena runs it.
func _plan_when_running(ctx: Dictionary, plan: Dictionary) -> void:
	var arena: CombatArena = ctx["adapter"].arena
	if int(plan.get("king_damage", 0)) > 0:
		arena.sim.attacker().health.apply_damage(int(plan["king_damage"]))
	if plan.get("kill_king", false):
		arena.sim.attacker().health.apply_damage(100000)
	if plan.get("kill_checker", false):
		arena.sim.defender().health.apply_damage(100000)


func _sequence_shots() -> void:
	var ctx := await _boot(BOTH, "b")   # the human plays the mated Black King; the computer fights the two checking rooks
	var pit: PitSequence = ctx["pit"]
	var flow: BattleFlow = ctx["flow"]
	var game: BattleRoyalMatch = ctx["game"]
	var adapter = ctx["adapter"]
	var done := {}
	var duel_planned := {}
	var frames := 0
	while frames < 4000 and not (pit.is_idle() and flow.phase == "board" and frames > 30):
		frames += 1
		await process_frame
		var arena = adapter.arena
		var pending := game.pending_request()
		var battle_id: String = String(pending.get("battleId", ""))
		var index := game.royal_progress().get("duelIndex", -1) as int
		if flow.phase == "preview" and pit.phase == PitSequence.Phase.INTERLUDE and not done.has("banner") and ctx["app"].royal_presenter.banner.visible:
			for _i in 10:
				await process_frame
			done["banner"] = true
			await _shot("banner_duel2")
		if pit.phase == PitSequence.Phase.DROP and pit._time > 0.7 and not done.has("descent"):
			done["descent"] = true
			await _shot("descent_duel1")
		if is_instance_valid(arena) and arena.sim.is_running() and arena.sim.request.get("battleId", "") == battle_id and arena.hud != null and arena.hud.context_text() != "":
			if index == 0 and not duel_planned.has(battle_id):
				duel_planned[battle_id] = true
				_plan_when_running(ctx, {"king_damage": 50, "kill_checker": true})
			elif index == 1 and pit.phase == PitSequence.Phase.COMBAT and not done.has("chamber"):
				done["chamber"] = true
				for _i in 6:
					await process_frame
				await _shot("chamber_duel2")
				_plan_when_running(ctx, {"kill_checker": true})
				duel_planned[battle_id] = true
		if pit.phase == PitSequence.Phase.CLIMB and pit._time > 1.4 and not done.has("climb"):
			done["climb"] = true
			await _shot("climb")
	print("sequence frames: ", frames, " shots: ", done.keys())
	ctx["app"].queue_free()
	await process_frame
	await process_frame


func _defeat_shots() -> void:
	var ctx := await _boot("6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1", "w")   # the human (White) mates; the computer King falls
	var app = ctx["app"]
	var pit: PitSequence = ctx["pit"]
	var flow: BattleFlow = ctx["flow"]
	var game: BattleRoyalMatch = ctx["game"]
	var adapter = ctx["adapter"]
	app.game.play("a1", "a8")
	var planned := false
	var frames := 0
	var shot := false
	while frames < 3000 and not shot:
		frames += 1
		await process_frame
		var arena = adapter.arena
		if not planned and is_instance_valid(arena) and arena.sim.is_running() and arena.hud != null and arena.hud.context_text() != "":
			planned = true
			_plan_when_running(ctx, {"kill_king": true})
		for child in app.get_children():
			if child is AcceptDialog and child.visible:
				for _i in 15:
					await process_frame
				await _shot("defeat_result")
				shot = true
				break
	print("defeat frames: ", frames, " shot: ", shot, " result: ", game.engine.result)
	app.queue_free()
	await process_frame
	await process_frame
