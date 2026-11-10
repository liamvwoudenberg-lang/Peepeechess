# Combat sound effects (procedural, reproducible)

All combat SFX are **synthesised by `generate_sfx.py`** - there is no recorded or third-party audio, hence no
external licence to track. The script uses only the Python 3 standard library (`wave`, `math`, `random`, `zlib`,
`hashlib`, `json`), so no virtual environment is needed.

```bash
python3 -I tools/audio/generate_sfx.py                  # -> godot/assets/combat/audio/*.wav + manifest.json + INVENTORY.md
python3 -I tools/audio/generate_sfx.py --out /tmp/x     # elsewhere (the Godot determinism test does this)
python3 -I tools/audio/generate_sfx.py --list           # sound names
python3 -I tools/audio/analyze_sfx.py                   # objective report: peak, RMS, crest, spectral centroid, DC, edges
```

Takes about two seconds. Output is **byte-identical** on re-runs (all randomness is seeded from
`crc32("<name>:<variant>")`; only IEEE-754 `math` functions are used). `godot/combat/tests/test_audio.gd` regenerates
into a temp directory and compares SHA-256 of every file against the committed ones.

Format: 44.1 kHz, mono, 16-bit PCM, peak between -2 and -17 dBFS (never above -1 dBFS), each file < 62 kB,
total about 1.3 MiB. Short fade at both edges so nothing clicks.

## How the sounds are built

| Technique | Used for |
| --- | --- |
| Band-passed noise with a swept centre frequency (Chamberlin state-variable filter, then a 12 dB/oct low-pass) | weapon swings (spear / sword / staff / hammer / dual / king differ in sweep range, width, body tone), dodge, charge-ups |
| Modal resonator banks (decaying sinusoids at inharmonic ratios) | steel/plate impact ring, block, perfect parry, guard break, Fortress Guard, Royal Counter bell |
| Pitch-dropping sine "thump" + low-passed noise | flesh/leather/plate body impacts, stagger, footsteps, defeat |
| FM synthesis | Blink zap |
| Additive brass-like partials | victory fanfare (C5-E5-G5-C6), fight cue chord |
| Stacked detuned sweeps + tremolo | Royal Fury shimmer |

Design intent for readability: a perfect parry is the **brightest, longest, highest** sound in the set (1.76/1.98 kHz ring
plus a rising sparkle, 0.58 s) so it is never confused with an ordinary block (duller, shorter, 1.1-1.3 kHz); guard break is a
crack + low thud; plate hits are low and heavy, steel hits ring, leather hits slap, flesh/cloth hits thump.

## Sound list

See `godot/assets/combat/audio/INVENTORY.md` (generated: file, duration, peak, RMS, crest factor, bytes) and
`manifest.json` (machine-readable, also read by `CombatAudio`).

## What this is NOT

* Not recorded or foley-quality audio. It is a coherent, clean, game-ready placeholder-plus set. A sound designer can replace any
  `*.wav` with the same name and the manifest/test still pass if format, peak and size rules hold (re-run
  `generate_sfx.py` only if you want the procedural versions back; the manifest lists what exists).
* Not verified by ear in this repository's CI or by the author (no audio device or listener was available). Objective checks only.
* No music, no ambience, no voice lines, no music ducking.

## Adding a sound

1. Add a recipe function and a `add("name", category, variants, peak_db, fn)` line in `catalogue()`.
2. `python3 -I tools/audio/generate_sfx.py` and commit the new files + manifest.
3. Map it in `godot/combat/audio/combat_audio.gd` and add it to `REQUIRED` in `test_audio.gd` if it is mandatory.
