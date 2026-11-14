extends Node
## Dev tool: renders the real combat arena (paladins) from the player's camera at a few fighter positions and saves PNGs.
##   xvfb-run -a godot --path godot --rendering-driver opengl3 --resolution 1280x720 res://combat/tools/arena_shots.tscn -- out=/tmp/shots pair=qp
const ARENA := "res://combat/arena.tscn"
var _arena: CombatArena
var _frame := 0
var _out := "/tmp/arena_shots"
var _pair := "qp"
const CLIPS := [["idle", 0.0], ["light_1", 0.36], ["light_2", 0.36], ["heavy", 0.36], ["block", 0.5], ["parry", 0.4], ["dodge", 0.4], ["defeat", 0.9]]
var _cam: Camera3D
var _steps := [
	{"at": 260, "w": Vector3(0, 0, -1.2), "b": Vector3(0, 0, 1.2), "name": "center"},
	{"at": 360, "w": Vector3(6.2, 0, 0), "b": Vector3(4.6, 0, 0), "name": "at_wall_facing_wall"},
	{"at": 460, "w": Vector3(-6.2, 0, 0), "b": Vector3(-4.4, 0, 0.3), "name": "other_wall"},
	{"at": 560, "w": Vector3(0, 0, 6.3), "b": Vector3(0, 0, 4.7), "name": "south_wall"},
]
func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_out = arg.substr(4)
		elif arg.begins_with("pair="):
			_pair = arg.substr(5)
	DirAccess.make_dir_recursive_absolute(_out)
	_arena = (load(ARENA) as PackedScene).instantiate()
	add_child(_arena)
	_arena.configure_seats({"player-white": {"type": "human", "scheme": "kb1"}, "player-black": {"type": "ai", "skill": 0.0}})
	var reply: Dictionary = _arena.start_battle(FighterRoster.build_request(_pair[0], _pair[1], "w", "shots", 9, 0))
	assert(reply["ok"], "start failed")
func _process(_d: float) -> void:
	_frame += 1
	for f in _arena.sim.fighters:
		f.health.current = f.health.maximum   # the shots are about the camera and the model, not the result
	for s in _steps:
		if _frame == int(s["at"]) - 20:
			_arena.sim.fighters[0].teleport(s["w"])
			_arena.sim.fighters[1].teleport(s["b"])
		if _frame == int(s["at"]):
			get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [_out, _pair, s["name"]])
	if _frame >= 600 and _frame < 600 + CLIPS.size() * 12:
		_closeup((_frame - 600) / 12, (_frame - 600) % 12)
	if _frame > 600 + CLIPS.size() * 12 + 2:
		get_tree().quit()

func _closeup(index: int, phase: int) -> void:
	var visual: Node3D = _arena.find_children("Visual_*", "", false, false)[0]
	var fighter = _arena.sim.fighters[0]
	if _cam == null:
		_cam = Camera3D.new()
		add_child(_cam)
		_cam.current = true
		fighter.teleport(Vector3(0, 0, 0))
		_arena.sim.fighters[1].teleport(Vector3(0, 0, 5))
	var base: Vector3 = fighter.global_position
	_cam.global_position = base + Vector3(1.9, 1.35, 2.3)
	_cam.look_at(base + Vector3(0, 0.95, 0), Vector3.UP)
	var clip: String = CLIPS[index][0]
	var player: AnimationPlayer = visual.player if "player" in visual else null
	if player != null and player.has_animation(clip):
		if phase == 0:
			player.play(clip, 0.0)
		if phase == 6:
			player.seek(float(CLIPS[index][1]) * player.current_animation_length, true)
			player.pause()
		if phase == 10:
			get_viewport().get_texture().get_image().save_png("%s/%s_clip_%s.png" % [_out, _pair, clip])
