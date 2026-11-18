extends MarginContainer
## Centres its child column and caps its width (wide / ultrawide screens would otherwise stretch cards edge to edge).
## `align_right` pins the column to the right edge instead, leaving the left "stage" open for the 3D world behind the cinematic menu pages.
var max_width := 1120.0
var align_right := false
func _ready() -> void:
	resized.connect(_fit)
	_fit()
func _fit() -> void:
	if align_right:
		# measured against the PARENT's width (our own width grows with our margins) and never narrower than the content needs
		var parent_width := (get_parent() as Control).size.x if get_parent() is Control else size.x
		var content_min := 0.0
		for child in get_children():
			if child is Control:
				content_min = maxf(content_min, (child as Control).get_combined_minimum_size().x)
		add_theme_constant_override("margin_left", maxi(0, int(parent_width - maxf(max_width, content_min))))
		add_theme_constant_override("margin_right", 0)
		return
	var side := maxi(0, int((size.x - max_width) * 0.5))
	add_theme_constant_override("margin_left", side)
	add_theme_constant_override("margin_right", side)
