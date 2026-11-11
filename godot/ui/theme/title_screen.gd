extends RefCounted
## The title screen ("home" page): emblem, wordmark, tagline and the primary menu. Built into the application's page
## container. Left column = brand, right column = menu; stacks vertically when the window is narrow.
const T = preload("res://ui/theme/ui_tokens.gd")
const Kit = preload("res://ui/theme/ui_kit.gd")
const Icons = preload("res://ui/theme/ui_icons.gd")

## Draws the emblem (a control so the title can size it).
class Emblem:
	extends Control
	const T = preload("res://ui/theme/ui_tokens.gd")
	const Icons = preload("res://ui/theme/ui_icons.gd")
	var _texture: ImageTexture
	var _px := 0
	func _init(px: int = 160) -> void:
		custom_minimum_size = Vector2(px, px)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var extent := minf(size.x, size.y)
		var px := maxi(32, int(ceilf(extent * maxf(1.0, get_global_transform_with_canvas().get_scale().x))))
		if _texture == null or absi(px - _px) > 2:
			_texture = Icons.texture("emblem", px)
			_px = px
		var origin := (size - Vector2(extent, extent)) * 0.5
		draw_circle(size * 0.5, extent * 0.56, Color(T.GOLD.r, T.GOLD.g, T.GOLD.b, 0.08))
		draw_texture_rect(_texture, Rect2(origin, Vector2(extent, extent)), false, T.GOLD)

static func version_text() -> String:
	return "v" + str(ProjectSettings.get_setting("application/config/version", "dev"))

## `app` provides: navigate(String), selected_mode, online, account_badge handling (via add_account_chip).
## Returns {menu: VBoxContainer, buttons: Dictionary(name -> Button)}.
static func build(app: Control, parent: Container, quit_visible: bool) -> Dictionary:
	var root := VBoxContainer.new()
	root.name = "Home"
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", T.S4)
	parent.add_child(root)
	var top := HBoxContainer.new()
	root.add_child(top)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var chip := Kit.button(top, "Sign in", func(): app.navigate("account"), "GhostButton", "user")
	chip.name = "AccountChip"
	if app.has_method("_update_badge"):
		app.account_badge = chip
		app._update_badge()
	var top_pad := Control.new()
	top_pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top_pad.custom_minimum_size.y = 0
	root.add_child(top_pad)
	var row := Kit.responsive(root, 880.0, 96)
	row.name = "TitleRow"
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	# brand column
	var brand := VBoxContainer.new()
	brand.name = "Brand"
	brand.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	brand.alignment = BoxContainer.ALIGNMENT_CENTER
	brand.add_theme_constant_override("separation", T.S3)
	row.add_child(brand)
	var emblem := Emblem.new(168)
	emblem.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	brand.add_child(emblem)
	var wordmark := Kit.label(brand, "PEEPEECHESS", "Wordmark", false)
	wordmark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wordmark.name = "Wordmark"
	var tagline := Kit.label(brand, "Your board. Your perspective. One shared game.")
	tagline.theme_type_variation = "Muted"
	tagline.add_theme_font_size_override("font_size", T.FS_LEAD)
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# menu column
	var menu := VBoxContainer.new()
	menu.name = "Menu"
	menu.custom_minimum_size.x = 340
	menu.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	menu.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	menu.add_theme_constant_override("separation", T.S3)
	row.add_child(menu)
	var buttons := {}
	var entries := [
		["classic", "Classic Chess", "rook", "PrimaryButton", func(): app.selected_mode = "classic"; app.online = false; app.navigate("play")],
		["battle", "Battle Chess", "sword", "PrimaryButton", func(): app.selected_mode = "battle"; app.online = false; app.navigate("play")],
		["online", "Online", "cloud", "", func(): app.online = true; app.navigate("play")],
		["profile", "Profile", "user", "", func(): app.navigate("profile")],
		["settings", "Settings", "gear", "", func(): app.navigate("settings")],
	]
	if quit_visible:
		entries.append(["quit", "Quit", "close", "GhostButton", func(): app.get_tree().quit()])
	for entry in entries:
		var button := Kit.button(menu, entry[1], entry[4], entry[3], entry[2])
		button.name = entry[0].capitalize() + "Button"
		button.custom_minimum_size.y = maxi(Kit.target_height(), 54)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", T.FS_LEAD)
		buttons[entry[0]] = button
	var bottom_pad := Control.new()
	bottom_pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(bottom_pad)
	var version := Kit.label(root, version_text() + "  ·  Windows and Android crossplay", "Caption", false)
	version.name = "Version"
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version.add_theme_color_override("font_color", T.TEXT_MUTED)
	return {"root": root, "menu": menu, "buttons": buttons, "wordmark": wordmark}
