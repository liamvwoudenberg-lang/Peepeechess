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
- Take the account service offline after ticket admission, complete the private
  match, then restart both dedicated and account service. The persisted terminal
  outbox must deliver exactly one unchanged result.
- Restart a dedicated server with a journaled active match. It must record an
  explicit unrated infrastructure abort, without statistics or rating changes.
- Check independent mode ratings, aggregate statistics, history ownership,
  leaderboard order, then restart the backend and confirm account sessions,
  profiles, ratings, and all three completed records plus the aborted record persist.

The harness uses explicit plaintext loopback development transport. It does not
claim TLS/DTLS coverage; `npm run test:multiplayer` separately tests DTLS trust,
reconnection through simulated packet loss/latency, and authoritative inputs.
Production requires HTTPS for accounts and DTLS for game transport. PostgreSQL
transaction/persistence checks are documented with the backend test suite.

Set `APPLICATION_REPORT_DIR=/absolute/path` to retain JSON reports for the three
completed matches. Reports include public allocation IDs, client-observed states and
persisted records, never account bearer tokens, passwords, ticket secrets or
the dedicated server secret. On failure, the script prints an isolated temporary
directory containing process logs and reports for diagnosis; that directory may
contain ephemeral development tickets and should be treated as private.

These are automated Linux headless integration scenarios. They do not verify
physical Windows or Android devices, controller feel, touch ergonomics, GPU
rendering, store publication, or public Internet deployment.

## Recorded run

On 2026-11-11, `node scripts/test-application.mjs` completed with exit code 0 on
Linux using Node 24.22.1 and Godot 4.6.3 (`7d41c59c4`). The tested integration tree
was `58fa240`, incorporating native application/backend work through `fb9d3bf`
and Claude's combat/audio/mobile handoff `f8128cc`.

All scenarios above passed: ranked Classic (4 plies), private Classic (4 plies),
ranked Battle (12 plies, 4 real knockouts), terminal-result outbox recovery after
account and dedicated server outages, active-match restart abort, and database
reopen. Both independent clients agreed on final chess states and exact history;
account ratings and mode-specific W/L/D matched the persisted records. The
harness also confirmed all three completed records plus the abort survived the
backend restart. Its Godot import and gameplay process logs contained no script,
parse, or engine error diagnostics.

The same harness had also completed successfully on the preceding application
integration tree before the latest Claude handoff. This recorded run covers the
SQLite account service; PostgreSQL-specific coverage is reported separately in
[BACKEND.md](BACKEND.md).
