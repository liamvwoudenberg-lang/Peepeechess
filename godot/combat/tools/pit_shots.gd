extends Node
## Dev tool: plays one Battle Chess capture through the real flow (board -> trapdoor -> drop -> combat -> climb -> return) and saves a
## screenshot every few frames, to look for the camera passing through walls, ceiling or pillars.
##   xvfb-run -a godot --path godot --rendering-driver opengl3 --resolution 1280x720 res://combat/tools/pit_shots.tscn -- out=/tmp/pit kill=defender every=20
const Main := preload("res://app/main.tscn")
const FEN := "7k/8/8/4q3/3P4/8/8/7K w - - 0 1"
var _out := "/tmp/pit_shots"
var _kill := "defender"
var _every := 20
var _frame := 0
var _app
var _world: BattleWorld
var _started := false
var _forced := false
func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out="): _out = arg.substr(4)
		elif arg.begins_with("kill="): _kill = arg.substr(5)
		elif arg.begins_with("every="): _every = int(arg.substr(6))
	DirAccess.make_dir_recursive_absolute(_out)
	_app = Main.instantiate()
	add_child(_app)
	await get_tree().process_frame
	await get_tree().process_frame
	_app._switch_mode(1)
	_app.set_view(true)
	_app.game.new_game(0, 0, FEN)
	_app.board_3d.animation_enabled = false
	_world = _app.board_3d.world
	_world.auto_advance = false
	await get_tree().process_frame
	_app.game.play("d4", "e5")
	await get_tree().process_frame
	_app._start_battle_pressed()
	_started = true
func _process(_d: float) -> void:
	if not _started:
		return
	_frame += 1
	_world.advance(1.0 / 60.0)
	var pit := _world.pit
	if pit.phase == PitSequence.Phase.COMBAT and not _forced and _world.chamber.arena_mount.get_child_count() > 0:
		var arena: CombatArena = _world.chamber.arena_mount.get_child(0)
		if arena.sim.countdown_remaining == 0 and _frame % 7 == 0:
			_forced = true
			var loser = arena.sim.defender() if _kill == "defender" else arena.sim.attacker()
			loser.health.apply_damage(100000)
	if _frame % _every == 0:
		get_viewport().get_texture().get_image().save_png("%s/f%04d_%s.png" % [_out, _frame, ["IDLE", "FOCUS", "TRAPDOOR", "DROP", "COMBAT", "RESOLVE", "CLIMB", "RETURN"][pit.phase]])
	if (pit.is_idle() and _frame > 60) or _frame > 4000:
		get_tree().quit()
