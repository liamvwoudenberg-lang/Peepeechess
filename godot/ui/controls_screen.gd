class_name ControlsScreen
extends Control
## Controls configuration: who plays on which device, keyboard sets for Player 1 and Player 2, the gamepad
## buttons (named after the connected controller: Cross/Circle/Square/Triangle or A/B/X/Y), pad tuning (dead zone,
## camera speed, inversion, trigger point), conflict warnings, reset. Changes apply at once and are saved to
## user://controls.json. Works with mouse, keyboard and pad (D-pad up/down, Cross to rebind, Circle / Esc to leave).
##
##   ControlsScreen.open(some_node)        # a full-screen overlay on top of `some_node`'s scene
##
## Rebinding: select a row, the row says "Press a key..." (or "Press a button..." for the pad): the next key (or pad
## button / trigger) is bound. Esc cancels (and a pad capture times out after 6 s, so a pad-only player is never
## stuck). Conflicts are swapped (same set) or refused (other player's keys) and always explained in the status line.

signal closed

const TIMEOUT := 6.0

var bindings: ControlBindings
var assignment: InputAssignment
var path: String = ControlBindings.DEFAULT_PATH
var autosave: bool = true
var status: Label
var capture: Dictionary = {}  # {"kind": "key"|"pad", "scheme", "action", "button": Button, "left": float}
var _rows: Dictionary = {}    # "kb1/light" -> Button
var _players_box: VBoxContainer
var _seat_options: Array[OptionButton] = []
var _pad_names: Label
var _sliders: Dictionary = {}
var _reset_all: Button
var _reset_confirm := 0.0
var _body: VBoxContainer


static func open(host: Node, p_bindings: ControlBindings = null, p_assignment: InputAssignment = null) -> ControlsScreen:
	var screen := ControlsScreen.new()
	screen.bindings = p_bindings if p_bindings != null else ControlBindings.shared()
	screen.assignment = p_assignment if p_assignment != null else InputAssignment.shared()
	screen.name = "ControlsScreen"
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(screen)
	return screen


func _ready() -> void:
	add_to_group(PadUi.SCOPE_GROUP)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.07, 0.06, 1.0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 24)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var head := HBoxContainer.new()
	column.add_child(head)
	var title := Label.new()
	title.text = "Controls"
	title.add_theme_font_size_override("font_size", 34)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(120, 44)
	back.pressed.connect(close)
	head.add_child(back)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.text = "Select a control, then press the new key or button. Esc cancels."
	status.modulate = Color(1, 1, 1, 0.8)
	column.add_child(status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	column.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 6)
	scroll.add_child(_body)
	_build_players()
	_build_keyboard("kb1", "Player 1 keyboard + mouse (pick a profile, then rebind anything: keys, mouse buttons, the wheel)")
	_build_keyboard("kb2", "Player 2 keyboard (the mouse belongs to Player 1)")
	_build_pad()
	_build_pad_tuning()
	_build_overlay_option()  # control-overlay hook
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	column.add_child(footer)
	_reset_all = Button.new()
	_reset_all.text = "Reset everything to defaults"
	_reset_all.custom_minimum_size.y = 44
	_reset_all.pressed.connect(_on_reset_all)
	footer.add_child(_reset_all)
	var close_button := Button.new()
	close_button.text = "Done"
	close_button.custom_minimum_size.y = 44
	close_button.pressed.connect(close)
	footer.add_child(close_button)
	bindings.changed.connect(_refresh)
	assignment.assignment_changed.connect(_refresh_players)
	Input.joy_connection_changed.connect(_on_joy_changed)
	_refresh()
	_focus_first.call_deferred()


## Start on the first player option once the layout exists (focusing earlier would scroll to a wrong position).
func _focus_first() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_inside_tree() and not _seat_options.is_empty():
		_seat_options[0].grab_focus()


func _exit_tree() -> void:
	if Input.joy_connection_changed.is_connected(_on_joy_changed):
		Input.joy_connection_changed.disconnect(_on_joy_changed)


func close() -> void:
	_cancel_capture()
	_save()
	closed.emit()
	queue_free()


# ---- building ------------------------------------------------------------------------------------------------
func _section(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color("e5c586"))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(Control.new())
	_body.add_child(label)


func _build_players() -> void:
	_section("Players")
	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 6)
	_body.add_child(_players_box)
	for slot in 2:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "Player %d (%s) uses" % [slot + 1, "White" if slot == 0 else "Black"]
		label.custom_minimum_size.x = 260
		row.add_child(label)
		var option := OptionButton.new()
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option.custom_minimum_size.y = 44
		for item in [["Automatic (controllers first)", "auto"], ["Keyboard 1", "kb1"], ["Keyboard 2", "kb2"], ["First controller", "pad1"], ["Second controller", "pad2"]]:
			option.add_item(item[0])
			option.set_item_metadata(option.item_count - 1, item[1])
		var slot_index := slot
		option.item_selected.connect(func(i: int): _on_seat_selected(slot_index, String(option.get_item_metadata(i))))
		row.add_child(option)
		_seat_options.append(option)
		_players_box.add_child(row)
	_pad_names = Label.new()
	_pad_names.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pad_names.modulate = Color(1, 1, 1, 0.8)
	_players_box.add_child(_pad_names)
	var join := Button.new()
	join.text = "Press any button to join... (assign controllers by pressing them)"
	join.custom_minimum_size.y = 44
	join.pressed.connect(func():
		var prompt := JoinPrompt.open(self, assignment)
		prompt.finished.connect(func(_ok: bool): _refresh_players()))
	_players_box.add_child(join)


var _profile_options: Dictionary = {}   # scheme -> OptionButton


func _build_keyboard(scheme: String, heading: String) -> void:
	_section(heading)
	var profile_row := HBoxContainer.new()
	var profile_label := Label.new()
	profile_label.text = "Control profile"
	profile_label.custom_minimum_size.x = 320
	profile_row.add_child(profile_label)
	var profile_pick := OptionButton.new()
	profile_pick.custom_minimum_size = Vector2(260, 40)
	profile_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for id in ControlBindings.profiles_for(scheme):
		profile_pick.add_item(String(ControlBindings.PROFILE_LABELS[id]))
		profile_pick.set_item_metadata(profile_pick.item_count - 1, id)
	profile_pick.item_selected.connect(func(index: int): _on_profile_selected(scheme, String(profile_pick.get_item_metadata(index))))
	profile_row.add_child(profile_pick)
	_body.add_child(profile_row)
	_profile_options[scheme] = profile_pick
	for action in ControlBindings.KEY_ACTIONS:
		_add_row("%s/%s" % [scheme, action], String(ControlBindings.ACTION_LABELS[action]), func(): _begin_capture("key", scheme, action, "primary"))
		if action in ControlBindings.ALT_ACTIONS:
			_add_row("%s/%s#alt" % [scheme, action], "    " + String(ControlBindings.ACTION_LABELS[action]) + " (alternate)", func(): _begin_capture("key", scheme, action, "alt"))
	_build_options(scheme)
	var reset := Button.new()
	reset.text = "Reset this keyboard set to its profile defaults"
	reset.custom_minimum_size.y = 40
	reset.pressed.connect(func():
		bindings.reset_scheme(scheme)
		_say("%s restored to the defaults of %s." % ["Keyboard set", ControlBindings.PROFILE_LABELS[bindings.profile_of(scheme)]])
		_save())
	_body.add_child(reset)


func _on_profile_selected(scheme: String, id: String) -> void:
	var result := bindings.apply_profile(scheme, id)
	if not result["ok"]:
		_say("That profile cannot be used for this keyboard set.", true)
		return
	var cleared: Array = result["cleared"]
	if cleared.is_empty():
		_say("%s selected." % ControlBindings.PROFILE_LABELS[id])
	else:
		_say("%s selected. %d key(s) of the other keyboard set were unbound because they clash; rebind them below." % [ControlBindings.PROFILE_LABELS[id], cleared.size()], true)
	_save()


const OPTION_ROWS := [
	["mouse_sensitivity", "Mouse look speed", 0.2, 4.0, 0.05, true], ["camera_sensitivity", "Camera speed (mouse and camera keys)", 0.2, 4.0, 0.05, false],
	["heavy_hold_ms", "Hold to heavy attack after (ms)", 100.0, 600.0, 10.0, false], ["parry_tap_ms", "Tap the block button to parry within (ms)", 60.0, 400.0, 10.0, false],
	["sprint_tap_ms", "Tap sprint to dodge within (ms)", 80.0, 400.0, 10.0, false],
]
const OPTION_CHECKS := [
	["invert_x", "Invert camera left/right"], ["invert_y", "Invert camera up/down"], ["hold_block", "Block while held (off = press to toggle)"],
	["heavy_on_hold", "Hold the light attack button for a heavy attack (light then fires on release)"], ["alt_heavy", "Alt + light attack = heavy attack"],
	["parry_on_tap", "A quick tap of the block button also parries"], ["sprint_tap_dodge", "A quick tap of sprint dodges"], ["lock_hold", "Hold the lock-on button to free the camera"],
]


func _build_options(scheme: String) -> void:
	for item in OPTION_ROWS:
		if item[5] and scheme != "kb1":
			continue
		var key: String = item[0]
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = item[1]
		label.custom_minimum_size.x = 320
		row.add_child(label)
		var slider := HSlider.new()
		slider.min_value = item[2]
		slider.max_value = item[3]
		slider.step = item[4]
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.custom_minimum_size = Vector2(240, 40)
		slider.value_changed.connect(func(v: float):
			if bindings.set_option(scheme, key, v):
				_save())
		row.add_child(slider)
		var value := Label.new()
		value.custom_minimum_size.x = 60
		row.add_child(value)
		_sliders["opt/%s/%s" % [scheme, key]] = {"slider": slider, "label": value, "scheme": scheme, "name": key}
		_body.add_child(row)
	for item in OPTION_CHECKS:
		var key: String = item[0]
		var check := CheckButton.new()
		check.text = item[1]
		check.custom_minimum_size.y = 40
		check.toggled.connect(func(on: bool):
			if bindings.set_option(scheme, key, on):
				_save())
		_sliders["opt/%s/%s" % [scheme, key]] = {"check": check, "scheme": scheme, "name": key}
		_body.add_child(check)


func _build_pad() -> void:
	_section("Gamepad (every controller uses the same layout; sticks: left = move, right = camera; Options = pause; Share / Back = controls overlay)")
	for action in ControlBindings.PAD_ACTIONS:
		_add_row("pad/" + action, String(ControlBindings.ACTION_LABELS[action]), func(): _begin_capture("pad", "pad", action))
	var reset := Button.new()
	reset.text = "Reset gamepad buttons"
	reset.custom_minimum_size.y = 40
	reset.pressed.connect(func():
		var settings: Dictionary = bindings.pad_settings.duplicate()
		bindings.pad = ControlBindings.DEFAULT_PAD.duplicate(true)
		bindings.pad_settings = settings
		bindings.changed.emit()
		_say("Gamepad buttons restored to defaults.")
		_save())
	_body.add_child(reset)


func _build_pad_tuning() -> void:
	_section("Gamepad feel")
	for item in [["deadzone", "Stick dead zone", 0.05, 0.6, 0.01], ["response", "Stick response curve (1 = linear)", 0.5, 3.0, 0.1],
			["look_sensitivity", "Camera speed", 0.25, 3.0, 0.05], ["trigger_press", "Trigger press point (L2 / R2)", 0.2, 0.9, 0.05]]:
		var key: String = item[0]
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = item[1]
		label.custom_minimum_size.x = 320
		row.add_child(label)
		var slider := HSlider.new()
		slider.min_value = item[2]
		slider.max_value = item[3]
		slider.step = item[4]
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.custom_minimum_size = Vector2(240, 40)
		slider.value_changed.connect(func(v: float):
			if bindings.set_pad_setting(key, v):
				_save())
		row.add_child(slider)
		var value := Label.new()
		value.custom_minimum_size.x = 60
		row.add_child(value)
		_sliders[key] = {"slider": slider, "label": value}
		_body.add_child(row)
	for item in [["invert_look_x", "Invert camera left/right"], ["invert_look_y", "Invert camera up/down"]]:
		var key: String = item[0]
		var check := CheckButton.new()
		check.text = item[1]
		check.custom_minimum_size.y = 40
		check.toggled.connect(func(on: bool):
			if bindings.set_pad_setting(key, on):
				_save())
		_sliders[key] = {"check": check}
		_body.add_child(check)


# --- BEGIN control-overlay hook (combat/presentation/control_overlay.gd; prefs in control_overlay_prefs.gd) -----------
## "Show controls overlay in battles": the same remembered choice that F1 / Share / the on-screen chip change in a fight.
var overlay_check: CheckButton


func _build_overlay_option() -> void:
	_section("Battle HUD")
	overlay_check = CheckButton.new()
	overlay_check.text = "Show controls overlay in battles"
	overlay_check.custom_minimum_size.y = 40
	overlay_check.button_pressed = ControlOverlayPrefs.shared().enabled
	overlay_check.toggled.connect(func(on: bool): ControlOverlayPrefs.shared().set_enabled(on))
	_body.add_child(overlay_check)
	var note := Label.new()
	note.text = "In a fight F1 (keyboard) or Share / Back (gamepad) toggles it too; those two cannot be rebound."
	note.modulate = Color(1, 1, 1, 0.7)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(note)
# --- END control-overlay hook -------------------------------------------------------------------------------------


func _add_row(id: String, label_text: String, on_press: Callable) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 320
	row.add_child(label)
	var button := Button.new()
	button.custom_minimum_size = Vector2(260, 40)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(on_press)
	row.add_child(button)
	if id.begins_with("kb"):
		var key_clear := Button.new()
		key_clear.text = "Clear"
		key_clear.custom_minimum_size = Vector2(80, 40)
		var key_parts := id.split("/")
		var key_scheme := key_parts[0]
		var key_action := key_parts[1].replace("#alt", "")
		var key_slot := "alt" if id.ends_with("#alt") else "primary"
		key_clear.pressed.connect(func():
			if key_slot == "alt":
				bindings.set_alt(key_scheme, key_action, 0)
			else:
				bindings.set_key(key_scheme, key_action, 0)
			_say("%s is unbound." % ControlBindings.ACTION_LABELS[key_action])
			_save())
		row.add_child(key_clear)
	if id.begins_with("pad/"):
		var clear := Button.new()
		clear.text = "Clear"
		clear.custom_minimum_size = Vector2(80, 40)
		var action := id.substr(4)
		clear.pressed.connect(func():
			bindings.set_pad(action, {})
			_say("%s is unbound." % ControlBindings.ACTION_LABELS[action])
			_save())
		row.add_child(clear)
	_body.add_child(row)
	_rows[id] = button


# ---- text ------------------------------------------------------------------------------------------------------
func pad_family() -> int:
	for device in assignment.connected_pads():
		return ControllerGlyphs.family_of_device(device)
	return -1


func pad_text(input: Dictionary) -> String:
	var family := pad_family()
	if family >= 0:
		return ControllerGlyphs.input_label(input, family)
	if input.is_empty():
		return "Unbound"  # no controller connected: show both vocabularies
	return "%s / %s" % [ControllerGlyphs.input_label(input, ControllerGlyphs.Family.PLAYSTATION), ControllerGlyphs.input_label(input, ControllerGlyphs.Family.XBOX)]


func row_text(id: String) -> String:
	var parts := id.split("/")
	if parts[0] == "pad":
		return pad_text(bindings.pad_input(parts[1]))
	if parts[1].ends_with("#alt"):
		return ControlBindings.key_name(bindings.alt_for(parts[0], parts[1].replace("#alt", "")))
	return ControlBindings.key_name(bindings.key_for(parts[0], parts[1]))


func _refresh() -> void:
	for id in _rows:
		var button: Button = _rows[id]
		if not capture.is_empty() and capture.get("button") == button:
			continue
		button.text = row_text(id)
	for key in _sliders:
		var entry: Dictionary = _sliders[key]
		var current: Variant = bindings.option(entry["scheme"], entry["name"]) if entry.has("scheme") else bindings.pad_setting(key)
		if entry.has("slider"):
			var slider: HSlider = entry["slider"]
			slider.set_value_no_signal(float(current))
			entry["label"].text = ("%.0f" % float(current)) if float(slider.max_value) > 50.0 else ("%.2f" % float(current))
		else:
			(entry["check"] as CheckButton).set_pressed_no_signal(bool(current))
	for scheme in _profile_options:
		var pick: OptionButton = _profile_options[scheme]
		for i in pick.item_count:
			if pick.get_item_metadata(i) == bindings.profile_of(scheme):
				pick.select(i)
	for slot in _seat_options.size():
		var pref := bindings.seat_pref(slot)
		for i in _seat_options[slot].item_count:
			if _seat_options[slot].get_item_metadata(i) == pref:
				_seat_options[slot].select(i)
	_refresh_players()


func _refresh_players() -> void:
	if _pad_names == null:
		return
	var pads := assignment.connected_pads()
	var lines: Array[String] = []
	if pads.is_empty():
		lines.append("No controller detected. Plug in or pair a DualShock 4 / DualSense / Xbox controller; it is picked up automatically.")
	for device in pads:
		lines.append("Controller %d: %s (%s)" % [device, ControllerGlyphs.device_label(device), ControllerGlyphs.family_name(ControllerGlyphs.family_of_device(device))])
	lines.append(assignment.describe(0))
	lines.append(assignment.describe(1))
	_pad_names.text = "\n".join(lines)


func _on_joy_changed(_device: int, _connected: bool) -> void:
	_refresh()


func _say(text: String, warn: bool = false) -> void:
	status.text = text
	status.add_theme_color_override("font_color", Color("f1b7a0") if warn else Color("b6c4b5"))


func _on_seat_selected(slot: int, value: String) -> void:
	bindings.set_seat_pref(slot, value)
	var other := 1 - slot
	if value != "auto" and bindings.seat_pref(other) == value:
		bindings.set_seat_pref(other, "auto")
		_say("Player %d was using the same device, so it is set back to Automatic." % (other + 1), true)
	_save()


func _on_reset_all() -> void:
	if _reset_confirm <= 0.0:
		_reset_confirm = 3.0
		_reset_all.text = "Press again to reset EVERYTHING"
		return
	_reset_confirm = 0.0
	_reset_all.text = "Reset everything to defaults"
	bindings.reset_defaults("all")
	_say("All controls restored to defaults.")
	_save()


# ---- rebinding -----------------------------------------------------------------------------------------------------
func _begin_capture(kind: String, scheme: String, action: String, slot: String = "primary") -> void:
	_cancel_capture()
	var button: Button = _rows["%s/%s%s" % [("pad" if kind == "pad" else scheme), action, "#alt" if slot == "alt" else ""]]
	capture = {"kind": kind, "scheme": scheme, "action": action, "slot": slot, "button": button, "left": TIMEOUT}
	var mouse_ok := kind == "key" and scheme == "kb1" and action in ControlBindings.ALT_ACTIONS
	button.text = ("Press a key or mouse button...  (Esc cancels)" if mouse_ok else "Press a key...  (Esc cancels)") if kind == "key" else "Press a button...  (Esc cancels)"
	_say("Rebinding %s: %s" % [ControlBindings.ACTION_LABELS[action], "press the new key." if kind == "key" else "press the new controller button or trigger."])


func _cancel_capture() -> void:
	if capture.is_empty():
		return
	var button: Button = capture["button"]
	capture = {}
	_refresh()
	if is_instance_valid(button):
		button.grab_focus()


func _process(delta: float) -> void:
	if not capture.is_empty():
		capture["left"] = float(capture["left"]) - delta
		if capture["left"] <= 0.0 and capture["kind"] == "pad":
			_say("Rebinding timed out; nothing changed.")
			_cancel_capture()
	if _reset_confirm > 0.0:
		_reset_confirm -= delta
		if _reset_confirm <= 0.0:
			_reset_all.text = "Reset everything to defaults"


func _input(event: InputEvent) -> void:
	if capture.is_empty():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_say("Rebinding canceled.")
		_cancel_capture()
		get_viewport().set_input_as_handled()
		return
	var action: String = capture["action"]
	if capture["kind"] == "key":
		var scheme: String = capture["scheme"]
		var code := ControlBindings.event_to_binding(event) if (scheme == "kb1" and action in ControlBindings.ALT_ACTIONS) else ControlBindings.event_to_key(event)
		if code == KEY_NONE:
			return
		get_viewport().set_input_as_handled()
		var result := bindings.set_alt(scheme, action, code) if String(capture.get("slot", "primary")) == "alt" else bindings.set_key(scheme, action, code)
		capture = {}
		if not result["ok"]:
			_say("%s cannot be used: %s." % [ControlBindings.key_name(code), result["reason"]], true)
		elif result["swapped"]:
			_say("%s was already %s - the two were swapped." % [ControlBindings.key_name(code), _conflict_names(result["conflicts"])], true)
		else:
			_say("%s -> %s" % [ControlBindings.ACTION_LABELS[action], ControlBindings.key_name(code)])
		_refresh()
		_save()
	else:
		var input := ControlBindings.event_to_pad(event)
		if input.is_empty():
			return
		get_viewport().set_input_as_handled()
		var result := bindings.set_pad(action, input)
		capture = {}
		if not result["ok"]:
			_say("That button cannot be used: %s." % result["reason"], true)
		elif result["swapped"]:
			_say("%s was already %s - the two were swapped." % [pad_text(input), _conflict_names(result["conflicts"])], true)
		else:
			_say("%s -> %s" % [ControlBindings.ACTION_LABELS[action], pad_text(input)])
		_refresh()
		_save()


func _conflict_names(conflicts: Array) -> String:
	var names: Array[String] = []
	for c in conflicts:
		names.append(String(ControlBindings.ACTION_LABELS.get(c["action"], c["action"])))
	return "used by " + ", ".join(names)


func _unhandled_input(event: InputEvent) -> void:
	if not capture.is_empty():
		return
	if event.is_action_pressed("ui_cancel") and not (event is InputEventMouse):
		close()
		get_viewport().set_input_as_handled()


func _save() -> void:
	if not autosave:
		return
	var error := bindings.save_file(path)
	if error != OK:
		_say("Could not save your controls (%s). They are active for this session only." % bindings.last_error, true)
