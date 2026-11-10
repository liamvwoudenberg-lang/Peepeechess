extends Node3D
## Line-up of all six generated classes with clip selection (animation review tool).
##   godot --path godot res://combat/scenes/character_gallery.tscn
## Keys: Left/Right = previous/next clip, L = toggle mobile LOD1. Flags after `--`:
##   --clip=NAME  --time=SECONDS (freeze there)  --lod=1  --shot=PATH --frames=N
const CLASSES := ["pawn", "knight", "bishop", "rook", "queen", "king"]
const ROLES := ["p", "n", "b", "r", "q", "k"]

var models: Array[CharacterModel] = []
var clip_index: int = 0
var label: Label
var _args: Dictionary = {}
var _frame: int = 0
var _lod: int = 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and "=" in arg:
			var parts := arg.substr(2).split("=", true, 1)
			_args[parts[0]] = parts[1]
	_lod = int(_args.get("lod", 0))
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.07, 0.075, 0.1)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.45, 0.47, 0.58)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -28, 0)
	sun.light_energy = 1.3
	add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-18, 155, 0)
	rim.light_energy = 0.7
	add_child(rim)
	var floor_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(16, 0.1, 5)
	floor_mesh.mesh = box
	floor_mesh.position.y = -0.05
	add_child(floor_mesh)
	for i in CLASSES.size():
		var m := CharacterModel.new()
		add_child(m)
		if not m.setup_free(ROLES[i], _lod, "w" if i % 2 == 0 else "b"):
			push_error("missing model: " + CLASSES[i])
			m.queue_free()
			continue
		m.position = Vector3((float(i) - 2.5) * 2.4, 0.0, 0.0)
		m.rotation_degrees.y = 12.0
		models.append(m)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.6, 12.5)
	cam.fov = 42
	add_child(cam)
	cam.look_at(Vector3(0, 1.0, 0))
	var layer := CanvasLayer.new()
	label = Label.new()
	label.position = Vector2(16, 12)
	label.add_theme_font_size_override("font_size", 22)
	layer.add_child(label)
	add_child(layer)
	var clip: String = String(_args.get("clip", CharacterModel.REQUIRED_CLIPS[0]))
	clip_index = maxi(0, CharacterModel.REQUIRED_CLIPS.find(clip))
	_play()


func _play() -> void:
	var clip: String = CharacterModel.REQUIRED_CLIPS[clip_index]
	label.text = "clip: %s   (Left/Right to change, LOD%d)" % [clip, _lod]
	for m in models:
		m.play_clip(clip, 1.0, 0.0)
		if _args.has("time") and m.player != null:
			m.player.seek(float(_args["time"]), true)
			m.player.pause()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var n := CharacterModel.REQUIRED_CLIPS.size()
		if event.keycode == KEY_RIGHT:
			clip_index = (clip_index + 1) % n
			_play()
		elif event.keycode == KEY_LEFT:
			clip_index = (clip_index + n - 1) % n
			_play()


func _process(_delta: float) -> void:
	_frame += 1
	if _args.has("frames") and _frame >= int(_args["frames"]):
		if _args.has("shot"):
			get_viewport().get_texture().get_image().save_png(String(_args["shot"]))
		get_tree().quit()
