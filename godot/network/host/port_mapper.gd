class_name PortMapper
extends Node
## Opens one UDP port on the host's router so friends can reach the game. This base class is the interface (and the "no router help" fallback);
## UpnpPortMapper does the real work and FakePortMapper (tests) answers from a script.
## `start(port)` returns at once; `finished` fires once with {ok, external_ip, message, private_external}.
signal finished(result: Dictionary)
var mapped_port = 0
var result: Dictionary = {}

func start(_port: int) -> void:
	_finish({"ok": false, "external_ip": "", "message": "Automatic port opening is not available.", "private_external": false})

## Removes the mapping again. Safe to call twice.
func stop() -> void:
	mapped_port = 0

func _finish(value: Dictionary) -> void:
	result = value
	finished.emit(value)

## True for addresses that are not reachable from the internet (private, shared CGNAT, link-local, loopback).
static func is_private_address(address: String) -> bool:
	if address.is_empty():
		return false
	if address.contains(":"):
		var lower = address.to_lower()
		return lower == "::1" or lower.begins_with("fe80") or lower.begins_with("fc") or lower.begins_with("fd")
	var parts = address.split(".")
	if parts.size() != 4:
		return false
	var a = int(parts[0])
	var b = int(parts[1])
	return a == 10 or a == 127 or (a == 172 and b >= 16 and b <= 31) or (a == 192 and b == 168) or (a == 169 and b == 254) or (a == 100 and b >= 64 and b <= 127)
