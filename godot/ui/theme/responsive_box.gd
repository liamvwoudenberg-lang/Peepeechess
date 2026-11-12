extends BoxContainer
## A BoxContainer that lays its children out in a row when it is wide enough and in a column otherwise.
## `break_width` is in logical px; set `row_children_min_width` instead to derive it from the children.
var break_width := 760.0
var _last_vertical := false

func _ready() -> void:
	resized.connect(_reflow)
	_reflow()

func _reflow() -> void:
	var narrow := size.x < break_width
	if narrow != vertical:
		vertical = narrow
