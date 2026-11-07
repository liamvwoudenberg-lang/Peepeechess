extends SceneTree
const Match = preload("res://chess/classic_match.gd")
const Rules = preload("res://chess/chess_engine.gd")
const Codec = preload("res://contracts/codec.gd")
var failures: Array = []
var checks = 0
func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL: ", label)
func request(g, from: String, to: String, id: String = "test") -> Dictionary:
	return {"schemaVersion": 1, "matchId": g.match_id, "requestId": id, "playerId": g.players[g.engine.turn], "expectedRevision": g.revision, "from": from, "to": to, "promotion": null}
func _init() -> void:
	var g = Match.new()
	var codec = Codec.new()
	var snapshots: Array = []
	expect(codec.valid("MatchState", g.match_state()), "initial schema")
	var first_id = g.registry[12]
	var r = request(g, "e2", "e4")
	var response = g.submit_request(r, g.players.w)
	expect(response.ok and g.revision == 1, "admit move")
	expect(g.registry[28] == first_id, "piece identity survives move")
	expect(g.submit_request(r, g.players.w) == response and g.revision == 1, "idempotent exact retry")
	var reused = r.duplicate()
	reused.to = "e3"
	expect(g.submit_request(reused, g.players.w).error.code == "INVALID_PAYLOAD", "request ID payload conflict")
	var stale = request(g, "e7", "e5", "stale")
	stale.expectedRevision = 0
	expect(g.submit_request(stale, g.players.b).error.code == "STALE_REVISION", "reject stale")
	var forged = request(g, "e7", "e5", "forged")
	expect(g.submit_request(forged, g.players.w).error.code == "FORBIDDEN", "bind player identity")
	for m in [["e7", "e5"], ["g1", "f3"], ["b8", "c6"]]:
		expect(g.play(m[0], m[1]).ok, "play normal move")
		expect(codec.valid("MatchState", g.match_state()), "ongoing schema")
		snapshots.append({"type": "MatchState", "payload": g.match_state()})
	var prior_revision = g.revision
	expect(g.undo() and g.revision > prior_revision and g.engine.history.size() == 3, "undo invalidates stale branch revisions")
	g.authority_mode = "server"
	expect(not g.undo() and not g.set_paused(true), "server cannot use local undo or pause")
	g.authority_mode = "local"
	g.allow_undo = false
	expect(not g.undo(), "undo permission")
	g.allow_undo = true
	g.new_game(10000, 2000)
	g.start_clock()
	g.advance_msec(1000)
	expect(g.remaining.w == 9000 and g.remaining.b == 10000, "active clock only")
	g.last_poll = -1
	g.play("e2", "e4")
	expect(g.remaining.w == 11000 and g.engine.turn == "b", "Fischer increment once")
	g.set_paused(true)
	var paused = g.remaining.duplicate()
	g.advance_msec(3000)
	expect(g.remaining == paused, "pause stops clock")
	expect(not g.play("e7", "e5").ok, "pause rejects moves")
	g.set_paused(false)
	g.advance_msec(10000)
	expect(g.engine.result == "1-0" and g.remaining.b == 0, "timeout")
	expect(not g.play("e7", "e5").ok, "no move after flag")
	g.new_game(1000, 0, "7k/8/8/8/8/8/7r/K7 b - - 0 1")
	g.start_clock()
	g.advance_msec(1000)
	expect(g.engine.result == "1/2-1/2", "flag with bare king opponent is draw")
	g.new_game(1000, 0, "7k/7q/8/8/8/8/N7/K7 b - - 0 1")
	g.start_clock()
	g.advance_msec(1000)
	expect(g.engine.result == "1/2-1/2", "queen flags against lone knight: no possible mate")
	g.new_game(0, 0)
	g.start_clock()
	g.advance_msec(999999)
	expect(g.engine.result.is_empty(), "untimed does not flag")
	g.new_game(1000)
	g.started = true
	g.last_poll = 0
	expect(not g.submit_request(request(g, "e2", "e4", "flag"), g.players.w, 1001).ok and g.engine.reason == "Time expired", "move admission charges elapsed time first")
	for item in [["r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1", "e1", "g1", "q"], ["7k/8/8/3pP3/8/8/8/K7 w - d6 0 1", "e5", "d6", "q"], ["1r5k/P7/8/8/8/8/8/K7 w - - 0 1", "a7", "b8", "n"]]:
		g.new_game(0, 0, item[0])
		var ids = g.registry.duplicate()
		expect(g.play(item[1], item[2], item[3]).ok, "special move admission")
		expect(codec.valid("MatchState", g.match_state()), "special move schema")
		var at = Rules.index(item[2])
		expect(g.registry[at] == ids[Rules.index(item[1])], "special move identity")
		for p in g.chess_state().pieces:
			expect(p.role == g.engine.board[Rules.index(p.square)].to_lower(), "registry role matches FEN")
		snapshots.append({"type": "MatchState", "payload": g.match_state()})
		expect(g.undo() and g.registry == ids, "undo restores entire registry")
	var old = g.match_state()
	expect(not g.new_game(10000, 0, "invalid").ok and g.match_state() == old, "invalid load preserves session")
	g.new_game()
	g.agree_draw()
	expect(g.engine.reason == "Draw by agreement", "agreed draw")
	g.new_game()
	g.resign()
	expect(g.engine.result == "0-1" and codec.valid("MatchState", g.match_state()), "resign schema")
	var args = OS.get_cmdline_user_args()
	if args.size() == 1:
		var file = FileAccess.open(args[0], FileAccess.WRITE)
		file.store_string(JSON.stringify(snapshots, "", true, true))
	print("MATCH: ", checks, " checks; failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
