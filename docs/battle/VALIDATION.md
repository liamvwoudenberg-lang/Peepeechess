# Battle C0 validation — 2026-11-07

**Real-combat acceptance is incomplete.** No native Claude arena/scripts exist
in the inspected remote branches or the local Claude worktree. The default
`res://combat/arena.tscn` is missing. This report distinguishes tested integration
from actual player-controlled combat, which could not be run.

Base `8b13047` integrates Classic PR #1, whose hosted CI passed before merge.
The Battle work is isolated on `codex/battle-loop`; no combat-owned files changed.
Godot 4.6.3 stable, Node 24.22.1, Linux.

| Check actually run | Result |
| --- | --- |
| `npm ci` | Passed in the feature worktree |
| `npm run lint` | Passed |
| `npm test` | 71 passed, 0 failed |
| `npm run build` | Passed; existing large procedural-character chunk warning remains |
| `npm run test:contracts` | 23 Node tests, 21 Godot shared cases, malformed JSON rejection and 9 exact cross-engine round trips passed |
| `npm run test:classic` | 83 engine, 53 match/clock and 345 view/UI checks passed; 72 reference positions / 1,962 legal moves matched chess.js; main scene smoke passed |
| `npm run test:battle` | 250 match/rules, 50 flow, 9 real-adapter lifecycle and 31 UI checks passed (340 total) |
| C0 differential corpus | 106 seeded/special positions, 747 outcomes matched existing TypeScript C0 legal moves, successor boards and terminal results |
| Native v1 snapshots | Actual settled Battle MatchState payloads passed Godot and Node/Ajv schema validation |
| Godot main project | Headless import/startup passed; native desktop launched on Mesa llvmpipe using the dummy audio driver |
| Native manual UI | Selected Battle C0, played e4/d5, opened e4xd5 capture preview, observed disabled Start battle and the unavailable-combat explanation, canceled, and confirmed both pawns/history/turn remained correct |
| `git diff --check` | Passed before commit |

The match tests cover attacker/defender wins, check/pins/king restrictions,
EP victim squares and discovered check, all capture promotions and quiet
promotion, castling legality/rook rights, Black fullmove counters, C0 automatic
draws, mate/stalemate, stable identities, one-time settlement, and phase/input
locks. They reject wrong source, match/battle/player/revision, impossible timing,
invalid causes/HP, NaN/Infinity/fractional ticks, conflicting terminal snapshots
and frozen-board changes. Validated results survive cancellation/resignation of
presentation, while an already terminal mate cannot be overwritten.

The flow tests run four successive captures with alternating outcomes in one
match, then a continuing quiet move. They exercise preview cancellation, late
loader callbacks, loading/start failure, timeout, invalid results, duplicate
terminal signals, result/return interruption and new-match invalidation.

The real adapter test loads a **protocol-only test scene** asynchronously,
checks its root API, passes both combatants intact to initialization, forwards
snapshot/result signals, stops it and rejects stale callbacks. A separate
incompatible scene is rejected. Neither fixture has characters, attacks or
winner logic; neither is a production arena/fallback.

The UI tests inject an explicit test double to check loading/countdown/result
presentation and return animations, both board preferences and perspectives,
consistent survivor registries, mode switches, narrow preview layout and touch
Start battle. A test caught and fixed touch mouse-emulation requirements;
boards filter emulated events and disable their raw touch callbacks during
combat so input can reach the arena. Classic touch selection and the New game
button are covered by the regression suite.

Still required: Claude's native combat branch/PR, actual fighter/controller
initialization, real input/damage/countdown/result behavior, and end-to-end
repeated capture play with that component. Native online authority, physical
Windows/Android runs, exports, persistent process-crash recovery and the newer
king-gauntlet ruleset are not claimed. This draft should not be treated as a
completed real-combat build merely because the deterministic checks pass.
