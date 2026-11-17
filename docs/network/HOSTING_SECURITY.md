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

## Relay mode (hides both players' addresses): design, not implemented

A relay is a small UDP forwarder on a third machine (for example the Oracle Always Free VM, see `docs/deployment/ORACLE.md`). Neither player learns the other's address.

- Why it is **not** shipped here: the host's game is the DTLS *server*. An ENet listening host (Godot 4.6.3) never initiates a packet from its listen port, but a NAT'd
  host would have to open the path outwards first for the relay to reach it. That needs either an outbound-connecting server transport (a change to
  `enet_transport.gd`) or a helper process beside the game. Both are bigger than a security patch, change the transport, and could not be tested over a real NAT here.
- Sketch for later: relay assigns a session id; the host opens an outbound ENet connection to the relay (host becomes a *client* of the relay and a bridge to its own
  loopback server); the guest dials the relay with the session id (inside the sealed invite); the relay copies DTLS datagrams between the two without being able to read
  them (end-to-end DTLS with the pinned certificate stays between host and guest). The invite would carry `{relay: host:port, session: id}` instead of the host address.
  Risks to design: relay abuse (session limits, bandwidth caps, expiry), amplification, and a relay operator who sees both addresses and traffic volume.
- Until then: use a VPN/overlay network you trust (for example a tailnet) if you must not reveal your home address to the friend.

## Tests

- `godot/tests/network/host_play_test.gd` (sealing, wrong/missing word code, tampering, no-consent lookup, default privacy, expiry, locking, invite round trips, real DTLS in one process).
- `scripts/test-host-play-processes.mjs`: two **separate Godot processes** over localhost UDP, directly and through the UDP latency/loss proxy.
- Not covered: real routers and NAT (UPnP against hardware), the real internet, IPv6-only hosts, Android hosting, Windows Firewall prompts.
