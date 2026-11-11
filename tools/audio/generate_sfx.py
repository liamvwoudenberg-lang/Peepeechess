#!/usr/bin/env python3
"""Deterministic procedural sound-effect generator for the combat module.

Everything here is synthesised from scratch by this script (filtered noise, modal resonators,
FM and additive tones). No third-party audio is used, so there are no external licences.
Python standard library only (wave, math, random, zlib, hashlib, json).

    python3 -I tools/audio/generate_sfx.py                 # writes godot/assets/combat/audio
    python3 -I tools/audio/generate_sfx.py --out DIR       # elsewhere (used by the determinism test)
    python3 -I tools/audio/generate_sfx.py --list          # names only

Output: 44.1 kHz mono 16-bit PCM WAV, `<name>.wav` or `<name>_<n>.wav` for variants, plus
`manifest.json` (name, files, duration, peak/rms/crest, loop flag, category) and `INVENTORY.md`.
Re-running produces byte-identical files on the same Python/platform (all randomness is seeded
from crc32(name:variant); float maths is IEEE-754 and uses only math.sin/cos/exp/sqrt/log).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import random
import sys
import wave
import zlib
from pathlib import Path

SR = 44100
TWO_PI = 2.0 * math.pi
REPO = Path(__file__).resolve().parents[2]
DEFAULT_OUT = REPO / "godot" / "assets" / "combat" / "audio"


# ---------------------------------------------------------------------------------------------
# DSP primitives (lists of floats)
# ---------------------------------------------------------------------------------------------
def N(seconds: float) -> int:
    return max(1, int(round(seconds * SR)))


def rng_for(name: str, variant: int) -> random.Random:
    return random.Random(zlib.crc32(f"{name}:{variant}".encode()))


def noise(n: int, rng: random.Random) -> list[float]:
    return [rng.random() * 2.0 - 1.0 for _ in range(n)]


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def path(keys):
    """Piecewise log-frequency interpolation: keys = [(x0, f0), (x1, f1), ...] with x in 0..1."""
    def f(x: float) -> float:
        if x <= keys[0][0]:
            return keys[0][1]
        for (xa, fa), (xb, fb) in zip(keys, keys[1:]):
            if x <= xb:
                t = (x - xa) / max(xb - xa, 1e-9)
                return math.exp(lerp(math.log(fa), math.log(fb), t))
        return keys[-1][1]
    return f


def lowpass(x, fc):
    a = 1.0 - math.exp(-TWO_PI * fc / SR)
    y = 0.0
    out = []
    for s in x:
        y += a * (s - y)
        out.append(y)
    return out


def highpass(x, fc):
    lp = lowpass(x, fc)
    return [s - l for s, l in zip(x, lp)]


def lp2(x, fc):
    """Two cascaded one-pole low-passes (12 dB/oct) - tames the SVF band-pass's broad high-frequency skirt."""
    return lowpass(lowpass(x, fc), fc)


def svf_band(x, fc_fn, damping=0.35):
    """Chamberlin state-variable band-pass with a time-varying centre frequency fc_fn(i/n)."""
    n = len(x)
    low = band = 0.0
    out = []
    for i, s in enumerate(x):
        fc = min(max(fc_fn(i / n), 40.0), 5500.0)
        f = 2.0 * math.sin(math.pi * fc / SR)
        low += f * band
        high = s - low - damping * band
        band += f * high
        out.append(band)
    return out


def env_exp(n, tau, attack=0.001):
    a = max(1, int(attack * SR))
    return [(i / a if i < a else math.exp(-(i - a) / (tau * SR))) for i in range(n)]


def env_bell(n, centre=0.5, power=2.0):
    k = math.log(0.5) / math.log(centre)
    return [math.sin(math.pi * ((i / max(n - 1, 1)) ** k)) ** power for i in range(n)]


def env_ramp(n, power=1.5, release=0.08):
    r = max(1, int(release * SR))
    out = []
    for i in range(n):
        e = (i / max(n - 1, 1)) ** power
        if i > n - r:
            e *= (n - i) / r
        out.append(e)
    return out


def sweep(n, f_fn, amp=1.0):
    """Sine with instantaneous frequency f_fn(i/n) (phase integrated)."""
    ph = 0.0
    out = []
    for i in range(n):
        ph += TWO_PI * f_fn(i / n) / SR
        out.append(amp * math.sin(ph))
    return out


def fm_sweep(n, fc_fn, ratio, index_fn, amp=1.0):
    ph = pm = 0.0
    out = []
    for i in range(n):
        x = i / n
        fc = fc_fn(x)
        ph += TWO_PI * fc / SR
        pm += TWO_PI * fc * ratio / SR
        out.append(amp * math.sin(ph + index_fn(x) * math.sin(pm)))
    return out


def modal(n, partials, phase=0.0):
    """Sum of exponentially decaying sinusoids (resonator bank) via complex rotation.
    partials = [(freq_hz, amp, tau_s), ...]"""
    out = [0.0] * n
    for f, a, tau in partials:
        if f >= SR * 0.47:
            continue
        w = TWO_PI * f / SR
        c, s = math.cos(w), math.sin(w)
        d = math.exp(-1.0 / (tau * SR))
        re, im = a * math.cos(phase), a * math.sin(phase)
        for i in range(n):
            out[i] += im
            re, im = d * (re * c - im * s), d * (re * s + im * c)
    return out


def mul(x, e):
    return [a * b for a, b in zip(x, e)]


def scaled(x, g):
    return [a * g for a in x]


def mix(n, *layers):
    out = [0.0] * n
    for layer, gain, offset in layers:
        for i, v in enumerate(layer):
            j = i + offset
            if 0 <= j < n:
                out[j] += v * gain
    return out


def fade_edges(x, ms=1.5):
    k = max(1, int(ms * SR / 1000.0))
    k = min(k, len(x) // 2)
    for i in range(k):
        g = i / k
        x[i] *= g
        x[-1 - i] *= g
    return x


def tremolo(n, hz, depth):
    return [1.0 - depth + depth * (0.5 + 0.5 * math.sin(TWO_PI * hz * i / SR)) for i in range(n)]


def normalise(x, peak_db):
    peak = max(max(x), -min(x), 1e-9)
    g = (10.0 ** (peak_db / 20.0)) / peak
    return [v * g for v in x]


# ---------------------------------------------------------------------------------------------
# Recipes. Each returns a raw (unnormalised) list of floats.
# ---------------------------------------------------------------------------------------------
def j(rng, x, p=0.07):
    return x * (1.0 + rng.uniform(-p, p))


SWING = {
    # family: duration, band-noise path, damping, air cutoff, body sine path (or None), body gain, peak position
    "spear": dict(d=0.22, fc=[(0, 1500), (0.55, 4200), (1, 3000)], damp=0.22, air=5000, body=None, bg=0.0, pk=0.55),
    "sword": dict(d=0.28, fc=[(0, 800), (0.45, 3300), (1, 1500)], damp=0.30, air=4200, body=None, bg=0.0, pk=0.5),
    "staff": dict(d=0.34, fc=[(0, 600), (0.5, 2200), (1, 900)], damp=0.45, air=3000, body=[(0, 170), (0.5, 260), (1, 190)], bg=0.5, pk=0.5),
    "hammer": dict(d=0.42, fc=[(0, 220), (0.6, 950), (1, 380)], damp=0.6, air=1400, body=[(0, 55), (0.6, 85), (1, 50)], bg=0.7, pk=0.62),
    "dual": dict(d=0.16, fc=[(0, 1900), (0.5, 4800), (1, 2600)], damp=0.2, air=5200, body=None, bg=0.0, pk=0.45),
    "king": dict(d=0.32, fc=[(0, 520), (0.5, 2500), (1, 1100)], damp=0.35, air=3200, body=[(0, 100), (0.5, 135), (1, 90)], bg=0.45, pk=0.52),
}


def make_swing(family, rng, v):
    p = SWING[family]
    n = N(j(rng, p["d"], 0.05))
    fc = path([(x, j(rng, f, 0.08)) for x, f in p["fc"]])
    if family == "dual":
        half = N(0.095)
        first = lp2(svf_band(noise(half, rng), fc, p["damp"]), p["air"])
        second = lp2(svf_band(noise(half, rng), path([(0, 2300), (0.5, 5000), (1, 2900)]), p["damp"]), p["air"])
        a = mul(first, env_bell(half, 0.45, 2.0))
        b = mul(second, env_bell(half, 0.45, 2.0))
        raw = mix(n, (a, 1.0, 0), (b, 0.85, N(0.062)))
        air = mul(lp2(noise(n, rng), p["air"] * 0.7), env_bell(n, 0.5, 2.0))
        return mix(n, (raw, 1.0, 0), (air, 0.12, 0))
    band = mul(lp2(svf_band(noise(n, rng), fc, p["damp"]), p["air"]), env_bell(n, p["pk"], 2.0))
    air = mul(lp2(noise(n, rng), p["air"] * 0.7), env_bell(n, p["pk"], 2.0))
    layers = [(band, 1.0, 0), (air, 0.15, 0)]
    if p["body"]:
        f = path([(x, j(rng, fq, 0.05)) for x, fq in p["body"]])
        body = mul(sweep(n, f), env_bell(n, p["pk"], 1.5))
        if family == "staff":  # spellblade hum: faint vibrato-like shimmer
            body = mul(body, tremolo(n, 38.0, 0.35))
        layers.append((body, p["bg"], 0))
    if family == "sword":  # faint steel "shing" ring
        ring = mul(modal(n, [(j(rng, 3100, 0.03), 1.0, 0.05), (j(rng, 5300, 0.03), 0.6, 0.035)]), env_bell(n, 0.4, 1.0))
        layers.append((ring, 0.06, 0))
    return mix(n, *layers)


MATERIAL = {"p": "leather", "n": "steel", "b": "flesh", "r": "plate", "q": "steel", "k": "steel"}


def make_hit(mat, heavy, rng, v):
    n = N(0.22 if heavy else 0.14)
    k = 1.0 if not heavy else 1.8
    if mat == "flesh":
        thump = mul(sweep(n, path([(0, j(rng, 120 if heavy else 170)), (0.3, 60 if heavy else 85), (1, 45 if heavy else 60)])), env_exp(n, 0.09 if heavy else 0.05))
        puff = mul(lowpass(noise(n, rng), 1100), env_exp(n, 0.04 if heavy else 0.02))
        return mix(n, (thump, 1.0, 0), (puff, 0.55, 0))
    if mat == "leather":
        slap = mul(highpass(lowpass(noise(n, rng), 2800), 400), env_exp(n, 0.03 if heavy else 0.015, 0.0005))
        thump = mul(sweep(n, path([(0, j(rng, 120)), (1, 60)])), env_exp(n, 0.07 if heavy else 0.04))
        return mix(n, (slap, 1.0, 0), (thump, 0.75, 0))
    if mat == "steel":
        f0 = j(rng, 850 if heavy else 1250, 0.06)
        ring = modal(n, [(f0, 1.0, 0.07 * k), (f0 * 2.76, 0.6, 0.05 * k), (f0 * 5.4, 0.35, 0.03 * k), (f0 * 8.93, 0.2, 0.02 * k)], phase=rng.random())
        click = mul(highpass(noise(n, rng), 3000), env_exp(n, 0.003, 0.0002))
        thump = mul(sweep(n, path([(0, 130), (1, 70)])), env_exp(n, 0.04 * k))
        return mix(n, (ring, 0.7, 0), (click, 0.8, 0), (thump, 0.5, 0))
    # plate
    f0 = j(rng, 320 if heavy else 520, 0.05)
    thump = mul(sweep(n, path([(0, 90 if heavy else 120), (0.4, 50 if heavy else 70), (1, 38 if heavy else 55)])), env_exp(n, 0.12 if heavy else 0.06))
    ring = modal(n, [(f0, 1.0, 0.1 * k), (f0 * 2.4, 0.5, 0.07 * k), (f0 * 4.1, 0.25, 0.04 * k)], phase=rng.random())
    thud = mul(lowpass(noise(n, rng), 700), env_exp(n, 0.05 if heavy else 0.025))
    return mix(n, (thump, 1.0, 0), (ring, 0.45, 0), (thud, 0.5, 0))


def make_block(rng, v):
    n = N(0.28)
    f0 = j(rng, 1100 if v % 2 == 0 else 1320, 0.04)
    ring = modal(n, [(f0, 1.0, 0.12), (f0 * 2.32, 0.7, 0.09), (f0 * 4.25, 0.5, 0.06), (f0 * 6.63, 0.3, 0.04)], phase=rng.random())
    click = mul(highpass(noise(n, rng), 2000), env_exp(n, 0.004, 0.0002))
    body = mul(sweep(n, path([(0, 190), (1, 120)])), env_exp(n, 0.05))
    return mix(n, (ring, 0.7, 0), (click, 0.7, 0), (body, 0.4, 0))


def make_guard_break(rng, v):
    n = N(0.45)
    crack = mul(highpass(noise(n, rng), 3000), env_exp(n, 0.012, 0.0003))
    crackle = [0.0] * n
    for _ in range(14):
        pos = int(rng.random() * 0.16 * SR)
        amp = rng.uniform(0.3, 1.0)
        for kk in range(30):
            if pos + kk < n:
                crackle[pos + kk] += amp * (rng.random() * 2 - 1) * math.exp(-kk / 8.0)
    thump = mul(sweep(n, path([(0, 95), (0.5, 55), (1, 40)])), env_exp(n, 0.1))
    ring = modal(n, [(700.0, 1.0, 0.1), (1540.0, 0.6, 0.08), (2660.0, 0.4, 0.06)], phase=rng.random())
    return mix(n, (crack, 0.9, 0), (crackle, 0.6, 0), (thump, 1.0, 0), (ring, 0.4, 0))


def make_parry(rng, v):
    n = N(0.58)
    f0 = 1760.0 if v % 2 == 0 else 1975.5
    ring = modal(n, [(f0, 1.0, 0.36), (f0 * 2.0, 0.55, 0.3), (f0 * 3.0, 0.3, 0.22), (f0 * 2.76, 0.28, 0.12), (f0 * 0.5, 0.45, 0.4)])
    click = mul(highpass(noise(n, rng), 4000), env_exp(n, 0.0025, 0.0001))
    sparkle_n = N(0.09)
    sparkle = mul(sweep(sparkle_n, path([(0, 2200), (1, 5200)])), env_exp(sparkle_n, 0.03, 0.002))
    body = mul(sweep(n, path([(0, 230), (1, 140)])), env_exp(n, 0.045))
    return mix(n, (ring, 0.8, 0), (click, 0.9, 0), (sparkle, 0.35, 0), (body, 0.35, 0))


def make_dodge(rng, v):
    n = N(0.22)
    band = mul(lp2(svf_band(noise(n, rng), path([(0, j(rng, 2000)), (1, j(rng, 480))]), 0.5), 2200), env_bell(n, 0.4, 2.0))
    rustle = mul(mul(highpass(lowpass(noise(n, rng), 3500), 800), tremolo(n, 55.0, 0.5)), env_bell(n, 0.35, 1.5))
    return mix(n, (band, 1.0, 0), (rustle, 0.35, 0))


def make_footstep(rng, v):
    n = N(0.09)
    thump = mul(sweep(n, path([(0, j(rng, 105, 0.12)), (1, 60)])), env_exp(n, 0.025))
    tick = mul(highpass(lowpass(noise(n, rng), 2600), 900), env_exp(n, 0.01, 0.0003))
    return mix(n, (thump, 1.0, 0), (tick, 0.35, 0))


def make_stagger(rng, v):
    n = N(0.15)
    thump = mul(sweep(n, path([(0, j(rng, 150)), (1, 60)])), env_exp(n, 0.05))
    puff = mul(lowpass(noise(n, rng), 900), env_exp(n, 0.03))
    rattle = modal(n, [(j(rng, 640, 0.05), 1.0, 0.04), (j(rng, 1390, 0.05), 0.5, 0.03)], phase=rng.random())
    return mix(n, (thump, 1.0, 0), (puff, 0.5, 0), (rattle, 0.18, 0))


def tri_note(n, f, tau, attack=0.004):
    e = env_exp(n, tau, attack)
    x = [0.0] * n
    ph = 0.0
    w = TWO_PI * f / SR
    for i in range(n):
        ph += w
        # soft triangle-ish via first odd harmonics
        x[i] = math.sin(ph) + math.sin(3 * ph) / -9.0 + math.sin(5 * ph) / 25.0
    return mul(x, e)


def make_defeat(rng, v):
    n = N(0.7)
    thump = mul(sweep(n, path([(0, 95), (0.3, 50), (1, 38)])), env_exp(n, 0.14))
    puff = mul(lowpass(noise(n, rng), 450), env_exp(n, 0.06))
    a = tri_note(N(0.4), 329.63, 0.18)
    b = tri_note(N(0.4), 246.94, 0.22)
    return mix(n, (thump, 1.0, 0), (puff, 0.4, 0), (a, 0.45, N(0.1)), (b, 0.5, N(0.3)))


def brass_note(n, f, tau, attack=0.012, vib=0.0):
    out = [0.0] * n
    ph = 0.0
    for i in range(n):
        t = i / SR
        ph += TWO_PI * f * (1.0 + vib * math.sin(TWO_PI * 5.5 * t)) / SR
        s = 0.0
        for kk, g in ((1, 1.0), (2, 0.55), (3, 0.38), (4, 0.22), (5, 0.12), (6, 0.07)):
            s += g * math.sin(kk * ph)
        out[i] = s
    return mul(out, env_exp(n, tau, attack))


def make_victory(rng, v):
    n = N(0.65)
    notes = [(523.25, 0.0), (659.25, 0.11), (783.99, 0.22), (1046.5, 0.33)]
    layers = []
    for idx, (f, start) in enumerate(notes):
        last = idx == len(notes) - 1
        dur = 0.65 - start
        layers.append((brass_note(N(dur), f, 0.5 if last else 0.12, 0.010, 0.004 if last else 0.0), 1.0 if last else 0.8, N(start)))
    shimmer = modal(n, [(2093.0, 1.0, 0.35), (3136.0, 0.5, 0.3), (4186.0, 0.3, 0.25)])
    layers.append((mul(shimmer, [0.0 if i < N(0.33) else 1.0 for i in range(n)]), 0.18, 0))
    return mix(n, *layers)


def make_ability(kind, rng, v):
    if kind == "last_stand":
        n = N(0.65)
        swell = mul(lp2(svf_band(noise(n, rng), path([(0, 150), (1, 1800)]), 0.6), 2200), env_ramp(n, 1.4, 0.06))
        growl = mul(sweep(n, path([(0, 70), (1, 120)])), mul(env_ramp(n, 1.2, 0.06), tremolo(n, 28.0, 0.6)))
        grit = mul(highpass(lp2(noise(n, rng), 3500), 1500), env_ramp(n, 2.0, 0.06))
        return mix(n, (swell, 1.0, 0), (growl, 0.9, 0), (grit, 0.12, 0))
    if kind == "lunge":
        n = N(0.6)
        cn = N(0.38)
        charge = mul(lp2(svf_band(noise(cn, rng), path([(0, 400), (1, 3000)]), 0.4), 3500), env_ramp(cn, 1.6, 0.01))
        thump = mul(sweep(n, path([(0, 120), (1, 50)])), env_exp(n, 0.1))
        ring = modal(n, [(520.0, 1.0, 0.12), (1210.0, 0.6, 0.1), (2150.0, 0.4, 0.07)], phase=rng.random())
        burst = mul(highpass(lp2(noise(n, rng), 5000), 1500), env_exp(n, 0.02, 0.0005))
        i0 = N(0.38)
        return mix(n, (charge, 1.0, 0), (thump, 1.0, i0), (ring, 0.5, i0), (burst, 0.6, i0))
    if kind == "blink":
        n = N(0.35)
        zap = mul(fm_sweep(n, path([(0, 2400), (0.5, 600), (1, 300)]), 1.5, lambda x: 6.0 * (1 - x)), env_exp(n, 0.12, 0.001))
        sn = N(0.2)
        spark = mul(mul(sweep(sn, path([(0, 1800), (1, 5200)])), tremolo(sn, 40.0, 0.5)), env_bell(sn, 0.5, 1.0))
        crackle = mul(lp2(svf_band(noise(n, rng), lambda x: 4200, 0.3), 5000), env_exp(n, 0.05, 0.001))
        return mix(n, (zap, 1.0, 0), (spark, 0.45, N(0.12)), (crackle, 0.3, 0))
    if kind == "fortress":
        n = N(0.6)
        res = modal(n, [(98.0, 1.0, 0.55), (148.0, 0.8, 0.5), (233.0, 0.7, 0.45), (331.0, 0.5, 0.4), (412.0, 0.3, 0.35), (881.0, 0.15, 0.3)])
        att = [min(1.0, i / (0.04 * SR)) for i in range(n)]
        swell = mul(lowpass(noise(n, rng), 220), env_bell(n, 0.35, 1.5))
        return mix(n, (mul(res, att), 1.0, 0), (swell, 0.5, 0))
    if kind == "fury":
        n = N(0.6)
        base = path([(0, 330), (1, 990)])
        voices = []
        for ratio, g in ((1.0, 1.0), (1.005, 0.8), (1.5, 0.5), (2.01, 0.4), (3.0, 0.2)):
            voices.append((sweep(n, lambda x, r=ratio: base(x) * r), g, 0))
        stack = mix(n, *voices)
        shaped = mul(mul(stack, tremolo(n, 12.0, 0.4)), env_ramp(n, 0.7, 0.12))
        air = mul(highpass(noise(n, rng), 4000), env_ramp(n, 1.2, 0.12))
        return mix(n, (shaped, 1.0, 0), (air, 0.12, 0))
    if kind == "counter":
        n = N(0.65)
        f0 = 660.0
        bell = modal(n, [(f0, 1.0, 0.5), (f0 * 2.0, 0.6, 0.35), (f0 * 2.41, 0.35, 0.28), (f0 * 3.0, 0.3, 0.25), (f0 * 4.07, 0.15, 0.15)])
        click = mul(highpass(noise(n, rng), 3500), env_exp(n, 0.003, 0.0002))
        return mix(n, (bell, 1.0, 0), (click, 0.4, 0))
    raise ValueError(kind)


def make_countdown_tick(rng, v):
    n = N(0.08)
    x = mix(n, (mul(sweep(n, lambda t: 880.0), env_exp(n, 0.03, 0.002)), 1.0, 0), (mul(sweep(n, lambda t: 1760.0), env_exp(n, 0.02, 0.002)), 0.3, 0))
    return x


def make_fight_cue(rng, v):
    n = N(0.5)
    chord = mix(n, *[(brass_note(n, f, 0.3, 0.025), g, 0) for f, g in ((392.0, 1.0), (493.88, 0.8), (587.33, 0.8), (783.99, 0.9))])
    blast = mul(highpass(noise(n, rng), 1500), env_exp(n, 0.04, 0.001))
    return mix(n, (chord, 1.0, 0), (blast, 0.25, 0))


def make_ui(kind, rng, v):
    if kind == "hover":
        n = N(0.04)
        return mul(sweep(n, lambda t: 2200.0), env_exp(n, 0.008, 0.001))
    if kind == "click":
        n = N(0.06)
        t = mul(sweep(n, lambda t: 1200.0), env_exp(n, 0.012, 0.001))
        c = mul(highpass(noise(n, rng), 3000), env_exp(n, 0.004, 0.0002))
        return mix(n, (t, 1.0, 0), (c, 0.25, 0))
    if kind == "confirm":
        n = N(0.2)
        a = mul(sweep(N(0.1), lambda t: 660.0), env_exp(N(0.1), 0.04, 0.002))
        b = mul(sweep(N(0.13), lambda t: 990.0), env_exp(N(0.13), 0.05, 0.002))
        return mix(n, (a, 1.0, 0), (b, 0.9, N(0.07)))
    if kind == "back":
        n = N(0.14)
        a = mul(sweep(N(0.07), lambda t: 660.0), env_exp(N(0.07), 0.03, 0.002))
        b = mul(sweep(N(0.09), lambda t: 440.0), env_exp(N(0.09), 0.04, 0.002))
        return mix(n, (a, 1.0, 0), (b, 0.9, N(0.05)))
    raise ValueError(kind)


# ---------------------------------------------------------------------------------------------
# Catalogue: name -> (category, variants, peak_db, builder(rng, variant))
# ---------------------------------------------------------------------------------------------
def catalogue():
    cat = {}

    def add(name, category, variants, peak_db, fn):
        cat[name] = (category, variants, peak_db, fn)

    for fam in SWING:
        add(f"swing_{fam}", "swing", 2, -6.0, lambda r, v, fam=fam: make_swing(fam, r, v))
    for mat in ("flesh", "leather", "steel", "plate"):
        add(f"hit_{mat}_light", "hit", 2, -3.0, lambda r, v, mat=mat: make_hit(mat, False, r, v))
        add(f"hit_{mat}_heavy", "hit", 2, -2.5, lambda r, v, mat=mat: make_hit(mat, True, r, v))
    add("block", "defence", 2, -3.0, make_block)
    add("guard_break", "defence", 1, -2.5, make_guard_break)
    add("parry", "defence", 2, -2.0, make_parry)
    add("dodge", "movement", 2, -8.0, make_dodge)
    add("footstep_stone", "movement", 3, -17.0, make_footstep)
    add("stagger", "reaction", 2, -6.0, make_stagger)
    add("defeat", "result", 1, -3.0, make_defeat)
    add("victory", "result", 1, -4.0, make_victory)
    for kind in ("last_stand", "lunge", "blink", "fortress", "fury", "counter"):
        add(f"ability_{kind}", "ability", 1, -4.0, lambda r, v, kind=kind: make_ability(kind, r, v))
    add("countdown_tick", "cue", 1, -8.0, make_countdown_tick)
    add("fight_cue", "cue", 1, -3.0, make_fight_cue)
    for kind, pk in (("hover", -16.0), ("click", -10.0), ("confirm", -9.0), ("back", -10.0)):
        add(f"ui_{kind}", "ui", 1, pk, lambda r, v, kind=kind: make_ui(kind, r, v))
    return cat


def to_pcm(x):
    out = bytearray()
    for v in x:
        i = int(round(v * 32767.0))
        i = max(-32767, min(32767, i))
        out += i.to_bytes(2, "little", signed=True)
    return bytes(out)


def write_wav(path_: Path, pcm: bytes) -> None:
    with wave.open(str(path_), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm)


def stats_of(pcm: bytes):
    n = len(pcm) // 2
    samples = [int.from_bytes(pcm[2 * i:2 * i + 2], "little", signed=True) / 32768.0 for i in range(n)]
    peak = max(max(samples), -min(samples), 1e-9)
    rms = math.sqrt(sum(s * s for s in samples) / n)
    db = lambda a: round(20.0 * math.log10(max(a, 1e-9)), 2)
    return {"duration_s": round(n / SR, 4), "peak_db": db(peak), "rms_db": db(rms), "crest_db": round(db(peak) - db(rms), 2)}


def generate(out_dir: Path, only=None) -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)
    manifest = {"generator": "tools/audio/generate_sfx.py", "sample_rate": SR, "channels": 1, "bit_depth": 16,
                "licence": "Generated procedurally by this repository's script; no third-party audio.", "sounds": {}}
    rows = []
    for name, (category, variants, peak_db, fn) in sorted(catalogue().items()):
        if only and name not in only:
            continue
        files = []
        durations = []
        stats_acc = []
        for v in range(variants):
            raw = fn(rng_for(name, v), v)
            raw = fade_edges(normalise(raw, peak_db))
            pcm = to_pcm(raw)
            fname = f"{name}.wav" if variants == 1 else f"{name}_{v + 1}.wav"
            write_wav(out_dir / fname, pcm)
            files.append(fname)
            s = stats_of(pcm)
            stats_acc.append(s)
            durations.append(s["duration_s"])
            rows.append((fname, s, 44 + len(pcm)))
        manifest["sounds"][name] = {
            "category": category, "files": files, "variants": variants, "loop": False,
            "duration_s": round(max(durations), 4),
            "peak_db": max(s["peak_db"] for s in stats_acc),
            "rms_db": round(sum(s["rms_db"] for s in stats_acc) / variants, 2),
            "crest_db": round(sum(s["crest_db"] for s in stats_acc) / variants, 2),
        }
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    total = sum(r[2] for r in rows)
    lines = ["# Sound inventory (generated by tools/audio/generate_sfx.py - do not edit)", "",
             "| file | duration (s) | peak dBFS | RMS dBFS | crest dB | bytes |", "| --- | ---: | ---: | ---: | ---: | ---: |"]
    for fname, s, size in rows:
        lines.append(f"| {fname} | {s['duration_s']:.3f} | {s['peak_db']:.1f} | {s['rms_db']:.1f} | {s['crest_db']:.1f} | {size} |")
    lines += ["", f"Total: {len(rows)} files, {total} bytes ({total / 1048576.0:.2f} MiB)."]
    (out_dir / "INVENTORY.md").write_text("\n".join(lines) + "\n")
    return manifest


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    ap.add_argument("--only", default="", help="comma separated sound names")
    ap.add_argument("--list", action="store_true")
    a = ap.parse_args()
    if a.list:
        print("\n".join(sorted(catalogue())))
        return 0
    only = {s for s in a.only.split(",") if s}
    manifest = generate(a.out, only or None)
    digest = hashlib.sha256(json.dumps(manifest, sort_keys=True).encode()).hexdigest()[:12]
    print(f"wrote {sum(m['variants'] for m in manifest['sounds'].values())} files to {a.out} (manifest {digest})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
