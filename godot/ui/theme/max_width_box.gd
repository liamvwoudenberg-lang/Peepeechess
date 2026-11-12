extends MarginContainer
## Centres its child column and caps its width (wide / ultrawide screens would otherwise stretch cards edge to edge).
var max_width := 1120.0
func _ready() -> void:
	resized.connect(_fit)
	_fit()
func _fit() -> void:
	var side := maxi(0, int((size.x - max_width) * 0.5))
	add_theme_constant_override("margin_left", side)
	add_theme_constant_override("margin_right", side)
