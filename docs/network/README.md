# Native dedicated multiplayer

Godot 4.6.3 clients share one ENet/UDP + DTLS protocol on Windows and Android.
The dedicated Godot process owns sessions, seats, legal moves, chess clocks,
board state, capture requests, the combat simulation, costs/damage/results and
termination. This implementation was tested on Linux. **Physical
Windows-to-Android crossplay and exported binaries have not been verified.**

The integration includes Claude handoff `6cc2ea7` (including combat net host
`c2110ea` and five-role mechanics `0c522d4`) and Battle board integration `67101fe`, based on develop `b4c6dab`.
C0 supports Pawn, Knight, Bishop, Rook and Queen battles. King duels belong to the
separate, unimplemented v2 gauntlet. Classic keeps standard chess rules.

## Start a local DTLS server

Requirements: pinned Godot on PATH (or GODOT_BIN), Node 24/npm for the test
runner, and OpenSSL for development certificates. No Blender is needed to run
or import the committed GLBs.

From the repository root:

```sh
npm ci
mkdir -p work/certificates
openssl req -x509 -newkey rsa:2048 -nodes -days 2 \
  -subj /CN=localhost -addext subjectAltName=DNS:localhost,IP:127.0.0.1 \
  -keyout work/certificates/server.key -out work/certificates/server.crt
export XDG_DATA_HOME="$PWD/work/runtime/data"
export XDG_CONFIG_HOME="$PWD/work/runtime/config"
export XDG_CACHE_HOME="$PWD/work/runtime/cache"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
godot --headless --path godot --editor --import
npm run server:native -- --bind=127.0.0.1 --port=2456 \
  --certificate="$PWD/work/certificates/server.crt" \
  --private-key="$PWD/work/certificates/server.key"
```

The Bash launcher sets writable server-specific XDG directories and runs the
headless entry point. Direct invocation (also usable in a service/container):

```sh
godot --headless --path godot --script res://network/server/server_main.gd -- \
  --bind=127.0.0.1 --port=2456 \
  --certificate=/absolute/path/server.crt --private-key=/absolute/path/server.key
```

A public host needs a hostname-valid certificate/private key, a reachable UDP
port, and `--bind=0.0.0.0` (or the specific interface). DTLS verifies the
hostname/certificate; there is no trust-all switch. `--insecure-local` is an
explicit developer option restricted to loopback binding. It cannot start a
public plaintext listener. Self-signed development certificates are trusted only
when the client is given that certificate as its custom CA. Never commit keys.
The certificate must cover the address entered by the client.

## Play with two native clients

Launch `godot --path godot` twice, or open
`res://network/client/online_lobby.tscn` directly. Choose **Online** in the local
client. Enter server hostname/port and, for the self-signed example, the absolute
path to `work/certificates/server.crt` as the custom CA. Connect in each client.

1. First client: Create Classic (10 minutes) or Create Battle C0 (untimed).
2. Copy the private invite ID into the second client and Join.
3. Both choose Ready. White moves first and the server starts the clocks.
4. Each client can switch 2D/3D and flip/orbit its own board independently.
5. Battle capture previews explain both outcomes before the request is sent.
   Once accepted, the server runs the countdown, battle and bounded aftermath,
   commits once and returns both clients to their chosen board view.

Each remote projection permits selection only on its authenticated seat's turn.
FEN import, pause, clock editing and undo are unavailable online. Draw agreement
requires an opponent offer; Classic draw claims are validated server-side. The
protocol supports a claim with an intended move; the current UI offers immediate
claims. Resignation always acts on the sender's own seat, including out of turn.

During combat, keyboard/mouse uses WASD, F/G or mouse attacks, Q block, E parry,
Space dodge, R ability, Tab lock, Z/X orbit. Choose Capture mouse for free look;
Esc releases it. Gamepad 1 uses Claude's existing controller mapping. Touch
combat enables a multi-touch move pad, action buttons, held block/sprint and
swipe look. All adapters send identical world-space CombatInput. The virtual
controls were tested with injected Godot touch events; physical touch/gamepad
feel and device performance remain unverified.

## Authority, time and recovery

- `DedicatedChessServer` owns authenticated transport bindings, rooms, command
  caches and resource/rate limits. `OnlineMatchSession` owns ClassicMatch or
  BattleChessMatch and a separate World3D for each battle.
- The room uses Claude's **CombatNetServer + CombatSimulation** unchanged.
  It passes authenticated inputs, ticks at 60 Hz, feeds ENet's measured RTT for
  bounded defensive hit grace, validates snapshots/results through BattleMatch,
  and commits after 120 aftermath ticks. The client never supplies a winner.
- Network data classes have no board/camera dependencies. The online client
  mounts Claude's arena in PRESENTATION mode: no authority ticks and no AI.
  Input adapters live outside the rendering viewport. HP/stamina/result are
  copied from validated snapshots. The first socket client uses the existing
  snapshot presentation; Claude's separate prediction/interpolation model is
  available but is not enabled in this UI.
- Chess clocks use server monotonic wall time and expire even under delayed
  client rendering. Combat uses fixed server physics ticks. A clientTick cannot
  rewind the game or set damage; transport RTT overrides client tick claims.
- Heartbeat silence/ENet timeout is detected after about three seconds. A
  detected disconnect has ten seconds of server wall time to resume; combat
  does not pause. Claude's combat host also enforces 600 server ticks without
  valid combat input. One absent seat forfeits; both absent draw. Match-level
  forfeits bypass BattleResult and stop the simulation.
- Same-process reconnect retains the bearer token and identity. Full reliable
  MatchFrame restores board, phase, clocks, own input sequence and cumulative
  action counters. A missed intermediate revision is recovered from the full
  committed history; stale snapshots cannot overwrite the board.
  The latest 32 validated battle-result receipts are replayed after reconnect,
  so a missed aftermath can still be displayed once without reapplying a move.
- Tokens are 256 random bits, stored as digests server-side, kept in client
  memory and expire within 24 hours. There is no account/rating integration or
  OS credential persistence. A new client process must start a new session;
  restarting a server loses its in-memory rooms/tokens and clients receive a
  session error. No durable recovery, rollback checkpoint or ranked result is
  claimed.

## Admission and operational bounds

The transport uses raw ENet packets, not Godot RPC or object-capable Variant
serialization. DTLS is established before Hello/session credentials. Only
intent message types are accepted from clients; no FEN, position, HP, damage,
clock, loadout, BattleRequest, snapshot or BattleResult writes are admitted.
UTF-8, strict JSON/duplicate keys, depth/number lexemes, schemas, membership,
turns/revisions, sequences/counters, movement/collision/stamina/cooldown rules
and packet channels are checked at their owning boundary.

Default bounds: 64 connected peers, 128 sessions, 16 rooms, 4,096 cached commands
per session, 4,096 history plies, 64 KiB client frames, 1 MiB server frames,
180 packets/s (burst 240), 128 KiB/s input bytes (burst 128 KiB), 10 control
messages/s (burst 20), 90 combat inputs/s (burst 120), per-IP handshake budget
0.2/s (burst 12), five-second unauthenticated lifetime. Errors from rejected
high-rate/late inputs are bounded. Correctly bound packets still in flight for
an ended battle are discarded and cannot affect the next one. An internal
simulation/counter failure aborts the unrated match as an explicit service draw,
without fabricating a combat winner. Completed rooms retire after one minute;
unstarted lobbies after five minutes. Session limits expire with the session.
These are application bounds, not a measured internet-scale capacity claim.

UDP hosting must be a persistent process; Vercel web previews do not host this
ENet service. This protocol is native-only and does not translate the existing
web WebSocket/PeerJS protocol. Android exports need INTERNET permission, the
matching Godot version, a reachable UDP server and the appropriate certificate
trust. No Android/Windows export or signing configuration is certified here.

## Reproduce validation

```sh
npm run test:multiplayer
# Optional retained, non-secret state/packet-loss reports:
MULTIPLAYER_REPORT_DIR="$PWD/work/network-results" npm run test:multiplayer
npm run lint
npm test
npm run build
npm run test:contracts
npm run test:classic
npm run test:battle
```

The multiplayer runner generates temporary development certificates, imports
the project, validates network fixtures with both Ajv and Godot, and runs
server-admission, full-roster combat and online UI tests. It launches **one
separate dedicated server process and two separate client processes** for each
of three cases: full Classic checkmate, server clock expiry, and a twelve-ply
Battle game with four real input-driven knockouts, en passant, a defender win,
session reconnect and final resignation. It compares authoritative final FEN,
history and stable piece IDs and checks every observed/recovered revision.

The Battle case uses two seeded raw UDP proxies with 40–59 ms one-way delay
and 10% loss in each direction, covering DTLS/ENet packets as well as game data.
Each new client UDP socket gets its own upstream endpoint, preserving NAT/DTLS
session identity during reconnect rather than merging sessions onto one port.
The seed fixes loss decisions; OS timing determines packet counts, so packet
counts/outcomes are reported rather than advertised as bitwise cross-machine
lockstep. A wrong-CA probe must never authenticate; a subsequent trusted probe
must succeed. The negative probe intentionally produces a TLS-handshake error;
all gameplay runs fail on any script/parse/resource diagnostic. Failed runs
retain private temporary diagnostic logs; successful runs remove certificates
and keys. See [protocol](PROTOCOL.md) and [validation report](VALIDATION.md).
