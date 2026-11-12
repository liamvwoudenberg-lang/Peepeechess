extends RefCounted
## Test rig. Every action goes through the real CombatInput channel (CombatInputBuilder ->
## CombatSimulation.submit_input), exactly as an online client would use it. Tests may place
## fighters or adjust component state directly where they are checking a *rule*, never to fake
## an outcome.

class Seat:
	var builder: CombatInputBuilder
	var move: Vector2 = Vector2.ZERO
	var yaw: float = 0.0
	var lock: bool = true
	var sprint: bool = false
	var block: bool = false
	var autosend: bool = true

	func press(action: String) -> void:
		builder.press(action)

	func packet() -> Dictionary:
		return builder.build(move.x, move.y, yaw, lock, sprint, block)


class Rig:
	var sim: CombatSimulation
	var w: Seat
	var b: Seat
	var tree: SceneTree
	var submit_errors: Array = []

	func white() -> FighterController:
		return sim.fighters[0]

	func black() -> FighterController:
		return sim.fighters[1]

	## Steps `n` ticks; each seat with autosend submits one packet per tick first.
	func tick(n: int = 1) -> void:
		for _i in n:
			for seat in [w, b]:
				if seat.autosend:
					var reply: Dictionary = sim.submit_input(seat.packet())
					if not reply["ok"]:
						submit_errors.append(reply)
			sim.step_tick()

	## Runs the 180-tick countdown so the next tick is the first live tick.
	func to_live() -> void:
		var guard := 0
		while sim.phase == CombatSimulation.Phase.COUNTDOWN and guard < 400:
			tick()
			guard += 1

	## Steps until `condition` is true; returns ticks stepped or -1 on timeout.
	func until(condition: Callable, max_ticks: int = 600) -> int:
		for i in max_ticks:
			if condition.call():
				return i
			tick()
		return -1

	func place(white_position: Vector3, black_position: Vector3) -> void:
		white().teleport(white_position)
		black().teleport(black_position)

	## Both fighters 1.8 m apart on the z axis, facing each other: inside every reach.
	func face_off(gap: float = 1.8) -> void:
		white().teleport(Vector3(0.0, 0.0, -gap * 0.5), 0.0)
		black().teleport(Vector3(0.0, 0.0, gap * 0.5), PI)

	func events_of(type: String) -> Array:
		return sim.recent_events.filter(func(e): return e["type"] == type)

	func dispose() -> void:
		sim.stop()
		if sim.get_parent() != null:
			sim.get_parent().remove_child(sim)
		sim.queue_free()


## Creates a running (countdown phase) battle. A physics frame is awaited so world colliders
## are registered before the first tick. `attacker` is the seat that initiated the capture.
static func make_rig(tree: SceneTree, white_role: String, black_role: String, attacker: String = "w",
		start_tick: int = 0, battle_id: String = "t-1") -> Rig:
	var rig := Rig.new()
	rig.tree = tree
	rig.sim = CombatSimulation.new()
	tree.root.add_child(rig.sim)
	var request := FighterRoster.build_request(white_role, black_role, attacker, battle_id, 7, start_tick)
	var reply: Dictionary = rig.sim.start(request)
	assert(reply["ok"], "rig start failed: %s" % str(reply))
	await tree.physics_frame
	rig.w = Seat.new()
	rig.w.builder = CombatInputBuilder.new(request["matchId"], battle_id, "player-white")
	rig.w.yaw = 0.0
	rig.b = Seat.new()
	rig.b.builder = CombatInputBuilder.new(request["matchId"], battle_id, "player-black")
	rig.b.yaw = PI
	return rig
