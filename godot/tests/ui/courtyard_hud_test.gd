extends SceneTree
## Exercises the real match UI: full viewport, reachable drawer, true 2D, and a single combat-visibility barrier.
const Main = preload("res://app/main.tscn")
const Hud = preload("res://ui/game_hud.gd")
const Settings = preload("res://ui/application_settings.gd")
const Prefs = preload("res://ui/theme/ui_prefs.gd")
const Check = preload("res://tests/ui/overlap_check.gd")
var checks = 0
var failures: Array = []
func _init() -> void:
	call_deferred("run")
func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL: ", label)
func settle() -> void:
	for i in 5:
		await process_frame
func run() -> void:
	Settings.loaded = true
	Settings.preferred_3d = false
	Prefs.loaded = true
	Prefs.reduce_motion = true
	for config in [[Vector2i(1280, 800), 1.0], [Vector2i(800, 600), 1.5], [Vector2i(640, 960), 1.0]]:
		root.size = config[0]
		root.content_scale_factor = config[1]
		Settings.launch = {"mode": "classic", "initialMs": 600000, "incrementMs": 0, "view3d": false}
		var m = Main.instantiate()
		root.add_child(m)
		await settle()
		expect(m.board_panel.size.is_equal_approx(m.size), "board viewport fills the match window")
		expect(m.board_2d.visible and not m.board_3d.visible, "Classic 2D uses the real illustrated board")
		expect(not m.info_panel.visible and not m.history_text.is_visible_in_tree(), "history occupies no permanent screen space")
		expect(Check.problems(m).is_empty() and Check.overlaps(m).is_empty(), "floating HUD fits without overlapping controls")
		expect(m.game.play("e2", "e4").ok and m.game.play("e7", "e5").ok, "opening moves still use original chess authority")
		Hud.toggle_drawer(m)
		await settle()
		expect(m.info_panel.visible and m.history_text.is_visible_in_tree(), "menu opens existing actions and history")
		expect(Check.problems(m.info_panel).is_empty(), "drawer stays inside the window at this UI scale")
		Hud.toggle_drawer(m)
		var event = InputEventKey.new()
		event.keycode = KEY_F1
		event.pressed = true
		m._unhandled_input(event)
		await settle()
		expect(m.hud.help.visible, "F1 opens optional chess controls")
		Hud.set_combat(m, true)
		await settle()
		expect(not m.hud.chrome.visible and not m.status_label.is_visible_in_tree() and not m.view_button.is_visible_in_tree(), "combat hides all chess HUD")
		expect(not m.info_panel.is_visible_in_tree() and not m.hud.help.is_visible_in_tree(), "combat also closes history and help")
		Hud.toggle_drawer(m)
		expect(not m.info_panel.visible, "chess drawer cannot open during combat")
		Hud.set_combat(m, false)
		expect(m.hud.chrome.visible and not m.info_panel.visible and not m.hud.help.visible, "return restores compact HUD only")
		m.queue_free()
		await settle()
	root.content_scale_factor = 1.0
	print("COURTYARD HUD: %d checks; failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
