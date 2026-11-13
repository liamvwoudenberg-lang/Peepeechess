extends RefCounted
## One bot-vs-bot duel with role `attacker_role` attacking `defender_role`, for the balance tools (attacker_matrix.gd,
## edge_calibrate.gd). The same bot config plays both seats so skill cancels out; the seat colour alternates with the seed so a
## positional bias cancels. `options` go to CombatSimulation.start() (for example {"attacker_edge": false} for raw frame data or
## {"attacker_edge": {"attacker": 1.8, "defender": 1.0}} for a calibration trial). BOT-measured, not a human balance claim.
const MAX_TICKS := 6000


## Returns {outcome: "attacker"|"defender", reason, ticks, active_ticks, hits, blocks, parries, dodges, attacker_hp, defender_hp
## (fractions of their maximum)}. `ticks` counts from the start of the duel INCLUDING the 180-tick countdown; `active_ticks` is the
## fight itself (what a player experiences); `hits` are clean hits that took HP away (both seats together).
static func duel(tree: SceneTree, attacker_role: String, defender_role: String, cfg: Dictionary, seed_value: int, options: Dictionary = {}) -> Dictionary:
	var attacker_white := seed_value % 2 == 0
	var white_role := attacker_role if attacker_white else defender_role
	var black_role := defender_role if attacker_white else attacker_role
	var battle_id := "ad-%d" % seed_value
	var request := FighterRoster.build_request(white_role, black_role, "w" if attacker_white else "b", battle_id, seed_value, 0)
	var sim := CombatSimulation.new()
	tree.root.add_child(sim)
	var start_options := {"allow_experimental_roles": true}
	start_options.merge(options, true)
	var started: Dictionary = sim.start(request, start_options)
	if not started["ok"]:
		sim.get_parent().remove_child(sim)
		sim.queue_free()
		return {"error": str(started), "outcome": "error", "reason": "error", "ticks": 0, "attacker_hp": 0.0, "defender_hp": 0.0}
	await tree.physics_frame
	var white_builder := CombatInputBuilder.new(request["matchId"], battle_id, "player-white")
	var black_builder := CombatInputBuilder.new(request["matchId"], battle_id, "player-black")
	var ai_white := CombatAI.new(white_builder, FighterRoster.stats_for(white_role), FighterRoster.stats_for(black_role), seed_value * 2 + 1, float(cfg["skill"]), String(cfg["style"]))
	var ai_black := CombatAI.new(black_builder, FighterRoster.stats_for(black_role), FighterRoster.stats_for(white_role), seed_value * 2 + 2, float(cfg["skill"]), String(cfg["style"]))
	var counts := {"hit": 0, "block": 0, "parry": 0, "dodge": 0, "guardbreak": 0}
	sim.event_emitted.connect(func(event: Dictionary) -> void:
		var kind := String(event.get("type", ""))
		if counts.has(kind):
			counts[kind] += 1)
	var guard := 0
	while sim.is_running() and guard < MAX_TICKS:
		var snapshot := sim.snapshot(false)
		sim.submit_input(ai_white.think(snapshot))
		sim.submit_input(ai_black.think(snapshot))
		sim.step_tick()
		guard += 1
	var result: Dictionary = sim.result.duplicate(true)
	var attacker_fighter = sim.fighters[0] if attacker_white else sim.fighters[1]
	var defender_fighter = sim.fighters[1] if attacker_white else sim.fighters[0]
	var out := {"outcome": String(result.get("outcome", "unfinished")), "reason": String(result.get("reason", "unfinished")), "ticks": guard,
			"active_ticks": maxi(0, guard - CombatConstants.COUNTDOWN_TICKS), "hits": counts["hit"] + counts["guardbreak"], "blocks": counts["block"],
			"parries": counts["parry"], "dodges": counts["dodge"],
			"attacker_hp": attacker_fighter.health.current / float(attacker_fighter.health.maximum),
			"defender_hp": defender_fighter.health.current / float(defender_fighter.health.maximum)}
	sim.stop()
	sim.get_parent().remove_child(sim)
	sim.queue_free()
	return out


## Attacker win rate over `n` seeds for the pairing under `options`. Returns {wins, n, timeouts, ticks}.
static func series(tree: SceneTree, attacker_role: String, defender_role: String, cfg: Dictionary, n: int, base_seed: int, options: Dictionary = {}) -> Dictionary:
	var wins := 0
	var timeouts := 0
	var ticks := 0
	for i in n:
		var r: Dictionary = await duel(tree, attacker_role, defender_role, cfg, base_seed + i, options)
		ticks += int(r["ticks"])
		if String(r["reason"]).begins_with("timeout"):
			timeouts += 1
		if r["outcome"] == "attacker":
			wins += 1
	return {"wins": wins, "n": n, "timeouts": timeouts, "ticks": ticks}
