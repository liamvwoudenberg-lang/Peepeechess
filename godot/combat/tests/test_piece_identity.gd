extends RefCounted
## Piece identity and pacing (BALANCE.md "Piece identity" and "Pacing"): the Knight's telegraphed lunge, the Bishop's range-scaled
## beam, the Rook's guard-break, the comeback bonus and sudden death. Everything is data (balance_v1.json) plus three small rules in
## the authoritative simulation, derived from HP and the clock only, so duels stay deterministic and snapshots are unchanged.

const Balance := preload("res://combat/data/balance_data.gd")
const Duel := preload("res://combat/tools/attacker_duel.gd")
const CFG := {"style": "balanced", "skill": 0.6}


static func run(h, tree: SceneTree) -> void:
	_data(h)
	_range(h)
	await _pacing(h, tree)
	await _guard_break(h, tree)
	await _determinism(h, tree)


static func _data(h) -> void:
	h.begin("piece identity data: Knight lunge telegraph, Bishop beam, Rook guard-break, pacing rules")
	var lunge: AttackDefinition = AttackLibrary.ability_attack("n", "lunging-strike")
	h.check(lunge.startup_end >= 0.5 and lunge.forward_motion_m >= 4.0 and lunge.armor_end > lunge.armor_start, "Knight lunge: a long wind-up (%.2f), a big gap-closing run (%.1f m), armoured on the way in" % [lunge.startup_end, lunge.forward_motion_m])
	var recovery := lunge.absolute_ticks - lunge.active_window(lunge.absolute_ticks).y
	h.check(lunge.cancel_from >= 1.0 and recovery >= 22, "Knight lunge: no cancel and %d ticks of recovery after the hit window, so a blocked or dodged lunge is punishable (72 ticks stay the contract length)" % recovery)
	var beam: AttackDefinition = AttackLibrary.heavy("b")
	h.check(beam.reach_mult >= 1.8 and beam.arc_degrees <= 30.0, "Bishop heavy is a beam: long reach (x%.1f), narrow arc (%.0f deg)" % [beam.reach_mult, beam.arc_degrees])
	h.check(beam.far_mult > 1.0 and beam.startup_end >= 0.55, "Bishop beam bites harder at range (x%.2f) and is telegraphed (wind-up %.2f)" % [beam.far_mult, beam.startup_end])
	for light in Balance.attack_tables("b")["light"]:
		h.check(light.near_mult < 1.0 and light.near_m > 0.0, "%s is weaker up close (x%.2f inside %.1f m)" % [light.id, light.near_mult, light.near_m])
	var smash: AttackDefinition = AttackLibrary.heavy("r")
	h.check(smash.guard_break == 1 and smash.forward_motion_m <= 0.01 and smash.startup_end >= 0.6, "Rook heavy: guard-breaking, rooted (no forward motion), slow wind-up (%.2f)" % smash.startup_end)
	h.check(AttackLibrary.heavy("n").guard_break == 0 and AttackLibrary.heavy("q").guard_break == 0, "only the Rook breaks guards")
	var pacing := Balance.pacing()
	h.check(float(pacing["comeback"]["damage_mult"]) > 1.0 and float(pacing["comeback"]["damage_mult"]) <= 1.25 and float(pacing["comeback"]["hp_gap"]) >= 0.3, "comeback: a modest bonus (x%s) for a large HP gap (%s)" % [str(pacing["comeback"]["damage_mult"]), str(pacing["comeback"]["hp_gap"])])
	h.check(float(pacing["sudden_death"]["start_s"]) > 20.0 and float(pacing["sudden_death"]["start_s"]) < 80.0 and float(pacing["sudden_death"]["ramp_per_s"]) > 0.0, "sudden death starts after %s s and ramps %s per second" % [str(pacing["sudden_death"]["start_s"]), str(pacing["sudden_death"]["ramp_per_s"])])
	h.check(Balance.validate(Balance.snapshot()).is_empty(), "the shipped data validates (including pacing and the new attack fields)")
	var bad := Balance.snapshot()
	bad["pacing"] = {"comeback": {"hp_gap": 0.4, "damage_mult": 5.0}, "sudden_death": {"start_s": 40.0, "ramp_per_s": 0.04}}
	h.check(not Balance.validate(bad).is_empty(), "a comeback bonus of x5 is refused")


static func _range(h) -> void:
	h.begin("range curve: near scaling, far scaling, neutral when unset")
	var beam: AttackDefinition = AttackLibrary.heavy("b")
	h.near(beam.range_mult(1.0), 1.0, 0.0001, "no change inside the far threshold")
	h.near(beam.range_mult(beam.far_m + 1.0), beam.far_mult, 0.0001, "the full far bonus one metre past the threshold")
	h.check(beam.range_mult(beam.far_m + 0.5) > 1.0 and beam.range_mult(beam.far_m + 0.5) < beam.far_mult, "growing in between")
	var light: AttackDefinition = Balance.attack_tables("b")["light"][0]
	h.near(light.range_mult(0.0), light.near_mult, 0.0001, "the full close-range malus at contact")
	h.near(light.range_mult(light.near_m + 0.5), 1.0, 0.0001, "none beyond the near threshold")
	h.near(AttackLibrary.heavy("n").range_mult(0.2), 1.0, 0.0001, "a Knight's blow has no distance curve")


static func _sim(tree: SceneTree, a: String, d: String) -> CombatSimulation:
	var sim := CombatSimulation.new()
	tree.root.add_child(sim)
	var request := FighterRoster.build_request(a, d, "w", "pid-1", 11, 0)
	var reply: Dictionary = sim.start(request, {"allow_experimental_roles": true})
	assert(reply["ok"], "start failed: %s" % str(reply))
	await tree.physics_frame
	return sim


static func _dispose(sim: CombatSimulation) -> void:
	sim.stop()
	sim.get_parent().remove_child(sim)
	sim.queue_free()


static func _pacing(h, tree: SceneTree) -> void:
	h.begin("pacing: comeback applies only to the fighter far behind; sudden death ramps with the clock")
	var sim := await _sim(tree, "r", "r")
	var a := sim.attacker()
	var d := sim.defender()
	h.near(sim.pacing_mult(a, d), 1.0, 0.0001, "even fight, early: no bonus")
	d.health.current = int(d.health.maximum * 0.5)
	var comeback := float(Balance.pacing()["comeback"]["damage_mult"])
	h.near(sim.pacing_mult(d, a), comeback, 0.0001, "the fighter %d%% behind hits x%.2f harder" % [50, comeback])
	h.near(sim.pacing_mult(a, d), 1.0, 0.0001, "the leader gets nothing")
	d.health.current = int(d.health.maximum * 0.8)
	h.near(sim.pacing_mult(d, a), 1.0, 0.0001, "a small gap is not enough")
	d.health.current = d.health.maximum
	var start_s := float(Balance.pacing()["sudden_death"]["start_s"])
	var ramp := float(Balance.pacing()["sudden_death"]["ramp_per_s"])
	sim.duration_remaining = CombatConstants.DURATION_TICKS - int((start_s - 1.0) * 60.0)
	h.check(not sim.sudden_death_active() and is_equal_approx(sim.pacing_mult(a, d), 1.0), "just before sudden death: nothing")
	sim.duration_remaining = CombatConstants.DURATION_TICKS - int((start_s + 10.0) * 60.0)
	h.check(sim.sudden_death_active(), "after %s s sudden death is on" % str(start_s))
	h.near(sim.pacing_mult(a, d), 1.0 + ramp * 10.0, 0.001, "ten seconds in: x%.2f on every blow" % (1.0 + ramp * 10.0))
	# A blow in sudden death removes more HP than the same blow early (the same arithmetic path as every hit).
	var heavy: AttackDefinition = AttackLibrary.heavy("r")
	var before := a.health.current
	sim.duration_remaining = CombatConstants.DURATION_TICKS - int((start_s + 30.0) * 60.0)
	sim._apply_hit(d, a, heavy, 20)
	var late_damage := before - a.health.current
	a.health.current = before
	sim.duration_remaining = CombatConstants.DURATION_TICKS - 600
	sim._apply_hit(d, a, heavy, 20)
	var early_damage := before - a.health.current
	h.check(late_damage > early_damage, "the same blow hurts more in sudden death (%d vs %d HP)" % [late_damage, early_damage])
	_dispose(sim)


static func _guard_break(h, tree: SceneTree) -> void:
	h.begin("guard-break: a blocked Rook heavy breaks the guard even with full stamina; a blocked Knight heavy does not")
	for case in [["r", "guardbreak"], ["n", "block"]]:
		var sim := await _sim(tree, case[0], "q")
		var a := sim.attacker()
		var d := sim.defender()
		d.global_position = a.global_position + Vector3(0.0, 0.0, 1.0)
		a.yaw = CombatConstants.yaw_of(CombatConstants.flat(d.global_position - a.global_position))
		d.yaw = CombatConstants.yaw_of(CombatConstants.flat(a.global_position - d.global_position))
		d.sm.state = CombatConstants.State.BLOCKING
		d.sm.state_ticks = CombatConstants.BLOCK_RAISE_TICKS + 2
		var kinds: Array = []
		sim.event_emitted.connect(func(event: Dictionary) -> void: kinds.append(String(event.get("type", ""))))
		d.stamina.current = d.stamina.maximum
		sim._apply_hit(a, d, AttackLibrary.heavy(case[0]), 4)
		h.check(kinds.has(case[1]), "%s heavy into a raised guard -> %s (events %s)" % [case[0], case[1], str(kinds)])
		_dispose(sim)


static func _determinism(h, tree: SceneTree) -> void:
	h.begin("determinism: the same seeded duel gives the same result twice (pacing and identity rules included)")
	for key in ["bn", "rr", "nb"]:
		var one: Dictionary = await Duel.duel(tree, key.substr(0, 1), key.substr(1, 1), CFG, 4242)
		var two: Dictionary = await Duel.duel(tree, key.substr(0, 1), key.substr(1, 1), CFG, 4242)
		h.check(one["outcome"] == two["outcome"] and one["ticks"] == two["ticks"] and is_equal_approx(one["attacker_hp"], two["attacker_hp"]), "%s: identical outcome, length and HP twice (%s in %d ticks)" % [key, one["outcome"], one["ticks"]])
	var rook: Dictionary = await Duel.duel(tree, "r", "r", CFG, 4343)
	h.check(rook["reason"] != "unfinished" and rook["ticks"] <= CombatConstants.DURATION_TICKS + CombatConstants.COUNTDOWN_TICKS + 30, "a Rook mirror ends inside the duel clock (%d ticks, %s)" % [rook["ticks"], rook["reason"]])
