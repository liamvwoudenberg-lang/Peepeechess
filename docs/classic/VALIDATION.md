# Native Classic validation — 2026-11-07

Branch `codex/native-chess`, based on integrated architecture `c0dfe92`.
Godot 4.6.3 stable, Node 24.22.1, Linux. No combat-owned file was modified.

## Checks actually run

| Check | Result |
| --- | --- |
| `npm run lint` | Passed |
| `npm test` | 71 passed, 0 failed; existing web/Battle tests preserved |
| `npm run build` | Passed; the existing procedural-character chunk-size warning remains |
| `npm run test:contracts` | 23 Node tests, 21 Godot shared schema cases, malformed JSON rejection, and 9 exact Node→Godot→Node round trips passed |
| `npm run test:classic` | Passed: 83 engine checks, 53 authority/clock checks, 344 view/UI checks, differential corpus and main-scene smoke |
| Perft | Start position depths 1–4: 20 / 400 / 8,902 / 197,281; four special standard positions through depth 3: Kiwipete 48 / 2,039 / 97,862; rook/pawn endgame 14 / 191 / 2,812; promotion/castling position 6 / 264 / 9,467; tactical promotion position 44 / 1,486 / 62,379 |
| Differential reference | 72 seeded/special positions, 1,962 legal moves; legal sets, SAN, resulting FEN and undo matched existing chess.js |
| v1 native state compatibility | Real ongoing/special-move native MatchState snapshots passed Godot and Node/Ajv schema validation |
| Godot import and main scene | Headless import and scene smoke passed; runner rejects script/parse/resource errors even if process exits 0 |
| Native desktop execution | Ran and visually inspected the game with the Compatibility renderer on Mesa llvmpipe; played e4 in 2D and e5 through 3D ray selection, observed clocks/history, switched views, and inspected the narrow stacked layout |
| `git diff --check` | Passed before commit |

The view suite exercises actual 3D physics raycasts, 2D touch and drag/drop,
3D touch moves/swipe/pinch, promotion choice, 64-square transforms in both
orientations, both views' piece registries, state preservation across switches,
a second independently oriented view, and desktop/narrow board/dialog layout.
The input generator flushes buffered drag events as real frames do.

The authority suite covers seat/revision rejection, idempotent retries,
conflicting request IDs, clocks/increments, pause, timeout, insufficient mating
material at timeout (including a lone knight versus only enemy queens), untimed play, flag-before-move admission, local-only undo,
transactional invalid imports, stable identities across castling/EP/promotion,
agreed draws and resignation. Engine tests include checkmate/stalemate,
insufficient material, pinned EP, castling through check, all promotions,
repetition/claims/automatic draws, the mate/75-move priority, SAN/PGN and FEN.

## Issues caught and resolved

- The first 3D picking test exposed use of a nullable explicit `world_3d`
  property. Picking now queries the SubViewport's effective `find_world_3d()`;
  real physics selection and the rendered desktop move passed afterward.
- chess.js omits an EP target when no adjacent capturer exists, even with its
  force option. Native FEN follows the original FEN convention. The reference
  corpus explicitly supplies the passed square after double pawn moves rather
  than hiding the difference in a broad string comparison.
- Initial clock controls made the board scroll on desktop; adjusted spacing
  and history minimum height keep the complete board visible.
- The first FEN popup grew taller than the viewport because of auto-wrap
  minimum-size calculation. Predictable short instruction lines and explicit
  narrow dialog tests corrected it.

The desktop machine has no audio device and falls back to Godot's dummy audio
backend; this is unrelated to chess/rule validation. Automated headless runs
use task-local writable XDG directories and completed without script errors.

Not claimed: a physical Android run, Windows executable, platform exports,
native network/crossplay, AI play, production deployment, or an exhaustive
retrograde/tablebase solver for every possible blocked dead position. Native
network clock synchronization remains a versioned adapter follow-up; view
orientation/camera are deliberately not part of the v1 state. Hosted CI status
is reported in the PR, not assumed from local passes.
