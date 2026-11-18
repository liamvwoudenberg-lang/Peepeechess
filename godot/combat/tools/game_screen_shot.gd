extends SceneTree
## Dev tool: the chess game screen at one window size, plus a dump of the HUD rects.
##   xvfb-run -a godot --path godot --rendering-driver opengl3 --resolution 1920x1080 --script res://combat/tools/game_screen_shot.gd -- OUT.png 1920 1080
const MainScene := preload("res://app/main.tscn")
func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	get_root().size = Vector2i(int(args[1]), int(args[2]))
	var AppSettings = load("res://ui/application_settings.gd")
	AppSettings.launch = {"mode": "classic", "initialMs": 600000, "incrementMs": 0, "view3d": true}
	var app = MainScene.instantiate()
	get_root().add_child(app)
	for _i in 50:
		await process_frame
	var overlay = app.find_child("MinimalOverlay", true, false)
	if overlay != null:
		for c in overlay.get_children():
			if c is Control:
				print("HUD ", c.name, " ", c.get_global_rect(), " vis=", c.visible)
	get_root().get_viewport().get_texture().get_image().save_png(args[0])
	quit()
