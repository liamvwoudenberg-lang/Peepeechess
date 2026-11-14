extends RefCounted
## The training framework (godot/training/): lesson schema and catalog, objective detection from REAL simulation events, failure
## conditions, handicaps, ratings, progress save/load, unlocks and Free Practice. Scripted "players" drive the real CombatSimulation
## through TrainingSession (the same engine as a Battle Chess duel); objectives must complete only from what actually connected.

const TMP := "user://training_test"
const S := CombatConstants.State


static func run(h, tree: SceneTree) -> void:
	_schema(h)
	_catalog(h)
	await _detect_combo(h, tree)
	await _detect_basics(h, tree)
	await _detect_stamina_and_distance(h, tree)
	await _failures(h, tree)
	_synthetic_events(h)
	_rating(h)
	_progress(h)
	_unlocks(h)
	_free_practice(h)


# ---- helpers ---------------------------------------------------------------------------------------------------------
static func _lesson(extra: Dictionary) -> Dictionary:
	var d := {"id": "t_custom", "title": "T", "summary": "S", "category": "beginner", "order": 1, "player_role": "p", "opponent_role": "p",
			"behaviour": "idle", "difficulty": "easy", "objectives": [], "fail": [], "rating": {}}
	d.merge(extra, true)
	return d


static func _start(tree: SceneTree, lesson: Dictionary, options: Dictionary = {}) -> TrainingSession:
	var session := TrainingSession.new(lesson, options)
	await session.start(tree)
	session.skip_countdown()
	return session


static func _dist(session: TrainingSession) -> float:
	var a := session.sim.fighter_by_id(TrainingSession.PLAYER_ID)
	var b := session.sim.fighter_by_id(TrainingSession.OPPONENT_ID)
	return Vector2(a.global_position.x - b.global_position.x, a.global_position.z - b.global_position.z).length()


## A simple scripted attacker: walk in to `reach`, then press light every `every` ticks.
static func _striker(every: int = 9, reach: float = 1.3) -> Callable:
	return func(session: TrainingSession) -> void:
		session.player.move = Vector2.ZERO
		if _dist(session) > reach:
			var me := session.sim.fighter_by_id(TrainingSession.PLAYER_ID)
			var other := session.sim.fighter_by_id(TrainingSession.OPPONENT_ID)
			var d := other.global_position - me.global_position
			session.player.move = Vector2(d.x, d.z).normalized()
		elif session.ticks % every == 0:
			session.player.press("light")


# ---- schema and catalog ----------------------------------------------------------------------------------------------
static func _schema(h) -> void:
	h.begin("training: lesson schema accepts a valid lesson and rejects broken ones")
	h.eq(LessonSchema.validate(_lesson({"objectives": [{"id": "a", "type": "hit_count", "text": "x", "count": 2}]})), [], "a valid lesson has no problems")
	var bad: Array = LessonSchema.validate(_lesson({"player_role": "z", "objectives": [{"id": "a", "type": "hit_count", "text": "x", "count": 2}]}))
	h.check(bad.size() == 1 and "player_role" in String(bad[0]), "an unknown role is reported")
	h.check(not LessonSchema.validate(_lesson({"objectives": [{"id": "a", "type": "teleport", "text": "x"}]})).is_empty(), "an unknown objective type is rejected")
	h.check(not LessonSchema.validate(_lesson({"objectives": [{"id": "a", "type": "combo", "text": "x"}]})).is_empty(), "a combo objective needs a count")
	h.check(not LessonSchema.validate(_lesson({"objectives": [{"id": "a", "type": "hit_count", "text": "x", "count": 1}, {"id": "a", "type": "hit_count", "text": "y", "count": 1}]})).is_empty(), "duplicate objective ids are rejected")
	h.check(not LessonSchema.validate(_lesson({"available": false})).is_empty(), "an unavailable lesson needs a reason")
	h.eq(LessonSchema.validate(_lesson({"available": false, "unavailable_reason": "not implemented"})), [], "...and is valid with one")
	h.check(not LessonSchema.validate(_lesson({"behaviour": "dance", "objectives": [{"id": "a", "type": "win", "text": "x"}]})).is_empty(), "an unknown opponent behaviour is rejected")
	h.check(not LessonSchema.validate(_lesson({"constraints": {"player_hp_fraction": 2.0}, "objectives": [{"id": "a", "type": "win", "text": "x"}]})).is_empty(), "an out-of-range HP handicap is rejected")


static func _catalog(h) -> void:
	h.begin("training: every shipped lesson file is valid and the catalog is complete and consistent")
	var catalog := LessonCatalog.load_all()
	h.eq(catalog.errors, [], "no schema problems in res://training/lessons")
	h.check(catalog.lessons.size() >= 25, "at least 25 lessons (%d)" % catalog.lessons.size())
	for category in LessonSchema.CATEGORIES:
		h.check(catalog.in_category(category).size() >= 4, "category %s has lessons (%d)" % [category, catalog.in_category(category).size()])
	var unavailable := catalog.lessons.filter(func(l): return not bool(l.get("available", true)))
	h.check(unavailable.size() >= 1 and unavailable.all(func(l): return String(l["unavailable_reason"]) != ""), "unavailable lessons say why (%d)" % unavailable.size())
	var broken := 0
	for lesson in catalog.lessons:
		for required in lesson.get("requires", []):
			if not catalog.by_id.has(required):
				broken += 1
	h.eq(broken, 0, "every `requires` points at an existing lesson")
	# the named matchups of the brief exist as playable character lessons
	var pairs := {}
	for lesson in catalog.playable():
		pairs["%s-%s" % [lesson["player_role"], lesson["opponent_role"]]] = true
	for pair in ["n-p", "r-n", "b-r", "q-k", "k-q"]:
		h.check(pairs.has(pair), "a playable lesson for the matchup %s" % pair)
	# every lesson's roles can actually start a real battle request (schema-valid)
	var codec := load("res://contracts/codec.gd").new()
	var bad_requests := 0
	for lesson in catalog.playable():
		var request := TrainingSession.new(lesson).lesson_request()
		if not codec.valid("BattleRequest", request):
			bad_requests += 1
	h.eq(bad_requests, 0, "every playable lesson builds a schema-valid BattleRequest")


# ---- detection from real fights --------------------------------------------------------------------------------------
static func _detect_combo(h, tree: SceneTree) -> void:
	h.begin("training: a combo objective completes only from chained hits that really connected")
	var lesson := LessonCatalog.load_all().get_lesson("b08_first_combo")
	var session := await _start(tree, lesson)
	var combos: Array = []
	session.tracker.combo_changed.connect(func(n): combos.append(n))
	session.run(_striker())
	var result := session.finish()
	h.check(result["completed"], "a striker landing chained light hits completes the 3-hit combo lesson (best combo %d, hits %d)" % [session.tracker.stats["best_combo"], session.tracker.stats["hits"]])
	h.check(3 in combos and int(session.tracker.stats["best_combo"]) >= 3, "the combo counter reached 3 through real hits")
	h.check(result["rating"] in ["bronze", "silver", "gold"], "a completed lesson gets a rating (%s)" % result["rating"])
	session.stop()
	# pressing attack without connecting never counts
	var spam := await _start(tree, lesson)
	spam.player.move = Vector2.ZERO
	var gap := _dist(spam)
	var reach := float(FighterRoster.stats_for("p")["reachM"])
	h.check(gap > reach + 0.5, "the fighters start out of reach (%.2f m > %.2f m)" % [gap, reach + 0.5])
	var presses := 0
	for i in 400:
		if i % 6 == 0:
			spam.player.press("light")
			presses += 1
		spam.step()
	h.check(presses > 40 and int(spam.tracker.stats["hits"]) == 0, "%d attack presses in the air connected 0 times" % presses)
	h.check(not spam.tracker.finished and spam.tracker.objective_state("combo")["value"] == 0.0, "...so the combo objective did not move")
	spam.stop()


static func _detect_basics(h, tree: SceneTree) -> void:
	h.begin("training: movement, hit, range, block, dodge, cancel and ability objectives come from real events")
	var catalog := LessonCatalog.load_all()
	# movement
	var move := await _start(tree, catalog.get_lesson("b01_movement"))
	var walker := func(s: TrainingSession) -> void:
		s.player.move = Vector2(0, 1) if (s.ticks / 90) % 2 == 0 else Vector2(0, -1)
	move.run(walker)
	h.check(move.tracker.finished, "walking 8 m completes the movement lesson (%.1f m)" % float(move.tracker.stats["distance"]))
	move.stop()
	# hit count on the dummy
	var strike := await _start(tree, catalog.get_lesson("b03_first_strike"))
	strike.run(_striker())
	h.check(strike.tracker.finished and strike.tracker.stats["hits"] >= 3, "three light hits complete the basic-attack lesson")
	strike.stop()
	# hit at range: the Knight hits from 1.4 m
	var range_lesson := catalog.get_lesson("b04_range")
	var rng := await _start(tree, range_lesson)
	rng.run(_striker(9, 1.55))
	h.check(rng.tracker.finished, "hits taken from at least 1.2 m complete the range lesson (best %s)" % str(rng.tracker.objective_state("far")))
	rng.stop()
	var close := await _start(tree, range_lesson)
	close.run(_striker(9, 0.55))
	h.check(int(close.tracker.stats["hits"]) > 0 and close.tracker.objective_state("far")["value"] == 0.0 and not close.tracker.finished,
			"hits from point-blank range (%d) do not satisfy the range objective" % int(close.tracker.stats["hits"]))
	close.stop()
	# block: hold the guard while the opponent attacks
	var block := await _start(tree, catalog.get_lesson("b05_block"))
	var block_bot := func(s: TrainingSession) -> void:
		s.player.block = true
		s.player.move = Vector2.ZERO
	block.run(block_bot, 2400)
	h.check(int(block.tracker.stats["blocks"]) >= 1, "holding block against an attacker registers blocks (%d)" % int(block.tracker.stats["blocks"]))
	h.check(block.tracker.finished == (int(block.tracker.stats["blocks"]) >= 3), "...and the objective completes exactly when 3 blocks happened")
	block.stop()
	# dodge: dodge when the opponent starts a swing
	var dodge := await _start(tree, catalog.get_lesson("b06_dodge"))
	var dodge_bot := func(s: TrainingSession) -> void:
		var opp := s.sim.fighter_by_id(TrainingSession.OPPONENT_ID)
		if opp.sm.state == S.ATTACKING and opp.sm.state_ticks == 4 and _dist(s) < 2.6:
			s.player.move = Vector2(1, 0)
			s.player.press("dodge")
		elif opp.sm.state != S.ATTACKING:
			s.player.move = Vector2.ZERO
	dodge.run(dodge_bot, 3000)
	h.check(int(dodge.tracker.stats["dodges"]) >= 1, "dodging into an attack registers dodges (%d)" % int(dodge.tracker.stats["dodges"]))
	dodge.stop()
	# cancel: attack, then dodge out of the recovery
	var cancel_lesson := _lesson({"id": "t_cancel", "objectives": [{"id": "c", "type": "cancel", "text": "cancel", "count": 1}]})
	var cancel := await _start(tree, cancel_lesson)
	var cancel_bot := func(s: TrainingSession) -> void:
		var me := s.sim.fighter_by_id(TrainingSession.PLAYER_ID)
		if _dist(s) > 1.3:
			var other := s.sim.fighter_by_id(TrainingSession.OPPONENT_ID)
			var d := other.global_position - me.global_position
			s.player.move = Vector2(d.x, d.z).normalized()
		else:
			s.player.move = Vector2(1, 0)
			if int(me.sm.state) == S.IDLE or int(me.sm.state) == S.MOVING:
				s.player.press("light")
			elif int(me.sm.state) == S.ATTACKING and me.sm.state_ticks >= 12:
				s.player.press("dodge")
	cancel.run(cancel_bot, 1500)
	h.check(cancel.tracker.finished and int(cancel.tracker.stats["cancels"]) >= 1, "an attack cancelled into a dodge completes the cancel objective")
	cancel.stop()
	# a plain dodge without attacking does not count as a cancel
	var no_cancel := await _start(tree, cancel_lesson)
	for i in 120:
		if i % 30 == 0:
			no_cancel.player.move = Vector2(1, 0)
			no_cancel.player.press("dodge")
		no_cancel.step()
	h.eq(int(no_cancel.tracker.stats["cancels"]), 0, "dodging from idle is not an attack cancel")
	no_cancel.stop()
	# ability use (the Knight's Lunging Strike)
	var ability := await _start(tree, _lesson({"id": "t_ability", "player_role": "n", "objectives": [{"id": "a", "type": "ability_use", "text": "ability", "count": 1}]}))
	ability.player.press("ability")
	for i in 40:
		ability.step()
	h.check(ability.tracker.finished, "using the Knight's Lunging Strike completes the ability objective")
	ability.stop()


static func _detect_stamina_and_distance(h, tree: SceneTree) -> void:
	h.begin("training: stamina cycle, hold-distance and survive objectives")
	var catalog := LessonCatalog.load_all()
	var cycle := await _start(tree, catalog.get_lesson("b07_stamina"))
	var phase := {"drained": false}
	var cycle_bot := func(s: TrainingSession) -> void:
		var me := s.sim.fighter_by_id(TrainingSession.PLAYER_ID)
		var frac := me.stamina.current / me.stamina.maximum
		if frac < 0.3:
			phase["drained"] = true
		if not phase["drained"]:
			s.player.press("light")
		s.player.move = Vector2.ZERO
	cycle.run(cycle_bot, 2500)
	h.check(phase["drained"], "attacking drained the stamina below 30%")
	h.check(cycle.tracker.finished, "waiting afterwards recovers it to 90% and completes the lesson")
	cycle.stop()
	var hold := await _start(tree, _lesson({"id": "t_hold", "objectives": [{"id": "g", "type": "hold_distance", "text": "gap", "min": 1.0, "max": 99.0, "seconds": 2}]}))
	for i in 200:
		hold.step()
	h.check(hold.tracker.finished, "standing in the allowed range band for 2 s completes hold_distance")
	hold.stop()
	var survive := await _start(tree, _lesson({"id": "t_survive", "behaviour": "idle", "objectives": [{"id": "s", "type": "survive", "text": "survive", "seconds": 3}]}))
	for i in 240:
		survive.step()
	h.check(survive.tracker.finished, "surviving 3 live seconds completes survive")
	survive.stop()


static func _failures(h, tree: SceneTree) -> void:
	h.begin("training: failure conditions, handicaps and the real win condition")
	# time limit
	var limited := await _start(tree, _lesson({"id": "t_limit", "fail": [{"type": "time_limit", "seconds": 2}],
			"objectives": [{"id": "h", "type": "hit_count", "text": "hit", "count": 99}]}))
	for i in 200:
		limited.step()
	h.check(limited.tracker.failed and limited.tracker.fail_reason == "time_limit", "a time limit fails the lesson (%s)" % limited.tracker.fail_reason)
	limited.stop()
	# defeat: stand still against an attacking queen that strikes first
	var defeat := await _start(tree, _lesson({"id": "t_defeat", "player_role": "p", "opponent_role": "q", "behaviour": "attack_only", "attacker": "opponent",
			"objectives": [{"id": "s", "type": "survive", "text": "survive", "seconds": 85}]}))
	var idle_bot := func(s: TrainingSession) -> void:
		s.player.move = Vector2.ZERO
	defeat.run(idle_bot, 5400)
	h.check(defeat.tracker.failed and defeat.tracker.fail_reason == "defeated", "being knocked out fails the lesson (%s)" % defeat.tracker.fail_reason)
	var summary := defeat.finish()
	h.check(not summary["completed"] and summary["rating"] == "", "a failed lesson has no rating")
	defeat.stop()
	# HP handicap
	var handicap_lesson := LessonCatalog.load_all().get_lesson("e02_limited_health")
	var handicap := await _start(tree, handicap_lesson)
	var me := handicap.sim.fighter_by_id(TrainingSession.PLAYER_ID)
	h.check(me.health.current == int(ceil(float(me.health.maximum) * 0.5)), "the limited-health lesson starts the player at half HP (%d/%d)" % [me.health.current, me.health.maximum])
	handicap.stop()
	# win through the real result: the player knocks out an idle dummy
	var win := await _start(tree, _lesson({"id": "t_win", "objectives": [{"id": "w", "type": "win", "text": "win"}]}))
	win.run(_striker(9, 1.3), 5400)
	h.check(win.tracker.finished and not win.tracker.failed, "knocking the dummy out completes a win objective (hits %d)" % int(win.tracker.stats["hits"]))
	h.eq(String(win.sim.result.get("winnerPlayerId", "")), TrainingSession.PLAYER_ID, "...and the simulation's own result names the player as the winner")
	win.stop()


## Objectives that need a real parry / counter timing are checked here against synthetic simulation events: this proves the tracker's
## BOOKKEEPING (what counts, what resets) while the event stream itself is the real one in the tests above.
static func _synthetic_events(h) -> void:
	h.begin("training: tracker bookkeeping on injected events (parry, counter, punish, combo breaks)")
	var sim := CombatSimulation.new()
	var request := FighterRoster.build_request("p", "p", "w", "syn-1", 3, 0)
	sim.start(request, {})
	var lesson := _lesson({"id": "t_syn", "objectives": [
			{"id": "parry", "type": "parry_n", "text": "p", "count": 2},
			{"id": "counter", "type": "counter_after", "text": "c", "after": "parry", "count": 1, "window_ticks": 90},
			{"id": "combo", "type": "combo", "text": "k", "count": 3}]})
	var tracker := ObjectiveTracker.new(sim, TrainingSession.PLAYER_ID, lesson)
	var failed_combos: Array = []
	tracker.combo_failed.connect(func(n): failed_combos.append(n))
	var ev := func(type: String, actor: String, target: String, tick: int):
		sim.server_tick = tick
		sim.event_emitted.emit({"eventId": tick, "tick": tick, "type": type, "actorPlayerId": actor, "targetPlayerId": target, "damage": 5})
	var P := TrainingSession.PLAYER_ID
	var O := TrainingSession.OPPONENT_ID
	ev.call("hit", P, O, 100)
	ev.call("hit", P, O, 140)
	h.eq(tracker.combo, 2, "two hits 40 ticks apart chain")
	ev.call("hit", P, O, 300)
	h.eq(tracker.combo, 1, "a hit after a long pause starts a new chain")
	ev.call("hit", O, P, 310)
	h.eq(tracker.combo, 0, "being hit breaks the chain")
	ev.call("hit", P, O, 400)
	ev.call("hit", P, O, 440)
	ev.call("hit", P, O, 480)
	h.check(tracker.objective_state("combo")["done"], "three chained hits complete a combo objective")
	ev.call("parry", O, P, 500)
	ev.call("hit", P, O, 530)
	h.check(tracker.objective_state("counter")["done"], "a hit within the window after a parry counts as a counter")
	ev.call("parry", P, O, 600)
	h.eq(int(tracker.stats["parries"]), 1, "being parried is not a parry of your own")
	ev.call("parry", O, P, 700)
	h.check(tracker.objective_state("parry")["done"], "two parries complete the parry objective")
	h.check(failed_combos.size() >= 1, "the combo_failed signal fired when chains were broken (%s)" % str(failed_combos))
	sim.stop()
	sim.free()


static func _rating(h) -> void:
	h.begin("training: completion ratings from the lesson thresholds")
	var lesson := {"rating": {"silver": {"max_seconds": 30, "max_hits_taken": 2}, "gold": {"max_seconds": 15, "max_hits_taken": 0, "min_combo": 3}}}
	h.eq(ObjectiveTracker.rate(lesson, {"completed": false}), "", "an incomplete lesson has no rating")
	h.eq(ObjectiveTracker.rate(lesson, {"completed": true, "seconds": 60.0, "hits_taken": 5, "best_combo": 0}), "bronze", "completed slowly = bronze")
	h.eq(ObjectiveTracker.rate(lesson, {"completed": true, "seconds": 25.0, "hits_taken": 1, "best_combo": 0}), "silver", "fast enough and clean enough = silver")
	h.eq(ObjectiveTracker.rate(lesson, {"completed": true, "seconds": 10.0, "hits_taken": 0, "best_combo": 3}), "gold", "all gold criteria = gold")
	h.eq(ObjectiveTracker.rate(lesson, {"completed": true, "seconds": 10.0, "hits_taken": 0, "best_combo": 1}), "silver", "one missed gold criterion falls back to silver")
	h.eq(ObjectiveTracker.rate({}, {"completed": true}), "bronze", "a lesson without thresholds is bronze when completed")


static func _progress(h) -> void:
	h.begin("training: progress is saved, versioned, kept at the best result and tolerant of corrupt files")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP))
	var path := TMP + "/progress.cfg"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var store := ProgressStore.new(path)
	h.check(store.lessons.is_empty() and store.last_error == "", "a missing file starts empty without an error")
	store.record_attempt("b03_first_strike", false, "", 0.0)
	h.eq(store.attempts("b03_first_strike"), 1, "a failed attempt is counted")
	h.check(not store.is_completed("b03_first_strike"), "...but does not complete the lesson")
	store.record_attempt("b03_first_strike", true, "silver", 30.0)
	store.record_attempt("b03_first_strike", true, "bronze", 20.0)
	h.eq(store.best_rating("b03_first_strike"), "silver", "the best rating is kept")
	h.eq(float(store.lessons["b03_first_strike"]["best_seconds"]), 20.0, "the fastest time is kept")
	store.adaptive = false
	store.fixed_level = "hard"
	h.eq(store.save(), OK, "save succeeds")
	var again := ProgressStore.new(path)
	h.check(again.is_completed("b03_first_strike") and again.best_rating("b03_first_strike") == "silver" and again.attempts("b03_first_strike") == 3, "a reload restores completion, rating and attempts")
	h.check(not again.adaptive and again.fixed_level == "hard", "...and the difficulty settings")
	# corrupt and foreign files
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("this is [not] a config\n[[[ garbage = = = ]]")
	file.close()
	var broken := ProgressStore.new(path)
	h.check(broken.lessons.is_empty() and broken.last_error != "", "a corrupt file starts empty and reports it")
	var future := ConfigFile.new()
	future.set_value("meta", "version", 99)
	future.set_value("lesson:x", "completed", true)
	future.save(path)
	h.check(ProgressStore.new(path).lessons.is_empty(), "an unknown file version is ignored, not misread")
	var weird := ConfigFile.new()
	weird.set_value("meta", "version", ProgressStore.VERSION)
	weird.set_value("settings", "fixed_level", "godlike")
	weird.set_value("lesson:y", "best_rating", "platinum")
	weird.set_value("lesson:y", "attempts", -5)
	weird.save(path)
	var cleaned := ProgressStore.new(path)
	h.check(cleaned.fixed_level == "normal" and cleaned.best_rating("y") == "" and cleaned.attempts("y") == 0, "invalid stored values fall back to safe defaults")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func _unlocks(h) -> void:
	h.begin("training: unlock rules")
	var catalog := LessonCatalog.load_all()
	var store := ProgressStore.new(TMP + "/none.cfg", false)
	h.check(catalog.is_unlocked("b01_movement", store), "the first lesson is unlocked from the start")
	h.check(not catalog.is_unlocked("b02_camera", store), "an unavailable lesson never unlocks")
	h.check(not catalog.is_unlocked("b08_first_combo", store) or catalog.get_lesson("b08_first_combo").has("requires") == false, "later lessons are locked by default")
	h.check(not catalog.is_unlocked("i01_long_combo", store), "an intermediate lesson is locked until its prerequisite is done")
	store.record_attempt("b08_first_combo", true, "bronze", 20.0)
	h.check(catalog.is_unlocked("i01_long_combo", store), "completing the prerequisite unlocks it")
	h.check(not catalog.is_unlocked("e01_hard_duel", store), "expert lessons stay locked behind advanced ones")
	h.eq(catalog.next_after("b01_movement"), "b03_first_strike", "next_after skips unavailable lessons")


static func _free_practice(h) -> void:
	h.begin("training: free practice builds a valid, objective-free lesson")
	var lesson := FreePractice.make({"player_role": "n", "opponent_role": "q", "behaviour": "attack_only", "difficulty": "hard"})
	h.check(lesson["player_role"] == "n" and lesson["opponent_role"] == "q" and lesson["behaviour"] == "attack_only" and lesson["difficulty"] == "hard", "the chosen setup is kept")
	h.check(lesson["objectives"].is_empty() and bool(lesson["free_practice"]), "no objectives, flagged as free practice")
	var junk := FreePractice.make({"player_role": "zz", "behaviour": "dance", "difficulty": "nightmare"})
	h.check(junk["player_role"] == "p" and junk["behaviour"] == "idle" and junk["difficulty"] == "normal", "invalid choices fall back to safe values")
