# Repository audit

Inspected 2026-11-07 at `29e267b04daba6aaab0c8e4ce46c0d978e22aa15` (v1.3).
The initial checkout was clean on `work`. Remote refs advertised only `main` at
that SHA; `develop` did not exist. All six available history commits were
inspected for Godot/migration filenames and messages. No `.gd`, `.tscn`,
`project.godot`, `.blend`, or previous Godot migration was found. This statement
covers accessible Git history, not unpublished developer machines/branches.

## Implemented reference systems

| Area | Evidence and assessment |
| --- | --- |
| Runtime | React 19/TypeScript, Vite 8, Three.js; `src/App.tsx`, `src/next/`, `server.ts` |
| Classic | `chess.js` 1.4 legal moves, check, mate, castling, EP, promotions, repetition/draws; engine worker, coaching, lessons/puzzles, imports/analysis; server-side online adjudication |
| Board presentation | Drawn 2D sprites and Three.js 3D castles/miniatures; `src/next/Board.tsx`, `Scene.tsx`, `GameBoard.tsx`, `src/three/`; performance and reduced-motion options |
| Cosmetic capture effects | `src/game/battle2D.ts`, `src/next/Battle2D.tsx`, procedural 3D effects; these do not turn Classic captures into competitive combat |
| Battle Chess | `src/battle/BattleChess.tsx`, `rules.ts`, `session.ts`; both board views, local two-player or private room; capture combat, custom defender outcome, separate save/history |
| Combat | `simulation.ts`, `config.ts`, `controls.ts`, `CombatArena.tsx`, `ArenaRenderer.ts`, `fighterModel.ts`; 60 Hz, six fighter configurations, stamina/parry/dodge/specials, 90-second duel, deterministic defender ties; kings are excluded from real duels |
| Classic online | `server/onlineService.ts`, `onlineStorage.ts`, `onlineHandler.ts`, `api/chess.ts`, `src/next/PeerTransport.ts`; API authority, PeerJS notifications, authenticated polling fallback, SQLite locally/Redis on Vercel, profiles/matchmaking/social/invites/clocks/ratings |
| Battle online | `server/battleServer.ts`, `RoomClient.ts`; persistent WSS host, secret seat credentials, input sequence checks, server combat, snapshots; rooms in one process memory, no ranked queue/durable recovery |
| Older multiplayer | `server/chessService.ts`, `store.ts` WebSocket compatibility; separate identity/persistence from active PeerJS/HTTP UI |
| Native Android | Capacitor 7 wrapper in `android/`, API/target 35, min 23, AGP 8.7.2, Gradle wrapper 8.11.1; this is not a Godot Android export |
| Other variants | `src/variants/` and older components contain Chess960, three-check, atomic/crazyhouse/king-of-hill helpers and tests. They are reference/prototype code, not evidence of fully exposed polished modes. Do not migrate them as production requirements silently. |

## Assets and dependencies

The royal, elves and skeletons factions share role identity and cosmetic colors
through `src/game/legionIdentity.ts`. Existing 3D figures, weapons, castles,
animations and procedural audio are built in code, not a Blender/glTF pipeline.
`public/pieces/` has editable SVGs and PNG/WebP atlases for front/top/drawn pieces
and battle bodies; `scripts/draw-legions.ts`, `render-pieces.py` and
`render-drawn-pieces.py` are existing generation tools. Python rasterization uses
Playwright/Chromium. Preserve these assets; do not assume they are rigged models
or imported animation clips usable in Godot.

The lockfile is the dependency source of truth. Important existing dependencies:
chess.js, Three.js, React, Express, ws, PeerJS/peer, Capacitor, motion, Tailwind,
Vite, tsx, TypeScript and @google/genai. A cloud AI key is not required for local
play. Redis credentials/TURN configuration are deployment concerns; no credential
was configured in this environment. New foundation dependency: Ajv 8.17.1 for
schema verification in Node tooling. No Godot addons are required.

## Verification scope

Before changes: `npm test` passed 69 tests and `npm run lint` passed. Existing
browser/APK verification files are historical evidence, not reruns in this task.
Current foundation checks are recorded separately in
`docs/development/VALIDATION.md`. Native crossplay, Windows execution, physical
Android behavior and production deployment remain unverified by this task.
