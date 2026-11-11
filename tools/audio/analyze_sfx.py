#!/usr/bin/env python3
"""Objective sanity report for the generated SFX (no listening required): peak, RMS, crest factor,
spectral centroid, DC offset, leading/trailing silence, clipping. Stdlib only.

    python3 -I tools/audio/analyze_sfx.py [DIR]
"""
import cmath
import math
import sys
import wave
from pathlib import Path

DEFAULT = Path(__file__).resolve().parents[2] / "godot" / "assets" / "combat" / "audio"


def fft(a):
    n = len(a)
    if n == 1:
        return a
    even, odd = fft(a[0::2]), fft(a[1::2])
    t = [cmath.exp(-2j * math.pi * k / n) * odd[k] for k in range(n // 2)]
    return [even[k] + t[k] for k in range(n // 2)] + [even[k] - t[k] for k in range(n // 2)]


def analyse(path):
    with wave.open(str(path)) as w:
        sr, n = w.getframerate(), w.getnframes()
        raw = w.readframes(n)
    s = [int.from_bytes(raw[2 * i:2 * i + 2], "little", signed=True) / 32768.0 for i in range(n)]
    peak = max(max(s), -min(s))
    rms = math.sqrt(sum(x * x for x in s) / n)
    size = 1
    while size < min(n, 8192):
        size *= 2
    # analyse the loudest window of 8192 samples
    best = max(range(0, max(1, n - size + 1), size // 2), key=lambda i: sum(x * x for x in s[i:i + size]))
    win = [s[best + i] * (0.5 - 0.5 * math.cos(2 * math.pi * i / size)) if best + i < n else 0.0 for i in range(size)]
    spec = [abs(c) for c in fft(win)[:size // 2]]
    tot = sum(spec) or 1e-9
    centroid = sum(k * sr / size * m for k, m in enumerate(spec)) / tot
    thr = 0.01
    lead = next((i for i, x in enumerate(s) if abs(x) > thr), n) / sr * 1000
    trail = next((i for i, x in enumerate(reversed(s)) if abs(x) > thr), n) / sr * 1000
    return dict(dur=n / sr, peak=20 * math.log10(max(peak, 1e-9)), rms=20 * math.log10(max(rms, 1e-9)),
                centroid=centroid, dc=sum(s) / n, lead_ms=lead, trail_ms=trail, clipped=sum(1 for x in s if abs(x) >= 0.9999))


def main():
    d = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT
    print(f"{'file':26} {'dur':>6} {'peak':>6} {'rms':>6} {'crest':>6} {'centroid':>9} {'dc':>8} {'lead':>6} {'trail':>6}")
    bad = 0
    for p in sorted(d.glob("*.wav")):
        r = analyse(p)
        flag = "" if (r["peak"] <= -1.0 and r["clipped"] == 0 and abs(r["dc"]) < 0.01) else "  <-- CHECK"
        bad += bool(flag)
        print(f"{p.name:26} {r['dur']:6.3f} {r['peak']:6.1f} {r['rms']:6.1f} {r['peak'] - r['rms']:6.1f} {r['centroid']:8.0f}Hz {r['dc']:8.5f} {r['lead_ms']:5.1f}ms {r['trail_ms']:5.1f}ms{flag}")
    print(f"{bad} file(s) flagged")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
