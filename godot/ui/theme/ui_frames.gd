extends RefCounted
## Procedural ornate 9-slice frames (no image files): a carved stone panel with a gold keyline and corner studs, and a fully
## gilded variant. Textures are generated once (48x48) and cached; StyleBoxTexture stretches only the plain edges and centre.
## Presentation only. Usage: UiFrames.stone(fill, margin_h, margin_v) / UiFrames.gilded(...).
const T = preload("res://ui/theme/ui_tokens.gd")
const SIZE := 48
const SLICE := 14
static var _cache := {}

static func _noise(x: int, y: int) -> float:
	var h: int = (x * 73856093) ^ (y * 19349663)
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float((h ^ (h >> 16)) & 255) / 255.0

static func _image(fill: Color, gilded: bool) -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var gold: Color = T.GOLD if gilded else T.GOLD_LO
	var edge: Color = T.GOLD_HI if gilded else T.BORDER_STRONG
	for y in SIZE:
		for x in SIZE:
			var d := mini(mini(x, SIZE - 1 - x), mini(y, SIZE - 1 - y))
			var c := fill.lightened((_noise(x, y) - 0.5) * 0.05)
			if d == 0:
				c = gold.darkened(0.25) if gilded else T.BORDER
			elif d == 1:
				c = edge
			elif d == 2:
				c = fill.lightened(0.07)
			elif d == 3:
				c = fill.darkened(0.12)
			elif d == 4 and gilded:
				c = gold
			elif d == 5:
				c = fill.darkened(0.2)   # soft inner shadow
			image.set_pixel(x, y, c)
	# corner studs (small gold diamonds) inside the 14 px corners
	for corner in [Vector2i(7, 7), Vector2i(SIZE - 8, 7), Vector2i(7, SIZE - 8), Vector2i(SIZE - 8, SIZE - 8)]:
		for oy in range(-3, 4):
			for ox in range(-3, 4):
				var m := absi(ox) + absi(oy)
				if m <= 3:
					image.set_pixel(corner.x + ox, corner.y + oy, T.GOLD_HI if m <= 1 else T.GOLD_LO)
	# round the outermost corner pixels so the frame is not a hard rectangle
	for p in [Vector2i(0, 0), Vector2i(SIZE - 1, 0), Vector2i(0, SIZE - 1), Vector2i(SIZE - 1, SIZE - 1)]:
		image.set_pixelv(p, Color(0, 0, 0, 0))
	return image

static func _make(fill: Color, gilded: bool, margin_h: int, margin_v: int) -> StyleBoxTexture:
	var key := "%s|%s" % [fill.to_html(), gilded]
	if not _cache.has(key):
		_cache[key] = ImageTexture.create_from_image(_image(fill, gilded))
	var style := StyleBoxTexture.new()
	style.texture = _cache[key]
	style.texture_margin_left = SLICE
	style.texture_margin_right = SLICE
	style.texture_margin_top = SLICE
	style.texture_margin_bottom = SLICE
	style.content_margin_left = margin_h
	style.content_margin_right = margin_h
	style.content_margin_top = margin_v
	style.content_margin_bottom = margin_v
	style.draw_center = true
	return style

static func stone(fill: Color = T.SURFACE, margin_h: int = 16, margin_v: int = 14) -> StyleBoxTexture:
	return _make(fill, false, margin_h, margin_v)

static func gilded(fill: Color = T.SURFACE_GOLD, margin_h: int = 16, margin_v: int = 14) -> StyleBoxTexture:
	return _make(fill, true, margin_h, margin_v)
