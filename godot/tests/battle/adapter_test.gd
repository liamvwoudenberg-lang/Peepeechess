extends SceneTree
const Match = preload("res://chess/battle_match.gd")
const Flow = preload("res://app/battle_flow.gd")
const Adapter = preload("res://app/battle_combat_adapter.gd")
const Messages = preload("res://tests/battle/test_combat_adapter.gd")
var checks = 0
var failures: Array = []
func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("FAIL: ", label)
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var g = Match.new()
	var adapter = Adapter.new()
	adapter.scene_path = "res://tests/battle/fixture_arena.tscn"
	var host = Node.new()
	var flow = Flow.new()
	root.add_child(host)
	root.add_child(adapter)
	root.add_child(flow)
	flow.set_process(false)
	flow.setup(g, adapter, host)
	g.new_game(0, 0, "7k/8/8/4q3/3P4/8/8/7K w - - 0 1")
	g.play("d4", "e5")
	expect(adapter.available() and flow.confirm_capture().ok, "production adapter queues threaded scene load")
	var deadline = Time.get_ticks_msec() + 5000
	while flow.phase == "loading" and Time.get_ticks_msec() < deadline:
		await process_frame
	expect(flow.phase == "countdown", "real adapter mounts and starts protocol fixture")
	if not is_instance_valid(adapter.arena):
		flow.dispose()
		quit(1)
		return
	var arena = adapter.arena
	expect(arena.running and arena.get_parent() == host, "arena initialized in supplied host")
	expect(arena.request.attacker.playerId != arena.request.defender.playerId and arena.request.attacker.role == "p" and arena.request.defender.role == "q", "two combatants passed intact to arena initialization")
	var messages = Messages.new()
	messages.request = arena.request
	arena.combat_snapshot.emit(messages.snapshot(60))
	expect(g.combat_snapshot().countdownTicksRemaining == 120, "snapshot crosses actual adapter signal bridge")
	var result = messages.winner()
	arena.battle_finished.emit(result)
	expect(flow.phase == "aftermath", "result crosses actual authority bridge")
	flow.interrupt()
	expect(g.revision == 1 and not arena.running and adapter.arena == null, "stopped arena and validated settlement")
	arena.battle_finished.emit(result)
	expect(g.revision == 1, "stopped scene generation cannot replay result")
	messages.free()
	await process_frame
	adapter.scene_path = "res://tests/battle/invalid_arena.tscn"
	g.new_game(0, 0, "7k/8/8/4q3/3P4/8/8/7K w - - 0 1")
	var frozen = g.chess_state()
	g.play("d4", "e5")
	flow.confirm_capture()
	deadline = Time.get_ticks_msec() + 5000
	while flow.phase == "loading" and Time.get_ticks_msec() < deadline:
		await process_frame
	expect(flow.phase == "board" and g.chess_state() == frozen and adapter.arena == null, "incompatible scene fails closed without board mutation")
	flow.dispose()
	flow.queue_free()
	adapter.queue_free()
	host.queue_free()
	await process_frame
	print("BATTLE ADAPTER: ", checks, " checks; failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
