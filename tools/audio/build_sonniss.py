#!/usr/bin/env python3
"""Builds the in-game OGGs from the Sonniss #GameAudioGDC selection in assets/audio_incoming/sonniss/ (raw WAVs, kept out of git from now on).
Needs ffmpeg + numpy. Output: godot/assets/audio/<name>_<n>.ogg and godot/assets/audio/sonniss_manifest.json (read by combat_audio.gd).
Slicing, pitch variants, loudness targets and loops are all in SPEC below; rerun to regenerate: python3 tools/audio/build_sonniss.py
Licence: Sonniss GDC bundle, royalty-free, no attribution required; no resale of the raw files, no AI training (see CREDITS.md)."""
import json, os, re, subprocess, sys, tempfile
import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "assets", "audio_incoming", "sonniss")
OUT = os.path.join(ROOT, "godot", "assets", "audio")
SR = 48000

def find(sub):
    hits = [f for f in os.listdir(SRC) if sub.lower() in f.lower() and f.endswith(".wav")]
    if len(hits) != 1:
        sys.exit("source pattern %r matched %d files" % (sub, len(hits)))
    return os.path.join(SRC, hits[0])

# LUFS targets by bus role
TARGET = {"sfx": -15.0, "ui": -21.0, "music": -18.0, "amb": -27.0}
P3 = [1.0, 0.92, 1.08]   # pitch variants (a, b, c): the sources are few, so each frequent event gets three
P2 = [1.0, 0.94]

# name: (bus, category, [(source substring, start, end) ...], pitches, mono, extra)
SPEC = {
 # ---- combat: swings (pure whooshes: the impact comes from the hit event, never doubled here)
 "swing_sword":  ("sfx", "swing", [("SWING SCRAPE", 0.0, 1.1)], P3, True, {}),
 "swing_spear":  ("sfx", "swing", [("Woosh Debris", 0.0, 1.0)], P3, True, {}),
 "swing_staff":  ("sfx", "swing", [("Wind, Rush, Whoosh", 0.05, 0.95)], P3, True, {}),
 "swing_hammer": ("sfx", "swing", [("Slow Whoosh, Rattle", 0.05, 1.0)], [0.82, 0.76], True, {}),
 "swing_dual":   ("sfx", "swing", [("Sword Slice Special", 0.0, 1.2)], P3, True, {}),
 "swing_king":   ("sfx", "swing", [("Whoosh Fire Deep Growl", 0.0, 1.3)], [0.9, 0.82], True, {}),
 # ---- hits by material and weight
 "hit_flesh_light":   ("sfx", "hit", [("Combat Punch Impact Light", 0.0, 0.6)], P3, True, {}),
 "hit_flesh_heavy":   ("sfx", "hit", [("4 x Punch", 0.12, 0.75), ("4 x Punch", 1.1, 1.8), ("4 x Punch", 2.1, 2.75)], [1.0], True, {}),
 "hit_leather_light": ("sfx", "hit", [("Spear And Stick", 0.0, 0.4), ("Spear And Stick", 0.6, 1.0), ("Spear And Stick", 1.95, 2.35)], [1.0], True, {}),
 "hit_leather_heavy": ("sfx", "hit", [("Spear And Stick", 4.3, 4.85), ("Spear And Stick", 6.4, 6.9), ("Spear And Stick", 9.25, 9.95)], [0.88], True, {}),
 "hit_steel_light":   ("sfx", "hit", [("Old File Impact", 0.0, 0.47)], P3, True, {}),
 "hit_steel_heavy":   ("sfx", "hit", [("METAL SWING HIT", 0.0, 2.0)], P2, True, {}),
 "hit_plate_light":   ("sfx", "hit", [("Sword Slide Cuts", 0.1, 0.75), ("Sword Slide Cuts", 2.2, 2.85), ("Sword Slide Cuts", 4.3, 4.9)], [1.0], True, {}),
 "hit_plate_heavy":   ("sfx", "hit", [("SWING IMPACTS", 0.0, 0.95), ("SWING IMPACTS", 3.0, 3.95), ("SWING IMPACTS", 6.05, 6.95)], [1.0], True, {}),
 # ---- defence and movement
 "block":       ("sfx", "block", [("Old File Impact", 0.0, 0.47), ("Sword Slide Cuts", 6.3, 6.9), ("Sword Slide Cuts", 8.4, 9.0)], [0.82], True, {}),
 "parry":       ("sfx", "parry", [("Sword Slide Cuts", 10.75, 11.4), ("Metal Hit Thud Thump", 0.0, 1.4)], [1.1], True, {}),
 "guard_break": ("sfx", "guard_break", [("Gore Designed Transient", 0.0, 1.0)], [1.0], True, {}),
 "dodge":       ("sfx", "dodge", [("Woosh Sweep Slide", 0.0, 0.5), ("Wind, Rush, Whoosh", 0.05, 0.95)], P2, True, {}),
 # ---- abilities
 "ability_last_stand": ("sfx", "ability", [("Power Up Bright", 0.0, 1.5)], [1.0], False, {}),
 "ability_lunge":      ("sfx", "ability", [("Sword Slice Special", 0.0, 1.5)], [1.12], True, {}),
 "ability_blink":      ("sfx", "ability", [("Glass Crystal Fragments", 0.0, 1.3)], [1.0], False, {}),
 "ability_fortress":   ("sfx", "ability", [("Metal Hit Thud Thump", 0.0, 1.6)], [0.9], True, {}),
 "ability_fury":       ("sfx", "ability", [("Whoosh Fire Deep Growl", 0.0, 1.8)], [1.0], True, {}),
 "ability_counter":    ("sfx", "ability", [("METAL SWING HIT", 0.0, 1.2)], [1.15], True, {}),
 # ---- match cues (stingers)
 "fight_cue":       ("music", "fight", [("Impact Cut Sweep", 0.0, 1.8)], [1.0], False, {}),
 "countdown_tick":  ("ui", "countdown", [("Interface Percussion Snap", 0.0, 0.3)], [1.0], True, {}),
 "victory":         ("music", "victory", [("Braam, Epic, Cinematic, Dark, Instrument, Huge-32", 0.0, 5.0)], [1.0], False, {"fade_out": 1.5}),
 "defeat":          ("music", "defeat", [("Transition Braam Slow Dark", 0.0, 4.5)], [1.0], False, {"fade_out": 1.0}),
 # ---- UI
 "ui_hover":   ("ui", "ui", [("Interface Pop High Short", 0.0, 0.14)], P3, True, {}),
 "ui_click":   ("ui", "ui", [("UI Button Analog Vintage", 0.0, 0.17)], P3, True, {}),
 "ui_confirm": ("ui", "ui", [("Interface Accept Glassy Snap", 0.0, 0.44)], P2, True, {}),
 "ui_back":    ("ui", "ui", [("Interface Deny Low Fat Dark", 0.0, 0.5), ("Deny Muted", 0.0, 0.5)], [1.0], True, {}),
 "ui_deny":    ("ui", "ui", [("Deny Muted", 0.0, 0.7)], [1.0], True, {}),
 "ui_transition": ("ui", "ui", [("Woosh Sweep Slide", 0.0, 0.5)], P2, True, {}),
 # ---- chess side
 "chess_move":      ("sfx", "chess", [("Game Play Piece Action", 0.0, 0.22)], P3, True, {}),
 "chess_capture":   ("sfx", "chess", [("Spear And Stick", 0.0, 0.3), ("Spear And Stick", 4.3, 4.65)], [1.0, 0.9], True, {}),
 "chess_castle":    ("sfx", "chess", [("Board Reset Organic", 0.0, 1.1)], [1.0], True, {}),
 "chess_check":     ("sfx", "chess", [("Impact Hit Rapid Chord", 0.0, 1.8)], [1.0], False, {"fade_out": 0.8}),
 "chess_checkmate": ("music", "chess", [("Braam, Epic, Cinematic, Dark, Instrument, Huge-67", 0.0, 6.0)], [1.0], False, {"fade_out": 2.0}),
 "chess_promote":   ("sfx", "chess", [("Magic Light Spell", 0.0, 1.6)], [1.0], False, {"fade_out": 0.5}),
 "chess_win":       ("music", "chess", [("Braam, Epic, Cinematic, Dark, Instrument, Huge-32", 0.0, 5.0)], [1.0], False, {"fade_out": 1.5}),
 "chess_lose":      ("music", "chess", [("Transition Braam Slow Dark", 0.0, 4.5)], [1.0], False, {"fade_out": 1.0}),
 "capture_shatter": ("sfx", "chess", [("Glass Crystal Fragments", 0.0, 1.6)], [1.0], False, {"fade_out": 0.4}),
 "capture_intro":   ("music", "chess", [("Rapid Chord Reverb", 0.0, 2.2)], [0.9], False, {"fade_out": 0.6}),
 # ---- loops (seamless: equal-power crossfade of the tail into the head)
 "amb_torch":  ("amb", "ambience", [("Fire Crackling Crunchy", 0.0, None)], [1.0], True, {"loop": 0.8}),
 "amb_wind":   ("amb", "ambience", [("Weather Wind Whipping", 0.0, None)], [1.0], False, {"loop": 1.2}),
 "amb_mystic": ("amb", "ambience", [("Dark Loop Mystic Forest", 0.0, 40.0)], [1.0], False, {"loop": 3.0}),
}

def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode:
        sys.exit("ffmpeg failed: %s\n%s" % (" ".join(cmd), r.stderr[-400:]))
    return r.stderr

def decode(path, start, end, channels, pitch):
    """Float32 samples at SR, optionally trimmed and pitch-shifted by resampling (varispeed)."""
    cmd = ["ffmpeg", "-v", "error", "-ss", str(start)]
    if end is not None:
        cmd += ["-t", str(end - start)]
    cmd += ["-i", path, "-ac", str(channels)]
    flt = []
    if pitch != 1.0:
        flt.append("asetrate=%d,aresample=%d" % (round(48000 * pitch), SR))
    else:
        flt.append("aresample=%d" % SR)
    cmd += ["-af", ",".join(flt), "-f", "f32le", "-"]
    raw = subprocess.run(cmd, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, channels)

def lufs_gain(x, target):
    """Gain in dB to reach `target` LUFS (ffmpeg ebur128 on the real signal); falls back to peak -3 dB for very short material."""
    peak = float(np.abs(x).max()) + 1e-9
    peak_db = 20 * np.log10(peak)
    if len(x) < SR * 0.45:
        return -3.0 - peak_db
    with tempfile.NamedTemporaryFile(suffix=".wav") as t:
        write_wav(t.name, x)
        err = run(["ffmpeg", "-nostats", "-i", t.name, "-af", "ebur128=peak=true", "-f", "null", "-"])
    m = re.findall(r"I:\s+(-?[\d.]+) LUFS", err)
    loud = float(m[-1]) if m else target
    gain = target - loud
    return min(gain, -1.5 - peak_db)   # never past -1.5 dBFS peak (limiter-free headroom)

def write_wav(path, x):
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-f", "f32le", "-ar", str(SR), "-ac", str(x.shape[1]), "-i", "-", path], input=x.astype("<f4").tobytes(), check=True)

def fades(x, fin=0.003, fout=0.02):
    x = x.copy()
    n = len(x)
    a, b = min(int(fin * SR), n // 2), min(int(fout * SR), n // 2)
    if a: x[:a] *= np.linspace(0, 1, a)[:, None]
    if b: x[-b:] *= np.linspace(1, 0, b)[:, None]
    return x

def make_loop(x, seconds):
    n = int(seconds * SR)
    n = min(n, len(x) // 2)
    t = np.linspace(0, np.pi / 2, n)[:, None]
    y = x[n:].copy()
    y[-n:] = x[-n:] * np.cos(t) + x[:n] * np.sin(t)   # tail fades out while the head fades in: the end meets y[0] = x[n] seamlessly
    return y

def encode(path, x, mono):
    if mono and x.shape[1] == 2:
        x = x.mean(1, keepdims=True)
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-f", "f32le", "-ar", str(SR), "-ac", str(x.shape[1]), "-i", "-", "-c:a", "libvorbis", "-q:a", "4", path],
                   input=np.clip(x, -1, 1).astype("<f4").tobytes(), check=True)

def main():
    os.makedirs(OUT, exist_ok=True)
    manifest = {"generator": "tools/audio/build_sonniss.py", "licence": "Sonniss #GameAudioGDC bundle: royalty-free, no attribution; no resale of raw files, no AI training", "sounds": {}}
    sources = {}
    for name, (bus, cat, parts, pitches, mono, extra) in SPEC.items():
        files = []
        variants = [(p, pi) for p in parts for pi in pitches]
        for i, ((sub, start, end), pitch) in enumerate(variants):
            path = sources.setdefault(sub, find(sub))
            x = decode(path, start, end, 2, pitch)
            if len(x) < 100:
                sys.exit("empty slice for %s %s" % (name, sub))
            if "loop" in extra:
                x = make_loop(x, extra["loop"])
            else:
                x = fades(x, 0.003, extra.get("fade_out", 0.02))
            x = x * (10 ** (lufs_gain(x, TARGET[bus]) / 20))
            out = "%s_%d.ogg" % (name, i + 1)
            encode(os.path.join(OUT, out), x, mono)
            files.append("res://assets/audio/" + out)
        dur = round(len(x) / SR, 2)
        manifest["sounds"][name] = {"category": cat, "bus": bus, "files": files, "variants": len(files), "loop": "loop" in extra, "duration_s": dur, "replace": True}
        print("%-20s %d file(s) %.2fs" % (name, len(files), dur))
    json.dump(manifest, open(os.path.join(OUT, "sonniss_manifest.json"), "w"), indent=1, sort_keys=True)

if __name__ == "__main__":
    main()
