extends Control
## Vector icons authored as small SVG strings (no third-party assets): crown, sword, shield, gear, controller, cloud,
## user, trophy, clock, flag, rook, plus utility glyphs and chess-piece silhouettes. All shapes are white on a
## 24 x 24 grid so they can be tinted with Control.modulate / theme icon colours.
##
##   UiIcons.texture("gear", 24)            -> ImageTexture (white, tint it) for Button.icon / TextureRect
##   var icon := UiIcons.new("crown", 28, T.GOLD)  -> a Control that draws the icon tinted (re-rasterises for crisp edges)
## Textures are NOT cached in statics (a static Resource would still be alive at engine shutdown).
const KINDS := ["crown", "sword", "shield", "gear", "controller", "cloud", "user", "trophy", "clock", "flag", "rook", "check", "close", "arrow", "warning", "info", "list", "emblem", "play", "lock"]
const PIECES := ["pawn", "knight", "bishop", "rook_piece", "queen", "king"]
const GEAR := "M18.86 10.61 L21.53 10.85 L21.53 13.15 L18.86 13.39 L17.83 15.87 L19.55 17.93 L17.93 19.55 L15.87 17.83 L13.39 18.86 L13.15 21.53 L10.85 21.53 L10.61 18.86 L8.13 17.83 L6.07 19.55 L4.45 17.93 L6.17 15.87 L5.14 13.39 L2.47 13.15 L2.47 10.85 L5.14 10.61 L6.17 8.13 L4.45 6.07 L6.07 4.45 L8.13 6.17 L10.61 5.14 L10.85 2.47 L13.15 2.47 L13.39 5.14 L15.87 6.17 L17.93 4.45 L19.55 6.07 L17.83 8.13 Z"
const SHIELD := "M12 2 L20.5 5 V11.5 C20.5 17 16.5 20.5 12 22.5 C7.5 20.5 3.5 17 3.5 11.5 V5 Z"
const SVG := {
	"crown": "<path d='M3 18 L2.5 7.5 L8 12 L12 4.5 L16 12 L21.5 7.5 L21 18 Z' fill='white' stroke='white' stroke-width='1' stroke-linejoin='round'/><rect x='3' y='19.5' width='18' height='2.6' rx='1.2' fill='white'/><circle cx='2.5' cy='6.4' r='1.7' fill='white'/><circle cx='12' cy='3.4' r='1.7' fill='white'/><circle cx='21.5' cy='6.4' r='1.7' fill='white'/>",
	"sword": "<path d='M12 1.5 L14.4 4.6 V15 H9.6 V4.6 Z' fill='white' stroke='white' stroke-width='0.8' stroke-linejoin='round'/><rect x='5.5' y='15' width='13' height='2.4' rx='1.1' fill='white'/><rect x='10.9' y='17.4' width='2.2' height='3.8' fill='white'/><circle cx='12' cy='22' r='1.6' fill='white'/>",
	"shield": "<path d='" + SHIELD + "' fill='none' stroke='white' stroke-width='2.2' stroke-linejoin='round'/><path d='M12 7 V17 M7.6 11 H16.4' stroke='white' stroke-width='2.2' stroke-linecap='round'/>",
	"gear": "<path fill-rule='evenodd' fill='white' d='" + GEAR + " M12 8.4 a3.6 3.6 0 1 0 0.01 0 Z'/>",
	"controller": "<path d='M7 6.5 H17 C19.5 6.5 21 8 21.8 11 L22.8 16 C23.1 18 21.4 19.4 19.8 18.4 L16.6 15.4 H7.4 L4.2 18.4 C2.6 19.4 0.9 18 1.2 16 L2.2 11 C3 8 4.5 6.5 7 6.5 Z' fill='none' stroke='white' stroke-width='2' stroke-linejoin='round'/><path d='M7.5 9 V13.4 M5.3 11.2 H9.7' stroke='white' stroke-width='1.9' stroke-linecap='round'/><circle cx='16.2' cy='10' r='1.25' fill='white'/><circle cx='18.7' cy='12.4' r='1.25' fill='white'/>",
	"cloud": "<path d='M7 19 C3.6 19 2 16.7 2 14.4 C2 12.1 3.8 10.4 6 10.2 C6.6 7 9.2 5 12.2 5 C15.4 5 17.9 7.2 18.3 10.2 C20.6 10.4 22.4 12 22.4 14.5 C22.4 17 20.6 19 17.8 19 Z' fill='white'/>",
	"user": "<circle cx='12' cy='7.6' r='4.4' fill='white'/><path d='M3 22 C3 16.4 7 14 12 14 C17 14 21 16.4 21 22 Z' fill='white'/>",
	"trophy": "<path d='M6.5 3 H17.5 V8.5 C17.5 11.8 15 14 12 14 C9 14 6.5 11.8 6.5 8.5 Z' fill='white'/><path d='M6.5 5 H3.5 C3.5 9 4.8 10.8 7 11 M17.5 5 H20.5 C20.5 9 19.2 10.8 17 11' fill='none' stroke='white' stroke-width='1.8' stroke-linecap='round'/><rect x='10.7' y='13.5' width='2.6' height='4.6' fill='white'/><rect x='7' y='18' width='10' height='3.2' rx='1.2' fill='white'/>",
	"clock": "<circle cx='12' cy='12' r='9.2' fill='none' stroke='white' stroke-width='2'/><path d='M12 6 V12 L16 14.6' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'/>",
	"flag": "<path d='M5.5 2.5 V22' stroke='white' stroke-width='2.2' stroke-linecap='round'/><path d='M6.5 3.5 H20 L16.6 8 L20 12.5 H6.5 Z' fill='white' stroke='white' stroke-width='1' stroke-linejoin='round'/>",
	"rook": "<path d='M5 21.5 L6 17.5 H7.6 L8 10 L5.5 9.5 V3 H8.7 V5.2 H10.8 V3 H13.2 V5.2 H15.3 V3 H18.5 V9.5 L16 10 L16.4 17.5 H18 L19 21.5 Z' fill='white' stroke='white' stroke-width='0.8' stroke-linejoin='round'/>",
	"check": "<path d='M4.5 12.5 L9.5 17.5 L19.5 6.5' fill='none' stroke='white' stroke-width='2.6' stroke-linecap='round' stroke-linejoin='round'/>",
	"close": "<path d='M5.5 5.5 L18.5 18.5 M18.5 5.5 L5.5 18.5' stroke='white' stroke-width='2.6' stroke-linecap='round'/>",
	"arrow": "<path d='M4 12 H19 M13 5.5 L19.5 12 L13 18.5' fill='none' stroke='white' stroke-width='2.4' stroke-linecap='round' stroke-linejoin='round'/>",
	"warning": "<defs><mask id='m'><rect width='24' height='24' fill='white'/><path d='M12 9 V14.5' stroke='black' stroke-width='2' stroke-linecap='round'/><circle cx='12' cy='17.4' r='1.2' fill='black'/></mask></defs><path mask='url(#m)' d='M12 2.8 L22 20.5 H2 Z' fill='white' stroke='white' stroke-width='1.2' stroke-linejoin='round'/>",
	"info": "<defs><mask id='m'><rect width='24' height='24' fill='white'/><path d='M12 11 V17' stroke='black' stroke-width='2.2' stroke-linecap='round'/><circle cx='12' cy='7.4' r='1.4' fill='black'/></mask></defs><circle mask='url(#m)' cx='12' cy='12' r='10' fill='white'/>",
	"list": "<circle cx='4.5' cy='6' r='1.6' fill='white'/><circle cx='4.5' cy='12' r='1.6' fill='white'/><circle cx='4.5' cy='18' r='1.6' fill='white'/><path d='M9 6 H21 M9 12 H21 M9 18 H21' stroke='white' stroke-width='2' stroke-linecap='round'/>",
	"play": "<path d='M7 4 L20 12 L7 20 Z' fill='white' stroke='white' stroke-width='1.4' stroke-linejoin='round'/>",
	"lock": "<rect x='5' y='10.5' width='14' height='10.5' rx='2.4' fill='white'/><path d='M8 10.5 V7.5 C8 5.2 9.7 3.6 12 3.6 C14.3 3.6 16 5.2 16 7.5 V10.5' fill='none' stroke='white' stroke-width='2.2'/>",
	"emblem": "<path fill-rule='evenodd' fill='white' d='" + SHIELD + " M12 4.2 L18.8 6.4 V11.4 C18.8 15.6 15.8 18.4 12 20.2 C8.2 18.4 5.2 15.6 5.2 11.4 V6.4 Z'/><path d='M8 10 L16 18 M16 10 L8 18' stroke='white' stroke-width='1.7' stroke-linecap='round'/><path d='M8.6 8.8 L8.3 5.4 L10.4 7 L12 4.4 L13.6 7 L15.7 5.4 L15.4 8.8 Z' fill='white' stroke='white' stroke-width='0.6' stroke-linejoin='round'/>",
	# chess silhouettes for the title background
	"pawn": "<circle cx='12' cy='6.2' r='3.6' fill='white'/><path d='M10 9.4 H14 L15 13.5 H17 L16.2 16 H17.4 L19 21.5 H5 L6.6 16 H7.8 L7 13.5 H9 Z' fill='white'/>",
	"knight": "<path d='M5 21.5 L6.5 15 C6.5 11 8.5 8.5 11 7 L9.6 4 L12.4 5 L14 3 L15.4 6 C18 8 19 11.5 18.6 15 L19.5 21.5 Z' fill='white'/>",
	"bishop": "<path d='M12 2.2 C15 5 16.4 8 14.6 11 L15.2 13.2 H16.6 L16 15.6 H17.2 L18.6 21.5 H5.4 L6.8 15.6 H8 L7.4 13.2 H8.8 L9.4 11 C7.6 8 9 5 12 2.2 Z' fill='white'/>",
	"rook_piece": "<path d='M5.5 21.5 L6.5 16.5 H8 L8.4 9.5 L5.8 9 V3.5 H9 V5.6 H10.9 V3.5 H13.1 V5.6 H15 V3.5 H18.2 V9 L15.6 9.5 L16 16.5 H17.5 L18.5 21.5 Z' fill='white'/>",
	"queen": "<path d='M4 21.5 L5.4 16 L3 7 L8 11 L12 4.5 L16 11 L21 7 L18.6 16 L20 21.5 Z' fill='white'/><circle cx='3' cy='6' r='1.7' fill='white'/><circle cx='12' cy='3.4' r='1.7' fill='white'/><circle cx='21' cy='6' r='1.7' fill='white'/>",
	"king": "<path d='M11 2 H13 V4 H15 V6 H13 V8 C17 9 19 12 18 15 L19 17.5 H17.6 L19.5 21.5 H4.5 L6.4 17.5 H5 L6 15 C5 12 7 9 11 8 V6 H9 V4 H11 Z' fill='white'/>",
}
var kind := "crown":
	set(value):
		kind = value
		_texture = null
		queue_redraw()
var color := Color("e0b45f"):
	set(value):
		color = value
		queue_redraw()
var _texture: ImageTexture
var _texture_px := 0

func _init(p_kind: String = "crown", p_size: int = 24, p_color: Color = Color("e0b45f")) -> void:
	kind = p_kind
	color = p_color
	custom_minimum_size = Vector2(p_size, p_size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE

## White rasterised icon `px` pixels square. Unknown kinds give a small square so a typo is visible, not fatal.
static func texture(icon_kind: String, px: int = 24) -> ImageTexture:
	px = maxi(4, px)
	var markup: String = SVG.get(icon_kind, "<rect x='4' y='4' width='16' height='16' fill='white'/>")
	var svg := "<svg xmlns='http://www.w3.org/2000/svg' width='%d' height='%d' viewBox='0 0 24 24'>%s</svg>" % [px, px, markup]
	var image := Image.new()
	if image.load_svg_from_string(svg, 1.0) != OK or image.is_empty():
		image = Image.create(px, px, false, Image.FORMAT_RGBA8)
		image.fill(Color(1, 1, 1, 0.0))
	return ImageTexture.create_from_image(image)

func _draw() -> void:
	var extent := minf(size.x, size.y)
	if extent < 2.0:
		return
	# crisp edges at the real pixel size: rasterise at the canvas scale the control is drawn at
	var scale_factor := get_global_transform_with_canvas().get_scale().x if is_inside_tree() else 1.0
	var px := maxi(8, int(ceilf(extent * maxf(scale_factor, 1.0))))
	if _texture == null or absi(_texture_px - px) > 1:
		_texture = texture(kind, px)
		_texture_px = px
	var origin := (size - Vector2(extent, extent)) * 0.5
	draw_texture_rect(_texture, Rect2(origin, Vector2(extent, extent)), false, color)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_TRANSFORM_CHANGED:
		queue_redraw()
