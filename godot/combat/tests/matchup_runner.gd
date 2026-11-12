extends RefCounted
## Headless AI-vs-AI fights for balance measurement (used by test_matchups.gd, test_king.gd and
## tools/balance_matrix.gd). Everything goes through the real CombatInput channel; the King is allowed through the
## experimental start option. Deterministic: (roles, configs, seed) -> the same fight every time.
##
## IMPORTANT honesty note: results are BOT-measured (CombatAI styles). They say what a scripted opponent can
## achieve, not what a human would; they are a regression and sanity signal, not a human balance verdict.

const BASELINE := {"style": "balanced", "skill": 0.6}   # "the default AI" every class must be beatable against
const STYLES := ["duelist", "patient", "aggressive", "defensive", "evasive", "ability", "balanced"]
const SKILLS := [0.6, 0.9]


## Plays ONE fight. `a_cfg` / `b_cfg`: {"style": String, "skill": float}. Seat and attacker colour alternate with the
## seed so neither side keeps a positional advantage. Returns {winner: "a"|"b", reason, ticks, a_hp, b_hp, timeout}.
static func fight(tree: SceneTree, a_role: String, b_role: String, a_cfg: Dictionary, b_cfg: Dictionary,
		seed_value: int) -> Dictionary:
	var a_white := seed_value % 2 == 0
	var white_role := a_role if a_white else b_role
	var black_role := b_role if a_white else a_role
	var white_cfg := a_cfg if a_white else b_cfg
	var black_cfg := b_cfg if a_white else a_cfg
	var attacker := "w" if (seed_value / 2) % 2 == 0 else "b"
	var sim := CombatSimulation.new()
	tree.root.add_child(sim)
	var battle_id := "mx-%d" % seed_value
	var request := FighterRoster.build_request(white_role, black_role, attacker, battle_id, seed_value, 0)
	var started: Dictionary = sim.start(request, {"allow_experimental_roles": true})
	if not started["ok"]:
		sim.get_parent().remove_child(sim)
		sim.queue_free()
		return {"error": str(started), "winner": "none", "reason": "error", "ticks": 0, "timeout": false}
	await tree.physics_frame
	var white_builder := CombatInputBuilder.new(request["matchId"], battle_id, "player-white")
	var black_builder := CombatInputBuilder.new(request["matchId"], battle_id, "player-black")
	var ai_white := CombatAI.new(white_builder, FighterRoster.stats_for(white_role), FighterRoster.stats_for(black_role),
			seed_value * 2 + 1, float(white_cfg["skill"]), String(white_cfg["style"]))
	var ai_black := CombatAI.new(black_builder, FighterRoster.stats_for(black_role), FighterRoster.stats_for(white_role),
			seed_value * 2 + 2, float(black_cfg["skill"]), String(black_cfg["style"]))
	var guard := 0
	while sim.is_running() and guard < 6000:
		var snap := sim.snapshot(false)
		sim.submit_input(ai_white.think(snap))
		sim.submit_input(ai_black.think(snap))
		sim.step_tick()
		guard += 1
	var result: Dictionary = sim.result.duplicate(true)
	var out := {"winner": "none", "reason": "unfinished", "ticks": guard, "timeout": false, "a_hp": 0, "b_hp": 0}
	if not result.is_empty():
		var winner_white: bool = result["winnerPlayerId"] == "player-white"
		var a_won := winner_white == a_white
		out["winner"] = "a" if a_won else "b"
		out["reason"] = String(result["reason"])
		out["timeout"] = String(result["reason"]).begins_with("timeout")
		var white_hp := sim.fighters[0].health.current
		var black_hp := sim.fighters[1].health.current
		out["a_hp"] = white_hp if a_white else black_hp
		out["b_hp"] = black_hp if a_white else white_hp
	out["final"] = JSON.stringify(sim.snapshot(), "", true, true)
	out["result"] = result
	out["events"] = sim._next_event_id - 1
	sim.stop()
	sim.get_parent().remove_child(sim)
	sim.queue_free()
	return out


## Win count of config `a_cfg` (as role A) against `b_cfg` over seeds base..base+n-1, stopping early once `need` wins
## are reached (need <= 0 plays everything). Returns {wins, played, timeouts, ticks}.
static func series(tree: SceneTree, a_role: String, b_role: String, a_cfg: Dictionary, b_cfg: Dictionary,
		n: int, base_seed: int, need: int = 0) -> Dictionary:
	var wins := 0
	var timeouts := 0
	var ticks := 0
	var played := 0
	for i in n:
		var r: Dictionary = await fight(tree, a_role, b_role, a_cfg, b_cfg, base_seed + i)
		played += 1
		ticks += int(r["ticks"])
		if r["timeout"]:
			timeouts += 1
		if r["winner"] == "a":
			wins += 1
		if need > 0 and wins >= need:
			break
		# cannot reach `need` any more
		if need > 0 and wins + (n - played) < need:
			break
	return {"wins": wins, "played": played, "timeouts": timeouts, "ticks": ticks}


## Searches the style/skill family of role A for a config that beats the baseline AI of role B in at least half of
## `n` seeded fights. Returns {ok, best: {style, skill, wins, played}, tried: [...]}. Early-exits on the first hit.
static func winnable(tree: SceneTree, a_role: String, b_role: String, n: int, base_seed: int) -> Dictionary:
	var need := (n + 1) / 2
	var tried: Array = []
	var best := {"style": "", "skill": 0.0, "wins": -1, "played": 0}
	for skill in SKILLS:
		for style in STYLES:
			var cfg := {"style": style, "skill": skill}
			var s: Dictionary = await series(tree, a_role, b_role, cfg, BASELINE, n, base_seed, need)
			var entry := {"style": style, "skill": skill, "wins": s["wins"], "played": s["played"], "timeouts": s["timeouts"]}
			tried.append(entry)
			if int(s["wins"]) > int(best["wins"]):
				best = entry
			if int(s["wins"]) >= need:
				return {"ok": true, "best": entry, "tried": tried}
	return {"ok": false, "best": best, "tried": tried}


## A test rig (see test_support.gd) whose battle may include the experimental King. Same behaviour as
## Support.make_rig otherwise: every action goes through the real CombatInput channel.
static func make_rig(tree: SceneTree, white_role: String, black_role: String, attacker: String = "w",
		start_tick: int = 0, battle_id: String = "t-1"):
	var Support = preload("res://combat/tests/test_support.gd")
	var rig = Support.Rig.new()
	rig.tree = tree
	rig.sim = CombatSimulation.new()
	tree.root.add_child(rig.sim)
	var request := FighterRoster.build_request(white_role, black_role, attacker, battle_id, 7, start_tick)
	var reply: Dictionary = rig.sim.start(request, {"allow_experimental_roles": true})
	assert(reply["ok"], "rig start failed: %s" % str(reply))
	await tree.physics_frame
	rig.w = Support.Seat.new()
	rig.w.builder = CombatInputBuilder.new(request["matchId"], battle_id, "player-white")
	rig.w.yaw = 0.0
	rig.b = Support.Seat.new()
	rig.b.builder = CombatInputBuilder.new(request["matchId"], battle_id, "player-black")
	rig.b.yaw = PI
	return rig
