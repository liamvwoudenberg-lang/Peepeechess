extends SceneTree
## Full Battle Chess games, bot vs bot, through the real BattleMetaMatch (persistent wounds, support, Resolve, comeback), to answer
## "do chess skill and fighting skill count equally?". Profile A = strong chess / weak fighter, profile B = weak chess / strong fighter;
## colours alternate with the game number. Prints win rates and the Resolve flow. BOT-measured, not a human claim.
##
##   godot --headless --path godot --script res://combat/tools/chess_vs_fight.gd -- games=12 seed=100 \
##       chess_a=5 fight_a=0.30 chess_b=2 fight_b=0.90 max_plies=120 shard=0/4 out=/tmp/cvf-0.json [verbose=1]
const Meta := preload("res://chess/battle_meta_match.gd")
const ENGINE := preload("res://chess/chess_engine.gd")
const FIGHT_STYLE := {"weak": "balanced", "strong": "duelist"}


class Authority extends Node:
	var sim: CombatSimulation
	func duel_summary() -> Dictionary:
		return sim.duel_summary()
	func fighter_state(player_id: String) -> Dictionary:
		return sim.fighter_state(player_id)


var totals := {"duels": 0, "resolve_gained": 0.0, "resolve_spent": 0.0, "second_winds": 0, "overcharges": 0, "resolve_dodges": 0, "whiffs": 0, "decisive": 0, "defender_wins": 0, "timeouts": 0, "fight_ticks": 0, "wounded_start": 0}


func _fight_cfg(skill: float, style: String = "") -> Dictionary:
	return {"skill": skill, "style": style if style != "" else ("duelist" if skill >= 0.7 else "balanced")}


func _run_duel(game, cfg: Dictionary, verbose: bool) -> void:
	var req: Dictionary = game.pending_request()
	var options: Dictionary = game.combat_options()
	var sim := CombatSimulation.new()
	root.add_child(sim)
	var started: Dictionary = sim.start(req, options)
	if not started["ok"]:
		push_error("duel did not start: %s" % str(started))
		quit(1)
		return
	await physics_frame
	var ais := {}
	for seat in ["attacker", "defender"]:
		var c: Dictionary = req[seat]
		var other: Dictionary = req["defender" if seat == "attacker" else "attacker"]
		var builder := CombatInputBuilder.new(req["matchId"], req["battleId"], c["playerId"])
		var skill_cfg: Dictionary = cfg[c["color"]]
		ais[seat] = CombatAI.new(builder, c["stats"], other["stats"], absi(String(req["battleId"]).hash()) % 100000 + (1 if seat == "attacker" else 2), float(skill_cfg["skill"]), String(skill_cfg["style"]))
	for seat in ais:
		ais[seat].use_resolve = true
	var guard := 0
	while sim.is_running() and guard < 6200:
		var snapshot := sim.snapshot(false)
		for seat in ais:
			ais[seat].own_resolve = (sim.attacker() if seat == "attacker" else sim.defender()).resolve
		sim.submit_input(ais["attacker"].think(snapshot))
		sim.submit_input(ais["defender"].think(snapshot))
		sim.step_tick()
		guard += 1
	var auth := Authority.new()
	auth.sim = sim
	root.add_child(auth)
	game.bind_combat_authority(auth)
	var summary: Dictionary = sim.duel_summary()
	var accepted: Dictionary = game.accept_result(sim.result, auth)
	if not accepted.get("ok", false):
		push_error("result rejected: %s" % str(accepted))
		quit(1)
		return
	totals["duels"] += 1
	totals["fight_ticks"] += int(summary["ticks"])
	if sim.result["outcome"] == "defender":
		totals["defender_wins"] += 1
	if String(sim.result["reason"]).begins_with("timeout"):
		totals["timeouts"] += 1
	for seat in ["attacker", "defender"]:
		var s: Dictionary = summary[seat]
		totals["resolve_gained"] += float(s["resolve_gained"])
		totals["resolve_spent"] += float(s["resolve_spent"])
		totals["second_winds"] += int(s["second_winds"])
		totals["overcharges"] += int(s["overcharges"])
		totals["resolve_dodges"] += int(s["resolve_dodges"])
		totals["whiffs"] += int(s["whiffs"])
		if int(s["hp"]) < int(s["max_hp"]) * 1.0 and seat == "attacker":
			pass
	var before: int = game.meta.notes.size()
	game.commit_battle()
	if verbose:
		for line in game.meta.notes.slice(maxi(0, before - 3)):
			print("    " + String(line))
	if "decisive win" in String(game.meta.notes[game.meta.notes.size() - 2] if game.meta.notes.size() > 1 else ""):
		totals["decisive"] += 1
	sim.stop()
	root.remove_child(sim)
	sim.queue_free()
	root.remove_child(auth)
	auth.queue_free()


## Returns "a", "b" or "draw" (plus plies).
func _game(number: int, base_seed: int, args: Dictionary, verbose: bool) -> Dictionary:
	var a_white := number % 2 == 0
	var game = Meta.new()
	game.new_game()
	var ai := {}
	var fight := {}
	ai[("w" if a_white else "b")] = ChessAI.new(int(args["chess_a"]), base_seed + number)
	ai[("b" if a_white else "w")] = ChessAI.new(int(args["chess_b"]), base_seed + number + 7)
	fight[("w" if a_white else "b")] = _fight_cfg(float(args["fight_a"]), String(args["style_a"]))
	fight[("b" if a_white else "w")] = _fight_cfg(float(args["fight_b"]), String(args["style_b"]))
	for color in ai:
		ai[color].deterministic = true
		ai[color].node_scale = float(args["node_scale"])
		ai[color].new_game()
	var plies := 0
	while game.engine.result.is_empty() and plies < int(args["max_plies"]):
		var color: String = game.engine.turn
		var choice: Dictionary = ai[color].choose_move(game.engine)
		if not choice.get("ok", false):
			break
		var outcome: Dictionary = game.play(choice["from"], choice["to"], choice["promotion"] if choice["promotion"] != "" else "q")
		if not outcome.get("ok", false):
			break
		plies += 1
		if game.phase == "combat":
			await _run_duel(game, fight, verbose)
	var result := "draw"
	var reason := String(game.engine.reason)
	if game.engine.result == "1-0" or game.engine.result == "0-1":
		var white_won: bool = game.engine.result == "1-0"
		result = "a" if white_won == a_white else "b"
	elif game.engine.result.is_empty():
		# Ply cap: adjudicate by material (a lead of 4+ wins) so a long game is not silently a draw.
		var lead: int = game.meta.material(game.engine.board, "w") - game.meta.material(game.engine.board, "b")
		if absi(lead) >= 4:
			result = "a" if (lead > 0) == a_white else "b"
			reason = "adjudicated on material"
		else:
			reason = "ply cap"
	return {"result": result, "plies": plies, "reason": reason, "a_white": a_white, "resolve": game.meta.resolve.duplicate()}


func _initialize() -> void:
	await process_frame
	var args := {"games": "12", "seed": "100", "chess_a": "5", "fight_a": "0.30", "chess_b": "2", "fight_b": "0.90", "max_plies": "120", "node_scale": "0.25", "shard": "0/1", "out": "", "verbose": "0", "patch": "", "style_a": "", "style_b": ""}
	for token in OS.get_cmdline_user_args():
		var kv: PackedStringArray = String(token).split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	if String(args["patch"]) != "":   # patch='{"meta":{"support":{"defended_take_mult":0.8}}}': tune the data for this run only (Balance.apply_override)
		var errors: Array = preload("res://combat/data/balance_data.gd").apply_override(JSON.parse_string(String(args["patch"])))
		if not errors.is_empty():
			push_error("patch refused: %s" % str(errors))
			quit(1)
			return
	var shard := String(args["shard"]).split("/")
	var rows: Array = []
	var wins := {"a": 0, "b": 0, "draw": 0}
	var a_by_color := {"white": 0, "black": 0}
	var started := Time.get_ticks_msec()
	for number in int(args["games"]):
		if number % int(shard[1]) != int(shard[0]):
			continue
		var r: Dictionary = await _game(number, int(args["seed"]), args, String(args["verbose"]) == "1")
		wins[r["result"]] += 1
		if r["result"] == "a":
			a_by_color["white" if r["a_white"] else "black"] += 1
		rows.append(r)
		print("game %d: %s in %d plies (%s) A=%s [%d s]" % [number, r["result"], r["plies"], r["reason"], "white" if r["a_white"] else "black", (Time.get_ticks_msec() - started) / 1000])
	var out := {"args": args, "wins": wins, "a_by_color": a_by_color, "games": rows, "duel_totals": totals, "tuning": preload("res://combat/data/balance_data.gd").stamp()}
	print("RESULT A(strong chess, weak fighter)=%d  B(weak chess, strong fighter)=%d  draws=%d" % [wins["a"], wins["b"], wins["draw"]])
	print("DUELS %s" % JSON.stringify(totals))
	if String(args["out"]) != "":
		var file := FileAccess.open(String(args["out"]), FileAccess.WRITE)
		file.store_string(JSON.stringify(out, "\t", true))
	quit(0)
