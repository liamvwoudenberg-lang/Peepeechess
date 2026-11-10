# Native application integration validation

Run `node scripts/test-application.mjs` from the repository root after `npm ci`.
Godot 4.6.3 must be on PATH (or set `GODOT_BIN`). The harness imports the native
project, starts an isolated account service backed by a temporary SQLite file,
starts a real headless dedicated server, and launches two independent Godot
client processes for each match. It uses the production account HTTP API,
production ENet client, shared chess authority, and Claude's combat simulation.
It does not call server chess methods, set fighter health, or fabricate winners.

The reproducible scenarios are:

- Register two persistent accounts, log in independently to the same account,
  reject a wrong password, and reject unauthenticated profile access.
- Reject account credentials on the internal result endpoint and reject a
  client attempt to write its competitive rating.
- Ranked Classic quick match: both seats ready, Fool's Mate, matching final
  chess state and exact recorded history on both accounts.
- Private Classic match: invite code joins the other account, host is White,
  game completes, and the private result changes statistics without rating.
- Ranked Battle quick match: twelve chess plies, four real knockout battles,
  attacker and defender victories, en passant, same-session reconnection,
  rejected forged winner/damage, and resignation. Both clients receive the
  same committed chess state and battle results.
- Check independent mode ratings, aggregate statistics, history ownership,
  leaderboard order, then restart the backend and confirm account sessions,
  profiles, ratings, and all match records persist.

The harness uses explicit plaintext loopback development transport. It does not
claim TLS/DTLS coverage; `npm run test:multiplayer` separately tests DTLS trust,
reconnection through simulated packet loss/latency, and authoritative inputs.
Production requires HTTPS for accounts and DTLS for game transport. PostgreSQL
transaction/persistence checks are documented with the backend test suite.

Set `APPLICATION_REPORT_DIR=/absolute/path` to retain JSON reports for the three
matches. Reports include public allocation IDs, client-observed states and
persisted records, never account bearer tokens, passwords, ticket secrets or
the dedicated server secret. On failure, the script prints an isolated temporary
directory containing process logs and reports for diagnosis; that directory may
contain ephemeral development tickets and should be treated as private.

These are automated Linux headless integration scenarios. They do not verify
physical Windows or Android devices, controller feel, touch ergonomics, GPU
rendering, store publication, or public Internet deployment.

## Recorded run

Pending execution on the integrated application branch. No passing result is
implied until the command above completes successfully.
