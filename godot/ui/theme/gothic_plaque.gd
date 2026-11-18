class_name GothicPlaque
extends RefCounted
## Gothic plaque button art, drawn in code (no image files): a dark gunmetal frame with a bevelled silver rim, a scroll-work band with rivets,
## a thin inner line and a deep blue-violet "glass" interior, in the style of the Battle plaque reference. One 9-slice texture per
## variant and state, generated once and cached; pure function of its inputs (deterministic, no randomness, no clock).
##
##   GothicPlaque.apply(theme)   sets the Button / PrimaryButton / SegButton / NavButtonActive / DangerButton styles and colours.
##
## Lettering: if res://ui/fonts/gothic.ttf (or .otf) exists it is used for these buttons; without it the bold UI font is used with an engraved
## outline. (A blackletter font file has to be supplied by the project; nothing is downloaded.)

const SIZE := 96            # texture size in pixels (drawn 1:1, so a 44 px button shows the frame at its real scale)
const MARGIN := 20          # 9-slice margin: corners and rim are never stretched
const CHAMFER := 9.0       # cut corners (the gothic "tombstone" shoulder)
const PERIOD := 14.0        # scroll-work period along an edge; (SIZE - 2 * MARGIN) is a multiple of it so tiled edges are seamless
const STATES := ["normal", "hover", "pressed", "disabled"]

const SILVER_HI := Color("eef4fc")
const SILVER := Color("aab8cc")
const SILVER_LO := Color("4d596f")
const GUNMETAL := Color("171d2e")
const TEAL := Color("62e6d8")

## variant -> palette. rim: bevel colours; fill: interior gradient top/bottom; accent: inner line and glow; text colours.
const VARIANTS := {
	"plate": {"rim_hi": SILVER_HI, "rim_lo": SILVER_LO, "band": GUNMETAL, "fill_top": Color("0f1a40"), "fill_bot": Color("2a1a62"), "accent": TEAL,
		"text": Color("e8eef8"), "text_hover": Color("ffffff"), "text_pressed": Color("c4d2ea"), "text_disabled": Color("7d8aa3")},
	"selected": {"rim_hi": Color("ffffff"), "rim_lo": Color("7f8fae"), "band": Color("1d2540"), "fill_top": Color("19296a"), "fill_bot": Color("4326a0"), "accent": TEAL,
		"text": Color("ffffff"), "text_hover": Color("ffffff"), "text_pressed": Color("dfe8fa"), "text_disabled": Color("8c98b0")},
	"gold": {"rim_hi": Color("fff1c4"), "rim_lo": Color("7a5a22"), "band": Color("261d14"), "fill_top": Color("221447"), "fill_bot": Color("4a2478"), "accent": Color("e9bf62"),
		"text": Color("ffe9b3"), "text_hover": Color("fff6d6"), "text_pressed": Color("ead39a"), "text_disabled": Color("9a8a68")},
	"danger": {"rim_hi": Color("f2d6d0"), "rim_lo": Color("6b3a36"), "band": Color("26151a"), "fill_top": Color("3a1220"), "fill_bot": Color("5d1c2a"), "accent": Color("ff8f7a"),
		"text": Color("ffe3de"), "text_hover": Color("ffffff"), "text_pressed": Color("e8bdb6"), "text_disabled": Color("96787a")},
}

static var _cache: Dictionary = {}


static func texture(variant: String, state: String) -> ImageTexture:
	var key := variant + ":" + state
	if not _cache.has(key):
		_cache[key] = ImageTexture.create_from_image(_render(VARIANTS[variant], state))
	return _cache[key]


static func stylebox(variant: String, state: String, h_margin: int = 22, v_margin: int = 9) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = texture(variant, state)
	box.texture_margin_left = MARGIN
	box.texture_margin_right = MARGIN
	box.texture_margin_top = MARGIN
	box.texture_margin_bottom = MARGIN
	box.content_margin_left = h_margin
	box.content_margin_right = h_margin
	box.content_margin_top = v_margin
	box.content_margin_bottom = v_margin
	box.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	box.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	return box


## Sets the plaque look for the main button types of the theme. Ghost / icon / nav buttons stay flat on purpose (they are not plaques).
static func apply(theme: Theme) -> void:
	var lettering := _lettering()
	for entry in [["Button", "plate"], ["SegButton", "plate"], ["PrimaryButton", "gold"], ["NavButtonActive", "selected"], ["DangerButton", "danger"]]:
		var type_name: String = entry[0]
		var variant: String = entry[1]
		var palette: Dictionary = VARIANTS[variant]
		theme.set_stylebox("normal", type_name, stylebox(variant, "normal"))
		theme.set_stylebox("hover", type_name, stylebox(variant, "hover"))
		theme.set_stylebox("pressed", type_name, stylebox("selected" if type_name == "SegButton" else variant, "pressed"))
		theme.set_stylebox("hover_pressed", type_name, stylebox("selected" if type_name == "SegButton" else variant, "pressed"))
		theme.set_stylebox("disabled", type_name, stylebox(variant, "disabled"))
		theme.set_color("font_color", type_name, palette["text"])
		theme.set_color("font_hover_color", type_name, palette["text_hover"])
		theme.set_color("font_focus_color", type_name, palette["text_hover"])
		theme.set_color("font_pressed_color", type_name, palette["text_pressed"] if type_name != "SegButton" else VARIANTS["selected"]["text"])
		theme.set_color("font_hover_pressed_color", type_name, palette["text_hover"])
		theme.set_color("font_disabled_color", type_name, palette["text_disabled"])
		theme.set_color("font_outline_color", type_name, Color(0.02, 0.03, 0.08, 0.9))
		theme.set_constant("outline_size", type_name, 2)
		if lettering != null:
			theme.set_font("font", type_name, lettering)


static func _lettering() -> Font:
	for path in ["res://ui/fonts/gothic.ttf", "res://ui/fonts/gothic.otf"]:
		if ResourceLoader.exists(path):
			return load(path)
	return null


# ---- drawing ------------------------------------------------------------------------------------------------------------------
static func _render(p: Dictionary, state: String) -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var half := SIZE / 2.0
	var hx := half - 1.0
	var pressed := state == "pressed"
	var hover := state == "hover"
	var disabled := state == "disabled"
	for y in SIZE:
		for x in SIZE:
			var px := x + 0.5 - half
			var py := y + 0.5 - half
			# signed distance to a chamfered rectangle (negative inside)
			var ax := absf(px) - hx
			var ay := absf(py) - hx
			var cut := (absf(px) + absf(py) - (2.0 * hx - CHAMFER)) * 0.70710678
			var d := maxf(maxf(ax, ay), cut)
			var alpha := clampf(0.5 - d, 0.0, 1.0)
			if alpha <= 0.0:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var depth := -d
			var nx := px / hx
			var ny := py / hx
			var light := clampf(0.5 - 0.32 * nx - 0.5 * ny, 0.0, 1.0)
			if pressed:
				light = 1.0 - light   # inset: the light comes from the other side
			var col: Color
			if depth < 2.3:    # bevelled silver rim, bright on the lit side, with a thin specular line on the top edge
				col = (p["rim_lo"] as Color).lerp(p["rim_hi"], light)
				if not pressed and py < 0.0 and depth < 1.1 and absf(px) < hx - CHAMFER:
					col = col.lightened(0.18)
				if hover:
					col = col.lightened(0.14)
			elif depth < 6.2:  # scroll-work band: gunmetal with a bright wave that repeats every PERIOD pixels, and rivets in the corners
				var t := py if absf(nx) > absf(ny) else px
				var wave := sin(t * TAU / PERIOD + depth * 0.45)
				col = (p["band"] as Color).lightened(0.06 + 0.10 * light)
				if absf(wave) < 0.20:
					col = col.lerp(p["rim_lo"], 0.55).lightened(0.10 * light)
				elif wave > 0.60:
					col = col.lightened(0.07)
				var rv := Vector2(absf(px) - (hx - 8.5), absf(py) - (hx - 8.5)).length()
				if rv < 2.2:
					col = (p["rim_hi"] as Color).lerp(p["rim_lo"], clampf(rv / 2.2, 0.0, 1.0) * 0.7)
			elif depth < 7.4:  # thin inner accent line (teal / gold), brighter on hover
				col = (p["band"] as Color).lerp(p["accent"], 0.85 if hover else 0.62)
			else:              # blue-violet glass: vertical gradient, darker toward the frame, soft glow near the top centre, faint stone grain
				var v := clampf((py + half) / SIZE, 0.0, 1.0)
				col = (p["fill_top"] as Color).lerp(p["fill_bot"], v)
				var edge := smoothstep(7.4, 24.0, depth)
				col = col.darkened(0.34 * (1.0 - edge))
				var glow := exp(-((px / 42.0) * (px / 42.0) + ((py + 16.0) / 26.0) * ((py + 16.0) / 26.0)))
				col = col.lerp(p["accent"], 0.12 * glow + (0.07 if hover else 0.0))
				var grain := float(((x * 73856093) ^ (y * 19349663)) & 255) / 255.0 - 0.5
				col = col.lightened(0.05 * grain) if grain > 0.0 else col.darkened(-0.05 * grain)
				if pressed:
					col = col.darkened(0.18)
			if disabled:
				var grey := col.get_luminance()
				col = col.lerp(Color(grey, grey, grey * 1.05), 0.70).darkened(0.28)
			col.a = alpha
			image.set_pixel(x, y, col)
	return image
