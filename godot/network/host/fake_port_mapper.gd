class_name FakePortMapper
extends PortMapper
## Test double for the router: answers with a scripted result and records start/stop calls.
var scripted: Dictionary = {"ok": true, "external_ip": "203.0.113.7", "message": "Port opened (fake).", "private_external": false}
var started_ports: Array = []
var stopped = 0

func start(port: int) -> void:
	started_ports.append(port)
	mapped_port = port if scripted.get("ok", false) else 0
	call_deferred("_finish", scripted)

func stop() -> void:
	if mapped_port > 0:
		stopped += 1
	mapped_port = 0
