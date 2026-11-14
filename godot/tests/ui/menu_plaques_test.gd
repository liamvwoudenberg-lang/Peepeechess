extends SceneTree
const AppScene = preload("res://ui/application.tscn")
const Settings = preload("res://ui/application_settings.gd")
const Prefs = preload("res://ui/theme/ui_prefs.gd")
var failures := 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	Settings.loaded = true
	Settings.intro_seen = true
	Settings.token = ""
	Prefs.loaded = true
	Prefs.reset_defaults()
	root.size = Vector2i(1280, 800)
	var app = AppScene.instantiate()
	root.add_child(app)
	for i in 4:
		await process_frame
	var plaques = app.scene3d.camera.get_node_or_null("MenuPlaques")
	check(plaques != null, "3D menu plaques exist in the castle camera")
	if plaques != null:
		check(plaques.entries.size() >= 5, "all main actions have a plaque")
		plaques._sync()
		var first: Dictionary = plaques.entries[0]
		var button: Button = first.button
		check(first.root.visible and first.edge.scale.x > 0 and first.edge.scale.y > 0, "plaque fits the visible action")
		button.grab_focus()
		await process_frame
		check(first.target == 1.0, "keyboard or controller focus highlights the matching plaque")
		Prefs.reduce_motion = true
		plaques._set_hover(first, true)
		check(first.highlight == 1.0, "reduced motion uses an immediate highlight")
		root.size = Vector2i(540, 960)
		for i in 3:
			await process_frame
		plaques._sync()
		check(first.edge.scale.x > 0 and first.edge.scale.y > 0, "plaques resize with the portrait layout")
	app.navigate("home")
	for i in 3:
		await process_frame
	check(app.scene3d.camera.find_children("MenuPlaques*", "Node3D", false, false).size() == 1, "rebuilding home removes old plaques")
	app.navigate("settings")
	await process_frame
	check(app.scene3d == null, "leaving home releases the 3D menu")
	app.queue_free()
	await process_frame
	Prefs.reset_defaults()
	print("Menu plaques: %d failures" % failures)
	quit(0 if failures == 0 else 1)
