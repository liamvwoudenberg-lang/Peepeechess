extends SceneTree
## Dev tool: default 3D board view from White's and Black's side.
##   xvfb-run -a godot --path godot --rendering-driver opengl3 --resolution 1280x800 --script res://combat/tools/board_view_shot.gd -- OUT_PREFIX
const MainScene := preload("res://app/main.tscn")

func _shot(path: String) -> void:
	await process_frame
	await process_frame
	get_root().get_viewport().get_texture().get_image().save_png(path)

func _initialize() -> void:
	await process_frame
	var prefix: String = OS.get_cmdline_user_args()[0]
	get_root().size = Vector2i(1280, 800)
	var app = MainScene.instantiate()
	get_root().add_child(app)
	for _i in 10:
		await process_frame
	app.set_view(true)
	for _i in 60:
		await process_frame
	await _shot(prefix + "_white.png")
	app.game.play("e2", "e4")
	for _i in 150:
		await process_frame
	app.game.play("d7", "d5")
	for _i in 150:
		await process_frame
	app.set_flipped(true)
	for _i in 60:
		await process_frame
	await _shot(prefix + "_black.png")
	quit()
