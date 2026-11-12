extends RefCounted
## Headless AI-vs-AI duels for the battle-royal-v1 "last stand" (used by test_royal.gd and tools/royal_matrix.gd).
## Every action goes through the real CombatInput channel; the King fights through the experimental start option and its
## HP / stamina / cooldown carry from duel to duel exactly like BattleRoyalMatch does. Deterministic per (request, configs).
##
## Honesty note: results are BOT-measured (CombatAI styles), not human-tested (see combat/BALANCE.md).

const BASELINE := {"style": "balanced", "skill": 0.6}


## Plays ONE duel from `request` (+ start `options`). The attacker seat uses `attacker_cfg`, the defender `defender_cfg`
## ({"style", "skill"}). `on_snapshot` (optional) is called with the full snapshot before the first tick and every
## `snapshot_every` ticks. Returns {ok, sim (the caller disposes it with dispose()), result, ticks, error}.
static func play(tree: SceneTree, request: Dictionary, options: Dictionary, attacker_cfg: Dictionary,
		defender_cfg: Dictionary, on_snapshot: Callable = Callable(), snapshot_every: int = 15) -> Dictionary:
	var sim := CombatSimulation.new()
	tree.root.add_child(sim)
	var started: Dictionary = sim.start(request, options)
	if not started["ok"]:
		sim.get_parent().remove_child(sim)
		sim.queue_free()
		return {"ok": false, "error": str(started), "result": {}, "ticks": 0, "sim": null}
	await tree.physics_frame
	var seed_value := int(request["seed"])
	var cfgs := {request["attacker"]["playerId"]: attacker_cfg, request["defender"]["playerId"]: defender_cfg}
	var opponents := {request["attacker"]["playerId"]: request["defender"]["stats"], request["defender"]["playerId"]: request["attacker"]["stats"]}
	var own := {request["attacker"]["playerId"]: request["attacker"]["stats"], request["defender"]["playerId"]: request["defender"]["stats"]}
	var ais := {}
	var index := 0
	for player_id in cfgs:
		var builder := CombatInputBuilder.new(request["matchId"], request["battleId"], player_id)
		ais[player_id] = CombatAI.new(builder, own[player_id], opponents[player_id], seed_value * 2 + 1 + index,
				float(cfgs[player_id]["skill"]), String(cfgs[player_id]["style"]))
		index += 1
	var ticks := 0
	if on_snapshot.is_valid():
		on_snapshot.call(sim.snapshot())
	while sim.is_running() and ticks < 6000:
		var snap := sim.snapshot(false)
		for player_id in ais:
			sim.submit_input(ais[player_id].think(snap))
		sim.step_tick()
		ticks += 1
		if on_snapshot.is_valid() and (ticks % snapshot_every == 0 or not sim.is_running()):
			on_snapshot.call(sim.snapshot())
	return {"ok": true, "error": "", "sim": sim, "result": sim.result.duplicate(true), "ticks": ticks}


static func dispose(sim: CombatSimulation) -> void:
	if sim == null:
		return
	sim.stop()
	if sim.get_parent() != null:
		sim.get_parent().remove_child(sim)
	sim.queue_free()


## A pure-combat last stand: the King (colour `king_color`) fights `checker_roles` in order. Returns
## {king_wins, duels: [{role, hp_start, hp_end, stamina_end, cooldown_end, reason, ticks}], king}.
static func sequence(tree: SceneTree, king_color: String, checker_roles: Array, king_cfg: Dictionary,
		checker_cfg: Dictionary, base_seed: int, carry: bool = true) -> Dictionary:
	var king := {"hp": int(FighterRoster.stats_for("k")["maxHp"]), "stamina": float(FighterRoster.stats_for("k")["maxStamina"]), "cooldownTicks": 0}
	var duels: Array = []
	var wins := true
	for i in checker_roles.size():
		var role: String = checker_roles[i]
		var white := "k" if king_color == "w" else role
		var black := role if king_color == "w" else "k"
		var request := FighterRoster.build_request(white, black, king_color, "royal-%d-%d" % [base_seed, i], base_seed * 16 + i, 0)
		var options := {"allow_experimental_roles": true, "initial_hp": king["hp"], "initial_stamina": king["stamina"], "initial_cooldown": king["cooldownTicks"]}
		if not carry:
			options = {"allow_experimental_roles": true}
		var played: Dictionary = await play(tree, request, options, king_cfg, checker_cfg)
		if not played["ok"]:
			return {"king_wins": false, "duels": duels, "king": king, "error": played["error"]}
		var sim: CombatSimulation = played["sim"]
		var end: Dictionary = sim.fighter_state(request["attacker"]["playerId"])
		var result: Dictionary = played["result"]
		duels.append({"role": role, "hp_start": king["hp"], "hp_end": int(end["hp"]), "stamina_end": end["stamina"],
				"cooldown_end": end["cooldownTicks"], "reason": String(result["reason"]), "outcome": String(result["outcome"]),
				"ticks": played["ticks"], "checker_hp": int(result["defenderHp"])})
		dispose(sim)
		king = {"hp": int(end["hp"]), "stamina": float(end["stamina"]), "cooldownTicks": int(end["cooldownTicks"])}
		if result["outcome"] != "attacker" or int(end["hp"]) <= 0:
			wins = false
			break
	return {"king_wins": wins, "duels": duels, "king": king}
