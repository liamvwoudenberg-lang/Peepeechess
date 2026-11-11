extends RefCounted
## Client movement prediction is exact for EVERY role, not just Pawn/Knight.
##
## Two layers:
##   1. "bare": the pure predictor (net/movement_predictor.gd) against the authoritative CombatSimulation, tick by tick,
##      for all six roles (the experimental King through the opt-in start option) over scripted free-state inputs
##      (walk, strafe, sprint, block, lock-on, wall, pillar, opponent body, movement buffs). No network involved.
##   2. "networked": the real CombatNetServer + CombatNetClient through the lockstep harness at 0/50/100/150 ms RTT, with
##      and without packet loss, for every v1 role (the King is not a v1 combatant and cannot be hosted by the v1 server).
## Convention as in test_net_latency.gd: "N ms" = round trip N ms; channels are integer ticks split up/down.

const Harness := preload("res://combat/net/net_harness.gd")
const Bot := preload("res://combat/net/net_bot.gd")
const Predictor := preload("res://combat/net/movement_predictor.gd")
const Runner := preload("res://combat/tests/matchup_runner.gd")
const Latency := preload("res://combat/tests/test_net_latency.gd")

const ROLES: Array = ["p", "n", "b", "r", "q", "k"]
const OPPONENT := {"p": "n", "n": "p", "b": "r", "r": "q", "q": "b", "k": "p"}
const LIVE := 180


static func run(h, tree: SceneTree) -> void:
	print("  predictor vs authority, scripted free-state inputs (positions in metres, error = distance to the server):")
	for role in ROLES:
		await _bare_role(h, tree, role)
	await _bare_buffs(h, tree)
	await _bare_opponent_contact(h, tree)
	print("  networked prediction error (reconciliation correction, metres), walker bot, 900 live ticks:")
	print("    role  latency   loss  n    mean     p95      max     hard_snaps")
	await _networked(h, tree)
	await _networked_buff(h, tree)


# ---- scripted inputs --------------------------------------------------------------------------------
## Deterministic intent for scripted tick `i` (segments of 20..70 ticks: headings, sprint bursts, block, stand-still).
## `leash` > 0 steers back to the middle when farther from it, keeping the run away from walls and pillars.
static func _intent(i: int, rng: RandomNumberGenerator, state: Dictionary, pos: Vector3 = Vector3.ZERO, leash: float = 0.0) -> Dictionary:
	if leash > 0.0 and pos.length() > leash and not bool(state.get("returning", false)):
		state["hold"] = 0
		state["returning"] = true
	if int(state.get("hold", 0)) <= 0:
		state["heading"] = rng.randf_range(-PI, PI)
		state["hold"] = rng.randi_range(20, 70)
		var kind := rng.randi_range(0, 5)
		state["sprint"] = kind == 1 or kind == 2
		state["block"] = kind == 3
		state["stand"] = kind == 4
		state["lock"] = rng.randf() < 0.4
		if bool(state.get("returning", false)):
			state["heading"] = CombatConstants.yaw_of(CombatConstants.flat(-pos))
			state["stand"] = false
			state["hold"] = 25
			state["returning"] = false
	state["hold"] = int(state["hold"]) - 1
	var dir := CombatConstants.heading(float(state["heading"]))
	if bool(state["stand"]):
		dir = Vector3.ZERO
	return {"move_x": dir.x, "move_z": dir.z, "yaw": float(state["heading"]), "lock": bool(state["lock"]),
			"sprint": bool(state["sprint"]), "block": bool(state["block"])}


static func _fighter_state(snap: Dictionary, player_id: String) -> Dictionary:
	for f in snap["fighters"]:
		if f["playerId"] == player_id:
			return f
	return {}


static func _pos(f: Dictionary) -> Vector3:
	return Vector3(f["position"]["x"], 0.0, f["position"]["z"])


static func _rebase(params: Dictionary, f: Dictionary, previous: Dictionary = {}, max_stamina: float = 100.0) -> Dictionary:
	var stamina := float(f["stamina"])
	var s := Predictor.initial(_pos(f), float(f["yawRadians"]), stamina, Predictor.buff_remaining(params, int(f["cooldownTicks"])))
	s["vel"] = Vector3(f["velocity"]["x"], 0.0, f["velocity"]["z"])
	s["exhausted"] = (bool(previous.get("exhausted", false)) and stamina < max_stamina * StaminaComponent.RECOVER_FRACTION) or stamina <= 0.0
	return s


## Plays `ticks` live ticks for the white fighter with scripted intents against an idle opponent and, in parallel, three
## predictors: re-based from the authoritative snapshot every tick, every 12 ticks (what a 100 ms RTT client does) and
## once per 150 ticks (free-running). Returns the error series of each.
static func _drive(tree: SceneTree, role: String, opponent_role: String, ticks: int, seed_value: int, prepare: Callable = Callable(),
		script: Callable = Callable(), leash: float = 0.0) -> Dictionary:
	var rig = await Runner.make_rig(tree, role, opponent_role, "w", 0, "roles-%s" % role)
	rig.w.autosend = false
	rig.place(Vector3(-1.0, 0.0, -1.0), Vector3(5.2, 0.0, 0.6))
	if prepare.is_valid():
		prepare.call(rig)
	rig.to_live()
	var request: Dictionary = rig.sim.request
	var me: Dictionary = request["attacker"] if request["attacker"]["playerId"] == "player-white" else request["defender"]
	var params := Predictor.params_for(role, me["stats"])
	var max_stamina := float(me["stats"]["maxStamina"])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var scripted := {}
	var snap: Dictionary = rig.sim.snapshot()
	var truth_pos := _pos(_fighter_state(snap, "player-white"))
	var opp_state := {"pos": _pos(_fighter_state(snap, "player-black")), "radius": float(FighterProfile.for_role(opponent_role)["radius"]), "alive": true}
	var each := _rebase(params, _fighter_state(snap, "player-white"), {}, max_stamina)
	var window := each.duplicate()
	var free := each.duplicate()
	var errs := {"each": [], "window": [], "free": [], "states": []}
	for i in ticks:
		var intent: Dictionary = script.call(i, rig) if script.is_valid() else _intent(i, rng, scripted, truth_pos, leash)
		rig.w.move = Vector2(intent["move_x"], intent["move_z"])
		rig.w.yaw = intent["yaw"]
		rig.w.lock = intent["lock"]
		rig.w.sprint = intent["sprint"]
		rig.w.block = intent["block"]
		var reply: Dictionary = rig.sim.submit_input(rig.w.packet())
		if not reply["ok"]:
			rig.submit_errors.append(reply)
		# opponent keeps sending neutral packets (b.autosend) through the rig's own submit below
		rig.sim.submit_input(rig.b.packet())
		rig.sim.step_tick()
		snap = rig.sim.snapshot()
		var mine := _fighter_state(snap, "player-white")
		var state_name := String(mine["state"])
		var free_state := state_name in ["Idle", "Moving", "Blocking"]
		# predictors advance one tick with this tick's intent
		each = Predictor.step(each, intent, params, opp_state)
		window = Predictor.step(window, intent, params, opp_state)
		free = Predictor.step(free, intent, params, opp_state)
		var truth := _pos(mine)
		truth_pos = truth
		if free_state:
			errs["each"].append(truth.distance_to(each["pos"]))
			errs["window"].append(truth.distance_to(window["pos"]))
			errs["free"].append(truth.distance_to(free["pos"]))
		errs["states"].append(state_name)
		# re-base like the client does after a snapshot
		each = _rebase(params, mine, each, max_stamina)
		if i % 12 == 11:
			window = _rebase(params, mine, window, max_stamina)
		if i % 150 == 149:
			free = _rebase(params, mine, free, max_stamina)
	rig.dispose()
	return errs


static func _max(values: Array) -> float:
	var out := 0.0
	for v in values:
		out = maxf(out, float(v))
	return out


# ---- (1) bare predictor vs authority, every role ------------------------------------------------------
static func _bare_role(h, tree: SceneTree, role: String) -> void:
	h.begin("predictor is exact vs the server: role %s" % role)
	# (a) open floor: nothing but the role's own movement profile is being tested
	var open: Dictionary = await _drive(tree, role, OPPONENT[role], 900, 100 + ROLES.find(role), Callable(), Callable(), 3.0)
	# (b) the whole arena including wall and pillar contact (engine capsule-vs-box collision vs the analytic model)
	var errs: Dictionary = await _drive(tree, role, OPPONENT[role], 900, 100 + ROLES.find(role))
	var moving := (open["states"] as Array).count("Moving") + (errs["states"] as Array).count("Moving")
	print("    %-4s  open floor: 1-tick max %.5f  12-tick max %.5f  150-tick max %.5f | with walls: 1-tick max %.5f  12-tick max %.5f (mean %.5f)  150-tick max %.5f"
			% [role, _max(open["each"]), _max(open["window"]), _max(open["free"]), _max(errs["each"]), _max(errs["window"]), Latency._mean(errs["window"]), _max(errs["free"])])
	h.check(moving > 600, "the scripted runs really moved (%d Moving ticks)" % moving)
	# Open floor: exact up to the 0.0001 m snapshot quantisation (this is where a wrong movement profile would show).
	h.check(_max(open["each"]) < 0.001, "open floor one-tick error %.5f m < 0.001 m (per-role movement profile applied)" % _max(open["each"]))
	h.check(_max(open["window"]) < 0.003, "open floor 12-tick window error %.5f m < 0.003 m" % _max(open["window"]))
	h.check(_max(open["free"]) < 0.01, "open floor 150-tick free-running error %.5f m < 0.01 m" % _max(open["free"]))
	# Walls: the engine's box colliders and the analytic polygon differ at the 24 vertices (centimetres, documented).
	h.check(_max(errs["each"]) < 0.006, "with wall contact one-tick error %.5f m < 0.006 m" % _max(errs["each"]))
	h.check(_max(errs["window"]) < 0.04, "with wall contact 12-tick window error %.5f m < 0.04 m" % _max(errs["window"]))
	h.check(_max(errs["free"]) < 0.15, "with wall contact 150-tick free-running error %.5f m < 0.15 m" % _max(errs["free"]))


## Walking-speed buffs: the predictor models Last Stand (1.3x), Royal Fury (1.1x) and Fortress Guard (0.7x) from the
## ability cooldown in the snapshot. Without that the error would be 0.3 x speed per tick.
static func _bare_buffs(h, tree: SceneTree) -> void:
	for role in ["p", "r", "q"]:
		h.begin("predictor models the %s movement buff" % role)
		var prepare := func(rig):
			rig.white().health.current = 20   # Last Stand needs <= 35% HP; harmless for the others
		var ability_tick := 6
		var script := func(i: int, rig) -> Dictionary:
			if i == ability_tick:
				rig.w.press("ability")
			var walking := i > ability_tick + 40
			var dir := CombatConstants.heading(0.8 + 0.01 * float(i / 40))
			return {"move_x": dir.x if walking else 0.0, "move_z": dir.z if walking else 0.0, "yaw": 0.8, "lock": false,
					"sprint": walking and (i / 90) % 2 == 1, "block": false}
		var errs: Dictionary = await _drive(tree, role, OPPONENT[role], 420, 200, prepare, script)
		var open_script := func(i: int, rig) -> Dictionary:
			var d: Dictionary = script.call(i, rig)
			# stay inside r < 3: turn around when the fighter gets far from the middle
			var p: Vector3 = rig.white().global_position
			if p.length() > 2.8:
				var back := CombatConstants.flat(-p).normalized()
				d["move_x"] = back.x
				d["move_z"] = back.z
				d["yaw"] = CombatConstants.yaw_of(back)
			return d
		var open: Dictionary = await _drive(tree, role, OPPONENT[role], 420, 200, prepare, open_script)
		var buffed := 0
		for s in errs["states"]:
			buffed += 1 if s == "AbilityCasting" else 0
		var each_max := _max(errs["each"])
		var window_max := _max(errs["window"])
		print("    %-4s  buff run: open floor 1-tick max %.5f 12-tick max %.5f | with walls 1-tick max %.5f, 12-tick max %.5f (%d ticks casting)" % [role, _max(open["each"]), _max(open["window"]), each_max, window_max, buffed])
		h.check(_max(open["each"]) < 0.001 and _max(open["window"]) < 0.003, "buffed open-floor prediction is exact (1-tick %.5f, 12-tick %.5f m)" % [_max(open["each"]), _max(open["window"])])
		h.check(buffed > 5, "the ability was really cast (%d casting ticks)" % buffed)
		h.check(each_max < 0.014, "buffed one-tick error %.5f m < 0.014 m (wall contact at sprint speed included)" % each_max)
		h.check(window_max < 0.09, "buffed 12-tick window error %.5f m < 0.09 m" % window_max)


## Opponent body contact and the wall: the predictor separates the fighters exactly like FighterMovement._separate.
static func _bare_opponent_contact(h, tree: SceneTree) -> void:
	for role in ["p", "r", "k"]:
		h.begin("predictor handles opponent body contact: %s" % role)
		var prepare := func(rig):
			rig.place(Vector3(0.0, 0.0, -2.0), Vector3(0.0, 0.0, 0.6))
		var script := func(i: int, _rig) -> Dictionary:
			# walk straight into the (stationary) opponent, slide off it, then into the wall
			var heading := 0.0 if i < 140 else (PI * 0.5 if i < 260 else PI * 0.9)
			var dir := CombatConstants.heading(heading)
			return {"move_x": dir.x, "move_z": dir.z, "yaw": heading, "lock": i < 100, "sprint": i % 120 > 60, "block": false}
		var errs: Dictionary = await _drive(tree, role, OPPONENT[role], 400, 300, prepare, script)
		var each_max := _max(errs["each"])
		print("    %-4s  contact run: one-tick max %.5f, 12-tick max %.5f" % [role, each_max, _max(errs["window"])])
		h.check(each_max < 0.004, "contact one-tick error %.5f m < 0.004 m" % each_max)


# ---- (2) networked, every v1 role ---------------------------------------------------------------------
static func _networked(h, tree: SceneTree) -> void:
	for role in ["p", "n", "b", "r", "q"]:
		for l in Latency.LATENCIES:
			await _net_case(h, tree, role, l, 0.0, "")
		await _net_case(h, tree, role, Latency.LATENCIES[2], 0.05, "5% loss")


static func _net_case(h, tree: SceneTree, role: String, l: Dictionary, loss: float, tag: String) -> void:
	var label := "%s %s%s" % [role, l["name"], (" + " + tag) if tag != "" else ""]
	h.begin("networked prediction error: %s" % label)
	var net = await Latency._new(tree, Latency._cfg(l, {"seed": 4, "loss": loss}), [role, OPPONENT[role] if OPPONENT[role] != "k" else "p"], "roles-net", 9)
	net.place(Vector3(-1, 0, -1), Vector3(5.2, 0, 0.6))
	net.bots[0] = Bot.new("walker", 11)
	net.bots[0].leash = 5.0
	net.bots[1] = Bot.new("idle", 12)
	net.run(LIVE + 900)
	var c = net.clients[0]
	var mean: float = Latency._mean(c.corrections)
	var p95: float = Latency._p95(c.corrections)
	print("    %-4s  %-7s  %-5s %3d  %.4f   %.4f   %.4f   %d" % [role, l["name"], "%d%%" % int(loss * 100.0), c.corrections.size(), mean, p95, c.max_correction, c.stats["hard_snaps"]])
	h.check(c.corrections.size() > 60, "enough corrections measured (%d)" % c.corrections.size())
	h.check(mean < 0.01, "mean correction %.4f m < 0.01 m" % mean)
	h.check(p95 < (0.03 if loss == 0.0 else 0.08), "95th percentile %.4f m is small" % p95)
	h.check(c.max_correction < 0.3, "worst correction %.4f m < 0.3 m" % c.max_correction)
	h.eq(c.stats["hard_snaps"], 0, "no hard snaps in ordinary movement")
	if loss == 0.0:
		h.check(absf(net.server.rtt_ticks("player-white") - float(l["up"] + l["down"])) < 0.01, "the server's RTT estimate equals the configured RTT")
	net.dispose()


## A buffed fighter keeps the prediction error small over the network (Last Stand: +30% speed for 300 ticks).
static func _networked_buff(h, tree: SceneTree) -> void:
	for role in ["p", "r", "q"]:
		h.begin("networked prediction while buffed: %s at 100 ms" % role)
		var net = await Latency._new(tree, Latency._cfg(Latency.LATENCIES[2], {"seed": 5}), [role, "n"], "roles-buff", 9)
		net.place(Vector3(-1, 0, -1), Vector3(5.2, 0, 0.6))
		net.sim.fighters[0].health.current = 20
		var walker := Bot.new("walker", 17)
		walker.leash = 5.0
		var script := Bot.new("script", 1)
		script.hook = func(bot, client, tick):
			if tick == LIVE + 10:
				client.press("ability")
			walker.think(client, tick)
		net.bots[0] = script
		net.bots[1] = Bot.new("idle", 12)
		net.run(LIVE + 700)
		var c = net.clients[0]
		var activations: int = net.sim.fighters[0].ability.activations
		var mean: float = Latency._mean(c.corrections)
		print("    %-4s  buff @100ms  activations=%d  n=%d  mean %.4f  p95 %.4f  max %.4f  hard_snaps %d" % [role, activations, c.corrections.size(), mean, Latency._p95(c.corrections), c.max_correction, c.stats["hard_snaps"]])
		h.check(activations == 1, "the buff was cast once on the server (%d)" % activations)
		h.check(mean < 0.012, "mean correction while buffed %.4f m < 0.012 m" % mean)
		h.check(c.max_correction < 0.3 and c.stats["hard_snaps"] == 0, "no snap, worst correction %.4f m" % c.max_correction)
		net.dispose()
