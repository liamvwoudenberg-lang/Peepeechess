# 2D battle animations — Android 1.2

- TypeScript validation, the production web build and all **48 Node tests** passed. Animation tests check distinct choreography and weapon drawings for all 18 units, ordered finite keyframes for all 324 profiles, target reactions, timing limits and reduced-motion behavior.
- The development Board fixture rendered real legal captures for all 18 attack styles, with independently moving weapons. Every effect stayed below 100 DOM nodes. En passant from either orientation, capture-underpromotion, both castling figures, interruption by another move, and king survival at checkmate passed. Off, app reduced motion, operating-system reduced motion and Light mode passed without browser errors. See `battle2d-checks.json` and the strike/defeat screenshots.
- The production app used its real computer worker on a 360px phone layout with **6× CPU slowdown**. The reply followed the capture; pause cancelled a pending response and resume produced a legal reply. CPU emulation checks behavior under load, not a physical-phone frame-rate guarantee.
- A production installable web app cached the 208,244-byte battle-body WebP, reloaded offline and completed a capture with a computer reply. The bodies and complete pieces have PNG fallbacks and are precached. No WebGL canvas was created in these Light-mode tests.
- Two independent clients joined through a real private link, played `e4 d5 exd5`, and both received the logical position and a short 2D fight. Human games exposed no coach. A separate phone/invite regression checked touch moves, fixed sides and home castle, used-link rejection, reconnect, offline play and the APK's configured website. See `app-checks.json` and `mobile-invite-checks.json`.
- Android **1.2 (code 3)** assembled successfully. `apksigner` verified v1/v2 signatures, and `aapt` confirmed Android SDK 23–35 metadata. Every bundled web file matches `dist`, the test fixture is excluded, and the default website is `https://cheesy-indol.vercel.app`. This is a signed debug APK for sideloading; no physical-device or Play Store release test is claimed. See `apk-verification.json`.

The local multiplayer tests used the real authenticated HTTPS fallback. The managed Chromium policy prevents non-proxied WebRTC UDP, so a direct cross-network PeerJS connection is not claimed. The live website currently returns HTTP 503 with `ONLINE_NOT_CONFIGURED`; Upstash Redis must be configured in Vercel before public matchmaking and friend links can work. Offline chess and battle animations are bundled in the APK.

Reproduce with a local production server and a fresh SQLite database:

```sh
npm run lint
npm test
npm run build
NODE_ENV=production PORT=3031 CHESS_DATABASE=/tmp/battle-qa.sqlite npm start
# In another terminal:
BASE_URL=http://localhost:3031 PRODUCTION_QA=1 python tests/battle2d-app-browser.py
BASE_URL=http://localhost:3031 python tests/mobile-invite-browser.py
```

For the development-only choreography fixture, run `npm run dev` and `BASE_URL=http://localhost:3000 python tests/battle2d-browser.py`. Playwright and Chromium are required for browser checks.
