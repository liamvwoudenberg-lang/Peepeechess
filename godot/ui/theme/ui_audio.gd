extends RefCounted
## Thin hook that gives every button of a screen the combat layer's hover / click / confirm / back sounds
## (res://combat/audio/combat_audio.gd: attach_ui) and applies the user's UI-sound preference.
## Presentation only. Disabled in headless runs (no audio device, and it keeps tests free of cached streams)
## unless `force` is set by a test that cleans up with shutdown().
const CombatAudio = preload("res://combat/audio/combat_audio.gd")
const Prefs = preload("res://ui/theme/ui_prefs.gd")
const NODE_NAME := "UiAudio"
static var force := false

static func available() -> bool:
	return force or DisplayServer.get_name() != "headless"

## Adds (once) a CombatAudio node under `host` and hooks all of host's buttons. Returns the node or null.
static func attach(host: Node, owner_node: Node = null) -> Node:
	if host == null or not available():
		return null
	var holder := owner_node if owner_node != null else host
	var audio := holder.get_node_or_null(NODE_NAME)
	if audio == null:
		audio = CombatAudio.new()
		audio.name = NODE_NAME
		holder.add_child(audio)
	audio.set_muted(not Prefs.ui_sounds)
	audio.attach_ui(host)
	return audio

static func set_enabled(host: Node, on: bool) -> void:
	Prefs.ui_sounds = on
	if host != null:
		var audio := host.find_child(NODE_NAME, true, false)
		if audio != null:
			audio.set_muted(not on)

## Drops decoded streams cached in static storage (call before quitting a test).
static func shutdown() -> void:
	CombatAudio.clear_library()
