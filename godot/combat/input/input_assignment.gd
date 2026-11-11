class_name InputAssignment
extends RefCounted
## Who controls which seat. Two local seats ("slots": 0 = Player 1 = White, 1 = Player 2 = Black) each resolve to
## a LocalInputSource scheme: "kb1", "kb2" or "pad<device id>".
##
## Resolution order for each slot:
##   1. match lock   - taken by lock_for_match() when a fight starts, so a pad that disconnects keeps its seat
##                     ("lost") instead of the seat silently jumping to the keyboard
##   2. claim        - made by the "press any button to join" flow (begin_join / handle_join_event)
##   3. preference   - ControlBindings.seat_prefs ("auto", "kb1", "kb2", "pad1" = first connected pad, "pad2")
##   4. auto         - the connected pads sorted by device id: first -> P1, second -> P2; a seat with no pad gets
##                     its keyboard (P1 kb1, P2 kb2)
##
## Pure logic on top of two injectable facts: which pads are connected (`connected_provider`, default
## Input.get_connected_joypads) and the bindings. Hot-plug arrives through `on_connection_changed`, wired to
## Input.joy_connection_changed for the shared instance. Not an autoload.

signal assignment_changed
## A seat's pad vanished (mid-match: the arena holds neutral input and pauses until it is restored).
signal device_lost(slot: int, device: int)
signal device_restored(slot: int, device: int)
signal join_progress(slot: int, scheme: String)
signal join_completed

var bindings: ControlBindings
var connected_provider: Callable = Callable()
var joining: bool = false
## Fixed seat count for a join round (1 or 2).
var join_slots: int = 2

var _claims: Array[String] = ["", ""]  # "kb1" | "kb2" | "dev:<id>"
var _lock: Array[String] = ["", ""]
var _lost: Array[bool] = [false, false]

static var _shared: InputAssignment = null


func _init(p_bindings: ControlBindings = null) -> void:
	bindings = p_bindings if p_bindings != null else ControlBindings.shared()


## Process-wide instance wired to the real Input singleton.
static func shared() -> InputAssignment:
	if _shared == null:
		_shared = InputAssignment.new()
		_shared.connect_hotplug()
	return _shared


## "pad<id>" of the lowest-numbered connected controller ("pad0" when none: the seat is then simply neutral).
static func first_pad_scheme() -> String:
	var pads := shared().connected_pads()
	return "pad%d" % pads[0] if not pads.is_empty() else "pad0"


static func set_shared(value: InputAssignment) -> void:
	_shared = value


func connect_hotplug() -> void:
	if not Input.joy_connection_changed.is_connected(on_connection_changed):
		Input.joy_connection_changed.connect(on_connection_changed)


func disconnect_hotplug() -> void:
	if Input.joy_connection_changed.is_connected(on_connection_changed):
		Input.joy_connection_changed.disconnect(on_connection_changed)


# ---- facts -------------------------------------------------------------------------------------------
func connected_pads() -> Array[int]:
	var raw: Array = connected_provider.call() if connected_provider.is_valid() else Input.get_connected_joypads()
	var out: Array[int] = []
	for device in raw:
		out.append(int(device))
	out.sort()
	return out


func is_pad_connected(device: int) -> bool:
	return device in connected_pads()


# ---- resolution --------------------------------------------------------------------------------------
## The scheme for a seat right now. For a locked / claimed pad that has vanished this is still "pad<id>" (check
## is_slot_ready / is_lost to tell).
func scheme_for_slot(slot: int) -> String:
	return _resolve()[clampi(slot, 0, 1)]


func scheme_for_color(color: String) -> String:
	return scheme_for_slot(0 if color == "w" else 1)


func device_for_slot(slot: int) -> int:
	var scheme := scheme_for_slot(slot)
	return int(scheme.substr(3)) if scheme.begins_with("pad") else -1


func is_slot_ready(slot: int) -> bool:
	var scheme := scheme_for_slot(slot)
	return not scheme.begins_with("pad") or is_pad_connected(int(scheme.substr(3)))


func is_lost(slot: int) -> bool:
	return _lost[clampi(slot, 0, 1)]


func _resolve() -> Array[String]:
	var pads := connected_pads()
	var out: Array[String] = ["", ""]
	for slot in 2:
		var want: String = _lock[slot] if _lock[slot] != "" else _claims[slot]
		if want == "":
			want = bindings.seat_pref(slot)
		if want == "kb1" or want == "kb2":
			out[slot] = want
		elif want.begins_with("dev:"):
			out[slot] = "pad" + want.substr(4)
		elif want == "pad1" or want == "pad2":
			var ordinal := int(want.substr(3)) - 1
			if ordinal < pads.size():
				out[slot] = "pad%d" % pads[ordinal]
	# A pad can only serve one seat; the later seat loses.
	if out[0] != "" and out[0] == out[1]:
		out[1] = ""
	for slot in 2:
		if out[slot] != "":
			continue
		for device in pads:
			if ("pad%d" % device) not in out:
				out[slot] = "pad%d" % device
				break
		if out[slot] == "":
			var preferred := "kb1" if slot == 0 else "kb2"
			var other := "kb2" if slot == 0 else "kb1"
			out[slot] = preferred if preferred not in out else other
	return out


# ---- hot-plug / mid-match ----------------------------------------------------------------------------
## Connect to Input.joy_connection_changed. Safe to call with fake data in tests.
func on_connection_changed(device: int, connected: bool) -> void:
	refresh(device, connected)


## Re-evaluates loss state. Emits device_lost / device_restored for seats whose pad changed state, and
## assignment_changed whenever the resolved schemes may have changed.
func refresh(_device: int = -1, _connected: bool = true) -> void:
	for slot in 2:
		var scheme := scheme_for_slot(slot)
		var was_lost := _lost[slot]
		var now_lost := scheme.begins_with("pad") and not is_pad_connected(int(scheme.substr(3)))
		_lost[slot] = now_lost
		if now_lost and not was_lost:
			device_lost.emit(slot, int(scheme.substr(3)))
		elif was_lost and not now_lost:
			device_restored.emit(slot, int(scheme.substr(3)))
	assignment_changed.emit()


## Freezes the current seats for the duration of a fight (see class comment). Call unlock() when it ends.
func lock_for_match() -> void:
	var now := _resolve()
	for slot in 2:
		_lock[slot] = now[slot] if now[slot] in ["kb1", "kb2"] else "dev:" + now[slot].substr(3)
		_lost[slot] = false
	refresh()


func unlock() -> void:
	_lock = ["", ""]
	_lost = [false, false]
	assignment_changed.emit()


## Gives a seat to another connected pad (a controller that came back under a new device id).
func reassign(slot: int, device: int) -> bool:
	if slot < 0 or slot > 1 or not is_pad_connected(device):
		return false
	var other := 1 - slot
	if device_for_slot(other) == device:
		return false
	if _lock[slot] != "":
		_lock[slot] = "dev:%d" % device  # mid-match: only for this fight, the standing claims / prefs are untouched
	else:
		_claims[slot] = "dev:%d" % device
	var was_lost := _lost[slot]
	_lost[slot] = false
	if was_lost:
		device_restored.emit(slot, device)
	assignment_changed.emit()
	return true


# ---- "press any button to join" -----------------------------------------------------------------------
## Clears claims and waits for button presses: the first pad (or kb1/kb2 key) to press becomes Player 1, the next
## distinct one Player 2.
func begin_join(slots: int = 2) -> void:
	join_slots = clampi(slots, 1, 2)
	_claims = ["", ""]
	joining = true
	assignment_changed.emit()


func cancel_join() -> void:
	joining = false
	_claims = ["", ""]
	assignment_changed.emit()


## Feed raw input events. Returns true if the event was a join press (consume it).
func handle_join_event(event: InputEvent) -> bool:
	if not joining:
		return false
	var claim := ""
	if event is InputEventJoypadButton and event.pressed and is_pad_connected(int(event.device)) \
			and not (int(event.button_index) in ControlBindings.RESERVED_PAD_BUTTONS):
		claim = "dev:%d" % int(event.device)
	elif event is InputEventKey and event.pressed and not event.echo:
		var code := ControlBindings.event_to_key(event)
		for scheme in ControlBindings.SCHEMES:
			if code in bindings.keys_for(scheme).values():
				claim = scheme
				break
	if claim == "" or claim in _claims:
		return false  # not a join press, or a repeat by a device that already joined (left for the UI: Done button)
	for slot in join_slots:
		if _claims[slot] == "":
			_claims[slot] = claim
			join_progress.emit(slot, scheme_for_slot(slot))
			break
	var filled := true
	for slot in join_slots:
		filled = filled and _claims[slot] != ""
	if filled:
		joining = false
		# A one-seat join leaves the other seat to auto resolution; make sure it does not reuse the joined device.
		assignment_changed.emit()
		join_completed.emit()
	else:
		assignment_changed.emit()
	return true


func is_claimed(slot: int) -> bool:
	return slot >= 0 and slot < 2 and _claims[slot] != ""


func joined_count() -> int:
	var n := 0
	for slot in join_slots:
		if _claims[slot] != "":
			n += 1
	return n


# ---- text --------------------------------------------------------------------------------------------
func describe(slot: int) -> String:
	var scheme := scheme_for_slot(slot)
	var who := "P%d" % (slot + 1)
	if scheme.begins_with("pad"):
		var device := int(scheme.substr(3))
		var label := ControllerGlyphs.device_label(device)
		return "%s: %s (controller %d)%s" % [who, label, device, "" if is_pad_connected(device) else " - disconnected"]
	return "%s: Keyboard %s" % [who, "1 (WASD + mouse)" if scheme == "kb1" else "2 (arrows)"]
