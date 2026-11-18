class_name BoardLook
extends RefCounted
## Every tunable of the 3D board scene's LOOK in one place: squares, frame, courtyard, lights, fog, camera, piece scale and the
## readability marks. Pure presentation: nothing here touches chess state, the contract or the network.
## Used by boards/board_3d.gd, boards/board_scenery.gd (builds the dais / courtyard / braziers) and world/battle_world.gd (lights, fog).

# ---- pieces ---------------------------------------------------------------------------------------------------------------------
## Multiplies every paladin's standing height. The model width scales with it, so this is also the base-footprint scale: the paladin
## base used to fill more than a whole square and crowd the row behind it; ~0.82 of a square is the target (see BASE_TARGET).
const PIECE_SCALE := 1.0
const BASE_TARGET := 0.82          # documented goal: piece base / square. test_board_look measures the real footprint against it

# ---- squares (ivory marble vs dark slate) ----------------------------------------------------------------------------------------
const LIGHT_SQUARE := Color("e9e5db")     # ivory marble
const DARK_SQUARE := Color("c9631c")      # blue-black slate
const LIGHT_VEIN := Color("b9b3a4")       # marble veining (subtle)
const DARK_VEIN := Color("9a4a12")        # slate grain (subtle)
const SQUARE_ROUGHNESS_LIGHT := 0.34      # polished marble
const SQUARE_ROUGHNESS_DARK := 0.5
const SQUARE_NORMAL_STRENGTH := 0.35
const TEXTURE_SIZE := 256

# ---- frame, plinth, dais ---------------------------------------------------------------------------------------------------------
const PLINTH_COLOR := Color("3a3d44")     # carved stone body
const FRAME_COLOR := Color("b8924a")      # gilded trim
const FRAME_METALLIC := 0.75
const FRAME_ROUGHNESS := 0.38
const STONE_COLOR := Color("6f6d68")      # weathered courtyard stone (triplanar texture is tinted by this)
const STONE_DARK := Color("34353b")
const STONE_TEXEL := 0.28                 # triplanar scale: one texture repeat per 1/STONE_TEXEL metres -> no stretching
const DAIS_STEPS := 3
const DAIS_STEP_RISE := 0.16
const DAIS_STEP_RUN := 0.5
const FLOOR_Y := -0.92                    # courtyard paving height (board-local); the dais steps up from here
const FLOOR_HALF := 26.0

# ---- environment: courtyard walls, pillars, braziers, banners ----------------------------------------------------------------------
const WALL_DISTANCE := 15.0               # half-width of the courtyard; walls and battlements sit here, far outside the play area
const WALL_HEIGHT := 7.5
const PILLAR_POS := 8.6                   # corner pillars: x = z = +-PILLAR_POS, outside the dais
const PILLAR_HEIGHT := 4.6
const BRAZIER_POS := 6.7                  # braziers flank the board corners, outside the dais steps
const BANNER_NAVY := Color("1d2c52")
const BANNER_CRIMSON := Color("8c1f2c")
const BANNER_GOLD := Color("c9a24c")

# ---- imported props (Meshy models in assets/world/props/; sizes in metres at scale 1.0: torch 0.5 x 0.95, banner 0.57 x 0.95) ----
const PROP_TORCH_SCALE := 1.6
const PROP_BANNER_SCALE := 3.0
const TORCH_ENERGY := 1.1
const TORCH_RANGE := 6.0

# ---- lights & fog ----------------------------------------------------------------------------------------------------------------
const BACKGROUND := Color("0d1016")
const AMBIENT_COLOR := Color("8fa3bd")
const AMBIENT_ENERGY := 0.38
const KEY_COLOR := Color("ffd9a0")        # warm key
const KEY_ENERGY := 0.8
const KEY_ROTATION := Vector3(-52.0, -32.0, 0.0)
const KEY_SHADOW_BLUR := 2.5              # soft shadows
const RIM_COLOR := Color("8fb6ff")        # cool rim from behind the far side
const RIM_ENERGY := 0.55
const RIM_ROTATION := Vector3(-24.0, 150.0, 0.0)
const FOG_COLOR := Color("1b2130")
const FOG_DENSITY := 0.014
const EXPOSURE := 0.8                    # < 1 keeps the ivory squares from blowing out
const TONEMAP_WHITE := 6.0
const BRAZIER_COLOR := Color("ff9a3c")
const BRAZIER_ENERGY := 1.3
const BRAZIER_RANGE := 7.5
const BRAZIER_FLICKER := 0.18

# ---- camera ----------------------------------------------------------------------------------------------------------------------
## Default perspective view: closer and a little steeper than the old 13.5 / 0.88. Orbit and zoom are clamped so the board stays framed.
const CAM_DISTANCE := 12.6
const CAM_ELEVATION := 0.98               # radians above the board plane (about 57 degrees)
const CAM_DISTANCE_MIN := 8.6
const CAM_DISTANCE_MAX := 16.5
const CAM_ELEVATION_MIN := 0.62
const CAM_ELEVATION_MAX := 1.38

# ---- readability marks (selected, legal, capture, last move, check) ---------------------------------------------------------------
const MARK_SELECTED := Color(1.0, 0.86, 0.35, 0.95)
const MARK_LAST := Color(0.35, 0.65, 1.0, 0.55)
const MARK_LEGAL := Color(0.35, 0.95, 0.6, 0.9)
const MARK_CAPTURE := Color(1.0, 0.3, 0.25, 0.95)
const MARK_CHECK := Color(1.0, 0.15, 0.15, 0.9)
const MARK_HEIGHT := 0.06                 # above the tile centre (tile top = 0.04)

# ---- labels ------------------------------------------------------------------------------------------------------------------------
const LABEL_COLOR := Color("f6dfa6")
const LABEL_OUTLINE := Color("1a1308")
const LABEL_OFFSET := 4.28                # sits on the gilded rim, clear of every HUD panel (the HUD lives outside the board viewport)
