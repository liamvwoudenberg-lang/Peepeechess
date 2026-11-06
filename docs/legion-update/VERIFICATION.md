# Legion, screen layout and APK update

- TypeScript validation, production build, and all **44 Node tests** passed.
- Tests check the native ESM API without a TypeScript loader, both sides’ board contrast, shared 2D/3D identities for all 36 pieces, and foreground forest cutaways for either orientation.
- Phone and desktop browser checks cover 320×640, 360×800, 390×844, 844×390, and 1440×1000. The square 2D board stays within the viewport. The options drawer, retained match settings, More menu destinations and browser fullscreen/exit controls were exercised.
- Two real local API clients chose their own legions through a friend invitation, played both sides, and shared White’s home castle. Computer-game factions remain fixed when the collection preference changes. The installable web app reloaded offline and the computer worker replied.
- The social and chess interaction regression suites passed: friends, persistent chat, challenges, spectating, emotes, reconnect, feedback-off computer games, puzzles, drag moves, all promotions and underpromotion.
- Native-platform browser emulation checks that the APK’s default online website is https://cheesy-indol.vercel.app and that computer play survives a server outage. This is not a physical Android run.
- Android 1.1 (version code 2) assembled successfully; apksigner verified its signature. Every bundled web file matches the production build. See apk-verification.json.

The full-screen elven view was also inspected after the cutaway fix; all 32 pieces remain clear of foreground foliage. See 3d-fullscreen-match.png.

The software-rendered 3D UI checks cap the software-renderer timer to keep browser automation responsive; they are correctness checks, not physical-GPU performance benchmarks. Automatic graphics mode still falls back to 2D on unsuitable devices. The managed browser’s WebRTC policy prevents non-proxied UDP, so local multiplayer checks use the real authenticated server fallback. A direct cross-network peer channel and physical older-phone performance are not claimed.

The live website’s API returned HTTP 500 at the start of the update. This commit fixes emitted Node ESM imports. Live deployment and storage health are checked separately after the GitHub push; local successes do not establish production storage readiness.
