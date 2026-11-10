# Native application HTTP v1

This contract is separate from game/ENet v1. UTF-8 JSON, HTTPS outside explicit loopback development. Integer milliseconds are epoch time (not server simulation ticks). Every response has `schemaVersion: 1`; errors use HTTP 400/401/403/404/409/429/503 and `{schemaVersion:1,error:{code,message}}`. Unknown body keys are rejected. IDs are opaque server UUIDs; usernames are case-insensitive ASCII `[a-z0-9_]{3,24}` and passwords are 10–128 characters. Display names are 1–32 visible characters. Passwords and tokens must never be logged.

All `/v1` routes except registration/login/health require `Authorization: Bearer <account token>`. Tokens expire in 30 days and are stored only as SHA-256 hashes on the backend. Username+password allows the same account on Windows and Android. Profiles/stats/ratings are read-only. No client result endpoint exists.

| Method / route | JSON body or query | Success response fields (plus schemaVersion) |
| --- | --- | --- |
| GET `/health` | none | `ok:true` |
| POST `/v1/auth/register` | `{username,password,displayName}` | `token,expiresAt,profile` |
| POST `/v1/auth/login` | `{username,password}` | `token,expiresAt,profile` |
| POST `/v1/auth/logout` | `{}` | `ok:true` |
| GET `/v1/me` | none | `profile` |
| GET `/v1/profile?playerId=...` | optional playerId, defaults self | `profile` |
| GET `/v1/history?limit=20` | 1..100, self only | `matches:MatchRecord[]` |
| GET `/v1/leaderboard?mode=classic&limit=20` | mode classic/battle, limit1..100 | `players:Profile[]` |
| POST `/v1/queue` | `{mode,ranked,initialMs,incrementMs}` | `status:Status` |
| DELETE `/v1/queue` | no body | `status:Status` |
| GET `/v1/status` | none | `status:Status` |
| POST `/v1/private` | `{mode,initialMs,incrementMs}` | `status:Status` |
| POST `/v1/private/join` | `{code}` | `status:Status` |
| POST `/v1/tickets` | `{matchId}` | `ticket,expiresAt,allocation` |

See `types.ts` for exact response field types. Classic supports initialMs `60000..10800000` and incrementMs `0..60000`; Battle currently requires both 0 (C0 untimed). Matchmaking matches exactly mode/ranked/time controls, FIFO opponent within ranked window ±100 widening by50 per10sec up to600; unranked has no rating restriction. No cross-mode rating. Private invites are unranked, uppercase six-character unambiguous codes with ten-minute expiry; host is White, joining player Black. Queue pairs alternate White assignment based on random server choice. Only one queue/invite/active allocation per account. A queue status poll also checks for eligible opponents. Queues expire after ten minutes without activity. Allocations not connected within five minutes expire as aborted/unrated. A server infrastructure failure is an unrated aborted record, never a fabricated win.

Dedicated server calls use `Authorization: Bearer <configured server secret>` and `X-Server-Id: <configured serverId>`; use HTTPS/private network. These endpoints must never accept account tokens.

- POST `/internal/tickets/redeem` `{ticket}` → `{schemaVersion:1,playerId,allocation}`. Single-use random ticket, 60sec expiry, bound to authenticated account, match and assigned dedicated server. The allocation contains both persistent account player IDs. The game server creates the provisioned room exactly once and binds the redeemed player to its seat. The existing ENet resume token remains process-local and separate.
- POST `/internal/results` `{matchId,result,reason,finalFen,history}` → `{schemaVersion:1,record,duplicate}`. Result is `white|black|draw|aborted`; `aborted` produces an unrated record and no rating/stat changes. History max4096 plain JSON entries, finalFen bounded256 chars, reason1..96 chars. Only the assigned trusted dedicated server may submit. Backend atomically stores result and mode-specific W/L/D/Elo (K32, initial1200), once. Exact retries return the original record; conflicting replays return409. Competitive ratings are never writable in client requests.

Example quick match:

```json
{"mode":"classic","ranked":true,"initialMs":600000,"incrementMs":0}
```

Example ticket response (abbreviated):

```json
{"schemaVersion":1,"ticket":"64-hex-random-secret","expiresAt":1800000060000,"allocation":{"matchId":"a5093b3e-c2dc-4c02-83c0-33c94d52c707","mode":"classic","ranked":true,"whitePlayerId":"b6b1e29e-a3cc-4700-ae10-a522d1549db5","blackPlayerId":"78f20a29-ea36-4ed9-a16d-6849baac9a30","initialMs":600000,"incrementMs":0,"serverId":"local-1","endpoint":{"host":"127.0.0.1","port":2456,"serverName":"localhost","caCertificate":"","insecureLocal":true},"createdAt":1800000000000}}
```
