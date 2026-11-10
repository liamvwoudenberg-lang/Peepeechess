extends SceneTree
const Match = preload("res://chess/battle_match.gd")
const Flow = preload("res://app/battle_flow.gd")
const Double = preload("res://tests/battle/test_combat_adapter.gd")
const Adapter = preload("res://app/battle_combat_adapter.gd")
const Controls = preload("res://boards/board_interaction.gd")
const FEN = "7k/8/8/4q3/3P4/8/8/7K w - - 0 1"
var checks = 0
var failures: Array = []
var g
var a
var flow
var controls
var host: Node
func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("FAIL: ", label)
func _init() -> void:
	call_deferred("run")
func run() -> void:
	g = Match.new()
	a = Double.new()
	flow = Flow.new()
	host = Node.new()
	root.add_child(host)
	root.add_child(a)
	root.add_child(flow)
	flow.set_process(false)
	flow.setup(g, a, host)
	controls = Controls.new(g)
	g.new_game(0, 0, FEN)
	var before = g.chess_state()
	g.play("d4", "e5")
	expect(flow.phase == "preview", "capture preview")
	controls.select(7)
	expect(controls.selected == -1, "board input suspended")
	flow.cancel_preview()
	expect(flow.phase == "board" and g.chess_state() == before, "preview cancel no mutation")
	g.play("d4", "e5")
	flow.confirm_capture()
	expect(flow.phase == "loading", "loading phase")
	flow.interrupt()
	a.complete_load()
	expect(flow.phase == "board" and a.start_calls == 0 and g.chess_state() == before, "late load ignored after interruption")
	g.play("d4", "e5")
	flow.confirm_capture()
	flow.advance(16)
	expect(flow.phase == "board" and g.chess_state() == before, "loading timeout safe rollback")
	a.load_fails = true
	g.play("d4", "e5")
	expect(not flow.confirm_capture().ok and g.chess_state() == before, "load failure safe rollback")
	a.load_fails = false
	a.starts_fail = true
	g.play("d4", "e5")
	flow.confirm_capture()
	a.complete_load()
	expect(flow.phase == "board" and g.chess_state() == before, "initialization failure safe rollback")
	a.starts_fail = false
	# Four consecutive captures, alternating victors, without resetting the match.
	g.new_game(0, 0, "5k1r/6p1/7P/p7/8/p7/8/R5K1 w - - 0 1")
	for item in [["a1", "a3", "attacker"], ["h8", "h6", "defender"], ["a3", "a5", "defender"], ["g7", "h6", "attacker"]]:
		var prior = g.chess_state()
		expect(g.play(item[0], item[1]).ok and flow.phase == "preview", "repeat capture prepared")
		expect(flow.confirm_capture().ok and flow.phase == "loading", "repeat loading")
		a.complete_load()
		expect(flow.phase == "countdown", "countdown after arena initialization")
		a.snapshot_received.emit(a.snapshot(60))
		expect(g.combat_snapshot().countdownTicksRemaining == 120 and g.chess_state() == prior, "countdown freezes board")
		a.snapshot_received.emit(a.snapshot(180))
		expect(flow.phase == "combat", "active combat")
		var invalid = a.winner(item[2])
		invalid.winnerPlayerId = "forged"
		a.result_received.emit(invalid)
		expect(flow.phase == "combat" and g.chess_state() == prior, "invalid result ignored")
		var r = a.winner(item[2])
		a.result_received.emit(r)
		a.result_received.emit(r)
		expect(flow.phase == "aftermath" and g.chess_state() == prior, "result display before settlement")
		flow.advance(3)
		expect(flow.phase == "returning" and g.revision == prior.revision + 1, "return applies one atomic board change")
		flow.advance(1)
		expect(flow.phase == "board" and g.board_input_allowed(), "return completes")
	expect(g.engine.history.size() == 4 and g.engine.turn == "w", "multiple battles consistent ply/turn")
	expect(g.play("g1", "g2").ok, "match continues after repeated battles")
	# Interrupting result presentation must COMMIT an already validated result.
	g.new_game(0, 0, FEN)
	g.play("d4", "e5")
	flow.confirm_capture()
	a.complete_load()
	a.result_received.emit(a.winner("defender"))
	flow.interrupt()
	expect(g.revision == 1 and g.engine.board[27] == "" and flow.phase == "board", "result interruption settles instead of discarding outcome")
	flow.interrupt()
	expect(g.revision == 1, "repeat interruption cannot apply twice")
	g.new_game(0, 0, FEN)
	g.play("d4", "e5")
	flow.confirm_capture()
	a.complete_load()
	var late = a.winner()
	g.new_game()
	a.result_received.emit(late)
	expect(flow.phase == "board" and g.revision == 0 and g.engine.fen() == Match.BattleRules.START_FEN, "new match invalidates old arena result")
	# Production bridge must fail closed when Claude's scene is not supplied.
	var actual = Adapter.new()
	root.add_child(actual)
	actual.scene_path = "res://combat/definitely_missing.tscn"
	expect(not actual.available() and not actual.begin_load({}, host).ok, "missing real combat is reported, not simulated")
	actual.queue_free()
	controls.dispose()
	flow.dispose()
	flow.queue_free()
	a.queue_free()
	host.queue_free()
	await process_frame
	print("BATTLE FLOW: ", checks, " checks; failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
