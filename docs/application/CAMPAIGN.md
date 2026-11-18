# Campaign (offline, single player)

Twelve scripted duels from the castle gate to the pit. Every encounter is a real combat-engine duel (the same simulation, frame data and balance as a
Battle Chess duel) against the computer opponent at an AI level that climbs from Easy to Expert. No account, no network.

## How a run works

- **Start a run** on the Campaign page (title menu or top navigation). You have **3 lives**.
- Encounters 1-12 are played in order. A **win** offers **three boons**; pick one and it lasts for the whole run (each boon can be taken twice).
- A **loss** costs a life and you may retry the encounter. A **lost boss** (encounters 6, 9 and 12) ends the run at once; running out of lives ends it too.
  Unlocks you earned stay.
- Leaving an encounter from the pause menu costs nothing; the encounter is simply not played.
- The run is saved after every result, so closing the game resumes at the same encounter. Abandoning a run on the page discards only the run.

## Encounters

| # | Name | Kind | Level | Modifier / reward |
|---|------|------|-------|--------------------|
| 1 | The Gate | duel p v p | Easy | |
| 2 | The Squire's Test | position: pawn takes knight | Easy | arena Moonlit |
| 3 | Night Watch | duel, you defend p v n | Easy | |
| 4 | The Bishop's Lane | position: bishop takes rook | Normal | skin Gilded |
| 5 | The Rook Bridge | duel r v b | Normal | start at 80% health |
| 6 | Captain of the Guard | boss b v n (defend) | Normal | arena Crypt, Training lesson a01 |
| 7 | The Queen's Gambit | position: queen takes pawn | Hard | 45 s limit |
| 8 | The Keep | duel, you defend q v b | Hard | Training lesson a02 |
| 9 | Warden of the Pit | boss r v q (defend) | Hard | skin Obsidian, Training lesson a03 |
| 10 | The King's Stand | duel k v q (defend) | Expert | start at 90% health |
| 11 | The Knight's Crossing | duel n v r | Expert | arena Ember |
| 12 | The Pit Sovereign | boss q v q (defend) | Expert | 85% health, skin Ember, Training lesson a04 |

**Position encounters** are written as a FEN plus a capture (`"capture": "e4d5"`). The pieces standing on those squares are the duellists and the side that
captures is the attacker, exactly as in Battle Chess. Only "win the duel" goals exist so far (see Not built yet).

## Boons

Boons change the **player fighter's state** right after the duel starts (health pool, stamina pool, stamina costs, stamina regeneration), the same kind of
change as a lesson's reduced-health handicap. They do not change rules, frame data, balance data or contracts and are never sent online.

| Boon | Effect |
|------|--------|
| Vitality | +15% health |
| Endurance | +25% stamina pool |
| Efficiency | stamina costs -15% |
| Second wind | stamina regenerates 30% faster |
| Iron will | +8% health and +10% stamina |

Offers are a pure function of (run seed, encounter index, boons taken), so a run can be replayed and tested.

## Unlocks

Granted the first time an encounter is cleared, kept across runs:

- **Arena palettes** (Crypt, Moonlit, Ember): equip on the Campaign page; the arena's moonlight takes the colour (`CampaignProgress.arena_light`, used by
  `StoneArenaVisuals`). The default arena stays when none is equipped.
- **Skins** (Gilded, Obsidian, Ember): unlocked and equippable, but **not yet applied to the paladin models** (that code belongs to the paladin owner).
- **Bonus Training lessons**: the lesson opens without finishing the earlier ones (`LessonCatalog.is_unlocked`).

## Files

| Path | Role |
|------|------|
| `godot/campaign/campaign_nodes.gd` | the 12 encounters, FEN scripting, node -> lesson dictionary, validation |
| `godot/campaign/campaign_boons.gd` | boon table, deterministic offers, applying boons |
| `godot/campaign/campaign_run.gd` | run state machine (lives, boss loss, picks, clear) and its save format |
| `godot/campaign/campaign_progress.gd` | saved meta-progress (`user://campaign_progress.json`), unlocks, equipment |
| `godot/campaign/campaign_view.gd`, `campaign_scene.*` | the encounter on screen (extends the training fight view) |
| `godot/ui/campaign_page.gd` | the Campaign page |
| `godot/combat/tests/test_campaign.gd` | suite `campaign` (77 checks) |

The save file is versioned JSON, written atomically; a missing, corrupt or foreign file starts empty, and loaded values are clamped and filtered.

## Not built yet

- Chess-only goals ("checkmate in 3", "survive with the King" on the board): encounters are duels only.
- Applying skins to the paladin models.
- A campaign map drawn as 3D plaques (the page uses the standard card layout on the castle's page plaque).
- More than one boon type that touches the duel rules (kept out on purpose: no simulation changes).
- Human playtest of the difficulty curve; the levels and handicaps are bot-reasoned only.
