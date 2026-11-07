# Sovereign’s Gambit

Classic chess inside a fantasy castle. The game opens in a 3D castle, with a lightweight drawn 2D board available any time. Choose a legion before starting; both views share its livery, faces, weapons and familiar chess silhouettes. White’s faction determines the home castle for both players.

## Battle Chess — 3D Combat

Choose **Battle Chess — 3D Combat** from Play or More. Quiet chess moves stay familiar; captures become real player-controlled third-person fights. Play with two people sharing a device, or use a private room on the included authoritative Node/WebSocket host. Attacker and defender victories have explicit variant rules; Classic Chess keeps its existing rules and features. The static Vercel site supports local Battle Chess, while private combat rooms need a persistent server. See [BATTLE-CHESS.md](BATTLE-CHESS.md) for controls, complete rules, hosting, architecture and limitations.

## Phone and Android APK

Start with [MOBILE-START-HERE.md](MOBILE-START-HERE.md). The Android APK bundles offline computer play and connects to https://cheesy-indol.vercel.app for multiplayer. The installable web app supports iPhone/Android browsers. The live API must be healthy and have its Redis variables configured for online matches.

## Clear menus and a full-screen match

Main navigation is **Play, Learn, Friends, More**. More contains puzzles, the armory and battle previews, analysis, PGN/FEN import, profile and appearance settings. Match settings disclose the computer strength, side, clock and feedback controls; the summary shows the chosen values before Play.

Active matches fill the available window. **Moves and game options** opens the move history, chat, game actions and optional coaching drawer. **Menu** returns to the normal app; the browser fullscreen control can hide browser chrome where supported. Both clocks stay beside the square 2D board. In 3D, camera-facing elven trees cut away so scenery cannot cover the pieces.

Menus and fixed controls respect phone safe areas in both orientations. An unavailable online server shows a short notice with **Retry**; the host setup steps are in [DEPLOY-VERCEL.md](DEPLOY-VERCEL.md#if-the-app-says-offline-practice). Vercel's `KV_REST_API_URL`/`KV_REST_API_TOKEN` and Upstash's REST credential pair are both supported.

## Run locally

Use Node.js 24 LTS (22.13+ also supports the local SQLite store).

```sh
npm ci
npm run dev
```

Open http://localhost:3000. No cloud key is required locally. The Node server persists data in `.data/chess.sqlite`, serves the game API, and starts a local PeerJS signaling service. Change `PORT` or `CHESS_DATABASE` in your shell if needed. For a local production build:

```sh
npm run build
npm start
```

For play across devices, use the same reachable HTTPS website. Separate browsers/profiles represent separate players. Localhost is treated as a secure context by browsers; a plain HTTP LAN address may restrict WebRTC. The authenticated server fallback still handles moves when direct connectivity is unavailable.

## Vercel and PeerJS

See [DEPLOY-VERCEL.md](DEPLOY-VERCEL.md). The Vite client and stateless `/api/chess` Function are ready for Vercel; persistent online data uses Upstash Redis. Set its REST URL/token in Vercel, then deploy. Missing cloud storage is shown explicitly, while computer and learning modes remain playable.

PeerJS carries direct match sync notifications. Every position, move, clock, result and rating is verified by the API. An encrypted peer message cannot supply a trusted FEN or grant assistance. When a peer channel cannot connect, authenticated HTTPS polling keeps the match playable. The clock starts after both browsers are ready. Configure TURN over TLS/TCP for reliable WebRTC on restrictive networks.

The earlier Node WebSocket service remains as a compatibility implementation and is tested, but the running UI now uses the PeerJS/HTTP API. Online profiles for this transport use `sg-peer-session-v3`; its SQLite records and Redis namespace are separate from the earlier prototype profiles. Do not assume that an old local SQLite file is automatically migrated to a new Redis deployment.

## Board, characters, and castles

- **3D castle** opens by default on capable devices, including the pre-game preview. Both sides have stronger livery contrast, readable role markers, and contrasting pedestal rims. Auto performance mode keeps older phones on the lightweight board. You can choose 2D before a game and keep that choice when play starts.
- **Choose your legion** appears before computer games and matchmaking, in friend-link previews, and before sending/accepting friend challenges. Local and online matches keep the chosen factions fixed. Cosmetics do not change legal moves or strength.
- **2D pieces** are original ink drawings: round-headed pawns, horse-profile knights, split bishop mitres, rook battlements, five-point queen crowns and king crosses. Elven ears, skull faces, shields and signature weapons are drawn relatives of their 3D counterparts. White stays ivory; Black wears obsidian, red and purple. Drawings and models share `src/game/legionIdentity.ts`.
- **Board contrast** uses quieter midtone squares and matte 3D materials, with at least 3:1 contrast between the armor source colors and every board square. This is a source-color check, not a measurement of every lit 3D pixel. Strong ink edges keep illustrated pieces readable on both colors.
- **Light graphics** uses a roughly 225 KB WebP atlas with PNG fallback, preserves touch/drag/keyboard play, and avoids WebGL. Editable artwork is `public/pieces/legions-drawn.svg`; regenerate it with `npm run art:draw`, then rasterize both the complete figures and separate battle bodies with `python scripts/render-drawn-pieces.py`. Rasterization requires Playwright/Chromium, but no running server.
- **Royal Guard** hosts Dawn Citadel, **Silverwood Elves** host Silverwood Sanctuary, and **Hollow Legion** hosts Ossuary Keep. The halls contain masonry walls, flagstone floors, galleries, windows, banners, a home throne, and faction details. There is no floating mountain backdrop or photograph texture download.
- White always uses ivory/angelic armor and gold. Black uses obsidian, crimson and purple. Knights have real horses, including a skeletal mount. Both players see the actual factions chosen for that match.
- Eighteen signature weapons and attack performances combine with six target reactions and faction defeat effects: 324 deterministic matchup profiles. These are procedural combinations, not 324 individually authored animation clips. Kings remain on the board at checkmate; king-target previews are explicitly staged.
- **2D fights** have all 18 attack signatures: independently moving swords, lances, bows, hammers, axes, scythes and spells. Figures parry and recoil; armour fragments, elven petals or skeletal bones follow the captured faction. The illustrated bodies stay upright while weapons aim toward the opponent. En passant attacks the actual victim square, promotion keeps the chosen piece, and castling moves both figures. The effects use browser transform/opacity animations without loading Three.js.
- Choose full, brief, or off animation settings. Online battles remain brief, moves and clocks update immediately, and a new move settles unfinished cosmetic effects. Armory includes a matchup preview and a close control. Low-power mode keeps optional previews off.
- Cinematic 2D captures last about 1–1.25 seconds; brief fights take 480 ms, competitive fights at most 460 ms, and Light mode 340 ms with no particles. Reduced motion (including the operating-system setting) and Off show the result immediately. In untimed computer games the worker calculates during a capture and applies its reply after the fight; pause cancels that pending reply. Timed games and human opponents never wait for an animation.

## Chess, learning, and social play

- Standard legal chess: castling, en passant, all promotion choices, repetition and fifty-move draws, checkmate/stalemate, time controls and increments, resignation, agreed draws, move history, PGN export/import, separate analysis, reconnect and game archives.
- Human matchmaking by time control with provisional Blitz/Rapid Elo; no bot is inserted into an empty queue. Games against humans and live spectating have no hints, analysis worker or move-quality feedback.
- Computer strength is **simulated 400–2000 Elo**, with optional feedback selected before play. It is not calibrated against a human pool and does not claim Stockfish or Chess.com review accuracy. Computation runs in a worker.
- Private, single-use friend invite links with side/time selection and a guest preview, plus friends by code and acceptance, persistent private chat, unread messages, friend challenges, spectating with privacy controls, removing friends, and six emotes with cooldown/mute.
- Six verified beginner lessons and four board puzzles, including a multi-move fork with the defending reply. Assisted attempts are labeled.

Browser-held random secrets restore a profile; this MVP does not provide email sign-in or account recovery. Clearing browser storage loses the local identity. Friend codes add friends and are not recovery credentials. Back up the SQLite file or your cloud database using the provider’s tools.

## Verify

```sh
npm run lint
npm test
npm run build
```

Node tests cover chess, persistence, parallel matchmaking, authentication/permissions, social actions, clocks/ratings, all 324 battle profiles, 36 miniature models, recognizable role silhouettes, and bounded arena geometry. Browser tests require Playwright and Chromium; use `BASE_URL` to select the running server.

```sh
BASE_URL=http://localhost:3000 python tests/legions-browser.py
BASE_URL=http://localhost:3000 python tests/focus-navigation-browser.py
BASE_URL=http://localhost:3000 python tests/browser.py
BASE_URL=http://localhost:3000 python tests/interaction.py
BASE_URL=http://localhost:3000 python tests/battle2d-app-browser.py
BASE_URL=http://localhost:3000 python tests/mobile-safe-area-browser.py
```

The 2D choreography fixture runs only on the development server: `BASE_URL=http://localhost:3000 python tests/battle2d-browser.py`. It is excluded from the production bundle. Current 2D results are in [docs/battle2d/VERIFICATION.md](docs/battle2d/VERIFICATION.md).

Phone safe-area reproduction, retry recovery and Android 1.2.1 results are in [docs/mobile-safe-area/VERIFICATION.md](docs/mobile-safe-area/VERIFICATION.md).

For the current phone/invite checks, run `BASE_URL=http://localhost:3000 python tests/mobile-invite-browser.py`. Results and screenshots are in [docs/legion-update/VERIFICATION.md](docs/legion-update/VERIFICATION.md).

The browser evidence and deployment notes distinguish a real connection test from simulation. Older-phone checks use browser CPU/memory emulation, not physical-device certification. No cloud deployment is implied by a successful local build.

## Main source

- `src/App.tsx`, `src/next/`: UI, modes, board, worker, learning and social screens.
- `src/next/PeerTransport.ts`: lazy PeerJS connections, authenticated HTTPS fallback, retries and refresh handling.
- `api/chess.ts`, `server/onlineHandler.ts`, `server/onlineService.ts`: Vercel-compatible online API and authority.
- `server/onlineStorage.ts`: durable local KV and Redis locking/atomic commits.
- `src/three/`: shared miniature models, orthographic/perspective cameras, castle architecture and battles.
- Older components and analytics/variant prototypes remain reference code and are not exposed as unfinished game modes.

## Godot migration and two-agent development

The working web/Capacitor game is preserved. The native Godot client in
`godot/` now supports local Classic Chess in 2D and 3D, pinned to Godot 4.6.3.
Native online and Battle integration remain separate migration steps. Start with [the repository audit](docs/architecture/REPOSITORY_AUDIT.md),
[architecture](docs/architecture/ARCHITECTURE.md),
[migration plan](docs/architecture/MIGRATION.md),
[shared v1 contracts](docs/architecture/CONTRACTS.md), and
[Battle rules](docs/architecture/BATTLE_RULES.md).

Before editing, read [collaboration/worktrees](docs/development/COLLABORATION.md)
and [file ownership](docs/development/OWNERSHIP.md). Run the checks in
[toolchain](docs/development/TOOLCHAIN.md); current results are recorded in
[validation](docs/development/VALIDATION.md). Integration targets `develop`.

## Native Classic Chess (Godot 4.6.3)

Run `godot --path godot` for local two-player Classic Chess in illustrated 2D
or interactive 3D. Both views share one match, with legal moves, clocks,
promotion, notation, FEN, draw claims and local undo. See
[controls and architecture](docs/classic/CLASSIC.md) and
[Classic validation](docs/classic/VALIDATION.md). Run `npm run test:classic`.
Native online transport and combat integration are separate follow-up work.

## Native Battle C0 integration

The mode selector exposes the C0 Battle board, capture previews and the native
scene adapter. See [integration and combat handoff](docs/battle/INTEGRATION.md)
and [validation](docs/battle/VALIDATION.md). The real native combat scene has not
been supplied in the available branches, so Start battle is disabled in this
build. Deterministic tests exercise the complete transaction/transition sequence
with a test-only double; they do not certify real combat. Run `npm run test:battle`.
