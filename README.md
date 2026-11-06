# Sovereign’s Gambit

Classic chess inside a fantasy castle. The default 2D board uses front-facing illustrations of the shared 3D characters; the optional Castle view brings them into a real castle hall. White’s faction determines the home castle for both players.

## Phone and Android APK

Start with [MOBILE-START-HERE.md](MOBILE-START-HERE.md). The Android APK bundles offline computer play. The installable web app supports iPhone/Android browsers. Online invite links require deploying the included website; no public URL exists yet.

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

- **2D pieces** is the default familiar chessboard: front-facing illustrations baked from the same 3D character models, with a horse knight, bishop’s split mitre, rook battlements, queen crown and king cross. Pieces remain upright for both White and Black.
- **Light graphics** and the standard 2D board use an approximately 150 KB WebP atlas with PNG fallback, plus brief piece-specific move/capture effects. They create no WebGL context. Tap, drag, keyboard navigation, promotion, check highlights and premoves remain available. The atlas script is `scripts/render-pieces.py`; it needs a running Vite server and Playwright/Chromium.
- **Royal Guard** hosts Dawn Citadel, **Silverwood Elves** host Silverwood Sanctuary, and **Hollow Legion** hosts Ossuary Keep. The halls contain masonry walls, flagstone floors, galleries, windows, banners, a home throne, and faction details. There is no floating mountain backdrop or photograph texture download.
- White always uses ivory/angelic armor and gold. Black uses obsidian, crimson and purple. Knights have real horses, including a skeletal mount. Both players see the actual factions chosen for that match.
- Eighteen signature weapons and attack performances combine with six target reactions and faction defeat effects: 324 deterministic matchup profiles. These are procedural combinations, not 324 individually authored animation clips. Kings remain on the board at checkmate; king-target previews are explicitly staged.
- Choose full, brief, or off animation settings. Online battles remain brief, moves and clocks update immediately, and a new move settles unfinished cosmetic effects. Armory includes a matchup preview and a close control. Low-power mode keeps optional previews off.

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
BASE_URL=http://localhost:3004 python tests/browser.py
BASE_URL=http://localhost:3004 python tests/interaction.py
```

For the current phone/invite checks, run `BASE_URL=http://localhost:3000 python tests/mobile-invite-browser.py`. Results and screenshots are in [docs/mobile/VERIFICATION.md](docs/mobile/VERIFICATION.md).

The browser evidence and deployment notes distinguish a real connection test from simulation. Older-phone checks use browser CPU/memory emulation, not physical-device certification. No cloud deployment is implied by a successful local build.

## Main source

- `src/App.tsx`, `src/next/`: UI, modes, board, worker, learning and social screens.
- `src/next/PeerTransport.ts`: lazy PeerJS connections, authenticated HTTPS fallback, retries and refresh handling.
- `api/chess.ts`, `server/onlineHandler.ts`, `server/onlineService.ts`: Vercel-compatible online API and authority.
- `server/onlineStorage.ts`: durable local KV and Redis locking/atomic commits.
- `src/three/`: shared miniature models, orthographic/perspective cameras, castle architecture and battles.
- Older components and analytics/variant prototypes remain reference code and are not exposed as unfinished game modes.
