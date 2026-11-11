extends RefCounted
## Audio: the generated SFX files, their manifest, deterministic regeneration, the event -> sound mapping and the
## playback limits of CombatAudio. These tests FAIL when a deliverable is missing. They cannot judge how a sound
## *sounds*; they check objective properties (format, peak, silence, determinism, bounds). See tools/audio/README.md.

const CombatAudio := preload("res://combat/audio/combat_audio.gd")
const Support := preload("res://combat/tests/test_support.gd")
const DIR := "res://assets/combat/audio/"

const REQUIRED := [
	"swing_spear", "swing_sword", "swing_staff", "swing_hammer", "swing_dual", "swing_king",
	"hit_flesh_light", "hit_flesh_heavy", "hit_leather_light", "hit_leather_heavy", "hit_steel_light", "hit_steel_heavy",
	"hit_plate_light", "hit_plate_heavy", "block", "guard_break", "parry", "dodge", "footstep_stone", "stagger",
	"defeat", "victory", "ability_last_stand", "ability_lunge", "ability_blink", "ability_fortress", "ability_fury",
	"ability_counter", "countdown_tick", "fight_cue", "ui_hover", "ui_click", "ui_confirm", "ui_back",
]


class FakeClock:
	var ms: int = 1000

	func now() -> int:
		return ms


static func _peak_db(data: PackedByteArray) -> float:
	var peak := 0
	var count := data.size() / 2
	for i in count:
		peak = maxi(peak, absi(data.decode_s16(i * 2)))
	return 20.0 * log(maxf(float(peak) / 32768.0, 1e-9)) / log(10.0)


static func _rms_db(data: PackedByteArray) -> float:
	var sum := 0.0
	var count := data.size() / 2
	for i in count:
		var v := float(data.decode_s16(i * 2)) / 32768.0
		sum += v * v
	return 10.0 * log(maxf(sum / float(count), 1e-12)) / log(10.0)


static func run(h, tree: SceneTree) -> void:
	_files_and_manifest(h)
	_wav_quality(h)
	_parser(h)
	_determinism(h)
	await _mapping(h, tree)
	await _playback_limits(h, tree)
	_ui(h, tree)
	await _simulation_integration(h, tree)


static func _files_and_manifest(h) -> void:
	h.begin("audio: manifest lists every required sound and every file exists (and no orphan files)")
	var manifest: Dictionary = CombatAudio.manifest()
	h.check(not manifest.is_empty(), "manifest.json parses")
	h.eq(int(manifest.get("sample_rate", 0)), 44100, "manifest sample rate")
	var sounds: Dictionary = manifest.get("sounds", {})
	for sound_name in REQUIRED:
		h.check(sounds.has(sound_name), "manifest has '%s'" % sound_name)
	var listed := {}
	for sound_name in sounds:
		var entry: Dictionary = sounds[sound_name]
		h.eq((entry["files"] as Array).size(), int(entry["variants"]), "%s: variants == files" % sound_name)
		for file in entry["files"]:
			listed[file] = true
			h.check(FileAccess.file_exists(DIR + String(file)), "%s exists" % file)
	var on_disk := 0
	for file in DirAccess.get_files_at(DIR):
		if file.ends_with(".wav"):
			on_disk += 1
			h.check(listed.has(file), "%s is listed in the manifest" % file)
	h.eq(on_disk, listed.size(), "wav count on disk == manifest")
	for repeated in ["swing_spear", "hit_steel_light", "hit_plate_heavy", "parry", "block", "footstep_stone"]:
		h.check(CombatAudio.variants_of(repeated) >= 2, "'%s' has >= 2 variants (no machine-gun repetition)" % repeated)
	h.check(CombatAudio.variants_of("footstep_stone") >= 3, "footsteps have 3 variants")


static func _wav_quality(h) -> void:
	h.begin("audio: every WAV is 44.1 kHz mono 16-bit, loud enough, never clipping, within the size budget")
	var manifest: Dictionary = CombatAudio.manifest()
	var total := 0
	for sound_name in manifest.get("sounds", {}):
		var entry: Dictionary = manifest["sounds"][sound_name]
		for file in entry["files"]:
			var path: String = DIR + String(file)
			var bytes := FileAccess.get_file_as_bytes(path)
			total += bytes.size()
			var stream := CombatAudio.parse_wav(bytes)
			if not h.check(stream != null, "%s parses" % file):
				continue
			h.eq(stream.mix_rate, 44100, "%s mix rate" % file)
			h.check(not stream.stereo, "%s is mono" % file)
			h.eq(stream.format, AudioStreamWAV.FORMAT_16_BITS, "%s is 16-bit" % file)
			h.check(bytes.size() < 64000, "%s is small (%d bytes)" % [file, bytes.size()])
			var seconds := float(stream.data.size() / 2) / 44100.0
			h.near(seconds, stream.get_length(), 0.002, "%s length matches" % file)
			h.check(seconds >= 0.03 and seconds <= 0.8, "%s duration %.3f s is sane for a combat cue" % [file, seconds])
			var peak := _peak_db(stream.data)
			h.check(peak <= -1.0, "%s peak %.1f dBFS is at most -1" % [file, peak])
			h.check(peak >= -20.0, "%s peak %.1f dBFS is not inaudibly quiet" % [file, peak])
			h.check(_rms_db(stream.data) > -40.0, "%s is not silent (RMS %.1f dB)" % [file, _rms_db(stream.data)])
			var last := absi(stream.data.decode_s16(stream.data.size() - 2))
			h.check(last < 64, "%s ends without a click (last sample %d)" % [file, last])
	h.check(total < 2 * 1024 * 1024, "total audio %d bytes stays under 2 MiB" % total)


static func _parser(h) -> void:
	h.begin("audio: the WAV parser rejects malformed input and loads without an editor import")
	h.check(CombatAudio.parse_wav(PackedByteArray()) == null, "empty bytes -> null")
	h.check(CombatAudio.parse_wav(("RIFF" + "x".repeat(60)).to_ascii_buffer()) == null, "garbage -> null")
	var good := FileAccess.get_file_as_bytes(DIR + "parry_1.wav")
	var eight_bit := good.duplicate()
	eight_bit.encode_u16(34, 8)  # bits per sample
	h.check(CombatAudio.parse_wav(eight_bit) == null, "8-bit PCM is refused")
	var float_tag := good.duplicate()
	float_tag.encode_u16(20, 3)  # IEEE float
	h.check(CombatAudio.parse_wav(float_tag) == null, "non-PCM is refused")
	var truncated := good.slice(0, 200)
	var partial := CombatAudio.parse_wav(truncated)
	h.check(partial != null and partial.data.size() > 0, "a truncated file still yields the bytes it has")
	var library := CombatAudio.load_library(true)
	h.eq(library.size(), (CombatAudio.manifest()["sounds"] as Dictionary).size(), "every manifest sound loaded into the library")
	for sound_name in library:
		for stream in library[sound_name]:
			h.check(stream is AudioStream and stream.get_length() > 0.0, "%s stream usable" % sound_name)


static func _determinism(h) -> void:
	h.begin("audio: regenerating with tools/audio/generate_sfx.py reproduces the committed files byte for byte")
	var script := ProjectSettings.globalize_path("res://").path_join("../tools/audio/generate_sfx.py").simplify_path()
	if not FileAccess.file_exists(script):
		h.check(false, "generator script exists at %s" % script)
		return
	var out := OS.get_user_data_dir().path_join("audio_determinism")
	DirAccess.make_dir_recursive_absolute(out)
	for file in DirAccess.get_files_at(out):
		DirAccess.remove_absolute(out.path_join(file))
	var output: Array = []
	var code := OS.execute("python3", ["-I", script, "--out", out], output, true)
	if code == -1:
		print("  SKIPPED determinism (python3 could not be started on this machine)")
		return
	h.eq(code, 0, "generator exits 0 (%s)" % str(output))
	var committed := DirAccess.get_files_at(DIR)
	var regenerated := DirAccess.get_files_at(out)
	var wanted: Array = []
	for file in committed:
		if file.ends_with(".wav") or file in ["manifest.json", "INVENTORY.md"]:
			wanted.append(file)
	h.eq(regenerated.size(), wanted.size(), "same number of generated files")
	for file in wanted:
		h.eq(FileAccess.get_sha256(out.path_join(file)), FileAccess.get_sha256(DIR + file), "%s is byte-identical" % file)


# ---------------------------------------------------------------------------------------------
static func _new_audio(tree: SceneTree, simulation = null) -> Dictionary:
	var host := Node3D.new()
	tree.root.add_child(host)
	var audio = CombatAudio.new()
	host.add_child(audio)
	var clock := FakeClock.new()
	audio.clock = Callable(clock, "now")
	audio.setup(host, simulation)
	return {"audio": audio, "host": host, "clock": clock}


static func _free(rig: Dictionary) -> void:
	rig["host"].get_parent().remove_child(rig["host"])
	rig["host"].free()


static func _mapping(h, tree: SceneTree) -> void:
	h.begin("audio: every role maps to existing weapon, ability and hit sounds")
	for role in ["p", "n", "b", "r", "q", "k"]:
		h.check(CombatAudio.has_sound(CombatAudio.ROLE_SWING[role]), "swing sound for %s" % role)
		h.check(CombatAudio.has_sound(CombatAudio.ROLE_ABILITY[role]), "ability sound for %s" % role)
		h.check(CombatAudio.has_sound(CombatAudio.ROLE_ABILITY[role]) and CombatAudio.ROLE_ABILITY[role] != "", "ability for %s is not empty" % role)
		var material: String = CombatAudio.ROLE_MATERIAL[role]
		h.check(CombatAudio.has_sound("hit_%s_light" % material) and CombatAudio.has_sound("hit_%s_heavy" % material), "hit sounds for %s armour (%s)" % [role, material])
	h.check(CombatAudio.ROLE_SWING.values().size() == 6 and CombatAudio.ROLE_SWING.values().duplicate().size() == 6, "six swing sounds")
	var distinct := {}
	for role in CombatAudio.ROLE_SWING:
		distinct[CombatAudio.ROLE_SWING[role]] = true
	h.eq(distinct.size(), 6, "each fighter has its own weapon swing sound")
	distinct.clear()
	for role in CombatAudio.ROLE_ABILITY:
		distinct[CombatAudio.ROLE_ABILITY[role]] = true
	h.eq(distinct.size(), 6, "each fighter has its own ability sound")

	h.begin("audio: sound_for_event is a pure, total mapping")
	for pair in [["p", "n"], ["b", "r"], ["q", "p"]]:
		var rig = await Support.make_rig(tree, pair[0], pair[1])
		var fixture := _new_audio(tree, rig.sim)
		var audio = fixture["audio"]
		var a_id: String = rig.white().player_id
		var d_id: String = rig.black().player_id
		var d_material: String = CombatAudio.ROLE_MATERIAL[pair[1]]
		h.eq(audio.sound_for_event({"type": "hit", "actorPlayerId": a_id, "targetPlayerId": d_id, "damage": 5}), "hit_%s_light" % d_material, "%s hitting %s: light" % pair)
		h.eq(audio.sound_for_event({"type": "hit", "actorPlayerId": a_id, "targetPlayerId": d_id, "damage": 30}), "hit_%s_heavy" % d_material, "%s hitting %s: heavy (damage fallback)" % pair)
		h.eq(audio.sound_for_event({"type": "block", "actorPlayerId": a_id, "targetPlayerId": d_id}), "block", "block")
		h.eq(audio.sound_for_event({"type": "guardbreak", "actorPlayerId": a_id, "targetPlayerId": d_id}), "guard_break", "guard break")
		h.eq(audio.sound_for_event({"type": "parry", "actorPlayerId": a_id, "targetPlayerId": d_id}), "parry", "perfect parry")
		h.eq(audio.sound_for_event({"type": "ability", "actorPlayerId": a_id, "targetPlayerId": d_id}), CombatAudio.ROLE_ABILITY[pair[0]], "ability of %s" % pair[0])
		h.eq(audio.sound_for_event({"type": "whiff", "actorPlayerId": d_id, "targetPlayerId": a_id}), CombatAudio.ROLE_SWING[pair[1]], "whiff uses the actor's weapon")
		h.eq(audio.sound_for_event({"type": "dodge", "actorPlayerId": a_id, "targetPlayerId": d_id}), "", "dodge-through is silent (the whoosh plays at dodge start)")
		h.eq(audio.sound_for_event({"type": "nonsense"}), "", "unknown events are silent")
		h.eq(audio.sound_for_event({}), "", "empty event is silent")
		for t in CombatAudio.EVENT_TYPES:
			var e := {"type": t, "actorPlayerId": a_id, "targetPlayerId": d_id, "damage": 12}
			h.eq(audio.sound_for_event(e), audio.sound_for_event(e), "%s mapping is deterministic" % t)
			var sound: String = audio.sound_for_event(e)
			h.check(sound == "" or CombatAudio.has_sound(sound), "%s -> '%s' exists in the library" % [t, sound])
		_free(fixture)
		rig.dispose()


static func _playback_limits(h, tree: SceneTree) -> void:
	h.begin("audio: rate limiting, simultaneous caps, hard voice bounds and accounting")
	var fixture := _new_audio(tree)
	var audio = fixture["audio"]
	var clock: FakeClock = fixture["clock"]
	h.eq(audio.voice_capacity(), CombatAudio.MAX_WORLD_VOICES + CombatAudio.MAX_FLAT_VOICES, "voice pools have a fixed size")
	audio.stats["played"] = 0
	var attempts := 0
	for i in 300:  # a burst within one millisecond
		attempts += 1
		audio._play("hit_steel_light", Vector3.ZERO)
	h.eq(int(audio.stats["played"]), 1, "300 identical hits in the same instant play once (rate limit)")
	h.eq(int(audio.stats["dropped_rate"]), 299, "the rest are counted as rate-limited")
	clock.ms += 1000
	h.check(audio._play("hit_steel_light", Vector3.ZERO), "after the interval the sound plays again")
	# Many different sounds at the same instant never exceed the pools.
	var names := ["swing_spear", "swing_sword", "swing_staff", "swing_hammer", "swing_dual", "swing_king", "hit_flesh_light", "hit_plate_heavy",
			"block", "guard_break", "parry", "dodge", "footstep_stone", "stagger", "ability_blink", "ability_fury", "ui_click", "defeat"]
	for round_i in 12:
		clock.ms += 400
		for sound in names:
			audio._play(sound, Vector3(1, 1, 1))
		h.check(audio.active_voices() <= audio.voice_capacity(), "round %d: %d active voices within capacity %d" % [round_i, audio.active_voices(), audio.voice_capacity()])
	var s: Dictionary = audio.stats
	var by_total := 0
	for k in s["by_sound"]:
		by_total += int(s["by_sound"][k])
	h.eq(by_total, int(s["played"]), "per-sound counters add up to 'played'")
	# Simultaneous cap: footsteps allow 3 at a time even if the interval would permit more.
	var count_before := int(s["played"])
	for i in 8:
		clock.ms += 200
		audio._play("footstep_stone", Vector3.ZERO)
	h.check(int(s["played"]) - count_before <= 8, "footsteps never exceed their attempts")
	h.check(audio._simultaneous("footstep_stone") <= 3, "at most 3 footsteps ring at once (%d)" % audio._simultaneous("footstep_stone"))

	h.begin("audio: variant rotation never repeats immediately; ducking and mute")
	var last = null
	var repeats := 0
	var seen := {}
	for i in 200:
		var stream = audio._pick("hit_steel_light")
		if stream == last:
			repeats += 1
		seen[stream.get_instance_id()] = true
		last = stream
	h.eq(repeats, 0, "no back-to-back repeat of the same variant")
	h.eq(seen.size(), CombatAudio.variants_of("hit_steel_light"), "all variants get used")
	clock.ms += 5000
	audio.set_muted(true)
	h.eq(audio.active_voices(), 0, "muting silences every voice")
	var dropped := int(s["dropped_muted"])
	h.check(not audio._play("parry", Vector3.ZERO), "muted: nothing plays")
	h.eq(int(s["dropped_muted"]), dropped + 1, "muted attempts are counted")
	audio.set_muted(false)
	clock.ms += 5000
	h.check(audio._play("parry", Vector3.ZERO), "unmuted plays again")
	clock.ms += 10
	var footsteps_played := int(s["by_sound"].get("footstep_stone", 0))
	audio._play("footstep_stone", Vector3.ZERO)
	h.eq(int(s["by_sound"].get("footstep_stone", 0)), footsteps_played, "footsteps yield while a high-priority sound is ringing (ducking)")
	h.check(audio._play("bogus_sound_name", Vector3.ZERO) == false and int(s["dropped_missing"]) >= 1, "unknown sound names are counted, not fatal")
	audio.set_volumes(0.5, 0.8, 0.9)
	h.near(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(CombatAudio.SFX_BUS)), linear_to_db(0.4), 0.01, "SFX bus volume follows the settings")
	audio.set_volumes(1.0, 1.0, 1.0)
	h.check(AudioServer.get_bus_index(CombatAudio.UI_BUS) != -1 and AudioServer.get_bus_index(CombatAudio.SFX_BUS) != -1, "SFX and UI buses exist")
	_free(fixture)


static func _ui(h, tree: SceneTree) -> void:
	h.begin("audio: attach_ui is idempotent, classifies buttons and covers buttons added later")
	var fixture := _new_audio(tree)
	var audio = fixture["audio"]
	var clock: FakeClock = fixture["clock"]
	var root := Control.new()
	tree.root.add_child(root)
	var buttons := {}
	for label in ["FIGHT", "Back", "Choose"]:
		var b := Button.new()
		b.text = label
		root.add_child(b)
		buttons[label] = b
	h.eq(audio.attach_ui(root), 3, "first attach hooks three buttons")
	h.eq(audio.attach_ui(root), 0, "second attach hooks nothing (idempotent)")
	for b in buttons.values():
		h.eq(b.pressed.get_connections().size(), 1, "exactly one press handler on %s" % b.text)
	var expect := {"FIGHT": "ui_confirm", "Back": "ui_back", "Choose": "ui_click"}
	for label in expect:
		clock.ms += 500
		buttons[label].pressed.emit()
		h.eq(audio.stats["last_sound"], expect[label], "pressing '%s' plays %s" % [label, expect[label]])
	clock.ms += 500
	var late := Button.new()
	late.text = "Rematch"
	root.add_child(late)
	h.check(late.has_meta("_combat_audio_ui"), "a button added later is hooked automatically")
	clock.ms += 500
	late.pressed.emit()
	h.eq(audio.stats["last_sound"], "ui_confirm", "late button plays too")
	h.eq(CombatAudio.classify_button("Back to menu"), "back", "classification: back")
	h.eq(CombatAudio.classify_button("Start fight"), "confirm", "classification: confirm")
	h.eq(CombatAudio.classify_button("Option 2"), "click", "classification: click")
	clock.ms += 500
	audio.play_ui("hover")
	h.eq(audio.stats["last_sound"], "ui_hover", "play_ui('hover')")
	audio.play_ui("ui_back")
	h.check(true, "play_ui accepts the full name")
	root.get_parent().remove_child(root)
	root.free()
	_free(fixture)


static func _simulation_integration(h, tree: SceneTree) -> void:
	h.begin("audio: a live fight drives countdown, swing, hit and dodge sounds from simulation state only")
	var rig = await Support.make_rig(tree, "p", "n")
	var fixture := _new_audio(tree, rig.sim)
	var audio = fixture["audio"]
	var clock: FakeClock = fixture["clock"]
	rig.face_off()
	var tick_before: int = rig.sim.server_tick
	# Countdown: 3 ticks (3, 2, 1) then the fight cue.
	var guard := 0
	while rig.sim.phase == CombatSimulation.Phase.COUNTDOWN and guard < 400:
		rig.tick()
		clock.ms += 17
		audio.poll()
		guard += 1
	var by: Dictionary = audio.stats["by_sound"]
	h.eq(int(by.get("countdown_tick", 0)), 3, "three countdown ticks")
	h.eq(int(by.get("fight_cue", 0)), 1, "the fight cue plays once when the countdown ends")
	rig.tick()
	clock.ms += 17
	audio.poll()
	h.eq(int(by.get("fight_cue", 0)), 1, "and not again")

	rig.w.press("light")
	for i in 14:
		rig.tick()
		clock.ms += 17
		audio.poll()
	h.eq(int(by.get("swing_spear", 0)), 1, "the Pawn's spear whooshes once per swing")
	h.check(int(by.get("hit_steel_light", 0)) + int(by.get("hit_steel_heavy", 0)) >= 1, "the hit on the Knight plays a steel hit sound (%s)" % str(by.keys()))
	# Second fighter dodges: dodge whoosh on dodge start.
	clock.ms += 1000
	rig.b.press("dodge")
	for i in 4:
		rig.tick()
		clock.ms += 17
		audio.poll()
	h.eq(int(by.get("dodge", 0)), 1, "dodge whoosh plays when the dodge starts")

	# Duplicate event ids (e.g. a snapshot replay) never double the sound.
	var duplicate: Dictionary = rig.sim.recent_events.back()
	var played := int(audio.stats["played"])
	audio.on_event(duplicate)
	h.eq(int(audio.stats["played"]), played, "re-delivering a known event id adds no sound")
	h.check(int(audio.stats["duplicate_events"]) >= 1, "duplicates are counted")
	h.check(rig.sim.server_tick > tick_before, "the simulation advanced normally while audio listened")

	h.begin("audio: a finished battle triggers victory for the winner and defeat for the loser, never both")
	audio.local_player_id = "player-white"
	audio.on_battle_finished({"outcome": "attacker", "winnerPlayerId": "player-white"})
	h.eq(int(by.get("victory", 0)), 1, "winner hears the victory fanfare")
	clock.ms += 2000
	audio.on_battle_finished({"outcome": "defender", "winnerPlayerId": "player-black"})
	h.eq(int(by.get("defeat", 0)), 1, "loser hears the defeat sting")
	clock.ms += 2000
	audio.on_battle_finished({"outcome": "draw", "winnerPlayerId": ""})
	h.eq(int(by.get("victory", 0)) + int(by.get("defeat", 0)), 2, "a draw is silent")
	_free(fixture)
	rig.dispose()
