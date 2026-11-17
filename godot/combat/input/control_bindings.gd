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
const KEY_ACTIONS := ["up", "down", "left", "right", "sprint", "light", "heavy", "dodge", "block", "parry", "ability", "lock", "orbit_l", "orbit_r", "look_up", "look_down"]
## Actions that may carry a second (alternate) binding: a key, a mouse button or the wheel.
const ALT_ACTIONS := ["sprint", "light", "heavy", "dodge", "block", "parry", "ability", "lock"]
## Mouse buttons and the wheel are stored as NEGATIVE codes (-button_index) next to physical key codes, so one integer
## can name any keyboard-set input: key codes are > 0, mouse codes < 0, 0 = unbound. Only keyboard 1 can use the mouse.
const MOUSE_NAMES := {1: "LMB", 2: "RMB", 3: "MMB", 4: "Wheel up", 5: "Wheel down", 8: "Mouse 4", 9: "Mouse 5"}
## Control profiles (presets) a keyboard set can be switched to; "Reset" re-applies the active one.
##   classic      the original layout (WASD + F/G..., mouse LMB light / RMB heavy / MMB lock)
##   souls_mouse  one hand on WASD, the other on the mouse (Dark Souls style)
##   souls_keys   no mouse: left hand WASD + Shift/Space, right hand on I J K L U O P ; ' and Enter
##   duo_left / duo_right   two players on one keyboard (left half / right half), no mouse
## What a first-time player gets on keyboard 1 (tests build `ControlBindings.new()`, which stays classic).
const FIRST_RUN_PROFILE := "souls_mouse"
const PROFILE_IDS := ["classic", "souls_mouse", "souls_keys", "duo_left", "duo_right"]
const PROFILE_LABELS := {
	"classic": "Classic (WASD + mouse)", "souls_mouse": "Souls: keyboard + mouse", "souls_keys": "Souls: two hands, keyboard only",
	"duo_left": "Two players: left half", "duo_right": "Two players: right half",
}
## Which keyboard sets a profile can be applied to.
const PROFILE_SCHEMES := {"classic": ["kb1"], "souls_mouse": ["kb1"], "souls_keys": ["kb1"], "duo_left": ["kb1"], "duo_right": ["kb2"]}
## Per-keyboard-set options. mouse_* / look settings apply to the mouse and the camera keys.
const DEFAULT_OPTIONS := {
	"mouse_sensitivity": 1.0, "camera_sensitivity": 1.0, "invert_x": false, "invert_y": false,
	"hold_block": true,         # true = block while held; false = a press toggles block
	"heavy_on_hold": false,     # holding the light-attack input past heavy_hold_ms becomes a heavy attack (light then fires on release)
	"heavy_hold_ms": 200.0,
	"alt_heavy": false,         # Alt + the light-attack input = heavy attack
	"parry_on_tap": false,      # a quick tap of the block input also parries
	"parry_tap_ms": 160.0,
	"sprint_tap_dodge": false,  # a quick tap of the sprint input dodges; holding sprints
	"sprint_tap_ms": 200.0,
	"lock_hold": false,         # true = the lock-on input is hold-to-lock; false = a press toggles
}
const OPTION_RANGES := {"mouse_sensitivity": [0.2, 4.0], "camera_sensitivity": [0.2, 4.0], "heavy_hold_ms": [100.0, 600.0], "parry_tap_ms": [60.0, 400.0], "sprint_tap_ms": [80.0, 400.0]}
## Ergonomic rule used by tests and docs: which physical keys each hand rests on (a standard ANSI layout).
const LEFT_HAND_KEYS := [KEY_Q, KEY_W, KEY_E, KEY_R, KEY_T, KEY_A, KEY_S, KEY_D, KEY_F, KEY_G, KEY_Z, KEY_X, KEY_C, KEY_V, KEY_B, KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_SPACE, KEY_TAB, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5]
const RIGHT_HAND_KEYS := [KEY_Y, KEY_U, KEY_I, KEY_O, KEY_P, KEY_H, KEY_J, KEY_K, KEY_L, KEY_SEMICOLON, KEY_APOSTROPHE, KEY_N, KEY_M, KEY_COMMA, KEY_PERIOD, KEY_SLASH, KEY_ENTER, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_BRACKETLEFT, KEY_BRACKETRIGHT]
const PAD_ACTIONS := ["sprint", "light", "heavy", "heavy2", "dodge", "block", "parry", "ability", "lock"]
## Actions that are "held" (polled every tick) rather than one press per tap.
const HELD_ACTIONS := ["sprint", "block"]
const ACTION_LABELS := {
	"up": "Move forward", "down": "Move back", "left": "Move left", "right": "Move right",
	"sprint": "Sprint (hold)", "light": "Light attack", "heavy": "Heavy attack", "heavy2": "Heavy attack (alternate)",
	"dodge": "Dodge", "block": "Block (hold)", "parry": "Parry", "ability": "Special ability",
	"lock": "Lock-on / free camera", "orbit_l": "Camera left", "orbit_r": "Camera right", "look_up": "Camera tilt up", "look_down": "Camera tilt down",
}
const DEFAULT_KEYS := {
	"kb1": {"up": KEY_W, "down": KEY_S, "left": KEY_A, "right": KEY_D, "sprint": KEY_SHIFT, "light": KEY_F, "heavy": KEY_G,
		"dodge": KEY_SPACE, "block": KEY_Q, "parry": KEY_E, "ability": KEY_R, "lock": KEY_TAB, "orbit_l": KEY_Z, "orbit_r": KEY_X},
	"kb2": {"up": KEY_UP, "down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT, "sprint": KEY_CTRL, "light": KEY_J, "heavy": KEY_K,
		"dodge": KEY_L, "block": KEY_U, "parry": KEY_I, "ability": KEY_O, "lock": KEY_P, "orbit_l": KEY_COMMA, "orbit_r": KEY_PERIOD},
}
## Full key sets per profile ({action: code}), alternates and option overrides. Mouse codes are negative (see above).
## "classic" / "duo_left" / "duo_right" take their keys from DEFAULT_KEYS (the original constants).
const PROFILE_DATA := {
	"classic": {"keys": {}, "alts": {"light": -1, "heavy": -2, "lock": -3}, "options": {}},
	"duo_left": {"keys": {}, "alts": {}, "options": {}},
	"duo_right": {"keys": {}, "alts": {}, "options": {}},
	"souls_mouse": {
		"keys": {"up": KEY_W, "down": KEY_S, "left": KEY_A, "right": KEY_D, "sprint": KEY_SHIFT, "dodge": KEY_SPACE,
			"light": -1, "heavy": -9, "block": -2, "parry": KEY_F, "ability": KEY_R, "lock": -3, "orbit_l": KEY_Q, "orbit_r": KEY_E},
		"alts": {"ability": -8, "lock": KEY_X},
		"options": {"heavy_on_hold": true, "alt_heavy": true, "parry_on_tap": true, "sprint_tap_dodge": true},
	},
	"souls_keys": {
		"keys": {"up": KEY_W, "down": KEY_S, "left": KEY_A, "right": KEY_D, "sprint": KEY_SHIFT, "dodge": KEY_SPACE,
			"light": KEY_U, "heavy": KEY_O, "block": KEY_P, "parry": KEY_SEMICOLON, "ability": KEY_APOSTROPHE, "lock": KEY_ENTER,
			"orbit_l": KEY_J, "orbit_r": KEY_L, "look_up": KEY_I, "look_down": KEY_K},
		"alts": {},
		"options": {"sprint_tap_dodge": true},
	},
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
## Keys that menus own; they cannot be combat bindings (Esc cancels / leaves, F11 toggles fullscreen, F1 toggles the
## battle controls overlay - see combat/presentation/control_overlay.gd).
const RESERVED_KEYS := [KEY_ESCAPE, KEY_F11, KEY_F1]
## Options/Start opens menus and pauses, Share/Back (JOY_BUTTON_BACK) toggles the controls overlay; neither can be rebound.
const RESERVED_PAD_BUTTONS := [JOY_BUTTON_START, JOY_BUTTON_BACK]
const BINDABLE_AXES := [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]

var keys: Dictionary = {}
## Alternate binding per keyboard set: {"kb1": {"light": -1, ...}} (keys > 0, mouse < 0; absent / 0 = none).
var alts: Dictionary = {"kb1": {}, "kb2": {}}
## Active profile id per keyboard set and its tunables (see DEFAULT_OPTIONS).
var profiles: Dictionary = {"kb1": "classic", "kb2": "duo_right"}
var options: Dictionary = {}
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
		if not _shared.load_file():
			_shared.apply_profile("kb1", FIRST_RUN_PROFILE)   # no (usable) saved controls: new players get the Souls layout
	return _shared


## Tests replace the shared instance (null = lazily reload from disk next time).
static func set_shared(value: ControlBindings) -> void:
	_shared = value


# ---- defaults / lookup ----------------------------------------------------------------------------
func reset_defaults(scope: String = "all") -> void:
	if scope == "all" or scope == "kb1":
		_install_profile("kb1", "classic")
	if scope == "all" or scope == "kb2":
		_install_profile("kb2", "duo_right")
	if scope == "all" or scope == "pad":
		pad = DEFAULT_PAD.duplicate(true)
		pad_settings = DEFAULT_PAD_SETTINGS.duplicate(true)
	if scope == "all":
		seat_prefs = {"p1": "auto", "p2": "auto"}
	changed.emit()


func is_default() -> bool:
	return keys == DEFAULT_KEYS and alts == {"kb1": PROFILE_DATA["classic"]["alts"], "kb2": {}} and profiles == {"kb1": "classic", "kb2": "duo_right"} \
			and options == {"kb1": DEFAULT_OPTIONS, "kb2": DEFAULT_OPTIONS} and pad == DEFAULT_PAD and pad_settings == DEFAULT_PAD_SETTINGS and seat_prefs == {"p1": "auto", "p2": "auto"}


func keys_for(scheme: String) -> Dictionary:
	return keys.get(scheme, {})


func key_for(scheme: String, action: String) -> int:
	return int(keys.get(scheme, {}).get(action, KEY_NONE))


## {"type": "button"|"axis", "index": int} or {} when unbound.
func pad_input(action: String) -> Dictionary:
	return pad.get(action, {})


func pad_setting(name: String) -> Variant:
	return pad_settings.get(name, DEFAULT_PAD_SETTINGS.get(name))


# ---- profiles, alternates, options ----------------------------------------------------------------------
## Profile ids that can be applied to `scheme`.
static func profiles_for(scheme: String) -> Array:
	var out: Array = []
	for id in PROFILE_IDS:
		if scheme in PROFILE_SCHEMES[id]:
			out.append(id)
	return out


func profile_of(scheme: String) -> String:
	return String(profiles.get(scheme, "classic"))


## True when the profile of `scheme` reads the mouse (any mouse code bound, or the classic mouse alternates).
func uses_mouse(scheme: String) -> bool:
	if scheme != "kb1":
		return false
	for action in KEY_ACTIONS:
		if key_for(scheme, action) < 0 or alt_for(scheme, action) < 0:
			return true
	return false


func _profile_keys(scheme: String, id: String) -> Dictionary:
	var data: Dictionary = PROFILE_DATA[id]
	if (data["keys"] as Dictionary).is_empty():
		return DEFAULT_KEYS["kb2" if id == "duo_right" else "kb1"].duplicate()
	var out: Dictionary = {}
	for action in KEY_ACTIONS:
		if (data["keys"] as Dictionary).has(action):
			out[action] = int(data["keys"][action])
	return out


func _install_profile(scheme: String, id: String) -> void:
	keys[scheme] = _profile_keys(scheme, id)
	alts[scheme] = (PROFILE_DATA[id]["alts"] as Dictionary).duplicate() if scheme == "kb1" else {}
	var opt: Dictionary = DEFAULT_OPTIONS.duplicate()
	opt.merge(PROFILE_DATA[id]["options"], true)
	options[scheme] = opt
	profiles[scheme] = id


## Switches a keyboard set to a profile. Returns {"ok", "cleared": [{"scheme","action"}]}: keys of the OTHER keyboard set that clash
## with the new layout are unbound (a key never belongs to two seats). Applying a profile also resets the set's options.
func apply_profile(scheme: String, id: String) -> Dictionary:
	if not (scheme in SCHEMES) or not (id in PROFILE_IDS) or not (scheme in PROFILE_SCHEMES[id]):
		return {"ok": false, "cleared": []}
	_install_profile(scheme, id)
	var cleared: Array = []
	var other := "kb2" if scheme == "kb1" else "kb1"
	var mine: Dictionary = {}
	for action in KEY_ACTIONS:
		for code in [key_for(scheme, action), alt_for(scheme, action)]:
			if code > 0:
				mine[code] = true
	for action in KEY_ACTIONS:
		if key_for(other, action) > 0 and mine.has(key_for(other, action)):
			keys[other][action] = KEY_NONE
			cleared.append({"scheme": other, "action": action})
		if alts[other].has(action) and mine.has(int(alts[other][action])):
			alts[other].erase(action)
	changed.emit()
	return {"ok": true, "cleared": cleared}


## "Reset to default scheme": re-applies the active profile of `scheme`.
func reset_scheme(scheme: String) -> void:
	apply_profile(scheme, profile_of(scheme))


func alt_for(scheme: String, action: String) -> int:
	return int(alts.get(scheme, {}).get(action, KEY_NONE))


func option(scheme: String, name: String) -> Variant:
	return options.get(scheme, DEFAULT_OPTIONS).get(name, DEFAULT_OPTIONS.get(name))


func set_option(scheme: String, name: String, value: Variant) -> bool:
	if not DEFAULT_OPTIONS.has(name) or not options.has(scheme):
		return false
	var fixed: Variant = _fix_option(name, value)
	if fixed == null:
		return false
	options[scheme][name] = fixed
	changed.emit()
	return true


static func _fix_option(name: String, value: Variant) -> Variant:
	var default: Variant = DEFAULT_OPTIONS[name]
	if default is bool:
		return value if value is bool else null
	if not (value is float or value is int) or is_nan(float(value)) or is_inf(float(value)):
		return null
	var range: Array = OPTION_RANGES.get(name, [0.0, 1.0])
	return clampf(float(value), float(range[0]), float(range[1]))


## Actions bound (primary or alternate) to `code` on `scheme`.
func actions_for(scheme: String, code: int) -> Array:
	var out: Array = []
	if code == 0:
		return out
	for action in KEY_ACTIONS:
		if key_for(scheme, action) == code or alt_for(scheme, action) == code:
			out.append(action)
	return out


## True if `action` is currently held on `scheme`: a physical key, or a mouse button (only while `mouse_live`).
func is_held(scheme: String, action: String, mouse_live: bool = true) -> bool:
	for code in [key_for(scheme, action), alt_for(scheme, action)]:
		if code > 0 and Input.is_physical_key_pressed(code as Key):
			return true
		if code < 0 and mouse_live and -code in MOUSE_NAMES and not (-code in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]) \
				and Input.is_mouse_button_pressed((-code) as MouseButton):
			return true
	return false


static func is_mouse_code(code: int) -> bool:
	return code < 0


# ---- editing ----------------------------------------------------------------------------------------
## Binds `code` (a physical key > 0, a mouse button < 0 for keyboard 1, or 0 = unbound) to `action` of `scheme`. `conflict` decides
## what happens if another action (in this set or in the other player's keyboard set) already uses that input:
##   "swap"   the other action receives this action's old input (a same-set swap; a cross-set clash is refused)
##   "reject" nothing changes
##   "allow"  duplicate allowed (find_conflicts() will still report it)
## Returns {"ok": bool, "conflicts": [{"scheme","action","slot"}], "reason": String, "swapped": bool}.
func set_key(scheme: String, action: String, keycode: int, conflict: String = "swap") -> Dictionary:
	return _assign(scheme, action, "primary", keycode, conflict)


## Same for the alternate slot of `action` (ALT_ACTIONS only); 0 clears it.
func set_alt(scheme: String, action: String, code: int, conflict: String = "swap") -> Dictionary:
	if not (action in ALT_ACTIONS):
		return _fail("%s has no alternate binding" % action)
	return _assign(scheme, action, "alt", code, conflict)


func _slot_code(scheme: String, action: String, slot: String) -> int:
	return key_for(scheme, action) if slot == "primary" else alt_for(scheme, action)


func _write_slot(scheme: String, action: String, slot: String, code: int) -> void:
	if slot == "primary":
		keys[scheme][action] = code
	elif code == 0:
		alts[scheme].erase(action)
	else:
		alts[scheme][action] = code


func _assign(scheme: String, action: String, slot: String, keycode: int, conflict: String) -> Dictionary:
	if not keys.has(scheme) or not (action in KEY_ACTIONS):
		return _fail("unknown binding %s/%s" % [scheme, action])
	if keycode in RESERVED_KEYS:
		return _fail("that key is reserved for menus")
	if keycode < 0:
		if scheme != "kb1":
			return _fail("the mouse belongs to keyboard 1")
		if not (-keycode in MOUSE_NAMES) or not (action in ALT_ACTIONS):
			return _fail("the mouse can only trigger combat actions, not movement or camera keys")
	var clashes := _key_clashes(scheme, action, slot, keycode)
	if not clashes.is_empty() and conflict != "allow":
		if conflict == "reject":
			return {"ok": false, "conflicts": clashes, "reason": "already used", "swapped": false}
		for clash in clashes:
			if clash["scheme"] != scheme:
				return {"ok": false, "conflicts": clashes, "reason": "already used by the other player's keyboard set", "swapped": false}
		var old := _slot_code(scheme, action, slot)
		for clash in clashes:
			if old < 0 and not (String(clash["action"]) in ALT_ACTIONS):
				return {"ok": false, "conflicts": clashes, "reason": "the swap would put the mouse on a movement key", "swapped": false}
			_write_slot(scheme, String(clash["action"]), String(clash["slot"]), old)
		_write_slot(scheme, action, slot, keycode)
		changed.emit()
		return {"ok": true, "conflicts": clashes, "reason": "", "swapped": true}
	_write_slot(scheme, action, slot, keycode)
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


## Every duplicate binding as {"a": "kb1/light", "b": "kb1/heavy", "key": name}; empty = conflict free. Unbound (0) never clashes.
func find_conflicts() -> Array:
	var out: Array = []
	var seen: Dictionary = {}  # code -> "scheme/action"
	for scheme in SCHEMES:
		for action in KEY_ACTIONS:
			for slot in ["primary", "alt"]:
				var code := _slot_code(scheme, action, slot)
				if code == 0:
					continue
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


func _key_clashes(scheme: String, action: String, slot: String, keycode: int) -> Array:
	var out: Array = []
	if keycode == 0:
		return out
	for s in SCHEMES:
		for other in KEY_ACTIONS:
			for other_slot in ["primary", "alt"]:
				if (s != scheme or other != action or other_slot != slot) and _slot_code(s, other, other_slot) == keycode:
					out.append({"scheme": s, "action": other, "slot": other_slot})
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


## A pressed key (> 0) or mouse button / wheel notch (< 0) for the rebinding capture; 0 for everything else.
static func event_to_binding(event: InputEvent) -> int:
	var code := event_to_key(event)
	if code != KEY_NONE:
		return code
	if event is InputEventMouseButton and event.pressed and int(event.button_index) in MOUSE_NAMES:
		return -int(event.button_index)
	return 0


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
	if code < 0:
		return String(MOUSE_NAMES.get(-code, "Mouse %d" % -code))
	if code == 0:
		return "Unbound"
	# Show what is printed on the player's keycap (AZERTY: physical W is "Z"); fall back to the code's name.
	var shown: int = DisplayServer.keyboard_get_keycode_from_physical(code as Key) if DisplayServer.get_name() != "headless" else code
	var short := {KEY_COMMA: ",", KEY_PERIOD: ".", KEY_SLASH: "/", KEY_BACKSLASH: "\\", KEY_SEMICOLON: ";", KEY_APOSTROPHE: "'", KEY_BRACKETLEFT: "[", KEY_BRACKETRIGHT: "]",
		KEY_MINUS: "-", KEY_EQUAL: "=", KEY_QUOTELEFT: "`"}
	if short.has(shown if shown != KEY_NONE else code):
		return short[shown if shown != KEY_NONE else code]
	var name := OS.get_keycode_string(shown if shown != KEY_NONE else code)
	return name if not name.is_empty() else "Key %d" % code


## All inputs bound to `action` ("LMB / F"), mouse inputs first, skipping unbound slots; "Unbound" if none.
func binding_names(scheme: String, action: String, sep: String = " / ", mouse_live: bool = true) -> String:
	var parts: Array = []
	for code in [key_for(scheme, action), alt_for(scheme, action)]:
		if code != 0 and (code > 0 or mouse_live):
			parts.append(key_name(code))
	parts.sort_custom(func(a, b): return _mouse_first(a) < _mouse_first(b))
	return sep.join(parts) if not parts.is_empty() else "Unbound"


static func _mouse_first(name: String) -> int:
	return 0 if name in MOUSE_NAMES.values() else 1


func action_binding_text(scheme: String, action: String, device: int = -1) -> String:
	if scheme in SCHEMES:
		return binding_names(scheme, action, " / ")
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
	if profile_of(scheme) in ["souls_mouse", "souls_keys"]:
		return _souls_hint(scheme)
	var k: Dictionary = keys_for(scheme)
	var n := func(a: String) -> String: return key_name(int(k.get(a, KEY_NONE)))
	var move := ""
	if scheme == "kb2" and k.get("up") == KEY_UP and k.get("down") == KEY_DOWN and k.get("left") == KEY_LEFT and k.get("right") == KEY_RIGHT:
		move = "Arrows"
	elif k.get("up") == KEY_W and k.get("left") == KEY_A and k.get("down") == KEY_S and k.get("right") == KEY_D:
		move = "WASD"
	else:
		move = "%s/%s/%s/%s" % [n.call("up"), n.call("left"), n.call("down"), n.call("right")]
	var mouse_on := scheme == "kb1" and uses_mouse(scheme)
	var light: String = ("LMB/" if mouse_on else "") + n.call("light")
	var heavy: String = ("RMB/" if mouse_on else "") + n.call("heavy")
	var cam: String = ("mouse or " if mouse_on else "") + "%s / %s" % [n.call("orbit_l"), n.call("orbit_r")]
	return "%s move · %s sprint · %s light · %s heavy · %s hold block · %s parry · %s dodge · %s ability · %s lock-on · %s camera" % [
		move, n.call("sprint"), light, heavy, n.call("block"), n.call("parry"), n.call("dodge"), n.call("ability"), n.call("lock"), cam]


## Movement keys as a short label: "WASD", "Arrows" or the four key names.
func move_label(scheme: String) -> String:
	var k: Dictionary = keys_for(scheme)
	if k.get("up") == KEY_W and k.get("left") == KEY_A and k.get("down") == KEY_S and k.get("right") == KEY_D:
		return "WASD"
	if k.get("up") == KEY_UP and k.get("down") == KEY_DOWN and k.get("left") == KEY_LEFT and k.get("right") == KEY_RIGHT:
		return "Arrows"
	return "%s/%s/%s/%s" % [key_name(key_for(scheme, "up")), key_name(key_for(scheme, "left")), key_name(key_for(scheme, "down")), key_name(key_for(scheme, "right"))]


## Camera control label: the mouse (when bound anywhere) plus the orbit / look keys.
func camera_label(scheme: String) -> String:
	var keys_part := "%s / %s" % [key_name(key_for(scheme, "orbit_l")), key_name(key_for(scheme, "orbit_r"))]
	if key_for(scheme, "look_up") != 0:
		keys_part += " (+ %s / %s tilt)" % [key_name(key_for(scheme, "look_up")), key_name(key_for(scheme, "look_down"))]
	return ("mouse or " if uses_mouse(scheme) else "") + keys_part


## One-line modifier notes for an action under the scheme's options ("hold: heavy", "tap: parry" ...); "" when none.
func modifier_note(scheme: String, action: String) -> String:
	match action:
		"light":
			var parts: Array = []
			if bool(option(scheme, "heavy_on_hold")):
				parts.append("hold: heavy")
			if bool(option(scheme, "alt_heavy")):
				parts.append("Alt+: heavy")
			return ", ".join(parts)
		"block":
			var note := "" if bool(option(scheme, "hold_block")) else "press to toggle"
			if bool(option(scheme, "parry_on_tap")):
				note = (note + ", " if not note.is_empty() else "") + "tap: parry"
			return note
		"sprint":
			return "tap: dodge" if bool(option(scheme, "sprint_tap_dodge")) else ""
		"lock":
			return "hold: free camera" if bool(option(scheme, "lock_hold")) else ""
	return ""


func _souls_hint(scheme: String) -> String:
	var part := func(label: String, action: String) -> String:
		var note := modifier_note(scheme, action)
		return "%s %s%s" % [binding_names(scheme, action, "/"), label, " (%s)" % note if not note.is_empty() else ""]
	return "%s move · %s · %s · %s · %s · %s · %s · %s · %s lock-on · %s camera" % [
		move_label(scheme), part.call("sprint", "sprint"), part.call("light", "light"), part.call("heavy", "heavy"), part.call("block", "block"),
		part.call("parry", "parry"), part.call("dodge", "dodge"), part.call("ability", "ability"), binding_names(scheme, "lock", "/"), camera_label(scheme)]


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
	var kb_out: Dictionary = {}
	var alt_out: Dictionary = {}
	for scheme in SCHEMES:
		kb_out[scheme] = {}
		for action in KEY_ACTIONS:
			if keys[scheme].has(action):
				kb_out[scheme][action] = _code_to_file(int(keys[scheme][action]), true)
		alt_out[scheme] = {}
		for action in alts[scheme]:
			alt_out[scheme][action] = _code_to_file(int(alts[scheme][action]), false)
	return {"version": VERSION, "keyboard": kb_out, "alts": alt_out, "profiles": profiles.duplicate(), "options": options.duplicate(true),
		"pad": pad_out, "pad_settings": pad_settings.duplicate(true), "assignment": seat_prefs.duplicate()}


## File form of a binding: a key code stays an int (old files stay valid), a mouse input is "mouse:N", unbound is "none".
static func _code_to_file(code: int, _primary: bool) -> Variant:
	if code < 0:
		return "mouse:%d" % -code
	if code == 0:
		return "none"
	return code


## Parses a file value into a binding code; returns null when invalid. Unbound ("none") is 0.
static func _code_from_file(value: Variant, scheme: String, action: String, allow_unbound: bool) -> Variant:
	if value is String:
		if value == "none":
			return 0 if allow_unbound else null
		if value.begins_with("mouse:") and value.substr(6).is_valid_int():
			var button := int(value.substr(6))
			if scheme == "kb1" and button in MOUSE_NAMES and action in ALT_ACTIONS:
				return -button
		return null
	if (value is float or value is int) and int(value) > 0 and int(value) < 0x7fffffff and not (int(value) in RESERVED_KEYS) and float(value) == float(int(value)):
		return int(value)
	return null


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
	var prof: Variant = data.get("profiles", {})
	for scheme in SCHEMES:
		var wanted: Variant = prof.get(scheme) if prof is Dictionary else null
		if wanted is String and wanted in PROFILE_IDS and scheme in PROFILE_SCHEMES[wanted]:
			fresh._install_profile(scheme, wanted)
		elif prof is Dictionary and prof.has(scheme):
			warnings.append("profiles/%s invalid; default restored" % scheme)
	var kb: Variant = data.get("keyboard", {})
	for scheme in SCHEMES:
		var section: Variant = kb.get(scheme, {}) if kb is Dictionary else {}
		for action in KEY_ACTIONS:
			if not (section is Dictionary) or not section.has(action):
				continue
			var parsed_key: Variant = _code_from_file(section[action], scheme, action, true)
			if parsed_key != null:
				fresh.keys[scheme][action] = int(parsed_key)
			else:
				warnings.append("%s/%s invalid; default restored" % [scheme, action])
	var alt_data: Variant = data.get("alts", {})
	for scheme in SCHEMES:
		var alt_section: Variant = alt_data.get(scheme) if alt_data is Dictionary else null
		if alt_section is Dictionary:
			fresh.alts[scheme] = {}
			for action in ALT_ACTIONS:
				if alt_section.has(action):
					var parsed_alt: Variant = _code_from_file(alt_section[action], scheme, action, true)
					if parsed_alt == null:
						warnings.append("alts/%s/%s invalid; none used" % [scheme, action])
					elif int(parsed_alt) != 0:
						fresh.alts[scheme][action] = int(parsed_alt)
	var opt_data: Variant = data.get("options", {})
	for scheme in SCHEMES:
		var opt_section: Variant = opt_data.get(scheme) if opt_data is Dictionary else null
		if opt_section is Dictionary:
			for name in DEFAULT_OPTIONS:
				if opt_section.has(name):
					var fixed_opt: Variant = _fix_option(name, opt_section[name])
					if fixed_opt == null:
						warnings.append("options/%s/%s invalid; default restored" % [scheme, name])
					else:
						fresh.options[scheme][name] = fixed_opt
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
	alts = fresh.alts
	profiles = fresh.profiles
	options = fresh.options
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
