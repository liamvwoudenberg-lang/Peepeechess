# Hosting a game on your own PC

Play Classic or Battle Chess with a friend over the internet without any account or server: one of you hosts the game on their PC
and sends the other an invite. Hosted games are never ranked and cost nothing to run.

> Status: implemented and tested headless on loopback (real DTLS between two game clients in one process). It has **not** been tried
> across a real router or the real internet yet; see "What is not verified" at the end.

## How to host

1. Open the game, go to **Play → Online** and choose the mode (Classic or Battle) and, for Classic, the time control.
2. Under *Play a friend over the internet · no account* choose **I play White / Black / Random** and press **Host a game on this PC**.
3. Wait a few seconds. The game creates a one-off secure certificate, opens a UDP port (see below) and shows:
   - the **invite** (a long text starting with `PCHESS1-`) and a **Copy invite** button,
   - the address and port your friend would use (`Internet: 203.0.113.7:2456`, `Same network: 192.168.1.20:2456`),
   - a **security code** like `AB12-CD34-EF56-7890`, shown to both players,
   - whether your router opened the port, and manual steps when it did not.
4. Send the invite to your friend in any chat. Both of you press **Ready to play**; the game starts.
5. Leaving the lobby stops hosting: the match ends for both players, the router port is closed and the session key is deleted.

## How to join

1. Open **Play → Online**, paste the invite into *Paste the invite your friend sent* (the **Paste** button reads the clipboard) and press **Join with invite**.
2. The game tries the addresses in the invite one after another (internet address first, then local network) and joins.
3. Press **Ready to play**.

Messages you may see when joining: *"This is not a Peepeechess invite"* (wrong text), *"The invite is damaged / looks cut off"* (copy it again, including the end),
*"The host plays a different version of the combat rules"* (both update to the same game version), *"Could not reach the host"* (see troubleshooting),
*"The host's game is no longer available"* (full, finished or an old invite).

## What the invite contains (and why it is safe to send in a chat)

| Part | Purpose |
| --- | --- |
| host addresses + UDP port | where to connect |
| match code (128 random bits) | the join token: only someone holding the invite can take the second seat |
| the host's one-off certificate | the friend's game trusts **exactly this certificate** (pinning), so no certificate authority is needed and nobody in between can read or change the game |
| combat tuning stamp, mode, game version | refuses mismatched versions before connecting |
| check characters | detects a copy that lost characters |

- Traffic is **DTLS** (encrypted UDP). A client that expects a different certificate never finishes connecting.
- The private key never leaves the host's PC; it exists only while hosting and is deleted afterwards.
- One opponent only. A guest who connects but does not present a valid match code within 20 seconds is dropped and does not occupy the seat.
  Nobody can create other matches on your PC or watch the game. Rate limits from the normal server apply.
- Anyone who gets the invite before your friend can take the seat, so send it privately. The security code lets you both confirm you talk about the same host.
- The match code is never written to the log.

## Opening the port (reachability)

Your friend must be able to reach **UDP port 2456** (the game uses the first free port from 2456 upwards and shows it) on your PC from the internet.

1. **Automatic (UPnP).** The game asks your router to open the port, waits about 2.5 seconds and removes the mapping when you stop hosting (it also expires after 4 hours).
   If it works you see *"Your router opened UDP port …"*.
2. **Public address.** With UPnP the router reports its outside address. Otherwise the game asks a plain HTTPS address-echo service
   (`https://api.ipify.org`, then `https://ifconfig.me/ip`) for your public IPv4 address; only an ordinary request is sent, no game data.
   Set `PEEPEECHESS_IP_LOOKUP=off` to disable it, or `PEEPEECHESS_IP_LOOKUP_URLS=https://example.org/ip,...` to use your own endpoints.
   If nothing works the invite still contains your local-network address, and you can read your public address from your router's status page.
3. **Manual port forwarding** (when UPnP is off or refused): in your router's admin page (often `192.168.0.1` or `192.168.1.1`) find *Port forwarding / Virtual server / NAT*
   and add a rule: protocol **UDP**, external port and internal port = the port shown in the game, destination = your PC's local address shown in the game.
   Menu names differ per router brand; the rule always needs those four things.
4. **Windows Firewall.** The first time you host, Windows asks whether to allow the game to receive connections: allow it on *private networks* (and *public* if you host from a public network).
5. **Shared addresses (CGNAT).** If your router's outside address starts with `100.64.` to `100.127.`, `10.` or `192.168.`, your provider shares one public address between homes.
   The game says so ("blocked"). Port forwarding cannot work then: ask the provider for a public IPv4 address or play on the same network.
6. **Same network / same PC.** Friends in the same home use the *Same network* address from the invite; no port opening is needed.

The game cannot prove from the inside that the internet can reach you. *Good* means your router said it opened the port and the internet sees the same address;
the real proof is that your friend connects.

## Troubleshooting

| Symptom | Likely cause | What to try |
| --- | --- | --- |
| Friend: *Could not reach the host* | port not open, firewall, host stopped hosting, CGNAT | check the host's "reach" message, forward UDP port manually, allow the game in the firewall, host again |
| Host sees *router did not open the port* | UPnP disabled on the router | enable UPnP or forward the port manually |
| Host sees *shared address (CGNAT)* | provider shares the address | ask for a public IPv4, or play on the same network |
| *Internet sees you as X, not Y* | second router in front of yours | forward the port on both routers or bridge the first |
| *Different version of the combat rules* | different game builds | both install the same version |
| Invite looks cut off | chat app shortened it | send it as a file/code block, or copy again |
| *No longer available* | invite from an old game, game full, or host left | ask for a new invite |
| Host cannot open a port | another copy of the game is hosting | close it; the game tries ports 2456 to 2471 |

## For developers

- Code: `godot/network/host/` (`invite_code.gd`, `host_certificate.gd`, `hosted_game.gd`, `invite_join.gd`, `host_panel.gd`, `port_mapper.gd`, `upnp_port_mapper.gd`, `fake_port_mapper.gd`, `public_ip.gd`),
  Play page card in `godot/ui/application.gd`, lobby launch handling in `godot/network/client/online_lobby.gd`.
- The host runs the unchanged `DedicatedChessServer` in-process with a *host policy* (`configure_hosting`, `create_host_session`, `join_open`): the host's own client resumes a prepared
  session over loopback (its resume token is never put in an invite), every other connection is a guest (at most one), only the host can create the match, and a guest that
  never joins a match is dropped after 20 s. **No wire protocol, schema or contract change**; account/ranked servers behave as before (`host_policy` is empty there).
- Tests: `godot/tests/network/host_play_test.gd` (codec, pinning, fake router, a full Classic game over DTLS with the host as Black, a refused third player, both lobby screens)
  and its `--pinning` mode (a client pinned to another certificate never authenticates). Both run in `npm run test:multiplayer`. Godot 4.6.3 logs an engine error when a DTLS ENet
  server host is destroyed; the runner tolerates exactly that line and failed-handshake lines for these two tests (`scripts/test-multiplayer.mjs`).
- Invite format: `PCHESS1-` + base64url(JSON) + `-` + 8 hex check characters; JSON fields `v,h,p,m,c,t,g,pr,a`. A new incompatible format would use `PCHESS2-`.

## What is not verified

- A real router: UPnP discovery/mapping (`UpnpPortMapper`) was written against Godot's `UPNP` class and never run against hardware; only the fake mapper is tested.
- A real internet path between two houses, NAT hairpinning, mobile networks, IPv6-only networks (the invite carries IPv4 addresses).
- Windows Firewall prompts, Android hosting (hosting is meant for PCs; Android can join).
- A Battle duel was only tested up to its start: the automated test plays e4, d5, exd5 through the hosted path and checks the host's server enters the duel phase; fighting it out on two real screens (the existing `test:multiplayer` scenarios cover duels on the normal server, which is the same code) was not done.
