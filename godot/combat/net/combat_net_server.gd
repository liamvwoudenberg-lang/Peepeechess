extends RefCounted
## Authoritative host for ONE online battle: wraps a CombatSimulation and adds the things a hosted
## match needs that a local sim does not - per-seat input admission bookkeeping, a bounded latency
## estimate that drives the hit-commit grace, 15 Hz snapshot cadence, seat presence/abandonment on the
## SERVER clock, and an input record for replay verification.
##
## It does not own sockets, authentication or the chess state. The hosting transport (Codex) must:
##   * authenticate each packet to a seat and pass `player_id` (this class never trusts packet.playerId
##     for seat identity beyond the simulation's own seat check);
##   * call receive_input() for each CombatInput and step() once per 60 Hz tick;
##   * broadcast every `snapshot_ready` CombatSnapshot (identical for both seats: no hidden info);
##   * (recommended) feed measured transport RTT through set_seat_rtt_ms(), which overrides the
##     ack-derived estimate;
##   * settle `battle_finished(result)` exactly once; treat `seat_abandoned` / `battle_aborted_draw`
##     as match-level forfeit/draw that BYPASS BattleResult (CONTRACTS.md rule 8).
##
## Lag compensation is limited to CombatSimulation.set_hit_grace (see NETWORKING.md): this class only
## chooses the per-seat grace, clamped to 0..HIT_GRACE_CAP, from a bounded round-trip estimate.

signal snapshot_ready(snapshot: Dictionary)
signal battle_finished(result: Dictionary)
signal seat_abandoned(player_id: String)
signal battle_aborted_draw
signal input_rejected(player_id: String, code: String)

const SNAPSHOT_EVERY_TICKS := CombatConstants.SNAPSHOT_EVERY_TICKS
const ABANDON_TICKS := 600            # 10 s of SERVER time (CONTRACTS.md rule 8)
const RTT_WINDOW := 9
const RTT_SAMPLE_MAX := 30            # ack ages above 500 ms are ignored as stale/lying claims

var sim: CombatSimulation
var seats: Dictionary = {}
var aborted: bool = false
## Test/ops switch: false disables the hit-commit grace entirely (every seat resolves hits on the detection tick).
var grace_enabled: bool = true
var abort_reason: String = ""
var abandoned_at_tick: int = -1
var record: Array = []                # accepted inputs + grace changes, for replay verification
var counters := {"accepted": 0, "stale": 0, "invalid": 0, "forbidden": 0, "other": 0}

var _start_tick: int = 0


func _init(p_sim: CombatSimulation) -> void:
	sim = p_sim


func start(request: Dictionary) -> Dictionary:
	var reply: Dictionary = sim.start(request)
	if not reply["ok"]:
		return reply
	aborted = false
	abort_reason = ""
	abandoned_at_tick = -1
	record = []
	_start_tick = int(request["startTick"])
	seats.clear()
	for fighter in sim.fighters:
		seats[fighter.player_id] = {
			"last_input_tick": sim.server_tick, "disconnected_since": -1, "max_claim": -1,
			"rtt_samples": [], "rtt_override_ms": -1.0, "grace": 0,
		}
	if not sim.finished.is_connected(_on_finished):
		sim.finished.connect(_on_finished)
	return {"ok": true}


## Hosting transport reports a measured round trip (server-side ping), which overrides the
## ack-derived estimate. This is the preferred, non-client-influenced source.
func set_seat_rtt_ms(player_id: String, rtt_ms: float) -> void:
	if seats.has(player_id):
		seats[player_id]["rtt_override_ms"] = rtt_ms


func set_seat_connected(player_id: String, connected: bool) -> void:
	if not seats.has(player_id):
		return
	var seat: Dictionary = seats[player_id]
	if connected:
		seat["disconnected_since"] = -1
		seat["last_input_tick"] = sim.server_tick
	elif int(seat["disconnected_since"]) < 0:
		seat["disconnected_since"] = sim.server_tick


## Fresh full snapshot for a reconnecting seat; resets that seat's absence clock. Input sequence and
## action counters continue (the simulation retains them), so old packets stay stale.
func reconnect_seat(player_id: String) -> Dictionary:
	if aborted or not seats.has(player_id):
		return {}
	set_seat_connected(player_id, true)
	return sim.snapshot()


## The tick an input accepted right now will first take effect on.
func applied_tick() -> int:
	return sim.server_tick + 1


func receive_input(player_id: String, packet: Dictionary) -> Dictionary:
	if aborted or not seats.has(player_id):
		counters["forbidden"] += 1
		return {"ok": false, "code": "FORBIDDEN", "message": "unknown seat or battle aborted"}
	var seat: Dictionary = seats[player_id]
	if int(seat["disconnected_since"]) >= 0:
		counters["forbidden"] += 1
		return {"ok": false, "code": "FORBIDDEN", "message": "seat is disconnected; reconnect first"}
	# The authenticated seat, not the packet's claim, decides whose input this is.
	if String(packet.get("playerId", "")) != player_id:
		counters["forbidden"] += 1
		input_rejected.emit(player_id, "FORBIDDEN")
		return {"ok": false, "code": "FORBIDDEN", "message": "packet playerId does not match the authenticated seat"}
	var reply: Dictionary = sim.submit_input(packet)
	if not reply["ok"]:
		var code := String(reply["code"])
		match code:
			"STALE_INPUT":
				counters["stale"] += 1
			"INVALID_PAYLOAD":
				counters["invalid"] += 1
			"FORBIDDEN":
				counters["forbidden"] += 1
			_:
				counters["other"] += 1
		input_rejected.emit(player_id, code)
		return reply
	counters["accepted"] += 1
	var arrival := applied_tick()
	seat["last_input_tick"] = arrival
	_sample_rtt(seat, arrival, int(packet["clientTick"]))
	record.append({"t": arrival, "k": "in", "p": player_id, "packet": packet.duplicate(true)})
	return reply


func _sample_rtt(seat: Dictionary, arrival: int, claimed: int) -> void:
	# A client cannot claim a tick beyond the one this packet takes effect on (its own view lags the
	# server by the downlink delay, so a truthful claim is never ahead), and claims never move backwards.
	claimed = mini(claimed, arrival)
	claimed = maxi(claimed, int(seat["max_claim"]))
	seat["max_claim"] = claimed
	var age := arrival - claimed
	if age < 0:
		age = 0
	if age > RTT_SAMPLE_MAX:
		return  # a stalled/forged ack must not widen the window; the cap would bound it anyway
	var samples: Array = seat["rtt_samples"]
	samples.append(age)
	while samples.size() > RTT_WINDOW:
		samples.pop_front()


## Estimated round-trip in ticks for a seat (median of recent ack ages, or the transport override).
func rtt_ticks(player_id: String) -> float:
	var seat: Dictionary = seats[player_id]
	if float(seat["rtt_override_ms"]) >= 0.0:
		return float(seat["rtt_override_ms"]) / (1000.0 / 60.0)
	var samples: Array = seat["rtt_samples"]
	if samples.is_empty():
		return 0.0
	var sorted := samples.duplicate()
	sorted.sort()
	return float(sorted[sorted.size() / 2])


func grace_for(player_id: String) -> int:
	if not grace_enabled:
		return 0
	return clampi(ceili(rtt_ticks(player_id) - 0.001), 0, CombatSimulation.HIT_GRACE_CAP)


## Absent ticks for a seat on the server clock.
func absent_ticks(player_id: String) -> int:
	var seat: Dictionary = seats[player_id]
	var since := int(seat["disconnected_since"]) if int(seat["disconnected_since"]) >= 0 else int(seat["last_input_tick"])
	return sim.server_tick - since


## One 60 Hz server tick.
func step() -> void:
	if aborted or not sim.is_running():
		return
	for player_id in seats:
		var g := grace_for(player_id)
		if g != int(seats[player_id]["grace"]) or sim.hit_grace(player_id) != g:
			seats[player_id]["grace"] = g
			sim.set_hit_grace(player_id, g)
			record.append({"t": applied_tick(), "k": "grace", "p": player_id, "g": g})
	sim.step_tick()
	if not sim.is_running():
		snapshot_ready.emit(sim.snapshot())  # terminal snapshot carries the result
		return
	if (sim.server_tick - _start_tick) % SNAPSHOT_EVERY_TICKS == 0:
		snapshot_ready.emit(sim.snapshot())
	_check_abandonment()


func _check_abandonment() -> void:
	var expired: Array[String] = []
	for player_id in seats:
		if absent_ticks(player_id) >= ABANDON_TICKS:
			expired.append(player_id)
	if expired.is_empty():
		return
	# CONTRACTS.md rule 8: the missing seat forfeits - unless the other seat is gone too, then the
	# match is drawn. "Gone" = has not been heard from for longer than the neutralisation window.
	var everyone_gone := true
	for player_id in seats:
		if player_id != expired[0] and absent_ticks(player_id) < CombatConstants.INPUT_NEUTRAL_AFTER_TICKS:
			everyone_gone = false
	aborted = true
	abandoned_at_tick = sim.server_tick
	if everyone_gone:
		abort_reason = "both_abandoned"
		battle_aborted_draw.emit()
	else:
		abort_reason = "seat_abandoned:" + expired[0]
		seat_abandoned.emit(expired[0])


func _on_finished(result: Dictionary) -> void:
	battle_finished.emit(result)
