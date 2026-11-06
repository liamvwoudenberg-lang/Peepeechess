> Historical development notes. The current 2D pieces, mobile packaging and invite links are described in README.md and MOBILE-START-HERE.md.

# Character, arena, and animation update

Implemented in the supplied Sovereign’s Gambit project, preserving the prior chess, learning, social, and responsive-interface work.

## Design

- Articulated Royal Guard, Silverwood Elves, and Hollow Legion miniatures: layered plate, angelic trim, leaf armor and pointed ears, open ribs and skulls. All six ranks retain their chess headgear; knights ride actual horses, including a skeletal mount.
- Eighteen weapon designs: sword/shield, lance, warhammer, sun staff, sunblade, greatsword; twin daggers, mounted bow, longbow, moon staff, crescent blades, leafblade; rust axe, bone spear, ossuary maul, grave staff, scythe, executioner sword.
- Ivory/gold White and obsidian/crimson/purple Black remain consistent across factions. Familiar SVG silhouettes stay the standard 2D view, with polished material highlights.
- Dawn Citadel, Silverwood Sanctuary, and Ossuary Keep have distinct procedural scenery, board palettes, heraldry, and lighting. No photograph textures are loaded by the new renderer.

## Animation and sound

Eighteen signature pose sequences combine with six target reactions and faction-specific defeat effects to create 324 deterministic matchup profiles. These are composed procedural performances, not 324 separately authored animation clips. Rooks lose their guard/shield, knights are unhorsed, bishops have their staff interrupted, queens are disarmed, and kings kneel. Kings are never captured in live chess; king-target demonstrations are explicitly labeled as a showcase.

Walking, graceful elven steps, skeletal rattling, levitation, and articulated horse gaits accompany unit-specific attacks. Weapon aiming follows the strike; spells/arrows, impact arcs and a bounded particle pool reinforce contact. Each weapon has a distinct synthesized sound recipe, with material-dependent impacts and faction defeat sounds. Mute cancels voices; audio starts only after a user gesture.

The prior scene rebuilt models on every board change and discarded move animation events. It now preserves identities and forwards legal move transitions, including castling, en passant, promotion, captures and checkmate. Chess rules, moves, clocks, and inputs never wait for cosmetic battles. Incoming moves settle unfinished effects. Online sequences remain brief; full cinematics, brief and off options are available, with reduced motion taking priority.

## Verification

- TypeScript: passed.
- Automated tests: 25 passed, including 324 deterministic profiles, 18 distinct pose/sound recipes, 36 faction/side/unit models, geometry budgets, and legal special-move transitions.
- Production multiplayer browser suite: passed friends, requests, chat, challenges, spectating, emotes, reconnect, computer feedback settings, and mobile widths 320–1440 px. No browser errors.
- Production interaction suite: passed dragging, dialog text/focus, all promotion choices and knight underpromotion, multi-move puzzle and defending reply.
- Actual 3D scene controller: all 324 staged captures completed with exactly the expected survivor and destination. Off, reduced-motion and sub-600-ms simulated competitive encounters passed.
- Live 3D raycast clicks: a legal pawn capture updated the move list and board immediately, completed its battle, and restored correctly when switching to 2D. Browser sound/mute and mobile Armory checks passed with zero browser errors.
- Initial 2D loads no 3D chunks, images or canvas. The optional 3D controller is about 167 KB gzip; initial client JavaScript is about 113 KB gzip.
- Arena scenery is batched to 13–25 mesh draws. Example two-unit battle views used 76–97 total render calls. Particle and audio pools are bounded, and temporary resources are disposed.
- Replaying 16 rendered battles kept the geometry count at 56 after warmup; special-move, checkmate and animation-interruption scene checks passed. Low-memory mode blocks the optional 3D preview, and closing the preview disposes its canvas.
- At 390×844 with an emulated 6× CPU slowdown, four moves reached two animation frames in 70–163 ms; no WebGL was loaded. This is browser emulation, not physical-device certification. The QA renderer used software WebGL and manually advanced battle time, so its stored FPS counter is not a hardware benchmark.

## Run and inspect

Use Node.js 24 LTS: `npm ci`, then `npm run dev`. For production: `npm run build`, `npm start`.

Open Armory, choose each army and arena, and open Battle showcase. Select the attacking and defending unit to replay its encounter. The normal 2D game remains the default. See README.md for hosting, persistence, verification, and existing MVP limitations.
