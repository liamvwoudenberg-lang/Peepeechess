# Online play on a small Linux VPS

Runs the dedicated Godot server (`godot/network/`): server-validated chess, server-owned match state (persistent HP, Resolve, wounds), the authoritative
60 Hz duel simulation, rooms by short code, reconnect and forfeit rules. Players connect with the game over **UDP + DTLS** (default port 2456).
Written for an Ubuntu 24.04 VM such as Oracle `VM.Standard.E2.1.Micro` (x86_64, 1 GB RAM). **No secrets live in this repository**: the certificate key and
the environment file exist only on the VM (`/etc/peepeechess/`), and every setting is an environment variable or a command-line option.

Measured here (not on your VM): the exported x86_64 server starts in about a second and idles at ~94 MB resident after two probe sessions. Memory during
many simultaneous duels is **not measured**; the unit caps the service at 640 MB so a runaway process cannot take the whole 1 GB machine.

## What the server enforces

| Concern | Rule (all server-side) |
| --- | --- |
| Moves | Only the side to move, legal moves only (chess.js-equivalent engine + Battle capture restrictions). The client sends intent, never a board, HP, damage or winner. |
| Duels | The server runs the only simulation. Inputs are validated (schema, rate, counters, sequence, cooldown/stamina rules); impossible inputs are rejected or ignored. Snapshots go out at 15 Hz; the result also goes out as a reliable message. |
| Rules online | The server session runs `BattleMetaMatch`: defender's edge, failed-attack cost, persistent damage and healing, support bonuses, Resolve (second wind, overcharge, extra dodge), comeback, decisive-win bonus. See `docs/battle-chess/FAIRNESS_PASS.md`. |
| Rooms | Create a room, get a 6-character code (no 0/O/1/I/L); the friend types it (case, spaces and a dash are ignored). A code only works while the room waits for its second player. Long legacy invite ids still work. |
| Versions | The client sends its combat-tuning stamp in `Hello`; the server refuses a different one with a readable message. `PEEPEECHESS_BUILD_CHECK=require` also refuses clients that send no build. |
| Reconnect | Same session token resumes the seat with the full state; the last 32 duel results are replayed. |
| Disconnect | 10 s to resume, then the absent player forfeits (both absent = draw). A duel does not pause. |
| Timeouts | 600 ticks (10 s) without combat input forfeits; `PEEPEECHESS_MOVE_TIMEOUT_SECONDS` (default 180) forfeits the side to move in Battle; Classic has its chess clocks; waiting lobbies expire after 5 min. |
| Abuse limits | 64 peers, 16 rooms, 180 packets/s, 90 combat inputs/s per peer, per-address handshake budget, 64 KiB client frames. |

## One-time setup on your Oracle VM

1. **Public IP.** The console showed "The instance requires a public IP address". Instance > Networking > Attached VNICs > the VNIC > IPv4 addresses > Edit >
   *Reserved public IP* (it survives stop/start; an ephemeral one changes and breaks the pinned certificate). Note the address.
2. **Network ingress** (VCN > Security Lists, or the instance's NSG): allow **UDP 2456** from `0.0.0.0/0`; keep **TCP 22** limited to your own address.
3. **Build the server package** (here or on any Linux box with Godot 4.6.3):
   ```sh
   tools/deploy/install_server_templates.sh                       # once: official export templates, SHA-512 verified
   GODOT=$(which godot) tools/deploy/build_server.sh x86_64 out   # -> out/peepeechess-server-x86_64-<commit>.tar.gz (+ .sha256), smoke-tested
   ```
4. **Copy and bootstrap** (from your PC; replace `<ip>` and the key):
   ```sh
   scp -i <your_ssh_key> -r tools/deploy out/peepeechess-server-x86_64-*.tar.gz* ubuntu@<ip>:~/
   ssh -i <your_ssh_key> ubuntu@<ip>
   sudo bash ~/deploy/remote/bootstrap_vm.sh      # user, directories, unit, env template, iptables + ufw rule for UDP 2456
   sudo ~/deploy/remote/make_cert.sh <ip>         # self-signed certificate for that address; prints the SHA-256 fingerprint
   sudo editor /etc/peepeechess/server.env        # defaults are fine for a friends server
   sudo bash ~/deploy/remote/install_release.sh ~/peepeechess-server-x86_64-*.tar.gz   # installs, starts, health-checks, rolls back on failure
   ```
5. **Probe it** from your PC (a real handshake over DTLS; copy the public certificate first: `scp ubuntu@<ip>:/etc/peepeechess/server.crt .`):
   ```sh
   godot --headless --path godot --script res://network/server/probe_client.gd -- --host=<ip> --port=2456 --ca=./server.crt
   ```
   `PROBE_OK` means the whole path (cloud firewall, OS firewall, certificate, protocol and build check) works.
6. **Give the certificate to the players.** Put `server.crt` (public, safe to share) at `godot/network/trusted_server.crt` **before exporting the game** (the
   export filter includes `*.crt`), or save it on a device as `trusted_server.crt` in the app's `user://` folder, or type its path in the lobby's
   "Custom CA certificate" field (desktop). Then in the game: Online > host `<ip>`, port 2456 > Connect > **Create Battle** > send the code > friend: type the code > **Join** > both **Ready**.

Updating later: build a new package, copy it, run `install_release.sh` again. It keeps the last three releases and rolls back automatically if the new one is unhealthy.
The Oracle-specific automation (`deploy-oracle.yml`, A1 provisioning) is optional and described in `ORACLE.md`; you do not need it for an existing VM.

## Configuration (`/etc/peepeechess/server.env`)

| Variable | Default | Meaning |
| --- | --- | --- |
| `BIND`, `PORT` | `0.0.0.0`, `2456` | Listen address and UDP port. |
| `CERTIFICATE`, `PRIVATE_KEY` | `/etc/peepeechess/server.{crt,key}` | DTLS pair (key mode 600). |
| `PEEPEECHESS_BUILD_CHECK` | `require` | `off` / `match` / `require` (see Versions). |
| `PEEPEECHESS_MOVE_TIMEOUT_SECONDS` | `180` | Battle move timeout; `0` = off. |
| `EXTRA_ARGS` | empty | Extra server options, e.g. an account backend (`--backend-url=... --server-id=...`) plus `PEEPEECHESS_BACKEND_SECRET`. |

Logs: `journalctl -u peepeechess-server -f` (structured `COMBAT_BATTLE_START/DONE` lines include the tuning stamp). Status: `systemctl status peepeechess-server`.

## Verifying the network behaviour (no VPS needed)

```sh
npm run test:net-report -- 64     # bot-vs-bot duels under 0..250 ms, jitter, loss, reorder, duplication; prints desync + completion table
npm run test:multiplayer          # real ENet/DTLS server + two client processes through a lossy UDP proxy; roster, reconnect, forfeits
```

Last run of the network report (64 duels per profile, real rules, seed 1): every profile from LAN to 150 ms / 2 % loss with jitter, reordering and duplication
completed all duels with **0 state desyncs** (0 of ~49,000 applied snapshots differed from the server's state at that tick; 0 result mismatches; 0 replay
divergences in HP, state, Resolve or result). Re-simulating a duel from the server's recorded inputs differs in **position by at most 3 cm** in a few
percent of duels (engine collision settling; not used for any decision). The 250 ms / 5 % stress profile also completed 64/64.
This models the network between simulated clients and the server; real sockets are covered by `test:multiplayer`; real phones and WANs are on the checklist below.

## Manual test checklist (real devices; none of this has been run)

1. Two different devices on different networks (for example Windows PC on home Wi-Fi + Android on mobile data) connect to `<ip>:2456`; both reach the lobby.
2. Create Battle on one, join by the 6-character code on the other (try lowercase, with a space). A third device trying a wrong code gets a clear error.
3. Play a game with several captures: check persistent wounds, Resolve and the heal after each duel carry over on both screens; the duel HUD shows the same HP on both.
4. Duel feel at your real latency: parry/dodge timing, the 0.4 s defender head start (the attacker's early swing is rejected by the server; check the UI does not look broken), controller and touch.
5. Reconnect: toggle airplane mode for 5 s mid-duel and mid-board turn, then resume; try 15 s (the absent player should forfeit).
6. Idle: leave a board turn untouched for 3 minutes (forfeit message), and a duel untouched for 10 s.
7. Version mismatch: connect with an older build or after changing balance data; the refusal message must be readable.
8. Wrong certificate: connect with a different `trusted_server.crt`; it must fail, never connect.
9. Battery/thermal on the phone during a 10-minute game; server `top`/`journalctl` memory on the VM during two simultaneous games.
10. Server restart (`sudo systemctl restart peepeechess-server`) mid-game: clients get a session error and can start a new room (rooms are in memory by design).

## Not covered

No ranked play or accounts (optional backend only), no rollback/lockstep (the server is authoritative with client prediction), no crossplay with the web/TypeScript game,
no DDoS protection beyond the rate limits (use the cloud firewall), no automatic certificate renewal for self-signed certificates (825 days; rerun `make_cert.sh` and redistribute).
