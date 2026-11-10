"""Single source of truth for clip names, lengths and attack markers (frames == 60 Hz sim ticks).

Attack clip lengths equal the simulation's tick lengths so a clip plays 1:1 with the AttackDefinition
timeline in godot/combat/core/attack_library.gd. Pawn and Knight numbers are taken from that file
(lightTicks/heavyTicks x ticks_scale, parryTicks + recovery, lunge 72). Bishop/Rook/Queen/King have no
simulation stats yet: their lengths come from the legacy config (seconds * 60) and are PROPOSALS.
"""
CLASSES = ["pawn", "knight", "bishop", "rook", "queen", "king"]
ROLE = {"pawn": "p", "knight": "n", "bishop": "b", "rook": "r", "queen": "q", "king": "k"}

# lightTicks, heavyTicks, parryWindowTicks, parryRecoveryTicks
STATS = {
    "pawn": (24, 53, 11, 16), "knight": (32, 63, 13, 14), "bishop": (29, 59, 11, 16),
    "rook": (41, 74, 10, 18), "queen": (28, 58, 11, 14), "king": (32, 63, 13, 14),
}
DODGE = {"pawn": 22, "knight": 26, "bishop": 24, "rook": 30, "queen": 20, "king": 26}
ABILITY = {"pawn": 24, "knight": 72, "bishop": 30, "rook": 36, "queen": 30, "king": 40}
ABILITY_NAME = {"pawn": "last-stand", "knight": "lunging-strike", "bishop": "blink",
                "rook": "fortress-guard", "queen": "royal-fury", "king": "royal-counter"}
LIGHT_SCALE = [1.0, 0.95, 1.35]          # pawn; others use 1.3 for the finisher
STAGGER_TICKS = 30
DEFEAT_TICKS = 60

# (startup_end, active_end, cancel_from) as fractions, from AttackLibrary for p/n; others mirror
# the nearest archetype. Used for the animation manifest and for choosing where the strike lands.
MARKERS = {
    "pawn": {"light_1": (0.30, 0.50, 0.72), "light_2": (0.30, 0.50, 0.72), "light_3": (0.38, 0.58, 0.92), "heavy": (0.50, 0.64, 0.95)},
    "knight": {"light_1": (0.38, 0.58, 0.75), "light_2": (0.38, 0.58, 0.75), "light_3": (0.45, 0.62, 0.92), "heavy": (0.55, 0.67, 0.95)},
}
MARKERS["bishop"] = MARKERS["queen"] = MARKERS["pawn"]
MARKERS["rook"] = MARKERS["king"] = MARKERS["knight"]

LOOPING = {"idle", "walk", "run", "strafe_left", "strafe_right", "block"}
NOMINAL_SPEED_MPS = {"walk": 2.2, "run": 5.0, "strafe_left": 2.0, "strafe_right": 2.0}
LOOP_FRAMES = {"idle": 120, "walk": 40, "run": 30, "strafe_left": 40, "strafe_right": 40, "block": 40}


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
    })
    return frames


CLIP_NAMES = ["idle", "walk", "run", "strafe_left", "strafe_right", "light_1", "light_2", "light_3",
              "heavy", "block", "parry", "dodge", "stagger", "ability", "defeat"]
