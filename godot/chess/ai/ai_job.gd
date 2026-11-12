class_name ChessAIJob
extends RefCounted
## Runs one ChessAI search without blocking the main loop.
##
## Threaded mode (default wherever worker threads exist; single-threaded web builds are detected by feature tags): the search runs on a worker Thread; the owner polls
## `poll()` each frame. Sliced mode (no threads, or `force_slice`): `poll()` advances the same search for a few
## milliseconds per call; the transposition table makes an interrupted depth resume quickly.
## `cancel()` is always safe: it requests a stop and joins the thread (the search checks the flag every 64
## nodes, so this returns within about a millisecond). The job must be cancelled or finished before it is freed.
var ai: ChessAI
var result: Dictionary = {}
var state = "idle"  # idle | running | done | cancelled
var slice_ms = 6
var sliced = false
var _thread: Thread
var _mutex = Mutex.new()
var _done = false
var _engine
var _config: Dictionary = {}

func start(source_engine, p_ai: ChessAI, opts: Dictionary = {}, force_slice: bool = false) -> void:
	cancel()
	ai = p_ai
	result = {}
	_done = false
	_engine = ChessAI.clone_engine(source_engine)
	_config = ai.config_for(source_engine, opts)
	state = "running"
	sliced = force_slice or not threads_available()
	if sliced:
		ai.search.begin(_engine, _config)
		return
	_thread = Thread.new()
	ai.search.begin(_engine, _config)
	if _thread.start(_worker) != OK:
		_thread = null
		sliced = true

## Godot has no can_use_threads(); a web export without the "threads" feature runs single-threaded.
static func threads_available() -> bool:
	return not (OS.has_feature("web") and not OS.has_feature("threads"))

func _worker() -> void:
	while not ai.search.step(0):
		pass
	var value = ai.search.result()
	_mutex.lock()
	result = value
	_done = true
	_mutex.unlock()

## Call once per frame. Returns true when `result` is final.
func poll() -> bool:
	if state != "running":
		return state == "done"
	if sliced:
		if ai.search.step(slice_ms * 1000):
			result = ai.search.result()
			state = "done"
			ai.last_result = result
			return true
		return false
	_mutex.lock()
	var finished = _done
	_mutex.unlock()
	if not finished:
		return false
	_thread.wait_to_finish()
	_thread = null
	state = "done"
	ai.last_result = result
	return true

func cancel() -> void:
	if state == "running":
		if ai != null:
			ai.search.request_stop()
		if _thread != null:
			_thread.wait_to_finish()
			_thread = null
		state = "cancelled"
		result = {}
	elif _thread != null:
		_thread.wait_to_finish()
		_thread = null

func is_running() -> bool:
	return state == "running"
