extends Node
## Protocol/lifecycle fixture only. No combat, fighters, controls, damage or winner logic.
signal combat_snapshot(snapshot: Dictionary)
signal battle_finished(result: Dictionary)
var request: Dictionary = {}
var running = false
func start_battle(value: Dictionary) -> Dictionary:
	request = value.duplicate(true)
	running = true
	return {"ok": true}
func stop_battle() -> void:
	running = false
