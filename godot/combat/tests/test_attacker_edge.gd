extends RefCounted
## The attacker's advantage (BALANCE.md "Attacker advantage"): a data table of damage multipliers per attacker/defender pairing that
## boosts the WEAKER side, so that whoever attacks wins more often than not in every matchup (a Pawn attacking a Queen has a real
## chance) without anybody's damage being reduced. Tests: the shipped table and its validation, how the simulation picks it up, the
## damage arithmetic, and a deterministic bot gate (fixed seeds) that fails when a later change to attacks, stats or AI quietly
## breaks the calibration (then re-run tools/edge_calibrate.gd). Calibration/verification: tools/edge_calibrate.gd, attacker_matrix.gd.
## The duel-length scale (BALANCE.md "Duel length", a per-pairing multiplier on HP damage so that duels last long enough to be a fight)
## is tested here too: the carried fraction in HealthComponent, the shipped table, how the simulation picks it up, the arithmetic and a
## deterministic length gate (re-run tools/length_calibrate.gd when it fails).

const Balance := preload("res://combat/data/balance_data.gd")
const Duel := preload("res://combat/tools/attacker_duel.gd")
const ROLES := ["p", "n", "b", "r", "q"]
## Representative pairings for the bot gate: the weakest attacker into the strongest defenders, strong attackers into weak
## defenders, and mirrors. Fixed seeds make the result deterministic for a given tuning.
const GATE_PAIRS := ["pp", "nn", "bb", "rr", "qq", "qp", "qb", "nr", "bp", "rb"]   # attackers that are not hopeless underdogs
const GATE_N := 10
const GATE_SEED := 31000
const GATE_MIN_ATTACKER_RATE := 0.55   # over all gate duels (casual bot); the calibration target is 0.62 averaged over a casual and a skilled bot
const GATE_MIN_PAIR_RATE := 0.30       # no single gate pairing may leave the attacker as a clear underdog (n = 10 is noisy per pairing)
const GATE_MIN_MEDIAN_SECONDS := 10.0  # the shortest gate pairing's median fight (casual bot; the calibration target is for both bots' geometric mean)
const GATE_MAX_TIMEOUTS := 2


static func run(h, tree: SceneTree) -> void:
	_data(h)
	_stamina(h)
	await _simulation(h, tree)
	await _damage(h, tree)
	_health(h)
	_length_data(h)
	await _length_simulation(h, tree)
	await _length_damage(h, tree)
	await _gate(h, tree)
	await _queen_gate(h, tree)


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
	h.check(boosted_attackers > 0 and boosted_defenders == 0, "attackers are boosted (%d pairings) and NOBODY boosts a defender (%d): a strong piece stays strong when it attacks" % [boosted_attackers, boosted_defenders])
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
	h.begin("attacker edge damage: the multiplier scales each side's blows, before armour, rounding to whole HP (duel-length scale 1.0)")
	var light: AttackDefinition = Balance.attack_tables("p")["light"][0]
	for case in [[{"attacker": 2.0, "defender": 1.0}, 20, 10], [{"attacker": 1.0, "defender": 3.0}, 10, 30], [{"attacker": 1.5, "defender": 1.0}, 15, 10], [{"attacker": 1.0, "defender": 1.0}, 10, 10]]:
		var sim := await _start(tree, "p", "p", {"attacker_edge": case[0], "damage_scale": 1.0})
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
	var rook_sim := await _start(tree, "p", "r", {"attacker_edge": {"attacker": 2.0, "defender": 1.0}, "damage_scale": 1.0})
	var rook := rook_sim.defender()
	var rook_before := rook.health.current
	rook_sim._apply_hit(rook_sim.attacker(), rook, light, 10)
	h.eq(rook_before - rook.health.current, roundi(20.0 * (1.0 - float(rook.profile["armor"]))), "armour reduces the boosted blow, not the base blow")
	_dispose(rook_sim)


# ---- the duel-length scale ---------------------------------------------------------------------------------------------------
static func _health(h) -> void:
	h.begin("duel length health: fractional damage is carried, so the total over a fight is exact and HP stays a whole number")
	var hp := HealthComponent.new()
	hp.setup(80.0)
	h.eq(hp.apply_scaled(2.5), 2, "2.5 takes 2 off now")
	h.eq(hp.apply_scaled(2.5), 3, "the carried half makes the next 2.5 take 3 off")
	h.eq(hp.current, 75, "5.0 came off in total")
	var many := HealthComponent.new()
	many.setup(1000.0)
	var removed := 0
	for _i in 100:
		removed += many.apply_scaled(0.3)
	h.eq(removed, 30, "100 grazes of 0.3 remove exactly 30 in total")
	h.eq(many.current, 970, "and HP is a whole number that matches")
	var small := HealthComponent.new()
	small.setup(10.0)
	h.eq(small.apply_scaled(0.4), 0, "a graze below one point removes nothing yet")
	h.eq(small.current, 10, "HP is untouched until the carry adds up")
	var dying := HealthComponent.new()
	dying.setup(3.0)
	h.eq(dying.apply_scaled(10.0), 3, "never removes more than is left")
	h.check(not dying.is_alive(), "and a fighter at 0 is defeated")
	h.eq(dying.apply_scaled(5.0), 0, "a defeated fighter takes nothing more")
	var reset := HealthComponent.new()
	reset.setup(50.0)
	reset.apply_scaled(0.9)
	reset.setup(50.0)
	h.eq(reset.apply_scaled(0.9), 0, "setup() clears the carry, so a new duel starts clean")
	h.eq(reset.apply_scaled(0.0), 0, "zero damage is a no-op")
	h.eq(reset.apply_scaled(-3.0), 0, "negative damage is a no-op")


static func _length_data(h) -> void:
	h.begin("duel length data: a scale for each of the 25 pairings within range, the King and unknown pairings unscaled")
	var section: Dictionary = Balance.snapshot().get("duel_length", {})
	h.check(not section.is_empty(), "the shipped balance data has a duel_length section")
	h.eq(section.get("pairs", {}).size(), 25, "one entry for each of the 25 pairings of Pawn, Knight, Bishop, Rook and Queen")
	h.check(Balance.duel_target_seconds() > 0.0, "it records the fight length it was calibrated for (%.0f s)" % Balance.duel_target_seconds())
	var lengthened := 0
	for a in ROLES:
		for d in ROLES:
			var scale := Balance.damage_scale(a, d)
			h.check(scale >= 0.05 and scale <= 1.0, "%s attacks %s: the scale is within 0.05..1 (%.3f)" % [a, d, scale])
			if scale < 0.999:
				lengthened += 1
	h.check(lengthened >= 20, "duels are lengthened in nearly every pairing (%d of 25)" % lengthened)
	for key in ["kq", "qk", "kk", "pk", "kp"]:
		h.eq(Balance.damage_scale(key.substr(0, 1), key.substr(1, 1)), 1.0, "%s: the King is unscaled (King's last stand keeps its own balance)" % key)
	h.eq(Balance.damage_scale("x", "y"), 1.0, "an unknown pairing is unscaled")
	h.eq(Balance.damage_scale(), 1.0, "no roles given: unscaled")

	h.begin("duel length data: invalid sections are refused; a valid override works and changes the tuning stamp")
	var stamp := Balance.stamp()
	var invalid := [
		{"damage_scale": 2.0},          # the default may only lengthen a duel
		{"damage_scale": 0.0},
		{"pairs": {"pq": 0.0}},         # a duel nobody can lose
		{"pairs": {"pq": 1.5}},         # and no pairing is shortened below the raw frame data
		{"pairs": {"pzz": 0.5}},        # not a pairing
		{"pairs": {"pq": "slow"}},
		{"pairs": [0.5]},
		{"target_seconds": -1.0},
		"not an object",
	]
	for patch in invalid:
		var errors := Balance.apply_override({"duel_length": patch})
		h.check(not errors.is_empty() and not Balance.is_overridden(), "refused and nothing installed: %s" % str(patch))
	var ok := Balance.apply_override({"duel_length": {"pairs": {"pq": 0.5}}})
	h.check(ok.is_empty(), "a valid override installs (%s)" % str(ok))
	h.eq(Balance.damage_scale("p", "q"), 0.5, "the override is served")
	h.check(Balance.stamp() != stamp, "the tuning stamp changes, so a client and server with different scales can tell")
	Balance.clear_override()
	h.eq(Balance.stamp(), stamp, "clearing the override restores the shipped stamp")


static func _length_simulation(h, tree: SceneTree) -> void:
	h.begin("duel length simulation: data by default, raw frame data on request, explicit for tools, the King always unscaled")
	var shipped := Balance.damage_scale("p", "q")
	var sim := await _start(tree, "p", "q", {})
	h.check(is_equal_approx(sim.damage_scale, shipped), "Pawn attacks Queen: the table's scale %.3f is used by default (%.3f)" % [shipped, sim.damage_scale])
	_dispose(sim)
	sim = await _start(tree, "p", "q", {"attacker_edge": false})
	h.eq(sim.damage_scale, 1.0, "attacker_edge: false = raw frame data, so the tests that assert exact blows keep measuring raw frame data")
	_dispose(sim)
	sim = await _start(tree, "p", "q", {"attacker_edge": {"attacker": 2.0, "defender": 1.0}})
	h.check(is_equal_approx(sim.damage_scale, shipped), "an explicit edge (a calibration trial) still uses the data's scale")
	_dispose(sim)
	sim = await _start(tree, "p", "q", {"damage_scale": 0.4})
	h.eq(sim.damage_scale, 0.4, "an explicit scale is used as given (length calibration)")
	_dispose(sim)
	sim = await _start(tree, "p", "q", {"attacker_edge": false, "damage_scale": 0.4})
	h.eq(sim.damage_scale, 0.4, "an explicit scale also works on raw frame data")
	_dispose(sim)
	sim = await _start(tree, "p", "q", {"damage_scale": 5.0})
	h.eq(sim.damage_scale, 1.0, "a scale above 1 is clamped: duels are lengthened, never shortened")
	_dispose(sim)
	for roles in [["k", "q"], ["q", "k"]]:
		sim = await _start(tree, roles[0], roles[1], {"damage_scale": 0.4})
		h.eq(sim.damage_scale, 1.0, "%s attacks %s: a King on either side is unscaled even when asked" % roles)
		_dispose(sim)
	sim = await _start(tree, "p", "q", {"damage_scale": 0.4})
	sim.stop()
	var request := FighterRoster.build_request("n", "n", "w", "edge-3", 7, 0)
	h.check(sim.start(request, {"attacker_edge": false})["ok"] and sim.damage_scale == 1.0, "a new duel on the same simulation does not inherit the previous scale")
	_dispose(sim)


static func _length_damage(h, tree: SceneTree) -> void:
	h.begin("duel length damage: the scale multiplies HP damage after the edge and armour, the fraction carries, the guard cost does not shrink")
	var light: AttackDefinition = Balance.attack_tables("p")["light"][0]
	var sim := await _start(tree, "p", "p", {"attacker_edge": {"attacker": 2.0, "defender": 1.0}, "damage_scale": 0.5})
	var attacker := sim.attacker()
	var defender := sim.defender()
	var before := defender.health.current
	sim._apply_hit(attacker, defender, light, 10)
	h.eq(before - defender.health.current, 10, "scale 0.5 with a 2x edge: a 10-damage blow deals 10 x 2 x 0.5 = 10")
	before = attacker.health.current
	sim._apply_hit(defender, attacker, light, 10)
	h.eq(before - attacker.health.current, 5, "and the defender's 10-damage blow deals 10 x 0.5 = 5")
	_dispose(sim)
	sim = await _start(tree, "p", "p", {"attacker_edge": {"attacker": 1.0, "defender": 1.0}, "damage_scale": 0.25})
	defender = sim.defender()
	var dealt: Array = []
	for _i in 4:
		var hp := defender.health.current
		sim._apply_hit(sim.attacker(), defender, light, 10)
		dealt.append(hp - defender.health.current)
	h.eq(dealt, [2, 3, 2, 3], "scale 0.25: a 10-damage blow is 2.5, taken as 2 and 3 alternately, 10 in four blows")
	_dispose(sim)
	var rook_sim := await _start(tree, "p", "r", {"attacker_edge": {"attacker": 2.0, "defender": 1.0}, "damage_scale": 0.5})
	var rook := rook_sim.defender()
	var armor := float(rook.profile["armor"])
	var rook_before := rook.health.current
	for _i in 4:
		rook_sim._apply_hit(rook_sim.attacker(), rook, light, 10)
	h.eq(rook_before - rook.health.current, roundi(4.0 * 10.0 * 2.0 * 0.5 * (1.0 - armor)), "armour applies to the scaled blow: four blows take 4 x 10 x 2 x 0.5 x (1 - armour)")
	_dispose(rook_sim)
	# The stamina cost of a blocked blow is NOT scaled down: the scale lengthens the fight in HP terms only, it must not make blocking free.
	var lost: Array = []
	for scale in [1.0, 0.25]:
		var block_sim := await _start(tree, "p", "p", {"attacker_edge": false, "damage_scale": scale})
		var blocker := block_sim.defender()
		blocker.sm.state = CombatConstants.State.BLOCKING
		blocker.sm.state_ticks = CombatConstants.BLOCK_RAISE_TICKS
		var stamina_before := blocker.stamina.current
		var hp_before := blocker.health.current
		block_sim._apply_hit(block_sim.attacker(), blocker, light, 10)
		lost.append(stamina_before - blocker.stamina.current)
		h.eq(blocker.health.current, hp_before, "scale %.2f: a blocked blow takes no HP" % scale)
		_dispose(block_sim)
	h.check(lost[0] > 0.0 and is_equal_approx(lost[0], lost[1]), "blocking costs the same stamina at scale 1.0 and 0.25 (%.2f and %.2f)" % [lost[0], lost[1]])
	# A guard-break's chip damage is half a clean hit, scaled the same way.
	var chip_sim := await _start(tree, "p", "p", {"attacker_edge": false, "damage_scale": 0.5})
	var chipped := chip_sim.defender()
	var chip_before := chipped.health.current
	chip_sim._deal_damage(chipped, 20, 0.5)
	h.eq(chip_before - chipped.health.current, 5, "chip damage (factor 0.5) of a 20-damage blow at scale 0.5 is 5")
	_dispose(chip_sim)


# ---- the bot gate -------------------------------------------------------------------------------------------------------------
## One pass of fixed-seed duels (casual bot) checks both the attacker's advantage and the duel length with the shipped data: the
## attacker wins more often than not, and a duel lasts long enough to be a fight. Deterministic for a given tuning; when it fails,
## re-run tools/length_calibrate.gd (length) and tools/edge_calibrate.gd (advantage), BALANCE.md has the commands.
static func _gate(h, tree: SceneTree) -> void:
	h.begin("attacker edge gate: with the shipped data the attacker wins more often than not and a duel lasts like a fight (casual bot, fixed seeds)")
	var cfg := {"style": "balanced", "skill": 0.6}
	var wins := 0
	var total := 0
	var worst := 1.0
	var worst_pair := ""
	var timeouts := 0
	var shortest := 1e9
	var shortest_pair := ""
	for key in GATE_PAIRS:
		var pair_wins := 0
		var lengths: Array = []
		for i in GATE_N:
			var r: Dictionary = await Duel.duel(tree, key.substr(0, 1), key.substr(1, 1), cfg, GATE_SEED + i)
			total += 1
			if r["outcome"] == "attacker":
				pair_wins += 1
			if String(r["reason"]).begins_with("timeout"):
				timeouts += 1
			lengths.append(float(r["active_ticks"]) / 60.0)
		wins += pair_wins
		var rate := float(pair_wins) / float(GATE_N)
		if rate < worst:
			worst = rate
			worst_pair = key
		lengths.sort()
		var median: float = (float(lengths[GATE_N / 2 - 1]) + float(lengths[GATE_N / 2])) / 2.0
		if median < shortest:
			shortest = median
			shortest_pair = key
	var overall := float(wins) / float(total)
	h.check(overall >= GATE_MIN_ATTACKER_RATE, "the attacker wins %.0f%% of %d duels over the gate pairings (needs >= %.0f%%)" % [100.0 * overall, total, 100.0 * GATE_MIN_ATTACKER_RATE])
	h.check(worst >= GATE_MIN_PAIR_RATE, "the weakest gate pairing (%s attacks %s) still gives the attacker %.0f%% (needs >= %.0f%%)" % [worst_pair.substr(0, 1), worst_pair.substr(1, 1), 100.0 * worst, 100.0 * GATE_MIN_PAIR_RATE])
	h.check(shortest >= GATE_MIN_MEDIAN_SECONDS, "the shortest gate pairing (%s attacks %s) still lasts a median %.1f s of fighting (needs >= %.0f s)" % [shortest_pair.substr(0, 1), shortest_pair.substr(1, 1), shortest, GATE_MIN_MEDIAN_SECONDS])
	h.check(timeouts <= GATE_MAX_TIMEOUTS, "almost no gate duel runs into the time limit (%d of %d)" % [timeouts, total])


## The Queen is the strongest piece and must feel like it: she beats a Pawn or Bishop that attacks her, and wins when she attacks them,
## while the weaker attacker still has a real chance (the attacker's initiative bonus). Casual bot, fixed seeds.
static func _queen_gate(h, tree: SceneTree) -> void:
	h.begin("queen gate: a Queen holds against a Pawn or Bishop that attacks her and wins when she attacks (casual bot, fixed seeds)")
	var cfg := {"style": "balanced", "skill": 0.6}
	var rates := {}
	for key in ["qp", "qb", "pq", "bq"]:
		var wins := 0
		for i in GATE_N:
			var r: Dictionary = await Duel.duel(tree, key.substr(0, 1), key.substr(1, 1), cfg, GATE_SEED + 500 + i)
			if r["outcome"] == "attacker":
				wins += 1
		rates[key] = float(wins) / float(GATE_N)
	h.check(rates["qp"] >= 0.80 and rates["qb"] >= 0.80, "a Queen attacking a Pawn / Bishop wins at least 80%% (%.0f%% / %.0f%%)" % [100.0 * rates["qp"], 100.0 * rates["qb"]])
	h.check(rates["pq"] <= 0.45 and rates["bq"] <= 0.55, "a Pawn / Bishop attacking the Queen wins at most 45%% / 55%% (%.0f%% / %.0f%%): she holds" % [100.0 * rates["pq"], 100.0 * rates["bq"]])
	h.check(rates["pq"] >= 0.03, "...but the Pawn still has a real chance as the attacker (%.0f%%)" % (100.0 * rates["pq"]))
