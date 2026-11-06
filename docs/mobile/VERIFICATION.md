> Previous mobile release. Current results and screenshots are in [the legion update](../legion-update/VERIFICATION.md).

# Mobile and invitation update verification

- TypeScript check passed; all **39 Node tests** passed.
- Production web build and offline cache generation passed.
- Android Gradle debug build passed with the Capacitor native Share plugin. `apksigner` verified APK signatures; `aapt` confirmed the app ID and Android SDK 23–35 metadata. Every bundled web file matches `dist`. See `apk-verification.json`.
- Private invitation tests covered fixed sides, White’s home castle, preview, one guest, concurrent joins, cancellation, replacement, offline hosts, queued players, expiry, reconnect, moves, and readiness before clocks.
- Two independent browsers played a real private-link match through the authenticated API; the 360px touch client played Black with upright illustrated pieces. Used links rejected a third guest. Human matches exposed no coach feedback.
- The installable web shell reloaded offline, displayed its piece atlas and ran the computer worker. The same flow passed with **6× CPU slowdown**. These are browser simulations, not physical older-phone benchmarks.
- An HTTPS integration check used the app origin `https://localhost` and a separate game API origin. Authentication, scoped profile storage, invitation creation, a browser guest joining, and moves in both directions passed. This used native-platform browser emulation and granted the browser permission to reach the local test server; it was not a physical APK run. See `native-https-integration.json`.
- The native-platform branch without a website made no API requests, played a computer match, and exposed the website connection setting.
- Existing browser regression checks passed for friends, persistent chat, challenges, spectating, emotes, reconnect, feedback-off computer play, drag moves, promotion and underpromotion, puzzles and responsive layouts from 320px upward.
- All 324 battle combinations completed, with animation-off, reduced-motion, brief online timing, sound/mute, live 3D raycast moves, and no browser errors. Sixteen rendered battle replays held geometry use constant. En passant, castling, capture-underpromotion, king survival at checkmate and interrupted animations passed.
- The standard board uses **front-facing renders** of the actual updated models and creates no WebGL context. Optional 3D was visually inspected while rendering; `3d-running.png` shows it. A stopped WebGL drawing buffer cannot serve as a screenshot proof, so the screenshot helpers keep painting during captures.

Multiplayer in this environment used the real server fallback. Managed Chromium prohibits non-proxied WebRTC UDP and produced no ICE candidates. PeerJS signaling was exercised; a direct cross-network WebRTC data channel is not claimed. Deploy the Vercel/Redis package and configure TURN for restrictive networks.

No public hosting URL or production Redis credentials were supplied. The website has not been publicly deployed. The APK is signed for sideloading with a debug key; no Play Store release or physical Android/iPhone device test is claimed.
