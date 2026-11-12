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
| GET `/v1/history/summary?limit=20&offset=0` | limit1..100, offset0..1000000; self only | `matches:MatchSummary[],nextOffset:number|null` |
| GET `/v1/history?limit=20` | 1..100, self only | `matches:MatchRecord[]` |
| GET `/v1/leaderboard?mode=classic&limit=20` | mode classic/battle, limit1..100 | `players:Profile[]` |
| POST `/v1/queue` | `{mode,ranked,initialMs,incrementMs}` | `status:Status` |
| DELETE `/v1/queue` | no body | `status:Status` |
| GET `/v1/status` | none | `status:Status` |
| POST `/v1/private` | `{mode,initialMs,incrementMs}` | `status:Status` |
| POST `/v1/private/join` | `{code}` | `status:Status` |
| POST `/v1/tickets` | `{matchId}` | `ticket,expiresAt,allocation` |
| GET `/v1/friends` | none | `friends,incoming,outgoing,challenges` (`FriendsSnapshot`) |
| POST `/v1/friends/request` | `{username}` | `FriendsSnapshot` plus `result:"requested"\|"accepted"` |
| POST `/v1/friends/accept` | `{playerId}` | `FriendsSnapshot` |
| POST `/v1/friends/remove` | `{playerId}` | `FriendsSnapshot` |
| POST `/v1/friends/challenge` | `{playerId,mode,initialMs,incrementMs,side?}` | `FriendsSnapshot` plus `status:Status` |
| POST `/v1/friends/challenge/decline` | `{code}` | `FriendsSnapshot` |

**Friends (additive; nothing above changed).** `request` asks a player by username (case-insensitive); asking someone who already asked you accepts. `accept` answers an incoming request. `remove` is idempotent and means unfriend, decline or cancel depending on what exists between the two players, and also withdraws any challenge between them. A friend is shown with `online` (a client of theirs polled `/v1/friends` or `/v1/status` within 45 s), `inMatch` (an allocated or active match) and both ratings. Limits: 100 friends, 30 unanswered requests (they expire after 30 days), 30 requests per hour per account; errors `ALREADY_FRIENDS`, `REQUEST_PENDING`, `FRIEND_LIMIT`, `REQUEST_LIMIT`, `NOT_FRIENDS`, `INVITE_NOT_FOUND`.

A **challenge** is a private invite that only the chosen friend can join, so it reuses everything about private invites: ten-minute expiry, one outstanding invite per account (a new challenge, a queue entry or `DELETE /v1/queue` withdraws it), no challenge while you have an allocation, and always unranked. `side` is the challenger's colour: `white`, `black` or `random` (default; decided by the server when the friend joins). The challenger's `status.invite.code` is in the response so the usual status polling continues. The friend sees it in `challenges.incoming` (with the colour they will play) and **accepts with the ordinary `POST /v1/private/join {code}`**, which refuses everyone but the target with the same `INVITE_NOT_FOUND` a wrong code gets. From the allocation on, tickets, the ENet lobby and the dedicated server are unchanged. Clients poll; there is no push channel.

See `types.ts` for exact response field types. Classic supports initialMs `60000..10800000` and incrementMs `0..60000`; Battle currently requires both 0 (C0 untimed). Matchmaking matches exactly mode/ranked/time controls, FIFO opponent within ranked window ±100 widening by50 per10sec up to600; unranked has no rating restriction. No cross-mode rating. Private invites are unranked, uppercase six-character unambiguous codes with ten-minute expiry; host is White, joining player Black. Queue pairs alternate White assignment based on random server choice. Only one queue/invite/active allocation per account. A queue status poll also checks for eligible opponents. Queues expire after ten minutes without activity. Allocations not connected within five minutes expire as aborted/unrated. A server infrastructure failure is an unrated aborted record, never a fabricated win.

Dedicated server calls use `Authorization: Bearer <configured server secret>` and `X-Server-Id: <configured serverId>`; use HTTPS/private network. These endpoints must never accept account tokens.

- POST `/internal/tickets/redeem` `{ticket}` → `{schemaVersion:1,playerId,allocation}`. Single-use random ticket, 60sec expiry, bound to authenticated account, match and assigned dedicated server. The allocation contains both persistent account player IDs. The game server creates the provisioned room exactly once and binds the redeemed player to its seat. The existing ENet resume token remains process-local and separate.
- POST `/internal/heartbeat` `{matchIds:["match-uuid"]}` → `{schemaVersion:1,ok:true}`. At most256 IDs, only allocations assigned to the authenticated server; refreshes the lease for active allocations. The dedicated server sends its live and pending-result match IDs every20sec. Active leases expire after120sec without heartbeat; cleanup during client matchmaking/status/ticket operations records an unrated `aborted` result and releases accounts. A late conflicting terminal report after lease expiry returns409 and needs operator review; it must never overwrite the abort or adjust ratings. Empty lists are allowed.
- POST `/internal/results` `{matchId,result,reason,finalFen,history}` → `{schemaVersion:1,record,duplicate}`. Result is `white|black|draw|aborted`; `aborted` produces an unrated record and no rating/stat changes. History max4096 plain JSON entries, finalFen bounded256 chars, reason1..96 chars. Only the assigned trusted dedicated server may submit. Backend atomically stores result and mode-specific W/L/D/Elo (K32, initial1200), once. Exact retries return the original record; conflicting replays return409. Competitive ratings are never writable in client requests.

Example quick match:

```json
{"mode":"classic","ranked":true,"initialMs":600000,"incrementMs":0}
```

Example ticket response (abbreviated):

```json
{"schemaVersion":1,"ticket":"64-hex-random-secret","expiresAt":1800000060000,"allocation":{"matchId":"a5093b3e-c2dc-4c02-83c0-33c94d52c707","mode":"classic","ranked":true,"whitePlayerId":"b6b1e29e-a3cc-4700-ae10-a522d1549db5","blackPlayerId":"78f20a29-ea36-4ed9-a16d-6849baac9a30","initialMs":600000,"incrementMs":0,"serverId":"local-1","endpoint":{"host":"127.0.0.1","port":2456,"serverName":"localhost","caCertificate":"","insecureLocal":true},"createdAt":1800000000000}}
```

## Account-bound ENet admission

The separate additive `AccountHello` message is defined by
`godot/contracts/application/v1/schema.json`, with valid/invalid fixtures alongside.
Send `{type:"AccountHello",payload:{schemaVersion:1,protocol:"peepeechess-enet-v1",ticket:"<64 lowercase hex>"}}` reliably on channel0. It replaces initial anonymous Hello only for backend allocations. The dedicated server redeems the ticket over its authenticated internal HTTP connection, provisions the exact allocated seats/time controls once, and returns the existing Welcome and MatchFrame. No player ID comes from this client message. Existing Hello with a nonnull resumeToken resumes the resulting process-local ENet session without replaying the single-use ticket. Backend-enabled dedicated servers reject anonymous sessions, CreateMatch and JoinMatch; allocation and competitive mode are controlled by the account backend. An unconfigured standalone server retains the existing unranked development protocol. Older servers reject AccountHello rather than downgrading to anonymous identity.

Result delivery is a durable server outbox: terminal match data is written locally before retrying the authenticated idempotent internal result POST. On restart, queued reports retry, and provisioned unfinished matches are reported aborted/unrated; active combat state is not reconstructed. Account sessions belong to the HTTPS backend, while ENet resume tokens are memory-only and bound to one dedicated process. Neither token is a player ID. Never accept client-reported match results or competitive mode changes.

History summary pages omit the move array and provide `plies` instead. All other MatchRecord fields are retained. Order is completedAt descending then matchId ascending; offset pages refresh from0 when new results arrive. The UI uses this bounded route, leaving the original full-record history route compatible for existing tools.
