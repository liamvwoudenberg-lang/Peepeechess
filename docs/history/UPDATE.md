> Historical development notes. The current 2D pieces, mobile packaging and invite links are described in README.md and MOBILE-START-HERE.md.

# Castle, overhead miniatures, and online deployment update

The supplied game now supports one shared miniature system in a straight-down orthographic view and the angled Castle view. Low-memory devices use a baked render of those same models, with quick move/capture effects and the existing accessible chess grid. Physical role crests distinguish every rank from above. Standing units are checked to fit within a square; mounted knights retain their height while their footprints fit the board.

Dawn Citadel, Silverwood Sanctuary, and Ossuary Keep now sit within castle halls: masonry walls, flagstones, galleries, windows, heraldic banners, a home throne, and faction details. White’s selected faction chooses the home castle and both factions are stored in the match. Both players see that same setup after reconnecting.

Online setup includes a faction selector, locked choices during search, cancel search, a connection preparation state, direct/server connection status, and clear online-unavailable handling. The prior learning, analysis, friends/chat, challenges, spectating and emotes remain available, with no assistance in human games.

## Vercel and PeerJS

- `vercel.json` builds the Vite client and routes `/api/chess` to a stateless Node Function.
- Upstash Redis persists identity, social data, queues, games and provisional ratings across Function instances. Locks and atomic Lua commits protect updates.
- PeerJS is loaded when joining a human match. Authenticated room/peer checks bind its reliable data channel to the opponent. Sync notifications prompt an authoritative HTTPS refresh; peer packets cannot inject positions, clocks, results or ratings.
- HTTP polling keeps the game playable when a peer channel cannot connect. Clocks start after both browsers are ready. Server validation handles turn order, legal moves, expected ply, increments, results and idempotent actions.
- The deployment can use a separate PeerServer and coturn-compatible TURN REST credentials. Per-player TURN credentials last one hour; the shared secret stays server-side.

The Vercel project is prepared, not deployed to a cloud account. Configure `UPSTASH_REDIS_REST_URL` and `UPSTASH_REDIS_REST_TOKEN` in Vercel, and provide managed TURN for restrictive networks. See `DEPLOY-VERCEL.md` for exact steps and `.env.example` for settings. Local development needs no cloud keys and persists to SQLite.

## Verification

- TypeScript and Vite production build passed. The official Vercel configuration schema check passed.
- 33 Node tests passed, including simultaneous matchmaking, authority, clocks, rating results, privacy, room authentication, temporary TURN credentials, rollback/serialization, all 324 battle profiles, 36 model/side/faction combinations and square footprints.
- Production browser tests passed friends, chat, challenges, spectating, emotes, reconnect, computer feedback selection, promotions, multi-move puzzles, keyboard/dialog focus, dragging, and responsive widths 320–1440 px, with zero browser errors.
- Real two-player matchmaking and move exchange passed; both clients shared White’s home castle and the same factions. Reconnect and server results passed. Search cancellation and locked setup fields passed.
- Actual overhead rendering and capture animations passed. Overlay/model square centers aligned within 0.01 px in the final browser check. All 324 staged encounters settled correctly; castling, en passant, capture underpromotion, checkmate with the king retained, and interrupted animations passed.
- Sixteen rendered battle replays kept the geometry count at 66 after warmup; no growth was observed. Showcase disposal removed its canvas.
- The browser environment enforces `WebRtcIPHandling=disable_non_proxied_udp`. PeerJS signaling and offer/answer exchange passed, but yielded zero ICE candidates. Gameplay was verified through the HTTP fallback; a live managed TURN/real-network peer channel and actual Vercel/Upstash deployment remain to be verified with your services. The software-rendered/manual-animation screenshots are visual checks, not hardware FPS benchmarks.

With 6× CPU slowdown, 4 simulated cores and 2 GB memory at 390×844, four moves reached two animation frames in 48–143 ms. No WebGL was loaded. Authentication also worked with AbortSignal.timeout unavailable, and sound/moves worked without a stereo-panner API.

Phone performance evidence, screenshots, detailed browser results and build/test logs are included under `docs/castle-online/`. Browser CPU/memory emulation is not physical-device certification.

## Run

Use Node.js 24 LTS. Run `npm ci` and `npm run dev`, then open `http://localhost:3000`. For the built local app: `npm run build` and `npm start`. The archive contains both source and the current production build. Choose Armory to inspect factions/castles, Top down for normal play, or Castle view for the same models in perspective.
