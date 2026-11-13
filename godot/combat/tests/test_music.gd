extends RefCounted
## The score director (res://audio/music_director.gd): the generated loops, the state mix and its cross-fades, combat
## intensity, stingers. Objective properties only (peak, seam, bounds, mapping); nobody can judge the music from here.

const Music := preload("res://audio/music_director.gd")


static func run(h, tree: SceneTree) -> void:
	_streams(h)
	_mix(h)
	await _node(h, tree)


static func _peak(stream: AudioStreamWAV) -> float:
	var p := 0
	for i in stream.data.size() / 2:
		p = maxi(p, absi(stream.data.decode_s16(i * 2)))
	return float(p) / 32768.0


static func _streams(h) -> void:
	h.begin("music: every layer is a seamless, bounded, non-silent loop; stingers are bounded one-shots")
	var all := Music.generate_all(2.0)   # a short loop keeps the test fast; the rules are the same
	for layer in Music.LAYERS:
		var s: AudioStreamWAV = all["layer_" + layer]
		h.eq(s.data.size() / 2, int(2.0 * Music.RATE), "%s: exact loop length" % layer)
		h.eq(s.loop_mode, AudioStreamWAV.LOOP_FORWARD, "%s loops" % layer)
		var peak := _peak(s)
		h.check(peak > 0.05 and peak <= Music.PEAK + 0.01, "%s: audible but never above its fixed peak (%.3f)" % [layer, peak])
		# seam: the step across the loop point is no bigger than the largest step inside the loop (no click)
		var n := s.data.size() / 2
		var biggest := 0
		for i in range(1, n):
			biggest = maxi(biggest, absi(s.data.decode_s16(i * 2) - s.data.decode_s16((i - 1) * 2)))
		var seam := absi(s.data.decode_s16(0) - s.data.decode_s16((n - 1) * 2))
		h.check(seam <= maxi(biggest, 1) * 1.05, "%s: no click at the loop seam (seam step %d vs largest %d)" % [layer, seam, biggest])
	for stinger in Music.STINGERS:
		var st: AudioStreamWAV = all["stinger_" + stinger]
		h.check(_peak(st) > 0.1 and _peak(st) <= 0.4 and st.loop_mode == AudioStreamWAV.LOOP_DISABLED, "stinger %s: audible, bounded, not looped" % stinger)
	h.check(all["layer_pad"].data == Music.generate_all(2.0)["layer_pad"].data, "generation is deterministic")


static func _mix(h) -> void:
	h.begin("music: the state table is complete, and the worst-case mix cannot exceed full scale")
	for state in Music.STATES:
		h.check(Music.MIX.has(state), "state %s has a mix" % state)
	for state in Music.STATES:
		var sum := 0.0
		for layer in Music.MIX[state]:
			sum += float(Music.MIX[state][layer]) * Music.PEAK
		h.check(sum < 1.0, "%s: sum of layer peaks %.2f < 1" % [state, sum])
	h.check(Music.danger_from_health(1.0, 1.0) == 0.0 and Music.danger_from_health(0.0, 1.0) == 1.0, "danger: full health is calm, an empty bar is maximal")
	h.check(Music.danger_from_health(0.5, 0.9) > Music.danger_from_health(0.7, 0.9), "danger grows as the weaker bar drops")


static func _node(h, tree: SceneTree) -> void:
	h.begin("music: states cross-fade smoothly, combat intensity raises the drums, bad input is ignored, a headless run stays silent")
	var node: Node = load("res://audio/music_director.gd").new()   # not added to the tree: no audio device, state logic only
	node._apply_state_targets()
	h.eq(node.state, "silent", "starts silent")
	node.set_state("menu")
	for i in 5:
		node.step(0.1)
	var after_half := float(node.gains["pad"])
	h.check(after_half > 0.2 and after_half < float(node.targets["pad"]), "a cross-fade is gradual (pad %.2f after 0.5 s)" % after_half)
	for i in 30:
		node.step(0.1)
	h.check(is_equal_approx(float(node.gains["pad"]), 0.65), "it settles on the menu mix")
	node.set_state("not-a-state")
	h.eq(node.state, "menu", "an unknown state is ignored")
	node.set_state("combat")
	node.set_intensity(0.0)
	var calm_drum := float(node.targets["drum_fast"])
	node.set_intensity(1.0)
	h.check(float(node.targets["drum_fast"]) > calm_drum + 0.5 and float(node.targets["tension"]) > 0.7, "intensity raises the fast drum and the tension")
	node.set_state("board")
	h.check(float(node.targets["drum_fast"]) == 0.0, "back on the board the war drums fade out")
	h.check(Music.instance(tree) == null or DisplayServer.get_name() != "headless", "headless: no director node is created")
	node.free()
