class_name JoinPrompt
extends CanvasLayer
## "Press any button to join": a modal overlay driving InputAssignment's join flow for two local players.
## The first controller (or keyboard set: any key of the kb1 / kb2 map) to press becomes Player 1, the next one
## Player 2. Done / Esc keep what was joined (the rest falls back to automatic assignment); the pad can reach
## Done with D-pad + Cross once it has joined.

signal finished(completed: bool)

var assignment: InputAssignment
var _rows: Array[Label] = []
var _done: Button
var _pending_cancel := false


static func open(host: Node, p_assignment: InputAssignment = null, slots: int = 2) -> JoinPrompt:
	var prompt := JoinPrompt.new()
	prompt.assignment = p_assignment if p_assignment != null else InputAssignment.shared()
	host.add_child(prompt)
	prompt.assignment.begin_join(slots)
	prompt._refresh()
	return prompt


func _ready() -> void:
	layer = 70
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.92)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	var title := Label.new()
	title.text = "Press any button to join"
	title.add_theme_font_size_override("font_size", 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var note := Label.new()
	note.text = "Controllers: any button.  Keyboard: any key of the P1 (WASD...) or P2 (arrows...) set.\nFirst to press is Player 1 (White), the next is Player 2 (Black)."
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.modulate = Color(1, 1, 1, 0.75)
	box.add_child(note)
	for slot in 2:
		var row := Label.new()
		row.add_theme_font_size_override("font_size", 24)
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(row)
		_rows.append(row)
	_done = Button.new()
	_done.text = "Done (keep what is joined)"
	_done.custom_minimum_size = Vector2(0, 44)
	_done.pressed.connect(func(): _finish(false))
	box.add_child(_done)
	assignment.assignment_changed.connect(_refresh)
	assignment.join_completed.connect(_on_completed)
	_refresh()


func _refresh() -> void:
	if _rows.is_empty():
		return
	for slot in 2:
		var joined: bool = slot < assignment.join_slots and assignment.is_claimed(slot)
		_rows[slot].text = assignment.describe(slot) if joined else "P%d: waiting..." % (slot + 1) if slot < assignment.join_slots else "P%d: (automatic)" % (slot + 1)
		_rows[slot].modulate = Color(0.6, 1.0, 0.7) if joined else Color(1, 1, 1, 0.7)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_finish(false)
		get_viewport().set_input_as_handled()
	elif assignment.handle_join_event(event):
		get_viewport().set_input_as_handled()


func _on_completed() -> void:
	# Show both rows for a moment so the players see who is who, then close.
	_refresh()
	get_tree().create_timer(0.6).timeout.connect(func(): _finish(true))


func _finish(completed: bool) -> void:
	if _pending_cancel:
		return
	_pending_cancel = true
	assignment.joining = false
	assignment.assignment_changed.emit()
	finished.emit(completed)
	queue_free()
