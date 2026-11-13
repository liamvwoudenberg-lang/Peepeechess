extends SceneTree
## Dev tool: screenshots of the real app's 3D board with the paladin pieces (angled and top-down, mid-walk).
##   xvfb-run -a godot --path godot --rendering-driver opengl3 --resolution 1280x800 --script res://combat/tools/paladin_board_shot.gd -- OUT_PREFIX
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
	for _i in 40:
		await process_frame
	await _shot(prefix + "_angled.png")
	app.game.play("e2", "e4")
	for _i in 22:
		await process_frame
	await _shot(prefix + "_angled_walking.png")
	for _i in 120:
		await process_frame
	app.game.play("g8", "f6")
	for _i in 30:
		await process_frame
	await _shot(prefix + "_knight_walking.png")
	for _i in 120:
		await process_frame
	app.set_view(false)
	for _i in 90:
		await process_frame
	await _shot(prefix + "_topdown.png")
	quit()
