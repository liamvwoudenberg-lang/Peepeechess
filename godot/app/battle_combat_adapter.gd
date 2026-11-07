class_name BattleCombatAdapter
extends Node
## Codex-owned bridge to Claude's arena; contains no combat mechanics or winner logic.
signal arena_ready
signal snapshot_received(snapshot: Dictionary)
signal result_received(result: Dictionary)
signal failed(message: String)
var scene_path = "res://combat/arena.tscn"
var arena: Node
var _loading = false
var _generation = 0
var _host: Node

func available() -> bool:
	return ResourceLoader.exists(scene_path, "PackedScene")

func begin_load(_request: Dictionary, host: Node) -> Dictionary:
	stop()
	if not available():
		return {"ok": false, "error": "Combat is unavailable in this build. Return to the board or play Classic."}
	_host = host
	var error = ResourceLoader.load_threaded_request(scene_path, "PackedScene")
	if error != OK:
		return {"ok": false, "error": "The combat scene could not be queued for loading."}
	_loading = true
	return {"ok": true}

func _process(_delta: float) -> void:
	if not _loading:
		return
	var status = ResourceLoader.load_threaded_get_status(scene_path)
	if status in [ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE]:
		_loading = false
		failed.emit("The combat scene failed to load.")
	elif status == ResourceLoader.THREAD_LOAD_LOADED:
		_loading = false
		var resource = ResourceLoader.load_threaded_get(scene_path)
		if not resource is PackedScene or not is_instance_valid(_host):
			failed.emit("The combat scene or mount point is unavailable.")
			return
		arena = resource.instantiate()
		for method in ["start_battle", "stop_battle"]:
			if not arena.has_method(method):
				stop()
				failed.emit("The combat scene does not implement " + method + ".")
				return
		for event in ["combat_snapshot", "battle_finished"]:
			if not arena.has_signal(event):
				stop()
				failed.emit("The combat scene does not expose " + event + ".")
				return
		arena.connect("combat_snapshot", _snapshot.bind(_generation))
		arena.connect("battle_finished", _result.bind(_generation))
		_host.add_child(arena)
		arena_ready.emit()

func start(request: Dictionary) -> Dictionary:
	if not is_instance_valid(arena):
		return {"ok": false, "error": "The combat scene is not ready."}
	var response = arena.call("start_battle", request.duplicate(true))
	return response if response is Dictionary and response.has("ok") else {"ok": true}

func _snapshot(value: Variant, generation: int) -> void:
	if generation == _generation and value is Dictionary:
		snapshot_received.emit(value.duplicate(true))

func _result(value: Variant, generation: int) -> void:
	if generation == _generation and value is Dictionary:
		result_received.emit(value.duplicate(true))

func stop() -> void:
	_generation += 1
	_loading = false
	if is_instance_valid(arena):
		var old = arena
		arena = null
		if old.has_method("stop_battle"):
			old.call("stop_battle")
		if old.get_parent():
			old.get_parent().remove_child(old)
		old.queue_free()

func _exit_tree() -> void:
	stop()
