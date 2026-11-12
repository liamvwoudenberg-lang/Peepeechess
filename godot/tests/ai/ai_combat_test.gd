extends SceneTree
## Battle Chess against the computer, through the REAL combat arena: the computer's colour is a CombatAI seat (skill/style
## from its level), the human colour keeps seat 1's controls whichever colour it is, and the idle human loses the duel.
const Match = preload("res://chess/battle_match.gd")
const Flow = preload("res://app/battle_flow.gd")
const Adapter = preload("res://app/battle_combat_adapter.gd")
var checks = 0
var failures: Array = []
var game
var adapter
var flow
var host
var computer
func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("FAIL: ", label)
func _init() -> void:
	call_deferred("run")
func wait_for_load() -> void:
	var deadline = Time.get_ticks_msec() + 15000
	while flow.phase == "loading" and Time.get_ticks_msec() < deadline:
		await process_frame
	if is_instance_valid(adapter.arena):
		adapter.arena.set_physics_process(false)
	await physics_frame
	await process_frame
func duel(from: String, to: String, human_color: String, level: int) -> void:
	expect(game.play(from, to).ok and flow.phase == "preview", "capture preview %s%s" % [from, to])
	expect(flow.confirm_capture().ok, "arena load accepted")
	await wait_for_load()
	var arena = adapter.arena
	expect(flow.phase == "countdown" and is_instance_valid(arena), "real arena mounted")
	if not is_instance_valid(arena):
		return
	var request = game.pending_request()
	var ai_id = game.players["b" if human_color == "w" else "w"]
	var human_id = game.players[human_color]
	var profile = ChessAI.combat_profile(level)
	expect(arena.seats[ai_id].type == "ai" and absf(arena.seats[ai_id].skill - profile.skill) < 0.001 and arena.seats[ai_id].style == (profile.attack_style if request.attacker.playerId == ai_id else profile.style), "computer colour is a CombatAI seat with the level's skill/style")
	expect(arena.seats[human_id].type == "human" and arena.seats[human_id].scheme == "kb1", "human always uses seat 1 controls (colour %s)" % human_color)
	expect(arena._ais.size() == 1, "exactly one CombatAI is running")
	for tick in range(5580):
		if not arena.sim.is_running():
			break
		arena._physics_process(1.0 / 60.0)
	expect(not arena.sim.result.is_empty(), "the duel finished")
	var ai_role = request.attacker if request.attacker.playerId == ai_id else request.defender
	var winner_is_ai = arena.sim.result.get("winnerPlayerId", "") == ai_id
	expect(winner_is_ai, "the CombatAI beats an idle human (winner %s, reason %s)" % [arena.sim.result.get("winnerPlayerId", ""), arena.sim.result.get("reason", "")])
	print("duel %s%s human %s: winner is the computer = %s, reason %s, ticks %d" % [from, to, human_color, winner_is_ai, arena.sim.result.get("reason", ""), arena.sim.server_tick])
	expect(flow.return_to_board().ok, "result returns to the board")
	flow.advance(1)
	await process_frame
func run() -> void:
	game = Match.new()
	adapter = Adapter.new()
	adapter.presentation_enabled = true  # the arena builds its CombatAI seats together with its presentation layer
	flow = Flow.new()
	host = Node3D.new()
	root.add_child(host)
	root.add_child(adapter)
	root.add_child(flow)
	flow.set_process(false)
	flow.setup(game, adapter, host)
	computer = ComputerOpponent.new()
	root.add_child(computer)
	game.new_game()
	computer.bind(game, adapter)
	computer.begin({"level": 5, "color": "w", "seed": 1})
	expect(computer.ai_color == "b" and adapter.computer_seat.color == "b" and adapter.computer_seat.seat.type == "ai", "begin() hands the AI seat to the combat adapter")
	computer.cancel_search()
	expect(game.play("e2", "e4").ok and game.play("d7", "d5").ok, "opening moves")
	await duel("e4", "d5", "w", 5)
	# Now the computer is white: new game, human plays black.
	game.new_game()
	computer.begin({"level": 3, "color": "b", "seed": 2})
	computer.cancel_search()
	expect(computer.ai_color == "w" and adapter.computer_seat.color == "w", "computer plays White when the human is Black")
	expect(game.play("e2", "e4").ok and game.play("d7", "d5").ok, "opening moves (second game)")
	await duel("e4", "d5", "b", 3)
	# Levels 4-6 use reactive styles when defending and an aggressive style when attacking: both must beat an idle human.
	for level in [4, 6]:
		for human in ["w", "b"]:
			game.new_game()
			computer.begin({"level": level, "color": human, "seed": 3})
			computer.cancel_search()
			var ai_color = "b" if human == "w" else "w"
			expect(game.play("e2", "e4").ok and game.play("d7", "d5").ok, "opening moves (L%d)" % level)
			if ai_color == "w":
				await duel("e4", "d5", human, level)  # white (computer) attacks
			else:
				game.new_game()
				computer.begin({"level": level, "color": human, "seed": 3})
				computer.cancel_search()
				expect(game.play("e2", "e4").ok and game.play("d7", "d5").ok and game.play("a2", "a3").ok, "setup for black attack (L%d)" % level)
				await duel("d5", "e4", human, level)  # black (computer) attacks
	computer.end()
	expect(adapter.computer_seat.is_empty(), "ending the computer game restores two human seats")
	computer.dispose()
	computer.free()
	flow.dispose()
	flow.queue_free()
	adapter.queue_free()
	host.queue_free()
	await process_frame
	await process_frame
	# Same exit hygiene as combat/tests/test_runner.gd: drop the static sound cache and let the audio mix thread release playbacks.
	load("res://combat/audio/combat_audio.gd").clear_library()
	await create_timer(0.5).timeout
	print("AI COMBAT: ", checks, " checks; failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
