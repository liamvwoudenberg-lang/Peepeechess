# Incremental Godot migration

1. **Foundation (this change):** preserve the web client/server/Capacitor wrapper;
   add contracts, ownership, isolated workflow, runnable Godot status scene,
   schema codec, compatibility tests and CI.
2. **Chess slice (Codex):** authoritative state adapter, stable piece registry,
   standard initial board, one legal move loop, both board projections. Verify
   castling, EP, pins, all promotions, check/mate/draw parity before replacing
   any existing rules. No UI-side FEN becomes trusted input.
3. **Combat slice (Claude):** isolated arena/controller and headless simulation,
   BattleRequest/FighterStats ingestion, CombatInput consumption, snapshots and
   terminal result. Start with placeholder assets; maintain unit/tick conventions.
   Compare representative legacy combat outcomes without claiming floating-point
   cross-language deterministic lockstep. Port portable assets separately.
4. **Integration (Codex with a scheduled combat handoff):** native WSS adapter,
   authenticated seats, version rejection, result idempotency, disconnect/rejoin,
   match snapshots and atomic pending-capture settlement. Run Windows/Android
   clients against the same authority. Keep the old transports available until
   translation and multi-client tests prove parity.
5. **Exports/releases (Codex):** install exact matching export templates and
   Android SDK; introduce reviewed export presets/package identifiers, signing
   via CI secrets, Windows/Android smoke tests and device input/performance
   tests. Keep the existing Capacitor application ID and saves separate unless
   an explicit migration plan has been tested. Promote develop to main only
   after these release gates.

For each slice use a feature PR; leave working old routes available. Changes to
schema or variant rules require fixtures, tests, a documented version and both
agents to update. Native saves use their own schema/version. Existing browser
storage, Classic profiles, Redis namespaces and Battle saves must not be
silently reused. A failed native rollout can return users to the unchanged web
application; do not remove that path until equivalent features are verified.
