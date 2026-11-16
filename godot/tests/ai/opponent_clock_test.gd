extends SceneTree
## Exercise the real asynchronous controller with a busy presentation and a live clock.
var checks = 0
var failures: Array = []
var busy = true

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL: ", label)

func _init() -> void:
	call_deferred("run")

func until(condition: Callable) -> bool:
	var deadline = Time.get_ticks_msec() + 2000
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	return condition.call()

func controller(game: ClassicMatch) -> ComputerOpponent:
	var opponent = ComputerOpponent.new()
	opponent.force_slice = true
	opponent.base_delay_ms = 60000  # deliberately exaggerated: a live clock must bound cosmetics
	opponent.animation_busy = func(): return busy
	root.add_child(opponent)
	opponent.bind(game)
	return opponent

func run() -> void:
	var game = ClassicMatch.new()
	game.new_game(4000)
	game.start_clock()
	var opponent = controller(game)
	opponent.begin({"level": 1, "color": "b", "seed": 42})
	expect(await until(func(): return game.engine.history.size() == 1), "a timed computer moves despite a busy animation and a long cosmetic delay")
	expect(game.engine.result.is_empty() and game.remaining.w > 0, "the move is admitted before flag fall")
	expect(not opponent.is_thinking(), "the completed move leaves no pending search")
	opponent.dispose()
	opponent.free()

	game = ClassicMatch.new()
	game.new_game(0)
	opponent = controller(game)
	opponent.base_delay_ms = 0
	opponent.begin({"level": 1, "color": "b", "seed": 42})
	expect(await until(func(): return not opponent._ready_move.is_empty()), "untimed search finishes while presentation is busy")
	expect(game.engine.history.is_empty(), "untimed games wait for their animation")
	busy = false
	expect(await until(func(): return game.engine.history.size() == 1), "untimed move proceeds when the animation ends")
	opponent.dispose()
	opponent.free()

	# A result already calculated for the correct FEN cannot hold a flagged game open.
	game = ClassicMatch.new()
	game.new_game(1000)
	game.start_clock()
	busy = true
	opponent = controller(game)
	opponent.begin({"level": 1, "color": "b", "seed": 42})
	opponent.set_process(false)
	opponent._job.cancel()
	opponent._job = null
	opponent._ready_move = {"ok": true, "from": "e2", "to": "e4", "promotion": "", "score": 0}
	game.remaining.w = 1
	game.last_poll = Time.get_ticks_msec() - 2
	opponent._try_play()
	expect(game.engine.result == "0-1" and game.engine.reason == "Time expired", "a ready move polls and honours flag fall before cosmetic work")
	expect(game.engine.history.is_empty() and not opponent.is_thinking(), "flag fall cancels the stale move and its presentation delay")
	opponent.dispose()
	opponent.free()
	print("AI CLOCK: ", checks, " checks; failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
