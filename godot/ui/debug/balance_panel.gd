extends CanvasLayer
## Debug balance panel (F6): tune the numbers of a role live and try them in the next fight. DEBUG BUILDS ONLY: a release build never
## creates it, and it refuses to change anything while an online/ranked match holds the tuning lock.
##
## Every +/- stepper writes into a local patch that is applied through Balance.apply_override (so the tuning stamp becomes
## "<id>+override" and a fight that is already running keeps its copy; the NEXT fight uses the new numbers).
## Buttons: Reset (drop every change), Copy JSON diff (clipboard: the patch, ready to paste into config/balance.json or into
## user://config_override/balance.json), Save override (writes user://config_override/balance.json so the next debug launch keeps it).
## Workflow and ranges: docs/game/BALANCE_GUIDE.md.
const Balance := preload("res://combat/data/balance_data.gd")
const Meta := preload("res://config/config_meta.gd")

const ROLE_ORDER := ["p", "n", "b", "r", "q", "k"]
const GLOBAL_KEYS := [["hit_stun", "light_mult"], ["hit_stun", "heavy_mult"], ["hit_stun", "ability_mult"],
		["pacing", "comeback", "hp_gap"], ["pacing", "comeback", "damage_mult"], ["pacing", "sudden_death", "start_s"], ["pacing", "sudden_death", "ramp_per_s"]]

var role := "p"
var patch: Dictionary = {}
var _root: PanelContainer
var _list: VBoxContainer
var _status: Label
var _meta: Dictionary = {}


static func attach(target: Node) -> Node:
	if not OS.is_debug_build():
		return null
	var existing := target.get_node_or_null("BalancePanel")
	if existing != null:
		return existing
	var node: Node = (load("res://ui/debug/balance_panel.gd") as GDScript).new()
	node.name = "BalancePanel"
	target.add_child(node)
	return node


func _ready() -> void:
	layer = 95
	process_mode = Node.PROCESS_MODE_ALWAYS
	_meta = Meta.meta(Balance.META_PATH)
	_build()
	_root.visible = false


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F6 and OS.is_debug_build():
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	_root.visible = not _root.visible
	if _root.visible:
		_refresh()


func is_open() -> bool:
	return _root.visible


## One stepper action, also what the tests call: changes `path` (e.g. ["profiles", "n", "armor"]) by `direction` steps.
## Returns the validation errors (empty = applied).
func step(path: Array, direction: int) -> Array:
	if Balance.is_online_locked():
		return ["balance changes are locked during online/ranked matches"]
	var current = _value_at(Balance.snapshot(), path)
	if current == null:
		return ["unknown setting " + ".".join(PackedStringArray(path))]
	var spec: Dictionary = _spec_for(path)
	var amount := _step_size(current, spec)
	var next
	if current is int:
		next = clampi(int(current) + direction * int(amount), int(spec.get("min", -1000000)), int(spec.get("max", 1000000)))
	else:
		next = clampf(snappedf(float(current) + direction * amount, 0.0001), float(spec.get("min", -1000000.0)), float(spec.get("max", 1000000.0)))
	var candidate := patch.duplicate(true)
	_set_at(candidate, path, next)
	var errors := Balance.apply_override(candidate)
	if errors.is_empty():
		patch = candidate
	_refresh()
	return errors


func reset() -> void:
	patch = {}
	Balance.clear_override()
	_refresh()


func diff_json() -> String:
	return JSON.stringify(patch, "\t")


func save_override() -> bool:
	if patch.is_empty():
		return false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://config_override"))
	var file := FileAccess.open(Balance.DEV_OVERRIDE_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(diff_json())
	return true


# ---- UI ------------------------------------------------------------------------------------------
func _build() -> void:
	_root = PanelContainer.new()
	_root.anchor_left = 1.0
	_root.anchor_right = 1.0
	_root.offset_left = -430.0
	_root.offset_right = -10.0
	_root.offset_top = 70.0
	_root.offset_bottom = 640.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.08, 0.94)
	style.border_color = Color(0.9, 0.75, 0.4)
	style.set_border_width_all(1)
	style.set_content_margin_all(10)
	_root.add_theme_stylebox_override("panel", style)
	add_child(_root)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_root.add_child(column)
	var title := Label.new()
	title.text = "Balance (debug) · F6 closes · next fight uses the numbers"
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	column.add_child(title)
	var top := HBoxContainer.new()
	column.add_child(top)
	var picker := OptionButton.new()
	for r in ROLE_ORDER:
		if Balance.has_role(r):
			picker.add_item("%s (%s)" % [Balance.profile(r).get("display", r), r])
	picker.item_selected.connect(func(index: int): role = ROLE_ORDER[index]; _refresh())
	top.add_child(picker)
	for entry in [["Reset", reset], ["Copy JSON diff", func(): DisplayServer.clipboard_set(diff_json()); _say("copied %d change(s)" % _count_changes())], ["Save override", func(): _say("saved to user://config_override/balance.json" if save_override() else "nothing to save")]]:
		var button := Button.new()
		button.text = entry[0]
		button.pressed.connect(entry[1])
		top.add_child(button)
	_status = Label.new()
	_status.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	column.add_child(_status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 430)
	column.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)


func _refresh() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		child.queue_free()
	var data := Balance.snapshot()
	_status.text = "stamp %s · %d change(s)%s" % [Balance.stamp(), _count_changes(), "  · LOCKED (online)" if Balance.is_online_locked() else ""]
	var profile: Dictionary = data["profiles"].get(role, {})
	var keys: Array = profile.keys()
	keys.sort()
	for key in keys:
		if profile[key] is String:
			continue
		_row(["profiles", role, key], profile[key])
	for path in GLOBAL_KEYS:
		var value = _value_at(data, path)
		if value != null:
			_row(path, value)


func _row(path: Array, value) -> void:
	var row := HBoxContainer.new()
	var spec := _spec_for(path)
	var name_label := Label.new()
	name_label.text = String(path[path.size() - 1])
	name_label.tooltip_text = "%s (%s)" % [spec.get("doc", ""), spec.get("unit", "")]
	name_label.custom_minimum_size = Vector2(200, 0)
	var changed := _value_at(patch, path) != null
	name_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4) if changed else Color(0.85, 0.88, 0.95))
	row.add_child(name_label)
	var minus := Button.new()
	minus.text = "−"
	minus.pressed.connect(func(): _report(step(path, -1)))
	row.add_child(minus)
	var value_label := Label.new()
	value_label.text = _fmt(value)
	value_label.custom_minimum_size = Vector2(70, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(value_label)
	var plus := Button.new()
	plus.text = "+"
	plus.pressed.connect(func(): _report(step(path, 1)))
	row.add_child(plus)
	var unit_label := Label.new()
	unit_label.text = " " + String(spec.get("unit", ""))
	unit_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	row.add_child(unit_label)
	_list.add_child(row)


func _report(errors: Array) -> void:
	_say("" if errors.is_empty() else String(errors[0]))


func _say(text: String) -> void:
	if _status != null:
		_status.text = text if not text.is_empty() else _status.text


func _fmt(value) -> String:
	return str(value) if value is int else str(snappedf(float(value), 0.0001))


func _count_changes() -> int:
	return load("res://config/config_tools.gd").flatten(patch).size()


func _spec_for(path: Array) -> Dictionary:
	if path.size() >= 3 and path[0] == "profiles":
		return (_meta.get("profiles", {}) as Dictionary).get(path[2], {})
	return (_meta.get("paths", {}) as Dictionary).get(".".join(PackedStringArray(path)), {})


func _step_size(current, spec: Dictionary) -> float:
	if current is int:
		return maxf(1.0, roundf(absf(float(current)) * 0.05))
	var range_span := float(spec.get("max", 1.0)) - float(spec.get("min", 0.0)) if spec.has("max") else 1.0
	return maxf(0.001, snappedf(minf(absf(float(current)) * 0.05 if float(current) != 0.0 else range_span * 0.02, range_span * 0.1), 0.001))


static func _value_at(data: Dictionary, path: Array):
	var node = data
	for key in path:
		if not node is Dictionary or not (node as Dictionary).has(key):
			return null
		node = node[key]
	return node


static func _set_at(data: Dictionary, path: Array, value) -> void:
	var node: Dictionary = data
	for i in path.size() - 1:
		if not node.get(path[i]) is Dictionary:
			node[path[i]] = {}
		node = node[path[i]]
	node[path[path.size() - 1]] = value
