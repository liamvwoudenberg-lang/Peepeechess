# Native application integration validation

Run `node scripts/test-application.mjs` from the repository root after `npm ci`.
Godot 4.6.3 must be on PATH (or set `GODOT_BIN`). The harness imports the native
project, starts an isolated account service backed by a temporary SQLite file,
starts a real headless dedicated server, and launches two independent Godot
client processes for each match. It uses the production account HTTP API,
production ENet client, shared chess authority, and Claude's combat simulation.
It does not call server chess methods, set fighter health, or fabricate winners.

`APPLICATION_API_ONLY=1 node scripts/test-application.mjs` runs the project
import, Godot protocol/navigation tests, and real account API adapter smoke
without starting dedicated game scenarios. The default command runs everything.

The reproducible scenarios are:

- Run the production Godot `AccountApi` against the real HTTP service: register,
  log in, authenticated profile/status/history/compact-history/leaderboard reads,
  queue and invite cancellation, and logout followed by 401 session clearing.
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
contain ephemeral development tickets and test account passwords and should be
treated as private.

These are automated Linux headless integration scenarios. They do not verify
physical Windows or Android devices, controller feel, touch ergonomics, GPU
rendering, store publication, or public Internet deployment.

## Recorded runs

On 2026-11-11, `node scripts/test-application.mjs` completed with exit code 0 on
Linux using Node 24.22.1 and Godot 4.6.3 (`7d41c59c4`). The complete account and
gameflow run used integration tree `aea2821`, including Claude's combat/audio/
mobile handoff `f8128cc`, the updated application UI, and the real Godot account
adapter smoke.

Ranked Classic (4 plies), private Classic (4 plies), ranked Battle (12 plies,
4 real knockouts), terminal-result outbox recovery after account and dedicated
server outages, active-match restart abort, and database reopen all passed.
Both independent clients agreed on final chess states and exact history;
account ratings and mode-specific W/L/D matched the persisted records. All
three completed records plus the abort survived backend restart. The Godot
import and gameplay logs contained no script, parse, or engine error diagnostics.

After compact history pagination was integrated through `34d3657`,
`APPLICATION_API_ONLY=1 node scripts/test-application.mjs` completed with exit
code 0 on integration tree `6ebdee0`. The Godot protocol and application UI tests
passed, followed by all ten actual HTTP account adapter checks, including
`/v1/history/summary?limit=20&offset=0` and its pagination response shape.
These protocol/UI/component checks are now also included in the full harness.

These runs cover the SQLite account service. PostgreSQL-specific coverage is
reported separately in [BACKEND.md](BACKEND.md).
