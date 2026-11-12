extends SceneTree
## Level 6 must beat level 1 over 10 colour-alternated, seeded games. Node limits are scaled down (NODE_SCALE) so the
## test is fast and machine-independent; at the cap a game is adjudicated by material (>= 3 pawns ahead wins),
## which is reported separately from real checkmates.
const Support = preload("res://tests/ai/ai_support.gd")
const GAMES = 10
const MAX_PLIES = 110
const NODE_SCALE = 0.04
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
	var points = 0.0
	var mates = 0
	var adjudicated = 0
	var started = Time.get_ticks_msec()
	for game in range(GAMES):
		var strong_white = game % 2 == 0
		var outcome = Support.play_game(6 if strong_white else 1, 1 if strong_white else 6, 500 + game, MAX_PLIES, NODE_SCALE)
		expect(outcome.illegal == 0, "game %d legal" % game)
		var engine = outcome.engine
		var strong = "w" if strong_white else "b"
		var verdict = "draw"
		if engine.result == "1/2-1/2" or (engine.result == "" and absi(Support.material(engine.board)) < 3):
			points += 0.5
		else:
			var white_won = engine.result == "1-0" or (engine.result == "" and Support.material(engine.board) >= 3)
			var strong_won = white_won == strong_white
			points += 1.0 if strong_won else 0.0
			verdict = "level 6 wins" if strong_won else "level 1 wins"
			if engine.result != "":
				mates += 1 if strong_won else 0
			else:
				adjudicated += 1
		print("game %d: L6 as %s -> %s (%s), %d plies, material %d" % [game, "White" if strong_white else "Black", verdict, engine.reason if engine.result != "" else "adjudicated at cap", outcome.plies, Support.material(engine.board)])
	expect(points >= 7.0, "level 6 beats level 1: %.1f / %d points" % [points, GAMES])
	print("STRENGTH: level 6 scored %.1f / %d against level 1 (%d by rules result, %d adjudicated at the move cap), %.1f s" % [points, GAMES, mates, adjudicated, (Time.get_ticks_msec() - started) / 1000.0])
	print("AI STRENGTH: ", checks, " checks; failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
