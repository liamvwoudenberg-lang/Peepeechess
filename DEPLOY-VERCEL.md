# Deploy Sovereign’s Gambit on Vercel

The Android app targets https://cheesy-indol.vercel.app. The project is prepared for Vercel; this workspace has GitHub access but no Vercel account or Redis credentials. The API entry and its dependencies use explicit `.js` module imports so emitted server files run under native Node ESM. `tests/vercel-runtime.test.ts` checks this without a TypeScript loader.

## What runs where

- **Vercel** serves the built Vite interface and `/api/chess` Node Function. It does not run the long-lived `server.ts` process or host a WebSocket server.
- **Upstash Redis** stores browser profiles, friendships, chat, queues, games, ratings, presence, and reconnect state. Locks and atomic Lua commits keep concurrent requests consistent across Function instances.
- **PeerJS** opens a reliable WebRTC data channel between matched players. Room secrets and the expected peer ID bind the channel to that match. It carries immediate sync notifications; the receiving player fetches the authoritative position. Peer messages cannot replace a board, clock, rating, or result.
- The **server remains authoritative** for legal moves, turn order, move sequence, clocks, promotions, results, and provisional Elo. If peer connectivity fails, the same match continues through authenticated HTTPS polling. A silent queue always waits for a human.

## Deploy

1. Push the contents of this project directory to your Git repository and import that repository into Vercel. If it is inside a larger repository, select this directory as the Root Directory.
2. Select **Node.js 24.x**. `vercel.json` supplies the Vite build command (`npm run build`), output directory (`dist`), API routing, and Function duration. Do not use `npm start` as a Vercel build or Function command.
3. Create an Upstash Redis database, preferably in a region close to the Vercel Function region. Add these **server-only** Vercel environment variables:

   | Variable | Value |
   | --- | --- |
   | `UPSTASH_REDIS_REST_URL` | The database REST URL |
   | `UPSTASH_REDIS_REST_TOKEN` | The database REST token |

   Never name these with a `VITE_` prefix. Use separate databases for Preview and Production if preview games should be isolated.
4. Deploy. When adding or changing environment variables later, redeploy for the Function to use them.
5. Open `/api/chess`: a configured host returns `{"ok":true,"transport":"peerjs","storage":"ready"}`. Without Redis variables, online play explicitly reports unavailable and computer/learning modes continue to work. The API does not silently substitute an in-memory queue on Vercel.
6. For a direct invitation, choose **Friend → Share a friend link → Create invite link** and open the copied URL in another browser. Verify joining and moves. Enter the same HTTPS origin in the Android app’s website setting for APK multiplayer.
7. Open the site in two separate browsers/profiles. Choose factions, select Online and the same time control, then search. Both players must appear before clocks start. Verify that White’s faction selects the same castle on both clients. Play, reload, and confirm the saved position. Test a friend challenge, chat, spectating, resignation, and a draw.

The default signaling service is the public PeerJS Cloud (`0.peerjs.com`, HTTPS 443). For your own separately hosted PeerServer, set `PEER_HOST`, `PEER_PORT`, `PEER_PATH`, `PEER_SECURE`, and optional `PEER_KEY`. Persistent signaling belongs on a service that supports WebSockets, outside Vercel Functions.

## Reliable peer connections across networks

STUN alone cannot connect every pair of networks. For restrictive Wi-Fi, mobile carrier NAT, and browsers that prohibit direct UDP, configure a managed TURN service with **TLS/TCP on port 443** as well as its normal endpoints. HTTPS fallback remains available during connection setup or relay failure.

For a coturn-compatible REST secret, set:

```text
TURN_URLS=turns:turn.example.com:443?transport=tcp,turn:turn.example.com:3478?transport=tcp
TURN_SHARED_SECRET=<your provider's server-side shared secret>
```

The API issues one-hour per-player HMAC credentials. It never returns the shared secret. Alternatively, supply provider-issued temporary credentials through the server-only `CHESS_ICE_SERVERS` JSON array documented in `.env.example`. Do not commit real values.

No camera or microphone permission is needed. Only a data channel is created. PeerJS is lazy-loaded when searching for or joining a human match.

## Validation and operating scope

Run `npm run lint`, `npm test`, and `npm run build` before deploying. Automated tests cover simultaneous matchmaking, authority, clocks, idempotent moves, friends/chat/privacy, room authentication, short-lived TURN credentials, and the unavailable-Redis state.

This environment enforces Chromium’s `WebRtcIPHandling=disable_non_proxied_udp`. Local testing verified PeerJS signaling and offer/answer exchange, with zero ICE candidates in that browser policy. Real two-browser gameplay was verified through the HTTPS fallback. A live managed TURN connection and an actual Vercel/Upstash deployment require your configured services; neither is claimed as verified here.

This remains an MVP with browser-secret identities and provisional Elo. Account recovery, public-service moderation, measured fair-play enforcement, monitoring, and load testing remain deployment work. Polling and shared matchmaking locks suit a modest initial player pool; measure Redis usage, Function latency and game traffic before opening a large ranked pool. Clocks expire authoritatively on the next request, so sleeping clients cannot extend a game.
