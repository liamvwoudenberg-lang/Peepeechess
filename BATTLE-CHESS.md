# Battle Chess — 3D Combat

Battle Chess is integrated into Sovereign’s Gambit. It is a separate, playable chess variant: an attempted capture opens a real-time third-person fight, and the surviving piece determines the board result. Classic Chess still uses its existing chess.js history, computer worker, coaching, online authority, social features, puzzles and analysis.

## Launch and play

Use Node 24 LTS (22.13+ is supported).

```sh
npm ci
npm run dev
```

Open http://localhost:3000. Select **Battle Chess — 3D Combat** from the main Play screen or More menu. An active Classic match must finish before switching modes; a Battle friend link can open the separate mode directly. Choose the White and Black legions and select **Start Battle Chess** for two people sharing a device.

A quick full-loop example is **e2–e4, d7–d5, e4×d5**. Both players then control their pawns in the arena. Walk toward each other, attack, guard, parry and dodge. The winner returns to the board; Black then takes the next chess turn. No combat bot or random winner substitutes for the second person.

The board supports illustrated pieces or the existing 3D castle, legal destinations, capture rings and all four promotion choices. Match options contain pause/resume, key bindings, restart, draw offers, resignation and exit. Battle Chess has its own match chronicle and results panel. Local games, including an unfinished duel, save independently under `sg-battle-local-v1`; exiting saves and pauses them. Resume is explicit. Classic storage is not overwritten.

## Controls

| Action | White / single-client player | Black on a shared keyboard | Gamepad |
| --- | --- | --- | --- |
| Move / strafe | WASD | Arrow keys | Left stick |
| Camera | Middle-mouse drag or touch drag; wheel changes distance | Drag Black’s arena | Right stick |
| Light | Left mouse | J | X |
| Heavy | Right mouse | K | Y |
| Sprint | Left Shift | Enter | LT |
| Dodge | Space | L | A |
| Hold block | Q | U | LB |
| Parry | E | I | RB |
| Special | R | O | B |
| Target lock | Tab | P | Left-stick click |
| Match menu | Escape or Menu | Menu | Touch/click Menu |

The first two connected gamepads control White and Black locally. In a private room, the connected player's own fighter uses the primary controls regardless of color. Keyboard bindings can be changed in **Controls and key bindings**; reset restores the defaults. Conflicting shared-keyboard bindings are rejected. Key remaps apply to the current duel.

Touch controls have one joystick and separate action buttons for each player. Push a joystick to its edge to sprint. Drag an empty part of that player's arena with touch or the middle mouse button to orbit; target lock keeps the opponent framed, and Free look allows free camera rotation. Pointer capture and separate pointer IDs allow simultaneous movement, camera and actions. Shared-device cameras stack in portrait and sit side by side in landscape. Touch actions use at least 44px targets. A tablet or two gamepads gives shared-device players more physical space than a small phone.

## Complete variant rules

1. Quiet moves, check constraints, ordinary movement, castling through safe squares and promotion legality come from chess.js. The variant owns its FEN, history, repetition counts, pending capture and resolution state.
2. A legal capture is first checked for **both** outcomes. The original FEN, origin, destination, promotion, attacker and actual defender square are recorded. The board remains unchanged during the fight. A second chess move cannot be submitted until the duel finishes.
3. **Attacker victory:** perform the ordinary capture. The attacker occupies its intended destination and the turn ends.
4. **Defender victory:** remove the attacker from its original square; keep the defender where it was; clear en passant; reset the half-move counter; update castling rights and the full-move counter; pass the turn. This is a custom variant operation, not a fabricated chess.js move.
5. **King safety:** kings cannot be captured or initiate capture duels. They can move to safe empty squares and castle. Any other capture is unavailable if removing its attacking piece would leave that player's king attacked after a defender victory. This also restricts captures of a checking piece. Select or drag toward a restricted capture to see the reason. These restrictions intentionally make checks stronger than in Classic Chess.
6. **Checkmate / stalemate:** evaluate the remaining Battle-legal moves. A checked player with none loses by checkmate; an unchecked player with none draws. Kings stay on the board.
7. **En passant:** fight the pawn on its real square. An attacking victory removes that pawn and lands on the empty en-passant destination. A defending victory removes the attacking pawn and keeps the defender on its original square. Both outcomes pass the turn and expire the right.
8. **Promotion:** select queen, rook, bishop or knight before a promotion move. A capturing pawn fights as a pawn and promotes only if it wins. A failed capture never creates a promoted piece. Quiet promotion works normally.
9. **Castling rights:** moving or losing an original rook removes that side's corresponding right. A defending original rook retains its right when it wins and stays put. Normal successful captures use chess.js's rights handling.
10. **Draws:** insufficient material, fifty moves and threefold repetition are automatic. Repetition includes side and castling rights, and only includes an en-passant right when it is usable under Battle rules. Between duels, both players can also agree to a draw. A move expires outstanding offers.
11. **Combat starts fresh:** HP, stamina, cooldowns, buffs and combo state reset for each capture. There is a three-second countdown, then a 90-second duel. Chess itself is untimed in this first ruleset.
12. **Combat victory:** a knockout wins immediately. At the combat time limit, the higher percentage of original HP wins. An exact percentage tie or simultaneous knockout lets the defender hold. This deterministic tie rule is shown in the result. No random crits, dodges or winner selection are used.
13. **Abandonment:** shared-device play pauses when hidden and checkpoints separately. A server-room disconnect does not pause the fight: inputs become neutral after 250 ms, credentials permit reconnection, and a missing player forfeits the match after ten seconds. If both leave, the match is drawn. Resignation completes the match without eliminating a king.

The King fighter, royal-counter mechanics and model are implemented in the common combat system. This checkmate ruleset deliberately does not spawn king duels. Capturable-king rules or a combat-training selector would be separate future rulesets, not an unannounced exception.

## Combat and balance

| Class | HP | Stamina | Base damage | Speed / 10 | Special |
| --- | ---: | ---: | ---: | ---: | --- |
| Pawn — Agile Spearman | 80 | 120 | 12 | 9 | Last Stand: below 35% HP, five seconds of faster movement and attacks |
| Knight — Armored Duelist | 125 | 110 | 22 | 7 | Lunging Strike: committed forward charge |
| Bishop — Arcane Spellblade | 90 | 115 | 18 | 8 | Blink: directional teleport, brief evasion and recovery |
| Rook — Fortress Guardian | 190 | 90 | 25 | 4 | Fortress Guard: stronger guard and stagger resistance |
| Queen — Royal Assassin | 135 | 115 | 24 | 9 | Royal Fury: faster attacks and longer combo chains |
| King — Royal Champion | 160 | 100 | 18 | 6 | Royal Counter: timed counter stance |

All values live in `src/battle/config.ts`. Legions change appearance, never stats. These are initial tuning values, not a claim of measured tournament balance. The automated combat suite demonstrates a pawn defeating a queen through timed parries and empowered counters.

The simulation runs fixed 60 Hz steps. Its states are Idle, Moving, Attacking, Blocking, Parrying, Dodging, Staggered, AbilityCasting and Defeated. Attacks have startup, active and recovery periods. Hits require active time, reach and facing, and one target can be hit once per attack. Pressing a button never applies damage directly. Light/heavy follow-ups can be buffered near the end of recovery; chain limits, increasing stamina costs and stagger immunity prevent indefinite attack cancellation or stun locks. Held attack inputs do not auto-repeat.

Blocking drains stamina and absorbs frontal pressure until guard breaks. A fresh parry has a short window and committed recovery; spamming does not extend it. Dodges have directional movement, a bounded invulnerable window, cost and recovery. Regeneration has a delay and does not make sustained blocking free. Sprinting and abilities spend the same resource. There are no cosmetic stat upgrades or paid advantages.

The arena has stone masonry, an enclosed boundary, pillars, gate, banners, fog and warm/cool lighting. Original procedural figures share the application's faction colors and facial language. Their role silhouettes, shields, spears, swords, staff, hammer, crowns and mitres remain distinct. White wears ivory and gold; Black uses dark metal and red/purple. Combat knights are humanoid duelists; Classic knights retain their horses. No external asset download is required.

## Private rooms and hosting

Run the existing Node server for authoritative rooms:

```sh
npm run build
npm start
```

On that host, select **Create Battle room**, copy the private link, and have a second browser/device open it, choose a legion and join. The host is White, guest Black. Room admission has two secret seat credentials, independent of the Classic profile; reconnect credentials stay in session storage and never appear in invite URLs or opponent snapshots.

The host advertises `/api/battle-capabilities`, and room traffic uses `/battle-ws`. The Node server validates chess commands, clamps input vectors, consumes increasing input sequences, simulates damage/cooldowns at 60 Hz, and broadcasts snapshots at 15 Hz. Clients can send intent or resign/agree to a draw; they cannot send trusted HP, damage, FEN or victory. Payload limits, request limits and room limits are included. Stale inputs are released. Unknown credentials, occupied rooms and opponent moves are rejected.

The current Vercel deployment serves the static mode and offline shared-device play. **Vercel Functions cannot run this persistent combat WebSocket server.** Battle-room controls appear only when the host advertises the capability. Classic's Vercel/Redis/PeerJS transport remains unchanged and continues to serve Classic modes. There is no fake Battle queue on a host that cannot run fights.

For public rooms, deploy the Node app on a persistent Node/WebSocket service with HTTPS and forward `/battle-ws` upgrades to it. `npm start` is the start command. Serve the app from that same origin; the APK can use it through the existing game-website setting. If a separate web origin is allowed to connect, explicitly list it in the server-only `BATTLE_ALLOWED_ORIGINS` comma-separated environment variable. Native `https://localhost` is supported. No additional cloud token is bundled in the app.

Rooms run in one server process and memory. They expire after five minutes while waiting, or ten inactive minutes after completion; a process restart loses them. Shared-device saves persist in that browser. Public ranked queues, account-linked Battle ratings, durable room migration, cross-region coordination and Internet latency prediction are not implemented. Do not put multiple independent Node instances behind a random load balancer for these rooms.

## Architecture and changed files

| File | Responsibility |
| --- | --- |
| `src/battle/BattleChess.tsx`, `battle.css` | Integrated start flow, board, local checkpoint, menus, controls configuration, chronicle, room UI and results |
| `src/battle/rules.ts` | Variant legality, pending captures, both outcomes, safety, counters and adjudication |
| `src/battle/config.ts` | All fighter stats, timings and default bindings |
| `src/battle/simulation.ts` | Pure fixed-step combat, states, hit windows, movement, stamina, cooldowns and outcomes |
| `src/battle/session.ts` | Shared match host: board → combat → result → board, draw and resignation commands |
| `src/battle/CombatArena.tsx`, `controls.ts` | HUD, real keyboard/gamepad/multitouch input and arena lifecycle |
| `src/battle/ArenaRenderer.ts`, `fighterModel.ts` | One Three.js renderer, per-player cameras, castle, original articulated figures, poses and effects |
| `src/battle/RoomClient.ts` | Real WebSocket room transport and credential-based reconnect |
| `src/battle/copyState.ts` | Snapshot-copy fallback for older WebViews |
| `server/battleServer.ts` | Authoritative private rooms, input ownership, simulation, timeout and disconnect handling |
| `src/App.tsx`, `src/next/contracts.ts`, `src/index.css` | New lazy-loaded page/menu choice and capture-ring styling |
| `src/next/Board.tsx` | Optional capture-target rings; Classic defaults remain unchanged |
| `server.ts`, `server/chessService.ts` | New room endpoint and a narrow upgrade-route delegation for the existing server |
| `android/app/build.gradle` | Android version 1.3 / code 5 |
| `tests/battle-chess*.ts`, `tests/battle-server.test.ts`, `tests/battle-room-client.test.ts`, `tests/battle-chess*-browser.py` | Variant, combat, authority, full gameplay and offline/mobile verification |

No new runtime framework, physics package or asset service was added. The open flat arena uses explicit planar character collisions and convex wall limits instead of a full physics engine. Each third-person camera has independent lock, orbit and distance controls, smooth follow and wall clamping. Shared-device views share one renderer and use scissor viewports. Light quality keeps the chessboard in 2D and uses simple combat shaders, low-cost instanced masonry, capped resolution and 30 Hz rendering; the combat simulation retains fixed steps. The expensive arena is unmounted and GPU resources disposed when returning to the board.

## Verification

```sh
npm run lint
npm test
npm run build
```

Run the browser checks against the finished production build, with the local Node server running:

```sh
BASE_URL=http://localhost:3000 python tests/battle-chess-browser.py
BASE_URL=http://localhost:3000 python tests/battle-chess-mobile-browser.py
BASE_URL=http://localhost:3000 python tests/browser.py
BASE_URL=http://localhost:3000 python tests/interaction.py
```

Playwright and Chromium are required for browser checks. The new tests use genuine keyboard and touch inputs and actual WebGL rendering; they do not set a combat winner. Room tests use two real clients and the real authority. Mobile checks include offline chunk loading, simultaneous pointers, both orientations, saves and resumed combat, and browser API fallback handling. See `docs/battle-chess/VERIFICATION.md` for the recorded results and limits.

The APK is a signed debug build for sideloading. It contains local Battle Chess and all art/code offline. Private online combat requires the persistent room host; pointing an APK at the existing Vercel static host does not create that server. Physical phones, gamepads, Internet latency, load capacity and competitive balance still need external playtesting.

Recommended next work: test real devices/gamepads and adverse networks; tune hit telegraphs and role matchups with players; add client-side interpolation/prediction for Internet rooms; persist and coordinate room hosts; then add account-linked Battle matchmaking and ratings. Keep any capturable-king variant separate from the documented checkmate rules.
