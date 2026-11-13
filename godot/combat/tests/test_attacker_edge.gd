extends RefCounted
## The attacker's advantage (BALANCE.md "Attacker advantage"): a data table of damage multipliers per attacker/defender pairing that
## boosts the WEAKER side, so that whoever attacks wins more often than not in every matchup (a Pawn attacking a Queen has a real
## chance) without anybody's damage being reduced. Tests: the shipped table and its validation, how the simulation picks it up, the
## damage arithmetic, and a deterministic bot gate (fixed seeds) that fails when a later change to attacks, stats or AI quietly
## breaks the calibration (then re-run tools/edge_calibrate.gd). Calibration/verification: tools/edge_calibrate.gd, attacker_matrix.gd.

const Balance := preload("res://combat/data/balance_data.gd")
const Duel := preload("res://combat/tools/attacker_duel.gd")
const ROLES := ["p", "n", "b", "r", "q"]
## Representative pairings for the bot gate: the weakest attacker into the strongest defenders, strong attackers into weak
## defenders, and mirrors. Fixed seeds make the result deterministic for a given tuning.
const GATE_PAIRS := ["pq", "pn", "bq", "bn", "rq", "qp", "np", "pp", "qq", "rr"]
const GATE_N := 24
const GATE_SEED := 31000
const GATE_MIN_ATTACKER_RATE := 0.55   # over all gate duels (casual bot); the calibration target is 0.62 averaged over a casual and a skilled bot
const GATE_MIN_PAIR_RATE := 0.35       # no single gate pairing may leave the attacker as a clear underdog (n = 24 is noisy per pairing)


static func run(h, tree: SceneTree) -> void:
	_data(h)
	_stamina(h)
	await _simulation(h, tree)
	await _damage(h, tree)
	await _gate(h, tree)


static func _start(tree: SceneTree, attacker_role: String, defender_role: String, options: Dictionary) -> CombatSimulation:
	var sim := CombatSimulation.new()
	tree.root.add_child(sim)
	var request := FighterRoster.build_request(attacker_role, defender_role, "w", "edge-1", 7, 0)
	var start_options := {"allow_experimental_roles": true}
	start_options.merge(options, true)
	var reply: Dictionary = sim.start(request, start_options)
	assert(reply["ok"], "start failed: %s" % str(reply))
	await tree.physics_frame
	return sim


static func _dispose(sim: CombatSimulation) -> void:
	sim.stop()
	sim.get_parent().remove_child(sim)
	sim.queue_free()


# ---- the data --------------------------------------------------------------------------------------------------------------
static func _data(h) -> void:
	h.begin("attacker edge data: all 25 pairings, only the weaker side boosted, nobody nerfed, the King neutral")
	var table: Dictionary = Balance.snapshot().get("attacker_edge", {})
	h.check(not table.is_empty(), "the shipped balance data has an attacker_edge table")
	h.eq(table.get("pairs", {}).size(), 25, "one entry for each of the 25 pairings of Pawn, Knight, Bishop, Rook and Queen")
	var boosted_attackers := 0
	var boosted_defenders := 0
	for a in ROLES:
		for d in ROLES:
			var pair := Balance.attacker_edge(a, d)
			h.check(pair.size() == 2 and pair[0] >= 1.0 and pair[1] >= 1.0 and pair[0] <= 8.0 and pair[1] <= 8.0, "%s attacks %s: multipliers within 1..8 %s" % [a, d, str(pair)])
			h.check(pair[0] <= 1.0001 or pair[1] <= 1.0001, "%s attacks %s: at most one side is boosted %s" % [a, d, str(pair)])
			if pair[0] > 1.0001:
				boosted_attackers += 1
			if pair[1] > 1.0001:
				boosted_defenders += 1
	h.check(boosted_attackers > 0 and boosted_defenders > 0, "weak attackers are boosted (%d pairings) and so are weak defenders against strong attackers (%d)" % [boosted_attackers, boosted_defenders])
	for key in ["kq", "qk", "kk", "pk", "kp"]:
		h.eq(Balance.attacker_edge(key.substr(0, 1), key.substr(1, 1)), [1.0, 1.0], "%s: the King is neutral (King's last stand keeps its own balance)" % key)
	h.eq(Balance.attacker_edge("x", "y"), [1.0, 1.0], "an unknown pairing is neutral")
	var rule := Balance.stamina_edge()
	h.check(rule["attacker_cost"] >= 0.0 and rule["attacker_cost"] <= 1.0, "the attacker's stamina cost multiplier is within 0..1 (%s)" % str(rule["attacker_cost"]))
	h.check(rule["defender_cost"] >= 1.0 and rule["defender_cost"] <= 4.0, "the defender's stamina cost multiplier is within 1..4 (%s)" % str(rule["defender_cost"]))
	h.check(rule["defender_regen"] >= 0.1 and rule["defender_regen"] <= 1.0, "the defender's regeneration multiplier is within 0.1..1 (%s)" % str(rule["defender_regen"]))
	h.check(rule["attacker_cost"] <= rule["defender_cost"], "the stamina rule never favours the defender (it ships neutral: 1.0 / 1.0 / 1.0; see BALANCE.md for why)")

	h.begin("attacker edge data: invalid tables are refused; a valid override works and changes the tuning stamp")
	var stamp := Balance.stamp()
	var invalid := [
		{"pairs": {"pq": [2.0, 2.0]}},   # both sides boosted
		{"pairs": {"kq": [2.0, 1.0]}},   # the King is not in the table
		{"pairs": {"pq": [0.5, 1.0]}},   # nerfing is not allowed
		{"pairs": {"pq": [9.0, 1.0]}},   # beyond 8x
		{"pairs": {"pzz": [2.0, 1.0]}},  # not a pairing
		{"pairs": {"pq": [2.0]}},        # not a pair of numbers
		{"stamina": {"attacker_cost": 2.0}},    # the attacker's costs may only go down
		{"stamina": {"defender_cost": 0.5}},    # the defender's costs may only go up
		{"stamina": {"defender_cost": 9.0}},
		{"stamina": {"defender_regen": 0.0}},   # a defender that never recovers is not a duel
		{"stamina": "unlimited"},
		"not an object",
	]
	for patch in invalid:
		var errors := Balance.apply_override({"attacker_edge": patch})
		h.check(not errors.is_empty() and not Balance.is_overridden(), "refused and nothing installed: %s" % str(patch))
	var ok := Balance.apply_override({"attacker_edge": {"pairs": {"pq": [2.5, 1.0]}}})
	h.check(ok.is_empty(), "a valid override installs (%s)" % str(ok))
	h.eq(Balance.attacker_edge("p", "q"), [2.5, 1.0], "the override is served")
	h.check(Balance.stamp() != stamp, "the tuning stamp changes, so a client and server with different tables can tell")
	Balance.clear_override()
	h.eq(Balance.stamp(), stamp, "clearing the override restores the shipped stamp")


# ---- the stamina rule on the component ---------------------------------------------------------------------------------------
static func _stamina(h) -> void:
	h.begin("attacker edge stamina: the cost multiplier scales every cost; 0 is unlimited and can never exhaust; regeneration scales for the seat")
	var free := StaminaComponent.new()
	free.setup(100.0, 0.4, 0)
	free.cost_multiplier = 0.0
	h.check(free.spend(60.0) and free.current == 100.0, "multiplier 0: an action costs nothing")
	free.drain(50.0)
	free.lose(500.0)
	h.check(free.current == 100.0 and not free.exhausted and free.can_afford(1000.0), "multiplier 0: sprinting and blocking cost nothing, no cost is unaffordable, never exhausted")
	var costly := StaminaComponent.new()
	costly.setup(100.0, 0.4, 0)
	costly.cost_multiplier = 2.0
	h.check(costly.spend(30.0) and is_equal_approx(costly.current, 40.0), "multiplier 2: a 30-cost action takes 60")
	h.check(not costly.can_afford(25.0) and not costly.spend(25.0) and is_equal_approx(costly.current, 40.0), "multiplier 2: a 25-cost action needs 50, which is not there (and a refused spend changes nothing)")
	costly.drain(5.0)
	h.check(is_equal_approx(costly.current, 30.0), "multiplier 2: sprint drain 5 takes 10")
	var shortfall := costly.lose(20.0)
	h.check(is_equal_approx(shortfall, 10.0) and costly.current == 0.0 and costly.exhausted, "multiplier 2: absorbing a 20-cost blow needs 40, leaves a shortfall of 10 and exhausts")
	var slow := StaminaComponent.new()
	slow.setup(100.0, 1.0, 0)
	slow.current = 0.0
	slow.seat_regen = 0.5
	slow.tick(true)
	h.check(is_equal_approx(slow.current, 0.5), "seat regeneration 0.5: half the regeneration per tick")
	slow.regen_multiplier = 2.0
	slow.tick(true)
	h.check(is_equal_approx(slow.current, 1.5), "an ability's regeneration multiplier still applies on top of the seat's")
	var neutral := StaminaComponent.new()
	neutral.setup(100.0, 0.4, 0)
	h.check(neutral.spend(30.0) and is_equal_approx(neutral.current, 70.0), "the default multiplier is 1: behaviour is unchanged")


# ---- how the simulation picks it up ---------------------------------------------------------------------------------------
static func _simulation(h, tree: SceneTree) -> void:
	h.begin("attacker edge simulation: data by default, off on request, explicit for tools, the King always neutral")
	var shipped := Balance.attacker_edge("p", "q")
	var sim := await _start(tree, "p", "q", {})
	h.check(is_equal_approx(sim.edge_attacker, shipped[0]) and is_equal_approx(sim.edge_defender, shipped[1]), "Pawn attacks Queen: the table's %s is used by default (%.2f / %.2f)" % [str(shipped), sim.edge_attacker, sim.edge_defender])
	_dispose(sim)
	sim = await _start(tree, "p", "q", {"attacker_edge": false})
	h.check(sim.edge_attacker == 1.0 and sim.edge_defender == 1.0, "attacker_edge: false = raw frame data")
	_dispose(sim)
	sim = await _start(tree, "p", "q", {"attacker_edge": {"attacker": 2.0, "defender": 1.5}})
	h.check(sim.edge_attacker == 2.0 and sim.edge_defender == 1.5, "an explicit pair is used as given")
	_dispose(sim)
	for roles in [["k", "q"], ["q", "k"]]:
		sim = await _start(tree, roles[0], roles[1], {"attacker_edge": {"attacker": 3.0, "defender": 3.0}})
		h.check(sim.edge_attacker == 1.0 and sim.edge_defender == 1.0, "%s attacks %s: a King on either side is neutral even when asked for more" % roles)
		_dispose(sim)
	var rule := Balance.stamina_edge()
	sim = await _start(tree, "n", "b", {})
	h.check(is_equal_approx(sim.attacker().stamina.cost_multiplier, rule["attacker_cost"]) and is_equal_approx(sim.defender().stamina.cost_multiplier, rule["defender_cost"]) and is_equal_approx(sim.defender().stamina.seat_regen, rule["defender_regen"]) and sim.attacker().stamina.seat_regen == 1.0, "the stamina rule from the data: attacker cost %s, defender cost %s, defender regeneration %s" % [str(rule["attacker_cost"]), str(rule["defender_cost"]), str(rule["defender_regen"])])
	_dispose(sim)
	sim = await _start(tree, "n", "b", {"attacker_edge": false})
	h.check(sim.attacker().stamina.cost_multiplier == 1.0 and sim.defender().stamina.cost_multiplier == 1.0 and sim.defender().stamina.seat_regen == 1.0, "attacker_edge: false also switches the stamina rule off")
	_dispose(sim)
	sim = await _start(tree, "n", "b", {"attacker_edge": {"attacker": 1.0, "defender": 1.0}, "stamina_edge": {"attacker_cost": 0.0, "defender_cost": 3.0, "defender_regen": 0.5}})
	h.check(sim.attacker().stamina.cost_multiplier == 0.0 and sim.defender().stamina.cost_multiplier == 3.0 and sim.defender().stamina.seat_regen == 0.5, "an explicit stamina rule is used as given (sweeps)")
	_dispose(sim)
	sim = await _start(tree, "n", "b", {"stamina_edge": false})
	h.check(sim.attacker().stamina.cost_multiplier == 1.0 and sim.defender().stamina.cost_multiplier == 1.0, "stamina_edge: false switches only the stamina rule off (the damage multipliers stay)")
	_dispose(sim)
	sim = await _start(tree, "k", "q", {"stamina_edge": {"attacker_cost": 0.0, "defender_cost": 3.0, "defender_regen": 0.5}})
	h.check(sim.attacker().stamina.cost_multiplier == 1.0 and sim.defender().stamina.cost_multiplier == 1.0, "a King on either side: the stamina rule is neutral too")
	_dispose(sim)
	# A second duel on the same simulation object starts clean.
	sim = await _start(tree, "p", "q", {"attacker_edge": {"attacker": 4.0, "defender": 1.0}})
	sim.stop()
	var request := FighterRoster.build_request("n", "n", "w", "edge-2", 7, 0)
	h.check(sim.start(request, {"attacker_edge": false})["ok"] and sim.edge_attacker == 1.0, "a new duel on the same simulation does not inherit the previous advantage")
	_dispose(sim)


# ---- the arithmetic ---------------------------------------------------------------------------------------------------------
static func _damage(h, tree: SceneTree) -> void:
	h.begin("attacker edge damage: the multiplier scales each side's blows, before armour, rounding to whole HP")
	var light: AttackDefinition = Balance.attack_tables("p")["light"][0]
	for case in [[{"attacker": 2.0, "defender": 1.0}, 20, 10], [{"attacker": 1.0, "defender": 3.0}, 10, 30], [{"attacker": 1.5, "defender": 1.0}, 15, 10], [{"attacker": 1.0, "defender": 1.0}, 10, 10]]:
		var sim := await _start(tree, "p", "p", {"attacker_edge": case[0]})
		var attacker := sim.attacker()
		var defender := sim.defender()
		var defender_before := defender.health.current
		sim._apply_hit(attacker, defender, light, 10)
		h.eq(defender_before - defender.health.current, case[1], "%s: the attacker's 10-damage blow deals %d" % [str(case[0]), case[1]])
		var attacker_before := attacker.health.current
		sim._apply_hit(defender, attacker, light, 10)
		h.eq(attacker_before - attacker.health.current, case[2], "%s: the defender's 10-damage blow deals %d" % [str(case[0]), case[2]])
		_dispose(sim)
	# Armour is applied after the multiplier: a Rook (25% armour) takes 0.75 x (10 x 2).
	var rook_sim := await _start(tree, "p", "r", {"attacker_edge": {"attacker": 2.0, "defender": 1.0}})
	var rook := rook_sim.defender()
	var rook_before := rook.health.current
	rook_sim._apply_hit(rook_sim.attacker(), rook, light, 10)
	h.eq(rook_before - rook.health.current, roundi(20.0 * (1.0 - float(rook.profile["armor"]))), "armour reduces the boosted blow, not the base blow")
	_dispose(rook_sim)


# ---- the bot gate -------------------------------------------------------------------------------------------------------------
static func _gate(h, tree: SceneTree) -> void:
	h.begin("attacker edge gate: with the shipped table the attacker wins more often than not (casual bot, fixed seeds)")
	var cfg := {"style": "balanced", "skill": 0.6}
	var wins := 0
	var total := 0
	var worst := 1.0
	var worst_pair := ""
	var timeouts := 0
	for key in GATE_PAIRS:
		var s: Dictionary = await Duel.series(tree, key.substr(0, 1), key.substr(1, 1), cfg, GATE_N, GATE_SEED)
		wins += int(s["wins"])
		total += int(s["n"])
		timeouts += int(s["timeouts"])
		var rate := float(s["wins"]) / float(s["n"])
		if rate < worst:
			worst = rate
			worst_pair = key
	var overall := float(wins) / float(total)
	h.check(overall >= GATE_MIN_ATTACKER_RATE, "the attacker wins %.0f%% of %d duels over the gate pairings (needs >= %.0f%%)" % [100.0 * overall, total, 100.0 * GATE_MIN_ATTACKER_RATE])
	h.check(worst >= GATE_MIN_PAIR_RATE, "the weakest gate pairing (%s attacks %s) still gives the attacker %.0f%% (needs >= %.0f%%)" % [worst_pair.substr(0, 1), worst_pair.substr(1, 1), 100.0 * worst, 100.0 * GATE_MIN_PAIR_RATE])
	h.eq(timeouts, 0, "no gate duel timed out")
