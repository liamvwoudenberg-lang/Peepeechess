extends SceneTree
## Minimal game-screen layout guard (regression for the stretched-plates bug): at three window sizes the HUD elements
## (menu button, both player plates, turn toast) must have a real size, lie fully inside the viewport, never overlap each other,
## and stay small (no big solid blocks: each element covers less than 6 percent of the screen).
const MainScene = preload("res://app/main.tscn")
const Settings = preload("res://ui/application_settings.gd")
const Prefs = preload("res://ui/theme/ui_prefs.gd")
const SIZES := [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(800, 600)]
var checks := 0
var failures: Array = []

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		print("FAIL: ", label)

func _initialize() -> void:
	call_deferred("_run")

func _settle(frames: int = 4) -> void:
	for _i in frames:
		await process_frame

func _run() -> void:
	UiStyle.loaded = true
	UiStyle.style = "minimal"
	Prefs.reduce_motion = true
	for size in SIZES:
		root.size = size
		Settings.launch = {"mode": "classic", "initialMs": 600000, "incrementMs": 0, "view3d": false}
		var game: Control = MainScene.instantiate()
		root.add_child(game)
		await _settle(6)
		var screen := game.get_viewport_rect()
		var tag := "%dx%d" % [size.x, size.y]
		var overlay := game.find_child("MinimalOverlay", true, false) as Control
		expect(overlay != null, "minimal overlay exists at " + tag)
		if overlay == null:
			game.queue_free()
			continue
		var elements: Array = []
		for child in overlay.get_children():
			if child is Control and child.visible and child.name != "MinimalMenu":
				elements.append(child)
		expect(elements.size() >= 3, "menu button, both plates and the toast are present at " + tag)
		for element in elements:
			var rect: Rect2 = element.get_global_rect()
			expect(rect.size.x > 8 and rect.size.y > 8, "%s has a real size at %s (%s)" % [element.name, tag, rect.size])
			expect(screen.grow(1.0).encloses(rect), "%s is fully inside the viewport at %s (%s)" % [element.name, tag, rect])
			expect(rect.get_area() < screen.get_area() * 0.06, "%s stays small, no big block, at %s (%s)" % [element.name, tag, rect])
		for i in elements.size():
			for j in range(i + 1, elements.size()):
				expect(not (elements[i].get_global_rect().intersects(elements[j].get_global_rect())), "%s and %s do not overlap at %s" % [elements[i].name, elements[j].name, tag])
		# the black plate is on top, the white plate at the bottom, both centred
		var white := game.hud["card_w"] as Control
		var black := game.hud["card_b"] as Control
		expect(black.get_global_rect().position.y < white.get_global_rect().position.y, "black plate above white plate at " + tag)
		expect(absf(white.get_global_rect().get_center().x - screen.size.x * 0.5) < 3.0, "white plate centred at " + tag)
		game.queue_free()
		await _settle(3)
	print("Minimal layout: %d checks, %d failures" % [checks, failures.size()])
	quit(1 if failures.size() > 0 else 0)
