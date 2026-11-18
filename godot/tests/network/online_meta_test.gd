extends SceneTree
## Online Battle with the fairness rules: the authoritative session (match_session.gd) runs BattleMetaMatch, so a wounded piece enters its
## duel wounded, the defender's edge and Resolve are in force inside the server's simulation, and the finished duel's HP and Resolve are
## carried on the server's board state. Intent-only inputs; the fixture only sets a wound (a trusted test shortcut, like the roster fixture).
const Room = preload("res://network/server/match_session.gd")
const Builder = preload("res://combat/core/combat_input_builder.gd")
const Rules = preload("res://chess/chess_engine.gd")
const Balance = preload("res://combat/data/balance_data.gd")
var checks = 0
var failures: Array = []

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL: ", label)

func _init() -> void:
	call_deferred("run")

func move(room, color: String, from: String, to: String) -> Dictionary:
	var id: String = room.game.match_id
	return room.move({"schemaVersion":1,"requestId":"m-" + from + to,"matchId":id,"playerId":"player-" + color,"expectedRevision":room.game.revision,"from":from,"to":to,"promotion":null}, "player-" + color, 0)

func run() -> void:
	var room = Room.new()
	root.add_child(room)
	room.configure("match-online-meta", "battle", "player-w", 0, 0, 0)
	room.join("player-b", 0)
	room.command({"action":"ready"}, "player-w", 0)
	room.command({"action":"ready"}, "player-b", 0)
	expect(room.game is BattleMetaMatch, "the online session runs BattleMetaMatch (persistent damage, support, Resolve)")
	expect(move(room, "w", "e2", "e4").ok and move(room, "b", "d7", "d5").ok, "two quiet moves are accepted")
	var pawn_id: String = room.game.registry[Rules.index("e4")]
	room.game.meta.hp[pawn_id] = 0.5   # a wounded attacker (trusted fixture)
	var resolve_before: float = float(room.game.meta.resolve["w"])
	var response = move(room, "w", "e4", "d5")
	expect(response.ok and room.sim != null, "the capture starts the authoritative duel")
	await physics_frame
	await process_frame
	var request = room.game.pending_request()
	var attacker = room.sim.attacker()
	var defender = room.sim.defender()
	expect(room.sim.rules_on, "the duel rules are on in the online simulation")
	expect(attacker.health.current == roundi(0.5 * float(request.attacker.stats.maxHp)), "the wounded attacker starts at its persisted HP (%d)" % attacker.health.current)
	expect(defender.health.current == defender.health.maximum, "the unhurt defender starts full")
	expect(is_equal_approx(defender.take_mult, float(Balance.duel_rules()["defender"]["take_mult"])) or defender.take_mult < 1.0, "the defender's edge is in force on the server")
	expect(attacker.resolve > 0.0 and attacker.resolve <= float(Balance.meta()["resolve"]["carry_cap"]), "Resolve is carried into the duel, capped (%.0f)" % attacker.resolve)
	var builders = {"player-w": Builder.new(room.game.match_id, request.battleId, "player-w"), "player-b": Builder.new(room.game.match_id, request.battleId, "player-b")}
	var result: Dictionary = {}
	for tick in range(5580):
		if room.game.phase != "combat":
			break
		for fighter in room.sim.fighters:
			var builder = builders[fighter.player_id]
			var delta: Vector3 = room.sim.opponent_of(fighter).global_position - fighter.global_position
			delta.y = 0
			var moving = delta.normalized() if fighter.player_id == "player-w" and delta.length() > 1.15 else Vector3.ZERO
			if fighter.player_id == "player-w" and tick >= 200 + 30 and tick % 50 == 0:
				builder.press("light")
			room.input(builder.build(moving.x, moving.z, atan2(delta.x, delta.z), true, false, false), fighter.player_id)
		room.step((tick + 1) * 1000 / 60)
		if room.sim != null and not room.sim.result.is_empty():
			result = room.sim.result.duplicate(true)
	expect(not result.is_empty() and result.outcome == "attacker", "the scripted attacker wins by knockout")
	var end_hp: int = int(result.attackerHp)
	var before_tick = room.tick
	for i in range(121):
		room.step((before_tick + i + 1) * 1000 / 60)
	expect(room.game.revision == 3 and room.game.engine.history.size() == 3, "the server settled the capture exactly once")
	expect(room.game.meta.hp.has(pawn_id), "the surviving piece keeps its wounds on the server")
	expect(float(room.game.meta.hp[pawn_id]) > 0.0 and float(room.game.meta.hp[pawn_id]) <= 1.0, "carried HP fraction is valid (%.2f from %d HP)" % [float(room.game.meta.hp[pawn_id]), end_hp])
	expect(float(room.game.meta.resolve["w"]) != resolve_before, "Resolve changed on the server after the duel and the move")
	expect(room.game.meta.notes.size() > 0, "the server keeps a readable meta log (%d lines)" % room.game.meta.notes.size())
	print("ONLINE META: ", checks, " checks; failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
