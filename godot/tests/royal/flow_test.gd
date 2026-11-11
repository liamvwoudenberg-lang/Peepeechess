extends SceneTree
## BattleFlow with a battle-royal-v1 match: duels run one after another through the ordinary preview/loading/countdown/
## combat/aftermath path; the sequence signals reach the presentation layer; a royal duel cannot be cancelled and is retried
## (bounded) when it fails to start. Uses a test-only adapter double that, like the real adapter, reports the King's state.
const Royal = preload("res://chess/battle_royal_match.gd")
const Flow = preload("res://app/battle_flow.gd")
const BOTH = "R3k3/3p1p2/8/8/8/8/8/4R1K1 b - - 0 1"
const BACK_RANK = "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1"
var checks = 0
var failures: Array = []
var events: Array = []

class Adapter extends Node:
	signal arena_ready
	signal snapshot_received(snapshot: Dictionary)
	signal result_received(result: Dictionary)
	signal failed(message: String)
	var request: Dictionary = {}
	var options: Dictionary = {}
	var king_state = {"hp": 160, "stamina": 100.0, "cooldownTicks": 0}
	var load_calls = 0
	var start_calls = 0
	var stop_calls = 0
	var load_fails = false
	func available() -> bool: return true
	func begin_load(value: Dictionary, _host: Node, opts: Dictionary = {}) -> Dictionary:
		load_calls += 1
		request = value.duplicate(true)
		options = opts.duplicate(true)
		return {"ok": false, "error": "Fixture load failure."} if load_fails else {"ok": true}
	func start(value: Dictionary, opts: Dictionary = {}) -> Dictionary:
		start_calls += 1
		request = value.duplicate(true)
		options = opts.duplicate(true)
		return {"ok": true}
	func stop() -> void: stop_calls += 1
	func fighter_state(_player_id: String) -> Dictionary: return king_state
	func result(king_wins: bool, end: Dictionary, checker_hp: int = 0) -> Dictionary:
		king_state = end
		var outcome = "attacker" if king_wins else "defender"
		return {"schemaVersion": 1, "matchId": request.matchId, "battleId": request.battleId, "expectedRevision": request.expectedRevision, "resolvedTick": request.startTick + 181, "winnerPlayerId": request[outcome].playerId, "outcome": outcome, "reason": "knockout", "attackerHp": end.hp, "defenderHp": 0 if king_wins else maxi(1, checker_hp)}

func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("FAIL: ", label)

func _init() -> void:
	call_deferred("run")

func rig(fen: String):
	var g = Royal.new()
	var a = Adapter.new()
	var flow = Flow.new()
	var host = Node.new()
	root.add_child(host)
	root.add_child(a)
	root.add_child(flow)
	flow.set_process(false)
	flow.setup(g, a, host)
	events.clear()
	flow.sequence_started.connect(func(info): events.append(["sequence_started", info.attackers.size()]))
	flow.duel_started.connect(func(index, total, hp): events.append(["duel_started", index, total, hp]))
	flow.duel_finished.connect(func(index, total, summary): events.append(["duel_finished", index, total, summary.kingEnd.hp, summary.kingSurvived]))
	flow.sequence_finished.connect(func(summary): events.append(["sequence_finished", summary.outcome]))
	flow.returning_to_board.connect(func(): events.append(["returning_to_board"]))
	g.new_game(0, 0, fen)
	return [g, a, flow, host]

func drop(parts: Array) -> void:
	parts[2].dispose()
	for node in [parts[2], parts[1], parts[3]]:
		node.queue_free()

## Plays one duel from preview to the next board/preview state through the flow.
func fight(parts: Array, king_wins: bool, end: Dictionary) -> void:
	var g = parts[0]
	var a = parts[1]
	var flow = parts[2]
	flow.advance(1.6) # the mandatory banner elapses and the duel starts by itself
	expect(flow.phase == "loading", "the royal duel starts after the banner")
	a.arena_ready.emit()
	expect(flow.phase == "countdown", "countdown")
	var res = a.result(king_wins, end)
	a.result_received.emit(res)
	expect(flow.phase == "aftermath" and g.phase == "aftermath", "result accepted through the ordinary path")
	flow.advance(2.1)

func run() -> void:
	# Single checker, King wins: banner -> fight -> board.
	var parts = rig(BACK_RANK)
	var g = parts[0]
	var a = parts[1]
	var flow = parts[2]
	g.play("a1", "a8")
	expect(flow.phase == "preview" and g.royal_active(), "the mating move shows the first duel banner")
	expect(events == [["sequence_started", 1], ["duel_started", 0, 1, 160]], "sequence_started then duel_started(index,total,king_hp)")
	flow.cancel_preview()
	expect(flow.phase == "preview" and g.royal_active(), "a royal duel cannot be cancelled")
	flow.advance(1.0)
	expect(flow.phase == "preview", "the banner stays up until its time is over")
	fight(parts, true, {"hp": 90, "stamina": 40.0, "cooldownTicks": 12})
	expect(a.options == {"allow_experimental_roles": true, "initial_hp": 160, "initial_stamina": 100.0, "initial_cooldown": 0} and a.request.attacker.role == "k", "the adapter received the King request with its start options")
	expect(a.load_calls == 1 and a.start_calls == 1, "one load and one start")
	expect(flow.phase == "returning" and not g.royal_active() and g.engine.result.is_empty() and g.engine.turn == "b", "the board returns; the mated side is on move")
	expect(events.slice(2) == [["duel_finished", 0, 1, 90, true], ["sequence_finished", "king_survived"], ["returning_to_board"]], "duel_finished, sequence_finished, then the board return")
	flow.advance(0.5)
	expect(flow.phase == "board" and g.board_input_allowed(), "back on the board")
	drop(parts)

	# Two checkers: duel 2 follows duel 1 with the carried state, no board return in between.
	parts = rig(BOTH)
	g = parts[0]
	a = parts[1]
	flow = parts[2]
	expect(flow.phase == "preview" and g.royal_active(), "a loaded mate opens the sequence at once")
	fight(parts, true, {"hp": 100, "stamina": 55.5, "cooldownTicks": 220})
	expect(flow.phase == "preview" and g.royal_duel_request().duelIndex == 1, "after duel 1 the second duel is previewed, not the board")
	expect(events.filter(func(e): return e[0] == "returning_to_board").is_empty(), "no board-return animation between duels")
	expect(events.filter(func(e): return e[0] == "duel_started") == [["duel_started", 0, 2, 160], ["duel_started", 1, 2, 100]], "duel_started reports the carried King HP")
	fight(parts, true, {"hp": 25, "stamina": 3.0, "cooldownTicks": 20})
	expect(a.options.initial_hp == 100 and a.options.initial_stamina == 55.5 and a.options.initial_cooldown == 220, "duel 2 was started with the carried values")
	expect(g.engine.result.is_empty() and g.royal_log.size() == 1 and g.royal_log[0].duels.size() == 2, "both duels logged")
	flow.advance(0.5)
	expect(flow.phase == "board", "board after the sequence")
	drop(parts)

	# The King loses: checkmate, board untouched.
	parts = rig(BOTH)
	g = parts[0]
	a = parts[1]
	flow = parts[2]
	var fen = g.engine.fen()
	flow.advance(1.6)
	a.arena_ready.emit()
	a.result_received.emit(a.result(false, {"hp": 0, "stamina": 10.0, "cooldownTicks": 100}, 120))
	flow.advance(2.1)
	expect(g.engine.result == "1-0" and g.engine.fen() == fen and flow.phase in ["returning", "board"], "a fallen King ends the match as checkmate")
	expect(events.back()[0] == "returning_to_board" and ["sequence_finished", "king_fell"] in events, "sequence_finished(king_fell)")
	drop(parts)

	# A duel that cannot start is retried, then checkmate stands (no winner is invented from combat).
	parts = rig(BOTH)
	g = parts[0]
	a = parts[1]
	flow = parts[2]
	a.load_fails = true
	var failures_seen: Array = []
	flow.failed.connect(func(message): failures_seen.append(message))
	var first_id = g.pending_request().battleId
	flow.advance(1.6)
	expect(g.royal_active() and flow.phase == "preview" and g.pending_request().battleId == first_id + ":retry1", "failed start: same duel retried under a new id")
	flow.advance(1.6)
	flow.advance(1.6)
	expect(not g.royal_active() and g.engine.result == "1-0" and flow.phase == "board", "after the retries checkmate stands")
	expect(failures_seen.size() == 3 and g.royal_log[0].outcome == "unplayable", "three failures reported, outcome unplayable")
	drop(parts)

	# Interrupting mid-countdown retries as well and never grants a result.
	parts = rig(BACK_RANK)
	g = parts[0]
	a = parts[1]
	flow = parts[2]
	g.play("a1", "a8")
	flow.advance(1.6)
	a.arena_ready.emit()
	flow.interrupt()
	expect(g.royal_active() and g.engine.result.is_empty() and flow.phase == "preview", "an interrupted royal fight is re-armed from its start state")
	drop(parts)

	await process_frame
	await process_frame
	if failures.is_empty():
		print("PASS: %d royal flow checks" % checks)
		quit(0)
	else:
		printerr("FAILED: %d of %d royal flow checks" % [failures.size(), checks])
		quit(1)
