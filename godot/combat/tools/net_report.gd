extends SceneTree
## Online duel report: bot-vs-bot duels through the lockstep net harness (1 authoritative server + 2 clients + 4 simulated one-way channels with
## latency, jitter, loss, reordering and duplication) under the game's REAL rules (defender's edge, Resolve, persistent HP via seat_start).
## For every network profile it reports
##   * completion: the server finished the duel and both clients received the same result;
##   * desyncs, three kinds, each counted per duel:
##       replay    a fresh simulation fed the server's recorded inputs ends in a different snapshot or duel summary (non-determinism);
##       applied   a snapshot a client applied differs (state hash) from the server's state at that tick (corruption / bad reorder handling);
##       result    a client's final result differs from the server's (or never arrived).
##
##   godot --headless --path godot --script res://combat/tools/net_report.gd -- n=24 seed=1 profiles=all shard=0/4 out=/tmp/net-0.json
## Merge shards with: python3 godot/combat/tools/summarize_net.py /tmp/net-*.json
const Harness := preload("res://combat/net/net_harness.gd")
const Bot := preload("res://combat/net/net_bot.gd")
const StateHash := preload("res://combat/net/state_hash.gd")
const Balance := preload("res://combat/data/balance_data.gd")
## RTT convention: N ms = round trip; one-way ticks up/down as in test_net_latency.gd (60 ticks = 1 s).
const PROFILES := [
	{"name": "lan 0ms", "up": 0, "down": 0, "jitter": 0, "loss": 0.0, "reorder": 0.0, "dup": 0.0},
	{"name": "50ms 1%", "up": 1, "down": 2, "jitter": 0, "loss": 0.01, "reorder": 0.0, "dup": 0.0},
	{"name": "100ms 1%", "up": 3, "down": 3, "jitter": 1, "loss": 0.01, "reorder": 0.0, "dup": 0.0},
	{"name": "150ms 2%", "up": 4, "down": 5, "jitter": 1, "loss": 0.02, "reorder": 0.0, "dup": 0.0},
	{"name": "150ms 2% jitter+reorder", "up": 4, "down": 5, "jitter": 3, "loss": 0.02, "reorder": 0.05, "dup": 0.01},
	{"name": "250ms 5% (stress)", "up": 8, "down": 8, "jitter": 3, "loss": 0.05, "reorder": 0.05, "dup": 0.02},
]
const PAIRS := ["pp", "nb", "rq", "bn", "qp", "pq", "rr", "nn"]
const MAX_TICKS := 180 + 5400 + 120


func _initialize() -> void:
	await process_frame
	var args := {"n": "24", "seed": "1", "profiles": "all", "shard": "0/1", "out": ""}
	for token in OS.get_cmdline_user_args():
		var kv: PackedStringArray = String(token).split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var wanted := String(args["profiles"])
	var shard := String(args["shard"]).split("/")
	var report: Dictionary = {"tuning": Balance.stamp(), "n": int(args["n"]), "profiles": {}}
	var started := Time.get_ticks_msec()
	for profile in PROFILES:
		if wanted != "all" and not (String(profile["name"]).begins_with(wanted)):
			continue
		var row := {"duels": 0, "completed": 0, "both_clients_got_result": 0, "desync_replay": 0, "desync_applied": 0, "desync_result": 0, "applied_checked": 0, "snapshots_sent": 0, "dropped": 0, "terminal_lost": 0, "drift_replay": 0, "max_drift_cm": 0, "mean_ticks": 0.0}
		for i in int(args["n"]):
			if i % int(shard[1]) != int(shard[0]):
				continue
			var r: Dictionary = await _duel(profile, PAIRS[i % PAIRS.size()], int(args["seed"]) * 1000 + i, i)
			row["duels"] += 1
			for key in ["completed", "both_clients_got_result", "desync_replay", "desync_applied", "desync_result", "applied_checked", "snapshots_sent", "dropped", "terminal_lost", "drift_replay"]:
				row[key] += int(r[key])
			row["max_drift_cm"] = maxi(int(row["max_drift_cm"]), int(r["max_drift_cm"]))
			row["mean_ticks"] += float(r["ticks"])
		row["mean_ticks"] = snappedf(row["mean_ticks"] / maxf(1.0, float(row["duels"])), 0.1)
		report["profiles"][profile["name"]] = row
		print("%-26s duels %3d completed %3d both-clients %3d | desync: replay %d applied %d result %d (of %d applied snapshots) [%d s]" % [profile["name"], row["duels"], row["completed"],
				row["both_clients_got_result"], row["desync_replay"], row["desync_applied"], row["desync_result"], row["applied_checked"], (Time.get_ticks_msec() - started) / 1000])
	if String(args["out"]) != "":
		var file := FileAccess.open(String(args["out"]), FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "\t", true))
	quit(0)


func _duel(profile: Dictionary, pair: String, seed_value: int, index: int) -> Dictionary:
	var attacker_white := index % 2 == 0
	var request := FighterRoster.build_request(pair.substr(0, 1) if attacker_white else pair.substr(1, 1), pair.substr(1, 1) if attacker_white else pair.substr(0, 1), "w" if attacker_white else "b", "net-%d" % seed_value, seed_value, 0)
	# Persistent damage and carried Resolve exactly as the chess layer hands them over (a wounded attacker, a defender with some Resolve).
	var options := {"seat_start": {"attacker": {"hp": maxi(1, roundi(0.6 * float(request["attacker"]["stats"]["maxHp"]))), "resolve": 30.0, "take_mult": 0.95}, "defender": {"resolve": 50.0, "regen_mult": 1.1}}}
	var cfg := {"up": [profile["up"], profile["up"]], "down": [profile["down"], profile["down"]], "jitter": profile["jitter"], "loss": profile["loss"], "reorder": profile["reorder"], "dup": profile["dup"], "seed": seed_value, "options": options}
	var h := Harness.new()
	await h.setup(self, request, cfg)
	h.bots[0] = Bot.new("fighter", seed_value * 2 + 1)
	h.bots[1] = Bot.new("fighter", seed_value * 2 + 2)
	var server_hashes := {}
	h.server.snapshot_ready.connect(func(snapshot): server_hashes[int(snapshot["serverTick"])] = StateHash.of_snapshot(snapshot))
	for client in h.clients:
		client.result_received.connect(func(_r): pass)
	h.run_until(func(): return not h.result.is_empty(), MAX_TICKS)
	var out := {"completed": 0, "both_clients_got_result": 0, "desync_replay": 0, "desync_applied": 0, "desync_result": 0, "applied_checked": 0, "snapshots_sent": h.snapshots_sent, "dropped": 0, "terminal_lost": 0, "drift_replay": 0, "max_drift_cm": 0, "ticks": h.tick}
	if h.result.is_empty():
		h.dispose()
		return out
	out["completed"] = 1
	h.run(150)   # let the repeated final snapshot get through a lossy link (the server keeps sending the result)
	# The terminal snapshot is sent once on the (lossy, unreliable) snapshot channel, but the production server ALSO sends the result as a reliable
	# BattleResult message (match_session.gd battle_receipt) and replays it after a reconnect. Model that: a client that lost the terminal snapshot
	# gets the reliable copy; the loss itself is counted (informational), a result that still differs afterwards is a desync.
	for client in h.clients:
		if client.result.is_empty():
			out["terminal_lost"] += 1
			client.on_snapshot(h.sim.snapshot(), h.tick)
	var server_result := JSON.stringify(h.result, "", true, true)
	var agree := 0
	for client in h.clients:
		if not client.result.is_empty() and JSON.stringify(client.result, "", true, true) == server_result:
			agree += 1
		for entry in client.snapshots:
			var snapshot: Dictionary = entry["snap"]
			var tick := int(snapshot["serverTick"])
			if server_hashes.has(tick):
				out["applied_checked"] += 1
				if StateHash.of_snapshot(snapshot) != server_hashes[tick]:
					out["desync_applied"] += 1
	out["both_clients_got_result"] = 1 if agree == 2 else 0
	out["desync_result"] = 0 if agree == 2 else 1
	for channel in h.c2s + h.s2c:
		out["dropped"] += channel.dropped
	var replay: Dictionary = await h.replay_final_state()
	var live_snapshot := JSON.stringify(h.sim.snapshot(), "", true, true)
	var live_summary := JSON.stringify(h.sim.duel_summary(), "", true, true)
	if String(replay["snapshot"]) != live_snapshot or String(replay["summary"]) != live_summary:
		var drift := _position_drift(JSON.parse_string(live_snapshot), JSON.parse_string(String(replay["snapshot"])))
		if drift >= 0.0 and String(replay["summary"]) == live_summary:
			out["drift_replay"] = 1   # only positions / velocities / yaw differ, by `drift` metres: engine collision settling, not a state divergence
			out["max_drift_cm"] = roundi(drift * 100.0)
		else:
			out["desync_replay"] = 1
		print("  REPLAY DIVERGED %s pair %s: snapshot %s | summary %s" % [profile["name"], pair, _first_diff(JSON.parse_string(live_snapshot), JSON.parse_string(String(replay["snapshot"])), ""), _first_diff(JSON.parse_string(live_summary), JSON.parse_string(String(replay["summary"])), "")])
	h.dispose()
	return out


## First differing path between two parsed JSON values ("same" when equal): live value vs replayed value.
func _first_diff(a: Variant, b: Variant, path: String) -> String:
	if typeof(a) == TYPE_DICTIONARY and typeof(b) == TYPE_DICTIONARY:
		for key in a:
			if not b.has(key):
				return "%s/%s missing in replay" % [path, key]
			var d := _first_diff(a[key], b[key], path + "/" + str(key))
			if d != "same":
				return d
		return "same"
	if typeof(a) == TYPE_ARRAY and typeof(b) == TYPE_ARRAY:
		for i in mini(a.size(), b.size()):
			var d := _first_diff(a[i], b[i], "%s[%d]" % [path, i])
			if d != "same":
				return d
		return "same" if a.size() == b.size() else "%s size %d vs %d" % [path, a.size(), b.size()]
	return "same" if a == b else "%s live=%s replay=%s" % [path, str(a), str(b)]


## -1 when the snapshots differ in anything but fighter position / velocity / yaw (or those differ by more than 10 cm / 0.5 m/s / 0.1 rad); otherwise the
## largest position difference in metres.
func _position_drift(a: Dictionary, b: Dictionary) -> float:
	var worst := 0.0
	var a_core := a.duplicate(true)
	var b_core := b.duplicate(true)
	for i in a["fighters"].size():
		var fa: Dictionary = a["fighters"][i]
		var fb: Dictionary = b["fighters"][i]
		var pa := Vector3(fa["position"]["x"], fa["position"]["y"], fa["position"]["z"])
		var pb := Vector3(fb["position"]["x"], fb["position"]["y"], fb["position"]["z"])
		var va := Vector3(fa["velocity"]["x"], fa["velocity"]["y"], fa["velocity"]["z"])
		var vb := Vector3(fb["velocity"]["x"], fb["velocity"]["y"], fb["velocity"]["z"])
		if pa.distance_to(pb) > 0.1 or va.distance_to(vb) > 0.5 or absf(angle_difference(float(fa["yawRadians"]), float(fb["yawRadians"]))) > 0.1:
			return -1.0
		worst = maxf(worst, pa.distance_to(pb))
		for key in ["position", "velocity", "yawRadians"]:
			a_core["fighters"][i].erase(key)
			b_core["fighters"][i].erase(key)
	return worst if JSON.stringify(a_core, "", true, true) == JSON.stringify(b_core, "", true, true) else -1.0
