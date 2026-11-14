extends SceneTree
## Real local pit lifecycle plus the app-owned compact HUD, through both chess projections.
const Main = preload("res://app/main.tscn")
const Settings = preload("res://ui/application_settings.gd")
const Prefs = preload("res://ui/theme/ui_prefs.gd")
var checks = 0
var failures: Array = []
func _init() -> void:
	call_deferred("run")
func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL: ", label)
func run() -> void:
	root.size = Vector2i(1200, 800)
	Settings.loaded = true
	Prefs.loaded = true
	Prefs.reduce_motion = true
	BoardTheme.piece_set = "procedural"
	Engine.physics_ticks_per_second = 600
	Engine.max_fps = 0
	for three_d in [false, true]:
		Settings.launch = {"mode": "battle", "initialMs": 0, "view3d": three_d}
		var app = Main.instantiate()
		root.add_child(app)
		await process_frame
		await process_frame
		app.game.new_game(0, 0, "7k/8/8/4q3/3P4/8/8/7K w - - 0 1")
		app.board_3d.animation_enabled = false
		app.board_2d.animation_enabled = false
		var world = app.board_3d.world
		world.auto_advance = false
		expect(app.board_2d.visible == not three_d, "correct chess projection before pit battle")
		expect(app.game.play("d4", "e5").ok, "capture prepares original transaction")
		var frozen: String = app.game.engine.fen()
		app._start_battle_pressed()
		expect(app.bridge.is_presenting() and app.board_3d.visible and not app.board_2d.visible, "both projections enter the existing pit world")
		expect(app.game.engine.fen() == frozen and app.game.revision == 0, "transition does not settle the chess move")
		var phases: Array = []
		var arena_seen = false
		var forced = false
		var finished = false
		for frame in 2400:
			world.advance(1.0 / 60.0)
			await process_frame
			if not world.pit.phase in phases:
				phases.append(world.pit.phase)
			if app.battle_adapter.arena != null:
				var arena = app.battle_adapter.arena
				if arena.hud != null and not arena_seen:
					arena_seen = true
					expect(arena.hud is CourtyardCombatHud, "local adapter installs compact HUD")
					expect(arena.hud._message_box == null and arena.hud._icon_textures.size() == 4, "no centre event stack; four compact actions")
					expect(arena.overlay.target_mode() == ControlOverlay.Mode.OFF, "controls help starts optional")
				if world.pit.phase == PitSequence.Phase.COMBAT and arena.sim.phase == CombatSimulation.Phase.ACTIVE:
					expect(not app.hud.chrome.visible and not app.battle_resign.visible and not app.battle_title.visible, "fight hides every chess HUD and footer")
					if not forced:
						forced = true
						arena.sim.defender().health.apply_damage(100000)
			if world.pit.is_idle() and app.game.revision == 1:
				finished = true
				break
		expect(arena_seen and forced and finished, "actual pit fight resolves and returns")
		for phase in [PitSequence.Phase.TRAPDOOR_OPEN, PitSequence.Phase.DROP, PitSequence.Phase.COMBAT, PitSequence.Phase.RESOLVE, PitSequence.Phase.CLIMB, PitSequence.Phase.RETURN]:
			expect(phase in phases, "existing trapdoor/drop/combat/climb phase remains %s" % phase)
		expect(app.board_2d.visible == not three_d and app.board_3d.visible == three_d and app._view_3d == three_d, "return restores original true 2D or 3D choice")
		expect(app.hud.chrome.visible and app.interaction.enabled, "compact chess HUD and board input return")
		app.queue_free()
		await process_frame
		await process_frame
	Engine.physics_ticks_per_second = 60
	print("COURTYARD HUD INTEGRATION: %d checks; failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
