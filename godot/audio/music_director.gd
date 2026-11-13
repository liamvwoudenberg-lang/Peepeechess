extends Node
## Peepeechess score and ambience: a small set of seamless, procedurally generated loops (no audio files, nothing
## downloaded) that are cross-faded by game state, plus two stingers and an error cue. PRELOAD-ONLY (no class_name):
##
##   const Music := preload("res://audio/music_director.gd")
##   Music.go(get_tree(), "menu")             # opening | menu | board | preview | pit | combat | victory | defeat | silent
##   Music.intensity(get_tree(), 0.0 .. 1.0)  # combat only: drums and tension rise as the fight gets dangerous
##
## Layers (each one loop of LOOP_SECONDS, all started together so they stay in phase):
##   pad      D-minor drone, slowly breathing          wind     low filtered noise, slow gusts
##   torch    sparse fire crackle                       rumble   stone resonance of the pit
##   tension  a dissonant minor-second cluster          drum_slow heartbeat war drum (60 bpm)
##   drum_fast  double-time war drum (120 bpm)
## Every loop's frequencies are multiples of 1/LOOP_SECONDS, so the seam is exact. Each layer is normalised to a
## fixed peak and the Music bus carries a limiter, so no state can clip. Presentation only: it never reads or
## changes game state (combat intensity is fed from outside) and runs nothing in headless mode (no audio device).
const RATE := 22050
const LOOP_SECONDS := 8.0
const PEAK := 0.16
const FADE_PER_SECOND := 0.85   # gain change per second: a full cross-fade takes ~1.2 s
const BUS := "Music"
const LAYERS := ["pad", "wind", "torch", "rumble", "tension", "drum_slow", "drum_fast"]
const STATES := ["silent", "opening", "menu", "board", "preview", "pit", "combat", "victory", "defeat"]
## state -> layer -> target gain (0..1). Layers not listed fade to silence.
const MIX := {
	"silent": {},
	"opening": {"pad": 0.8, "wind": 0.5, "torch": 0.35},
	"menu": {"pad": 0.65, "wind": 0.25, "torch": 0.3},
	"board": {"pad": 0.32, "wind": 0.14, "torch": 0.12},
	"preview": {"pad": 0.5, "tension": 0.35, "drum_slow": 0.4, "wind": 0.15},
	"pit": {"pad": 0.4, "tension": 0.5, "drum_slow": 0.6, "rumble": 0.6, "wind": 0.2},
	"combat": {"pad": 0.3, "tension": 0.3, "drum_slow": 0.5, "rumble": 0.3},
	"victory": {"pad": 0.45, "torch": 0.2},
	"defeat": {"pad": 0.25, "rumble": 0.35, "wind": 0.3},
}
const STINGERS := ["victory", "defeat", "error"]

static var force := false   # tests: build the audio nodes even without an audio device
static var _cache: Dictionary = {}
static var _gen_thread: Thread = null

var state: String = "silent"
var combat_intensity: float = 0.0
var music_volume: float = 1.0
var gains: Dictionary = {}     # layer -> current linear gain
var targets: Dictionary = {}   # layer -> target linear gain
var active: bool = false       # true once players exist
var _players: Dictionary = {}
var _stinger_player: AudioStreamPlayer
var _ready_streams: bool = false


static func audible() -> bool:
	return force or DisplayServer.get_name() != "headless"


# ---- API ---------------------------------------------------------------------------------------------------
## The director node under the SceneTree root (created on first use; null in headless runs unless `force`).
static func instance(tree: SceneTree) -> Node:
	if tree == null:
		return null
	var existing := tree.root.get_node_or_null("MusicDirector")
	if existing != null:
		return existing
	if not audible():
		return null
	var node: Node = load("res://audio/music_director.gd").new()
	node.name = "MusicDirector"
	tree.root.add_child(node)
	return node


static func go(tree: SceneTree, new_state: String) -> void:
	var node := instance(tree)
	if node != null:
		node.set_state(new_state)


static func intensity(tree: SceneTree, value: float) -> void:
	var node := instance(tree)
	if node != null:
		node.set_intensity(value)


static func error_cue(tree: SceneTree) -> void:
	var node := instance(tree)
	if node != null:
		node.play_stinger("error")


## Combat danger 0..1 from the two fighters' health fractions: the lower of the two, with a ramp that starts at 80%.
static func danger_from_health(hp_fraction_a: float, hp_fraction_b: float) -> float:
	var low := minf(clampf(hp_fraction_a, 0.0, 1.0), clampf(hp_fraction_b, 0.0, 1.0))
	return clampf((0.8 - low) / 0.8, 0.0, 1.0)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_state_targets()
	if audible():
		_build_bus()
		_start_generation()


func set_state(new_state: String) -> void:
	if not (new_state in STATES) or new_state == state:
		return
	state = new_state
	_apply_state_targets()
	if new_state == "victory" or new_state == "defeat":
		play_stinger(new_state)


func set_intensity(value: float) -> void:
	combat_intensity = clampf(value, 0.0, 1.0)
	_apply_state_targets()


## Target gains for the current state; in combat the drums and tension follow the intensity.
func _apply_state_targets() -> void:
	targets = {}
	for layer in LAYERS:
		targets[layer] = float(MIX[state].get(layer, 0.0))
	if state == "combat":
		var i := combat_intensity
		targets["tension"] = 0.3 + 0.55 * i
		targets["drum_slow"] = 0.55 * (1.0 - 0.6 * i)
		targets["drum_fast"] = 0.95 * i
		targets["pad"] = 0.3 - 0.12 * i
	for layer in LAYERS:
		if not gains.has(layer):
			gains[layer] = 0.0


## Moves every gain toward its target (called from _process; tests call it with fixed deltas).
func step(delta: float) -> void:
	for layer in LAYERS:
		gains[layer] = move_toward(float(gains.get(layer, 0.0)), float(targets.get(layer, 0.0)), FADE_PER_SECOND * delta)
		var player: AudioStreamPlayer = _players.get(layer)
		if player != null:
			var linear := float(gains[layer]) * music_volume
			player.volume_db = linear_to_db(maxf(linear, 0.00001))


func _process(delta: float) -> void:
	_poll_generation()
	step(delta)


func play_stinger(stinger_name: String) -> void:
	if _stinger_player == null or not (stinger_name in STINGERS):
		return
	var stream = _cache.get("stinger_" + stinger_name)
	if stream == null:
		return
	_stinger_player.stream = stream
	_stinger_player.volume_db = linear_to_db(maxf(music_volume, 0.00001)) - 2.0
	_stinger_player.play()


func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)


# ---- bus and players -----------------------------------------------------------------------------------------
func _build_bus() -> void:
	if AudioServer.get_bus_index(BUS) == -1:
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, BUS)
		AudioServer.set_bus_send(index, "Master")
		AudioServer.add_bus_effect(index, AudioEffectLimiter.new())
	for layer in LAYERS:
		var p := AudioStreamPlayer.new()
		p.bus = BUS
		p.volume_db = -80.0
		add_child(p)
		_players[layer] = p
	_stinger_player = AudioStreamPlayer.new()
	_stinger_player.bus = BUS
	add_child(_stinger_player)


func _start_generation() -> void:
	if not _cache.is_empty():
		_attach_streams()
		return
	_gen_thread = Thread.new()
	_gen_thread.start(_generate_into_cache)


func _generate_into_cache() -> void:
	var made := generate_all()
	_cache = made


func _poll_generation() -> void:
	if _ready_streams or _gen_thread == null:
		if not _ready_streams and _gen_thread == null and not _cache.is_empty() and not _players.is_empty():
			_attach_streams()
		return
	if not _gen_thread.is_alive():
		_gen_thread.wait_to_finish()
		_gen_thread = null
		_attach_streams()


func _attach_streams() -> void:
	if _ready_streams or _players.is_empty():
		return
	_ready_streams = true
	for layer in LAYERS:
		_players[layer].stream = _cache["layer_" + layer]
	for layer in LAYERS:
		_players[layer].play()   # started together: the loops are the same length, so they stay in phase
	active = true


func _exit_tree() -> void:
	if _gen_thread != null:
		_gen_thread.wait_to_finish()
		_gen_thread = null
	for p in _players.values():
		p.stop()
		p.stream = null
	if _stinger_player != null:
		_stinger_player.stop()
		_stinger_player.stream = null
	_cache.clear()


# ---- synthesis (pure, deterministic) ----------------------------------------------------------------------------
## All streams: {"layer_<name>": loop, "stinger_victory"/"stinger_defeat"/"stinger_error": one-shot}.
static func generate_all(seconds: float = LOOP_SECONDS) -> Dictionary:
	var out := {}
	for layer in LAYERS:
		out["layer_" + layer] = to_loop(layer_samples(layer, seconds))
	for s in STINGERS:
		out["stinger_" + s] = to_stream(stinger_samples(s), false)
	return out


static func _snap(freq: float, seconds: float) -> float:
	return roundf(freq * seconds) / seconds   # a whole number of cycles per loop: the seam is exact


static func layer_samples(layer: String, seconds: float = LOOP_SECONDS) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("peepeechess-" + layer)
	match layer:
		"pad":
			var notes := [73.42, 110.0, 146.83, 174.61]   # D2 A2 D3 F3: D minor
			var w := [1.0, 0.8, 0.7, 0.45]
			for k in notes.size():
				var f := _snap(notes[k], seconds)
				var f2 := f + 1.0 / seconds * 2.0   # slow beating against a detuned twin
				for i in n:
					var t := float(i) / RATE
					var lfo := 0.65 + 0.35 * sin(TAU * (1.0 / seconds) * (k + 1) * t)
					var s := sin(TAU * f * t) + 0.45 * sin(TAU * 2.0 * f * t) + sin(TAU * f2 * t) * 0.6
					buf[i] += s * w[k] * lfo
		"tension":
			for f0: float in [440.0, 466.16, 659.25]:   # A4 Bb4 E5: a minor second that never resolves
				var f := _snap(f0, seconds)
				var trem := _snap(5.0, seconds)
				for i in n:
					var t := float(i) / RATE
					var s := sin(TAU * f * t) + 0.35 * sin(TAU * 2.0 * f * t)
					buf[i] += s * (0.6 + 0.4 * sin(TAU * trem * t)) * 0.5
		"rumble":
			for f0: float in [41.2, 55.0, 61.7]:
				var f := _snap(f0, seconds)
				for i in n:
					var t := float(i) / RATE
					buf[i] += sin(TAU * f * t) * (0.7 + 0.3 * sin(TAU * 2.0 / seconds * t + f))
			_one_pole_noise(buf, rng, 0.02, 0.35, true)
		"wind":
			_one_pole_noise(buf, rng, 0.012, 1.0, false)
			for i in n:   # slow gusts: whole cycles per loop
				var t := float(i) / RATE
				buf[i] *= 0.45 + 0.55 * (0.5 + 0.5 * sin(TAU * 2.0 / seconds * t)) * (0.7 + 0.3 * sin(TAU * 3.0 / seconds * t + 1.0))
		"torch":
			_one_pole_noise(buf, rng, 0.3, 0.05, false)   # faint hiss
			var clicks := int(seconds * 14.0)
			for c in clicks:
				var at := rng.randi_range(0, n - 1)
				var amp := rng.randf_range(0.25, 1.0)
				var decay := rng.randf_range(120.0, 600.0)
				var tone := rng.randf_range(900.0, 3200.0)
				for j in int(RATE * 0.04):
					var tt := float(j) / RATE
					buf[(at + j) % n] += amp * exp(-tt * decay) * sin(TAU * tone * tt) * (1.0 if rng.randf() > 0.15 else -1.0)
		"drum_slow":
			for beat in int(seconds):
				_kick(buf, int(beat * RATE), 1.0, 95.0, 42.0, 9.0)
				_kick(buf, int((beat + 0.27) * RATE), 0.45, 80.0, 38.0, 11.0)   # the second thump of a heartbeat
		"drum_fast":
			var beats := int(seconds * 2.0)
			for beat in beats:
				var accent := 1.0 if beat % 4 == 0 else (0.7 if beat % 2 == 0 else 0.45)
				_kick(buf, int(beat * 0.5 * RATE), accent, 110.0, 46.0, 10.0)
			for beat in int(seconds):
				_kick(buf, int((beat + 0.75) * RATE), 0.35, 130.0, 60.0, 16.0)
	_normalise(buf, PEAK)
	return buf


static func _kick(buf: PackedFloat32Array, start: int, amp: float, f_start: float, f_end: float, decay: float) -> void:
	var n := buf.size()
	var length := int(RATE * 0.5)
	var phase := 0.0
	for j in length:
		var t := float(j) / RATE
		var f := f_end + (f_start - f_end) * exp(-t * 28.0)
		phase += TAU * f / RATE
		buf[(start + j) % n] += amp * sin(phase) * exp(-t * decay)


## Low-passed white noise (one pole). `coefficient` small = darker. Seamless loop: n + fade samples are generated and the
## extra tail is cross-faded into the head, so the sample after the last one continues the noise exactly.
static func _one_pole_noise(buf: PackedFloat32Array, rng: RandomNumberGenerator, coefficient: float, gain: float, add: bool) -> void:
	var n := buf.size()
	var fade := int(RATE * 0.4)
	var y := 0.0
	var noise := PackedFloat32Array()
	noise.resize(n + fade)
	for i in n + fade:
		y += coefficient * (rng.randf_range(-1.0, 1.0) - y)
		noise[i] = y
	for i in n:
		var v := noise[i]
		if i < fade:
			var a := float(i) / fade
			v = noise[i] * sqrt(a) + noise[n + i] * sqrt(1.0 - a)
		buf[i] = (buf[i] if add else 0.0) + v * gain * 12.0


static func _normalise(buf: PackedFloat32Array, peak: float) -> void:
	var m := 0.0001
	for v in buf:
		m = maxf(m, absf(v))
	var k := peak / m
	for i in buf.size():
		buf[i] *= k


static func stinger_samples(kind: String) -> PackedFloat32Array:
	var seconds := 3.2 if kind != "error" else 0.45
	var n := int(seconds * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	match kind:
		"victory":   # D minor opening into a bright D major swell with bell partials
			for f0: float in [146.83, 220.0, 293.66, 369.99, 587.33]:
				for i in n:
					var t := float(i) / RATE
					var env := minf(t / 0.35, 1.0) * exp(-maxf(t - 0.8, 0.0) * 0.9)
					var s := sin(TAU * f0 * t) + 0.4 * sin(TAU * f0 * 2.0 * t) + 0.2 * sin(TAU * f0 * 2.76 * t) * exp(-t * 2.0)
					buf[i] += s * env
		"defeat":    # a falling, detuned minor drone that collapses
			for f0: float in [98.0, 116.54, 146.83]:
				for i in n:
					var t := float(i) / RATE
					var f := f0 * (1.0 - 0.18 * (t / seconds))
					var env := minf(t / 0.12, 1.0) * exp(-t * 1.1)
					buf[i] += (sin(TAU * f * t) + 0.5 * sin(TAU * f * 1.51 * t)) * env
		"error":     # a short dull double knock
			for i in n:
				var t := float(i) / RATE
				var hit := exp(-t * 28.0) * sin(TAU * 170.0 * t)
				var t2 := t - 0.11
				if t2 > 0.0:
					hit += 0.8 * exp(-t2 * 28.0) * sin(TAU * 140.0 * t2)
				buf[i] = hit
	_normalise(buf, 0.35)
	var fade := mini(int(RATE * 0.05), n)
	for i in fade:   # tiny fade-out so a stinger never ends on a click
		buf[n - 1 - i] *= float(i) / fade
	return buf


static func to_stream(samples: PackedFloat32Array, looped: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = bytes
	if looped:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	return stream


static func to_loop(samples: PackedFloat32Array) -> AudioStreamWAV:
	return to_stream(samples, true)
