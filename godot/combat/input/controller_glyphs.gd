class_name ControllerGlyphs
extends RefCounted
## Names for gamepad buttons that match what is printed on the player's controller.
##
## Godot reports every pad through the SDL game-controller layout: JOY_BUTTON_A is the bottom face button, B the
## right one, X the left one, Y the top one - on a DualShock 4 / DualSense those are Cross, Circle, Square and
## Triangle. The family is guessed from the device's reported name and GUID/vendor id. A DS4 that reaches Windows
## as an XInput pad (DS4Windows, Steam Input) reports an Xbox name and is therefore labelled as Xbox; that is
## correct for what the OS exposes (the physical labels differ, the positions do not).

enum Family { GENERIC, PLAYSTATION, XBOX, SWITCH }

const SONY_VENDOR := 0x054c
const MICROSOFT_VENDOR := 0x045e
const NINTENDO_VENDOR := 0x057e

const PLAYSTATION := {
	JOY_BUTTON_A: "Cross", JOY_BUTTON_B: "Circle", JOY_BUTTON_X: "Square", JOY_BUTTON_Y: "Triangle",
	JOY_BUTTON_LEFT_SHOULDER: "L1", JOY_BUTTON_RIGHT_SHOULDER: "R1", JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_START: "Options", JOY_BUTTON_BACK: "Share", JOY_BUTTON_GUIDE: "PS", JOY_BUTTON_MISC1: "Mic",
	JOY_BUTTON_TOUCHPAD: "Touchpad",
	JOY_BUTTON_DPAD_UP: "D-pad Up", JOY_BUTTON_DPAD_DOWN: "D-pad Down", JOY_BUTTON_DPAD_LEFT: "D-pad Left", JOY_BUTTON_DPAD_RIGHT: "D-pad Right",
}
const XBOX := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_LEFT_STICK: "LS", JOY_BUTTON_RIGHT_STICK: "RS",
	JOY_BUTTON_START: "Menu", JOY_BUTTON_BACK: "View", JOY_BUTTON_GUIDE: "Xbox", JOY_BUTTON_MISC1: "Share",
	JOY_BUTTON_TOUCHPAD: "Touchpad",
	JOY_BUTTON_DPAD_UP: "D-pad Up", JOY_BUTTON_DPAD_DOWN: "D-pad Down", JOY_BUTTON_DPAD_LEFT: "D-pad Left", JOY_BUTTON_DPAD_RIGHT: "D-pad Right",
}
## Nintendo prints A on the RIGHT button and B on the bottom one: Godot's A (bottom) is the Switch "B".
const SWITCH := {
	JOY_BUTTON_A: "B", JOY_BUTTON_B: "A", JOY_BUTTON_X: "Y", JOY_BUTTON_Y: "X",
	JOY_BUTTON_LEFT_SHOULDER: "L", JOY_BUTTON_RIGHT_SHOULDER: "R", JOY_BUTTON_LEFT_STICK: "L Stick", JOY_BUTTON_RIGHT_STICK: "R Stick",
	JOY_BUTTON_START: "+", JOY_BUTTON_BACK: "-", JOY_BUTTON_GUIDE: "Home", JOY_BUTTON_MISC1: "Capture",
	JOY_BUTTON_TOUCHPAD: "Touchpad",
	JOY_BUTTON_DPAD_UP: "D-pad Up", JOY_BUTTON_DPAD_DOWN: "D-pad Down", JOY_BUTTON_DPAD_LEFT: "D-pad Left", JOY_BUTTON_DPAD_RIGHT: "D-pad Right",
}
const TRIGGER_NAMES := {
	Family.PLAYSTATION: {JOY_AXIS_TRIGGER_LEFT: "L2", JOY_AXIS_TRIGGER_RIGHT: "R2"},
	Family.XBOX: {JOY_AXIS_TRIGGER_LEFT: "LT", JOY_AXIS_TRIGGER_RIGHT: "RT"},
	Family.SWITCH: {JOY_AXIS_TRIGGER_LEFT: "ZL", JOY_AXIS_TRIGGER_RIGHT: "ZR"},
	Family.GENERIC: {JOY_AXIS_TRIGGER_LEFT: "LT", JOY_AXIS_TRIGGER_RIGHT: "RT"},
}

## Test hook: device id -> {"name": String, "guid": String, "vendor": int} used instead of the real Input singleton.
static var fake_devices: Dictionary = {}


## Family from a device name (and optionally a GUID / vendor id). Name wins over vendor because XInput wrappers
## present Sony hardware as an Xbox pad and the OS-visible identity is what matters for labels.
static func family_from_name(joy_name: String, guid: String = "", vendor: int = 0) -> int:
	var n := joy_name.to_lower()
	if n.contains("xinput") or n.contains("xbox") or n.contains("x-box") or n.contains("microsoft"):
		return Family.XBOX
	if n.contains("dualshock") or n.contains("dualsense") or n.contains("ps4") or n.contains("ps5") or n.contains("ps3") \
			or n.contains("playstation") or n.contains("sony") or n.contains("wireless controller") or n.contains("ds4"):
		return Family.PLAYSTATION
	if n.contains("switch") or n.contains("nintendo") or n.contains("joy-con") or n.contains("joycon") or n.contains("pro controller"):
		return Family.SWITCH
	var id := vendor if vendor > 0 else vendor_from_guid(guid)
	match id:
		SONY_VENDOR:
			return Family.PLAYSTATION
		MICROSOFT_VENDOR:
			return Family.XBOX
		NINTENDO_VENDOR:
			return Family.SWITCH
	return Family.GENERIC


## SDL joystick GUID (32 hex chars): bytes 4..5 are the little-endian USB vendor id.
static func vendor_from_guid(guid: String) -> int:
	if guid.length() < 12 or not guid.is_valid_hex_number(false):
		return 0
	return ("0x" + guid.substr(10, 2) + guid.substr(8, 2)).hex_to_int()


static func family_of_device(device: int) -> int:
	if fake_devices.has(device):
		var f: Dictionary = fake_devices[device]
		return family_from_name(String(f.get("name", "")), String(f.get("guid", "")), int(f.get("vendor", 0)))
	var info: Dictionary = Input.get_joy_info(device) if Input.get_connected_joypads().has(device) else {}
	return family_from_name(Input.get_joy_name(device), Input.get_joy_guid(device), int(info.get("vendor_id", 0)))


static func family_name(family: int) -> String:
	match family:
		Family.PLAYSTATION:
			return "PlayStation"
		Family.XBOX:
			return "Xbox"
		Family.SWITCH:
			return "Switch"
	return "Gamepad"


static func device_label(device: int) -> String:
	var raw := String(fake_devices[device].get("name", "")) if fake_devices.has(device) else Input.get_joy_name(device)
	return raw if not raw.is_empty() else "Controller %d" % device


static func button_label(button: int, family: int) -> String:
	var table: Dictionary = PLAYSTATION if family == Family.PLAYSTATION else (SWITCH if family == Family.SWITCH else XBOX)
	return String(table.get(button, "Button %d" % button))


static func axis_label(axis: int, family: int) -> String:
	var names: Dictionary = TRIGGER_NAMES.get(family, TRIGGER_NAMES[Family.GENERIC])
	if names.has(axis):
		return String(names[axis])
	match axis:
		JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y:
			return "Left stick"
		JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y:
			return "Right stick"
	return "Axis %d" % axis


## `input` is a pad binding: {"type": "button"|"axis", "index": int}. Empty -> "Unbound".
static func input_label(input: Dictionary, family: int) -> String:
	if input.is_empty():
		return "Unbound"
	if String(input.get("type", "")) == "axis":
		return axis_label(int(input["index"]), family)
	return button_label(int(input["index"]), family)


## Label for the pad a given seat will use (device -1 -> PlayStation-less generic Xbox-style names).
static func input_label_for_device(input: Dictionary, device: int) -> String:
	return input_label(input, family_of_device(device) if device >= 0 else Family.XBOX)
