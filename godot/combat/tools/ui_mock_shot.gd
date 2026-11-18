extends SceneTree
## Dev tool: screenshots of the home page and the Settings page (graphics presets, FPS overlay).
##   xvfb-run -a godot --path godot --rendering-driver opengl3 --resolution 1280x800 --script res://combat/tools/ui_mock_shot.gd -- OUT_PREFIX
const AppScene := preload("res://ui/application.tscn")
func _shot(path: String) -> void:
	for _i in 4:
		await process_frame
	get_root().get_viewport().get_texture().get_image().save_png(path)
func _initialize() -> void:
	await process_frame
	var prefix: String = OS.get_cmdline_user_args()[0]
	get_root().size = Vector2i(1280, 800)
	GraphicsSettings.set_value("show_fps", true)
	var app = AppScene.instantiate()
	get_root().add_child(app)
	for _i in 60:
		await process_frame
	await _shot(prefix + "_home.png")
	app.navigate("settings")
	for _i in 30:
		await process_frame
	await _shot(prefix + "_settings.png")
	GraphicsSettings.set_value("show_fps", false)
	quit()
