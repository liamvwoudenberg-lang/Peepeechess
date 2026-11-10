# Combat audio assets

Generated files - **do not edit by hand**. Source: `tools/audio/generate_sfx.py` (stdlib Python, deterministic).
`manifest.json` lists every sound (files, variants, duration, peak/RMS/crest); `INVENTORY.md` is the same as a table.
Playback and event mapping live in `godot/combat/audio/combat_audio.gd`.

* Licence: no third-party audio. Everything is synthesised by this repository's script and carries the repository licence.
* Format: 44.1 kHz mono 16-bit PCM WAV. `CombatAudio` loads them through the importer when imported, otherwise parses the bytes at
  runtime, so a fresh checkout works without opening the editor.
* Variants: repeated sounds ship 2-3 variants (`name_1.wav`, `name_2.wav`, ...); the player never repeats the same variant back to back
  and adds +-3 % pitch / +-0.8 dB volume.

## Not included (documented gaps)

| Missing | Why / plan |
| --- | --- |
| Recorded (foley) sounds, real metal/cloth/footstep recordings | no licensed recordings were available offline; procedural stand-ins instead. Swap files of the same name to upgrade. |
| Per-surface footsteps | the arena is stone only (one set, 3 variants) |
| Per-fighter armour movement rattle / cloth | not synthesised; footsteps only |
| Voice lines, grunts, victory/defeat shouts | out of scope (no voices) |
| Music and ambience, music ducking | not in scope; only SFX/UI buses exist |
| Distinct sounds for every combo hit | combo hits 1-3 reuse the weapon's swing variants |
| Looping sounds (e.g. a sustained Royal Fury aura hum) | all sounds are one-shots |
| Spatial reverb / arena echo | no bus effects except a safety limiter on `SFX` |
| Human-verified mix balance | levels are set by peak targets and an objective analysis, not by listening |
