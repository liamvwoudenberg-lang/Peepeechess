extends SceneTree
const Rules = preload("res://chess/chess_engine.gd")
var failures: Array = []
var checks = 0

func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("FAIL: ", label)

func _init() -> void:
	var e = Rules.new()
	expect(e.fen() == Rules.START_FEN, "initial FEN")
	for depth in range(1, 4):
		var got = e.perft(depth)
		expect(got == [20, 400, 8902][depth - 1], "start perft %s = %s" % [depth, got])
	expect(e.perft(4) == 197281, "start perft 4")
	print("start perft passed")
	var special = [
		["r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", [48, 2039, 97862]],
		["8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", [14, 191, 2812]],
		["r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1", [6, 264, 9467]],
		["rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8", [44, 1486, 62379]],
	]
	for item in special:
		expect(e.load_fen(item[0]).ok, "load perft fixture")
		for depth in range(1, 4):
			var got = e.perft(depth)
			expect(got == item[1][depth - 1], "special perft %s/%s = %s" % [special.find(item), depth, got])
		print("special perft ", special.find(item), " passed")
	e.load_fen(Rules.START_FEN)
	for m in [["f2", "f3"], ["e7", "e5"], ["g2", "g4"], ["d8", "h4"]]:
		expect(e.move(m[0], m[1]).ok, "Fool's mate move")
	expect(e.reason == "Checkmate" and e.result == "0-1" and e.history[-1].san == "Qh4#", "mate and SAN")
	expect(e.undo() and e.result.is_empty(), "undo mate")
	for fen in ["7k/5Q2/6K1/8/8/8/8/8 b - - 0 1", "8/8/8/8/8/8/4k3/6K1 w - - 0 1"]:
		expect(e.load_fen(fen).ok, "terminal load")
		expect(e.result == "1/2-1/2", "stalemate or insufficient material")
	var before = e.fen()
	for bad in ["bad", "8/8/8/8/8/8/8/8 w - - 0 1", "7k/8/8/8/8/8/8/P6K w - - 0 1", "7k/8/8/8/8/8/8/K7 w KK - 0 1", "7k/8/8/8/8/8/8/K7 w - e6 0 1", "7k/8/8/8/8/8/6k1/7K w - - 0 1"]:
		expect(not e.load_fen(bad).ok and e.fen() == before, "invalid FEN transactional: " + bad)
	for item in special:
		e.load_fen(item[0])
		var fen = e.fen()
		var other = Rules.new()
		expect(other.load_fen(fen).ok and other.fen() == fen, "FEN roundtrip")
	# EP discovered-check trap; the pawn must not expose its king to the rook.
	e.load_fen("7k/8/8/r4pPK/8/8/8/8 w - f6 0 1")
	expect(not e.move("g5", "f6").ok, "illegal pinned EP")
	e.load_fen("7k/8/8/3pP3/8/8/8/K7 w - d6 0 1")
	expect(e.move("e5", "d6").ok and e.board[Rules.index("d5")] == "" and e.history[-1].san == "exd6", "EP capture")
	expect(e.undo() and e.ep == Rules.index("d6"), "EP undo")
	for promotion in ["q", "r", "b", "n"]:
		e.load_fen("7k/P7/8/8/8/8/8/K7 w - - 0 1")
		expect(e.move("a7", "a8", promotion).ok and e.board[56] == promotion.to_upper(), "promotion " + promotion)
	e.load_fen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
	expect(e.move("e1", "g1").ok and e.board[5] == "R" and e.history[-1].san == "O-O", "castle short")
	expect(e.move("e8", "c8").ok and e.board[59] == "r", "castle long")
	e.load_fen("r3k2r/8/8/8/8/5r2/8/R3K2R w KQkq - 0 1")
	expect(not e.move("e1", "g1").ok, "cannot castle through check")
	e.load_fen(Rules.START_FEN)
	for cycle in range(4):
		for m in [["g1", "f3"], ["g8", "f6"], ["f3", "g1"], ["f6", "g8"]]:
			expect(e.move(m[0], m[1]).ok, "repeat move")
		if cycle == 1:
			expect("Threefold repetition" in e.claimable_draws() and e.result.is_empty(), "threefold is claimable")
	expect(e.reason == "Fivefold repetition", "fivefold automatic")
	e.load_fen("7k/8/8/8/8/8/R7/K7 w - - 99 1")
	expect("Fifty-move rule" in e.claimable_draws({"from": "a2", "to": "a3"}), "intended fifty move claim")
	expect(e.move("a2", "a3").ok and "Fifty-move rule" in e.claimable_draws() and e.result.is_empty(), "fifty claim, no automatic draw")
	expect(e.claim_draw("Fifty-move rule"), "claim draw")
	e.load_fen("7k/8/8/8/8/8/R7/K7 w - - 149 1")
	e.move("a2", "a3")
	expect(e.reason == "Seventy-five-move rule", "75 automatic")
	e.load_fen("7k/5Q2/6K1/8/8/8/8/8 w - - 149 1")
	e.move("f7", "g7")
	expect(e.reason == "Checkmate", "mate takes precedence over 75")
	e.load_fen(Rules.START_FEN)
	e.move("e2", "e4")
	e.move("e7", "e5")
	expect(e.pgn().ends_with("1. e4 e5 *"), "PGN move numbering")
	e.load_fen("7k/8/8/8/8/8/R7/K7 b - - 0 24")
	e.move("h8", "g8")
	expect('[SetUp "1"]' in e.pgn() and "24... Kg8 *" in e.pgn(), "PGN Black start and FEN setup")
	e.load_fen("7k/8/8/r4pPK/8/8/8/8 w - f6 0 1")
	expect(e.position_key().split(" ")[3] == "-", "repetition ignores pinned EP")
	for item in [
		["7k/7q/8/8/8/8/N7/K7 w - - 0 1", false],
		["7k/7q/8/8/8/8/B7/K7 w - - 0 1", false],
		["7k/7r/8/8/8/8/B7/K7 w - - 0 1", false],
		["7k/7r/8/8/8/8/N7/K7 w - - 0 1", true],
		["7k/7n/8/8/8/8/B7/K7 w - - 0 1", true],
		["7k/8/8/8/8/8/NN6/K7 w - - 0 1", true],
	]:
		expect(e.load_fen(item[0]).ok and e.can_mate("w") == item[1], "timeout mating possibility " + item[0])
	print("ENGINE: ", checks, " checks; failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
