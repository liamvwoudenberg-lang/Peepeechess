extends SceneTree
## Full C0 roster through Claude's online host with approved board stats and intent-only inputs.
const Room = preload("res://network/server/match_session.gd")
const Builder = preload("res://combat/core/combat_input_builder.gd")
const Wire = preload("res://network/wire_codec.gd")
const Rules = preload("res://chess/chess_engine.gd")
var checks = 0
var failures: Array = []
func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL: ", label)
func _init() -> void:
	call_deferred("run")
func position(a: String, d: String) -> String:
	var from = {"p":"d4", "n":"c4", "b":"d4", "r":"e4", "q":"d4"}[a]
	var board = {7:"K", 56:"k", 36:d}
	board[Rules.index(from)] = a.to_upper()
	var rows = []
	for rank in range(7, -1, -1):
		var row = ""
		var gap = 0
		for file in range(8):
			var at = rank * 8 + file
			if not board.has(at):
				gap += 1
			else:
				if gap:
					row += str(gap)
					gap = 0
				row += board[at]
		if gap:
			row += str(gap)
		rows.append(row)
	return "/".join(rows) + " w - - 0 1"
func run() -> void:
	var wire = Wire.new()
	for pair in [["p","q"],["n","b"],["b","r"],["r","n"],["q","p"]]:
		for outcome in ["attacker", "defender"]:
			var room = Room.new()
			root.add_child(room)
			var id = "match-roster-" + pair[0] + pair[1] + outcome
			room.configure(id, "battle", "player-w", 0, 0, 0)
			room.join("player-b", 0)
			room.command({"action":"ready"}, "player-w", 0)
			room.command({"action":"ready"}, "player-b", 0)
			# Trusted test fixture only; the network CreateMatch has no FEN field.
			expect(room.game.new_game(0, 0, position(pair[0], pair[1])).ok, "valid roster position " + str(pair))
			room.game.match_id = id
			var from = {"p":"d4", "n":"c4", "b":"d4", "r":"e4", "q":"d4"}[pair[0]]
			var response = room.move({"schemaVersion":1,"requestId":"capture-1","matchId":id,"playerId":"player-w","expectedRevision":0,"from":from,"to":"e5","promotion":null}, "player-w", 0)
			expect(response.ok and room.sim != null, "full roster capture starts real combat host")
			if room.sim == null:
				room.queue_free()
				continue
			await physics_frame
			await process_frame
			var request = room.game.pending_request()
			var winner: Dictionary = request[outcome]
			var builders = {"player-w":Builder.new(id, request.battleId, "player-w"), "player-b":Builder.new(id, request.battleId, "player-b")}
			var abilities = []
			room.sim.event_emitted.connect(func(event): if event.type == "ability": abilities.append(event.actorPlayerId))
			var inputs_ok = true
			var result: Dictionary = {}
			for tick in range(5580):
				if room.game.phase != "combat":
					break
				for fighter in room.sim.fighters:
					var builder = builders[fighter.player_id]
					var delta: Vector3 = room.sim.opponent_of(fighter).global_position - fighter.global_position
					delta.y = 0
					var moving = delta.normalized() if fighter.player_id == winner.playerId and delta.length() > 1.15 else Vector3.ZERO
					if fighter.player_id == winner.playerId:
						if tick == 185:
							builder.press("ability")
						if tick >= 200 and tick % 50 == 0:
							builder.press("light")
					inputs_ok = inputs_ok and room.input(builder.build(moving.x, moving.z, atan2(delta.x, delta.z), true, false, false), fighter.player_id).ok
				room.step((tick + 1) * 1000 / 60)
				if room.sim != null and not room.sim.result.is_empty():
					result = room.sim.result.duplicate(true)
			expect(inputs_ok, "all roster inputs admitted by existing combat host")
			expect(not result.is_empty() and result.outcome == outcome and result.reason == "knockout", "input-driven roster knockout " + str(pair) + outcome)
			if winner.role in ["b", "r", "q"]:
				expect(winner.playerId in abilities, "real special ability triggers for " + winner.role)
			var before_tick = room.tick
			for i in range(121):
				room.step((before_tick + i + 1) * 1000 / 60)
			expect(room.game.revision == 1 and room.game.engine.history.size() == 1, "server settles full-roster result exactly once")
			expect(room.game.engine.board[Rules.index("e5")] == (pair[0].to_upper() if outcome == "attacker" else pair[1]), "correct full-roster survivor")
			expect(wire.valid("MatchFrame", room.frame("player-w")), "full-roster MatchFrame remains contract valid")
			var stale = builders[winner.playerId].build(0, 0, 0, true, false, false)
			expect(room.input(stale, winner.playerId).get("ignored", false), "in-flight input after a retired battle is ignored")
			room.queue_free()
			await process_frame
	print("NETWORK ROSTER: ", checks, " checks; failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
