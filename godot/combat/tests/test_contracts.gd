extends RefCounted
## Contract conformance and admission rules (CONTRACTS.md): shapes validate with Codex's codec;
## malformed, stale, forged or out-of-phase traffic is refused without side effects.

const Support := preload("res://combat/tests/test_support.gd")
const Codec := preload("res://contracts/codec.gd")


static func run(h, tree: SceneTree) -> void:
	await _shapes(h, tree)
	await _admission(h, tree)
	await _start_validation(h, tree)


static func _shapes(h, tree: SceneTree) -> void:
	h.begin("contracts: request, snapshots, input and result are schema-valid")
	var codec = Codec.new()
	var rig = await Support.make_rig(tree, "p", "n", "w", 300)
	h.check(codec.valid("BattleRequest", FighterRoster.build_request("p", "n")), "prototype BattleRequest (white attacker) is valid")
	h.check(codec.valid("BattleRequest", FighterRoster.build_request("n", "p", "b")), "prototype BattleRequest (black attacker) is valid")
	var snap: Dictionary = rig.sim.snapshot()
	h.check(codec.valid("CombatSnapshot", snap), "initial snapshot is a valid CombatSnapshot")
	h.eq(snap["serverTick"], 300, "serverTick starts at the request's startTick")
	h.eq(snap["countdownTicksRemaining"], 180, "180 countdown ticks")
	h.eq(snap["durationTicksRemaining"], 5400, "5400 active ticks")
	h.eq(snap["fighters"][0]["playerId"], "player-white", "fighters[0] is the White seat")
	h.near(snap["fighters"][0]["position"]["z"], -2.6, 0.0001, "White spawns at z=-2.6")
	h.near(snap["fighters"][1]["position"]["z"], 2.6, 0.0001, "Black spawns at z=+2.6")
	h.near(snap["fighters"][1]["yawRadians"], PI, 0.0001, "Black faces pi")
	h.check(snap["result"] == null, "no result during a fight")
	h.check(codec.valid("CombatInput", rig.w.packet()), "builder output is a valid CombatInput")

	rig.w.move = Vector2(0.0, 1.0)
	rig.tick(190)
	h.eq(rig.sim.server_tick, 490, "serverTick advances 1 per tick (300 + 190)")
	h.eq(rig.sim.countdown_remaining, 0, "countdown finished after 180 ticks")
	h.eq(rig.sim.duration_remaining, 5390, "active ticks count down after the countdown")
	snap = rig.sim.snapshot()
	h.check(codec.valid("CombatSnapshot", snap), "mid-fight snapshot is valid")
	h.eq(rig.submit_errors.size(), 0, "no rejected inputs in a clean run")
	rig.dispose()

	h.begin("contracts: Black-attacker mapping, attacker/defender are not seats")
	rig = await Support.make_rig(tree, "p", "n", "b")
	h.eq(rig.sim.attacker().player_id, "player-black", "attacker is the Black seat")
	h.eq(rig.sim.defender().player_id, "player-white", "defender is the White seat")
	h.near(rig.white().global_position.z, -2.6, 0.0001, "White still spawns at -2.6 even as defender")
	rig.dispose()


static func _admission(h, tree: SceneTree) -> void:
	h.begin("admission: forged, stale, replayed and out-of-phase inputs are refused")
	var rig = await Support.make_rig(tree, "p", "p")
	var sim: CombatSimulation = rig.sim

	var forged: Dictionary = rig.w.packet()
	forged["damage"] = 9999
	var reply: Dictionary = sim.submit_input(forged)
	h.check(not reply["ok"] and reply["code"] == "INVALID_PAYLOAD", "unknown field (damage) is rejected")
	var forged_hp: Dictionary = rig.w.packet()
	forged_hp["hp"] = 1000
	h.eq(sim.submit_input(forged_hp)["code"], "INVALID_PAYLOAD", "client-sent hp is rejected")

	var good: Dictionary = rig.w.packet()
	h.check(sim.submit_input(good)["ok"], "a valid input is accepted")
	h.eq(sim.submit_input(good)["code"], "STALE_INPUT", "replaying the same sequence is stale")
	var older: Dictionary = good.duplicate()
	older["sequence"] = int(good["sequence"]) - 1
	h.eq(sim.submit_input(older)["code"], "STALE_INPUT", "an older sequence is stale")

	var other_battle: Dictionary = rig.w.packet()
	other_battle["battleId"] = "someone-elses"
	h.eq(sim.submit_input(other_battle)["code"], "FORBIDDEN", "input for another battle is refused")
	var unknown_seat: Dictionary = rig.w.packet()
	unknown_seat["playerId"] = "player-mallory"
	h.eq(sim.submit_input(unknown_seat)["code"], "FORBIDDEN", "an unknown seat is refused")

	rig.w.press("light")
	rig.w.press("light")
	var with_counter: Dictionary = rig.w.packet()
	h.check(sim.submit_input(with_counter)["ok"], "counter increase is accepted")
	var rewound: Dictionary = rig.w.packet()
	rewound["light"] = 0
	h.eq(sim.submit_input(rewound)["code"], "INVALID_PAYLOAD", "action counters may never decrease")
	h.check(not sim.submit_input(rig.w.packet().merged({"moveX": 5.0}, true))["ok"], "axis outside [-1,1] is rejected")

	h.eq(sim.fighters[0].last_input_sequence, int(with_counter["sequence"]), "last accepted sequence is acknowledged in snapshots")
	rig.dispose()

	h.begin("admission: phases")
	var idle := CombatSimulation.new()
	tree.root.add_child(idle)
	h.eq(idle.submit_input({})["code"], "WRONG_PHASE", "input before any battle is WRONG_PHASE")
	h.check(idle.snapshot().is_empty(), "no snapshot without a battle")
	idle.queue_free()


static func _start_validation(h, tree: SceneTree) -> void:
	h.begin("start: request validation and unsupported fighters")
	var sim := CombatSimulation.new()
	tree.root.add_child(sim)
	var bad := FighterRoster.build_request("p", "n")
	bad["attacker"]["stats"]["role"] = "n"
	h.eq(sim.start(bad)["code"], "INVALID_PAYLOAD", "stats.role must match the combatant role")
	h.check(not sim.is_running(), "a refused request starts nothing")

	var schema_bad := FighterRoster.build_request("p", "n")
	schema_bad["countdownTicks"] = 90
	h.eq(sim.start(schema_bad)["code"], "INVALID_PAYLOAD", "off-contract countdown is rejected")

	var same_seat := FighterRoster.build_request("p", "n")
	same_seat["defender"]["playerId"] = same_seat["attacker"]["playerId"]
	h.eq(sim.start(same_seat)["code"], "INVALID_PAYLOAD", "attacker and defender must be different players")

	var queen := FighterRoster.build_request("p", "n")
	queen["defender"]["role"] = "q"
	queen["defender"]["characterId"] = "skeletons.q"
	queen["defender"]["stats"] = {
		"schemaVersion": 1, "statsId": "balance-v1.q", "role": "q", "maxHp": 135, "maxStamina": 115, "baseDamage": 24,
		"moveSpeedMps": 3.66, "reachM": 1.65, "lightTicks": 28, "heavyTicks": 58, "parryTicks": 10,
		"abilityId": "royal-fury", "cooldownTicks": 840,
	}
	var refused: Dictionary = sim.start(queen)
	h.eq(refused["code"], "INVALID_PAYLOAD", "a schema-valid queen is refused (not implemented), not silently weakened")
	h.check("not implemented" in String(refused["message"]), "the reason says the role is not implemented")
	h.check(not sim.is_running() and sim.fighters.is_empty(), "no half-built battle is left behind")

	var mismatch := FighterRoster.build_request("p", "n")
	mismatch["attacker"]["stats"]["abilityId"] = "lunging-strike"
	h.eq(sim.start(mismatch)["code"], "INVALID_PAYLOAD", "an ability that does not belong to the role is refused")

	h.begin("start: one battle at a time, stop() never fabricates a result")
	var ok: Dictionary = sim.start(FighterRoster.build_request("p", "n"))
	h.check(ok["ok"], "a valid request starts")
	h.eq(sim.start(FighterRoster.build_request("n", "p"))["code"], "WRONG_PHASE", "a second start while running is refused")
	sim.stop()
	h.eq(sim.phase, CombatSimulation.Phase.IDLE, "stop() returns to idle")
	h.check(sim.result.is_empty(), "stop() leaves no result")
	h.check(sim.snapshot().is_empty(), "no snapshot after stop()")
	h.check(sim.start(FighterRoster.build_request("n", "n", "w", "t-2"))["ok"], "a new battle can start after stop()")
	sim.stop()
	sim.queue_free()
