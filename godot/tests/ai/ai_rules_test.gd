extends SceneTree
## Legality and determinism of seeded self-play, levels 1..6. Usage: ... ai_rules_test.gd -- [shard=0 shards=1]
const Support = preload("res://tests/ai/ai_support.gd")
const GAMES = 42
const MAX_PLIES = 44
const NODE_SCALE = 0.05
var checks = 0
var failures: Array = []
func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("FAIL: ", label)
func _init() -> void:
	call_deferred("run")
func arg(name: String, fallback: int) -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(name + "="):
			return int(a.get_slice("=", 1))
	return fallback
func run() -> void:
	var shard = arg("shard", 0)
	var shards = arg("shards", 1)
	var played = 0
	var ended = 0
	var capped = 0
	var plies = 0
	var started = Time.get_ticks_msec()
	var per_level = {}
	for game in range(GAMES):
		if game % shards != shard:
			continue
		# Pairings cover every level on both colours: (1,1) (2,2) ... then mixed pairs.
		var white = (game + game / 6) % 6 + 1
		var black = white if game < 12 else (game * 5 + game / 6) % 6 + 1
		var outcome = Support.play_game(white, black, 1000 + game, MAX_PLIES, NODE_SCALE)
		played += 1
		plies += outcome.plies
		expect(outcome.illegal == 0, "game %d (L%d vs L%d): every AI move was legal" % [game, white, black])
		var engine = outcome.engine
		expect(outcome.plies == MAX_PLIES or not engine.result.is_empty(), "game %d ends legally (move cap or a rules result)" % game)
		if not engine.result.is_empty():
			ended += 1
			expect(engine.result in ["1-0", "0-1", "1/2-1/2"] and not engine.reason.is_empty(), "game %d result %s / %s is a rules outcome" % [game, engine.result, engine.reason])
			if engine.reason == "Checkmate":
				expect(engine.legal_moves().is_empty() and engine.in_check(), "game %d checkmate is real" % game)
			if engine.reason == "Stalemate":
				expect(engine.legal_moves().is_empty() and not engine.in_check(), "game %d stalemate is real" % game)
		else:
			capped += 1
		var copy = ClassicChess.new()
		expect(copy.load_fen(engine.fen()).ok, "game %d final FEN is a valid position" % game)
		for level in [white, black]:
			per_level[level] = per_level.get(level, 0) + 1
	# Determinism: the same seed and levels give the identical move list; a different seed (levels 1-3 are randomised) does not have to.
	for pair in [[1, 2], [3, 3], [4, 6]]:
		if pair[0] % shards != shard:
			continue
		var first = Support.play_game(pair[0], pair[1], 77, 30, NODE_SCALE)
		var second = Support.play_game(pair[0], pair[1], 77, 30, NODE_SCALE)
		expect(first.moves == second.moves and not first.moves.is_empty(), "same seed reproduces the game (levels %d/%d)" % [pair[0], pair[1]])
	var varied_a = Support.play_game(1, 1, 5, 24, NODE_SCALE)
	var varied_b = Support.play_game(1, 1, 6, 24, NODE_SCALE)
	if shard == 0:
		expect(varied_a.moves != varied_b.moves, "level 1 varies with the seed")
	print("RULES shard %d/%d: %d games, %d ended by rules, %d move-capped, %d plies, levels used %s, %.1f s" % [shard, shards, played, ended, capped, plies, str(per_level), (Time.get_ticks_msec() - started) / 1000.0])
	print("AI RULES: ", checks, " checks; failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
