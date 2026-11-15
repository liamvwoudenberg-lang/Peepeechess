extends SceneTree
const Settings = preload("res://ui/application_settings.gd")
const Main = preload("res://app/main.tscn")
var checks = 0
var failures = []
var screen
func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL: ", label)
func _init() -> void:
	call_deferred("run")
func capture() -> void:
	screen.game.new_game(0, 0, "7k/8/8/3p4/4P3/8/8/7K b - - 0 1")
	screen.opponent.computer.cancel_search()
	expect(screen.game.play("d5", "e4").ok, "computer-side capture is admitted")
func run() -> void:
	Settings.loaded = true
	Settings.animations = false
	Settings.launch = {"mode": "battle", "opponent": {"kind": "computer", "level": 4, "color": "w"}}
	BoardTheme.apply({"pieces": "procedural"})
	screen = Main.instantiate()
	root.add_child(screen)
	await process_frame
	await process_frame
	capture()
	expect(screen.opponent._capture_id != "" and screen.fight_button.text == "Fight now", "computer preview schedules automatic entry and explains the shortcut")
	expect(not screen.battle_cancel.visible, "an opponent's move is not offered as a cancellable player move")
	screen.game.paused = true
	screen.opponent._process(5.0)
	expect(screen.battle_flow.phase == "preview" and screen.opponent._capture_remaining > 0, "pause does not consume the readiness preview")
	screen.game.paused = false
	screen.battle_flow.cancel_preview()
	screen.opponent.computer.cancel_search()
	screen.opponent._process(5.0)
	expect(screen.battle_flow.phase == "board" and screen.opponent._capture_id == "", "a cancelled transaction never starts a stale duel")
	capture()
	screen.game.new_game()
	screen.opponent._process(5.0)
	expect(screen.battle_flow.phase == "board" and screen.game.pending_request().is_empty(), "new game invalidates the old preview")
	capture()
	screen.opponent.prepare_capture(screen.game.pending_request(), false)
	screen.opponent._process(5.0)
	expect(screen.battle_flow.phase == "preview", "unavailable combat never starts automatically")
	screen.game.new_game(0, 0, "7k/8/8/3p4/4P3/8/8/7K w - - 0 1")
	screen.game.play("e4", "d5")
	expect(screen.opponent._capture_id == "" and screen.fight_button.text == "Start battle", "human-initiated captures retain their manual preview")
	screen.queue_free()
	await process_frame
	BoardTheme.reset()
	print("COMPUTER CAPTURE: ", checks, " checks; failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
