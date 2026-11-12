extends RefCounted
## Deterministic unreliable-channel simulator for tests (one direction per instance).
## Time is the integer 60 Hz tick (1 tick = 16.667 ms). Everything random comes from a seeded RNG,
## so a given (config, seed, send schedule) always delivers the same messages on the same ticks.
##   latency_ticks   fixed one-way delay            jitter_ticks   uniform extra delay in [-j, +j]
##   loss            drop probability                reorder_chance probability a packet gets extra delay
##   reorder_extra   extra delay 1..N ticks for reordered packets
##   duplicate_chance probability a packet is delivered twice (second copy a tick later)
## Messages are deep-copied on send so the sender can never mutate what is "on the wire".

const TICK_MS := 1000.0 / 60.0

var latency_ticks: int = 0
var jitter_ticks: int = 0
var loss: float = 0.0
var reorder_chance: float = 0.0
var reorder_extra: int = 4
var duplicate_chance: float = 0.0
var rng := RandomNumberGenerator.new()

var sent: int = 0
var dropped: int = 0
var delivered: int = 0
var duplicated: int = 0
var reordered: int = 0

var _queue: Array = []
var _seq: int = 0
var _max_delivered_seq: int = -1


static func ms_to_ticks(ms: float) -> int:
	return int(round(ms / TICK_MS))


func configure(p_latency_ticks: int, p_jitter_ticks: int = 0, p_loss: float = 0.0, p_reorder: float = 0.0,
		p_duplicate: float = 0.0, seed_value: int = 1) -> void:
	latency_ticks = p_latency_ticks
	jitter_ticks = p_jitter_ticks
	loss = p_loss
	reorder_chance = p_reorder
	duplicate_chance = p_duplicate
	rng.seed = seed_value


func send(message: Variant, now: int) -> void:
	sent += 1
	if loss > 0.0 and rng.randf() < loss:
		dropped += 1
		return
	var delay := latency_ticks
	if jitter_ticks > 0:
		delay += rng.randi_range(-jitter_ticks, jitter_ticks)
	if reorder_chance > 0.0 and rng.randf() < reorder_chance:
		delay += rng.randi_range(1, maxi(1, reorder_extra))
	delay = maxi(0, delay)
	_seq += 1
	_queue.append({"at": now + delay, "seq": _seq, "msg": _copy(message)})
	if duplicate_chance > 0.0 and rng.randf() < duplicate_chance:
		duplicated += 1
		_queue.append({"at": now + delay + 1, "seq": _seq, "msg": _copy(message)})


## Messages due at or before `now`, in delivery order (by due tick, then send order).
func poll(now: int) -> Array:
	var due: Array = []
	var rest: Array = []
	for entry in _queue:
		if int(entry["at"]) <= now:
			due.append(entry)
		else:
			rest.append(entry)
	_queue = rest
	due.sort_custom(func(a, b): return int(a["at"]) < int(b["at"]) or (int(a["at"]) == int(b["at"]) and int(a["seq"]) < int(b["seq"])))
	var out: Array = []
	for entry in due:
		delivered += 1
		if int(entry["seq"]) < _max_delivered_seq:
			reordered += 1
		_max_delivered_seq = maxi(_max_delivered_seq, int(entry["seq"]))
		out.append(entry["msg"])
	return out


func in_flight() -> int:
	return _queue.size()


static func _copy(message: Variant) -> Variant:
	return message.duplicate(true) if (message is Dictionary or message is Array) else message
