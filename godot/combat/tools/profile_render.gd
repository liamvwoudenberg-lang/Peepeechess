extends Node
## Device-independent RENDER metrics for a running fight (draw calls, primitives, objects, memory) plus
## wall-clock frame time. Run windowed (software GL under Xvfb works):
##   xvfb-run -a godot --path godot --rendering-driver opengl3 --resolution 1280x720 res://combat/tools/profile_render.tscn -- frames=600 pair=pn [lod=1]
## Frame TIME under software GL is NOT representative of a phone GPU; draw calls / primitives / objects / texture
## memory are what transfer to a mobile budget. Prints a markdown row and quits.
const ARENA := "res://combat/arena.tscn"
var _frame := 0
var _frames := 600
var _pair := "pn"
var _samples: Array = []
var _times: Array = []
var _last := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("frames="):
			_frames = int(arg.substr(7))
		elif arg.begins_with("pair="):
			_pair = arg.substr(5)
		elif arg == "lod=1":
			CharacterModel.prefer_lod1 = true
	var arena: CombatArena = (load(ARENA) as PackedScene).instantiate()
	add_child(arena)
	arena.configure_seats({"player-white": {"type": "ai", "skill": 0.75}, "player-black": {"type": "ai", "skill": 0.6}})
	var reply: Dictionary = arena.start_battle(FighterRoster.build_request(_pair[0], _pair[1], "w", "render-prof", 9, 0))
	assert(reply["ok"], "start failed")
	_last = Time.get_ticks_usec()


func _process(_delta: float) -> void:
	_frame += 1
	var now := Time.get_ticks_usec()
	if _frame > 240:  # skip the countdown / warm-up
		_times.append(now - _last)
		_samples.append([
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		])
	_last = now
	if _frame >= _frames:
		_report()
		get_tree().quit()


func _report() -> void:
	var max_calls := 0
	var max_prims := 0
	var max_objs := 0
	var sum_calls := 0.0
	var sum_prims := 0.0
	for s in _samples:
		max_calls = maxi(max_calls, int(s[0]))
		max_prims = maxi(max_prims, int(s[1]))
		max_objs = maxi(max_objs, int(s[2]))
		sum_calls += float(s[0])
		sum_prims += float(s[1])
	var n := maxf(1.0, float(_samples.size()))
	_times.sort()
	var median_ms := float(_times[_times.size() / 2]) / 1000.0 if not _times.is_empty() else 0.0
	print("| %s%s | %.0f / %d | %.0fk / %.0fk | %d | %d MB | %.1f ms |" % [_pair, " LOD1" if CharacterModel.prefer_lod1 else "", sum_calls / n, max_calls,
			sum_prims / n / 1000.0, max_prims / 1000.0, max_objs,
			int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)) / 1048576, median_ms])
	print("(columns: draw calls mean/max, primitives mean/max, objects max, texture memory, median frame time under software GL)")
