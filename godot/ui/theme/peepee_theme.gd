extends RefCounted
## Builds the shared Theme resource from the design tokens (ui_tokens.gd).
##   theme = PeepeeTheme.build()              # assign to the root Control of a screen; every child inherits it
## Type variations (set Control.theme_type_variation): PrimaryButton, DangerButton, GhostButton, NavButton,
## NavButtonActive, SegButton (toggle), CardToggle (toggle), IconButton; panels CardPanel, RaisedPanel, SelectedPanel,
## HudPanel, BannerPanel, ToastPanel, DangerPanel, InsetPanel; labels H1, H2, H3, Muted, Caption, Accent, DangerLabel,
## SuccessLabel, ClockLabel, Wordmark.
## Resources are NOT cached in statics here: a cached Resource would still be alive at engine shutdown.
const T = preload("res://ui/theme/ui_tokens.gd")
const BUTTON_TYPES := ["Button", "OptionButton", "MenuButton"]

static func flat(bg: Color, border: Color = Color(0, 0, 0, 0), border_width: int = 0, radius: int = T.R_MD, margin_h: int = -1, margin_v: int = -1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(radius)
	style.set_border_width_all(border_width)
	style.border_color = border
	style.anti_aliasing = true
	style.anti_aliasing_size = 0.8
	if margin_h >= 0:
		style.content_margin_left = margin_h
		style.content_margin_right = margin_h
	if margin_v >= 0:
		style.content_margin_top = margin_v
		style.content_margin_bottom = margin_v
	return style

static func with_shadow(style: StyleBoxFlat, size: int = 10, offset_y: int = 4, alpha: float = 0.45) -> StyleBoxFlat:
	style.shadow_size = size
	style.shadow_offset = Vector2(0, offset_y)
	style.shadow_color = Color(0, 0, 0, alpha)
	return style

static func focus_ring(radius: int = T.R_MD) -> StyleBoxFlat:
	var ring := flat(Color(0, 0, 0, 0), T.GOLD_HI, T.FOCUS_RING, radius + 2)
	ring.set_expand_margin_all(2)
	return ring

static func _svg(markup: String, width: int, height: int) -> ImageTexture:
	var svg := "<svg xmlns='http://www.w3.org/2000/svg' width='%d' height='%d' viewBox='0 0 %d %d'>%s</svg>" % [width, height, width, height, markup]
	var image := Image.new()
	if image.load_svg_from_string(svg, 1.0) != OK or image.is_empty():
		image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	return ImageTexture.create_from_image(image)

static func _hex(color: Color) -> String:
	return "#" + color.to_html(false)

static func _checkbox_icon(checked: bool, enabled: bool) -> ImageTexture:
	var fill := T.GOLD if checked else T.SURFACE
	var edge := T.GOLD_HI if checked else T.BORDER_STRONG
	var alpha := 1.0 if enabled else 0.4
	var markup := "<g opacity='%s'><rect x='1.5' y='1.5' width='21' height='21' rx='6' fill='%s' stroke='%s' stroke-width='2'/>" % [alpha, _hex(fill), _hex(edge)]
	if checked:
		markup += "<path d='M6.5 12.5 L10.5 16.5 L17.5 8' fill='none' stroke='%s' stroke-width='2.8' stroke-linecap='round' stroke-linejoin='round'/>" % _hex(T.TEXT_ON_GOLD)
	return _svg(markup + "</g>", 24, 24)

static func _switch_icon(on: bool, enabled: bool) -> ImageTexture:
	var track := T.GOLD if on else T.SURFACE_3
	var edge := T.GOLD_HI if on else T.BORDER_STRONG
	var knob := T.TEXT_ON_GOLD if on else T.TEXT_MUTED
	var cx := 36 if on else 14
	var alpha := 1.0 if enabled else 0.4
	return _svg("<g opacity='%s'><rect x='1.5' y='2.5' width='45' height='23' rx='11.5' fill='%s' stroke='%s' stroke-width='2'/><circle cx='%d' cy='14' r='8' fill='%s'/></g>" % [alpha, _hex(track), _hex(edge), cx, _hex(knob)], 48, 28)

static func _radio_icon(checked: bool, enabled: bool) -> ImageTexture:
	var alpha := 1.0 if enabled else 0.4
	var markup := "<g opacity='%s'><circle cx='12' cy='12' r='10' fill='%s' stroke='%s' stroke-width='2'/>" % [alpha, _hex(T.SURFACE), _hex(T.GOLD_HI if checked else T.BORDER_STRONG)]
	if checked:
		markup += "<circle cx='12' cy='12' r='5.5' fill='%s'/>" % _hex(T.GOLD)
	return _svg(markup + "</g>", 24, 24)

static func _grabber(radius: int, fill: Color, edge: Color) -> ImageTexture:
	var size := radius * 2 + 4
	return _svg("<circle cx='%d' cy='%d' r='%d' fill='%s' stroke='%s' stroke-width='3'/>" % [size / 2, size / 2, radius, _hex(fill), _hex(edge)], size, size)

static func _chevron() -> ImageTexture:
	return _svg("<path d='M2 3 L8 9 L14 3' fill='none' stroke='%s' stroke-width='2.4' stroke-linecap='round' stroke-linejoin='round'/>" % _hex(T.TEXT_MUTED), 16, 12)

static func _close_icon(color: Color) -> ImageTexture:
	return _svg("<path d='M3 3 L15 15 M15 3 L3 15' fill='none' stroke='%s' stroke-width='2.4' stroke-linecap='round'/>" % _hex(color), 18, 18)

static func build(font_scale: float = 1.0) -> Theme:
	var theme := Theme.new()
	theme.default_font_size = roundi(T.FS_BODY * font_scale)
	var bold := FontVariation.new()
	bold.base_font = ThemeDB.fallback_font
	bold.variation_embolden = 0.55
	var display := FontVariation.new()
	display.base_font = ThemeDB.fallback_font
	display.variation_embolden = 0.9
	display.spacing_glyph = 3
	theme.set_font("bold", "Label", bold)
	_build_text(theme, bold, display)
	_build_buttons(theme, bold)
	_build_toggles(theme)
	_build_panels(theme)
	_build_inputs(theme)
	_build_containers(theme, bold)
	_build_windows(theme, bold)
	return theme

static func _build_text(theme: Theme, bold: Font, display: Font) -> void:
	for type_name in ["Label", "RichTextLabel", "TextEdit", "LineEdit", "SpinBox", "CheckBox", "CheckButton", "Button", "OptionButton", "MenuButton", "PopupMenu"]:
		theme.set_color("font_color", type_name, T.TEXT)
	theme.set_color("default_color", "RichTextLabel", T.TEXT)
	theme.set_constant("line_separation", "Label", 3)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))
	# label variations
	var variations := {
		"H1": [T.FS_H1, T.TEXT, bold], "H2": [T.FS_H2, T.GOLD_HI, bold], "H3": [T.FS_H3, T.TEXT, bold],
		"Muted": [T.FS_BODY, T.TEXT_MUTED, null], "Caption": [T.FS_CAPTION, T.TEXT_MUTED, bold], "Accent": [T.FS_BODY, T.GOLD, bold],
		"DangerLabel": [T.FS_BODY, T.DANGER, null], "SuccessLabel": [T.FS_BODY, T.SUCCESS, null],
		"ClockLabel": [T.FS_H1, T.TEXT, bold], "Wordmark": [T.FS_DISPLAY, T.GOLD_HI, display],
	}
	for key in variations:
		var data: Array = variations[key]
		theme.set_type_variation(key, "Label")
		theme.set_font_size("font_size", key, data[0])
		theme.set_color("font_color", key, data[1])
		if data[2] != null:
			theme.set_font("font", key, data[2])
	theme.set_font("font", "Label", ThemeDB.fallback_font)
	theme.set_color("font_selected_color", "RichTextLabel", T.TEXT)
	theme.set_color("selection_color", "RichTextLabel", Color(T.GOLD.r, T.GOLD.g, T.GOLD.b, 0.35))
	theme.set_font("bold_font", "RichTextLabel", bold)
	theme.set_font_size("normal_font_size", "RichTextLabel", T.FS_BODY)
	theme.set_font_size("bold_font_size", "RichTextLabel", T.FS_BODY)
	theme.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())

static func _button_style(bg: Color, border: Color, border_width: int = 1, radius: int = T.R_MD, h: int = 18, v: int = 11) -> StyleBoxFlat:
	return flat(bg, border, border_width, radius, h, v)

static func _set_button_states(theme: Theme, type_name: String, normal: StyleBox, hover: StyleBox, pressed: StyleBox, disabled: StyleBox, focus_radius: int = T.R_MD) -> void:
	theme.set_stylebox("normal", type_name, normal)
	theme.set_stylebox("hover", type_name, hover)
	theme.set_stylebox("pressed", type_name, pressed)
	theme.set_stylebox("hover_pressed", type_name, pressed)
	theme.set_stylebox("disabled", type_name, disabled)
	theme.set_stylebox("focus", type_name, focus_ring(focus_radius))

static func _button_colors(theme: Theme, type_name: String, normal: Color, hover: Color, pressed: Color, disabled: Color) -> void:
	theme.set_color("font_color", type_name, normal)
	theme.set_color("font_hover_color", type_name, hover)
	theme.set_color("font_focus_color", type_name, hover)
	theme.set_color("font_pressed_color", type_name, pressed)
	theme.set_color("font_hover_pressed_color", type_name, pressed)
	theme.set_color("font_disabled_color", type_name, disabled)
	theme.set_color("icon_normal_color", type_name, normal)
	theme.set_color("icon_hover_color", type_name, hover)
	theme.set_color("icon_pressed_color", type_name, pressed)
	theme.set_color("icon_disabled_color", type_name, disabled)

static func _build_buttons(theme: Theme, bold: Font) -> void:
	for type_name in BUTTON_TYPES:
		_set_button_states(theme, type_name,
			with_shadow(_button_style(T.SURFACE_2, T.BORDER), 3, 2, 0.35),
			_button_style(T.SURFACE_3, T.GOLD_LO),
			_button_style(T.SURFACE, T.GOLD),
			_button_style(Color(T.SURFACE.r, T.SURFACE.g, T.SURFACE.b, 0.6), T.BORDER))
		_button_colors(theme, type_name, T.TEXT, T.GOLD_HI, T.GOLD_HI, T.TEXT_DIM)
		theme.set_font("font", type_name, bold)
		theme.set_constant("h_separation", type_name, 10)
		theme.set_constant("outline_size", type_name, 0)
	theme.set_icon("arrow", "OptionButton", _chevron())
	theme.set_constant("arrow_margin", "OptionButton", 12)
	theme.set_constant("modulate_arrow", "OptionButton", 0)
	theme.set_stylebox("normal_mirrored", "OptionButton", theme.get_stylebox("normal", "OptionButton"))
	# primary (gold) / danger / ghost / nav / segmented
	theme.set_type_variation("PrimaryButton", "Button")
	_set_button_states(theme, "PrimaryButton",
		with_shadow(_button_style(T.GOLD, T.GOLD_HI), 6, 3, 0.45),
		_button_style(T.GOLD_HI, Color("fff0c7")),
		_button_style(Color("c79a45"), T.GOLD_HI),
		_button_style(Color(T.GOLD_LO.r, T.GOLD_LO.g, T.GOLD_LO.b, 0.55), T.GOLD_LO))
	_button_colors(theme, "PrimaryButton", T.TEXT_ON_GOLD, T.TEXT_ON_GOLD, T.TEXT_ON_GOLD, Color("c8b898"))
	theme.set_type_variation("DangerButton", "Button")
	_set_button_states(theme, "DangerButton", _button_style(T.DANGER_BG, Color("c45b52")), _button_style(T.DANGER_BG_HI, Color("e08074")), _button_style(Color("6d2420"), Color("e08074")), _button_style(Color(0.35, 0.15, 0.14, 0.5), T.BORDER))
	_button_colors(theme, "DangerButton", T.TEXT, Color.WHITE, Color.WHITE, T.TEXT_DIM)
	theme.set_type_variation("GhostButton", "Button")
	_set_button_states(theme, "GhostButton", _button_style(Color(0, 0, 0, 0), Color(0, 0, 0, 0)), _button_style(Color(1, 1, 1, 0.07), Color(0, 0, 0, 0)), _button_style(Color(1, 1, 1, 0.12), Color(0, 0, 0, 0)), _button_style(Color(0, 0, 0, 0), Color(0, 0, 0, 0)))
	_button_colors(theme, "GhostButton", T.TEXT_MUTED, T.GOLD_HI, T.GOLD_HI, T.TEXT_DIM)
	theme.set_type_variation("IconButton", "Button")
	_set_button_states(theme, "IconButton", _button_style(Color(0, 0, 0, 0), Color(0, 0, 0, 0)), _button_style(Color(1, 1, 1, 0.07), Color(0, 0, 0, 0)), _button_style(Color(1, 1, 1, 0.12), Color(0, 0, 0, 0)), _button_style(Color(0, 0, 0, 0), Color(0, 0, 0, 0)))
	_button_colors(theme, "IconButton", T.TEXT_MUTED, T.GOLD_HI, T.GOLD_HI, T.TEXT_DIM)
	theme.set_type_variation("NavButton", "Button")
	_set_button_states(theme, "NavButton", _button_style(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, T.R_MD, 16, 9), _button_style(Color(1, 1, 1, 0.07), Color(0, 0, 0, 0), 0, T.R_MD, 16, 9), _button_style(Color(1, 1, 1, 0.1), Color(0, 0, 0, 0), 0, T.R_MD, 16, 9), _button_style(T.SURFACE_GOLD, T.GOLD, 1, T.R_MD, 16, 9))
	_button_colors(theme, "NavButton", T.TEXT_MUTED, T.GOLD_HI, T.GOLD_HI, T.GOLD_HI)
	theme.set_type_variation("NavButtonActive", "Button")
	var active := _button_style(T.SURFACE_GOLD, T.GOLD, 1, T.R_MD, 16, 9)
	_set_button_states(theme, "NavButtonActive", active, active, active, active)
	_button_colors(theme, "NavButtonActive", T.GOLD_HI, T.GOLD_HI, T.GOLD_HI, T.GOLD_HI)
	theme.set_type_variation("SegButton", "Button")
	_set_button_states(theme, "SegButton", _button_style(T.SURFACE_2, T.BORDER, 1, T.R_MD, 16, 10), _button_style(T.SURFACE_3, T.GOLD_LO, 1, T.R_MD, 16, 10), _button_style(T.GOLD, T.GOLD_HI, 1, T.R_MD, 16, 10), _button_style(Color(T.SURFACE.r, T.SURFACE.g, T.SURFACE.b, 0.6), T.BORDER, 1, T.R_MD, 16, 10))
	_button_colors(theme, "SegButton", T.TEXT, T.GOLD_HI, T.TEXT_ON_GOLD, T.TEXT_DIM)
	theme.set_stylebox("hover_pressed", "SegButton", _button_style(T.GOLD_HI, Color("fff0c7"), 1, T.R_MD, 16, 10))
	theme.set_color("font_hover_pressed_color", "SegButton", T.TEXT_ON_GOLD)
	theme.set_type_variation("CardToggle", "Button")
	_set_button_states(theme, "CardToggle", _button_style(T.SURFACE, T.BORDER, 1, T.R_LG, 20, 16), _button_style(T.SURFACE_2, T.GOLD_LO, 1, T.R_LG, 20, 16), _button_style(T.SURFACE_GOLD, T.GOLD, 2, T.R_LG, 20, 16), _button_style(T.SURFACE, T.BORDER, 1, T.R_LG, 20, 16), T.R_LG)
	_button_colors(theme, "CardToggle", T.TEXT, T.GOLD_HI, T.GOLD_HI, T.TEXT_DIM)
	# link-ish MenuButton / flat
	theme.set_stylebox("normal", "LinkButton", StyleBoxEmpty.new())
	theme.set_color("font_color", "LinkButton", T.GOLD)
	theme.set_color("font_hover_color", "LinkButton", T.GOLD_HI)

static func _build_toggles(theme: Theme) -> void:
	for type_name in ["CheckBox", "CheckButton"]:
		var empty := StyleBoxEmpty.new()
		empty.content_margin_top = 8
		empty.content_margin_bottom = 8
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			theme.set_stylebox(state, type_name, empty)
		theme.set_stylebox("focus", type_name, focus_ring(T.R_SM))
		_button_colors(theme, type_name, T.TEXT, T.GOLD_HI, T.TEXT, T.TEXT_DIM)
		theme.set_color("font_hover_pressed_color", type_name, T.GOLD_HI)
		theme.set_constant("h_separation", type_name, 12)
		theme.set_constant("check_v_offset", type_name, 0)
	theme.set_icon("checked", "CheckBox", _checkbox_icon(true, true))
	theme.set_icon("unchecked", "CheckBox", _checkbox_icon(false, true))
	theme.set_icon("checked_disabled", "CheckBox", _checkbox_icon(true, false))
	theme.set_icon("unchecked_disabled", "CheckBox", _checkbox_icon(false, false))
	theme.set_icon("radio_checked", "CheckBox", _radio_icon(true, true))
	theme.set_icon("radio_unchecked", "CheckBox", _radio_icon(false, true))
	theme.set_icon("radio_checked_disabled", "CheckBox", _radio_icon(true, false))
	theme.set_icon("radio_unchecked_disabled", "CheckBox", _radio_icon(false, false))
	theme.set_icon("checked", "CheckButton", _switch_icon(true, true))
	theme.set_icon("unchecked", "CheckButton", _switch_icon(false, true))
	theme.set_icon("checked_disabled", "CheckButton", _switch_icon(true, false))
	theme.set_icon("unchecked_disabled", "CheckButton", _switch_icon(false, false))
	theme.set_icon("checked_mirrored", "CheckButton", _switch_icon(true, true))
	theme.set_icon("unchecked_mirrored", "CheckButton", _switch_icon(false, true))
	theme.set_icon("checked_disabled_mirrored", "CheckButton", _switch_icon(true, false))
	theme.set_icon("unchecked_disabled_mirrored", "CheckButton", _switch_icon(false, false))

static func _build_panels(theme: Theme) -> void:
	var card := with_shadow(flat(T.SURFACE, T.BORDER, 1, T.R_LG, 20, 18), 10, 4, 0.4)
	theme.set_stylebox("panel", "PanelContainer", card)
	theme.set_stylebox("panel", "Panel", flat(T.SURFACE, T.BORDER, 1, T.R_LG))
	var panel_variations := {
		"CardPanel": card,
		"RaisedPanel": with_shadow(flat(T.SURFACE_2, T.BORDER_STRONG, 1, T.R_LG, 20, 18), 12, 5, 0.5),
		"SelectedPanel": with_shadow(flat(T.SURFACE_GOLD, T.GOLD, 2, T.R_LG, 20, 18), 12, 4, 0.45),
		"HudPanel": flat(T.SURFACE, T.BORDER, 1, T.R_LG, 16, 14),
		"InsetPanel": flat(T.BG_DEEP, T.BORDER, 1, T.R_MD, 12, 10),
		"PlayerCard": flat(T.SURFACE_2, T.BORDER, 1, T.R_MD, 12, 8),
		"PlayerCardActive": flat(T.SURFACE_GOLD, T.GOLD, 2, T.R_MD, 11, 7),
		"CheckPanel": flat(Color("3a1b18"), T.DANGER, 2, T.R_MD, 14, 10),
		"ResultPanel": flat(T.SURFACE_GOLD, T.GOLD_HI, 2, T.R_MD, 14, 10),
		"BannerPanel": flat(T.SURFACE_GOLD, T.GOLD, 1, T.R_MD, 16, 10),
		"DangerPanel": flat(Color("2f1816"), T.DANGER_BG_HI, 1, T.R_MD, 16, 10),
		"ToastPanel": with_shadow(flat(T.SURFACE_3, T.GOLD_LO, 1, T.R_MD, 18, 12), 14, 6, 0.6),
		"TopBarPanel": flat(Color(T.BG_DEEP.r, T.BG_DEEP.g, T.BG_DEEP.b, 0.92), T.BORDER, 0, 0, 20, 8),
	}
	for key in panel_variations:
		theme.set_type_variation(key, "PanelContainer")
		theme.set_stylebox("panel", key, panel_variations[key])
	theme.get_stylebox("panel", "TopBarPanel").border_width_bottom = 1
	theme.set_stylebox("panel", "TooltipPanel", with_shadow(flat(T.SURFACE_3, T.GOLD_LO, 1, T.R_SM, 12, 8), 8, 3, 0.5))
	theme.set_color("font_color", "TooltipLabel", T.TEXT)
	theme.set_font_size("font_size", "TooltipLabel", T.FS_SMALL)
	var line := StyleBoxLine.new()
	line.color = T.BORDER
	line.thickness = 1
	theme.set_stylebox("separator", "HSeparator", line)
	var vline := StyleBoxLine.new()
	vline.color = T.BORDER
	vline.thickness = 1
	vline.vertical = true
	theme.set_stylebox("separator", "VSeparator", vline)
	theme.set_constant("separation", "HSeparator", 12)

static func _build_inputs(theme: Theme) -> void:
	for type_name in ["LineEdit", "TextEdit", "SpinBox"]:
		theme.set_color("font_placeholder_color", type_name, Color("98a0ad"))
		theme.set_color("caret_color", type_name, T.GOLD_HI)
		theme.set_color("selection_color", type_name, Color(T.GOLD.r, T.GOLD.g, T.GOLD.b, 0.35))
		theme.set_color("font_uneditable_color", type_name, T.TEXT_MUTED)
	theme.set_stylebox("normal", "LineEdit", flat(T.BG_DEEP, T.BORDER_STRONG, 1, T.R_MD, 14, 11))
	theme.set_stylebox("focus", "LineEdit", flat(T.BG_DEEP, T.GOLD_HI, 2, T.R_MD, 13, 10))
	theme.set_stylebox("read_only", "LineEdit", flat(T.SURFACE, T.BORDER, 1, T.R_MD, 14, 11))
	theme.set_stylebox("normal", "TextEdit", flat(T.BG_DEEP, T.BORDER_STRONG, 1, T.R_MD, 12, 10))
	theme.set_stylebox("focus", "TextEdit", flat(T.BG_DEEP, T.GOLD_HI, 2, T.R_MD, 11, 9))
	theme.set_stylebox("read_only", "TextEdit", flat(T.SURFACE, T.BORDER, 1, T.R_MD, 12, 10))
	# sliders
	for type_name in ["HSlider", "VSlider"]:
		var track := flat(T.SURFACE_3, T.BORDER, 1, 4, 0, 4)
		var fill := flat(T.GOLD, Color(0, 0, 0, 0), 0, 4, 0, 4)
		var fill_hi := flat(T.GOLD_HI, Color(0, 0, 0, 0), 0, 4, 0, 4)
		theme.set_stylebox("slider", type_name, track)
		theme.set_stylebox("grabber_area", type_name, fill)
		theme.set_stylebox("grabber_area_highlight", type_name, fill_hi)
		theme.set_icon("grabber", type_name, _grabber(10, T.GOLD, T.TEXT_ON_GOLD))
		theme.set_icon("grabber_highlight", type_name, _grabber(12, T.GOLD_HI, T.TEXT_ON_GOLD))
		theme.set_icon("grabber_disabled", type_name, _grabber(10, T.BORDER_STRONG, T.SURFACE))
		theme.set_constant("center_grabber", type_name, 0)
		theme.set_constant("grabber_offset", type_name, 0)
	# progress
	theme.set_stylebox("background", "ProgressBar", flat(T.BG_DEEP, T.BORDER, 1, 6, 0, 0))
	theme.set_stylebox("fill", "ProgressBar", flat(T.GOLD, Color(0, 0, 0, 0), 0, 6, 0, 0))
	theme.set_color("font_color", "ProgressBar", T.TEXT)
	theme.set_font_size("font_size", "ProgressBar", T.FS_SMALL)

static func _scrollbar(theme: Theme, type_name: String) -> void:
	var track := flat(Color(1, 1, 1, 0.03), Color(0, 0, 0, 0), 0, 6)
	var grab := flat(T.BORDER_STRONG, Color(0, 0, 0, 0), 0, 6)
	var grab_hi := flat(T.GOLD_LO, Color(0, 0, 0, 0), 0, 6)
	var grab_down := flat(T.GOLD, Color(0, 0, 0, 0), 0, 6)
	if type_name == "VScrollBar":
		track.content_margin_left = 6
		track.content_margin_right = 6
		for style in [grab, grab_hi, grab_down]:
			style.content_margin_left = 6
			style.content_margin_right = 6
	else:
		track.content_margin_top = 6
		track.content_margin_bottom = 6
		for style in [grab, grab_hi, grab_down]:
			style.content_margin_top = 6
			style.content_margin_bottom = 6
	theme.set_stylebox("scroll", type_name, track)
	theme.set_stylebox("scroll_focus", type_name, track)
	theme.set_stylebox("grabber", type_name, grab)
	theme.set_stylebox("grabber_highlight", type_name, grab_hi)
	theme.set_stylebox("grabber_pressed", type_name, grab_down)
	for icon_name in ["increment", "decrement", "increment_highlight", "decrement_highlight", "increment_pressed", "decrement_pressed"]:
		theme.set_icon(icon_name, type_name, ImageTexture.new())

static func _build_containers(theme: Theme, bold: Font) -> void:
	_scrollbar(theme, "VScrollBar")
	_scrollbar(theme, "HScrollBar")
	# tabs
	for type_name in ["TabContainer", "TabBar"]:
		theme.set_stylebox("tab_selected", type_name, flat(T.SURFACE, T.GOLD, 1, T.R_MD, 18, 10))
		theme.set_stylebox("tab_unselected", type_name, flat(T.BG, T.BORDER, 1, T.R_MD, 18, 10))
		theme.set_stylebox("tab_hovered", type_name, flat(T.SURFACE_2, T.GOLD_LO, 1, T.R_MD, 18, 10))
		theme.set_stylebox("tab_disabled", type_name, flat(T.BG, T.BORDER, 1, T.R_MD, 18, 10))
		theme.set_stylebox("tab_focus", type_name, focus_ring())
		theme.set_color("font_selected_color", type_name, T.GOLD_HI)
		theme.set_color("font_unselected_color", type_name, T.TEXT_MUTED)
		theme.set_color("font_hovered_color", type_name, T.TEXT)
		theme.set_color("font_disabled_color", type_name, T.TEXT_DIM)
		theme.set_font("font", type_name, bold)
	theme.set_stylebox("panel", "TabContainer", flat(T.SURFACE, T.BORDER, 1, T.R_LG, 18, 16))
	# popups
	theme.set_stylebox("panel", "PopupMenu", with_shadow(flat(T.SURFACE_2, T.BORDER_STRONG, 1, T.R_MD, 6, 6), 12, 5, 0.55))
	theme.set_stylebox("hover", "PopupMenu", flat(T.SURFACE_3, T.GOLD_LO, 1, T.R_SM, 10, 8))
	theme.set_stylebox("selected", "PopupMenu", flat(T.SURFACE_GOLD, T.GOLD, 1, T.R_SM, 10, 8))
	theme.set_color("font_hover_color", "PopupMenu", T.GOLD_HI)
	theme.set_color("font_disabled_color", "PopupMenu", T.TEXT_DIM)
	theme.set_color("font_separator_color", "PopupMenu", T.TEXT_MUTED)
	theme.set_constant("v_separation", "PopupMenu", 6)
	theme.set_constant("item_start_padding", "PopupMenu", 10)
	theme.set_constant("item_end_padding", "PopupMenu", 10)
	var sep := StyleBoxLine.new()
	sep.color = T.BORDER
	theme.set_stylebox("separator", "PopupMenu", sep)
	theme.set_font_size("font_size", "PopupMenu", T.FS_BODY)
	# item list / tree basics for any lists a screen adds
	theme.set_stylebox("panel", "ItemList", flat(T.BG_DEEP, T.BORDER, 1, T.R_MD, 8, 8))
	theme.set_stylebox("selected", "ItemList", flat(T.SURFACE_GOLD, T.GOLD, 1, T.R_SM))
	theme.set_stylebox("selected_focus", "ItemList", flat(T.SURFACE_GOLD, T.GOLD_HI, 2, T.R_SM))
	theme.set_stylebox("hovered", "ItemList", flat(T.SURFACE_3, T.GOLD_LO, 1, T.R_SM))
	theme.set_color("font_color", "ItemList", T.TEXT)
	theme.set_color("font_selected_color", "ItemList", T.GOLD_HI)

static func _build_windows(theme: Theme, bold: Font) -> void:
	var dialog := with_shadow(flat(T.SURFACE, T.BORDER_STRONG, 1, T.R_LG, 14, 14), 24, 8, 0.65)
	var border := with_shadow(flat(T.SURFACE, T.GOLD_LO, 2, T.R_LG, 10, 10), 24, 8, 0.65)
	border.expand_margin_top = 44.0
	border.content_margin_top = 0
	border.content_margin_left = 0
	border.content_margin_right = 0
	border.content_margin_bottom = 0
	for type_name in ["AcceptDialog", "ConfirmationDialog"]:
		theme.set_stylebox("panel", type_name, dialog)
		theme.set_constant("buttons_separation", type_name, 8)
		theme.set_constant("buttons_min_height", type_name, 46)
		theme.set_constant("buttons_min_width", type_name, 80)
	theme.set_stylebox("embedded_border", "Window", border)
	theme.set_stylebox("embedded_unfocused_border", "Window", border)
	theme.set_color("title_color", "Window", T.GOLD_HI)
	theme.set_font("title_font", "Window", bold)
	theme.set_font_size("title_font_size", "Window", T.FS_LEAD)
	theme.set_constant("title_height", "Window", 44)
	theme.set_constant("title_outline_size", "Window", 0)
	theme.set_constant("resize_margin", "Window", 4)
	theme.set_icon("close", "Window", _close_icon(T.TEXT_MUTED))
	theme.set_icon("close_pressed", "Window", _close_icon(T.GOLD_HI))
	theme.set_constant("close_h_offset", "Window", 22)
	theme.set_constant("close_v_offset", "Window", 28)
	theme.set_color("scrim_color", "Window", Color(0, 0, 0, 0.55))
