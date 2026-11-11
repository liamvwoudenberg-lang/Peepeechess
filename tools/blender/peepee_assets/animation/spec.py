"""Single source of truth for clip names, lengths and attack markers (frames == 60 Hz sim ticks).

Attack clip lengths equal the simulation's tick lengths so a clip plays 1:1 with the AttackDefinition
timeline in godot/combat/core/attack_library.gd. Light/heavy/parry numbers equal Codex's approved godot/chess/battle_stats.json (c0-balance-v1) for all six
roles; ability lengths equal the simulation's cast ticks (King: proposal, no simulation).
"""
CLASSES = ["pawn", "knight", "bishop", "rook", "queen", "king"]
ROLE = {"pawn": "p", "knight": "n", "bishop": "b", "rook": "r", "queen": "q", "king": "k"}

# lightTicks, heavyTicks, parryWindowTicks, parryRecoveryTicks
STATS = {  # == godot/chess/battle_stats.json (c0-balance-v1) lightTicks, heavyTicks, parryTicks + our recovery
    "pawn": (24, 53, 11, 16), "knight": (32, 63, 13, 14), "bishop": (29, 59, 11, 15),
    "rook": (42, 74, 10, 18), "queen": (29, 58, 11, 14), "king": (33, 63, 13, 14),
}
DODGE = {"pawn": 22, "knight": 26, "bishop": 24, "rook": 30, "queen": 20, "king": 26}
# Ability clip frames == the sim's cast ticks (ability_component.gd): last-stand 12, lunge 72, blink 20,
# fortress-guard 18, royal-fury 14. King has no simulation (v2 gauntlet); 40 is a proposal.
ABILITY = {"pawn": 12, "knight": 72, "bishop": 20, "rook": 18, "queen": 14, "king": 40}
ABILITY_NAME = {"pawn": "last-stand", "knight": "lunging-strike", "bishop": "blink",
                "rook": "fortress-guard", "queen": "royal-fury", "king": "royal-counter"}
LIGHT_SCALE = [1.0, 0.95, 1.35]          # pawn; others use 1.3 for the finisher
STAGGER_TICKS = 30
DEFEAT_TICKS = 60
# Presentation-only clips (no simulation counterpart; they are cosmetic and may be paced freely at runtime):
#   victory          held end pose (non-looping), distinct per class
#   hit_react_light  short flinch that returns to the ready pose (crossfades back to idle)
#   hit_react_heavy  bigger recoil with a stumble, also returning to the ready pose
VICTORY_TICKS = {"pawn": 96, "knight": 108, "bishop": 110, "rook": 120, "queen": 100, "king": 120}
HIT_REACT_LIGHT_TICKS = 14
HIT_REACT_HEAVY_TICKS = 24

# (startup_end, active_end, cancel_from) as fractions, from AttackLibrary for p/n; others mirror
# the nearest archetype. Used for the animation manifest and for choosing where the strike lands.
MARKERS = {
    "pawn": {"light_1": (0.30, 0.50, 0.72), "light_2": (0.30, 0.50, 0.72), "light_3": (0.38, 0.58, 0.92), "heavy": (0.50, 0.64, 0.95)},
    "knight": {"light_1": (0.38, 0.58, 0.75), "light_2": (0.38, 0.58, 0.75), "light_3": (0.45, 0.62, 0.92), "heavy": (0.55, 0.67, 0.95)},
}
MARKERS["bishop"] = MARKERS["queen"] = MARKERS["pawn"]
MARKERS["rook"] = MARKERS["king"] = MARKERS["knight"]

# World clips (pit / ladder sequence; presentation only, no simulation counterpart):
#   climb        loop, hands/feet alternate on a vertical ladder; body stays in place (root motion stripped), the
#                game moves the character UP along +Y at CLIMB_SPEED_MPS while it plays at speed 1.0
#   ladder_idle  loop, holding the ladder (the pose the climb passes through when one limb group has just reached)
#   drop_fall    loop, falling with limbs splayed
#   land         one-shot, crouch-impact then recover to the ready pose
# Ladder geometry the climb is authored against (shared with world/pit.py, which builds the ladder):
RUNG_SPACING = 0.25          # m between rungs
LADDER_PLANE_FWD = 0.42      # m in FRONT of the character's origin (character faces the ladder) where the rung centres are
CLIMB_TICKS = 72             # one cycle == 1.2 s == two rungs of travel (each limb advances two rungs per cycle)
LADDER_IDLE_TICKS = 120
DROP_FALL_TICKS = 40
LAND_TICKS = 36
CLIMB_SPEED_MPS = 2 * RUNG_SPACING / (CLIMB_TICKS / 60.0)   # 0.4167 m/s upward travel to avoid foot sliding

LOOPING = {"idle", "walk", "run", "strafe_left", "strafe_right", "block", "climb", "ladder_idle", "drop_fall"}
NOMINAL_SPEED_MPS = {"walk": 2.2, "run": 5.0, "strafe_left": 2.0, "strafe_right": 2.0}
LOOP_FRAMES = {"idle": 120, "walk": 40, "run": 30, "strafe_left": 40, "strafe_right": 40, "block": 40,
               "climb": CLIMB_TICKS, "ladder_idle": LADDER_IDLE_TICKS, "drop_fall": DROP_FALL_TICKS}


def clip_frames(cls: str) -> dict:
    """{clip name: frame count} for one class."""
    light, heavy, parry_w, parry_r = STATS[cls]
    finisher = LIGHT_SCALE[2] if cls == "pawn" else 1.3
    frames = dict(LOOP_FRAMES)
    frames.update({
        "light_1": round(light * LIGHT_SCALE[0]), "light_2": round(light * LIGHT_SCALE[1]),
        "light_3": round(light * finisher), "heavy": heavy,
        "parry": parry_w + parry_r, "dodge": DODGE[cls], "stagger": STAGGER_TICKS,
        "ability": ABILITY[cls], "defeat": DEFEAT_TICKS,
        "victory": VICTORY_TICKS[cls], "hit_react_light": HIT_REACT_LIGHT_TICKS, "hit_react_heavy": HIT_REACT_HEAVY_TICKS,
        "land": LAND_TICKS,
    })
    return frames


CLIP_NAMES = ["idle", "walk", "run", "strafe_left", "strafe_right", "light_1", "light_2", "light_3",
              "heavy", "block", "parry", "dodge", "stagger", "ability", "defeat",
              "victory", "hit_react_light", "hit_react_heavy", "climb", "ladder_idle", "drop_fall", "land"]
