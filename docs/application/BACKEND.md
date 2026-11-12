# Native accounts, matchmaking and persistence

The native application has an independent HTTP v1 control plane; it does not
replace the legacy web APIs. Both Windows and Android use the same account
service and dedicated Godot servers. Gameplay state/damage/results are owned by
the dedicated server. Account tokens only authorize account/read/matchmaking
operations. A client has no endpoint for changing ratings or posting results.

The normative [HTTP contract](../../contracts/application/v1/README.md) includes
concrete payloads and the trust boundary. PostgreSQL is required in production.
Node 24's SQLite is a persistent, zero-service local development/test option.

## Local startup

Install Node24 and run `npm ci`. Generate a development secret yourself and keep
it out of Git. Set matching values in API and dedicated server environments:

```sh
export NATIVE_SERVER_SECRET="$(openssl rand -hex 32)"
export PEEPEECHESS_BACKEND_SECRET="$NATIVE_SERVER_SECRET"
export NATIVE_SERVER_ID=local-1
export NATIVE_GAME_HOST=127.0.0.1
export NATIVE_GAME_PORT=2456
export NATIVE_GAME_SERVER_NAME=localhost
export NATIVE_GAME_INSECURE_LOCAL=1
export NATIVE_DATABASE_PATH="$PWD/.data/native-application.sqlite"
npm run backend:native
```

The API defaults to `127.0.0.1:8787`. Start the dedicated server in another shell
with the same secret/server ID and backend URL (see main integration instructions).
Loopback plaintext is explicitly a development option. It cannot connect physical
Windows/Android devices from other machines. API sessions are hashed at rest;
Godot's short-lived ENet reconnect tokens are separate from account sessions.

Other variables:

| Variable | Meaning |
| --- | --- |
| `NATIVE_API_BIND`, `NATIVE_API_PORT` | HTTP listening address/port, default127.0.0.1:8787 |
| `DATABASE_URL` | PostgreSQL URL; required when NODE_ENV=production |
| `NATIVE_DATABASE_PATH` | SQLite path when DATABASE_URL absent |
| `NATIVE_SERVER_ID`, `NATIVE_SERVER_SECRET` | Registered dedicated identity (secret at least32characters) |
| `NATIVE_GAME_HOST`, `NATIVE_GAME_PORT` | Public ENet endpoint advertised to clients |
| `NATIVE_GAME_SERVER_NAME` | DTLS certificate hostname; defaults game host |
| `NATIVE_GAME_CA_CERTIFICATE` | Optional PEM trust root for a privately issued DTLS certificate |
| `NATIVE_GAME_INSECURE_LOCAL=1` | Explicit plaintext ENet loopback only |
| `NATIVE_API_TLS_PROXY=1` | Required to bind API outside loopback; operator must terminate HTTPS and firewall direct HTTP |

## PostgreSQL deployment

Use a dedicated database/user with only this application's privileges and a
provider certificate-validated connection string. Put passwords/secrets in the
service's secret manager, never in the project or export. Configure an HTTPS
reverse proxy for the account API; firewall the unencrypted listener and the
server-only endpoints to trusted dedicated hosts. Use DTLS for the public game
endpoint and a certificate matching NATIVE_GAME_SERVER_NAME. The client needs no
server secret or database credential.

Startup creates `native_*` relational tables/indexes with foreign keys and
unique constraints, leaving legacy web tables alone. Account records, sessions,
per-mode stats, queues, invites, allocations, tickets and complete match records
persist across API restarts. API transactions acquire PostgreSQL advisory lock
192837465, serializing short matchmaking/result operations across replicas. This
is intentionally a simple initial design: one configured dedicated endpoint and
a globally serialized control plane. Expand to server allocation/sharding after
measuring load. Combat simulation never runs inside these SQL transactions.
Back up the database with standard PostgreSQL tooling. Restore into a staging
instance and run the service/API tests before promoting a backup.

Passwords use per-account random salts and scrypt N32768/r8/p3 with32MiB working
memory, following the memory/time trade-off recommended for scrypt. Login for
missing users performs the same derivation. Account sessions are random256-bit
bearers, expire after30days, and are stored as SHA256 hashes (up to8 active per
account). Sign out deletes the current session. Match tickets are separate
256-bit bearers, hashed at rest, single-use,60seconds, and bound to account,
match and assigned dedicated server. The dedicated credential is checked with a
constant-time comparison. Requests have bounded bodies/timeouts; auth work is
limited to8 simultaneous derivations and30 attempts/IP/10minutes; API budgets
are240/IP/minute and internal1200/IP/minute. Rate state has a hard10000-key cap.
Behind a proxy the service intentionally uses the actual socket peer IP; do not
blindly trust client-supplied X-Forwarded-For. For large deployment, add trusted
edge IP limiting and abuse controls. Password recovery/account deletion and
identity-provider/email verification are not part of this initial account UI.

## Matchmaking and adjudication

Queues match exact mode/ranked/time controls. Unranked FIFO is unrestricted;
ranked requires ±100 rating widening50 per10seconds up to600. Private matches
are unranked; host White, guest Black. Server randomness assigns queue colors.
There is one active allocation per player. Neither board perspective nor input
device affects pairing. Classic and Battle ratings are separate, initial1200.
Terminal ranked results apply zero-sum Elo K32 and W/L/D exactly once; unranked
results update W/L/D without ratings. Repeated exact server reports are
idempotent; conflicting replays409 and never change a completed record.

The dedicated server sends live and pending-result match IDs every20seconds.
A120second missing heartbeat expires an active match as an unrated service abort
when matchmaking/status cleanup next runs. Unconnected allocations expire in
five minutes. Delayed terminal reports conflicting with an already recorded
lease abort require operator investigation; automatic late winners never
rewrite ratings. Production monitoring should alert on outbox failures,401/409
reports and lease expiry. No infrastructure timeout fabricates a combat winner.

## Friends

Friendships, friend challenges and presence live in three additive tables created by the same `CREATE TABLE IF NOT EXISTS`
schema step (`native_friendships`, `native_challenges`, `native_presence`); no migration or new service is needed, and the
dedicated server and its internal routes are untouched. A friend challenge is a row in `native_challenges` that points at an
ordinary `native_invites` row (`ON DELETE CASCADE`), so every existing way an invite disappears (expiry, cancel, the sender
queueing or being matched, unfriending) also removes the challenge. Accepting is the ordinary private join, which refuses
everyone but the target. HTTP routes are in [the HTTP contract](../../contracts/application/v1/README.md).

Operating notes: presence is "a client polled `/v1/friends` or `/v1/status` in the last 45 seconds", so it is only as fresh as
the clients' polling (about 12 s while signed in) and costs one small upsert per poll. A friends poll reads one snapshot in a
single transaction; with the PostgreSQL advisory lock that serialises every transaction, watch API latency before opening large
friend lists or pools (limits: 100 friends, 30 unanswered requests that expire after 30 days, 30 requests per hour per account).
Not implemented: blocking or reporting players, friend chat, push or email notification, and rate limiting beyond the
per-IP and per-account limits above. Anyone who knows a username can send a request; the recipient can decline.

## Verification

`npm run test:backend` runs real HTTP requests against SQLite by default. To run
the same suite against an **empty disposable PostgreSQL database**, set
`NATIVE_TEST_DATABASE_URL` (tests delete native tables' data):

```sh
NATIVE_TEST_DATABASE_URL=postgresql://user:password@127.0.0.1:5432/testdb npm run test:backend
```

Tests cover password/session admission, unknown fields, client attempts to post
results, independent mode/time buckets, private invites, queue concurrency,
single-use ticket redemption, concurrent result retries, conflicting outcomes,
ranked Elo and unranked stats, profile/history/leaderboard, expiration, heartbeat
leases, malformed/oversized requests, auth rate limits, persistent service reopen and PostgreSQL replica races.
`npm run test:application` adds the real Godot server and two independent native
client processes; see its integration validation report for measured results.

### Recorded backend validation — 2026-11-11

Node24.22.1, PostgreSQL17.11 (`postgres:17-alpine`, Linux x86_64), and the
repository's `npm run lint` were executed in the development environment.

- SQLite:9passing tests;1PostgreSQL-only test skipped deliberately.
- PostgreSQL:10passing tests,0skipped. This includes reopening the entire API
  service against the same database, and two independent API instances sharing
  PostgreSQL while queue admissions, single-use ticket redemption and duplicate
  result commits race. Exactly one allocation/result and one rating update win.
- Both runs exercise real HTTP sockets and real SQL storage, including lease
  expiry, unrated abort history and conflicting late-result rejection.

These checks verify the account/control-plane implementation. They do not
constitute physical Windows/Android testing or a production deployment.

The application uses `/v1/history/summary?limit=20&offset=0` for bounded history
pages. Both SQL adapters remove move arrays inside the database and return
`plies` with a `nextOffset` value; the existing full-record endpoint stays
compatible for tooling. Pages sort completedAt descending then matchId ascending.
Tests store three 4096-ply records (combined full response exceeds 1 MiB), verify
summaries stay below 8 KiB, traverse all pages without duplicates, enforce query
bounds/authentication/self-only access, and refresh from offset 0 after a new result.
