# Peepeechess audio

Two systems, both generated: nothing is downloaded and no audio files were authored by hand.

**Score and ambience** (`godot/audio/music_director.gd`). Seven seamless 8-second loops are synthesised at start-up on a worker
thread (about a second of CPU): `pad` (D-minor drone), `wind`, `torch` (crackle), `rumble` (stone resonance), `tension`
(a minor-second cluster), `drum_slow` (heartbeat war drum) and `drum_fast`. They all start together so they stay in phase, and the
loop frequencies are whole cycles per loop, so the seam is exact. A game state selects the target gain of each layer and the
director cross-fades (about 1.2 s): `opening` -> `menu` -> `board` -> `preview` (capture card) -> `pit` (descent, countdown,
aftermath) -> `combat` -> `victory`/`defeat` stinger -> `board`. In combat the drum and tension layers follow the danger value
(`danger_from_health`, from the weaker fighter's health, fed from `CombatArena._process`), so the score rises as a fight gets
dangerous. The `Music` bus has a limiter, every layer is normalised to a fixed peak, and the saved music volume (`UiPrefs.music_volume`)
scales it. A short dull double knock (`error`) plays when the game rejects a move.

**Effects** (`godot/combat/audio/combat_audio.gd`, unchanged core). Heavy hits and guard breaks now carry a low body thud
(the `stagger` sample pitched down) and a parry a high ring (the `block` sample pitched up) on top of the impact.

Hook points: `ui/application.gd` (opening, menu), `app/main.gd` (board, capture phases, result, rejected moves),
`combat/arena.gd` (combat intensity). Headless runs create no director and no players.

Tests: suite `music` (loop length, peak, seam click check, determinism, mix bounds, cross-fade, intensity) and the existing `audio`.

Limits: nobody has listened to this. The checks are objective (peak, seam, bounds); taste, loudness balance against the effects and
how the loops feel over a long session need a person with speakers. There is no separate music/effects slider in the settings page yet
(the saved `music_volume` preference is honoured).
