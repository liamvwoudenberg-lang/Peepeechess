extends Node
## Combat sound playback: maps simulation events and fighter state changes to the procedurally generated SFX in
## res://assets/combat/audio (see tools/audio/generate_sfx.py), with hard voice caps, per-sound rate limits,
## variant rotation, priority voice stealing and light ducking. PRELOAD-ONLY (no class_name):
##
##   const CombatAudio := preload("res://combat/audio/combat_audio.gd")
##   var audio := CombatAudio.new(); add_child(audio)
##   audio.setup(arena_host_node3d, sim)      # connects sim.event_emitted / finished; call audio.poll() each frame (done in _process)
##   audio.attach_ui(menu_root)               # hover/click/confirm/back sounds for every BaseButton under it (idempotent)
##
## Presentation only. It never touches simulation state, never uses the simulation's RNG and uses its own seeded
## RandomNumberGenerator for cosmetic variation, so playing (or muting) sound cannot change a fight.
## Assets are loaded through ResourceLoader when imported, else the WAV bytes are parsed here (no editor import needed).

const MANIFEST_PATH := "res://assets/combat/audio/manifest.json"
const AUDIO_DIR := "res://assets/combat/audio/"
const SFX_BUS := "SFX"
const UI_BUS := "UI"

const MAX_WORLD_VOICES := 14
const MAX_FLAT_VOICES := 6
const MAX_SEEN_EVENTS := 96
## Damage at or above this counts as a "heavy" hit when the attack kind is unknown (presentation fallback).
const HEAVY_HIT_DAMAGE := 18
## A swing sound starts this many simulation ticks before the active window opens (matches the whoosh's onset).
const SWING_LEAD_TICKS := 3
const STRIDE_WALK_M := 1.45
const STRIDE_SPRINT_M := 2.1
const DUCK_MS := 220
const DUCK_DB := -7.0

const ROLE_MATERIAL := {"p": "leather", "n": "steel", "b": "flesh", "r": "plate", "q": "steel", "k": "steel"}
const ROLE_SWING := {"p": "swing_spear", "n": "swing_sword", "b": "swing_staff", "r": "swing_hammer", "q": "swing_dual", "k": "swing_king"}
const ROLE_ABILITY := {"p": "ability_last_stand", "n": "ability_lunge", "b": "ability_blink", "r": "ability_fortress", "q": "ability_fury", "k": "ability_counter"}
## Event types the simulation can emit and what we play for them ("" = deliberately silent; see sound_for_event).
const EVENT_TYPES := ["hit", "block", "guardbreak", "parry", "dodge", "ability", "whiff"]
const UI_NAMES := ["hover", "click", "confirm", "back"]

## sound -> [priority (higher steals lower), min interval ms, max simultaneous, base volume dB, flat (non-positional)]
const PROFILE := {
	"swing": [1, 45, 3, -2.0, false],
	"hit": [2, 25, 3, 0.0, false],
	"block": [2, 40, 2, -1.0, false],
	"guard_break": [3, 150, 1, 0.0, false],
	"parry": [3, 90, 2, 1.0, false],
	"dodge": [1, 120, 2, -3.0, false],
	"footstep": [0, 150, 3, -8.0, false],
	"stagger": [1, 120, 2, -4.0, false],
	"ability": [3, 150, 2, -1.0, false],
	"defeat": [3, 500, 1, 0.0, true],
	"victory": [3, 500, 1, 0.0, true],
	"countdown": [2, 200, 1, -3.0, true],
	"fight": [3, 500, 1, 0.0, true],
	"ui": [2, 30, 4, -6.0, true],
}

static var _library: Dictionary = {}  # sound name -> Array[AudioStream]
static var _manifest: Dictionary = {}


## Drops the decoded-sound cache. The cache is static, so without this the streams outlive the engine's
## shutdown cleanup ("resources still in use at exit"). Tests and the runner call it before quitting.
static func clear_library() -> void:
	_library.clear()
	_manifest.clear()

var sim = null
var host: Node3D = null
var local_player_id: String = ""
var muted: bool = false
var master_volume: float = 1.0
var sfx_volume: float = 1.0
var ui_volume: float = 1.0
## Injectable monotonic clock in milliseconds (tests replace it to exercise rate limits deterministically).
var clock: Callable = Callable(Time, "get_ticks_msec")
var stats: Dictionary = {"played": 0, "dropped_rate": 0, "dropped_cap": 0, "dropped_missing": 0, "dropped_muted": 0,
		"stolen": 0, "duplicate_events": 0, "by_sound": {}, "last_sound": ""}

var _world: Array[AudioStreamPlayer3D] = []
var _flat: Array[AudioStreamPlayer] = []
var _voice_info: Dictionary = {}  # player instance id -> [priority, sound name]
var _last_played: Dictionary = {}  # sound name -> ms
var _last_variant: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _seen: Array = []
var _duck_until: int = -1
var _swing_polling: bool = false
var _track: Dictionary = {}  # player_id -> {state, ticks, swung, last_pos, stride}
var _count_last: int = -1
var _phase_last: int = -1
var _ui_roots: Array[WeakRef] = []
var _tree_hooked: bool = false


# ---------------------------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------------------------
static func load_library(force: bool = false) -> Dictionary:
	if not _library.is_empty() and not force:
		return _library
	_library = {}
	_manifest = {}
	if not FileAccess.file_exists(MANIFEST_PATH):
		return _library
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return _library
	_manifest = parsed
	for sound_name in _manifest.get("sounds", {}):
		var streams: Array = []
		for file in _manifest["sounds"][sound_name].get("files", []):
			var stream := load_stream(AUDIO_DIR + String(file))
			if stream != null:
				streams.append(stream)
		if not streams.is_empty():
			_library[sound_name] = streams
	return _library


static func manifest() -> Dictionary:
	load_library()
	return _manifest


## Imported resource when available (exports), otherwise parse the WAV file bytes directly.
static func load_stream(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is AudioStream:
			return res
	if not FileAccess.file_exists(path):
		return null
	return parse_wav(FileAccess.get_file_as_bytes(path))


## Minimal RIFF/WAVE PCM16 parser -> AudioStreamWAV. Returns null for anything it does not understand.
static func parse_wav(bytes: PackedByteArray) -> AudioStreamWAV:
	if bytes.size() < 44 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF" or bytes.slice(8, 12).get_string_from_ascii() != "WAVE":
		return null
	var pos := 12
	var channels := 0
	var rate := 0
	var bits := 0
	var fmt_tag := 0
	var data := PackedByteArray()
	while pos + 8 <= bytes.size():
		var id := bytes.slice(pos, pos + 4).get_string_from_ascii()
		var size := bytes.decode_u32(pos + 4)
		var body := pos + 8
		if body + size > bytes.size():
			size = bytes.size() - body
		if id == "fmt " and size >= 16:
			fmt_tag = bytes.decode_u16(body)
			channels = bytes.decode_u16(body + 2)
			rate = bytes.decode_u32(body + 4)
			bits = bytes.decode_u16(body + 14)
		elif id == "data":
			data = bytes.slice(body, body + size)
		pos = body + size + (size & 1)
	if fmt_tag != 1 or bits != 16 or channels < 1 or channels > 2 or rate <= 0 or data.is_empty():
		return null
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = channels == 2
	stream.data = data
	return stream


static func has_sound(sound_name: String) -> bool:
	return load_library().has(sound_name)


static func variants_of(sound_name: String) -> int:
	return (load_library().get(sound_name, []) as Array).size()


# ---------------------------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------------------------
func _init() -> void:
	_rng.seed = 90210
	name = "CombatAudio"


func _ready() -> void:
	_ensure_buses()
	_build_pools()
	if OS.get_cmdline_user_args().has("--mute") or OS.get_cmdline_args().has("--mute"):
		muted = true
	load_library()
	_apply_volumes()


## `host_node` is where positional voices live (usually the arena); `simulation` is optional (a presentation without
## one can still call on_event / play_ui). Safe to call again: it rewires cleanly.
func setup(host_node: Node3D, simulation = null) -> void:
	_ensure_buses()
	if not is_inside_tree() and host_node != null and host_node.is_inside_tree():
		host_node.add_child(self)
	host = host_node
	_build_pools()
	_disconnect_sim()
	sim = simulation
	_swing_polling = sim != null
	_track.clear()
	_seen.clear()
	_count_last = -1
	_phase_last = -1
	if sim != null:
		if sim.has_signal("event_emitted") and not sim.event_emitted.is_connected(on_event):
			sim.event_emitted.connect(on_event)
		if sim.has_signal("finished") and not sim.finished.is_connected(_on_finished):
			sim.finished.connect(_on_finished)
	load_library()
	_apply_volumes()
	set_process(sim != null)


func _disconnect_sim() -> void:
	if sim != null and is_instance_valid(sim):
		if sim.event_emitted.is_connected(on_event):
			sim.event_emitted.disconnect(on_event)
		if sim.finished.is_connected(_on_finished):
			sim.finished.disconnect(_on_finished)
	sim = null


func _exit_tree() -> void:
	_disconnect_sim()
	release_voices()


## Stops every pooled voice and drops its stream so no decoded sound (or playback) is kept alive by a node that is
## leaving the tree; otherwise the engine reports "resources still in use at exit".
func release_voices() -> void:
	for p in _world:
		if is_instance_valid(p):
			p.stop()
			p.stream = null
	for p in _flat:
		if is_instance_valid(p):
			p.stop()
			p.stream = null


func _build_pools() -> void:
	var parent: Node = host if host != null and is_instance_valid(host) else self
	if _world.is_empty():
		for i in MAX_WORLD_VOICES:
			var p := AudioStreamPlayer3D.new()
			p.bus = SFX_BUS
			p.unit_size = 7.0
			p.max_distance = 45.0
			p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
			p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
			p.name = "Voice3D%d" % i
			parent.add_child(p)
			_world.append(p)
	if _flat.is_empty():
		for i in MAX_FLAT_VOICES:
			var p := AudioStreamPlayer.new()
			p.bus = SFX_BUS
			p.name = "VoiceFlat%d" % i
			add_child(p)
			_flat.append(p)
	# A new host (after a rematch the arena is reused, but tests may swap hosts): re-parent pooled voices.
	for p in _world:
		if p.get_parent() != parent and is_instance_valid(parent):
			if p.get_parent() != null:
				p.get_parent().remove_child(p)
			parent.add_child(p)


static func _ensure_buses() -> void:
	for bus_name in [SFX_BUS, UI_BUS]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.get_bus_count() - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")
			if bus_name == SFX_BUS:
				var limiter := AudioEffectLimiter.new()
				limiter.ceiling_db = -1.0
				limiter.threshold_db = -6.0
				AudioServer.add_bus_effect(idx, limiter)


func voice_capacity() -> int:
	return _world.size() + _flat.size()


# ---------------------------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------------------------
func set_volumes(master: float, sfx: float = -1.0, ui: float = -1.0) -> void:
	master_volume = clampf(master, 0.0, 1.0)
	if sfx >= 0.0:
		sfx_volume = clampf(sfx, 0.0, 1.0)
	if ui >= 0.0:
		ui_volume = clampf(ui, 0.0, 1.0)
	_apply_volumes()


func set_muted(value: bool) -> void:
	muted = value
	if muted:
		for p in _world:
			p.stop()
		for p in _flat:
			p.stop()
		_voice_info.clear()


func _apply_volumes() -> void:
	var sfx := AudioServer.get_bus_index(SFX_BUS)
	var ui := AudioServer.get_bus_index(UI_BUS)
	var user_mix: Dictionary = Engine.get_meta("ui_mix", {})  # the player's mixer levels from Settings (res://ui/theme/ui_prefs.gd)
	if sfx != -1:
		AudioServer.set_bus_volume_db(sfx, linear_to_db(maxf(master_volume * sfx_volume * float(user_mix.get("sfx", 1.0)), 0.0001)))
	if ui != -1:
		AudioServer.set_bus_volume_db(ui, linear_to_db(maxf(master_volume * ui_volume * float(user_mix.get("ui", 1.0)), 0.0001)))


# ---------------------------------------------------------------------------------------------
# Event mapping
# ---------------------------------------------------------------------------------------------
func _role_of(player_id: String) -> String:
	if sim != null and is_instance_valid(sim) and sim.has_method("fighter_by_id"):
		var f = sim.fighter_by_id(player_id)
		if f != null:
			return String(f.role)
	return "n"


## Pure mapping from a simulation/contract event to a sound name ("" = silent). Never random.
##   hit -> hit_<target material>_<light|heavy>   block -> block   guardbreak -> guard_break   parry -> parry
##   ability -> the actor's signature ability sound   whiff -> the actor's weapon swing
##   dodge (an attack passing through an invulnerable dodger) -> "" : the dodge whoosh is played when the dodge STARTS.
func sound_for_event(event: Dictionary) -> String:
	match String(event.get("type", "")):
		"hit":
			var target_role := _role_of(String(event.get("targetPlayerId", "")))
			var heavy := int(event.get("damage", 0)) >= HEAVY_HIT_DAMAGE
			if sim != null and is_instance_valid(sim) and sim.has_method("fighter_by_id"):
				var actor = sim.fighter_by_id(String(event.get("actorPlayerId", "")))
				if actor != null and actor.sm.attack != null:
					heavy = actor.sm.attack.kind != AttackDefinition.Kind.LIGHT
			return "hit_%s_%s" % [ROLE_MATERIAL.get(target_role, "steel"), "heavy" if heavy else "light"]
		"block":
			return "block"
		"guardbreak":
			return "guard_break"
		"parry":
			return "parry"
		"ability":
			return String(ROLE_ABILITY.get(_role_of(String(event.get("actorPlayerId", ""))), ""))
		"whiff":
			return String(ROLE_SWING.get(_role_of(String(event.get("actorPlayerId", ""))), ""))
		_:
			return ""


func on_event(event: Dictionary) -> void:
	var id := int(event.get("eventId", -1))
	if id >= 0:
		if id in _seen:
			stats["duplicate_events"] += 1
			return
		_seen.append(id)
		if _seen.size() > MAX_SEEN_EVENTS:
			_seen.pop_front()
	var type := String(event.get("type", ""))
	if type == "whiff" and _swing_polling:
		return  # the swing whoosh was already played when the attack approached its active window
	var sound := sound_for_event(event)
	if sound == "":
		return
	var where := _fighter_position(String(event.get("targetPlayerId", "")) if type in ["hit", "block", "guardbreak", "parry"] else String(event.get("actorPlayerId", "")))
	var pitch := 1.0
	if type == "hit" and sound.ends_with("heavy"):
		pitch = 0.96
	_play(sound, where, pitch)
	# Layering (same sample library, different pitch): a heavy blow and a guard break get a low body thud under the
	# impact, a parry gets a high, short ring over it. Rate limits and voice caps still apply per sound.
	if type == "hit" and sound.ends_with("heavy") and has_sound("stagger"):
		_play("stagger", where, 0.78)
	elif type == "guardbreak" and has_sound("stagger"):
		_play("stagger", where, 0.7)
	elif type == "parry" and has_sound("block"):
		_play("block", where, 1.7)


func _on_finished(result: Dictionary) -> void:
	on_battle_finished(result)


## Victory fanfare for the winner (or the viewer when local_player_id is empty), defeat sting for the loser, nothing for a draw.
func on_battle_finished(result: Dictionary) -> void:
	var winner := String(result.get("winnerPlayerId", ""))
	if String(result.get("outcome", "")) == "draw" or winner == "":
		return
	if local_player_id != "" and winner != local_player_id:
		play_defeat()
	else:
		play_victory()


func play_victory() -> void:
	_play("victory", Vector3.ZERO)


func play_defeat() -> void:
	_play("defeat", Vector3.ZERO)


func play_ui(ui_name: String) -> void:
	var sound := ui_name if ui_name.begins_with("ui_") else "ui_" + ui_name
	_play(sound, Vector3.ZERO)


func _fighter_position(player_id: String) -> Vector3:
	if sim != null and is_instance_valid(sim) and sim.has_method("fighter_by_id"):
		var f = sim.fighter_by_id(player_id)
		if f != null and f.is_inside_tree():
			return f.global_position + Vector3(0.0, 1.1, 0.0)
	return Vector3.ZERO


# ---------------------------------------------------------------------------------------------
# State-driven sounds (swings, footsteps, dodge, stagger, countdown). Called every frame from _process.
# ---------------------------------------------------------------------------------------------
func _process(_delta: float) -> void:
	poll()


func poll() -> void:
	if sim == null or not is_instance_valid(sim):
		return
	_poll_phase()
	for f in sim.fighters:
		if f != null and is_instance_valid(f):
			_poll_fighter(f)


func _poll_phase() -> void:
	var phase: int = sim.phase
	if phase == CombatSimulation.Phase.COUNTDOWN:
		var second: int = int(ceil(float(sim.countdown_remaining) / float(CombatConstants.TICK_RATE)))
		if second != _count_last and second >= 1 and second <= 3:
			_play("countdown_tick", Vector3.ZERO)
		_count_last = second
	if _phase_last == CombatSimulation.Phase.COUNTDOWN and phase == CombatSimulation.Phase.ACTIVE:
		_play("fight_cue", Vector3.ZERO)
	_phase_last = phase


func _poll_fighter(f) -> void:
	var tr: Dictionary = _track.get(f.player_id, {})
	var state: int = f.sm.state
	var ticks: int = f.sm.state_ticks
	var prev_state: int = int(tr.get("state", -1))
	var prev_ticks: int = int(tr.get("ticks", 0))
	var pos: Vector3 = f.global_position
	var at: Vector3 = pos + Vector3(0.0, 1.0, 0.0)
	if tr.is_empty():
		tr = {"swung": false, "last_pos": pos, "stride": 0.0}
	# New attack (state entered, or the combo advanced inside ATTACKING: state_ticks restarts) -> re-arm the swing sound.
	if state != prev_state or ticks < prev_ticks:
		tr["swung"] = false
		match state:
			S.DODGING:
				_play("dodge", at)
			S.STAGGERED:
				if f.sm.stun_kind == "hit":
					_play("stagger", at)
	if not tr["swung"] and f.sm.attack != null and (state == S.ATTACKING or state == S.ABILITY_CASTING):
		var window: Vector2i = f.sm.attack.active_window(f.sm.attack_total)
		if ticks >= window.x - SWING_LEAD_TICKS:
			tr["swung"] = true
			# Ability swings (Lunging Strike) have their own cast sound from the "ability" event; ordinary swings whoosh.
			if state == S.ATTACKING:
				_play(String(ROLE_SWING.get(f.role, "swing_sword")), at)
	# Footsteps: one per stride of horizontal travel while walking/sprinting.
	if state == S.MOVING:
		tr["stride"] = float(tr["stride"]) + Vector2(pos.x - tr["last_pos"].x, pos.z - tr["last_pos"].z).length()
		var stride := STRIDE_SPRINT_M if f.sprinting else STRIDE_WALK_M
		if float(tr["stride"]) >= stride:
			tr["stride"] = 0.0
			_play("footstep_stone", pos)
	else:
		tr["stride"] = 0.0
	tr["state"] = state
	tr["ticks"] = ticks
	tr["last_pos"] = pos
	_track[f.player_id] = tr


const S := CombatConstants.State


# ---------------------------------------------------------------------------------------------
# Playback core
# ---------------------------------------------------------------------------------------------
func _category(sound: String) -> String:
	if sound.begins_with("swing_"):
		return "swing"
	if sound.begins_with("hit_"):
		return "hit"
	if sound.begins_with("footstep"):
		return "footstep"
	if sound.begins_with("ability_"):
		return "ability"
	if sound.begins_with("ui_"):
		return "ui"
	if sound == "countdown_tick":
		return "countdown"
	if sound == "fight_cue":
		return "fight"
	return sound if PROFILE.has(sound) else "hit"


func _pick(sound: String) -> AudioStream:
	var list: Array = load_library().get(sound, [])
	if list.is_empty():
		return null
	var idx := 0
	if list.size() > 1:
		idx = _rng.randi() % list.size()
		if idx == int(_last_variant.get(sound, -1)):
			idx = (idx + 1 + (_rng.randi() % (list.size() - 1))) % list.size()
	_last_variant[sound] = idx
	return list[idx]


## Returns true when a voice was started. Applies mute, rate limit, simultaneous cap, voice stealing and ducking.
func _play(sound: String, where: Vector3, pitch: float = 1.0, extra_db: float = 0.0) -> bool:
	if muted:
		stats["dropped_muted"] += 1
		return false
	var stream := _pick(sound)
	if stream == null:
		stats["dropped_missing"] += 1
		return false
	var category := _category(sound)
	var prof: Array = PROFILE[category]
	var priority: int = prof[0]
	var now: int = int(clock.call())
	if now - int(_last_played.get(sound, -100000)) < int(prof[1]):
		stats["dropped_rate"] += 1
		return false
	if priority == 0 and now < _duck_until:
		stats["dropped_rate"] += 1  # low-priority sounds (footsteps) yield while a big sound is ringing
		return false
	if _simultaneous(sound) >= int(prof[2]):
		stats["dropped_cap"] += 1
		return false
	var flat: bool = prof[4]
	var voice = _free_voice(flat, priority)
	if voice == null:
		stats["dropped_cap"] += 1
		return false
	var volume := float(prof[3]) + extra_db + _rng.randf_range(-0.8, 0.8)
	if priority <= 1 and now < _duck_until:
		volume += DUCK_DB
	voice.stream = stream
	voice.pitch_scale = pitch * _rng.randf_range(0.97, 1.03)
	voice.volume_db = volume
	if flat:
		voice.bus = UI_BUS if category == "ui" else SFX_BUS
	else:
		voice.global_position = where if voice.is_inside_tree() else voice.position
	voice.play()
	_voice_info[voice.get_instance_id()] = [priority, sound, now, int(stream.get_length() * 1000.0 / maxf(voice.pitch_scale, 0.1)) + 30]
	_last_played[sound] = now
	if priority >= 3:
		_duck_until = now + DUCK_MS
	stats["played"] += 1
	stats["last_sound"] = sound
	var by: Dictionary = stats["by_sound"]
	by[sound] = int(by.get(sound, 0)) + 1
	return true


## A voice is busy while the engine says it plays AND the (injectable) clock says its sound has not run out yet.
func _busy(p, now: int) -> bool:
	if not p.playing:
		return false
	var info: Array = _voice_info.get(p.get_instance_id(), [])
	return info.is_empty() or now < int(info[2]) + int(info[3])


func _simultaneous(sound: String) -> int:
	var n := 0
	var now: int = int(clock.call())
	for pool in [_world, _flat]:
		for p in pool:
			if _busy(p, now) and _voice_info[p.get_instance_id()][1] == sound:
				n += 1
	return n


func _free_voice(flat: bool, priority: int):
	var pool: Array = _flat if flat else _world
	var weakest = null
	var weakest_priority := 99
	var now: int = int(clock.call())
	for p in pool:
		if not _busy(p, now):
			return p
		var pr: int = int(_voice_info.get(p.get_instance_id(), [0, ""])[0])
		if pr < weakest_priority:
			weakest_priority = pr
			weakest = p
	if weakest != null and weakest_priority < priority:
		weakest.stop()
		stats["stolen"] += 1
		return weakest
	return null


func active_voices() -> int:
	var n := 0
	for pool in [_world, _flat]:
		for p in pool:
			if p.playing:
				n += 1
	return n


# ---------------------------------------------------------------------------------------------
# UI hookup
# ---------------------------------------------------------------------------------------------
const CONFIRM_WORDS := ["fight", "start", "play", "confirm", "ok", "ready", "rematch", "continue", "join", "host"]
const BACK_WORDS := ["back", "menu", "cancel", "quit", "exit", "close", "leave", "pause"]


static func classify_button(text: String) -> String:
	var t := text.strip_edges().to_lower()
	for w in BACK_WORDS:
		if t.begins_with(w) or t.contains(" " + w):
			return "back"
	for w in CONFIRM_WORDS:
		if t.begins_with(w) or t.contains(" " + w):
			return "confirm"
	return "click"


## Adds hover/click/confirm/back sounds to every BaseButton under `root` (and to buttons added later). Idempotent.
func attach_ui(root: Node) -> int:
	if root == null:
		return 0
	var already := false
	for r in _ui_roots:
		if r.get_ref() == root:
			already = true
	if not already:
		_ui_roots.append(weakref(root))
	var added := 0
	if root is BaseButton:
		added += int(_hook_button(root))
	for b in root.find_children("*", "BaseButton", true, false):
		added += int(_hook_button(b))
	if not _tree_hooked and root.is_inside_tree():
		_tree_hooked = true
		root.get_tree().node_added.connect(_on_node_added)
	return added


func _hook_button(b: BaseButton) -> bool:
	if b.has_meta("_combat_audio_ui"):
		return false
	b.set_meta("_combat_audio_ui", true)
	b.mouse_entered.connect(func(): play_ui("hover"))
	b.focus_entered.connect(func(): play_ui("hover"))
	b.pressed.connect(func(): play_ui(classify_button(b.text if "text" in b else "")))
	return true


func _on_node_added(node: Node) -> void:
	if not (node is BaseButton):
		return
	for r in _ui_roots:
		var root = r.get_ref()
		if root != null and root.is_ancestor_of(node):
			_hook_button(node)
			return
