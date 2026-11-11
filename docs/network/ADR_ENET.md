# Architecture decision 002: native ENet/DTLS authority

Accepted for the native dedicated server, 2026-11-10. The user explicitly
requested ENet/UDP Windows/Android crossplay. This replaces the foundation's
proposed HTTPS/WSS **native** transport; the existing web transport is preserved.

Use a single pinned Godot version for server and both clients. Raw JSON messages
on two ENet channels separate reliable commands/full state from sequenced combat
inputs/snapshots. Godot's DTLS extension authenticates/encrypts the server
connection. Session credentials bind an opaque identity to one peer; they are
not client-selected seat IDs. Shared game v1 payloads remain unchanged; the
additive session protocol has its own versioned schema and fixtures.

ChessMatch and Claude's existing CombatNetServer/CombatSimulation remain the
authorities. Online UI and board projections cannot commit state. Per-room
World3D isolates combat collisions. Server wall time owns clocks/abandonment;
fixed server ticks own physics, costs and damage. No client-reported result or
hit enters the authority. Same-session reconnect restores counters without
resetting combat; process restart recovery is explicitly outside this slice.

Godot ENet/DTLS is suitable for native Windows and Android clients. It does not
provide browser or legacy-protocol compatibility, deployment, account security,
persistence, or measured physical crossplay. Those require separate integration
and platform evidence. See README.md and PROTOCOL.md for operational bounds.
