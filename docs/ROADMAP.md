# Combat/meta roadmap (Godot client)

Rules for every step
- Sequential, no parallel agents. Each step gets its own branch from the latest merged step branch (`steps/NN-name`).
  Small commits, pushed; never merged to `main` by the agent.
- The duel sim stays deterministic (online play depends on it): no wall-clock time, no unseeded randomness.
  Cosmetic work reads sim state and never changes it.
- All numbers live in the central config (`godot/combat/data/balance_v1.json` or a sibling file). New mechanics are
  flagged so ranked can use a fixed ruleset and chaos modes can enable extras.
- Save usage: grep/glob instead of reading the repo, no polling of background runs (check every few minutes at most),
  print only failing test names and summary numbers, run only relevant tests plus one headless import/load check per
  step, never download from the web.
- When a step finishes: tick it here with a 5-line summary (what changed, harness numbers, what is skipped, what needs
  human playtest), push, and stop.

## Steps

- [ ] **1. Duel anti-mash (merged OFF by default, needs calibration; see notes below) (sim, fighter, harness).** Button-mashing must lose to timing and tactics. Adapt to the
  existing actions (Light, Heavy, Guard, Special, dodge): whiff punishment with a vulnerable recovery window; stamina
  cost escalating for consecutive actions; move staleness (same attack repeated deals less); parry/perfect-block window
  that restores stamina and breaks poise; feints and delays (Heavy can be held a few ticks, Light can cancel into Guard
  early for stamina); dodge recovery and fewer i-frames when chained; counter relationships between actions. Add masher
  and timing bot styles to the harness. Acceptance: timing bot beats masher at least 70% at equal stats; equal-skill
  matrix inside 35-65% except Pawn-Queen 15-25%; median duel at most 35 s; timeouts under 5%; attacker win rate
  47-52%. Also make the chess AI's capture evaluation use the new table, re-run calibration (background, long), update
  pinned tests.
- [ ] **2. On-board abilities (meta-match layer).** One ability per piece, takes your turn, costs Resolve, visible
  cooldown, telegraphed, behind a flag. Pawn: Brace, Rally. Knight: Lunge (capture with a duel head start, cannot
  retreat next turn). Bishop: Snipe (damage along a diagonal from range). Rook: Bastion (immobile 2 turns, reduced
  damage, shields neighbours). Queen: Command (heal or Resolve to a friendly in sight). King: Royal Decree once per game
  (Rally, Sanctuary, or extend Last Stand). AI and bots use them. Acceptance: each ability's win-rate impact within
  45-55% between equal bots; white vs black fair. Minimal UI for highlights and cooldown pips.
- [ ] **3. Presentation.** Duels on the board: camera pushes in, the two pieces step into a ring while the army
  watches, then the camera pulls back (skippable, under 3 s, toggleable). Separate presentation clock for slow-mo and
  hit-stop (never touch `Engine.time_scale` or the duel tick). Piece personality (idles, capture reactions, victory
  poses, ghostly graveyard). Board memory (scorches, cracks, embers, shatter on capture, cosmetic). Dynamic audio layers
  using existing buses. Versus card, Last Stand zoom, replay camera. Respect quality presets and reduce-motion; never
  hide attack telegraphs.
- [ ] **4. Visible terrain.** Symmetric, visible: Shrine (heal and Resolve), Fortress square (defender armour), Cursed
  ground (no healing), Narrow ring (smaller arena), optional Pit edge. Mirrored or seeded layouts shown before the game;
  3 fixed presets for ranked, None and Seeded Random for casual. Duel modifiers passed to the sim as explicit
  deterministic parameters. Decals with a legend. Acceptance: white vs black 45-55% per preset.
- [ ] **5. Veterans, doctrines, sacrifice.** Veterans: max 2 ranks, small config perks, snowball cap. Doctrines: pick 1
  of 3 symmetric modifiers after a ban phase, minimal pre-game screen. Sacrifice: give up a piece for Resolve or
  cleansing. All behind casual/chaos flags. Acceptance: nothing outside 45-55% vs baseline between equal bots.
- [ ] **6. Online parity.** Port all mechanics to online rooms: server-validated chess layer, input-synced duels,
  state-hash desync checks, plus a network-simulator test with latency and packet loss (target zero desyncs at
  150 ms / 2% loss). Secrets only via environment variables.

## Step 1 status (merged into `main` 2026-11-18 with `anti_mash.enabled=false`; needs calibration)

- Merged OFF: `balance_v1.json` `anti_mash.enabled` is `false`, so the game plays exactly as the fairness pass left it (docs/battle-chess/FAIRNESS_PASS.md numbers hold). The sim start option `anti_mash: true` (harness `anti_mash.gd`, `edge_calibrate.gd am=on`) forces the rules on. The pinned stamp in `test_balance.gd` now covers the added (disabled) block.
- Known: with the rules on a Pawn attacking the Queen wins 0% and the queen gate in `test_attacker_edge` fails; nothing is tuned yet. Calibrate, then switch on, regenerate the chess AI table, update the pinned tests.


- Changed: `anti_mash` config block + `core/anti_mash.gd`, hooks in state machine / sim / fighter, `masher` + `timing` AI styles, `combat/tools/anti_mash.gd` harness, BALANCE.md section.
- Harness numbers: NONE. `godot` is not installed here and the rules forbid downloading, so no import check, tests or acceptance run happened.
- Skipped: chess AI capture table (`chess/ai/battle_model.gd` reads `combat/data/balance_matrix_v1.json`, needs the long calibration), pinned `SHIPPED_STAMP` in `combat/tests/test_balance.gd` (new hash needs Godot), tuning of every number.
- Needs a machine with Godot: import check, `test_balance`/`test_matchups`/`test_attacker_edge`/`test_fairness`, then `anti_mash.gd mode=skill|matrix`, tune, regenerate the matrix.
- Needs human playtest: feel of whiff lock, heavy hold (Guard at end of wind-up), feint, perfect block.
