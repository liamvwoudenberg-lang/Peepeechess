# Battle C0 validation — 2026-11-10

**Pawn/Knight combat integration works; full-roster acceptance remains incomplete.**
Claude's published branch `ccr-a4637d6e-lypbb4` through `2bc368d` is merged into
`codex/battle-loop`, based on integrated develop `b4c6dab`. This includes the real
arena, input controllers, simulation, generated character/arena GLBs and clips.
Imported combat-owned files match Claude's published versions; Codex edits only
the adapter, chess/app layer, integration tests, root configuration and docs.

The combat module explicitly supports only Pawn and Knight mechanics. Its
Bishop, Rook, Queen and King models do not supply corresponding simulation.
Unsupported captures are disclosed before Start; cancellation preserves state.
King combat is outside the requested C0 rules and belongs to the v2 gauntlet.
This draft must not be represented as a finished full Battle Chess match.

Environment: Godot 4.6.3 stable, Node 24.22.1, Linux, Mesa llvmpipe/dummy audio.

| Check actually run | Result |
| --- | --- |
| `npm run lint` | Passed |
| `npm test` | 74 passed, 0 failed, including Claude's import/combat-suite/standalone-arena wrapper |
| `npm run build` | Passed; existing large procedural-character chunk warning remains |
| `npm run test:contracts` | 23 Node tests, 21 Godot cases, malformed JSON rejection and 9 exact cross-engine round trips passed |
| `npm run test:classic` | 83 engine, 53 match/clock, 345 view/UI checks; 72 positions / 1,962 legal moves matched chess.js; main import/smoke passed |
| `npm run test:battle` | 250 match/rules, 50 flow, 9 protocol-adapter, 31 fixture-UI and 137 real-combat integration checks passed (477 total) |
| C0 reference corpus | 106 seeded/special positions, 747 outcomes matched TypeScript C0 legal moves, successor FEN and terminal results |
| Real native combat | Played e4/d5/exd5 in the rendered app; moved/attacked using keyboard controls, reduced HP, completed a duel and returned to the continuing board |
| Latest generated assets | Restarted on `2bc368d`, saw imported fighters/arena and animations, played Black's controls to a defender knockout; Black pawn stayed on d5, White pawn disappeared, Black moved next, history recorded `[defended]` |
| Godot project | Headless import and main scene smoke passed; no script/parse/resource errors; desktop driver issued only an unsupported V-Sync warning |

`real_combat_test.gd` loads the actual arena through the production asynchronous
adapter and sends only v1 CombatInput via its authenticated-seat bridge. It does
not change fighter HP, position, attack states or results. Seven real knockout
battles cover a continuous four-capture match, attacker/defender wins, Black as
attacker, en passant, both outcomes of capture underpromotion, and capture
checkmate with both kings retained. Every result crosses the actual arena
signals and chess validation, preserves the frozen board through aftermath,
commits once, returns to the board, and cannot replay after scene teardown.
The continuous match also terminates by resignation after repeated real fights.

The same suite checks input seat spoofing/extra health fields, initialization
error normalization, interruption without an invented winner, unsupported-role
disclosure, and Classic after combat teardown. In each 2D/3D preference it mounts
the real animated arena, verifies two human controllers/cameras with no AI,
routes physical F/J input through nested viewports, and retains board preference
and perspective after return. The headless suite verifies model/clip mounting;
rendered desktop verification supplements this with actual visuals and controls.

The independent match tests cover check/pins, king restrictions, EP discovered
check, promotions, castling/rights, Black counters, C0 automatic draws,
mate/stalemate, stable IDs and one-time settlement. They reject wrong authority,
IDs/revision, impossible timing/cause/HP, nonfinite/fractional ticks, conflicting
terminal snapshots and changed frozen state. Accepted results survive
cancellation/resignation without overwriting already terminal checkmate.

Fixture flow tests deliberately cover failures and invalid results independently
of fighter inputs: preview/loading cancellation, late load callbacks, start
failure, timeouts, forged/duplicate results, interrupted aftermath/return and
new-match invalidation. Fixtures never supply a production fallback. UI fixture
tests also cover narrow preview layout, touch Start and consistent survivor
registries. Classic touch controls are regression tested separately.

Remaining acceptance: Claude must publish Bishop/Rook/Queen mechanics and tests;
Codex must merge them and extend real integration cases to all supported roles.
Native combat touch controls, online hosting/credentials, physical Android/Windows
runs, exports, persistent process-crash recovery and king-gauntlet v2 are not
claimed. Local test success is not evidence of hosted CI until GitHub reports it.
