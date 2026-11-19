#!/usr/bin/env python3
"""Synthesizes the sounds of the rooms added to "L'etage" (kitchen, pantry, bathroom, stairwell). Everything is
generated from scratch (numpy / scipy), nothing recorded. Deterministic (fixed seeds).

    python3 -I pc/scripts/etage/tools/gen_etage2_sounds.py [--out DIR] [--only name,name]

Writes mono 44.1 kHz MP3 (ffmpeg + libmp3lame, 160 kbps, peak -3 dBFS) into pc/assets/audio/etage/. The manifest
entries (pc/assets/audio/manifest.json) and the definitions (pc/scripts/audio/sound_defs.gd) are added by hand; then
run `godot --headless --path pc --import` once so Godot writes the .mp3.import sidecars.

  tap_run          4.0 s  seamless loop: water from an old tap into an enamel basin (hiss, body, gurgle)
  fridge_hum       4.0 s  seamless loop: the compressor of an old refrigerator (50 Hz and harmonics, a rattle)
  furniture_drag   2.6 s  a heavy dresser pushed across linoleum: stick-slip groans, the feet juddering
  curtain_rings    1.0 s  metal rings sliding along a rail, the cloth after them
  pipe_knock       2.2 s  three blows on a water pipe somewhere in the wall, ringing
"""
import argparse
import os
import subprocess

import numpy as np
from scipy import signal

SR = 44100
HERE = os.path.dirname(os.path.abspath(__file__))
PC = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
DEFAULT_OUT = os.path.join(PC, "assets", "audio", "etage")


def secs(d):
    return int(round(d * SR))


def bp(x, lo, hi, order=2):
    return signal.sosfilt(signal.butter(order, [lo, hi], btype="band", fs=SR, output="sos"), x)


def lp(x, hz, order=2):
    return signal.sosfilt(signal.butter(order, hz, btype="low", fs=SR, output="sos"), x)


def hp(x, hz, order=2):
    return signal.sosfilt(signal.butter(order, hz, btype="high", fs=SR, output="sos"), x)


def cband(x, lo=None, hi=None, order=2):
    """Zero-phase circular (loop-periodic) band filter, done in the frequency domain."""
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


def place(buf, x, at):
    i = secs(at)
    n = min(len(x), len(buf) - i)
    if n > 0 and i >= 0:
        buf[i:i + n] += x[:n]


def fade(x, t_in=0.004, t_out=0.05):
    x = x.copy()
    a, b = secs(t_in), secs(t_out)
    x[:a] *= np.linspace(0, 1, a)
    x[-b:] *= np.linspace(1, 0, b) ** 2
    return x


def normalize(x, peak_db=-3.0):
    return x * (10 ** (peak_db / 20.0) / (np.max(np.abs(x)) + 1e-12))


def write_mp3(path, x):
    pcm = np.clip(np.asarray(x, np.float64), -1.0, 1.0).astype("<f4").tobytes()
    cmd = ["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "-", "-map_metadata", "-1",
           "-fflags", "+bitexact", "-flags:a", "+bitexact", "-c:a", "libmp3lame", "-b:a", "160k", path]
    subprocess.run(cmd, input=pcm, check=True)


def tap_run():
    n = secs(4.0)
    rng = np.random.default_rng(101)
    t = np.arange(n) / SR
    hiss = cnoise(n, rng, 2200, 9000) * 0.5
    body = cnoise(n, rng, 350, 1500) * 0.55
    # the stream wavers a little (periodic over the loop)
    wob = 1.0 + 0.18 * np.sin(2 * np.pi * 3 * t / 4.0 + 1.0) + 0.1 * np.sin(2 * np.pi * 7 * t / 4.0)
    x = (hiss + body) * wob
    # gurgle in the drain: short resonant blips at random, wrapped round the loop
    for _ in range(46):
        f0 = rng.uniform(280, 820)
        d = rng.uniform(0.03, 0.09)
        k = secs(d)
        tt = np.arange(k) / SR
        blip = np.sin(2 * np.pi * (f0 + 500 * tt) * tt) * np.exp(-tt / (d * 0.3)) * rng.uniform(0.25, 0.7)
        idx = (rng.integers(0, n) + np.arange(k)) % n
        np.add.at(x, idx, blip)
    return x


def fridge_hum():
    n = secs(4.0)
    rng = np.random.default_rng(102)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for h, a in [(1, 1.0), (2, 0.6), (3, 0.28), (4, 0.2), (6, 0.1), (8, 0.05)]:
        x += a * np.sin(2 * np.pi * 50.0 * h * t + rng.uniform(0, 6.28))
    x *= 1.0 + 0.06 * np.sin(2 * np.pi * 1.0 * t)           # 1 Hz beat: exact over 4 s
    x += cnoise(n, rng, 90, 600) * 0.16
    # a loose panel rattling at 25 Hz
    rat = cnoise(n, rng, 1200, 3800) * (np.maximum(0.0, np.sin(2 * np.pi * 25.0 * t)) ** 8) * 0.12
    return x + rat


def furniture_drag():
    n = secs(2.6)
    rng = np.random.default_rng(103)
    t = np.arange(n) / SR
    env = np.interp(t, [0, 0.08, 0.5, 1.9, 2.3, 2.6], [0, 1.0, 0.8, 0.9, 0.5, 0.0])
    # stick-slip: a sawtooth whose rate wanders between 28 and 60 Hz, through the body of the furniture
    rate = 40 + 16 * np.sin(2 * np.pi * 0.7 * t) + 8 * lp(rng.standard_normal(n), 3.0) * 30
    ph = np.cumsum(np.clip(rate, 22, 70)) / SR
    saw = 2.0 * (ph % 1.0) - 1.0
    groan = bp(saw, 70, 900) * 0.9 + bp(saw, 900, 2600) * 0.25
    scrape = bp(rng.standard_normal(n), 500, 4200) * 0.3 * (0.6 + 0.4 * np.abs(saw))
    x = (groan + scrape) * env
    # the feet catching on the joints of the lino
    for at in [0.32, 0.81, 1.22, 1.74, 2.12]:
        k = secs(0.16)
        tt = np.arange(k) / SR
        thud = (np.sin(2 * np.pi * 82 * tt) + 0.5 * np.sin(2 * np.pi * 131 * tt)) * np.exp(-tt / 0.035) + bp(rng.standard_normal(k), 300, 1800) * np.exp(-tt / 0.012) * 0.6
        place(x, thud * 0.9, at)
    # things rattling inside (plates)
    for _ in range(26):
        k = secs(0.05)
        tt = np.arange(k) / SR
        f0 = rng.uniform(2100, 5200)
        c = np.sin(2 * np.pi * f0 * tt) * np.exp(-tt / 0.012) * rng.uniform(0.04, 0.16)
        place(x, c, rng.uniform(0.1, 2.2))
    return fade(x, 0.01, 0.2)


def curtain_rings():
    n = secs(1.05)
    rng = np.random.default_rng(104)
    x = np.zeros(n)
    # a dozen rings, each a short bright scrape then a click against its neighbour
    for i in range(12):
        at = 0.04 + i * 0.05 + rng.uniform(-0.012, 0.012)
        k = secs(0.09)
        tt = np.arange(k) / SR
        f0 = rng.uniform(3200, 6400)
        ring = (np.sin(2 * np.pi * f0 * tt) + 0.6 * np.sin(2 * np.pi * f0 * 1.52 * tt)) * np.exp(-tt / 0.02) * rng.uniform(0.3, 0.6)
        place(x, ring, at)
    t = np.arange(n) / SR
    scrape = bp(rng.standard_normal(n), 2500, 8000) * np.interp(t, [0, 0.05, 0.6, 0.75, 1.05], [0, 0.5, 0.45, 0.1, 0.0])
    cloth = bp(rng.standard_normal(n), 300, 2400) * np.interp(t, [0, 0.1, 0.7, 1.05], [0, 0.35, 0.3, 0.0])
    return fade(x + scrape * 0.5 + cloth * 0.6, 0.004, 0.15)


def pipe_knock():
    n = secs(2.2)
    rng = np.random.default_rng(105)
    x = np.zeros(n)
    modes = [(212, 0.5, 1.0), (467, 0.34, 0.7), (743, 0.25, 0.5), (1181, 0.14, 0.4), (1870, 0.09, 0.25), (2790, 0.05, 0.14)]
    for at, amp in [(0.05, 1.0), (0.5, 0.82), (0.95, 0.9)]:
        k = secs(1.1)
        tt = np.arange(k) / SR
        hit = np.zeros(k)
        for f0, tau, a in modes:
            hit += a * np.sin(2 * np.pi * f0 * (1.0 + rng.uniform(-0.01, 0.01)) * tt) * np.exp(-tt / tau)
        hit += bp(rng.standard_normal(k), 400, 3000) * np.exp(-tt / 0.006) * 1.2
        place(x, hit * amp, at)
    # heard through a wall
    x = lp(x, 2600, 2) + 0.2 * x
    return fade(x, 0.002, 0.3)


JOBS = [("tap_run", tap_run), ("fridge_hum", fridge_hum), ("furniture_drag", furniture_drag), ("curtain_rings", curtain_rings),
        ("pipe_knock", pipe_knock)]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    only = set(filter(None, a.only.split(",")))
    os.makedirs(a.out, exist_ok=True)
    for name, fn in JOBS:
        if only and name not in only:
            continue
        x = normalize(fn(), -3.0)
        path = os.path.join(a.out, name + ".mp3")
        write_mp3(path, x)
        print("  %-20s %5.2f s  %6.1f KiB" % (name + ".mp3", len(x) / SR, os.path.getsize(path) / 1024.0))


if __name__ == "__main__":
    main()
