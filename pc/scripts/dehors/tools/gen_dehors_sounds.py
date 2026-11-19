#!/usr/bin/env python3
"""Synthesizes the sounds of chapter 3, "Dehors" (the yard at night). Everything is generated from scratch (numpy /
scipy), nothing recorded, no existing melody. Deterministic (fixed seeds).

    python3 -I pc/scripts/dehors/tools/gen_dehors_sounds.py [--only name,name]

Writes mono 44.1 kHz Ogg Vorbis into assets/audio/dehors/ (pc/assets/audio is a link to it) and that folder's own
manifest.json (merged into the library by autoload/audio_manager.gd EXTRA_MANIFESTS). Then run
`godot --headless --path pc --import` once.

  footstep_grass / _gravel / _leaves   the player's steps outdoors (5 each)
  dh_her_grass / _gravel / _leaves     her steps, heavier and slower (4 each)
  dh_lantern      loop   the wire handle of her storm lantern working in its sockets as she walks
  dh_wind         loop   night wind in bare trees        dh_theme   loop   a low drone, far-apart cold bell tones
  dh_owl, dh_twig, dh_gust             the night around
  dh_chimes       7 s    the wind chimes of the porch, shaken     dh_horn / dh_horn_dead   the horn of the dead car
  dh_radio        loop   an old tune through a small speaker, hiss and crackle
  dh_chain, dh_cut, dh_gate            the gate: the chain rattled, cut, the leaves dragged open
  dh_trap_open, dh_trap_slam           the cellar doors          dh_pot   a clay pot lifted off a bench
  dh_glass_bang   two palms on a pane  dh_stone_hard / _soft     a thrown pebble landing
  dh_swing        8 s    a swing going by itself, chains creaking
"""
import argparse
import json
import os
import subprocess

import numpy as np
from scipy import signal

SR = 44100
HERE = os.path.dirname(os.path.abspath(__file__))
PC = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
OUT = os.path.join(PC, "assets", "audio", "dehors")
MANIFEST = os.path.join(OUT, "manifest.json")


# ----------------------------------------------------------------------------------------------- helpers
def secs(d):
    return int(round(d * SR))


def bp(x, lo, hi, order=2):
    return signal.sosfilt(signal.butter(order, [lo, min(hi, SR * 0.49)], btype="band", fs=SR, output="sos"), x)


def lp(x, hz, order=2):
    return signal.sosfilt(signal.butter(order, hz, btype="low", fs=SR, output="sos"), x)


def hp(x, hz, order=2):
    return signal.sosfilt(signal.butter(order, hz, btype="high", fs=SR, output="sos"), x)


def place(buf, x, at, gain=1.0):
    i = secs(at)
    n = min(len(x), len(buf) - i)
    if n > 0 and i >= 0:
        buf[i:i + n] += x[:n] * gain


def wrap_add(buf, x, at, gain=1.0):
    idx = (secs(at) + np.arange(len(x))) % len(buf)
    np.add.at(buf, idx, x * gain)


def env_exp(n, t60, attack=0.001):
    t = np.arange(n) / SR
    e = np.exp(-6.91 * t / t60)
    a = secs(attack)
    if a > 1:
        e[:a] *= np.linspace(0, 1, a)
    return e


def cband(x, lo=None, hi=None, order=2):
    """Zero-phase circular (loop-periodic) band filter in the frequency domain."""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    g = np.ones_like(f)
    if lo:
        g *= 1.0 / np.sqrt(1.0 + (lo / np.maximum(f, 1e-9)) ** (2 * order))
    if hi:
        g *= 1.0 / np.sqrt(1.0 + (f / hi) ** (2 * order))
    return np.fft.irfft(X * g, len(x))


def cnoise(n, rng, lo=None, hi=None, order=2):
    x = cband(rng.standard_normal(n), lo, hi, order)
    x -= np.mean(x)
    return x / (np.std(x) + 1e-12)


def lfo(n, rng, cycles, depth=1.0):
    """A slow periodic wander in 0..1 made of a few sines with whole numbers of cycles over the loop."""
    t = np.arange(n) / n
    y = np.zeros(n)
    for c in cycles:
        y += np.sin(2 * np.pi * (c * t + rng.random())) * rng.uniform(0.5, 1.0)
    y = (y - y.min()) / (y.max() - y.min() + 1e-9)
    return 1.0 - depth + depth * y


def fade(x, t_in=0.002, t_out=0.03):
    x = x.copy()
    a = secs(t_in)
    b = secs(t_out)
    if a > 1:
        x[:a] *= np.linspace(0, 1, a)
    if b > 1:
        x[-b:] *= np.linspace(1, 0, b)
    return x


def normalize(x, db=-3.0):
    return x / (np.max(np.abs(x)) + 1e-12) * 10 ** (db / 20.0)


def air(x, seed, amount=0.1, t60=0.5):
    """A short open-air tail (no room: a few sparse echoes off the house and the trees)."""
    rng = np.random.default_rng(seed)
    n = secs(t60 * 1.2)
    t = np.arange(n) / SR
    ir = bp(rng.standard_normal(n), 300, 5000, 1) * np.exp(-6.91 * t / t60) * np.clip(t / 0.03, 0, 1)
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
    wet = signal.fftconvolve(x, ir)
    out = np.zeros(len(wet))
    out[:len(x)] += x
    out += amount * wet
    return out


def grains(n, rng, count, lo, hi, dur=(0.002, 0.008), shape=None, q=1):
    """A cloud of short band-passed noise ticks over n samples; shape(u) = density / level along 0..1."""
    out = np.zeros(n)
    for i in range(count):
        u = rng.random() ** (1.6 if shape is None else 1.0)
        lvl = 1.0 if shape is None else shape(u)
        if lvl <= 0:
            continue
        d = secs(rng.uniform(*dur))
        f0 = rng.uniform(lo, hi * 0.7)
        g = bp(rng.standard_normal(d + 64), f0, min(f0 * rng.uniform(1.4, 2.6), hi), q)[32:32 + d] * np.hanning(d)
        place(out, g, u * (n - d) / SR, lvl * rng.uniform(0.3, 1.0))
    return out


def thump(rng, f0, f1, dur, noise=0.0):
    n = secs(dur)
    t = np.arange(n) / SR
    f = f0 * (f1 / f0) ** (t / dur)
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-6.91 * t / (dur * 0.8))
    if noise > 0:
        x += noise * lp(rng.standard_normal(n), 900, 2) * np.exp(-6.91 * t / (dur * 0.3))
    return x


def ring(freqs, dur, amps=None, decays=None):
    n = secs(dur)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for i, f in enumerate(freqs):
        a = 1.0 if amps is None else amps[i]
        d = dur * 0.5 if decays is None else decays[i]
        x += a * np.sin(2 * np.pi * f * t) * np.exp(-6.91 * t / d)
    return x


# ----------------------------------------------------------------------------------------------- footsteps
def step_grass(seed, heavy=False):
    rng = np.random.default_rng(seed)
    n = secs(0.34 if heavy else 0.26)
    x = thump(rng, 120 if heavy else 150, 60, 0.11, 0.6)
    x = np.pad(x, (0, n - len(x)))
    swish = bp(rng.standard_normal(n), 1800, 7500, 1) * np.exp(-np.arange(n) / SR / 0.05) * np.clip(np.arange(n) / SR / 0.012, 0, 1)
    x = (1.3 if heavy else 0.9) * x + 0.28 * swish + 0.22 * grains(n, rng, 26, 2500, 9000)
    return fade(lp(x, 9000), 0.002, 0.05)


def step_gravel(seed, heavy=False):
    rng = np.random.default_rng(seed)
    n = secs(0.36 if heavy else 0.3)
    dens = lambda u: (1.0 if u < 0.35 else 0.55 * (1.0 - u)) + (0.5 if 0.5 < u < 0.7 else 0.0)       # heel, then the toe rolls
    x = grains(n, rng, 150 if heavy else 110, 1400, 9500, (0.0015, 0.007), dens, 1)
    x += 0.5 * grains(n, rng, 40, 500, 2400, (0.004, 0.012), dens, 1)
    x += (0.5 if heavy else 0.3) * np.pad(thump(rng, 130, 70, 0.07, 0.4), (0, n - secs(0.07)))
    return fade(x, 0.001, 0.05)


def step_leaves(seed, heavy=False):
    rng = np.random.default_rng(seed)
    n = secs(0.42 if heavy else 0.36)
    dens = lambda u: 1.0 if u < 0.3 else 0.8 * (1.0 - u) ** 0.7
    x = grains(n, rng, 170 if heavy else 130, 900, 8500, (0.003, 0.014), dens, 1)
    t = np.arange(n) / SR
    rustle = bp(rng.standard_normal(n), 2500, 9000, 1) * np.exp(-t / 0.09) * (0.5 + 0.5 * np.abs(lp(rng.standard_normal(n), 60, 2)) * 8)
    x += 0.35 * rustle + (0.4 if heavy else 0.22) * np.pad(thump(rng, 120, 60, 0.08, 0.5), (0, n - secs(0.08)))
    return fade(x, 0.001, 0.07)


# ----------------------------------------------------------------------------------------------- the night
def wind():
    rng = np.random.default_rng(100)
    n = secs(32.0)
    low = cnoise(n, rng, 60, 420, 2) * lfo(n, rng, (1, 2, 3), 0.75)
    mid = cnoise(n, rng, 350, 1400, 1) * lfo(n, rng, (2, 3, 5), 0.85) ** 2
    hiss = cnoise(n, rng, 2200, 7000, 1) * lfo(n, rng, (3, 5, 7), 0.95) ** 3            # gusts in the twigs
    # a faint whistle that comes and goes (wind in the eaves)
    t = np.arange(n) / SR
    whistle = cband(rng.standard_normal(n), 640, 720, 4) * lfo(n, rng, (1, 4), 1.0) ** 4
    return 0.75 * low + 0.5 * mid + 0.32 * hiss + 0.5 * whistle / (np.std(whistle) + 1e-9) * 0.12


def bell(f, dur, seed):
    rng = np.random.default_rng(seed)
    parts = [1.0, 2.0, 2.76, 5.4, 8.93]
    amps = [1.0, 0.25, 0.5, 0.22, 0.1]
    dec = [dur * 0.6, dur * 0.4, dur * 0.3, dur * 0.16, dur * 0.1]
    x = ring([f * p * (1 + rng.uniform(-0.002, 0.002)) for p in parts], dur, amps, dec)
    return x * np.clip(np.arange(len(x)) / SR / 0.006, 0, 1)


def theme():
    rng = np.random.default_rng(200)
    dur = 48.0
    n = secs(dur)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for f, a, cyc in ((49.0, 1.0, 3), (73.5, 0.5, 5), (98.25, 0.3, 4), (147.3, 0.12, 7)):
        f = round(f * dur) / dur                                        # whole cycles over the loop
        out += a * np.sin(2 * np.pi * f * t + rng.random() * 6.28) * (0.6 + 0.4 * np.sin(2 * np.pi * cyc * t / dur + rng.random() * 6.28))
    pad = cnoise(n, rng, 900, 1500, 3) * lfo(n, rng, (1, 2), 0.9) ** 2
    out += 0.07 * pad
    # cold bell tones, far apart, two of them a tritone from the drone
    for at, f, g in ((5.0, 392.0, 0.3), (17.5, 277.2, 0.34), (26.0, 415.3, 0.22), (37.0, 261.6, 0.3), (43.5, 554.4, 0.14)):
        b = air(bell(f, 7.0, int(f)), int(f) + 1, 0.3, 1.8)
        wrap_add(out, b, at, g)
    return cband(out, 30, 6000, 1)


def owl(seed):
    rng = np.random.default_rng(seed)
    n = secs(2.6)
    out = np.zeros(n)
    f0 = rng.uniform(330, 390)
    for at, d, a in ((0.0, 0.42, 1.0), (0.75, 0.22, 0.7), (1.05, 0.5, 0.9)):
        m = secs(d)
        t = np.arange(m) / SR
        f = f0 * (1.0 + 0.04 * np.sin(2 * np.pi * 5.5 * t) - 0.06 * t / d)
        x = (np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.25 * np.sin(4 * np.pi * np.cumsum(f) / SR)) * np.sin(np.pi * t / d) ** 1.5
        place(out, x, at, a)
    return fade(air(lp(out, 1800), seed + 1, 0.5, 1.4), 0.01, 0.3)


def twig(seed):
    rng = np.random.default_rng(seed)
    n = secs(0.5)
    out = np.zeros(n)
    for at, a in ((0.0, 1.0), (rng.uniform(0.05, 0.12), 0.45), (rng.uniform(0.16, 0.3), 0.2)):
        m = secs(0.06)
        x = bp(rng.standard_normal(m), 900, 6500, 1) * env_exp(m, 0.025, 0.0003)
        x += 0.6 * ring([rng.uniform(700, 1100), rng.uniform(1700, 2600)], 0.06, [1, 0.5], [0.03, 0.02])
        place(out, x, at, a)
    return fade(air(out, seed, 0.25, 0.5), 0.0005, 0.1)


def gust(seed):
    rng = np.random.default_rng(seed)
    n = secs(3.4)
    t = np.arange(n) / SR
    e = np.sin(np.pi * np.clip(t / 3.4, 0, 1)) ** 2
    x = bp(rng.standard_normal(n), 1800, 9000, 1) * e * (0.6 + 0.4 * np.abs(lp(rng.standard_normal(n), 25, 2)) * 10)
    x += 0.5 * grains(n, rng, 260, 1500, 8000, (0.004, 0.02), lambda u: np.sin(np.pi * u) ** 2)
    return fade(x, 0.2, 0.5)


# ----------------------------------------------------------------------------------------------- lures
CHIME_NOTES = (1046.5, 1174.7, 1396.9, 1568.0, 1864.7)


def chimes():
    rng = np.random.default_rng(300)
    n = secs(8.2)
    out = np.zeros(n)
    at = 0.0
    while at < 6.6:
        f = CHIME_NOTES[rng.integers(len(CHIME_NOTES))]
        tube = ring([f, f * 2.76, f * 5.4, f * 8.9], 2.6, [1.0, 0.45, 0.22, 0.08], [2.2, 1.1, 0.5, 0.25])
        tube *= np.clip(np.arange(len(tube)) / SR / 0.002, 0, 1)
        g = (1.0 if at < 2.5 else max(0.25, 1.0 - (at - 2.5) / 5.0)) * rng.uniform(0.5, 1.0)
        place(out, tube, at, g)
        place(out, bp(rng.standard_normal(secs(0.012)), 2500, 9000, 1) * np.hanning(secs(0.012)), at, g * 0.5)      # the clapper
        at += rng.uniform(0.05, 0.22) if at < 2.5 else rng.uniform(0.18, 0.7)
    return fade(air(out, 301, 0.15, 0.9)[:n], 0.001, 0.6)


def horn():
    rng = np.random.default_rng(310)
    dur = 3.6
    n = secs(dur)
    t = np.arange(n) / SR
    sag = 1.0 - 0.1 * np.clip((t - 2.2) / 1.4, 0, 1) ** 2                 # the battery gives
    wob = 1.0 + 0.012 * np.sin(2 * np.pi * 7.0 * t) * np.clip((t - 1.5) / 2.0, 0, 1)
    x = np.zeros(n)
    for f0, a in ((348.0, 1.0), (436.0, 0.9)):
        ph = 2 * np.pi * np.cumsum(f0 * sag * wob) / SR
        for h in range(1, 14):
            x += a * np.sin(h * ph + rng.random() * 6.28) / h ** 0.85
    e = np.clip(t / 0.03, 0, 1) * (1.0 - 0.75 * np.clip((t - 2.6) / 1.0, 0, 1) ** 1.5)
    crack = 1.0 - 0.6 * (lp(rng.standard_normal(n), 30, 2) * 12 > 0.9) * np.clip((t - 2.0) / 1.0, 0, 1)
    x = bp(x * e * crack, 280, 4200, 2)
    return fade(air(np.tanh(x * 0.25), 311, 0.3, 1.2), 0.002, 0.25)


def horn_dead():
    rng = np.random.default_rng(320)
    n = secs(0.9)
    t = np.arange(n) / SR
    out = np.zeros(n)
    place(out, bp(rng.standard_normal(secs(0.02)), 1500, 6000, 1) * env_exp(secs(0.02), 0.01, 0.0003), 0.0, 1.0)      # the relay
    f = 240.0 * np.exp(-t / 0.5)
    ph = 2 * np.pi * np.cumsum(f) / SR
    wheeze = sum(np.sin(h * ph) / h for h in range(1, 9)) * np.exp(-t / 0.22) * np.clip((t - 0.04) / 0.02, 0, 1)
    out += 0.5 * bp(wheeze, 200, 2500, 1)
    return fade(out, 0.0005, 0.1)


def radio():
    rng = np.random.default_rng(330)
    bar = 1.6                                                         # a slow waltz, 10 bars
    dur = bar * 10
    n = secs(dur)
    t = np.arange(n) / SR
    out = np.zeros(n)
    A = 220.0
    semis = lambda k: A * 2 ** (k / 12.0)
    # (bar, beat of 3, semitone above A3, beats long): an original tune in A minor
    tune = [(0, 0, 12, 2), (0, 2, 15, 1), (1, 0, 19, 2), (1, 2, 17, 1), (2, 0, 15, 1.5), (2, 1.5, 14, 0.5), (2, 2, 12, 1), (3, 0, 11, 3),
            (4, 0, 12, 2), (4, 2, 15, 1), (5, 0, 20, 2), (5, 2, 19, 1), (6, 0, 17, 1), (6, 1, 15, 1), (6, 2, 14, 1), (7, 0, 12, 3),
            (8, 0, 8, 2), (8, 2, 12, 1), (9, 0, 11, 2), (9, 2, 7, 1)]
    wow = 1.0 + 0.006 * np.sin(2 * np.pi * 0.625 * t) + 0.002 * np.sin(2 * np.pi * 5.0 * t)       # 0.625 Hz = 10 cycles / 16 s
    beat = bar / 3.0
    for b, bt, k, ln in tune:
        d = ln * beat
        m = secs(d + 0.25)
        tt = np.arange(m) / SR
        i0 = secs(b * bar + bt * beat)
        w = wow[(i0 + np.arange(m)) % n]
        ph = 2 * np.pi * np.cumsum(semis(k) * w * (1.0 + 0.008 * np.sin(2 * np.pi * 5.5 * tt))) / SR
        x = (np.sin(ph) + 0.4 * np.sin(2 * ph) + 0.22 * np.sin(3 * ph)) * np.clip(tt / 0.04, 0, 1) * np.exp(-tt / (d * 1.2)) * np.clip((d + 0.25 - tt) / 0.2, 0, 1)
        wrap_add(out, x, b * bar + bt * beat, 0.55)
    for b in range(10):                                               # oom-pah-pah
        root = (0, 7, 3, -2, 0, 8, 5, 0, -4, -5)[b]
        for bt, ks, g in ((0, (root - 12,), 0.6), (1, (root, root + 3 + (1 if root in (3, 8, -4) else 0), root + 7), 0.22),
                          (2, (root, root + 3 + (1 if root in (3, 8, -4) else 0), root + 7), 0.2)):
            for k in ks:
                m = secs(0.5)
                tt = np.arange(m) / SR
                x = np.sin(2 * np.pi * semis(k) * tt) * np.exp(-tt / 0.16) * np.clip(tt / 0.01, 0, 1)
                wrap_add(out, x, b * bar + bt * beat, g)
    out = cband(out, 420, 2900, 2)                                      # a three-inch speaker
    out = np.tanh(out * 1.6)
    hiss = cnoise(n, rng, 1200, 6000, 1) * 0.07 * (0.7 + 0.3 * lfo(n, rng, (3, 7), 1.0))
    crackle = np.zeros(n)
    for i in range(170):
        m = secs(rng.uniform(0.0006, 0.003))
        wrap_add(crackle, rng.standard_normal(m) * np.hanning(m), rng.uniform(0, dur), rng.uniform(0.1, 0.5))
    fadeout = 0.75 + 0.25 * lfo(n, rng, (2, 5), 1.0)                       # the station drifts
    return out * 0.6 * fadeout + hiss + cband(crackle, 800, 7000, 1)


# ----------------------------------------------------------------------------------------------- objects
def clink(rng, lo=1800, hi=6500, dur=0.07):
    fs = [rng.uniform(lo, hi) for _ in range(4)]
    x = ring(fs, dur, [1, 0.7, 0.5, 0.3], [dur * 0.7, dur * 0.5, dur * 0.4, dur * 0.3])
    x += 0.5 * bp(rng.standard_normal(len(x)), 2500, 9000, 1) * env_exp(len(x), 0.008, 0.0002)
    return x * np.clip(np.arange(len(x)) / SR / 0.0006, 0, 1)


def chain(seed):
    rng = np.random.default_rng(seed)
    n = secs(1.3)
    out = np.zeros(n)
    for i in range(22):
        u = rng.random() ** 1.4
        place(out, clink(rng, 1500, 5200, rng.uniform(0.03, 0.09)), u * 1.0, (1.0 - 0.6 * u) * rng.uniform(0.3, 1.0))
    place(out, thump(rng, 160, 80, 0.12, 0.5), 0.02, 0.5)                 # the gate knocks against its stop
    return fade(air(out, seed, 0.15, 0.5)[:n], 0.0005, 0.15)


def cut():
    rng = np.random.default_rng(410)
    n = secs(1.7)
    out = np.zeros(n)
    snap = bp(rng.standard_normal(secs(0.05)), 900, 8000, 1) * env_exp(secs(0.05), 0.02, 0.0003)
    place(out, snap, 0.0, 1.0)
    place(out, ring([2950, 4410, 6100], 0.5, [1, 0.6, 0.3], [0.35, 0.2, 0.12]), 0.002, 0.5)
    place(out, thump(rng, 220, 90, 0.08, 0.4), 0.0, 0.6)
    for i in range(26):                                               # the chain runs through the bars and drops
        u = rng.random()
        place(out, clink(rng, 1400, 5000, 0.05), 0.12 + u * 0.75, (1.0 - 0.5 * u) * rng.uniform(0.3, 0.8))
    place(out, thump(rng, 110, 55, 0.14, 0.7), 0.9, 0.8)
    for i in range(8):
        place(out, clink(rng, 1600, 4500, 0.04), 0.92 + rng.random() * 0.25, rng.uniform(0.2, 0.5))
    return fade(air(out, 411, 0.2, 0.7)[:n], 0.0003, 0.2)


def creak(seed, dur, f_lo, f_hi, rough=0.5):
    """Stick-slip groan: a harsh tone whose pitch wanders, broken by drop-outs."""
    rng = np.random.default_rng(seed)
    n = secs(dur)
    t = np.arange(n) / SR
    wander = lp(rng.standard_normal(n + SR), 3.0, 2)[SR:]
    wander = (wander - wander.min()) / (wander.max() - wander.min() + 1e-9)
    f = f_lo + (f_hi - f_lo) * wander
    ph = 2 * np.pi * np.cumsum(f * (1.0 + rough * 0.05 * lp(rng.standard_normal(n), 200, 1))) / SR
    x = sum(np.sin(h * ph) / h ** 0.7 for h in range(1, 12))
    gate = np.clip((lp(rng.standard_normal(n + SR), 9.0, 2)[SR:] * 6 + 0.5), 0, 1)
    e = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 0.6
    return x * gate * e


def gate():
    rng = np.random.default_rng(420)
    x = bp(creak(421, 2.7, 260, 620, 1.0), 300, 5200, 1)
    x += 0.6 * bp(creak(422, 2.7, 900, 1700, 0.6), 800, 6000, 1)
    n = len(x)
    out = np.tanh(x * 0.5)
    drag = lp(rng.standard_normal(n), 500, 2) * np.sin(np.pi * np.arange(n) / n) ** 0.5       # the foot of the leaf through the gravel
    out = out + 0.35 * drag / (np.std(drag) + 1e-9) * 0.2 + 0.25 * grains(n, rng, 200, 1500, 8000, (0.002, 0.008), lambda u: 1.0)
    return fade(air(out, 423, 0.2, 0.9)[:n + secs(0.4)], 0.01, 0.3)


def trap_open():
    rng = np.random.default_rng(430)
    n = secs(2.2)
    out = np.zeros(n)
    place(out, bp(creak(431, 1.2, 110, 260, 1.0), 90, 2600, 1), 0.0, 0.5)
    place(out, bp(creak(432, 1.1, 300, 520, 0.6), 250, 4000, 1), 0.1, 0.18)
    for at, g in ((1.25, 1.0), (1.42, 0.8)):                              # the two leaves fall back on the grass
        place(out, thump(rng, 95, 48, 0.3, 0.8), at, g)
        place(out, bp(rng.standard_normal(secs(0.05)), 300, 3000, 1) * env_exp(secs(0.05), 0.03, 0.0005), at, g * 0.5)
    return fade(air(np.tanh(out * 0.9), 433, 0.2, 0.6)[:n], 0.01, 0.2)


def trap_slam():
    rng = np.random.default_rng(440)
    n = secs(1.6)
    out = np.zeros(n)
    for at, g in ((0.0, 1.0), (0.11, 0.9)):
        place(out, thump(rng, 85, 38, 0.5, 1.0), at, g)
        place(out, bp(rng.standard_normal(secs(0.09)), 200, 5000, 1) * env_exp(secs(0.09), 0.05, 0.0004), at, g * 0.9)
        place(out, ring([212, 337, 508, 771], 0.4, [1, 0.7, 0.5, 0.3], [0.3, 0.22, 0.15, 0.1]), at + 0.002, g * 0.4)
    for i in range(6):                                                  # the hasp jumps
        place(out, clink(rng, 1800, 5000, 0.04), 0.13 + rng.random() * 0.2, rng.uniform(0.15, 0.35))
    # heard from below: the cellar answers
    return fade(air(np.tanh(out * 1.2), 441, 0.6, 1.1)[:n], 0.0003, 0.3)


def pot(seed):
    rng = np.random.default_rng(seed)
    n = secs(0.5)
    t = np.arange(n) / SR
    scrape = bp(rng.standard_normal(n), 1200, 4800, 1) * np.exp(-((t - 0.12) / 0.09) ** 2) * (0.4 + 0.6 * np.abs(lp(rng.standard_normal(n), 90, 2)) * 9)
    out = 0.6 * scrape
    f = rng.uniform(1500, 2100)
    place(out, ring([f, f * 2.3, f * 3.9], 0.14, [1, 0.5, 0.25], [0.09, 0.05, 0.03]), 0.3, 0.6)       # set down on its rim
    place(out, thump(rng, 300, 180, 0.04, 0.3), 0.3, 0.4)
    return fade(out, 0.005, 0.08)


def glass_bang():
    rng = np.random.default_rng(460)
    n = secs(1.3)
    out = np.zeros(n)
    for at, g in ((0.0, 1.0), (0.16, 0.85)):
        place(out, thump(rng, 260, 120, 0.1, 0.8), at, g)
        place(out, bp(rng.standard_normal(secs(0.03)), 600, 5000, 1) * env_exp(secs(0.03), 0.012, 0.0003), at, g * 0.8)
        place(out, ring([1130, 2310, 3740, 5120], 0.45, [1, 0.6, 0.4, 0.2], [0.35, 0.22, 0.14, 0.08]), at + 0.001, g * 0.3)
        m = secs(0.35)
        tt = np.arange(m) / SR
        buzz = np.sign(np.sin(2 * np.pi * 86 * tt)) * bp(rng.standard_normal(m), 1500, 6000, 1) * np.exp(-tt / 0.09)       # the pane in its putty
        place(out, buzz, at + 0.01, g * 0.25)
    return fade(air(np.tanh(out * 1.1), 461, 0.2, 0.5)[:n], 0.0003, 0.2)


def stone_hard(seed):
    rng = np.random.default_rng(seed)
    n = secs(0.8)
    out = np.zeros(n)
    at = 0.0
    gap = rng.uniform(0.11, 0.17)
    g = 1.0
    for i in range(4):
        m = secs(0.03)
        click = bp(rng.standard_normal(m), 1500, 9000, 1) * env_exp(m, 0.008, 0.0002)
        click += 0.8 * ring([rng.uniform(2200, 3200), rng.uniform(3800, 5200)], 0.03, [1, 0.6], [0.012, 0.008])
        place(out, click, at, g)
        place(out, grains(secs(0.06), rng, 14, 1500, 8000), at, g * 0.5)
        at += gap
        gap *= 0.55
        g *= 0.5
    return fade(air(out, seed, 0.15, 0.4)[:n], 0.0002, 0.1)


def stone_soft(seed):
    rng = np.random.default_rng(seed)
    n = secs(0.6)
    out = np.zeros(n)
    place(out, thump(rng, 170, 70, 0.1, 0.7), 0.0, 1.0)
    place(out, grains(secs(0.3), rng, 60, 1500, 8000, (0.003, 0.012), lambda u: (1 - u) ** 2), 0.005, 0.5)
    place(out, thump(rng, 140, 70, 0.07, 0.5), rng.uniform(0.13, 0.2), 0.3)
    return fade(out, 0.0005, 0.12)


def swing():
    rng = np.random.default_rng(480)
    dur = 8.5
    n = secs(dur)
    out = np.zeros(n)
    half = 1.33                                                        # half a period of a 1.75 m pendulum
    k = 0
    at = 0.05
    while at < dur - 0.6:
        up = k % 2 == 0
        d = rng.uniform(0.28, 0.4)
        m = secs(d)
        tt = np.arange(m) / SR
        f0, f1 = (880, 1340) if up else (1260, 820)
        f = f0 + (f1 - f0) * (tt / d) + 30 * lp(rng.standard_normal(m), 40, 1)
        ph = 2 * np.pi * np.cumsum(f) / SR
        x = (np.sin(ph) + 0.5 * np.sin(2 * ph) + 0.3 * np.sin(3.01 * ph)) * np.sin(np.pi * tt / d) ** 1.2
        x *= 0.5 + 0.5 * (lp(rng.standard_normal(m), 60, 1) * 10 > -0.4)
        place(out, bp(x, 600, 6000, 1), at, (1.0 - 0.75 * at / dur) * rng.uniform(0.7, 1.0))
        place(out, clink(rng, 1500, 4000, 0.03), at + d * rng.uniform(0.2, 0.8), 0.15 * (1.0 - 0.7 * at / dur))
        at += half + rng.uniform(-0.03, 0.03)
        k += 1
    return fade(air(out, 481, 0.15, 0.6)[:n], 0.005, 0.5)


def lantern():
    rng = np.random.default_rng(490)
    dur = 2.5
    n = secs(dur)
    out = np.zeros(n)
    for at, f0, f1, g in ((0.1, 2050, 2400, 1.0), (1.32, 2500, 2150, 0.8)):
        d = 0.09
        m = secs(d)
        tt = np.arange(m) / SR
        f = f0 + (f1 - f0) * tt / d
        ph = 2 * np.pi * np.cumsum(f) / SR
        x = (np.sin(ph) + 0.4 * np.sin(2.02 * ph)) * np.sin(np.pi * tt / d) ** 1.5
        wrap_add(out, x, at, g)
        wrap_add(out, clink(rng, 3000, 7000, 0.02), at + 0.11, 0.25 * g)
    return out


# ----------------------------------------------------------------------------------------------- main
def many(fn, seeds, **kw):
    return [(lambda s=s: fn(s, **kw)) for s in seeds]


JOBS = [  # name, [fn...], loop, gainDb
    ("footstep_grass", many(step_grass, (11, 12, 13, 14, 15)), False, -7),
    ("footstep_gravel", many(step_gravel, (21, 22, 23, 24, 25)), False, -2),
    ("footstep_leaves", many(step_leaves, (31, 32, 33, 34, 35)), False, -3),
    ("dh_her_grass", many(step_grass, (41, 42, 43, 44), heavy=True), False, -2),
    ("dh_her_gravel", many(step_gravel, (51, 52, 53, 54), heavy=True), False, 0),
    ("dh_her_leaves", many(step_leaves, (61, 62, 63, 64), heavy=True), False, 0),
    ("dh_lantern", [lantern], True, -8),
    ("dh_wind", [wind], True, -6),
    ("dh_theme", [theme], True, -6),
    ("dh_owl", many(owl, (71, 72)), False, -8),
    ("dh_twig", many(twig, (81, 82, 83)), False, -4),
    ("dh_gust", many(gust, (91, 92)), False, -6),
    ("dh_chimes", [chimes], False, 0),
    ("dh_horn", [horn], False, 0),
    ("dh_horn_dead", [horn_dead], False, -4),
    ("dh_radio", [radio], True, -2),
    ("dh_chain", many(chain, (401, 402)), False, -2),
    ("dh_cut", [cut], False, 0),
    ("dh_gate", [gate], False, 0),
    ("dh_trap_open", [trap_open], False, 0),
    ("dh_trap_slam", [trap_slam], False, 2),
    ("dh_pot", many(pot, (451, 452, 453)), False, -4),
    ("dh_glass_bang", [glass_bang], False, 2),
    ("dh_stone_hard", many(stone_hard, (471, 472, 473)), False, 0),
    ("dh_stone_soft", many(stone_soft, (476, 477)), False, -2),
    ("dh_swing", [swing], False, -2),
]


def write_ogg(path, x):
    pcm = (np.clip(x, -1, 1) * 32767.0).astype("<i2").tobytes()
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", "1", "-i", "-", "-c:a", "libvorbis",
                    "-q:a", "5", path], input=pcm, check=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    only = set(filter(None, a.only.split(",")))
    os.makedirs(OUT, exist_ok=True)
    man = {}
    if os.path.exists(MANIFEST):
        with open(MANIFEST, encoding="utf-8") as fh:
            man = json.load(fh)
    for name, fns, loop, gain in JOBS:
        rels = []
        for i, fn in enumerate(fns):
            stem = name if len(fns) == 1 else "%s_%d" % (name, i + 1)
            path = os.path.join(OUT, stem + ".ogg")
            rels.append("assets/audio/dehors/" + stem + ".ogg")
            if only and name not in only:
                continue
            x = normalize(fn(), -3.0)
            write_ogg(path, x)
            print("  %-24s %6.2f s  %7.1f KiB  %s" % (stem + ".ogg", len(x) / SR, os.path.getsize(path) / 1024.0, "loop" if loop else ""))
        man[name] = {"files": rels, "loop": loop, "gainDb": gain}
    with open(MANIFEST, "w", encoding="utf-8") as fh:
        fh.write(json.dumps(man, indent=1, ensure_ascii=False) + "\n")
    print("  manifest: %d entries" % len(man))


if __name__ == "__main__":
    main()
