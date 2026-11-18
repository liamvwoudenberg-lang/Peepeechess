# The relay: play friends through any router

Direct hosting (`HOSTING_GUIDE.md`) needs the host to forward a UDP port, which many players cannot do. The **relay** removes that: the host
and the friend both connect OUT to a small relay server, which passes their game traffic between them. Nobody forwards a port, and neither
player learns the other's IP address.

```
host's game  ── wss ──►  relay  ◄── wss ──  friend's game
   ENet + DTLS (encrypted end to end, pinned certificate from the invite)
```

* The game's own encryption (ENet over DTLS with the host's one-off certificate, pinned by the sealed invite) runs end to end THROUGH the relay.
  The relay sees only ciphertext: it cannot read, alter or inject moves, and it does not need to be trusted with the game.
* The relay pairs a host and ONE guest by a random 128-bit session id that only the invite carries. It never logs IPs, session ids or payloads.
* The relay operator (and the platform in front of it) can see both players' IP addresses and how much traffic a session uses.
  Use a relay you or a friend runs.

**What you have to do once:** deploy the relay somewhere, then paste its `wss://` address into the game (Settings > Online relay) or bake it into
the export. Without a relay address the game offers direct mode only ("No relay configured: direct mode only"). Nothing in this repository
deploys a relay for you.

## 0. Try it on your own PC first

```sh
node tools/relay/relay.mjs                 # listens on 0.0.0.0:8080 (HOST=127.0.0.1 to keep it on this PC)
```
In the game: Settings > Online relay > `ws://127.0.0.1:8080` > Save. Plain `ws://` is only accepted for this PC and private networks (10.x,
172.16-31.x, 192.168.x). Two copies of the game on one PC, or two PCs on one network (use the host PC's LAN address), can now play through it.

## 1. Free hosting options

All of these need a credit card or phone number for sign-up and have changing free allowances: check the current terms. A game session uses
roughly 1-3 kB/s each way, so even the smallest instance carries dozens of games.

### A. A free web service (Render, Fly.io, ...)

The platform terminates TLS (so the address is `wss://...`). Examples are in this folder:

* `render.yaml`: Render Blueprint (`runtime: docker`, health check `/healthz`, `TRUST_PROXY=1`). Free instances sleep when idle: the first connection
  after a pause can take up to a minute; press Host again if the game gave up.
* `fly.toml`: Fly.io (`fly launch --copy-config --no-deploy`, then `fly deploy`).
* `Dockerfile`: any container host (`docker build -t peepeechess-relay tools/relay`).

The relay address is `wss://<your-service-host>`, no path.

### B. The Oracle Always Free VM

The Oracle deployment tooling lives on branch `deploy/oracle-always-free` (`docs/deployment/ORACLE.md` there). Once the VM exists:

```sh
sudo apt-get install -y nodejs caddy          # Node 22+ (NodeSource or Oracle's packages); Caddy gets a free TLS certificate
sudo useradd --system --home /opt/peepeechess-relay --shell /usr/sbin/nologin peepeechess-relay
sudo install -d -o peepeechess-relay /opt/peepeechess-relay
sudo cp tools/relay/relay.mjs /opt/peepeechess-relay/
sudo cp tools/relay/peepeechess-relay.service /etc/systemd/system/
sudo systemctl enable --now peepeechess-relay
# /etc/caddy/Caddyfile  (replace the name with a DNS name that points at the VM, for example a free DuckDNS name):
#   relay.example.com {
#       reverse_proxy 127.0.0.1:8080
#   }
sudo systemctl reload caddy
curl https://relay.example.com/healthz        # {"ok":true,"sessions":0,"connections":0}
```
Open TCP 443 (and 80 for the certificate) in the VM's security list and firewall. The relay itself only listens on 127.0.0.1.

## 2. Give the address to the game

* A player: Settings > Online relay > paste `wss://relay.example.com` > Save. Playing a friend then offers "Relay (works everywhere)".
* A build: set the project setting `peepeechess/network/relay_url` (Project Settings > custom, or `godot/project.godot` section `[peepeechess]`,
  `network/relay_url="wss://relay.example.com"`) before exporting, so every player gets it by default.
* A shell or test: `PEEPEECHESS_RELAY_URL=wss://relay.example.com`.

The friend does NOT need to configure anything: the invite carries the relay address.

## 3. Limits and settings (environment variables of `relay.mjs`)

| Variable | Default | Meaning |
|---|---|---|
| `PORT`, `HOST` | 8080, 0.0.0.0 | listen address (use `HOST=127.0.0.1` behind a reverse proxy on the same machine) |
| `TRUST_PROXY` | off | `1` behind a proxy: the first `X-Forwarded-For` address is used for the per-address connect rate limit only |
| `MAX_SESSIONS` | 200 | concurrent games |
| `MAX_CONNECTIONS` | 600 | concurrent sockets |
| `WAIT_MS` | 900000 | a session nobody joined is closed after 15 minutes |
| `IDLE_MS` | 300000 | a session without traffic for 5 minutes is closed |

Fixed limits: 2 kB per datagram, 256 kB/s and 1500 datagrams/s per session (bursts 512 kB / 3000), 30 new connections per minute per address, one
guest per session at a time, a host that drops keeps its session for 30 seconds. `GET /healthz` returns the counts and nothing else.

## 4. What is not covered

Everything here was tested with the relay, a host process and a guest process on one machine (`npm run test:multiplayer`,
`node scripts/test-relay-play.mjs`). Not tested: a relay on a real platform, TLS in front of it, real home routers and NAT, mobile
networks, IPv6-only players, or Android as host or guest through the relay. The relay carries the game over TCP (WebSocket), so a lossy
connection stalls a little more than UDP would; fine for chess and the duel's current tick rate on normal connections, unmeasured on bad ones.
