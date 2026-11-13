extends RefCounted
## Full screen support for the desktop build: "windowed" or "fullscreen" (Window.MODE_FULLSCREEN, a borderless window
## that covers the screen; it behaves well with the Compatibility renderer and alt-tab, unlike exclusive full screen).
##
## Nothing here touches the simulation. The stored choice lives in ApplicationSettings (user://preferences.cfg, key
## presentation/display); this file only knows how to apply it and how to recognise the shortcut:
##   * F11 or Alt+Enter toggle it anywhere (menus, board, duels). Esc is never used, F1 stays the controls overlay;
##     F11 is also listed in combat/input/control_bindings.gd RESERVED_KEYS so it cannot be bound as a combat key.
##   * It is a no-op where a window cannot change mode: headless runs (tests, the dedicated server), Android/iOS
##     (always full screen) and the web export. `available()` says so, and the Settings page hides the control then.
##
## Test hooks (production leaves them untouched): `backend_set` / `backend_get` replace the DisplayServer calls and
## `available_override` forces availability, so the whole flow is testable without a window.
const WINDOWED := "windowed"
const FULLSCREEN := "fullscreen"
const MODES := [WINDOWED, FULLSCREEN]

static var backend_set: Callable      # (mode: String) -> void
static var backend_get: Callable      # () -> String
static var available_override := -1   # -1 detect, 0 unavailable, 1 available
## Set by ApplicationSettings: called with the target mode when the shortcut toggles, so the choice is persisted.
static var toggle_handler: Callable
static var _watchers: Array[Callable] = []


static func available() -> bool:
	if available_override >= 0:
		return available_override == 1
	return OS.has_feature("pc") and DisplayServer.get_name() != "headless"


## Strict: anything that is not exactly a known mode (wrong case, a number, "exclusive"...) is windowed.
static func normalise(value: Variant) -> String:
	var text := str(value)
	return text if text in MODES else WINDOWED


## The mode the window is really in (the OS can change it too: a maximise button, a window manager shortcut).
static func current() -> String:
	if backend_get.is_valid():
		return normalise(backend_get.call())
	if not available():
		return WINDOWED
	var mode := DisplayServer.window_get_mode()
	return FULLSCREEN if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN else WINDOWED


## Puts the window into `mode`. Returns false (and does nothing) where that is not possible.
static func apply(mode: String) -> bool:
	if not available():
		return false
	mode = normalise(mode)
	if backend_set.is_valid():
		backend_set.call(mode)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if mode == FULLSCREEN else DisplayServer.WINDOW_MODE_WINDOWED)
	_notify(mode)
	return true


## F11, or Alt+Enter. Plain key presses only: no auto-repeat, no key release, and F11 with Ctrl/Alt/Meta is left to the OS.
static func is_toggle_event(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return false
	var code: Key = key.keycode if key.keycode != KEY_NONE else key.physical_keycode
	if code == KEY_F11:
		return not (key.ctrl_pressed or key.alt_pressed or key.meta_pressed)
	if code == KEY_ENTER or code == KEY_KP_ENTER:
		return key.alt_pressed and not (key.ctrl_pressed or key.meta_pressed)
	return false


## Switches to the other mode. Returns false where the window cannot change mode (the key is then not consumed).
static func toggle() -> bool:
	if not available():
		return false
	var target := WINDOWED if current() == FULLSCREEN else FULLSCREEN
	if toggle_handler.is_valid():
		toggle_handler.call(target)
	else:
		apply(target)
	return true


## `callback(mode: String)` runs after every successful apply(), so an open Settings page can follow F11.
static func watch(callback: Callable) -> void:
	if not _watchers.has(callback):
		_watchers.append(callback)


static func unwatch(callback: Callable) -> void:
	_watchers.erase(callback)


static func _notify(mode: String) -> void:
	for callback in _watchers.duplicate():
		if callback.is_valid():
			callback.call(mode)
		else:
			_watchers.erase(callback)
