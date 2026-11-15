extends SceneTree
## Native WAV loop safety: Android faults where desktop heap padding can hide
## an inclusive mixer read at a one-past-the-buffer loop endpoint.
const Music = preload("res://audio/music_director.gd")
var checks = 0
var failures: Array = []

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL: ", label)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var source = PackedFloat32Array([0.0, 0.5, -0.5, 0.25])
	var loop = Music.to_loop(source)
	expect(loop.loop_mode == AudioStreamWAV.LOOP_FORWARD, "music still loops")
	expect(loop.loop_begin >= 0 and loop.loop_end < loop.data.size() / 2, "every mixer loop endpoint addresses allocated PCM")
	expect(loop.data.size() == source.size() * 2, "PCM duration and sample format are preserved")
	var playback = loop.instantiate_playback()
	playback.start()
	var audible = false
	var bounded = true
	# Exercise the real resampler/mixer across many boundaries, with an audio
	# stream that is much shorter than the mix block.
	for _i in 32:
		var mixed = playback.mix_audio(1.0, 512)
		for sample in mixed:
			audible = audible or sample.length_squared() > 0.001
			bounded = bounded and is_finite(sample.x) and is_finite(sample.y) and absf(sample.x) <= 1.0 and absf(sample.y) <= 1.0
	playback.stop()
	expect(audible and bounded, "native loop mixing remains audible and finite across repeated wraps")
	for samples in [PackedFloat32Array(), PackedFloat32Array([0.25])]:
		expect(Music.to_loop(samples).loop_mode == AudioStreamWAV.LOOP_DISABLED, "empty/single-frame input never configures a zero-span loop")
	var stinger = Music.to_stream(source, false)
	expect(stinger.loop_mode == AudioStreamWAV.LOOP_DISABLED and stinger.data == loop.data, "one-shot stingers keep their PCM and do not loop")
	print("MUSIC LOOP: ", checks, " checks; failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
