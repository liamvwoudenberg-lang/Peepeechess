# Hosted-game security model (host on your own PC)

Scope: "Host a game on this PC" (`godot/network/host/*`, listen-server policy in `godot/network/server/dedicated_server.gd`). The dedicated-server / account flow is unchanged.

## What is protected, from whom

| Asset | Threat | Rule in the code |
| --- | --- | --- |
| Host's public IP | A website learns it (address-echo services) | No lookup unless the host presses **Detect my address**; UPnP's own answer or a typed address is preferred (`PublicIpLookup.consented`, `HostedGame.detect_public_ip`) |
| Host's public IP | Shoulder-surfing, streams, screenshots, logs | The UI never prints it (only "internet address: yes (hidden)"); the join screen never prints the dialled address; reachability texts contain no address; nothing logs it |
| Host's IP + certificate + match token | Someone reads the invite in a chat | Invite is **sealed** (`PCHESS2-`): AES-256-CBC + HMAC-SHA256 (encrypt-then-MAC), key from a 12-character word code (~59 bits) through 6000 HMAC rounds; the word code is shown separately, only after "Show invite" |
| The match | A stranger takes the guest seat | One 128-bit match code as join token; exactly one guest; invite expires after 15 minutes unless the guest already joined; a connection without a valid match code is dropped after 20 s |
| The listener | Port scanners / strangers after the guest joined | After the guest joined, the server **locks**: connections from any other address (except this PC's loopback) are dropped silently in `attach()`, before any session exists |
| The traffic | Eavesdropping, man in the middle | DTLS with a one-off self-signed certificate whose SHA-256 fingerprint-bearing DER travels in the (sealed) invite and is pinned by the guest |
| The host's PC | Port left open | Router mapping removed and listener closed when hosting stops, the lobby is left, or 60 s after the game is complete; the key is deleted |

## Honest limits

- **Direct (peer-to-peer) play necessarily reveals the host's IP to the invited friend**: their game must connect to it. Sealing protects the address from everybody else
  who might see the invite, not from the guest. Likewise the guest's address is visible to the host's server (and thus to the host's PC).
- The word code has ~59 bits; the iterated HMAC makes offline guessing of a stolen invite slow, not impossible. Send the invite and the word code over different channels.
- A guest whose address changes mid-game (mobile network switch) is locked out until they reconnect from the original address.
- UPnP itself is a router feature that any program on the LAN can use; it is only used for the game port and removed afterwards.
- A third-party address-echo site (only on the explicit button) sees that this PC asked, and its address.

## Relay mode (no port forwarding; hides both players' addresses from each other)

Shipped as `tools/relay/relay.mjs` + `godot/network/relay/` (deployment: `docs/deployment/RELAY.md`). Both players connect OUT to the relay over a WebSocket
(`wss://`); the game's ENet + DTLS keep running END TO END between host and guest through it:

- Host: the game server listens on this PC's loopback only (nothing is exposed to any network); a bridge copies its UDP datagrams to `/h/<session>` and back.
- Guest: a bridge opens a loopback UDP port, the game's ENet client dials it, and the datagrams go to `/g/<session>`.
- The sealed invite carries `{relay, session}` and NO host address (relay-only), plus the pinned certificate. The guest verifies the host's certificate through the
  tunnel exactly as in direct mode, so the relay cannot impersonate the host. Transport order in an invite that has both: relay first, direct addresses as fallback.

| Threat | Direct mode | Relay mode |
|---|---|---|
| Friend learns the host's IP | yes, necessarily | **no** |
| Host learns the friend's IP | only from packets of an open port | **no** |
| Strangers probe the host's game port | the port is open to the internet (guest-locked, rate limited) | **no port is open** (loopback only) |
| Third party reads or alters moves | no: DTLS with a pinned certificate | no: the same DTLS, end to end |
| Relay operator reads or alters moves | n/a | **no**: it only carries ciphertext (it can drop or delay packets) |
| Relay operator sees both IP addresses, session timing and traffic volume | n/a | **yes**: run your own or a friend's relay |
| Stranger takes the guest seat | invite + match token + lock | needs the 128-bit session id (only in the invite) AND the match token AND the host's certificate check happens on the guest side |
| Stranger hijacks the host side of a session id | n/a | the first host to register an id owns it; a hijacker cannot present the pinned certificate, and the real guest aborts the DTLS handshake |
| Relay abuse (floods, many sessions) | n/a | caps: sessions, sockets, 2 kB datagrams, per-session bytes/s and datagrams/s, per-address connects/min, one guest per session, idle/wait expiry, 1 MiB write back-pressure |
| Relay logs | n/a | no IPs, session ids or payloads are logged; `/healthz` returns counts only. The platform in front may log addresses (check it) |

Remaining limits: the relay is a single point of availability; a relay that drops packets only slows or ends a game, it cannot change it. Plain `ws://`
is accepted only for this PC and private networks (an invite with a public `ws://` relay is refused). The relay carries the game over TCP, so very lossy
connections stall more than UDP would. Everything here was tested with relay, host and guest as real processes on one machine, not over a real NAT or platform.

## Tests

- `godot/tests/network/host_play_test.gd` (sealing, wrong/missing word code, tampering, no-consent lookup, default privacy, expiry, locking, invite round trips, real DTLS in one process).
- `scripts/test-host-play-processes.mjs`: two **separate Godot processes** over localhost UDP, directly and through the UDP latency/loss proxy.
- Not covered: real routers and NAT (UPnP against hardware), the real internet, IPv6-only hosts, Android hosting, Windows Firewall prompts.
- `tools/relay/relay.test.mjs`: the relay's own behaviour (pairing, one-guest lock, session isolation, size/rate/session caps, per-address connect limit, expiry and host grace, malformed frames).
- `scripts/test-relay-play.mjs`: relay + host process + guest process (Classic, Classic with 60 ms + 2% loss on the relay path, a Battle capture reaching its duel, and the direct fallback). Part of `npm run test:multiplayer`.
