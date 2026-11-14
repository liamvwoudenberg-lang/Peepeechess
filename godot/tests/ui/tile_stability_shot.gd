extends SceneTree
## Render-based tile stability probe for the opening scene (needs a real renderer: run under xvfb with software GL).
##   xvfb-run -a godot --path godot --rendering-driver opengl3 --resolution 960x600 --script res://tests/ui/tile_stability_shot.gd -- [legacy] [save_dir]
## For several camera positions along the glide it renders the scene twice, the second time with the camera nudged by 3 mm (a static
## scene, so a stable surface changes by sub-pixel amounts at most), and prints the share of pixels in the bridge band whose colour
## changed by more than a threshold. Z-fighting surfaces flip between two colours on such a nudge.
const OpeningScene = preload("res://ui/opening/opening_scene.gd")
const Builder = preload("res://ui/opening/castle_builder.gd")
const THRESHOLD := 40   # sum of |dr|+|dg|+|db| in 0..255 units

func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	Builder.debug_pier_tops = "legacy" in args
	var save_dir := ""
	for a in args:
		if a.begins_with("dir="):
			save_dir = a.substr(4)
	var s := OpeningScene.new()
	root.add_child(s)
	s.build("balanced", false, 0.0)
	var worst := 0.0
	for blend in [0.0, 0.12, 0.25, 0.4, 0.55]:
		s.set_blend(blend)
		for _i in 3:
			await process_frame
		var a := root.get_viewport().get_texture().get_image()
		s.camera.position += Vector3(0.003, 0.0, 0.0)
		for _i in 3:
			await process_frame
		var b := root.get_viewport().get_texture().get_image()
		var size := a.get_size()
		var y0 := int(size.y * 0.55)
		var changed := 0
		var total := 0
		for y in range(y0, size.y, 2):
			for x in range(0, size.x, 2):
				var ca := a.get_pixel(x, y)
				var cb := b.get_pixel(x, y)
				var d := (absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) * 255.0
				total += 1
				if d > THRESHOLD:
					changed += 1
		var share := float(changed) / maxf(total, 1)
		worst = maxf(worst, share)
		print("blend %.2f: %.3f%% of the lower band changed on a 3 mm nudge" % [blend, share * 100.0])
		if save_dir != "":
			a.save_png("%s/tile_%s_%03d.png" % [save_dir, "legacy" if Builder.debug_pier_tops else "fixed", int(blend * 100)])
	print("WORST ", "%.3f" % (worst * 100.0), "%")
	quit()
