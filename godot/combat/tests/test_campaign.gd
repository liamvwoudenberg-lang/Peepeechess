extends RefCounted
## Campaign: the node table is valid and scripted from FEN captures, boons are deterministic and applied to fighter state only, the run state machine
## (lives, boss loss, boon picks, clear), saving/loading and unlock rules, and the UI (campaign page, encounter view, menu entries).

const Settings := preload("res://ui/application_settings.gd")
const TMP := "user://campaign_test.json"


static func run(h, tree: SceneTree) -> void:
	_nodes(h)
	_boons(h)
	await _boons_applied(h, tree)
	_run_machine(h)
	_progress(h)
	await _view(h, tree)
	await _page(h, tree)


static func _fresh() -> CampaignProgress:
	for suffix in ["", ".tmp"]:
		if FileAccess.file_exists(TMP + suffix):
			DirAccess.remove_absolute(TMP + suffix)
	var progress := CampaignProgress.new(TMP)
	CampaignProgress._shared = progress
	return progress


static func _nodes(h) -> void:
	h.begin("campaign nodes: a valid 12-encounter table, scripted from chess positions")
	h.eq(CampaignNodes.count(), 12, "twelve encounters")
	h.eq(CampaignNodes.validate(LessonCatalog.load_all()), [], "no schema, matchup or reward problems")
	var levels: Array = []
	for i in CampaignNodes.count():
		levels.append(CampaignNodes.level(i))
	h.check(levels[0] == "easy" and levels[11] == "expert", "levels climb from Easy to Expert")
	var rank := {"easy": 0, "normal": 1, "hard": 2, "expert": 3}
	var monotonic := true
	for i in range(1, levels.size()):
		monotonic = monotonic and rank[levels[i]] >= rank[levels[i - 1]]
	h.check(monotonic, "the level never drops along the path")
	h.check(CampaignNodes.is_boss(5) and CampaignNodes.is_boss(8) and CampaignNodes.is_boss(11) and not CampaignNodes.is_boss(0), "bosses are encounters 6, 9 and 12")
	# position nodes: the capture decides roles and the attacker
	var squire := CampaignNodes.matchup(CampaignNodes.node(1))
	h.eq([squire["player_role"], squire["opponent_role"], squire["attacker"]], ["p", "n", "player"], "pawn takes knight from the FEN: pawn attacks")
	var defended := CampaignNodes.matchup({"kind": "position", "fen": "4k3/8/8/3n4/4P3/8/8/4K3 w - - 0 1", "capture": "e4d5", "player_side": "b"})
	h.eq([defended["player_role"], defended["opponent_role"], defended["attacker"]], ["n", "p", "opponent"], "playing the other side defends the same capture")
	h.eq(CampaignNodes.matchup({"kind": "position", "fen": "4k3/8/8/8/8/8/8/4K3 w - - 0 1", "capture": "e1e2", "player_side": "w"}), {}, "a non-capture is refused")
	h.eq(CampaignNodes.matchup({"kind": "position", "fen": "nonsense", "capture": "e4d5"}), {}, "a bad FEN is refused")
	var gambit := CampaignNodes.lesson_for(6)
	h.check(float(gambit["duration_seconds"]) == 45.0 and gambit["objectives"][0]["type"] == "win", "a timed node carries its time limit and a win objective")
	var bridge := CampaignNodes.lesson_for(4)
	h.check(float(bridge["constraints"]["player_hp_fraction"]) == 0.8, "a handicapped node starts the player at 80% health")
	h.eq(LessonSchema.validate(bridge), [], "node lessons are valid training lessons")


static func _boons(h) -> void:
	h.begin("campaign boons: offers are deterministic, distinct and respect the stack limit")
	var a := CampaignBoons.offer(42, 3, ["vitality"])
	var b := CampaignBoons.offer(42, 3, ["vitality"])
	h.eq(a, b, "the same seed, node and boons give the same offer")
	h.eq(a.size(), 3, "three boons are offered")
	h.check(a[0] != a[1] and a[1] != a[2] and a[0] != a[2], "the offered boons are distinct")
	var different := false
	for s in range(1, 12):
		different = different or CampaignBoons.offer(s, 3, ["vitality"]) != a
	h.check(different, "other seeds give other offers")
	var stacked := CampaignBoons.offer(7, 2, ["vitality", "vitality", "endurance", "endurance", "efficiency", "efficiency"])
	h.check(not stacked.has("vitality") and not stacked.has("endurance") and not stacked.has("efficiency"), "a boon at its stack limit is not offered again")
	h.eq(stacked.size(), 2, "fewer than three remain when most are stacked out")
	h.eq(CampaignBoons.offer(7, 2, ["vitality", "vitality", "endurance", "endurance", "efficiency", "efficiency", "second_wind", "second_wind", "iron_will", "iron_will"]), [], "nothing is offered when every boon is stacked out")


static func _boons_applied(h, tree: SceneTree) -> void:
	h.begin("campaign boons: applied to the player's fighter state only")
	var sim := CombatSimulation.new()
	tree.root.add_child(sim)
	var reply: Dictionary = sim.start(FighterRoster.build_request("p", "p", "w", "campaign-boon", 5, 0), {"allow_experimental_roles": true})
	h.check(reply.get("ok", false), "a duel starts")
	await tree.physics_frame
	var me := sim.fighter_by_id("player-white")
	var foe := sim.fighter_by_id("player-black")
	var hp := me.health.maximum
	var stamina := me.stamina.maximum
	var foe_hp := foe.health.maximum
	var summary := CampaignBoons.apply(sim, ["vitality", "endurance", "efficiency", "second_wind"], "player-white")
	h.eq(me.health.maximum, int(round(float(hp) * 1.15)), "Vitality: +15% maximum health")
	h.check(me.health.current == me.health.maximum, "current health follows the larger pool")
	h.check(is_equal_approx(me.stamina.maximum, stamina * 1.25), "Endurance: +25% stamina pool")
	h.check(is_equal_approx(me.stamina.cost_multiplier, 0.85) and is_equal_approx(me.stamina.seat_regen, 1.3), "Efficiency and Second wind scale cost and regeneration")
	h.eq(foe.health.maximum, foe_hp, "the opponent is untouched")
	h.eq(summary["health_max"], me.health.maximum, "the summary reports the new pool")
	sim.stop()
	sim.get_parent().remove_child(sim)
	sim.queue_free()


static func _run_machine(h) -> void:
	h.begin("campaign run: wins offer boons, losses cost lives, a lost boss ends the run, the last win clears it")
	var run := CampaignRun.start(11)
	h.check(run.status == "map" and run.index == 0 and run.lives == 3, "a new run starts at the gate with three lives")
	var report := run.report(true)
	h.check(report["event"] == "boon" and run.status == "boon" and run.offer.size() == 3, "a win offers three boons")
	h.check(not run.pick_boon("not_a_boon"), "a boon that was not offered is refused")
	var picked: String = run.offer[0]
	h.check(run.pick_boon(picked) and run.index == 1 and run.status == "map" and run.boons == [picked], "picking a boon moves on and keeps it")
	h.eq(run.report(false)["event"], "retry", "a lost ordinary encounter can be retried")
	h.eq(run.lives, 2, "...and costs a life")
	run.report(false)
	var over := run.report(false)
	h.check(over["event"] == "run_over" and over["reason"] == "lives" and run.status == "lost" and run.lives == 0, "no lives left ends the run")
	h.eq(run.report(true)["event"], "ignored", "a finished run ignores further results")
	# a lost boss ends the run at once
	var boss_run := CampaignRun.start(3)
	boss_run.index = 5
	var lost := boss_run.report(false)
	h.check(lost["event"] == "run_over" and lost["reason"] == "boss" and boss_run.lives == 3 and boss_run.status == "lost", "a lost boss ends the run without costing lives")
	# the whole path
	var full := CampaignRun.start(5)
	for i in CampaignNodes.count():
		var r := full.report(true)
		if i < CampaignNodes.count() - 1:
			if i == 0:
				h.check(r["event"] == "boon", "encounter 1 won: boon offer")
			if not full.offer.is_empty():
				full.pick_boon(full.offer[0])
		else:
			h.eq(r["event"], "cleared", "the last win clears the campaign")
	h.check(full.status == "cleared" and full.nodes_cleared() == 12, "all twelve encounters are cleared")
	h.check(CampaignBoons.stack_of(full.boons, "vitality") <= 2, "no boon was stacked past its limit over the whole run")
	# determinism of the whole run
	var again := CampaignRun.start(5)
	for i in CampaignNodes.count() - 1:
		again.report(true)
		if not again.offer.is_empty():
			again.pick_boon(again.offer[0])
	h.eq(again.boons, full.boons, "the same seed and choices give the same boons")


static func _progress(h) -> void:
	h.begin("campaign progress: saves, loads, grants rewards once, equips only what is unlocked")
	var progress := _fresh()
	h.check(progress.run == null and progress.unlocked_arenas.is_empty(), "a fresh save is empty")
	progress.start_run(9)
	h.eq(progress.runs_started, 1, "a run is counted")
	# clear the first 4 encounters (n02 arena moonlit, n04 skin gilded)
	var rewards: Array = []
	for i in 4:
		var report := progress.report_result(true)
		rewards.append_array(report["rewards"])
		progress.run.pick_boon(progress.run.offer[0])
	h.eq(rewards, ["arena:moonlit", "skin:gilded"], "rewards are granted the first time an encounter is cleared")
	h.check(progress.unlocked_arenas == ["moonlit"] and progress.unlocked_skins == ["gilded"], "unlocks are recorded")
	h.check(not progress.equip_arena("crypt") and progress.equip_arena("moonlit") and progress.equipped_arena == "moonlit", "only an unlocked arena can be equipped")
	h.check(not progress.equip_skin("ember") and progress.equip_skin("gilded"), "only an unlocked skin can be equipped")
	h.check(progress.best_cleared == 4, "the best run counts cleared encounters")
	var loaded := CampaignProgress.new(TMP)
	h.check(loaded.run != null and loaded.run.index == 4 and loaded.run.boons.size() == 4, "the run in progress survives a restart")
	h.check(loaded.unlocked_arenas == ["moonlit"] and loaded.equipped_skin == "gilded" and loaded.best_cleared == 4, "unlocks, equipment and the best run survive a restart")
	# a second run does not grant the same rewards again
	progress.abandon_run()
	progress.start_run(10)
	var again: Dictionary = progress.report_result(true)
	progress.run.pick_boon(progress.run.offer[0])
	var second: Dictionary = progress.report_result(true)
	h.eq([again["rewards"], second["rewards"]], [[], []], "a cleared encounter grants nothing the second time")
	h.check(progress.best_cleared == 4, "the best run is not lowered by a worse run")
	# bonus lessons open the training lesson without its prerequisites
	progress.start_run(1)
	progress.run.index = 5
	progress.report_result(true)
	h.check(progress.is_lesson_unlocked("a01_knight_vs_pawn") and progress.unlocked_arenas.has("crypt"), "a boss reward unlocks a bonus lesson and an arena")
	var catalog := LessonCatalog.load_all()
	var store := ProgressStore.new("user://campaign_test_training.json", false)
	h.check(catalog.is_unlocked("a01_knight_vs_pawn", store) or not catalog.is_available("a01_knight_vs_pawn"), "the unlocked Training lesson opens")
	h.check(CampaignProgress.arena_light(Color.WHITE) == CampaignProgress.ARENA_LIGHT["moonlit"], "the equipped arena palette colours the moonlight")
	progress.equip_arena("")
	h.eq(CampaignProgress.arena_light(Color(0.1, 0.2, 0.3)), Color(0.1, 0.2, 0.3), "no equipped arena keeps the default light")
	# a corrupt or foreign file starts empty without failing
	var file := FileAccess.open(TMP, FileAccess.WRITE)
	file.store_string("{ not json")
	file.close()
	var broken := CampaignProgress.new(TMP)
	h.check(broken.run == null and broken.last_error != "", "a corrupt file starts empty")
	file = FileAccess.open(TMP, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 1, "meta": {"skins": ["bogus", "ember"], "arenas": ["crypt", 7], "equipped_skin": "gilded", "best_cleared": 99}, "run": {"index": 99, "lives": 9, "boons": ["vitality", "vitality", "vitality", "x"], "status": "wat"}}))
	file.close()
	var hostile := CampaignProgress.new(TMP)
	h.check(hostile.unlocked_skins == ["ember"] and hostile.unlocked_arenas == ["crypt"] and hostile.equipped_skin == "" and hostile.best_cleared == 12, "saved data is clamped and filtered")
	h.check(hostile.run != null and hostile.run.index == 11 and hostile.run.lives == 3 and hostile.run.boons == ["vitality", "vitality"] and hostile.run.status == "map", "a hostile run record is clamped to a valid run")
	for suffix in ["", ".tmp"]:
		if FileAccess.file_exists(TMP + suffix):
			DirAccess.remove_absolute(TMP + suffix)
	CampaignProgress._shared = null


static func _view(h, tree: SceneTree) -> void:
	h.begin("campaign encounter view: the real arena with boons, a boon card after a win, lives after a loss")
	var progress := _fresh()
	progress.start_run(21)
	progress.run.boons = ["vitality"]
	var training_store := ProgressStore.new("user://campaign_test_training.json", false)
	DuelAi._store = training_store
	var view := CampaignView.new()
	view.setup_campaign(progress, training_store)
	tree.root.add_child(view)
	for i in 5:
		await tree.process_frame
	h.check(view.arena != null and view.tracker != null and view.opponent != null, "the view builds arena, tracker and opponent")
	h.eq(view.lesson["id"], "campaign_n01_gate", "it plays the run's current encounter")
	h.check(view.boon_summary.get("health_max", 0) > 0 and view.arena.sim.fighter_by_id("player-white").health.maximum == int(view.boon_summary["health_max"]), "the run's boons are applied to the player")
	var exited := [0]
	view.exit_requested.connect(func(): exited[0] += 1)
	view._on_completed({"seconds": 12.0, "completed": true})
	h.check(view._card != null and progress.run.status == "boon" and progress.run.offer.size() == 3, "a win shows the boon card and the run waits for a pick")
	h.check(not training_store.lessons.has("campaign_n01_gate"), "campaign results never touch the Training progress")
	view._take_boon(progress.run.offer[0])
	h.check(exited[0] == 1 and progress.run.index == 1 and progress.run.boons.size() == 2, "taking a boon saves it and returns to the map")
	view.queue_free()
	await tree.process_frame
	# a loss
	var view2 := CampaignView.new()
	view2.setup_campaign(progress, training_store)
	tree.root.add_child(view2)
	for i in 5:
		await tree.process_frame
	view2._on_failed("lost", {})
	h.check(view2._card != null and progress.run.lives == 2 and progress.run.status == "map", "a loss costs a life and offers a retry")
	view2.queue_free()
	await tree.process_frame
	DuelAi._store = null
	for suffix in ["", ".tmp"]:
		if FileAccess.file_exists(TMP + suffix):
			DirAccess.remove_absolute(TMP + suffix)
	CampaignProgress._shared = null


static func _page(h, tree: SceneTree) -> void:
	h.begin("campaign page: menu entries, new run, path, boon picks and unlocks are reachable")
	var progress := _fresh()
	tree.root.size = Vector2i(1280, 800)
	Settings.loaded = true
	Settings.token = ""
	Settings.account.clear()
	Settings.launch.clear()
	Settings.intro_seen = true
	var shell: Control = (load("res://ui/application.tscn") as PackedScene).instantiate()
	tree.root.add_child(shell)
	for i in 4:
		await tree.process_frame
	h.check(shell._menu_buttons.has("campaign"), "the top navigation has a Campaign entry")
	shell.navigate("campaign")
	for i in 3:
		await tree.process_frame
	h.eq(shell.page, "campaign", "the Campaign page opens")
	var new_run: Button = shell.content.find_child("NewRun", true, false)
	h.check(new_run != null and not new_run.disabled, "a new run can be started")
	new_run.pressed.emit()
	for i in 3:
		await tree.process_frame
	h.check(progress.run != null and progress.runs_started == 1, "starting a run saves it")
	var fight: Button = shell.content.find_child("FightNode", true, false)
	h.check(fight != null, "the next encounter can be fought")
	h.check(shell.content.find_children("Boon_*", "Button", true, false).is_empty(), "no boon is offered before a win")
	progress.report_result(true)
	shell.navigate("campaign")
	for i in 3:
		await tree.process_frame
	var boons: Array = shell.content.find_children("Boon_*", "Button", true, false)
	h.eq(boons.size(), 3, "after a win the page offers three boons")
	boons[0].pressed.emit()
	for i in 3:
		await tree.process_frame
	h.check(progress.run.index == 1 and progress.run.boons.size() == 1, "picking a boon on the page advances the run")
	h.check(shell.content.find_child("Arena_default", true, false) != null and shell.content.find_child("Skin_gilded", true, false) != null, "the unlocks card lists arenas and skins")
	var moonlit: Button = shell.content.find_child("Arena_moonlit", true, false)
	h.check(moonlit != null and moonlit.disabled, "a locked arena cannot be chosen")
	h.check(shell.get("_menu_buttons") != null, "the shell stays intact")
	shell.queue_free()
	await tree.process_frame
	Settings.launch.clear()
	# the title menu has the entry too
	var title_source := FileAccess.get_file_as_string("res://ui/theme/title_screen.gd")
	h.check(title_source.contains('["campaign", "Campaign"'), "the title menu has a Campaign entry")
	for suffix in ["", ".tmp"]:
		if FileAccess.file_exists(TMP + suffix):
			DirAccess.remove_absolute(TMP + suffix)
	CampaignProgress._shared = null
