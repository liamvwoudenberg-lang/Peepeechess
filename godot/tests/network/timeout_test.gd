extends SceneTree
## Battle move timeout (match_session.gd move_timeout_ms): the side to move forfeits after the limit, the clock restarts on every committed
## move, and a Classic room (own clocks) and a disabled timeout never forfeit.
const Room = preload("res://network/server/match_session.gd")
var checks = 0
var failures: Array = []

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL: ", label)

func _init() -> void:
	call_deferred("run")

func ready_room(mode: String, timeout_ms: int):
	var room = Room.new()
	root.add_child(room)
	room.configure("T" + mode + str(timeout_ms), mode, "player-w", 0 if mode == "battle" else 600000, 0, 0)
	room.join("player-b", 0)
	room.command({"action": "ready"}, "player-w", 0)
	room.command({"action": "ready"}, "player-b", 0)
	room.move_timeout_ms = timeout_ms
	return room

func play(room, color: String, from: String, to: String, now: int) -> Dictionary:
	return room.move({"schemaVersion":1,"requestId":"m-" + from + to,"matchId":room.game.match_id,"playerId":"player-" + color,"expectedRevision":room.game.revision,"from":from,"to":to,"promotion":null}, "player-" + color, now)

func run() -> void:
	var room = ready_room("battle", 5000)
	expect(room.status == "active", "both ready: the room is active")
	room.step(1000)
	room.step(5900)
	expect(room.status == "active", "inside the limit nobody forfeits")
	expect(play(room, "w", "e2", "e4", 6000).ok, "White moves in time")
	room.step(7000)
	room.step(11000)
	expect(room.status == "active", "the clock restarted on White's move (Black has until 12000)")
	room.step(12100)
	expect(room.status == "complete" and room.game.engine.result == "1-0" and room.game.engine.reason == "Move timeout", "Black forfeits after the limit: %s %s" % [room.game.engine.result, room.game.engine.reason])
	room.queue_free()
	var off = ready_room("battle", 0)
	off.step(1000)
	off.step(10000000)
	expect(off.status == "active", "timeout 0 never forfeits")
	off.queue_free()
	var classic = ready_room("classic", 1000)
	classic.step(1000)
	classic.step(3000)
	expect(classic.status == "active", "Classic ignores the Battle move timeout (it has chess clocks)")
	classic.queue_free()
	print("TIMEOUT: ", checks, " checks; failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
