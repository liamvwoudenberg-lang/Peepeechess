extends SceneTree
## Renders the gothic plaque buttons (normal, hover/focus glow, selected, primary, chips, tabs, danger, disabled) to a PNG, to judge the look.
##   xvfb-run -a godot --path godot --rendering-driver opengl3 --resolution 1100x640 --script res://ui/tools/plaque_preview.gd -- out=/tmp/plaques.png
const PeepeeTheme = preload("res://ui/theme/peepee_theme.gd")
const Fx = preload("res://ui/theme/plaque_fx.gd")

func _initialize() -> void:
	var out := "/tmp/plaques.png"
	for token in OS.get_cmdline_user_args():
		if String(token).begins_with("out="):
			out = String(token).substr(4)
	var backdrop := ColorRect.new()
	backdrop.color = Color("0a0d16")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.theme = PeepeeTheme.build(1.0)
	root.add_child(backdrop)
	var column := VBoxContainer.new()
	column.position = Vector2(30, 24)
	column.add_theme_constant_override("separation", 16)
	backdrop.add_child(column)
	var focus_target: Button
	var rows := [
		[["Classic Chess", ""], ["Battle Chess", ""], ["Training", ""], ["Settings", ""], ["Quit", "DangerButton"]],
		[["Create or join a room code  →", "PrimaryButton"], ["Start local Classic Chess  →", "PrimaryButton"], ["Disabled button", "DISABLED"]],
		[["Local · two players", "SegButton"], ["Computer", "SegButton"], ["Online crossplay", "PrimaryButton"], ["2D board", "SegButton"], ["3D board", "PrimaryButton"]],
		[["Play", "NavButtonActive"], ["Friends", "NavButton"], ["Profile", "NavButton"], ["Leaderboard", "NavButton"]],
	]
	for row_data in rows:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		column.add_child(row)
		for item in row_data:
			var b := Button.new()
			b.text = item[0]
			b.custom_minimum_size = Vector2(0, 46)
			if item[1] == "DISABLED":
				b.disabled = true
			elif item[1] != "":
				b.theme_type_variation = item[1]
			row.add_child(b)
			if item[0] == "Battle Chess":
				focus_target = b
	await process_frame
	focus_target.grab_focus()   # shows the "hover / focus" glow + wisps
	for b in backdrop.find_children("*", "Button", true, false):
		Fx.sync(b)   # the preview has no UiInteract node, so sync the effects by hand
	for i in 110:
		await process_frame
	root.get_texture().get_image().save_png(out)
	print("saved ", out)
	quit(0)
