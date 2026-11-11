class_name ControlBindings
extends RefCounted
## Combat control bindings: the single source of truth for what each key / pad button does.
##
## * Keyboard sets "kb1" (player 1) and "kb2" (player 2). Keys are PHYSICAL key codes (layout independent, like
##   the constants they replace). Mouse buttons for kb1 (LMB light, RMB heavy, MMB lock, wheel zoom) are fixed.
## * One gamepad set, shared by every pad (each pad is a separate device; there is no cross-talk, see
##   LocalInputSource). The sticks are fixed (left = move, right = camera); everything else can be rebound.
## * Pad analog settings (dead zone, response curve, camera sensitivity, inversion, trigger thresholds).
## * Seat preferences ("auto" | "kb1" | "kb2" | "pad1" | "pad2") that InputAssignment honours.
##
## Defaults reproduce the constants that used to live in local_input_source.gd. Persistence: user://controls.json
## (versioned, validated; a corrupt or hostile file never crashes the game - it is backed up and defaults load).
## Not an autoload: `shared()` is a lazily created process-wide instance.

signal changed

const VERSION := 1
const DEFAULT_PATH := "user://controls.json"
const SCHEMES := ["kb1", "kb2"]
const KEY_ACTIONS := ["up", "down", "left", "right", "sprint", "light", "heavy", "dodge", "block", "parry", "ability", "lock", "orbit_l", "orbit_r"]
const PAD_ACTIONS := ["sprint", "light", "heavy", "heavy2", "dodge", "block", "parry", "ability", "lock"]
## Actions that are "held" (polled every tick) rather than one press per tap.
const HELD_ACTIONS := ["sprint", "block"]
const ACTION_LABELS := {
	"up": "Move forward", "down": "Move back", "left": "Move left", "right": "Move right",
	"sprint": "Sprint (hold)", "light": "Light attack", "heavy": "Heavy attack", "heavy2": "Heavy attack (alternate)",
	"dodge": "Dodge", "block": "Block (hold)", "parry": "Parry", "ability": "Special ability",
	"lock": "Lock-on / free camera", "orbit_l": "Camera left", "orbit_r": "Camera right",
}
const DEFAULT_KEYS := {
	"kb1": {"up": KEY_W, "down": KEY_S, "left": KEY_A, "right": KEY_D, "sprint": KEY_SHIFT, "light": KEY_F, "heavy": KEY_G,
		"dodge": KEY_SPACE, "block": KEY_Q, "parry": KEY_E, "ability": KEY_R, "lock": KEY_TAB, "orbit_l": KEY_Z, "orbit_r": KEY_X},
	"kb2": {"up": KEY_UP, "down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT, "sprint": KEY_CTRL, "light": KEY_J, "heavy": KEY_K,
		"dodge": KEY_L, "block": KEY_U, "parry": KEY_I, "ability": KEY_O, "lock": KEY_P, "orbit_l": KEY_COMMA, "orbit_r": KEY_PERIOD},
}
## DualShock 4 names in comments (SDL layout: A = Cross, B = Circle, X = Square, Y = Triangle).
const DEFAULT_PAD := {
	"sprint": {"type": "axis", "index": JOY_AXIS_TRIGGER_LEFT},      # L2 (hold; hysteresis 0.50 / 0.35)
	"light": {"type": "button", "index": JOY_BUTTON_X},               # Square
	"heavy": {"type": "button", "index": JOY_BUTTON_Y},               # Triangle
	"heavy2": {"type": "axis", "index": JOY_AXIS_TRIGGER_RIGHT},     # R2 = heavy attack alias (same press counter)
	"dodge": {"type": "button", "index": JOY_BUTTON_A},               # Cross
	"block": {"type": "button", "index": JOY_BUTTON_LEFT_SHOULDER},  # L1 (hold)
	"parry": {"type": "button", "index": JOY_BUTTON_RIGHT_SHOULDER}, # R1
	"ability": {"type": "button", "index": JOY_BUTTON_B},             # Circle
	"lock": {"type": "button", "index": JOY_BUTTON_LEFT_STICK},      # L3
}
const DEFAULT_PAD_SETTINGS := {
	"deadzone": 0.18, "outer_deadzone": 0.96, "response": 1.0, "look_sensitivity": 1.0,
	"invert_look_x": false, "invert_look_y": false, "trigger_press": 0.5, "trigger_release": 0.35,
}
## [min, max] per numeric pad setting.
const PAD_SETTING_RANGES := {
	"deadzone": [0.05, 0.6], "outer_deadzone": [0.7, 1.0], "response": [0.5, 3.0], "look_sensitivity": [0.25, 3.0],
	"trigger_press": [0.2, 0.9], "trigger_release": [0.05, 0.85],
}
const SEATS := ["auto", "kb1", "kb2", "pad1", "pad2"]
## Keys that menus own; they cannot be combat bindings (Esc cancels / leaves, F11 toggles fullscreen).
const RESERVED_KEYS := [KEY_ESCAPE, KEY_F11]
## Options/Start opens menus and pauses; it cannot be rebound.
const RESERVED_PAD_BUTTONS := [JOY_BUTTON_START]
const BINDABLE_AXES := [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]

var keys: Dictionary = {}
var pad: Dictionary = {}
var pad_settings: Dictionary = {}
var seat_prefs: Dictionary = {"p1": "auto", "p2": "auto"}
## Human readable notes from the last load (invalid entries that were replaced by defaults).
var warnings: Array[String] = []
var last_error: String = ""

static var _shared: ControlBindings = null


func _init() -> void:
	reset_defaults()


## Process-wide instance, loaded from user://controls.json on first use.
static func shared() -> ControlBindings:
	if _shared == null:
		_shared = ControlBindings.new()
		_shared.load_file()
	return _shared


## Tests replace the shared instance (null = lazily reload from disk next time).
static func set_shared(value: ControlBindings) -> void:
	_shared = value


# ---- defaults / lookup ----------------------------------------------------------------------------
func reset_defaults(scope: String = "all") -> void:
	if scope == "all" or scope == "kb1":
		keys["kb1"] = DEFAULT_KEYS["kb1"].duplicate()
	if scope == "all" or scope == "kb2":
		keys["kb2"] = DEFAULT_KEYS["kb2"].duplicate()
	if scope == "all" or scope == "pad":
		pad = DEFAULT_PAD.duplicate(true)
		pad_settings = DEFAULT_PAD_SETTINGS.duplicate(true)
	if scope == "all":
		seat_prefs = {"p1": "auto", "p2": "auto"}
	changed.emit()


func is_default() -> bool:
	return keys == DEFAULT_KEYS and pad == DEFAULT_PAD and pad_settings == DEFAULT_PAD_SETTINGS and seat_prefs == {"p1": "auto", "p2": "auto"}


func keys_for(scheme: String) -> Dictionary:
	return keys.get(scheme, {})


func key_for(scheme: String, action: String) -> int:
	return int(keys.get(scheme, {}).get(action, KEY_NONE))


## {"type": "button"|"axis", "index": int} or {} when unbound.
func pad_input(action: String) -> Dictionary:
	return pad.get(action, {})


func pad_setting(name: String) -> Variant:
	return pad_settings.get(name, DEFAULT_PAD_SETTINGS.get(name))


# ---- editing ----------------------------------------------------------------------------------------
## Binds `keycode` (physical) to `action` of `scheme`. `conflict` decides what happens if another action (in this
## set or in the other player's keyboard set) already uses that key:
##   "swap"   the other action receives this action's old key (a same-set swap; a cross-set clash is refused)
##   "reject" nothing changes
##   "allow"  duplicate allowed (find_conflicts() will still report it)
## Returns {"ok": bool, "conflicts": [{"scheme","action"}], "reason": String, "swapped": bool}.
func set_key(scheme: String, action: String, keycode: int, conflict: String = "swap") -> Dictionary:
	if not keys.has(scheme) or not (action in KEY_ACTIONS):
		return _fail("unknown binding %s/%s" % [scheme, action])
	if keycode <= 0 or keycode in RESERVED_KEYS:
		return _fail("that key is reserved for menus")
	var clashes := _key_clashes(scheme, action, keycode)
	if not clashes.is_empty() and conflict != "allow":
		if conflict == "reject":
			return {"ok": false, "conflicts": clashes, "reason": "already used", "swapped": false}
		for clash in clashes:
			if clash["scheme"] != scheme:
				return {"ok": false, "conflicts": clashes, "reason": "already used by the other player's keyboard set", "swapped": false}
		var old := key_for(scheme, action)
		for clash in clashes:
			keys[scheme][clash["action"]] = old
		keys[scheme][action] = keycode
		changed.emit()
		return {"ok": true, "conflicts": clashes, "reason": "", "swapped": true}
	keys[scheme][action] = keycode
	changed.emit()
	return {"ok": true, "conflicts": clashes, "reason": "", "swapped": false}


## `input` as returned by event_to_pad(), or {} to unbind.
func set_pad(action: String, input: Dictionary, conflict: String = "swap") -> Dictionary:
	if not (action in PAD_ACTIONS):
		return _fail("unknown pad action " + action)
	if not input.is_empty() and not _valid_pad_input(input):
		return _fail("that button cannot be bound")
	var clashes: Array = []
	if not input.is_empty():
		for other in PAD_ACTIONS:
			if other != action and pad.get(other, {}) == input:
				clashes.append({"scheme": "pad", "action": other})
	if not clashes.is_empty() and conflict != "allow":
		if conflict == "reject":
			return {"ok": false, "conflicts": clashes, "reason": "already used", "swapped": false}
		var old: Dictionary = pad.get(action, {})
		for clash in clashes:
			pad[clash["action"]] = old.duplicate()
		pad[action] = input.duplicate()
		changed.emit()
		return {"ok": true, "conflicts": clashes, "reason": "", "swapped": true}
	pad[action] = input.duplicate()
	changed.emit()
	return {"ok": true, "conflicts": clashes, "reason": "", "swapped": false}


func set_pad_setting(name: String, value: Variant) -> bool:
	if not DEFAULT_PAD_SETTINGS.has(name):
		return false
	var fixed: Variant = _fix_setting(name, value)
	if fixed == null:
		return false
	pad_settings[name] = fixed
	_repair_trigger_thresholds()
	changed.emit()
	return true


func set_seat_pref(slot: int, value: String) -> bool:
	if slot < 0 or slot > 1 or not (value in SEATS):
		return false
	seat_prefs["p%d" % (slot + 1)] = value
	changed.emit()
	return true


func seat_pref(slot: int) -> String:
	return String(seat_prefs.get("p%d" % (slot + 1), "auto"))


## Every duplicate binding as {"a": "kb1/light", "b": "kb1/heavy", "key": name}; empty = conflict free.
func find_conflicts() -> Array:
	var out: Array = []
	var seen: Dictionary = {}  # keycode -> "scheme/action"
	for scheme in SCHEMES:
		for action in KEY_ACTIONS:
			var code := key_for(scheme, action)
			var id := "%s/%s" % [scheme, action]
			if seen.has(code):
				out.append({"a": seen[code], "b": id, "key": key_name(code)})
			else:
				seen[code] = id
	var seen_pad: Dictionary = {}
	for action in PAD_ACTIONS:
		var input: Dictionary = pad.get(action, {})
		if input.is_empty():
			continue
		var token := _pad_token(input)
		if seen_pad.has(token):
			out.append({"a": "pad/" + seen_pad[token], "b": "pad/" + action, "key": token})
		else:
			seen_pad[token] = action
	return out


func _key_clashes(scheme: String, action: String, keycode: int) -> Array:
	var out: Array = []
	for s in SCHEMES:
		for other in KEY_ACTIONS:
			if (s != scheme or other != action) and key_for(s, other) == keycode:
				out.append({"scheme": s, "action": other})
	return out


func _fail(reason: String) -> Dictionary:
	return {"ok": false, "conflicts": [], "reason": reason, "swapped": false}


# ---- events -> bindings (rebinding capture) -----------------------------------------------------------
## Physical key of a pressed key event; KEY_NONE for echoes, releases and non-keys.
static func event_to_key(event: InputEvent) -> int:
	if event is InputEventKey and event.pressed and not event.echo:
		var code: int = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		return int(code)
	return KEY_NONE


## A pressed pad button, or a trigger pushed past 0.6; {} otherwise (sticks and Options never bind).
static func event_to_pad(event: InputEvent) -> Dictionary:
	if event is InputEventJoypadButton and event.pressed:
		var input := {"type": "button", "index": int(event.button_index)}
		return input if _valid_pad_input(input) else {}
	if event is InputEventJoypadMotion and int(event.axis) in BINDABLE_AXES and event.axis_value > 0.6:
		return {"type": "axis", "index": int(event.axis)}
	return {}


static func _valid_pad_input(input: Dictionary) -> bool:
	if not input.has("type") or not input.has("index"):
		return false
	var index := int(input["index"])
	match String(input["type"]):
		"button":
			return index >= 0 and index < JOY_BUTTON_SDL_MAX and not (index in RESERVED_PAD_BUTTONS)
		"axis":
			return index in BINDABLE_AXES
	return false


static func _pad_token(input: Dictionary) -> String:
	return "%s:%d" % [input.get("type", "?"), int(input.get("index", -1))]


static func _parse_pad_token(value: Variant) -> Variant:
	if value is String and value == "none":
		return {}
	if not value is String or not ":" in value:
		return null
	var parts: PackedStringArray = (value as String).split(":")
	if parts.size() != 2 or not parts[1].is_valid_int():
		return null
	var input := {"type": parts[0], "index": int(parts[1])}
	return input if _valid_pad_input(input) else null


# ---- naming ------------------------------------------------------------------------------------------
static func key_name(code: int) -> String:
	if code <= 0:
		return "Unbound"
	# Show what is printed on the player's keycap (AZERTY: physical W is "Z"); fall back to the code's name.
	var shown: int = DisplayServer.keyboard_get_keycode_from_physical(code as Key) if DisplayServer.get_name() != "headless" else code
	var short := {KEY_COMMA: ",", KEY_PERIOD: ".", KEY_SLASH: "/", KEY_BACKSLASH: "\\", KEY_SEMICOLON: ";", KEY_APOSTROPHE: "'", KEY_BRACKETLEFT: "[", KEY_BRACKETRIGHT: "]",
		KEY_MINUS: "-", KEY_EQUAL: "=", KEY_QUOTELEFT: "`"}
	if short.has(shown if shown != KEY_NONE else code):
		return short[shown if shown != KEY_NONE else code]
	var name := OS.get_keycode_string(shown if shown != KEY_NONE else code)
	return name if not name.is_empty() else "Key %d" % code


func action_binding_text(scheme: String, action: String, device: int = -1) -> String:
	if scheme in SCHEMES:
		return key_name(key_for(scheme, action))
	return ControllerGlyphs.input_label_for_device(pad_input(action), device)


# ---- hint strings -------------------------------------------------------------------------------------
## One-line control summary for the HUD / menus, generated from the live bindings.
## `scheme` is "kb1", "kb2", "padN" or "touch".
func hint_text(scheme: String) -> String:
	if scheme == "touch":
		return "Left stick move · right buttons act (Light, Heavy, Dodge, Parry, Special) · hold Block · Lock-on button · drag to orbit"
	if scheme in SCHEMES:
		return _keyboard_hint(scheme)
	var device := int(scheme.substr(3)) if scheme.begins_with("pad") and scheme.substr(3).is_valid_int() else -1
	return pad_hint(ControllerGlyphs.family_of_device(device) if device >= 0 else ControllerGlyphs.Family.XBOX, device)


func _keyboard_hint(scheme: String) -> String:
	var k: Dictionary = keys_for(scheme)
	var n := func(a: String) -> String: return key_name(int(k.get(a, KEY_NONE)))
	var move := ""
	if scheme == "kb2" and k.get("up") == KEY_UP and k.get("down") == KEY_DOWN and k.get("left") == KEY_LEFT and k.get("right") == KEY_RIGHT:
		move = "Arrows"
	elif k.get("up") == KEY_W and k.get("left") == KEY_A and k.get("down") == KEY_S and k.get("right") == KEY_D:
		move = "WASD"
	else:
		move = "%s/%s/%s/%s" % [n.call("up"), n.call("left"), n.call("down"), n.call("right")]
	var light: String = ("LMB/" if scheme == "kb1" else "") + n.call("light")
	var heavy: String = ("RMB/" if scheme == "kb1" else "") + n.call("heavy")
	var cam: String = ("mouse or " if scheme == "kb1" else "") + "%s / %s" % [n.call("orbit_l"), n.call("orbit_r")]
	return "%s move · %s sprint · %s light · %s heavy · %s hold block · %s parry · %s dodge · %s ability · %s lock-on · %s camera" % [
		move, n.call("sprint"), light, heavy, n.call("block"), n.call("parry"), n.call("dodge"), n.call("ability"), n.call("lock"), cam]


func pad_hint(family: int, device: int = -1) -> String:
	var lbl := func(a: String) -> String: return ControllerGlyphs.input_label(pad_input(a), family)
	var heavy: String = lbl.call("heavy")
	if not pad_input("heavy2").is_empty():
		heavy += "/" + String(lbl.call("heavy2"))
	return "Pad: left stick move · %s sprint · %s light · %s heavy · %s hold block · %s parry · %s dodge · %s ability · %s lock-on · right stick camera · %s pause" % [
		lbl.call("sprint"), lbl.call("light"), heavy, lbl.call("block"), lbl.call("parry"), lbl.call("dodge"),
		lbl.call("ability"), lbl.call("lock"), ControllerGlyphs.button_label(JOY_BUTTON_START, family)]


## Multi-line help for menus (both keyboard sets and the pad in the connected controller's own words).
func help_text(family: int = -1) -> String:
	if family < 0:
		family = ControllerGlyphs.Family.PLAYSTATION
		for device in Input.get_connected_joypads():
			family = ControllerGlyphs.family_of_device(device)
			break
	return "P1: %s\nP2: %s\n%s" % [_keyboard_hint("kb1"), _keyboard_hint("kb2"), pad_hint(family)]


# ---- persistence --------------------------------------------------------------------------------------
func to_dict() -> Dictionary:
	var pad_out: Dictionary = {}
	for action in PAD_ACTIONS:
		var input: Dictionary = pad.get(action, {})
		pad_out[action] = "none" if input.is_empty() else _pad_token(input)
	return {"version": VERSION, "keyboard": keys.duplicate(true), "pad": pad_out, "pad_settings": pad_settings.duplicate(true),
		"assignment": seat_prefs.duplicate()}


func save_file(path: String = DEFAULT_PATH) -> Error:
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		last_error = "could not write %s (error %d)" % [tmp, FileAccess.get_open_error()]
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_dict(), "\t"))
	file.close()
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		last_error = "could not open " + path.get_base_dir()
		return ERR_CANT_OPEN
	if dir.file_exists(path.get_file()):
		dir.remove(path.get_file())
	var err := dir.rename(tmp.get_file(), path.get_file())
	if err != OK:
		last_error = "could not replace %s (error %d)" % [path, err]
	return err


## Loads and validates. A missing file is not an error (defaults). A corrupt file loads defaults, is copied to
## `<path>.corrupt` and reported in `last_error`; the next save() then writes a clean file. Returns true if a
## file was read and understood.
func load_file(path: String = DEFAULT_PATH) -> bool:
	warnings.clear()
	last_error = ""
	if not FileAccess.file_exists(path):
		reset_defaults()
		return false
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = null
	if text.length() < 65536:
		var json := JSON.new()  # JSON.parse_string would print an engine ERROR line for a corrupt file
		if json.parse(text) == OK:
			parsed = json.data
	if not parsed is Dictionary:
		_quarantine(path, "controls file is not valid JSON")
		reset_defaults()
		return false
	if from_dict(parsed):
		return true
	_quarantine(path, last_error if not last_error.is_empty() else "controls file rejected")
	reset_defaults()
	return false


func _quarantine(path: String, why: String) -> void:
	last_error = why
	var dir := DirAccess.open(path.get_base_dir())
	if dir != null:
		var bad := path.get_file() + ".corrupt"
		if dir.file_exists(bad):
			dir.remove(bad)
		dir.rename(path.get_file(), bad)


## Applies a parsed file. Unknown version -> rejected. Each section is validated independently: a bad entry
## falls back to its default and adds a warning; a section with duplicate bindings falls back entirely.
func from_dict(data: Dictionary) -> bool:
	if not data.has("version") or not (data["version"] is float or data["version"] is int) or int(data["version"]) != VERSION:
		last_error = "unsupported controls file version"
		return false
	var fresh := ControlBindings.new()
	var kb: Variant = data.get("keyboard", {})
	for scheme in SCHEMES:
		var section: Variant = kb.get(scheme, {}) if kb is Dictionary else {}
		for action in KEY_ACTIONS:
			var value: Variant = section.get(action) if section is Dictionary else null
			if (value is float or value is int) and int(value) > 0 and int(value) < 0x7fffffff and not (int(value) in RESERVED_KEYS) \
					and float(value) == float(int(value)):
				fresh.keys[scheme][action] = int(value)
			elif section is Dictionary and section.has(action):
				warnings.append("%s/%s invalid; default restored" % [scheme, action])
	var pad_data: Variant = data.get("pad", {})
	for action in PAD_ACTIONS:
		if pad_data is Dictionary and pad_data.has(action):
			var parsed: Variant = _parse_pad_token(pad_data[action])
			if parsed == null:
				warnings.append("pad/%s invalid; default restored" % action)
			else:
				fresh.pad[action] = parsed
	var settings: Variant = data.get("pad_settings", {})
	if settings is Dictionary:
		for name in DEFAULT_PAD_SETTINGS:
			if settings.has(name):
				var fixed: Variant = _fix_setting(name, settings[name])
				if fixed == null:
					warnings.append("pad_settings/%s invalid; default restored" % name)
				else:
					fresh.pad_settings[name] = fixed
	fresh._repair_trigger_thresholds()
	var assignment: Variant = data.get("assignment", {})
	if assignment is Dictionary:
		for slot in ["p1", "p2"]:
			if assignment.has(slot) and assignment[slot] is String and assignment[slot] in SEATS:
				fresh.seat_prefs[slot] = assignment[slot]
	# Duplicates: refuse the offending section, never run with an ambiguous map.
	var settings_kept: Dictionary = fresh.pad_settings.duplicate()
	for c in fresh.find_conflicts():
		var scheme_b: String = String(c["b"]).get_slice("/", 0)
		warnings.append("duplicate binding %s and %s (%s): %s restored to defaults" % [c["a"], c["b"], c["key"], scheme_b])
		fresh.reset_defaults(scheme_b)
	if not fresh.find_conflicts().is_empty():  # a repaired set can still clash with the other player's set
		warnings.append("keyboard sets still clash after repair: both restored to defaults")
		fresh.reset_defaults("kb1")
		fresh.reset_defaults("kb2")
	fresh.pad_settings = settings_kept
	keys = fresh.keys
	pad = fresh.pad
	pad_settings = fresh.pad_settings
	seat_prefs = fresh.seat_prefs
	changed.emit()
	return true


func _fix_setting(name: String, value: Variant) -> Variant:
	var default: Variant = DEFAULT_PAD_SETTINGS[name]
	if default is bool:
		return value if value is bool else null
	if not (value is float or value is int) or is_nan(float(value)) or is_inf(float(value)):
		return null
	var range: Array = PAD_SETTING_RANGES.get(name, [0.0, 1.0])
	return clampf(float(value), float(range[0]), float(range[1]))


func _repair_trigger_thresholds() -> void:
	var press := float(pad_settings["trigger_press"])
	var release := float(pad_settings["trigger_release"])
	if release > press - 0.05:
		pad_settings["trigger_release"] = maxf(0.05, press - 0.15)
	var deadzone := float(pad_settings["deadzone"])
	if float(pad_settings["outer_deadzone"]) < deadzone + 0.05:
		pad_settings["outer_deadzone"] = minf(1.0, deadzone + 0.1)
