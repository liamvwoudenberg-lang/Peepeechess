extends RefCounted
## Deterministic scripted input source for harness clients. It sees the world ONLY through its own
## client's view() (predicted self, interpolated opponent), exactly like a human would, so reaction
## timing includes snapshot cadence, interpolation delay and network latency.
##
## modes:
##   "idle"      stands still facing the opponent (lock-on)
##   "walker"    walks seeded random headings (with sprint bursts), never attacks - for prediction stats
##   "fighter"   approaches, attacks in light chains, blocks/dodges now and then (seeded)
##   "reactor"   stands; when its view first shows the opponent in `watch_state`, presses `action`
##               after `react_ticks` more ticks (once). Used for parry/dodge timing tables.
##   "script"    calls `hook.call(bot, client, tick)` (tests drive exact presses)

var mode: String = "idle"
var rng := RandomNumberGenerator.new()
var react_ticks: int = 10
var action: String = "parry"
var watch_state: String = "Attacking"
var hook: Callable
var fired_at: int = -1
var seen_at: int = -1

var _heading: float = 0.0
var _hold: int = 0
var _sprint: bool = false
var _cooldown: int = 0
var _block_left: int = 0
## walker: steer back toward the middle when farther than this from the arena centre (pillars sit at 4.8).
var leash: float = 5.0


func _init(p_mode: String = "idle", seed_value: int = 1) -> void:
	mode = p_mode
	rng.seed = seed_value


func think(client, tick: int) -> void:
	var me: Dictionary = client.view(client.local_id, float(tick))
	if me.is_empty():
		client.set_intent(0.0, 0.0, 0.0, true, false, false)
		return
	var opp: Dictionary = client.view(client.opponent_id, float(tick))
	var to_opp: Vector3 = Vector3.ZERO
	if not opp.is_empty():
		to_opp = CombatConstants.flat(opp["position"] - me["position"])
	match mode:
		"idle":
			client.set_intent(0.0, 0.0, CombatConstants.yaw_of(to_opp) if to_opp.length() > 0.01 else 0.0, true, false, false)
		"walker":
			if _hold <= 0:
				_heading = rng.randf_range(-PI, PI)
				_hold = rng.randi_range(20, 70)
				_sprint = rng.randf() < 0.3
			_hold -= 1
			var h := CombatConstants.heading(_heading)
			if me["position"].length() > leash:  # steer back toward the middle near the wall
				h = CombatConstants.flat(-me["position"]).normalized()
				_heading = CombatConstants.yaw_of(h)
			client.set_intent(h.x, h.z, _heading, false, _sprint, false)
		"fighter":
			_fight(client, tick, me, opp, to_opp)
		"reactor":
			client.set_intent(0.0, 0.0, CombatConstants.yaw_of(to_opp) if to_opp.length() > 0.01 else 0.0, true, false, false)
			if seen_at < 0 and not opp.is_empty() and String(opp["state"]) == watch_state:
				seen_at = tick
			if seen_at >= 0 and fired_at < 0 and tick - seen_at >= react_ticks:
				client.press(action)
				fired_at = tick
		"script":
			if hook.is_valid():
				hook.call(self, client, tick)


func _fight(client, tick: int, me: Dictionary, opp: Dictionary, to_opp: Vector3) -> void:
	var dist := to_opp.length()
	var dir := to_opp.normalized() if dist > 0.01 else Vector3.FORWARD
	var move := Vector3.ZERO
	var block := false
	if _block_left > 0:
		_block_left -= 1
		block = true
	if dist > 2.1:
		move = dir
	else:
		var side := Vector3(dir.z, 0.0, -dir.x)
		move = side * (1.0 if (tick / 40) % 2 == 0 else -1.0) * 0.5
		if _cooldown <= 0 and String(me["state"]) in ["Idle", "Moving"]:
			client.press("light" if rng.randf() < 0.85 else "heavy")
			_cooldown = rng.randi_range(26, 60)
		elif not opp.is_empty() and String(opp["state"]) == "Attacking" and rng.randf() < 0.05:
			_block_left = rng.randi_range(20, 40)
	_cooldown -= 1
	client.set_intent(move.x, move.z, CombatConstants.yaw_of(dir), true, false, block)
