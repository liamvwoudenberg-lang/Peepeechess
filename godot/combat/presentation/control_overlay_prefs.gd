class_name ControlOverlayPrefs
extends RefCounted
## Persistent choice for the in-battle controls overlay (ControlOverlay).
##
## * `enabled`   the player's last choice (true until they switch the overlay off).
## * `chosen`    true once the player has toggled it themselves (F1 / Share / '?' / the chip / the settings checkbox).
## * `battles`   how many battles this profile has started (counted when a battle with a local human seat begins).
##
## Default for a fresh profile: ON. A profile that never touched the toggle sees the full cheat sheet for its first
## FREE_BATTLES battles and then only the small "F1 Controls" hint chip (the sheet is one key away). As soon as the
## player toggles, that choice is honoured from the next battle on: off stays off, on stays on.
##
## Stored in user://control_overlay.json (versioned; written atomically; a corrupt, hostile or oversized file is moved to
## `.corrupt` and defaults load - it never raises an engine error). Not an autoload: `shared()` is a lazily created
## process-wide instance. Tests give private instances (`autosave = false`, or a temp `path`).

signal changed

const VERSION := 1
const DEFAULT_PATH := "user://control_overlay.json"
## Battles during which the full sheet is shown to a profile that never chose.
const FREE_BATTLES := 3
const MAX_BYTES := 4096

enum Start { OFF, FULL, MINIMISED }

var enabled: bool = true
var chosen: bool = false
var battles: int = 0
var path: String = DEFAULT_PATH
## false = never touch the disk (tests, automation).
var autosave: bool = true
var last_error: String = ""

static var _shared: ControlOverlayPrefs = null


static func shared() -> ControlOverlayPrefs:
	if _shared == null:
		_shared = ControlOverlayPrefs.new()
		_shared.load_file()
	return _shared


## Tests replace the shared instance (null = lazily reload from disk next time).
static func set_shared(value: ControlOverlayPrefs) -> void:
	_shared = value


func reset_defaults() -> void:
	enabled = true
	chosen = false
	battles = 0


## What the overlay does at the start of the next battle (does not count it).
func start_mode() -> int:
	if not enabled:
		return Start.OFF
	if chosen or battles < FREE_BATTLES:
		return Start.FULL
	return Start.MINIMISED


## Called once when a battle with a local human seat begins. Counts it and returns the Start mode that applies to it.
func begin_battle() -> int:
	var mode := start_mode()
	battles = mini(battles + 1, 1000000)
	_commit()
	return mode


## The player's explicit choice (any of the toggles). Remembered from now on.
func set_enabled(value: bool) -> void:
	if enabled == value and chosen:
		return
	enabled = value
	chosen = true
	_commit()


func _commit() -> void:
	changed.emit()
	if autosave:
		save_file()


# ---- persistence ----------------------------------------------------------------------------------------
func to_dict() -> Dictionary:
	return {"version": VERSION, "enabled": enabled, "chosen": chosen, "battles": battles}


func save_file(p: String = "") -> Error:
	var target := p if not p.is_empty() else path
	var tmp := target + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		last_error = "could not write %s (error %d)" % [tmp, FileAccess.get_open_error()]
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_dict()))
	file.close()
	var dir := DirAccess.open(target.get_base_dir())
	if dir == null:
		last_error = "could not open " + target.get_base_dir()
		return ERR_CANT_OPEN
	if dir.file_exists(target.get_file()):
		dir.remove(target.get_file())
	var err := dir.rename(tmp.get_file(), target.get_file())
	if err != OK:
		last_error = "could not replace %s (error %d)" % [target, err]
	return err


## A missing file is not an error (defaults). A corrupt one loads defaults and is copied to `<path>.corrupt`.
## Returns true if a valid file was read.
func load_file(p: String = "") -> bool:
	var source := p if not p.is_empty() else path
	last_error = ""
	if not FileAccess.file_exists(source):
		reset_defaults()
		return false
	var text := FileAccess.get_file_as_string(source)
	var parsed: Variant = null
	if text.length() <= MAX_BYTES:
		var json := JSON.new()  # JSON.parse_string would print an engine ERROR line for a corrupt file
		if json.parse(text) == OK:
			parsed = json.data
	if parsed is Dictionary and from_dict(parsed):
		return true
	_quarantine(source, last_error if not last_error.is_empty() else "overlay preferences are not valid")
	reset_defaults()
	return false


func from_dict(data: Dictionary) -> bool:
	var v: Variant = data.get("version")
	if not (v is float or v is int) or int(v) != VERSION:
		last_error = "unsupported overlay preferences version"
		return false
	var e: Variant = data.get("enabled")
	var c: Variant = data.get("chosen")
	var b: Variant = data.get("battles")
	if not (e is bool) or not (c is bool) or not (b is float or b is int):
		last_error = "overlay preferences have the wrong field types"
		return false
	var count := float(b)
	if is_nan(count) or is_inf(count) or count < 0.0 or count > 1000000.0 or count != floorf(count):
		last_error = "overlay preference battle count out of range"
		return false
	enabled = e
	chosen = c
	battles = int(count)
	changed.emit()
	return true


func _quarantine(source: String, why: String) -> void:
	last_error = why
	var dir := DirAccess.open(source.get_base_dir())
	if dir != null:
		var bad := source.get_file() + ".corrupt"
		if dir.file_exists(bad):
			dir.remove(bad)
		dir.rename(source.get_file(), bad)
