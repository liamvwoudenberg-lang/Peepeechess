extends RefCounted

static func box(color: Color, radius: int = 10) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.set_border_width_all(1)
	style.border_color = Color("3f5647")
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

static func create() -> Theme:
	var theme = Theme.new()
	theme.default_font_size = 17
	for type_name in ["Label", "Button", "OptionButton", "CheckButton", "LineEdit", "RichTextLabel", "TextEdit", "SpinBox"]:
		theme.set_color("font_color", type_name, Color("f4eddc"))
		theme.set_color("font_hover_color", type_name, Color("e5c586"))
		theme.set_color("font_disabled_color", type_name, Color("748679"))
	for type_name in ["Button", "OptionButton"]:
		theme.set_stylebox("normal", type_name, box(Color("233e32")))
		theme.set_stylebox("hover", type_name, box(Color("345440")))
		theme.set_stylebox("pressed", type_name, box(Color("456246")))
		theme.set_stylebox("disabled", type_name, box(Color("1d3027")))
		var focus = box(Color.TRANSPARENT)
		focus.border_color = Color("e5c586")
		focus.set_border_width_all(3)
		theme.set_stylebox("focus", type_name, focus)
	for type_name in ["LineEdit", "TextEdit"]:
		theme.set_stylebox("normal", type_name, box(Color("10271f")))
	theme.set_stylebox("panel", "PopupMenu", box(Color("233e32")))
	theme.set_stylebox("panel", "AcceptDialog", box(Color("233e32")))
	theme.set_color("font_placeholder_color", "LineEdit", Color("99ab9d"))
	return theme
