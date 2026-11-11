# Persistent board world contract — version 2

Accepted user direction, 2026-11-11. This supersedes the separate combat scene
and independent drawn 2D renderer for the native application. Legacy web and
native v1 resources remain compatibility references, not the new application path.

Public schemas and fixtures: `godot/contracts/v2/`, `network/v2/` and
`application/v2/`. Native protocol is `peepeechess-enet-v2`. All schemaVersion
fields, including nested payloads, are 2. Shapes otherwise retain v1, except the
only allowed arenaId is `board-v1`. Classic/Battle chess rules and authoritative
state ownership remain unchanged. Existing v1 schemas and fixtures are immutable.

## One world, one board, one active camera

The board is stationary, one metre per square, edges x/z = -4..+4 and top y=0.
Algebraic mapping remains a1=(-3.5,0,+3.5), h8=(+3.5,0,-3.5). The board root,
64 tile meshes, picking bodies and World3D persist through camera switches and
all repeated capture encounters. No board scaling, position/rotation animation,
scene reload, separate arena visuals or loading screen may occur during a duel.

The top-down 2D-style view is the same 3D board under an overhead orthographic
camera. Perspective and third-person are camera poses, not separate renderers.
Each online client owns its camera. Camera preferences never enter match rules.
A single board Camera3D remains active; a reused ThirdPersonCamera may calculate
a target pose without becoming the rendered camera. Camera pose/projection/FOV
blend on entry and return. Only the camera and the two fighter representations
animate, never the board. Board input is locked throughout the encounter/return.

## Board encounter adapter

The public BattleRequest identifies original attacker/defender squares and
capture destination. Fighters initialize at their **original square centres**
and face one another. En passant uses defender.square for its pawn victim,
not the empty destination. Survivors return to request.to on attacker victory,
or defender.square on defender victory. Other pieces retain their transforms.
Only the two participants take combat damage. Nonparticipant piece meshes remain
nonblocking presentation; they do not become extra combatants or obstacles.

Actors use unchanged one-metre world units, y=0 and existing fighter stats.
Authoritative square edge collision prevents movement, dodge, knockback and
Blink beyond the board. The legacy circular emergency backstop lies outside
all board corners and must not substitute for the board edges. Tile picking
uses a separate physics layer; picking geometry must not block fighter capsules.
The camera may hover outside the board edge to frame corner encounters; fighter
containment must not trap the camera behind an invisible wall.

Reuse Claude's FighterController, CombatStateMachine, movement, hit detection,
abilities, models, input, HUD and audio. A Codex-owned CombatSimulation subclass
may replace lifecycle initialization only (geometry and square spawns), inheriting
all input/tick/damage/result logic. No StoneArena or combat arena scene is
instantiated by that board subclass. It creates only square collision boundaries.
The presentation host creates existing CharacterModel objects in the board's
World3D, with no second visible arena or combat viewport.

Private compatibility adapters deliberately retain v1 component DTOs inside the
process. They convert schemaVersion/arenaId at the public v2 boundary; a private
stone-v1 label must never select legacy geometry in a v2 match. The selected
layout is immutable on the match session, derived from negotiated protocol.
Old v1 sessions/rooms stay explicit legacy; mixed-version joins/resume are refused.
No silent downgrade and no client-selected spawn positions. Persisted game
records keep their existing backend HTTP interface; no rating authority changes.

## Prediction and unfinished roles

Existing circular-arena prediction must not be enabled unchanged on the square
board. Reconciliation/interpolation may be reused with a board-aware geometry
adapter; until verified, snapshots remain authoritative and prediction is
reported unavailable. Rendering quality never changes server simulation ticks.

This milestone preserves `battle-checkmate-v1` C0 legality and traditional mate.
King combat is still unsupported by the owner simulation. The user's royal
last-chance sequence needs an explicitly versioned ruleset and owner mechanics;
never enable king captures or remove a checked king as an incidental camera fix.

## Required proof

Record board/tile/World3D identities and transforms before, throughout and after
a real input-driven capture. Exercise overhead/perspective switches, independent
client preferences, both battle outcomes, en passant/promotion, repeated captures,
interruption, disconnect, invalid results and cleanup. Test square spawn/bounds
and cross-language v2 serialization. Existing v1 rule/combat suites remain intact.
