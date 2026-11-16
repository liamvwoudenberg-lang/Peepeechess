extends SceneTree
const Adapter = preload("res://app/battle_combat_adapter.gd")
var checks = 0
var failures = []
func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL: ", label)
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var previous = InputAssignment.shared()
	var assignment = InputAssignment.new()
	assignment.connected_provider = func(): return []
	InputAssignment.set_shared(assignment)
	expect(Adapter.human_input_scheme("kb1", true) == "touch", "mobile keyboard fallback uses real touch controls")
	expect(Adapter.human_input_scheme("kb2", true) == "touch", "either seat can receive touch input")
	expect(Adapter.human_input_scheme("pad7", true) == "pad7", "a real controller keeps its assigned seat")
	expect(Adapter.human_input_scheme("kb1", false) == "kb1", "desktop keyboard controls stay unchanged")
	expect(Adapter.local_controls_available(true, true), "solo touch battles are supported")
	expect(not Adapter.local_controls_available(false, true), "two humans cannot share one overlapping touch interface")
	expect(Adapter.local_controls_available(false, false), "desktop two-player controls remain supported")
	var game = BattleChessMatch.new()
	game.new_game(0, 0, "7k/8/8/3p4/4P3/8/8/7K w - - 0 1")
	game.play("e4", "d5")
	var adapter = Adapter.new()
	adapter.prefer_touch = true
	var reply = adapter.check_request(game.pending_request())
	expect(not reply.ok and reply.error == Adapter.SHARED_TOUCH_NOTICE, "capture admission explains unsupported shared-touch setup")
	adapter.computer_seat = {"color": "b", "seat": {"type": "ai"}}
	expect(adapter.check_request(game.pending_request()).ok, "the same real capture supports human touch versus computer")
	assignment.connected_provider = func(): return [2, 3]
	expect(Adapter.local_controls_available(false, true), "two separately assigned controllers enable local battles")
	assignment._claims[0] = "kb1"
	expect(not Adapter.local_controls_available(false, true), "connected but unassigned controllers cannot hide overlapping touch seats")
	adapter.free()
	InputAssignment.set_shared(previous)
	print("MOBILE CONTROLS: ", checks, " checks; failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
