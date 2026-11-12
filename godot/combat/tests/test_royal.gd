extends RefCounted
## battle-royal-v1 combat support: the optional King start state (HP / stamina / cooldown), its validation, the carry-over from
## one duel into the next through the REAL simulation with CombatAI bots, determinism, and one end-to-end last stand played
## on the chess layer (BattleRoyalMatch) with real CombatSimulation fights.
##
## The default CombatSimulation.start(request) behaviour is covered by every other suite and must not change: this suite
## also pins that the new options are inert unless given.

const Runner := preload("res://combat/tests/royal_runner.gd")
const RoyalMatch := preload("res://chess/battle_royal_match.gd")
const S := CombatConstants.State
const MATE_BOTH := "R3k3/3p1p2/8/8/8/8/8/4R1K1 b - - 0 1" # double check by Re1 and Ra8, black king boxed in
const MATE_ONE := "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1" # Ra8# next (single checker)


static func run(h, tree: SceneTree) -> void:
	_options(h, tree)
	_validation(h, tree)
	await _ability_and_exhaustion(h, tree)
	await _carry_over(h, tree)
	await _determinism(h, tree)
	await _chess_level(h, tree)


static func _king_request(king_color: String = "w", checker: String = "p", battle_id: String = "royal-t") -> Dictionary:
	var white := "k" if king_color == "w" else checker
	var black := checker if king_color == "w" else "k"
	return FighterRoster.build_request(white, black, king_color, battle_id, 11, 0)


static func _sim(tree: SceneTree) -> CombatSimulation:
	var sim := CombatSimulation.new()
	tree.root.add_child(sim)
	return sim


static func _drop(sim: CombatSimulation) -> void:
	sim.stop()
	sim.get_parent().remove_child(sim)
	sim.queue_free()


static func _fighter(sim: CombatSimulation, role: String) -> FighterController:
	for f in sim.fighters:
		if f.role == role:
			return f
	return null


# ---- start options ------------------------------------------------------------------------------------------------------
static func _options(h, tree: SceneTree) -> void:
	h.begin("royal: initial_* options set the King's HP/stamina/cooldown, nothing else")
	var request := _king_request("w", "n")
	var sim := _sim(tree)
	var reply: Dictionary = sim.start(request, {"allow_experimental_roles": true, "initial_hp": 57, "initial_stamina": 31.25, "initial_cooldown": 222})
	h.check(reply["ok"], "start with a full option set succeeds: %s" % str(reply))
	var king := _fighter(sim, "k")
	var knight := _fighter(sim, "n")
	h.eq(king.health.current, 57, "King HP starts at initial_hp")
	h.eq(king.health.maximum, 160, "King max HP is untouched (timeout percentages stay relative to the real maximum)")
	h.near(king.stamina.current, 31.25, 0.0001, "King stamina starts at initial_stamina")
	h.eq(king.stamina.maximum, 100.0, "King max stamina untouched")
	h.eq(king.ability.cooldown_remaining, 222, "ability cooldown starts at initial_cooldown")
	h.eq(king.ability.cooldown_total, 600, "ability cooldown_total untouched")
	h.check(not king.stamina.exhausted, "positive stamina is not exhausted")
	h.eq(knight.health.current, 125, "the opponent keeps full HP")
	h.near(knight.stamina.current, 110.0, 0.0001, "the opponent keeps full stamina")
	h.eq(knight.ability.cooldown_remaining, 0, "the opponent's ability is ready")
	var snap: Dictionary = sim.snapshot()
	var king_snap: Dictionary = snap["fighters"][0 if king.color == "w" else 1]
	h.eq(king_snap["hp"], 57, "snapshot reports the carried HP")
	h.near(float(king_snap["stamina"]), 31.25, 0.0001, "snapshot reports the carried stamina")
	h.eq(king_snap["cooldownTicks"], 222, "snapshot reports the carried cooldown")
	h.check(sim.phase == CombatSimulation.Phase.COUNTDOWN and sim.countdown_remaining == 180, "the battle still opens with the 180-tick countdown")
	var state: Dictionary = sim.fighter_state(king.player_id)
	h.check(state == {"hp": 57, "stamina": 31.25, "cooldownTicks": 222}, "fighter_state mirrors the start state: %s" % str(state))
	h.eq(sim.fighter_state("nobody"), {}, "fighter_state of an unknown seat is empty")
	_drop(sim)

	h.begin("royal: without options the King starts exactly as before (full HP, full stamina, ready)")
	sim = _sim(tree)
	h.check(sim.start(request, {"allow_experimental_roles": true})["ok"], "the opt-in king start is unchanged")
	king = _fighter(sim, "k")
	h.check(king.health.current == 160 and is_equal_approx(king.stamina.current, 100.0) and king.ability.cooldown_remaining == 0, "full HP, stamina, ready ability")
	_drop(sim)
	sim = _sim(tree)
	h.check(sim.start(FighterRoster.build_request("q", "n", "w", "plain", 3, 0))["ok"], "a plain v1 battle is unchanged")
	h.check(not sim.start(request)["ok"], "the strict default still refuses a king request")
	_drop(sim)

	h.begin("royal: partial options and the boundary values")
	for case in [
		[{"initial_hp": 1}, 1, 100.0, 0], [{"initial_hp": 160}, 160, 100.0, 0], [{"initial_stamina": 0.0}, 160, 0.0, 0],
		[{"initial_stamina": 100}, 160, 100.0, 0], [{"initial_cooldown": 600}, 160, 100.0, 600], [{"initial_cooldown": 0}, 160, 100.0, 0],
	]:
		sim = _sim(tree)
		var options: Dictionary = case[0].duplicate()
		options["allow_experimental_roles"] = true
		h.check(sim.start(request, options)["ok"], "accepted: %s" % str(case[0]))
		king = _fighter(sim, "k")
		h.check(king.health.current == case[1] and is_equal_approx(king.stamina.current, case[2]) and king.ability.cooldown_remaining == case[3], "applied exactly: %s" % str(case[0]))
		_drop(sim)
	sim = _sim(tree)
	sim.start(request, {"allow_experimental_roles": true, "initial_stamina": 0})
	h.check(_fighter(sim, "k").stamina.exhausted, "zero stamina starts exhausted (cannot spend until it recovers)")
	_drop(sim)


static func _validation(h, tree: SceneTree) -> void:
	h.begin("royal: bad or misplaced initial_* options are refused and leave nothing running")
	var request := _king_request("b", "r")
	var bad := [
		["hp zero", {"initial_hp": 0}], ["hp above max", {"initial_hp": 161}], ["hp fractional", {"initial_hp": 50.5}], ["hp string", {"initial_hp": "50"}],
		["stamina negative", {"initial_stamina": -0.1}], ["stamina above max", {"initial_stamina": 100.5}], ["stamina nan", {"initial_stamina": NAN}],
		["stamina inf", {"initial_stamina": INF}], ["stamina string", {"initial_stamina": "full"}],
		["cooldown negative", {"initial_cooldown": -1}], ["cooldown above total", {"initial_cooldown": 601}], ["cooldown float", {"initial_cooldown": 3.5}],
	]
	for case in bad:
		var sim := _sim(tree)
		var options: Dictionary = case[1].duplicate()
		options["allow_experimental_roles"] = true
		var reply: Dictionary = sim.start(request, options)
		h.check(not reply["ok"] and reply["code"] == "INVALID_PAYLOAD", "%s refused with INVALID_PAYLOAD" % case[0])
		h.check(not sim.is_running() and sim.fighters.is_empty(), "%s leaves no running battle" % case[0])
		_drop(sim)
	var sim := _sim(tree)
	h.check(not sim.start(request, {"initial_hp": 50})["ok"], "initial_* without the experimental flag is refused")
	_drop(sim)
	sim = _sim(tree)
	var no_king: Dictionary = sim.start(FighterRoster.build_request("q", "n", "w", "nk", 1, 0), {"allow_experimental_roles": true, "initial_hp": 50})
	h.check(not no_king["ok"] and no_king["code"] == "INVALID_PAYLOAD", "initial_* without a King seat is refused (they never touch ordinary roles)")
	_drop(sim)
	sim = _sim(tree)
	h.check(sim.start(request, {"allow_experimental_roles": true, "initial_hp": 50})["ok"], "a valid start after the refusals still works")
	h.check(not sim.start(request, {"allow_experimental_roles": true, "initial_hp": 50})["ok"], "a second start while running is refused as before")
	_drop(sim)


# ---- the carried values matter in the fight ------------------------------------------------------------------------------
static func _ability_and_exhaustion(h, tree: SceneTree) -> void:
	h.begin("royal: a carried cooldown blocks Royal Counter, a carried zero stamina blocks every spend")
	for cooldown in [0, 300]:
		var rig = await _rig(tree, {"initial_cooldown": cooldown})
		rig.face_off(3.0)
		rig.to_live()
		rig.w.press("ability") # the King is the white seat here
		var cast := false
		for step in 30:
			rig.tick()
			cast = cast or rig.white().sm.state == S.ABILITY_CASTING
		h.check(cast == (cooldown == 0), "cooldown %d: Royal Counter %s" % [cooldown, "casts" if cooldown == 0 else "is refused"])
		rig.dispose()
	var rig = await _rig(tree, {"initial_stamina": 0.0})
	rig.face_off(1.4)
	rig.to_live()
	var before: float = rig.white().stamina.current
	rig.w.press("light")
	for step in 20:
		rig.tick()
	h.check(rig.white().sm.state != S.ATTACKING and before == 0.0, "an exhausted King cannot start an attack at once")
	h.check(rig.white().stamina.current >= 0.0, "stamina never goes negative")
	rig.dispose()
	rig = await _rig(tree, {"initial_hp": 1})
	rig.face_off(1.4)
	rig.to_live()
	rig.b.press("light")
	var fallen := false
	for step in 120:
		rig.tick()
		fallen = fallen or not rig.sim.is_running()
	h.check(fallen and rig.sim.result["outcome"] == "defender" and rig.sim.result["attackerHp"] == 0, "a 1 HP King falls to the first clean hit (the carried HP is real)")
	h.eq(rig.sim.result["reason"], "knockout", "reported as a knockout")
	rig.dispose()


static func _rig(tree: SceneTree, extra: Dictionary):
	var Support = preload("res://combat/tests/test_support.gd")
	var rig = Support.Rig.new()
	rig.tree = tree
	rig.sim = CombatSimulation.new()
	tree.root.add_child(rig.sim)
	var request := FighterRoster.build_request("k", "p", "w", "royal-rig", 7, 0)
	var options := {"allow_experimental_roles": true}
	options.merge(extra, true)
	var reply: Dictionary = rig.sim.start(request, options)
	assert(reply["ok"], "rig start failed: %s" % str(reply))
	await tree.physics_frame
	rig.w = Support.Seat.new()
	rig.w.builder = CombatInputBuilder.new(request["matchId"], "royal-rig", "player-white")
	rig.w.yaw = 0.0
	rig.b = Support.Seat.new()
	rig.b.builder = CombatInputBuilder.new(request["matchId"], "royal-rig", "player-black")
	rig.b.yaw = PI
	return rig


# ---- carry-over through real AI fights ------------------------------------------------------------------------------------
static func _carry_over(h, tree: SceneTree) -> void:
	h.begin("royal: HP, stamina and cooldown carry from one real duel into the next; the checkers start fresh")
	var king_cfg := {"style": "duelist", "skill": 0.9}
	var first_state := {}
	var checked := 0
	for color in ["w", "b"]:
		var roles := ["p", "n"]
		var king := {"hp": 160, "stamina": 100.0, "cooldownTicks": 0}
		for i in roles.size():
			var request := FighterRoster.build_request("k" if color == "w" else roles[i], roles[i] if color == "w" else "k", color, "carry-%s-%d" % [color, i], 31 + i, 0)
			var options := {"allow_experimental_roles": true, "initial_hp": king["hp"], "initial_stamina": king["stamina"], "initial_cooldown": king["cooldownTicks"]}
			var collector := Collector.new()
			var played: Dictionary = await Runner.play(tree, request, options, king_cfg, Runner.BASELINE, collector.add)
			h.check(played["ok"], "duel %d starts" % i)
			if not played["ok"]:
				continue
			var snap0: Dictionary = collector.first
			var king_seat: Dictionary = snap0["fighters"][0 if color == "w" else 1]
			var other: Dictionary = snap0["fighters"][1 if color == "w" else 0]
			h.check(king_seat["hp"] == king["hp"] and is_equal_approx(float(king_seat["stamina"]), king["stamina"]) and king_seat["cooldownTicks"] == king["cooldownTicks"], "duel %d (%s) opens with the carried King state %s" % [i, color, str(king)])
			h.eq(other["hp"], int(request["defender"]["stats"]["maxHp"]), "duel %d: the checker starts at full HP" % i)
			var sim: CombatSimulation = played["sim"]
			var result: Dictionary = played["result"]
			var end: Dictionary = sim.fighter_state(request["attacker"]["playerId"])
			h.eq(end["hp"], int(result["attackerHp"]), "duel %d: fighter_state HP equals the BattleResult attackerHp" % i)
			h.check(end["stamina"] >= 0.0 and end["stamina"] <= 100.0 and end["cooldownTicks"] >= 0 and end["cooldownTicks"] <= 600, "duel %d: end state within bounds" % i)
			h.check(float(snappedf(end["stamina"], 0.01)) == end["stamina"], "duel %d: stamina is reported on the 0.01 grid snapshots use" % i)
			if i == 0:
				first_state = end
				h.check(end["hp"] <= 160, "the first duel cannot raise HP")
			checked += 1
			var won: bool = result["outcome"] == "attacker" and end["hp"] > 0
			Runner.dispose(sim)
			if not won:
				break
			king = {"hp": end["hp"], "stamina": end["stamina"], "cooldownTicks": end["cooldownTicks"]}
	h.check(checked >= 2, "at least two duels were played across the colours (%d)" % checked)
	h.check(not first_state.is_empty(), "a first duel produced an end state")

	h.begin("royal: a full sequence helper reports the carried state and stops at the first defeat")
	var seq: Dictionary = await Runner.sequence(tree, "w", ["p", "p"], {"style": "duelist", "skill": 0.9}, Runner.BASELINE, 4242)
	h.check(seq["duels"].size() >= 1 and seq["duels"].size() <= 2, "one or two duels were played")
	if seq["duels"].size() == 2:
		h.eq(seq["duels"][1]["hp_start"], seq["duels"][0]["hp_end"], "duel 2 starts at duel 1's end HP")
	h.check(seq["king_wins"] == (seq["duels"].size() == 2 and seq["duels"][1]["outcome"] == "attacker" and seq["duels"][1]["hp_end"] > 0), "king_wins matches the duel log")


static func _determinism(h, tree: SceneTree) -> void:
	h.begin("royal: a carried-state sequence is fully deterministic (same seed, same duels, same end state)")
	var cfg := {"style": "patient", "skill": 0.9}
	var a: Dictionary = await Runner.sequence(tree, "b", ["p", "n"], cfg, Runner.BASELINE, 909)
	var b: Dictionary = await Runner.sequence(tree, "b", ["p", "n"], cfg, Runner.BASELINE, 909)
	h.check(JSON.stringify(a) == JSON.stringify(b), "identical duel logs, HP/stamina/cooldown trails and end state")
	var c: Dictionary = await Runner.sequence(tree, "b", ["p", "n"], cfg, Runner.BASELINE, 910)
	h.check(JSON.stringify(a) != JSON.stringify(c), "a different seed plays differently (the comparison is not vacuous)")
	var low: Dictionary = await Runner.sequence(tree, "w", ["p"], cfg, Runner.BASELINE, 5)
	var request := _king_request("w", "p", "determinism")
	var sim := _sim(tree)
	sim.start(request, {"allow_experimental_roles": true})
	var fresh_json := JSON.stringify(sim.snapshot(), "", true, true)
	_drop(sim)
	sim = _sim(tree)
	sim.start(request, {"allow_experimental_roles": true, "initial_hp": 160, "initial_stamina": 100.0, "initial_cooldown": 0})
	h.check(JSON.stringify(sim.snapshot(), "", true, true) == fresh_json, "options equal to the defaults give the identical opening snapshot")
	_drop(sim)
	h.check(low["duels"].size() == 1, "a single-checker sequence plays exactly one duel")


# ---- chess level: BattleRoyalMatch + real simulation ---------------------------------------------------------------------
class RealAuthority extends RefCounted:
	var sim: CombatSimulation

	func fighter_state(player_id: String) -> Dictionary:
		return sim.fighter_state(player_id)


class Collector extends RefCounted:
	var first: Dictionary = {}

	func add(snapshot: Dictionary) -> void:
		if first.is_empty():
			first = snapshot


## Feeds every snapshot of a running fight to the match, which validates it against the frozen duel (including the
## carried King values during the countdown).
class Feeder extends RefCounted:
	var game
	var authority: Object
	var ok := true
	var count := 0

	func feed(snapshot: Dictionary) -> void:
		count += 1
		ok = ok and game.accept_snapshot(snapshot, authority)


## Plays every pending duel of `game` with a real CombatSimulation and bots. Returns the number of duels played.
static func _play_last_stand(h, tree: SceneTree, game, king_cfg: Dictionary, checker_cfg: Dictionary, label: String) -> int:
	var played := 0
	var guard := 0
	while game.royal_active() and guard < 8:
		guard += 1
		var request: Dictionary = game.pending_request()
		var options: Dictionary = game.combat_options()
		var authority := RealAuthority.new()
		game.bind_combat_authority(authority)
		var feeder := Feeder.new()
		feeder.game = game
		feeder.authority = authority
		var run: Dictionary = await Runner.play(tree, request, options, king_cfg, checker_cfg, feeder.feed)
		h.check(run["ok"], "%s: duel %d starts with the match's own request and options" % [label, played])
		if not run["ok"]:
			game.bind_combat_authority(null)
			break
		var sim: CombatSimulation = run["sim"]
		authority.sim = sim
		# The match validates every snapshot of the fight (including the countdown values of the carried King).
		h.check(feeder.count > 10 and feeder.ok, "%s: every snapshot of duel %d (%d) is accepted by the match" % [label, played, feeder.count])
		var accepted: Dictionary = game.accept_result(run["result"], authority)
		h.check(accepted["ok"], "%s: the trusted result of duel %d is accepted" % [label, played])
		var committed: Dictionary = game.commit_battle()
		h.check(committed["ok"], "%s: duel %d commits" % [label, played])
		played += 1
		Runner.dispose(sim)
		game.bind_combat_authority(null)
	return played


static func _chess_level(h, tree: SceneTree) -> void:
	h.begin("royal: end-to-end last stand on the chess layer with real simulation fights")
	var outcomes := {"king_survived": 0, "king_fell": 0}
	var configs := [
		["pawn checker, skilled king", MATE_ONE, {"style": "duelist", "skill": 0.9}, 4],
		["double check, balanced king", MATE_BOTH, {"style": "balanced", "skill": 0.6}, 2],
	]
	for scenario in configs:
		var game = RoyalMatch.new()
		var begun: Array = []
		game.sequence_started.connect(func(info): begun.append(info))
		var finished: Array = []
		game.sequence_finished.connect(func(summary): finished.append(summary))
		var duels: Array = []
		game.duel_finished.connect(func(index, total, summary): duels.append([index, total, summary]))
		h.check(game.new_game(0, 0, scenario[1]).ok, "%s: position loads" % scenario[0])
		if scenario[1] == MATE_ONE:
			h.check(game.play("a1", "a8").ok, "%s: the mating move is accepted" % scenario[0])
		h.check(game.royal_active() and game.phase == "combat", "%s: checkmate opens a last stand instead of ending the game" % scenario[0])
		h.check(game.royal_codec.valid("RoyalMatchState", game.match_state()), "%s: the pending state is a valid RoyalMatchState" % scenario[0])
		var fen_before: String = game.engine.fen()
		var n := await _play_last_stand(h, tree, game, scenario[2], {"style": "balanced", "skill": 0.6}, scenario[0])
		h.check(not game.royal_active() and begun.size() == 1 and finished.size() == 1, "%s: exactly one sequence ran to its end" % scenario[0])
		h.check(duels.size() == n and n >= 1, "%s: a duel_finished signal per duel (%d)" % [scenario[0], n])
		if finished.is_empty():
			continue
		var summary: Dictionary = finished[0]
		outcomes[summary["outcome"]] += 1
		h.check(game.royal_codec.valid("RoyalSequenceResult", summary) and game.royal_codec.valid("RoyalMatchState", game.match_state()), "%s: result and final state satisfy the royal contract" % scenario[0])
		h.check(summary["duels"].size() == n, "%s: the result lists every duel" % scenario[0])
		for i in range(1, summary["duels"].size()):
			h.eq(summary["duels"][i]["kingEnd"]["hp"] <= summary["duels"][i - 1]["kingEnd"]["hp"], true, "%s: King HP never rises between duels" % scenario[0])
		if summary["outcome"] == "king_fell":
			h.check(game.engine.result == "1-0" or game.engine.result == "0-1", "%s: a fallen King means checkmate for the other side" % scenario[0])
			h.eq(game.engine.reason, "Checkmate", "%s: reported as Checkmate" % scenario[0])
			h.eq(game.engine.fen(), fen_before, "%s: the board is untouched when the King falls" % scenario[0])
		else:
			h.check(game.engine.fen() != fen_before, "%s: the board changed when the King survived" % scenario[0])
			h.check(summary["defeated"].size() == (2 if scenario[1] == MATE_BOTH else 1), "%s: every checker was defeated" % scenario[0])
			for piece_id in summary["defeated"]:
				h.check(piece_id not in game.registry.values(), "%s: defeated %s left the board" % [scenario[0], piece_id])
	h.check(outcomes["king_survived"] + outcomes["king_fell"] == 2, "both end-to-end sequences ended (%s)" % str(outcomes))
