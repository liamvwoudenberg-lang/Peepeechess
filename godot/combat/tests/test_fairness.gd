extends RefCounted
## Fairness pass (BALANCE.md "Fairness pass"): the defender's edge, the cost of a failed attack, Resolve (gain, second wind, overcharge,
## extra dodge), per-seat start modifiers, raw-frame-data neutrality, and the board layer (chess/battle_meta.gd): persistent wounds,
## healing, support / isolation, key squares, comeback, decisive-win initiative, and a BattleMetaMatch duel round trip.

const Balance := preload("res://combat/data/balance_data.gd")
const Support := preload("res://combat/tests/test_support.gd")
const Meta := preload("res://chess/battle_meta.gd")
const MetaMatch := preload("res://chess/battle_meta_match.gd")
const ChessEngine := preload("res://chess/chess_engine.gd")


static func run(h, tree: SceneTree) -> void:
	_data(h)
	await _defender_edge(h, tree)
	await _failed_attack_and_resolve(h, tree)
	await _seat_start(h, tree)
	await _neutral_when_raw(h, tree)
	_meta_rules(h)
	await _match_round_trip(h, tree)


static func _data(h) -> void:
	h.begin("fairness data: every number lives in balance_v1.json (duel_rules, meta) and is sane")
	var rules := Balance.duel_rules()
	h.check(float(rules["defender"]["take_mult"]) < 1.0 and float(rules["defender"]["take_mult"]) >= 0.8, "the defender takes slightly less damage (x%.2f, 0.8..1.0)" % float(rules["defender"]["take_mult"]))
	h.check(int(rules["defender"]["head_start_ticks"]) > 0 and int(rules["defender"]["head_start_ticks"]) <= 60, "the defender strikes first for %d ticks (1..60)" % int(rules["defender"]["head_start_ticks"]))
	h.check(float(rules["failed_attack"]["whiff_stamina"]) > 0.0 and float(rules["failed_attack"]["attacker_seat_mult"]) >= 1.0, "a failed attack costs stamina, the duel's attacker at least as much")
	h.check(float(rules["resolve"]["second_wind"]["cost"]) < float(rules["resolve"]["max"]) and float(rules["resolve"]["overcharge"]["cost"]) <= float(rules["resolve"]["max"]), "every Resolve spend is affordable from a full pool")
	var meta := Balance.meta()
	h.check(float(meta["persistence"]["min_start_hp_frac"]) > 0.0, "wounded pieces keep a floor of HP (%.0f%%)" % (100.0 * float(meta["persistence"]["min_start_hp_frac"])))
	h.check(float(meta["support"]["defended_take_mult"]) < 1.0 and float(meta["support"]["isolated_take_mult"]) > 1.0, "defended pieces take less, isolated pieces more")
	h.check(Balance.stamp().begins_with("balance-v1:"), "the tuning stamp covers the new sections")


static func _start(tree: SceneTree, options: Dictionary = {}, attacker: String = "p", defender: String = "n"):
	var rig = await Support.make_rig(tree, attacker, defender, "w", 0, "fair-1", options)
	rig.to_live()
	return rig


static func _defender_edge(h, tree: SceneTree) -> void:
	h.begin("defender's edge: sturdier, quicker recovery, and the attacker cannot start an action during the head start")
	var rig = await _start(tree, {})
	var sim: CombatSimulation = rig.sim
	h.check(sim.rules_on, "the rules are on by default")
	h.near(rig.black().take_mult, float(Balance.duel_rules()["defender"]["take_mult"]), 1e-6, "the defender's damage-taken multiplier comes from the data")
	h.near(rig.white().take_mult, 1.0, 1e-6, "the attacker has no damage-taken bonus")
	h.near(rig.black().stamina.seat_regen, float(Balance.duel_rules()["defender"]["regen_mult"]), 1e-6, "the defender recovers stamina faster")
	rig.face_off(1.2)
	rig.w.press("light")
	rig.tick(1)
	h.check(rig.white().sm.state != CombatConstants.State.ATTACKING, "the attacker's swing is refused inside the head start")
	rig.tick(sim.head_start_ticks + 2)
	rig.w.press("light")
	rig.tick(2)
	h.check(rig.white().sm.state == CombatConstants.State.ATTACKING, "after the head start the attacker can swing")
	rig.dispose()


static func _failed_attack_and_resolve(h, tree: SceneTree) -> void:
	h.begin("a failed attack costs the attacker; a parry / dodge pays the defender in Resolve; Resolve buys a dodge, a heal and a ready ability")
	var rig = await _start(tree, {}, "q", "n")
	var sim: CombatSimulation = rig.sim
	var attacker: FighterController = rig.white()
	var defender: FighterController = rig.black()
	rig.tick(sim.head_start_ticks + 2)
	# whiff: swing at nothing -> the queued whiff event drains stamina beyond the swing's own cost
	rig.place(Vector3(-5, 0, 0), Vector3(5, 0, 0))
	var before := attacker.stamina.current
	rig.w.press("light")
	rig.tick(80)
	h.check(attacker.whiffs >= 1, "a swing that touches nobody is counted as a whiff")
	h.check(before - attacker.stamina.current >= float(Balance.duel_rules()["failed_attack"]["whiff_stamina"]), "the whiff cost the attacker stamina (%.1f)" % (before - attacker.stamina.current))
	# Resolve rules on the fighter directly (the arithmetic; the bots cover the live use)
	defender.resolve = 100.0
	defender.resolve_max = 100.0
	defender.stamina.current = 0.0
	defender.stamina.exhausted = true
	h.check(defender.try_resolve_dodge(), "an exhausted fighter can pay a dodge with Resolve")
	h.near(defender.resolve, 100.0 - float(Balance.duel_rules()["resolve"]["dodge_cost"]), 1e-6, "the dodge cost the data's Resolve")
	defender.health.current = int(defender.health.maximum * 0.4)
	defender.resolve = 100.0
	h.eq(defender.resolve_special(), "second_wind", "wounded with Resolve: the ability button on cooldown means second wind")
	defender.health.current = defender.health.maximum
	h.eq(defender.resolve_special(), "overcharge", "healthy with Resolve: it means overcharge (ability ready again)")
	defender.resolve = 5.0
	h.eq(defender.resolve_special(), "", "without Resolve it does nothing")
	rig.dispose()

	var rig2 = await _start(tree, {}, "p", "n")
	var fighter: FighterController = rig2.black()
	rig2.tick(rig2.sim.head_start_ticks + 2)
	fighter.health.current = int(fighter.health.maximum * 0.3)
	fighter.resolve = 100.0
	fighter.resolve_max = 100.0
	fighter.ability.cooldown_remaining = 600
	var low := fighter.health.current
	rig2.b.press("ability")
	rig2.tick(int(Balance.duel_rules()["resolve"]["second_wind"]["cast_ticks"]) + 6)
	h.check(fighter.health.current > low, "second wind heals when the cast is not broken (%d -> %d)" % [low, fighter.health.current])
	h.eq(fighter.second_winds, 1, "and is counted")
	h.near(fighter.resolve, 100.0 - float(Balance.duel_rules()["resolve"]["second_wind"]["cost"]), 1e-6, "for the data's Resolve cost")
	rig2.dispose()


static func _seat_start(h, tree: SceneTree) -> void:
	h.begin("seat_start option: persistent HP, carried Resolve and support modifiers reach the right seat")
	var rig = await _start(tree, {"seat_start": {"attacker": {"hp": 30, "resolve": 50.0, "take_mult": 0.9}, "defender": {"hp": 70, "regen_mult": 1.1}}}, "n", "n")
	h.eq(rig.white().health.current, 30, "the attacker starts wounded")
	h.eq(rig.black().health.current, 70, "the defender starts at its persisted HP")
	h.near(rig.white().resolve, 50.0, 1e-6, "Resolve carried into the duel")
	h.near(rig.white().take_mult, 0.9, 1e-6, "support multiplier applied to the attacker")
	h.near(rig.black().take_mult, float(Balance.duel_rules()["defender"]["take_mult"]), 1e-6, "defender keeps its edge")
	rig.dispose()


static func _neutral_when_raw(h, tree: SceneTree) -> void:
	h.begin("raw frame data (attacker_edge:false) and King pairings stay neutral: no head start, no multipliers, no Resolve")
	var rig = await _start(tree, {"attacker_edge": false})
	h.check(not rig.sim.rules_on and rig.sim.head_start_ticks == 0, "rules off")
	h.near(rig.black().take_mult, 1.0, 1e-9, "no defender bonus")
	h.near(rig.white().resolve, 0.0, 1e-9, "no Resolve")
	rig.dispose()


static func _board(fen: String):
	var engine := ChessEngine.new()
	engine.load_fen(fen)
	return engine


static func _meta_rules(h) -> void:
	h.begin("board layer: wounds persist with a floor, heal each turn (faster on the rest ranks), support / isolation / flanking / centre / comeback")
	var meta := Meta.new()
	meta.reset()
	var cfg := Balance.meta()
	meta.hp["w-n-b1"] = 0.1
	h.near(meta.start_fraction("w-n-b1"), float(cfg["persistence"]["min_start_hp_frac"]), 1e-9, "a nearly dead piece still starts with the floor")
	h.eq(meta.start_hp("w-n-b1", 125), roundi(float(cfg["persistence"]["min_start_hp_frac"]) * 125.0), "start HP is the fraction of the contract maxHp")
	var engine = _board("4k3/8/8/8/8/8/8/N3K3 w - - 0 1")   # white knight a1 (rest rank), white king e1, black king e8
	var registry := {0: "w-n-a1"}
	meta.hp["w-n-a1"] = 0.5
	meta.after_move(engine, registry, "w")
	var expected := 0.5 + float(cfg["healing"]["per_turn_frac"]) + float(cfg["healing"]["rest_frac"])
	h.near(float(meta.hp["w-n-a1"]), expected, 1e-9, "a wounded piece on its rest ranks heals per-turn + rest (%.2f)" % expected)
	var spared := Meta.new()
	spared.reset()
	spared.hp["w-n-a1"] = 0.5
	spared.after_move(engine, registry, "w", "w-n-a1")
	h.near(float(spared.hp["w-n-a1"]), 0.5, 1e-9, "the piece that just fought does not heal that turn")
	var lonely = _board("4k3/8/8/3p4/8/8/8/4K3 w - - 0 1")
	h.check(meta.isolated(lonely, ChessEngine.index("d5"), "b"), "a lone pawn is isolated")
	var guarded = _board("4k3/8/2p5/3p4/8/8/8/4K3 w - - 0 1")
	h.check(not meta.isolated(guarded, ChessEngine.index("d5"), "b") and meta.defended(guarded, ChessEngine.index("d5"), "b"), "a pawn with a friend behind is neither isolated nor undefended")
	var flank = _board("4k3/8/8/2PpP3/8/8/8/4K3 w - - 0 1")
	h.check(meta.flanked(flank, ChessEngine.index("d5"), "b"), "enemies on both sides flank a piece")
	var centre = _board("4k3/8/8/8/3PP3/2N2N2/8/4K3 w - - 0 1")
	h.check(meta.key_control(centre, "w") >= int(cfg["key_squares"]["control_needed"]), "a held centre counts as key-square control (%d)" % meta.key_control(centre, "w"))
	var behind = _board("4k3/pppppppp/8/8/8/8/8/4K3 w - - 0 1")
	h.check(meta.is_behind(behind.board, "w") and not meta.is_behind(behind.board, "b"), "the side down material is behind (comeback applies)")


static func _match_round_trip(h, tree: SceneTree) -> void:
	h.begin("BattleMetaMatch: a wounded piece enters the next duel wounded, and the validator accepts the persisted start HP")
	var game = MetaMatch.new()
	game.new_game()
	for step in [["e2", "e4"], ["d7", "d5"]]:
		var r: Dictionary = game.play(step[0], step[1])
		h.check(r.ok, "%s-%s is legal" % [step[0], step[1]])
	var wounded_id: String = game.registry[ChessEngine.index("e4")]
	game.meta.hp[wounded_id] = 0.5
	var capture: Dictionary = game.play("e4", "d5")
	h.check(capture.ok and game.phase == "combat", "the capture starts a duel")
	var request: Dictionary = game.pending_request()
	h.eq(int(game._combat.fighters[0].hp if game._combat.fighters[0].pieceId == wounded_id else game._combat.fighters[1].hp), roundi(0.5 * float(request.attacker.stats.maxHp)), "the snapshot starts at the persisted HP")
	var options: Dictionary = game.combat_options()
	h.eq(int(options["seat_start"]["attacker"]["hp"]), roundi(0.5 * float(request.attacker.stats.maxHp)), "and so does the combat authority's start option")
	h.check(float(options["seat_start"]["defender"]["resolve"]) <= float(Balance.meta()["resolve"]["carry_cap"]), "carried Resolve is capped")
	var sim := CombatSimulation.new()
	tree.root.add_child(sim)
	var started: Dictionary = sim.start(request, options)
	h.check(started["ok"], "the simulation accepts the options")
	await tree.physics_frame
	h.eq(sim.attacker().health.current, int(options["seat_start"]["attacker"]["hp"]), "the simulation's attacker starts at that HP")
	sim.stop()
	sim.get_parent().remove_child(sim)
	sim.queue_free()
	game.cancel_pending()
