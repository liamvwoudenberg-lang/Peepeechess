extends RefCounted
## Headless client model for ONE seat of an online battle: input sending, movement prediction,
## server reconciliation, remote-fighter interpolation, event de-duplication and cosmetic action
## prediction. It never touches a node, a device or a socket; the host (a CombatArena in
## PRESENTATION mode, a test harness, or a future transport adapter) feeds it intent and snapshots
## and sends the packets it produces.
##
## TRUST MODEL: this object has NO code path that changes HP, stamina, cooldowns or results.
## Those values are only ever copied out of schema-validated CombatSnapshots. Everything predicted
## (position of the local fighter, a "predicted action") is cosmetic and is overwritten or cancelled
## by the next authoritative snapshot. The server never reads anything the client computed except the
## intent in CombatInput (which the contract already treats as untrusted).
##
## Wire: only CombatInput out / CombatSnapshot in. `clientTick` carries the client's estimate of the
## server tick it is currently viewing (last snapshot tick + local ticks elapsed since receipt); the
## server uses (arrival tick - clientTick) as a bounded round-trip estimate, nothing else.

const Codec := preload("res://contracts/codec.gd")
const Predictor := preload("res://combat/net/movement_predictor.gd")
const S := CombatConstants.State

const INTERP_DELAY_TICKS := 8      # ~2 snapshot intervals: survives one lost snapshot
const EXTRAP_MAX_TICKS := 6
const HISTORY := 64
const SMOOTH_TICKS := 6.0          # visual error is blended out over ~100 ms
const HARD_SNAP_ABOVE := 1.5       # larger corrections teleport instead of sliding
const ACTION_PREDICT_TICKS := 8    # cosmetic predicted action lifetime without confirmation
const TELEPORT_ABOVE := 5.0        # snapshot-to-snapshot jumps (Blink) are not interpolated
const FREE_STATES := ["Idle", "Moving", "Blocking"]
const PREDICTED_STATE := {"light": "Attacking", "heavy": "Attacking", "dodge": "Dodging", "parry": "Parrying", "ability": "AbilityCasting"}

signal event_confirmed(event: Dictionary)
signal result_received(result: Dictionary)

var local_id: String
var opponent_id: String
var request: Dictionary
var send: Callable
var builder: CombatInputBuilder
var role: String
var radius: float = 0.4
var opp_radius: float = 0.4
var params: Dictionary
var start_tick: int

var snapshots: Array[Dictionary] = []       # {tick, recv, snap}
var latest: Dictionary = {}
var result: Dictionary = {}
var last_tick: int = -1
var clock_offset: float = NAN
var active: bool = true

# statistics (read by tests)
var stats := {"applied": 0, "dropped_old": 0, "rejected": 0, "events": 0, "events_deduped": 0, "sent": 0,
		"actions_predicted": 0, "actions_confirmed": 0, "actions_rejected": 0, "actions_expired": 0,
		"hard_snaps": 0}
var last_correction: float = 0.0
var max_correction: float = 0.0
var corrections: Array[float] = []

var _codec = Codec.new()
var _move := Vector2.ZERO
var _yaw := 0.0
var _lock := true
var _sprint := false
var _block := false
var _local_tick := 0
var _offset_window: Array[float] = []
var _seen_events: Dictionary = {}
var _unacked: Array[Dictionary] = []
var _pred: Dictionary = {}
var _render_offset := Vector3.ZERO
var _display_pos := Vector3.ZERO
var _display_init := false
var _pending_action: Dictionary = {}
var _send_ticks: Dictionary = {}
## Every press with the local tick it was made on (test/diagnostic: action delay measurements).
var press_log: Array[Dictionary] = []
var _ack_samples: Array[float] = []
var _last_ack: int = 0


func _init(p_request: Dictionary, p_local_id: String, p_send: Callable) -> void:
	request = p_request
	local_id = p_local_id
	send = p_send
	start_tick = int(request["startTick"])
	var me: Dictionary = request["attacker"] if request["attacker"]["playerId"] == local_id else request["defender"]
	var other: Dictionary = request["defender"] if request["attacker"]["playerId"] == local_id else request["attacker"]
	opponent_id = other["playerId"]
	role = me["role"]
	params = Predictor.params_for(role, me["stats"])
	radius = float(params["radius"])
	opp_radius = float(FighterProfile.for_role(other["role"]).get("radius", 0.4))
	builder = CombatInputBuilder.new(request["matchId"], request["battleId"], local_id)
	_yaw = 0.0 if me["color"] == "w" else PI


# ---- device-layer API ------------------------------------------------------------------------
func set_intent(move_x: float, move_z: float, yaw: float, lock: bool, sprint: bool, block: bool) -> void:
	_move = Vector2(move_x, move_z)
	_yaw = yaw
	_lock = lock
	_sprint = sprint
	_block = block


## Records one press ("light", "heavy", "dodge", "parry", "ability"). Sent with the next packet.
func press(action: String) -> void:
	builder.press(action)
	press_log.append({"action": action, "counter": int(builder.counters[action]), "tick": _local_tick})
	if _can_predict(action):
		_pending_action = {"action": action, "press_tick": _local_tick, "seq": -1}
		stats["actions_predicted"] += 1


# ---- clock -----------------------------------------------------------------------------------
## The server tick this client currently "sees" (lags the true server tick by the fastest one-way delay).
func view_server_tick(local_tick: float) -> float:
	if is_nan(clock_offset):
		return float(start_tick) + local_tick
	return local_tick + clock_offset


# ---- per-tick --------------------------------------------------------------------------------
## One 60 Hz client tick: builds and sends one CombatInput, advances prediction.
func tick(local_tick: int) -> void:
	_local_tick = local_tick
	if not active:
		return
	var packet := builder.build(_move.x, _move.y, _yaw, _lock, _sprint, _block)
	packet["clientTick"] = clampi(int(floor(view_server_tick(float(local_tick)))), 0, 2147483647)
	if not _pending_action.is_empty() and int(_pending_action["seq"]) < 0:
		_pending_action["seq"] = int(packet["sequence"])
	_send_ticks[int(packet["sequence"])] = local_tick
	_unacked.append({"seq": int(packet["sequence"]), "move_x": packet["moveX"], "move_z": packet["moveZ"],
			"yaw": packet["yawRadians"], "lock": packet["lockTarget"], "sprint": packet["sprint"], "block": packet["block"],
			"view": view_server_tick(float(local_tick))})
	if _unacked.size() > 240:
		_unacked.pop_front()
	_expire_action(local_tick)
	if _prediction_active():
		_pred = Predictor.step(_pred, _intent_of(_unacked[-1]), params, _opponent_state())
	_render_offset *= (1.0 - 1.0 / SMOOTH_TICKS)
	if _render_offset.length() < 0.004:
		_render_offset = Vector3.ZERO
	_update_display()
	stats["sent"] += 1
	send.call(packet)


func _intent_of(entry: Dictionary) -> Dictionary:
	return {"move_x": entry["move_x"], "move_z": entry["move_z"], "yaw": entry["yaw"], "lock": entry["lock"],
			"sprint": entry["sprint"], "block": entry["block"]}


# ---- snapshots -------------------------------------------------------------------------------
## Feeds one received CombatSnapshot. Returns true if it advanced the authoritative state.
func on_snapshot(snapshot: Dictionary, local_tick: int) -> bool:
	_local_tick = local_tick
	if not _codec.valid("CombatSnapshot", snapshot) or snapshot["matchId"] != request["matchId"] \
			or snapshot["battleId"] != request["battleId"]:
		stats["rejected"] += 1
		return false
	# Events are de-duplicated by (battleId, eventId) even from stale snapshots: the server repeats
	# recent events in every snapshot, so loss/reordering/reconnect must never double-fire a cue.
	for event in snapshot["events"]:
		var key := "%s:%d" % [snapshot["battleId"], int(event["eventId"])]
		if _seen_events.has(key):
			stats["events_deduped"] += 1
			continue
		_seen_events[key] = true
		stats["events"] += 1
		event_confirmed.emit(event)
	if snapshot["result"] != null and result.is_empty():
		result = snapshot["result"]
		result_received.emit(result)
	var tick := int(snapshot["serverTick"])
	if tick <= last_tick:
		stats["dropped_old"] += 1
		return false
	last_tick = tick
	latest = snapshot
	snapshots.append({"tick": tick, "recv": local_tick, "snap": snapshot})
	while snapshots.size() > HISTORY:
		snapshots.pop_front()
	stats["applied"] += 1
	_update_clock(tick, local_tick)
	_sample_ack(local_tick)
	_reconcile()
	_resolve_action()
	return true


func _sample_ack(local_tick: int) -> void:
	var ack := int(_fighter(latest, local_id)["lastInputSequence"])
	if ack > _last_ack:
		if _send_ticks.has(ack):
			_ack_samples.append(float(local_tick - int(_send_ticks[ack])))
			while _ack_samples.size() > 12:
				_ack_samples.pop_front()
		for key in _send_ticks.keys():
			if int(key) <= ack:
				_send_ticks.erase(key)
		_last_ack = ack


func _update_clock(server_tick: int, local_tick: int) -> void:
	_offset_window.append(float(server_tick - local_tick))
	while _offset_window.size() > 8:
		_offset_window.pop_front()
	var best: float = _offset_window.max()
	clock_offset = best if is_nan(clock_offset) else lerpf(clock_offset, best, 0.25)


func _fighter(snapshot: Dictionary, player_id: String) -> Dictionary:
	for f in snapshot["fighters"]:
		if f["playerId"] == player_id:
			return f
	return {}


## Round trip in ticks measured from acknowledgements: (snapshot receipt tick) - (send tick of the newest
## acked input), minimum over a short window (the minimum is the sample taken with no snapshot-cadence wait).
func rtt_estimate_ticks() -> float:
	if _ack_samples.is_empty():
		return 0.0
	return _ack_samples.min()


func _live() -> bool:
	if latest.is_empty() or not result.is_empty():
		return false
	if int(latest["countdownTicksRemaining"]) == 0:
		return true
	return _counts_at(view_server_tick(float(_local_tick)))


## Will an input sent when the client views server tick `view_tick` take effect in the live fight?
## (applied tick = view + RTT; the first live tick is startTick + 180 + 1.) Lets prediction start with
## the fight instead of one round trip later.
func _counts_at(view_tick: float) -> bool:
	return view_tick + rtt_estimate_ticks() >= float(start_tick + CombatConstants.COUNTDOWN_TICKS + 1) - 0.5


func _is_free(state: String) -> bool:
	return state in FREE_STATES


func _prediction_active() -> bool:
	if latest.is_empty() or not _live():
		return false
	if not _is_free(String(_fighter(latest, local_id)["state"])):
		return false
	return _pending_action.is_empty()


func _opponent_state() -> Dictionary:
	if latest.is_empty():
		return {}
	var o := _fighter(latest, opponent_id)
	var p: Dictionary = o["position"]
	return {"pos": Vector3(p["x"], 0.0, p["z"]), "radius": opp_radius, "alive": String(o["state"]) != "Defeated"}


## Server reconciliation: restart from the authoritative state and replay every input the server has
## not yet acknowledged, then blend any visual error away.
func _reconcile() -> void:
	var me := _fighter(latest, local_id)
	var ack := int(me["lastInputSequence"])
	while not _unacked.is_empty() and int(_unacked[0]["seq"]) <= ack:
		_unacked.pop_front()
	var p: Dictionary = me["position"]
	var server_pos := Vector3(p["x"], 0.0, p["z"])
	if not _prediction_active():
		# Not predicting (action in progress, countdown, defeated ...): show server state.
		if not _pred.is_empty():
			_render_offset = (_pred["pos"] + _render_offset) - server_pos
			if _render_offset.length() > HARD_SNAP_ABOVE:
				_render_offset = Vector3.ZERO
		_pred = Predictor.initial(server_pos, float(me["yawRadians"]), float(me["stamina"]))
		_pred["vel"] = Vector3(me["velocity"]["x"], 0.0, me["velocity"]["z"])
		_update_display()
		return
	var rebased := Predictor.initial(server_pos, float(me["yawRadians"]), float(me["stamina"]))
	rebased["vel"] = Vector3(me["velocity"]["x"], 0.0, me["velocity"]["z"])
	var opp := _opponent_state()
	var countdown_over := int(latest["countdownTicksRemaining"]) == 0
	for entry in _unacked:
		if countdown_over or _counts_at(float(entry["view"])):
			rebased = Predictor.step(rebased, _intent_of(entry), params, opp)
	if not _pred.is_empty():
		var error: Vector3 = _pred["pos"] - rebased["pos"]
		last_correction = error.length()
		max_correction = maxf(max_correction, last_correction)
		corrections.append(last_correction)
		if last_correction > HARD_SNAP_ABOVE:
			_render_offset = Vector3.ZERO
			stats["hard_snaps"] += 1
		else:
			_render_offset += error
	_pred = rebased
	_update_display()


func _update_display() -> void:
	if _pred.is_empty():
		return
	var target: Vector3 = _pred["pos"] + _render_offset
	if _prediction_active() or not _display_init:
		_display_pos = target
	else:
		_display_pos = _display_pos.lerp(target, 0.4)
	_display_init = true


# ---- cosmetic action prediction --------------------------------------------------------------
func _can_predict(action: String) -> bool:
	if latest.is_empty() or not _live() or not _pending_action.is_empty():
		return false
	var me := _fighter(latest, local_id)
	if not _is_free(String(me["state"])):
		return false
	var stamina := float(me["stamina"])
	var profile := FighterProfile.for_role(role)
	match action:
		"light":
			return stamina >= AttackLibrary.light(role, 0).stamina_cost
		"heavy":
			return stamina >= AttackLibrary.heavy(role).stamina_cost
		"dodge":
			return stamina >= float(profile["dodge_cost"])
		"parry":
			return stamina >= float(profile["parry_cost"])
		"ability":
			var ability_id: String = String((request["attacker"] if request["attacker"]["playerId"] == local_id else request["defender"])["stats"]["abilityId"])
			var definition: Dictionary = AbilityComponent.DEFINITIONS.get(ability_id, {})
			if int(me["cooldownTicks"]) > 0:
				return false
			if definition.has("hp_threshold") and float(me["hp"]) > float(definition["hp_threshold"]) * _max_hp():
				return false
			return stamina >= float(definition.get("stamina_cost", 0.0))
	return false


func _max_hp() -> float:
	var me: Dictionary = request["attacker"] if request["attacker"]["playerId"] == local_id else request["defender"]
	return float(me["stats"]["maxHp"])


func _resolve_action() -> void:
	if _pending_action.is_empty() or int(_pending_action["seq"]) < 0:
		return
	var me := _fighter(latest, local_id)
	if int(me["lastInputSequence"]) < int(_pending_action["seq"]):
		return  # the server has not seen the press yet
	if _is_free(String(me["state"])):
		stats["actions_rejected"] += 1   # acknowledged but nothing started: the server refused it
	else:
		stats["actions_confirmed"] += 1  # the authoritative animation takes over
	_pending_action = {}


func _expire_action(local_tick: int) -> void:
	if not _pending_action.is_empty() and local_tick - int(_pending_action["press_tick"]) > ACTION_PREDICT_TICKS:
		stats["actions_expired"] += 1
		_pending_action = {}


func predicted_action() -> String:
	return String(_pending_action.get("action", ""))


# ---- presentation view -----------------------------------------------------------------------
## What to draw for `player_id` at local tick `local_tick`. All gameplay numbers (hp, stamina,
## cooldown) are copied from authoritative snapshots; only position/yaw/animation phase of the LOCAL
## fighter may be predicted, and remote fighters are interpolated in the past.
func view(player_id: String, local_tick: float) -> Dictionary:
	if latest.is_empty():
		return {}
	if player_id == local_id:
		return _local_view(local_tick)
	return _remote_view(player_id, local_tick)


func _local_view(local_tick: float) -> Dictionary:
	var me := _fighter(latest, local_id)
	var predicting := _prediction_active() and not _pred.is_empty()
	var out := {
		"playerId": local_id, "hp": me["hp"], "stamina": me["stamina"], "cooldownTicks": me["cooldownTicks"],
		"state": me["state"], "stateTicks": me["stateTicks"], "predicted": predicting, "predicted_action": "",
		"yawRadians": float(_pred["yaw"]) if predicting else float(me["yawRadians"]),
		"position": _display_pos if _display_init else Vector3(me["position"]["x"], 0.0, me["position"]["z"]),
		"velocity": Vector3(me["velocity"]["x"], 0.0, me["velocity"]["z"]),
	}
	if not _pending_action.is_empty():
		out["predicted_action"] = _pending_action["action"]
		out["state"] = PREDICTED_STATE[_pending_action["action"]]
		out["stateTicks"] = maxi(0, int(local_tick) - int(_pending_action["press_tick"]))
	return out


func _remote_view(player_id: String, local_tick: float) -> Dictionary:
	var render := view_server_tick(local_tick) - float(INTERP_DELAY_TICKS)
	var older: Dictionary = snapshots[0]
	var newer: Dictionary = {}
	for entry in snapshots:
		if float(entry["tick"]) <= render:
			older = entry
		else:
			newer = entry
			break
	var a := _fighter(older["snap"], player_id)
	var pa := Vector3(a["position"]["x"], 0.0, a["position"]["z"])
	var out := {
		"playerId": player_id, "hp": a["hp"], "stamina": a["stamina"], "cooldownTicks": a["cooldownTicks"],
		"state": a["state"], "stateTicks": int(a["stateTicks"]) + maxi(0, int(render - float(older["tick"]))),
		"predicted": false, "predicted_action": "", "interpolated": not newer.is_empty(),
		"velocity": Vector3(a["velocity"]["x"], 0.0, a["velocity"]["z"]),
	}
	if not newer.is_empty():
		var b := _fighter(newer["snap"], player_id)
		var pb := Vector3(b["position"]["x"], 0.0, b["position"]["z"])
		var span := float(newer["tick"] - older["tick"])
		var t := clampf((render - float(older["tick"])) / maxf(span, 1.0), 0.0, 1.0)
		if pa.distance_to(pb) > TELEPORT_ABOVE:
			out["position"] = pb if t >= 0.5 else pa  # e.g. Blink: do not slide through walls
		else:
			out["position"] = pa.lerp(pb, t)
		out["yawRadians"] = lerp_angle(float(a["yawRadians"]), float(b["yawRadians"]), t)
	else:
		# Buffer ran dry: limited extrapolation, kept inside the arena.
		var dt := minf(maxf(render - float(older["tick"]), 0.0), float(EXTRAP_MAX_TICKS))
		var vel: Vector3 = out["velocity"]
		var pos: Vector3 = pa + vel * dt * CombatConstants.DT
		var limit := CombatConstants.ARENA_WALL_RADIUS - opp_radius
		if Vector2(pos.x, pos.z).length() > limit:
			var clipped := Vector2(pos.x, pos.z).normalized() * limit
			pos = Vector3(clipped.x, 0.0, clipped.y)
		out["position"] = pos
		out["yawRadians"] = float(a["yawRadians"])
		out["extrapolated_ticks"] = dt
	return out


## After an app restart the sequence must continue above what the server already accepted
## (CONTRACTS.md rule 5). The snapshot carries lastInputSequence; the cumulative ACTION COUNTERS are not
## in any v1 message, so a restarted client that had pressed actions earlier cannot resume them (the
## server rejects decreasing counters) - see NETWORKING.md "limitations".
func resume_after_restart(snapshot: Dictionary) -> void:
	for f in snapshot["fighters"]:
		if f["playerId"] == local_id:
			builder.sequence = maxi(builder.sequence, int(f["lastInputSequence"]))


## Persisting this lets a recreated client (app restart / reconnect) keep events from firing twice.
func export_dedupe_state() -> Array:
	return _seen_events.keys()


func import_dedupe_state(keys: Array) -> void:
	for key in keys:
		_seen_events[key] = true


func render_offset() -> Vector3:
	return _render_offset


func unacked_count() -> int:
	return _unacked.size()
