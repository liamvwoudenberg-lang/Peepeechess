extends RefCounted
## Design tokens for the whole native UI: colour palette, spacing grid, radii, type scale and touch sizes.
## Dark medieval-fantasy: deep slate/charcoal surfaces, warm gold accents, bone-white text.
## Everything else (theme, kit, pages) reads from here so the look changes in one place.
## Usage: const T = preload("res://ui/theme/ui_tokens.gd")

# --- surfaces (darkest to lightest) ---
const BG_DEEP := Color("0b0e12")
const BG := Color("11151a")
const SURFACE := Color("181d24")
const SURFACE_2 := Color("212731")
const SURFACE_3 := Color("2b3340")
const SURFACE_GOLD := Color("2b2415")   # selected / highlighted card tint
# --- lines ---
const BORDER := Color("363f4c")
const BORDER_STRONG := Color("525d6e")
# --- accents ---
const GOLD := Color("e0b45f")
const GOLD_HI := Color("f6d68f")
const GOLD_LO := Color("8f6b28")
const EMBER := Color("e8863a")
# --- text ---
const TEXT := Color("f2ecdc")           # bone white
const TEXT_MUTED := Color("b0b4bc")
const TEXT_DIM := Color("8b919c")       # large / decorative text only (>= 3:1), never body copy
const TEXT_ON_GOLD := Color("19130a")
# --- feedback ---
const DANGER := Color("e07a6c")         # danger text on dark surfaces
const DANGER_BG := Color("8a2f29")
const DANGER_BG_HI := Color("a63a33")
const SUCCESS := Color("84c496")
const INFO := Color("86b6da")
const WARNING := Color("f0b24c")
# colour-blind-safe highlight pair (blue / orange, distinguishable under deuteranopia and protanopia)
const CB_MOVE := Color("56b4e9")
const CB_CAPTURE := Color("d55e00")

# --- spacing grid (4 px base) ---
const S1 := 4
const S2 := 8
const S3 := 12
const S4 := 16
const S5 := 24
const S6 := 32
const S7 := 48
const S8 := 64
# --- radii ---
const R_SM := 6
const R_MD := 10
const R_LG := 16
# --- type scale (px at 100 % UI scale) ---
const FS_CAPTION := 13
const FS_SMALL := 14
const FS_BODY := 16
const FS_LEAD := 18
const FS_H3 := 21
const FS_H2 := 28
const FS_H1 := 38
const FS_DISPLAY := 64
# --- touch / pointer targets (logical px; the OS stretch makes 48 >= 44 dp on phones) ---
const TOUCH_MIN := 48
const POINTER_MIN := 40
const FOCUS_RING := 3
# --- semantic text-on-surface pairs verified by tests/ui/contrast_test.gd ---
const TEXT_PAIRS := [
	["TEXT on BG", TEXT, BG], ["TEXT on SURFACE", TEXT, SURFACE], ["TEXT on SURFACE_2", TEXT, SURFACE_2],
	["TEXT on SURFACE_3", TEXT, SURFACE_3], ["TEXT on SURFACE_GOLD", TEXT, SURFACE_GOLD],
	["TEXT_MUTED on BG", TEXT_MUTED, BG], ["TEXT_MUTED on SURFACE", TEXT_MUTED, SURFACE], ["TEXT_MUTED on SURFACE_2", TEXT_MUTED, SURFACE_2],
	["TEXT_MUTED on SURFACE_3", TEXT_MUTED, SURFACE_3],
	["GOLD on BG", GOLD, BG], ["GOLD on SURFACE", GOLD, SURFACE], ["GOLD on SURFACE_2", GOLD, SURFACE_2], ["GOLD_HI on SURFACE_3", GOLD_HI, SURFACE_3],
	["TEXT_ON_GOLD on GOLD", TEXT_ON_GOLD, GOLD], ["TEXT_ON_GOLD on GOLD_HI", TEXT_ON_GOLD, GOLD_HI],
	["TEXT on DANGER_BG", TEXT, DANGER_BG], ["TEXT on DANGER_BG_HI", TEXT, DANGER_BG_HI],
	["DANGER on SURFACE", DANGER, SURFACE], ["DANGER on BG", DANGER, BG],
	["SUCCESS on SURFACE", SUCCESS, SURFACE], ["INFO on SURFACE", INFO, SURFACE], ["WARNING on SURFACE", WARNING, SURFACE],
]

static func _channel(value: float) -> float:
	return value / 12.92 if value <= 0.03928 else pow((value + 0.055) / 1.055, 2.4)

## WCAG 2.x relative luminance.
static func luminance(color: Color) -> float:
	return 0.2126 * _channel(color.r) + 0.7152 * _channel(color.g) + 0.0722 * _channel(color.b)

## WCAG 2.x contrast ratio of two opaque colours (1.0 .. 21.0).
static func contrast(a: Color, b: Color) -> float:
	var la := luminance(a)
	var lb := luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)

## Space for a UI feature that must be at least 44 dp on touch: returns the minimum control height.
static func min_target(touch: bool) -> int:
	return TOUCH_MIN if touch else POINTER_MIN
