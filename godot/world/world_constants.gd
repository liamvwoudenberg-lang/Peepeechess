class_name WorldConstants
extends RefCounted
## Timings, geometry and render-layer conventions of the pit world. Every duration is a constant so
## tests and docs can quote them; PitSequence is driven by advance(dt) and never reads wall-clock time.

# ---- geometry (metres, world frame during a battle) -------------------------------------------
## Arena floor is y=0 (the combat simulation lives in world space and must stay at the origin).
## While a battle runs, the chess board root is lifted to this height and shifted horizontally so
## the contested tile sits exactly above the arena centre.
const BOARD_DEPTH := 7.0
const CEILING_BOTTOM := 5.0
const CEILING_THICKNESS := 0.5
const CEILING_HALF := 9.0
const HOLE_HALF := 0.5
const TILE_SIZE := 0.995
const TILE_THICKNESS := 0.08
## Board slab extents (board-local), see ChessBoard3D.
const PLINTH_SIZE := Vector3(8.65, 0.38, 8.65)
const PLINTH_CENTER := Vector3(0, -0.26, 0)
const FRAME_SIZE := Vector3(8.8, 0.06, 8.8)
const FRAME_CENTER := Vector3(0, -0.07, 0)
## Ladder plane offset from the shaft centre and rail half width (matches godot/assets/world/pit/ladder_*.glb).
const LADDER_Z := 0.42
const LADDER_HALF_WIDTH := 0.28
const LADDER_CLIP_SPEED := 0.4167   # m/s the `climb` clip covers at speed 1.0
## Sim spawn points (CombatConstants.SPAWN_DISTANCE): white z=-2.6, black z=+2.6.
const SPAWN_Z := 2.6

# ---- render layers ------------------------------------------------------------------------------
const LAYER_CHAMBER := 1   # default layer: arena, fighters, ladder
const LAYER_BOARD := 2     # tiles, chess pieces, marks
const LAYER_CEILING := 4   # chamber ceiling: hidden from cameras above it
const MASK_ALL := 0xFFFFF
const MASK_NO_CEILING := MASK_ALL & ~LAYER_CEILING

# ---- camera -------------------------------------------------------------------------------------
const FOV_TOP_DOWN := 12.0     # narrow perspective: reads as orthographic
const FOV_PERSPECTIVE := 45.0
const FOV_COMBAT := 68.0       # ThirdPersonCamera default
const TOP_DOWN_HALF_EXTENT := 4.9
const FOCUS_HALF_EXTENT := 1.7
const DESCENT_STOP_ABOVE_BOARD := 3.2
const CAMERA_NEAR := 0.1
const CAMERA_FAR := 220.0

# ---- timings (seconds) --------------------------------------------------------------------------
const VIEW_SWITCH_TIME := 0.55       # 2D <-> 3D button
const CAPTURE_FOCUS_TIME := 0.9      # attacker slides onto the tile, camera zooms in
const TRAPDOOR_OPEN_TIME := 0.65
const DROP_TIME := 1.2               # pieces fall to the chamber floor
const DESCENT_EXTRA_TIME := 0.7      # camera keeps travelling after the landing
const COMBAT_BLEND_TIME := 0.01      # path end == third-person pose, no extra blend
const RESOLVE_DEFEAT_TIME := 1.3     # loser plays its defeat, then dissolves
const RESOLVE_DISSOLVE_TIME := 0.5
const LADDER_DEPLOY_TIME := 0.6
const CLIMB_WALK_SPEED := 2.2
const CLIMB_SPEED := 1.6             # metres per second up the ladder
const CLIMB_EXIT_TIME := 0.5         # step from the ladder onto the tile
const RETURN_MORPH_TIME := 0.45
const TRAPDOOR_CLOSE_TIME := 0.7
const RETURN_CAMERA_TIME := 2.0
const RECOVER_TIME := 0.35           # glide back to the chess view after an abort
const PIECE_SLIDE_TIME := 0.5
const PIECE_OFFSET := 0.3            # attacker/defender stand this far either side of the tile centre
const LEAF_OPEN_ANGLE := 1.75        # radians (leaves swing slightly past vertical)

static func smooth(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

static func smooth_out(t: float) -> float:
	var x := 1.0 - clampf(t, 0.0, 1.0)
	return 1.0 - x * x * x
