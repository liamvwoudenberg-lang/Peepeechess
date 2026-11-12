extends SceneTree
const Rules = preload("res://chess/chess_engine.gd")
func _init() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 1:
		printerr("Expected generated chess.js corpus path")
		quit(1)
		return
	var cases = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var e = Rules.new()
	var total = 0
	for case in cases:
		if not e.load_fen(case.fen).ok:
			printerr("Rejected reference FEN: ", case.fen)
			quit(1)
			return
		var legal: Array = []
		for m in e.legal_moves():
			legal.append(Rules.square(m.from) + Rules.square(m.to) + m.promotion)
		legal.sort()
		var expected: Array = []
		for m in case.moves:
			expected.append(m.uci)
		expected.sort()
		if legal != expected:
			printerr("Legal mismatch: ", case.fen, " actual=", legal, " expected=", expected)
			quit(1)
			return
		for m in case.moves:
			var outcome = e.move(m.uci.substr(0, 2), m.uci.substr(2, 2), m.uci.substr(4) if m.uci.length() == 5 else "q")
			if not outcome.ok or outcome.san != m.san or e.fen() != m.after:
				printerr("Move mismatch: ", case.fen, " ", m, " got=", outcome, " fen=", e.fen())
				quit(1)
				return
			if not e.undo() or e.fen() != case.fen:
				printerr("Undo mismatch: ", case.fen)
				quit(1)
				return
			total += 1
	print("DIFFERENTIAL: ", cases.size(), " positions, ", total, " legal moves/SAN/FEN/undo matched chess.js")
	quit(0)
