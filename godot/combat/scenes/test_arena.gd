extends Node
## Standalone combat test arena (no chess, no network).
##   godot --path godot res://combat/scenes/test_arena.tscn
##
## Menu: 1 Player vs AI, 2 Players (split screen, one keyboard or two pads), or an AI-vs-AI
## demo; each side can be any of Pawn, Knight, Bishop, Rook or Queen. After a fight: Rematch (Enter / F5) or Menu (Esc).
## Everything runs through CombatArena in AUTHORITY mode, i.e. the same CombatSimulation and
## CombatInput path a server would use - only the host differs.
##
## Automation flags (after `--`): --auto=pve|pvp|demo  --p1=p|n|b|r|q  --p2=p|n|b|r|q  --seed=N
##   --frames=N (quit after N frames)  --shot=PATH (save a PNG at the end)  --touch (virtual touch controls for P1)  --pad (P1 on the first gamepad)

const ARENA_SCENE := "res://combat/arena.tscn"

var arena: CombatArena
var menu: Node
var config: Dictionary = {"mode": "pve", "white": "p", "black": "n", "controls": "kbm"}
var _round: int = 0
var _args: Dictionary = {}
var _frame: int = 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and "=" in arg:
			var parts := arg.substr(2).split("=", true, 1)
			_args[parts[0]] = parts[1]
		elif arg.begins_with("--"):
			_args[arg.substr(2)] = "1"
	if _args.has("p1"):
		config["white"] = _args["p1"]
	if _args.has("p2"):
		config["black"] = _args["p2"]
	# Touch controls for P1: automatic on a touchscreen device, or forced with --touch / --touch=1.
	if _args.has("touch") or DisplayServer.is_touchscreen_available():
		config["controls"] = "touch"
	elif _args.has("pad") or not Input.get_connected_joypads().is_empty():
		config["controls"] = "pad"  # a gamepad is plugged in: default P1 to it (the menu can switch back)
	arena = (load(ARENA_SCENE) as PackedScene).instantiate()
	add_child(arena)
	arena.rematch_requested.connect(rematch)
	arena.menu_requested.connect(show_menu)
	if _args.has("auto"):
		config["mode"] = _args["auto"]
		start_fight()
	else:
		show_menu()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			show_menu()
		elif (event.keycode == KEY_F5 or event.keycode == KEY_ENTER) and arena.sim.phase == CombatSimulation.Phase.FINISHED:
			rematch()


func _process(_delta: float) -> void:
	_frame += 1
	if _args.has("frames") and _frame >= int(_args["frames"]):
		if _args.has("shot"):
			get_viewport().get_texture().get_image().save_png(String(_args["shot"]))
		get_tree().quit()


func show_menu() -> void:
	arena.stop_battle()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if menu != null:
		menu.queue_free()
	menu = _build_menu()
	add_child(menu)


func _build_menu() -> Node:
	var layer := CanvasLayer.new()
	layer.layer = 50
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.9)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var panel := VBoxContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-230, -210)
	panel.custom_minimum_size = Vector2(460, 0)
	panel.add_theme_constant_override("separation", 12)
	root.add_child(panel)
	var title := Label.new()
	title.text = "PEEPEECHESS — Combat Test Arena"
	title.add_theme_font_size_override("font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)
	var note := Label.new()
	note.text = "Standalone prototype · offline · local authority\n(no chess, no multiplayer)"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.modulate = Color(1, 1, 1, 0.7)
	panel.add_child(note)

	panel.add_child(_chooser("Mode", ["pve", "pvp", "demo"], ["1 Player vs AI", "2 Players (split screen)", "AI vs AI demo"], "mode"))
	panel.add_child(_chooser("P1 controls", ["kbm", "pad", "touch"], ["Keyboard + mouse", "Gamepad (first connected)", "Touch (landscape)"], "controls"))
	var role_labels: Array = []
	for role in FighterRoster.ROLES:
		role_labels.append("%s — %s" % [FighterRoster.display_name(role), FighterRoster.ability_name(role)])
	panel.add_child(_chooser("White fighter", FighterRoster.ROLES, role_labels, "white"))
	panel.add_child(_chooser("Black fighter", FighterRoster.ROLES, role_labels, "black"))
	var start := Button.new()
	start.text = "FIGHT"
	start.custom_minimum_size = Vector2(0, 48)
	start.pressed.connect(start_fight)
	panel.add_child(start)
	start.call_deferred("grab_focus")
	var help := Label.new()
	help.text = "P1: WASD · Shift sprint · LMB/F light · RMB/G heavy · Q block · E parry · Space dodge · R ability · Tab lock\nP2: Arrows · Ctrl sprint · J light · K heavy · U block · I parry · L dodge · O ability · P lock\nGamepad: stick · X/Y attacks · LB block · RB parry · A dodge · B ability"
	help.add_theme_font_size_override("font_size", 13)
	help.modulate = Color(1, 1, 1, 0.75)
	panel.add_child(help)
	return layer


func _chooser(title: String, values: Array, labels: Array, key: String) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = title
	label.custom_minimum_size = Vector2(130, 0)
	row.add_child(label)
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in labels.size():
		option.add_item(labels[i], i)
	option.select(maxi(0, values.find(config[key])))
	option.item_selected.connect(func(index: int): config[key] = values[index])
	row.add_child(option)
	return row


func start_fight() -> void:
	if menu != null:
		menu.queue_free()
		menu = null
	var seats := {}
	match String(config["mode"]):
		"pve":
			seats = {"player-white": {"type": "human", "scheme": _p1_scheme()}, "player-black": {"type": "ai", "skill": 0.6}}
		"pvp":
			seats = {"player-white": {"type": "human", "scheme": _p1_scheme()}, "player-black": {"type": "human", "scheme": "kb2"}}
			var pads := Input.get_connected_joypads()
			if pads.size() >= 2:  # two controllers: one each
				seats["player-white"]["scheme"] = "pad%d" % pads[0]
				seats["player-black"]["scheme"] = "pad%d" % pads[1]
		_:
			seats = {"player-white": {"type": "ai", "skill": 0.75}, "player-black": {"type": "ai", "skill": 0.6}}
	arena.configure_seats(seats)
	_round += 1
	var request := FighterRoster.build_request(String(config["white"]), String(config["black"]), "w",
			"local-battle-%d" % _round, int(_args.get("seed", 1000 + _round)), 0)
	var reply: Dictionary = arena.start_battle(request)
	if not reply["ok"]:
		push_error("could not start the fight: %s" % str(reply))
		return
	# The on-screen PAUSE button returns to the menu (touch has no Esc key).
	for source in arena.find_children("*", "LocalInputSource", false, false):
		source.pause_requested.connect(show_menu)


func _p1_scheme() -> String:
	if config["controls"] == "touch":
		return "touch"
	var pads := Input.get_connected_joypads()
	if config["controls"] == "pad" and not pads.is_empty():
		return "pad%d" % pads[0]
	return "kb1"  # keyboard + mouse (also the fallback when "Gamepad" is chosen but none is connected)


func rematch() -> void:
	start_fight()
