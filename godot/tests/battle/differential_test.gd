extends SceneTree
const Rules = preload("res://chess/battle_rules.gd")
func _init() -> void:
	var args = OS.get_cmdline_user_args()
	var cases = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var count = 0
	var engine = Rules.new()
	for case in cases:
		if not engine.load_fen(case.fen).ok:
			printerr("Cannot load C0 reference: ", case.fen)
			quit(1)
			return
		var actual: Array = []
		for m in engine.legal_moves():
			actual.append(Rules.square(m.from) + Rules.square(m.to) + m.promotion)
		actual.sort()
		case.legal.sort()
		if actual != case.legal:
			printerr("C0 legal mismatch: ", case.fen, " actual=", actual, " expected=", case.legal)
			quit(1)
			return
		for move in case.moves:
			engine.load_fen(case.fen)
			var inspected = engine.inspect_move(move.from, move.to, move.promotion)
			var answer = engine.move(move.from, move.to, move.promotion) if move.outcome == "quiet" else engine.settle_capture(inspected.move, move.outcome)
			var fields = engine.fen().split(" ")
			fields[3] = engine.position_key().split(" ")[3]
			if not answer.ok or " ".join(fields) != move.after or engine.reason != move.reason or engine.result != move.result:
				printerr("C0 outcome mismatch: ", case.fen, " ", move, " got=", answer, " fen=", fields, " result=", engine.result, " reason=", engine.reason)
				quit(1)
				return
			count += 1
	print("BATTLE DIFFERENTIAL: ", cases.size(), " positions, ", count, " outcomes matched existing C0 authority")
	quit(0)
