extends RefCounted
## Deterministic hash of the authoritative gameplay state in a CombatSnapshot (tick, countdown, every fighter field, the result), without the
## event history (which is repeated across snapshots and may legitimately differ). Two snapshots of the same server tick are the same state
## exactly when their hashes are equal. Used by the network report to check, snapshot by snapshot, that what a client applied is what the
## server had at that tick.

static func of_snapshot(snapshot: Dictionary) -> String:
	var core := snapshot.duplicate(true)
	core.erase("events")
	return JSON.stringify(core, "", true, true).sha256_text()
