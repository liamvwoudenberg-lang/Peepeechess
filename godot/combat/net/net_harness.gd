extends RefCounted
## Lockstep test harness: 1 authoritative server + 2 clients + 4 one-way channels, all driven by one
## integer tick counter. Per harness tick n:
##   1 deliver due snapshots to clients   2 bots decide   3 clients tick (send 1 input each)
##   4 deliver due inputs to the server   5 server.step() (-> snapshots into the s2c channels)
## Server tick after step n is startTick + n + 1 (the countdown is part of the fight timeline).
## `latency` configs are per-direction tick counts; RTT ticks = up + down (60 ticks = 1 s).

const Server := preload("res://combat/net/combat_net_server.gd")
const Client := preload("res://combat/net/combat_net_client.gd")
const Channel := preload("res://combat/net/sim_channel.gd")
const Bot := preload("res://combat/net/net_bot.gd")

var tree: SceneTree
var sim: CombatSimulation
var server
var clients: Array = []
var bots: Array = [null, null]
var c2s: Array = []
var s2c: Array = []
var ids: Array[String] = ["player-white", "player-black"]
var tick: int = 0
var request: Dictionary
var muted: Array[bool] = [false, false]
var events_seen: Array = [[], []]       # events each client confirmed
var snapshots_sent: int = 0
var result: Dictionary = {}
var finished_tick: int = -1


## cfg: {up: [a,b] ticks, down: [a,b] ticks, jitter, loss, reorder, dup, seed, grace: bool}
func setup(p_tree: SceneTree, p_request: Dictionary, cfg: Dictionary = {}) -> void:
	tree = p_tree
	request = p_request
	sim = CombatSimulation.new()
	tree.root.add_child(sim)
	server = Server.new(sim)
	var reply: Dictionary = server.start(request)
	assert(reply["ok"], "harness start failed: %s" % str(reply))
	await tree.physics_frame
	var up: Array = cfg.get("up", [0, 0])
	var down: Array = cfg.get("down", [0, 0])
	var seed_value: int = int(cfg.get("seed", 1))
	for i in 2:
		var to_server := Channel.new()
		to_server.configure(int(up[i]), int(cfg.get("jitter", 0)), float(cfg.get("loss", 0.0)), float(cfg.get("reorder", 0.0)), float(cfg.get("dup", 0.0)), seed_value * 10 + i)
		var to_client := Channel.new()
		to_client.configure(int(down[i]), int(cfg.get("jitter", 0)), float(cfg.get("loss", 0.0)), float(cfg.get("reorder", 0.0)), float(cfg.get("dup", 0.0)), seed_value * 10 + 5 + i)
		c2s.append(to_server)
		s2c.append(to_client)
		var client = Client.new(request, ids[i], func(packet): c2s[i].send(packet, tick))
		var index := i
		client.event_confirmed.connect(func(e): events_seen[index].append(e))
		clients.append(client)
	server.snapshot_ready.connect(_broadcast)
	server.battle_finished.connect(func(r): result = r; finished_tick = tick)
	server.grace_enabled = bool(cfg.get("grace", true))


func _broadcast(snapshot: Dictionary) -> void:
	snapshots_sent += 1
	for i in 2:
		s2c[i].send(snapshot, tick)


func place(white_pos: Vector3, black_pos: Vector3) -> void:
	sim.fighters[0].teleport(white_pos, 0.0)
	sim.fighters[1].teleport(black_pos, PI)


func step() -> void:
	for i in 2:
		if not muted[i] and bots[i] != null:
			bots[i].think(clients[i], tick)
	for i in 2:
		if not muted[i]:
			clients[i].tick(tick)
	for i in 2:
		for packet in c2s[i].poll(tick):
			server.receive_input(ids[i], packet)
	server.step()
	_deliver_snapshots()
	tick += 1


## Snapshots sent by this tick's server step are delivered right away when the channel latency is 0,
## so a configured latency of N ticks means exactly N ticks (no hidden pipeline delay).
func _deliver_snapshots() -> void:
	for i in 2:
		var due: Array = s2c[i].poll(tick)
		if muted[i]:
			continue  # drained and discarded while the client is "away"
		for snapshot in due:
			clients[i].on_snapshot(snapshot, tick)


func run(ticks: int) -> void:
	for _i in ticks:
		step()


func run_until(condition: Callable, max_ticks: int) -> int:
	for i in max_ticks:
		if condition.call():
			return i
		step()
	return -1


func events_of(type: String) -> Array:
	return sim.recent_events.filter(func(e): return e["type"] == type)


## Replays the server's recorded inputs (and grace changes) through a FRESH simulation with no
## clients/channels and returns its final snapshot JSON - the network layer must add no divergence.
## `prepare` (optional) receives the fresh simulation so a test can re-apply the same pre-fight setup.
func replay_final_snapshot(prepare: Callable = Callable()) -> String:
	var fresh := CombatSimulation.new()
	tree.root.add_child(fresh)
	fresh.start(request)
	await tree.physics_frame
	if prepare.is_valid():
		prepare.call(fresh)
	var index := 0
	var recorded: Array = server.record
	var target_tick: int = sim.server_tick
	while fresh.server_tick < target_tick and fresh.is_running():
		var next_tick := fresh.server_tick + 1
		while index < recorded.size() and int(recorded[index]["t"]) <= next_tick:
			var entry: Dictionary = recorded[index]
			if entry["k"] == "in":
				fresh.submit_input(entry["packet"])
			else:
				fresh.set_hit_grace(entry["p"], int(entry["g"]))
			index += 1
		fresh.step_tick()
	var out := JSON.stringify(fresh.snapshot(), "", true, true)
	fresh.stop()
	tree.root.remove_child(fresh)
	fresh.queue_free()
	return out


## Frees the battle AND breaks the reference cycles the harness/test lambdas create (server and client
## signals connected to closures that capture the harness, send callables that capture it back).
## Without this Godot reports leaked script resources at exit.
func dispose() -> void:
	for obj in [server] + clients:
		_disconnect_all(obj)
	for client in clients:
		client.send = Callable()
	for bot in bots:
		if bot != null:
			bot.hook = Callable()
	if sim != null:
		_disconnect_all(sim)
		sim.stop()
		if sim.get_parent() != null:
			sim.get_parent().remove_child(sim)
		sim.queue_free()
	clients.clear()
	bots = [null, null]
	c2s.clear()
	s2c.clear()


static func _disconnect_all(obj: Object) -> void:
	for sig in obj.get_signal_list():
		for connection in obj.get_signal_connection_list(sig["name"]):
			obj.disconnect(sig["name"], connection["callable"])
