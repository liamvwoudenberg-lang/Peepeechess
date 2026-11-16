extends RefCounted
## AI difficulty (combat/ai/ai_difficulty.gd, adaptive_difficulty.gd): presets are behaviour-only parameter sets, the default AI is
## unchanged, the AI cannot read the human's input of the same tick, the levels really get stronger (fixed-seed bot duels), the
## adaptive controller moves gradually and the fixed behaviours (idle, passive block, attack only) do what they say.

const Levels := preload("res://combat/tools/ai_levels.gd")
const S := CombatConstants.State


static func run(h, tree: SceneTree) -> void:
	_presets(h)
	await _neutral_and_determinism(h, tree)
	await _no_future_input(h, tree)
	_adaptive(h)
	await _behaviours(h, tree)
	await _ordering(h, tree)


static func _presets(h) -> void:
	h.begin("ai difficulty: four behaviour-only presets")
	h.eq(AIDifficulty.LEVELS, ["easy", "normal", "hard", "expert"], "the four levels")
	var banned := ["damage", "hp", "health", "stamina", "speed", "multiplier", "mult"]
	for level in AIDifficulty.LEVELS:
		var cfg := AIDifficulty.config(level)
		for key in cfg["params"]:
			h.check(CombatAI.NEUTRAL.has(key), "%s: parameter %s is a real CombatAI behaviour key" % [level, key])
			h.check(not banned.any(func(b): return String(key).contains(b)), "%s: %s is not a damage / health / stat multiplier" % [level, key])
		h.check(CombatAI.STYLE_NAMES.has(cfg["style"]) and float(cfg["skill"]) >= 0.0 and float(cfg["skill"]) <= 1.0, "%s: valid style and skill" % level)
		h.check(AIDifficulty.summary(level) != "" and AIDifficulty.label(level) != "", "%s: has a label and summary" % level)
	var skills: Array = AIDifficulty.LEVELS.map(func(l): return float(AIDifficulty.config(l)["skill"]))
	h.check(skills[0] < skills[1] and skills[1] < skills[2] and skills[2] < skills[3], "skill rises with the level (%s)" % str(skills))
	var errors: Array = AIDifficulty.LEVELS.map(func(l): return float(AIDifficulty.config(l)["params"].get("error_rate", 0.0)))
	h.check(errors[0] > errors[1] and errors[1] > errors[2] and errors[2] >= errors[3] and errors[3] == 0.0, "error rate falls with the level (%s)" % str(errors))
	var delays: Array = AIDifficulty.LEVELS.map(func(l): return int(AIDifficulty.config(l)["params"].get("react_extra", 0)))
	h.check(delays[0] > delays[1] and delays[1] > delays[2] and delays[2] >= delays[3], "extra reaction delay falls with the level (%s)" % str(delays))
	h.eq(AIDifficulty.level_index("EXPERT"), 3, "level names are case-insensitive")
	h.eq(AIDifficulty.level_index("nonsense"), 0, "an unknown level falls back to easy")


## Plays `ticks` ticks of an AI-vs-AI fight and returns the final snapshot JSON (and all packets' hash).
static func _play(tree: SceneTree, make_white: Callable, make_black: Callable, ticks: int, seed_value: int = 11) -> String:
	var request := FighterRoster.build_request("n", "p", "w", "ai-t-%d" % seed_value, seed_value, 0)
	var sim := CombatSimulation.new()
	tree.root.add_child(sim)
	sim.start(request, {"allow_experimental_roles": true})
	await tree.physics_frame
	var wb := CombatInputBuilder.new(request["matchId"], request["battleId"], "player-white")
	var bb := CombatInputBuilder.new(request["matchId"], request["battleId"], "player-black")
	var white: CombatAI = make_white.call(wb, FighterRoster.stats_for("n"), FighterRoster.stats_for("p"))
	var black: CombatAI = make_black.call(bb, FighterRoster.stats_for("p"), FighterRoster.stats_for("n"))
	var packets := ""
	for i in ticks:
		var snap := sim.snapshot(false)
		var pw := white.think(snap)
		var pb := black.think(snap)
		packets += "%s|%s;" % [str(pw.get("moveX", 0)) + str(pw.get("light", 0)) + str(pw.get("parry", 0)), str(pb.get("moveX", 0)) + str(pb.get("light", 0))]
		sim.submit_input(pw)
		sim.submit_input(pb)
		sim.step_tick()
	var out := JSON.stringify(sim.snapshot(false)) + packets.sha256_text()
	sim.stop()
	sim.get_parent().remove_child(sim)
	sim.queue_free()
	return out


static func _neutral_and_determinism(h, tree: SceneTree) -> void:
	h.begin("ai difficulty: the default AI is unchanged, presets are deterministic")
	var plain := func(b, my, opp): return CombatAI.new(b, my, opp, 5, 0.6, "balanced")
	var applied := func(b, my, opp):
		var ai := CombatAI.new(b, my, opp, 5, 0.6, "balanced")
		ai.apply_params({"not_a_key": 99})   # unknown keys are ignored
		ai.apply_params({})
		return ai
	var a: String = await _play(tree, plain, plain, 500)
	var b: String = await _play(tree, applied, applied, 500)
	h.eq(a, b, "neutral parameters (and ignored unknown keys) reproduce the original behaviour exactly")
	var hard := func(b2, my, opp): return AIDifficulty.make_ai("hard", b2, my, opp, 5)
	var c: String = await _play(tree, hard, hard, 500)
	var d: String = await _play(tree, hard, hard, 500)
	h.eq(c, d, "the same preset and seed play the identical fight")
	var easy := func(b2, my, opp): return AIDifficulty.make_ai("easy", b2, my, opp, 5)
	var e: String = await _play(tree, easy, easy, 500)
	h.check(e != c, "different levels play differently")


## The AI decides from the snapshot taken BEFORE this tick's inputs: the human's packet of the same tick cannot influence it. Proof: the
## same fight with the human's packet submitted before / after the AI's think() is identical.
static func _no_future_input(h, tree: SceneTree) -> void:
	h.begin("ai difficulty: the AI cannot read the human's input of the current tick")
	var results: Array = []
	for human_first in [true, false]:
		var request := FighterRoster.build_request("p", "p", "w", "ai-future", 21, 0)
		var sim := CombatSimulation.new()
		tree.root.add_child(sim)
		sim.start(request, {})
		await tree.physics_frame
		var hb := CombatInputBuilder.new(request["matchId"], request["battleId"], "player-white")
		var ab := CombatInputBuilder.new(request["matchId"], request["battleId"], "player-black")
		var ai := AIDifficulty.make_ai("expert", ab, FighterRoster.stats_for("p"), FighterRoster.stats_for("p"), 9)
		for i in 420:
			var snap := sim.snapshot(false)
			var human := hb.build(0.0, 1.0 if (i / 40) % 2 == 0 else -1.0, 0.0, true, false, false)
			if i % 25 == 0 and i > 200:
				hb.press("light")
				human = hb.build(0.0, 0.0, 0.0, true, false, false)
			var ai_packet: Dictionary
			if human_first:
				sim.submit_input(human)
				ai_packet = ai.think(snap)
			else:
				ai_packet = ai.think(snap)
				sim.submit_input(human)
			sim.submit_input(ai_packet)
			sim.step_tick()
		results.append(JSON.stringify(sim.snapshot(false)))
		sim.stop()
		sim.get_parent().remove_child(sim)
		sim.queue_free()
	h.eq(results[0], results[1], "submitting the human's packet before or after the AI decided changes nothing")
	var info := CombatAI.new(CombatInputBuilder.new("m", "b", "player-black"), FighterRoster.stats_for("p"), FighterRoster.stats_for("p"))
	var methods := info.get_method_list().filter(func(m): return m["name"] == "think")
	h.check(methods.size() == 1 and methods[0]["args"].size() == 1, "think() takes the public snapshot and nothing else")


static func _adaptive(h) -> void:
	h.begin("ai difficulty: adaptive controller moves gradually, clamps, and can be fixed")
	var ctl := AdaptiveDifficulty.new("normal")
	h.eq(ctl.level, "normal", "starts on the chosen level")
	var great := {"won": true, "hit_ratio": 0.9, "damage_taken": 0.0, "parries": 4}
	var awful := {"won": false, "hit_ratio": 0.0, "damage_taken": 1.0, "parries": 0}
	h.check(AdaptiveDifficulty.performance(great) > 0.9 and AdaptiveDifficulty.performance(awful) < 0.05, "performance spans 0..1")
	ctl.record_fight(great)
	h.eq(ctl.level, "normal", "one great fight does not change the level")
	for i in 6:
		ctl.record_fight(great)
	h.eq(ctl.level, "expert", "sustained good play raises it, one step at a time, to the cap")
	var levels_seen: Array = []
	for i in 8:
		ctl.record_fight(awful)
		levels_seen.append(ctl.level)
	var steps_ok := true
	for i in range(1, levels_seen.size()):
		if absi(AIDifficulty.level_index(levels_seen[i]) - AIDifficulty.level_index(levels_seen[i - 1])) > 1:
			steps_ok = false
	h.check(steps_ok and ctl.level == "easy", "sustained poor play lowers it gradually to the floor (%s)" % str(levels_seen))
	var fixed := AdaptiveDifficulty.fixed("hard")
	for i in 10:
		fixed.record_fight(great)
	h.eq(fixed.level, "hard", "a fixed difficulty never changes")
	var mixed := AdaptiveDifficulty.new("normal")
	for i in 12:
		mixed.record_fight(great if i % 2 == 0 else awful)
	h.eq(mixed.level, "normal", "alternating results keep the level steady")


static func _behaviours(h, tree: SceneTree) -> void:
	h.begin("ai difficulty: fixed opponent behaviours (idle, passive block, attack only)")
	var counts := {}
	for behaviour in ["idle", "passive_block", "attack_only"]:
		var lesson := {"id": "beh_" + behaviour, "title": "t", "summary": "s", "category": "beginner", "order": 1, "player_role": "p", "opponent_role": "p",
				"behaviour": behaviour, "difficulty": "easy", "objectives": [], "fail": []}
		var session := TrainingSession.new(lesson, {"seed": 4})
		await session.start(tree)
		session.skip_countdown()
		var opp := session.sim.fighter_by_id(TrainingSession.OPPONENT_ID)
		var start := opp.global_position
		var states := {}
		var attacks := 0
		var defences := 0
		for i in 600:
			session.step()
			states[opp.sm.state] = true
			if opp.sm.state == S.ATTACKING and opp.sm.state_ticks == 1:
				attacks += 1
			if opp.sm.state in [S.BLOCKING, S.PARRYING, S.DODGING]:
				defences += 1
		counts[behaviour] = {"attacks": attacks, "defences": defences, "moved": start.distance_to(opp.global_position), "states": states.keys()}
		session.stop()
	h.check(counts["idle"]["attacks"] == 0 and counts["idle"]["defences"] == 0 and counts["idle"]["moved"] < 0.3, "idle: stands still, never attacks or defends %s" % str(counts["idle"]))
	h.check(counts["passive_block"]["attacks"] == 0 and counts["passive_block"]["defences"] > 300 and counts["passive_block"]["moved"] < 0.3, "passive_block: keeps its guard up, never attacks %s" % str(counts["passive_block"]))
	h.check(counts["attack_only"]["attacks"] >= 1 and counts["attack_only"]["defences"] == 0, "attack_only: attacks and never blocks, parries or dodges %s" % str(counts["attack_only"]))


## Fixed-seed bot duels: the levels really get stronger. (Larger measurement: tools/ai_levels.gd, numbers in docs/application/TRAINING.md.)
static func _ordering(h, tree: SceneTree) -> void:
	h.begin("ai difficulty: higher levels win more often (bot-measured, fixed seeds)")
	var reference := {"style": "balanced", "skill": 0.6, "params": {}}
	var easy: float = await Levels.rate(tree, "easy", reference, "pn", 5, 5000)
	var expert: float = await Levels.rate(tree, "expert", reference, "pn", 5, 5000)
	var head_to_head: float = await Levels.rate(tree, "expert", "easy", "pn", 5, 5900)
	h.check(expert > easy, "Expert beats the reference more often than Easy does (%.0f%% vs %.0f%%)" % [expert * 100.0, easy * 100.0])
	h.check(head_to_head >= 0.7, "Expert beats Easy head-to-head (%.0f%%)" % [head_to_head * 100.0])
