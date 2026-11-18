# Accounts on the VPS: prepared now, switched on in the next update

Today the VM runs only the **game server** (room codes, no logins). Everything needed to add **accounts** (sign-up, login, friends, ratings, matchmaking tickets)
is built, tested locally and sitting in the repository; nothing from it runs on the VM until you do the steps below. The account service is `server/native/`
(contract: `contracts/application/v1`, behaviour: `docs/application/BACKEND.md`).

## What gets installed (all from `tools/deploy`)

| Piece | What it is |
| --- | --- |
| `build_accounts.sh` | Packages the service with its four runtime dependencies. The **Build server package** GitHub workflow now builds it next to the game server (same artifact). |
| `remote/bootstrap_accounts.sh <ip>` | One time, as root: 1 GB swap, Node 24 (checksum-verified), Caddy (checksum-verified), service user and directories, units, a **freshly generated secret** in `/etc/peepeechess/accounts.env` (mode 600, never printed), TCP 80/443 in the OS firewall. Starts nothing. |
| `remote/install_accounts_release.sh <package>` | Installs a package, health-checks `/health`, rolls back on failure, keeps three releases. |
| `remote/enable_accounts.sh [--off]` | Turns accounts on/off for the game server and starts HTTPS. |
| `systemd/` | `peepeechess-accounts.service` (300 MB cap), `caddy.service` (150 MB cap), `Caddyfile.template`, `accounts.env.example`. |

Design: the account API listens on **127.0.0.1:8787 only**. Caddy is the only thing on the internet (HTTPS, automatic certificate) and answers 404 for `/internal/*`
(the game server talks to the API over loopback with the shared secret). Storage is **SQLite** in `/var/lib/peepeechess/accounts.sqlite` (one file; back it up).
PostgreSQL is supported (`DATABASE_URL`, and `NODE_ENV=production`) and recommended before real public use; on a 1 GB VM SQLite is the practical choice.

## Switching it on (about 15 minutes, once)

1. **Oracle Security List:** add Ingress Rules for **TCP 80** and **TCP 443**, source `0.0.0.0/0` (same page as the UDP 2456 rule).
2. Run the **Build server package** workflow, download the artifact (it now contains `peepeechess-accounts-<sha>.tar.gz` too) and `scp` the accounts package to the VM.
3. On the VM (use your real IP):
   ```sh
   tar xzf peepeechess-deploy.tar.gz                      # the newest scripts
   sudo bash ~/deploy/remote/bootstrap_accounts.sh 84.235.163.83
   sudo bash ~/deploy/remote/install_accounts_release.sh ~/peepeechess-accounts-*.tar.gz
   sudo bash ~/deploy/remote/enable_accounts.sh
   curl https://84-235-163-83.sslip.io/health            # after ~30 s: {"schemaVersion":1,"ok":true}
   ```
4. **Game build:** set the account URL as the default in `godot/project.godot` (`[peepeechess]` section): `network/default_api_url="https://84-235-163-83.sslip.io"` and publish a new
   Windows build (players can also type it under Settings). Redeploy the game server with a package built from the same commit (the tuning check refuses mismatched clients).
5. Roll back at any time: `sudo bash ~/deploy/remote/enable_accounts.sh --off` (anonymous room-code play returns; account data stays in the SQLite file).

## Things you must know first

* **Turning accounts on closes anonymous play on that server.** With a backend configured the game server answers every anonymous `Hello` with "An account matchmaking ticket is required".
  Everyone needs an account and the new build. (A second game server on another UDP port could stay open for guests; not set up.)
* **The default hostname `…sslip.io` is a shared public service.** Let's Encrypt limits certificates per registered domain; if Caddy cannot get one, use a free or paid domain you control
  (point an A record at the IP and re-run `bootstrap_accounts.sh <ip> <domain>`).
* **Memory:** game server (~94 MB measured), Node API and Caddy together should fit in 1 GB with the swap, but this was **not measured** on the VM. Check `free -m` and `systemctl status` after step 3.
* **Passwords** are stored hashed (scrypt); sessions are hashed at rest. There is no e-mail, no password reset and no moderation tooling.
* **Not tested here:** the install scripts on the real VM, Let's Encrypt issuance, a real login through the game client, and the account service together with this session's online changes (persistent HP, room codes). Treat the first run as a test and keep the rollback (`--off`) in mind.
* What was tested here: the package builds, starts under Node with SQLite, `/health` answers, and unauthenticated or secret-less calls to `/v1/*` and `/internal/*` get 401.
