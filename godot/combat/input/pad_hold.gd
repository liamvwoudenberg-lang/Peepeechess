class_name PadHold
extends Node
## Pause-and-wait for a controller that dropped out of a local fight.
##
## Attach to a CombatArena that is already running (after start_battle). Every frame it looks at the arena's
## LocalInputSource children; if one with a "pad<id>" scheme has lost its device, the arena's tick is frozen
## (`set_physics_process(false)`: no input is consumed, the simulation does not advance, so the fight is exactly
## where it was), a banner explains what to do, and the fight resumes when
##   * the same device id comes back (the usual case: unplug/replug, battery swap), or
##   * any button is pressed on another, unassigned controller (it takes the seat over).
## The sources themselves go neutral while their pad is missing (LocalInputSource.pad_lost). Nothing here can
## crash a fight: an arena that ended or was freed simply releases the hold.

signal hold_changed(holding: bool)

var arena: Node
var assignment: InputAssignment
var holding: bool = false
var lost_seats: Array[int] = []
var _layer: CanvasLayer
var _label: Label


static func attach(p_arena: Node, p_assignment: InputAssignment = null) -> PadHold:
	for existing in p_arena.get_children():
		if existing is PadHold:
			return existing
	var guard := PadHold.new()
	guard.name = "PadHold"
	guard.arena = p_arena
	guard.assignment = p_assignment if p_assignment != null else InputAssignment.shared()
	p_arena.add_child(guard)
	return guard


func _process(_delta: float) -> void:
	if arena == null or not is_instance_valid(arena):
		_set_hold(false)
		return
	var lost: Array[int] = []
	for source in _pad_sources():
		if not assignment.is_pad_connected(int(String(source.scheme).substr(3))):
			lost.append(_slot_of(source))
	lost_seats = lost
	_set_hold(not lost.is_empty())
	if holding:
		_label.text = _message()


func _pad_sources() -> Array:
	var out: Array = []
	for child in arena.get_children():
		if child is LocalInputSource and String(child.scheme).begins_with("pad"):
			out.append(child)
	return out


func _slot_of(source: LocalInputSource) -> int:
	return 0 if source.fighter != null and source.fighter.color == "w" else 1


func _source_of_slot(slot: int) -> LocalInputSource:
	for source in _pad_sources():
		if _slot_of(source) == slot:
			return source
	return null


func _message() -> String:
	var lines: Array[String] = ["Controller disconnected - fight paused"]
	for slot in lost_seats:
		var source := _source_of_slot(slot)
		var label := ControllerGlyphs.device_label(int(String(source.scheme).substr(3))) if source != null else "?"
		lines.append("Player %d: %s" % [slot + 1, label])
	lines.append("Reconnect it, or press any button on another controller to take over.")
	return "\n".join(lines)


func _set_hold(value: bool) -> void:
	if value == holding:
		return
	holding = value
	if is_instance_valid(arena):
		arena.set_physics_process(not value)
	if value:
		_layer = CanvasLayer.new()
		_layer.layer = 60
		var panel := PanelContainer.new()
		panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
		panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		panel.grow_vertical = Control.GROW_DIRECTION_BOTH
		_label = Label.new()
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.add_theme_font_size_override("font_size", 22)
		panel.add_child(_label)
		_layer.add_child(panel)
		add_child(_layer)
	elif _layer != null:
		_layer.queue_free()
		_layer = null
		_label = null
	hold_changed.emit(value)


func _input(event: InputEvent) -> void:
	if not holding or not (event is InputEventJoypadButton) or not event.pressed:
		return
	var device := int(event.device)
	if not assignment.is_pad_connected(device) or int(event.button_index) in ControlBindings.RESERVED_PAD_BUTTONS:
		return
	for slot in lost_seats:
		if assignment.device_for_slot(1 - slot) == device:
			continue  # the other player's pad cannot take this seat over
		var source := _source_of_slot(slot)
		if source != null and assignment.reassign(slot, device):
			source.scheme = "pad%d" % device
			get_viewport().set_input_as_handled()
			return


func _exit_tree() -> void:
	if holding and is_instance_valid(arena):
		arena.set_physics_process(true)
