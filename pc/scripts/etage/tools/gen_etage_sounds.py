#!/usr/bin/env python3
"""Synthesizes the music and sounds of the level "L'etage" (old wooden house at night). Everything is generated from
scratch (numpy / scipy), nothing recorded, no existing melody. Deterministic (fixed seeds).

    python3 -I pc/scripts/etage/tools/gen_etage_sounds.py [--out DIR] [--no-manifest] [--only name,name]

Writes mono 44.1 kHz MP3 (ffmpeg + libmp3lame, 160 kbps, peak -3 dBFS) into pc/assets/audio/etage/ and adds / refreshes
its own entries in pc/assets/audio/manifest.json (other entries are left untouched, same formatting). Then run
`godot --headless --path pc --import` once so Godot writes the .mp3.import sidecars.

  etage_theme        72 s   seamless loop: low detuned drone (55 Hz + fifth), far-apart soft piano-like notes / intervals
  dread_layer        40 s   seamless loop: bowed cluster 180-420 Hz, 40 Hz heartbeat pulse every 1.6 s, bowed-metal shimmer
  piano_sting_1..3   ~6 s   one low dissonant cluster struck on an out-of-tune upright piano
  floor_creak_long_1..3  1.35-1.98 s  slow, low floorboard creak under a heavy step (stick-slip groan + wood knocks)
The two loops are built periodic (every component repeats exactly over the loop, tails are wrapped into the head), so the
last sample runs into the first without a click.
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
DEFAULT_OUT = os.path.join(PC, "assets", "audio", "etage")
MANIFEST = os.path.join(PC, "assets", "audio", "manifest.json")


# ----------------------------------------------------------------------------------------------- helpers
def secs(d):
    return int(round(d * SR))


def bp(x, lo, hi, order=2):
    sos = signal.butter(order, [lo, hi], btype="band", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def lp(x, hz, order=2):
    return signal.sosfilt(signal.butter(order, hz, btype="low", fs=SR, output="sos"), x)


def hp(x, hz, order=2):
    return signal.sosfilt(signal.butter(order, hz, btype="high", fs=SR, output="sos"), x)


def peak(x, hz, q, gain=1.0):
    b, a = signal.iirpeak(hz, q, fs=SR)
    return signal.lfilter(b, a, x) * gain


def place(buf, x, at):
    i = secs(at)
    n = min(len(x), len(buf) - i)
    if n > 0 and i >= 0:
        buf[i:i + n] += x[:n]


def wrap_add(buf, x, at):
    """Adds x at time `at`; what runs past the end comes back in at the start (loop-periodic)."""
    idx = (secs(at) + np.arange(len(x))) % len(buf)
    np.add.at(buf, idx, x)


def smooth_noise(n, hz, rng):
    """Low-passed noise, roughly unit variance."""
    x = lp(rng.standard_normal(n + SR), hz, 2)[SR:]
    return x / (np.std(x) + 1e-9)


def curve(points, n):
    """Smooth interpolation of (time, value) breakpoints over n samples."""
    t = np.arange(n) / SR
    ts = np.array([p[0] for p in points])
    vs = np.array([p[1] for p in points])
    y = np.interp(t, ts, vs)
    k = max(3, secs(0.03) | 1)
    return np.convolve(np.pad(y, k // 2, mode="edge"), np.hanning(k) / np.hanning(k).sum(), mode="valid")[:n]


def cband(x, lo=None, hi=None, order=2):
    """Zero-phase circular (loop-periodic) Butterworth-shaped band filter, done in the frequency domain."""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    g = np.ones_like(f)
    if lo:
        g *= 1.0 / np.sqrt(1.0 + (lo / np.maximum(f, 1e-9)) ** (2 * order))
    if hi:
        g *= 1.0 / np.sqrt(1.0 + (f / hi) ** (2 * order))
    return np.fft.irfft(X * g, len(x))


def cnoise(n, rng, lo=None, hi=None, order=2):
    """Loop-periodic band noise, unit variance."""
    x = cband(rng.standard_normal(n), lo, hi, order)
    x -= np.mean(x)
    return x / (np.std(x) + 1e-12)


def cconv(x, ir):
    """Circular convolution (a reverb whose tail wraps round the loop)."""
    return np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(ir, len(x)), len(x))


def room_ir(rt60, seed, lo=200.0, hi=9000.0, early=((0.0061, 0.45), (0.0113, 0.34), (0.0187, 0.27), (0.0271, 0.2))):
    rng = np.random.default_rng(seed)
    n = secs(rt60 * 1.25)
    t = np.arange(n) / SR
    tail = bp(rng.standard_normal(n), lo, hi, 1) * np.exp(-6.91 * t / rt60)
    tail *= np.clip(t / 0.012, 0, 1)
    tail /= np.sqrt(np.sum(tail ** 2))
    ir = tail * 0.9
    for dt, g in early:
        ir[secs(dt)] += g * (1 if rng.random() < 0.5 else -1)
    return ir


def reverb(x, ir, mix, tail=True):
    wet = signal.fftconvolve(x, ir)
    out = np.zeros(len(wet) if tail else len(x))
    out[:len(x)] += x
    out += mix * wet[:len(out)]
    return out


def fade(x, t_in=0.002, t_out=0.03):
    x = x.copy()
    a, b = secs(t_in), secs(t_out)
    if a > 0:
        x[:a] *= np.linspace(0, 1, a)
    if b > 0:
        x[-b:] *= np.linspace(1, 0, b) ** 2
    return x


def normalize(x, peak_db=-3.0):
    return x * (10 ** (peak_db / 20.0) / (np.max(np.abs(x)) + 1e-12))


def write_mp3(path, x):
    pcm = np.clip(np.asarray(x, np.float64), -1.0, 1.0).astype("<f4").tobytes()
    cmd = ["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "-", "-map_metadata", "-1",
           "-fflags", "+bitexact", "-flags:a", "+bitexact", "-c:a", "libmp3lame", "-b:a", "160k", path]
    subprocess.run(cmd, input=pcm, check=True)


def midi(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


# ----------------------------------------------------------------------------------------------- piano string model
def piano_tone(f0, dur, rng, B=1.5e-4, strings=(-2.0, 2.5), fmax=3000.0, hammer_fc=1400.0, tau0=2.2, tau_f=900.0,
               strike=0.125, attack=0.006, pitch_int=None, slope=0.7):
    """One struck note: stiff-string (inharmonic) partials f_n = n f0 sqrt(1 + B n^2), two or three strings a few cents
    apart (beating), hammer comb + low-pass spectrum, two-stage decay, higher partials die faster.
    pitch_int = running integral of the tape-speed factor (seconds), for wow; default = plain time."""
    n = secs(dur)
    t = np.arange(n) / SR
    ti = t if pitch_int is None else pitch_int[:n]
    y = np.zeros(n)
    for cents in strings:
        fs = f0 * 2.0 ** (cents / 1200.0)
        k = 1
        while True:
            fk = k * fs * np.sqrt(1.0 + B * k * k)
            if fk > fmax:
                break
            a = k ** (-slope) * (0.22 + abs(np.sin(np.pi * k * strike))) * np.exp(-fk / hammer_fc)
            tau = tau0 / (1.0 + (fk / tau_f) ** 1.25)
            env = 0.6 * np.exp(-t / (tau * 0.33)) + 0.4 * np.exp(-t / tau)
            y += a * env * np.sin(2 * np.pi * fk * ti + rng.uniform(0, 2 * np.pi))
            k += 1
    y *= 1.0 - np.exp(-t / attack)
    return y / len(strings)


# ----------------------------------------------------------------------------------------------- etage_theme (72 s loop)
def etage_theme():
    rng = np.random.default_rng(7201)
    L = 72.0
    n = secs(L)
    t = np.arange(n) / SR

    def per(f):                                 # nearest frequency that repeats exactly over the loop
        return round(f * L) / L

    # --- drone: two tones 0.14 Hz apart at 55 Hz, a third that drifts in at 57.9 Hz (rough beating), the fifth above
    drone = np.zeros(n)
    for f, a, k, ph in ((55.0, 1.0, 4, 0.3), (55.139, 0.62, 5, 2.1), (57.9, 0.40, 3, 4.0), (82.5, 0.50, 7, 1.1),
                        (82.74, 0.30, 5, 5.2), (110.2, 0.10, 6, 3.3)):
        f = per(f)
        breath = 0.72 + 0.28 * np.sin(2 * np.pi * k * t / L + ph)
        if f > 57 and f < 58:
            breath = np.clip(np.sin(2 * np.pi * k * t / L + ph), 0, 1) ** 2          # only now and then
        p0 = rng.uniform(0, 2 * np.pi)
        tone = np.sin(2 * np.pi * f * t + p0) + 0.22 * np.sin(2 * np.pi * 2 * f * t + 1.7 * p0) \
            + 0.08 * np.sin(2 * np.pi * 3 * f * t + 0.6 * p0)
        drone += a * breath * tone
    drone *= 0.86 + 0.14 * np.sin(2 * np.pi * 2 * t / L + 0.9)                      # the whole bed breathes, 36 s
    air = cnoise(n, rng, 90, 420, 2) * (0.5 + 0.5 * cnoise(n, rng, None, 0.25, 2).clip(-1, 1))
    drone = drone / np.max(np.abs(drone)) * 0.34 + air * 0.006

    # --- tape wow (periodic over the loop): speed factor and its running integral
    speed = 1.0 + 0.0024 * np.sin(2 * np.pi * 31 * t / L) + 0.0011 * np.sin(2 * np.pi * 53 * t / L + 1.0) \
        + 0.0004 * np.sin(2 * np.pi * 468 * t / L + 2.0)

    # --- far-apart single notes / two-note intervals (minor seconds, tritones); no pulse, no tune
    A = midi
    events = [  # time, [(midi, delay, velocity)]
        (4.0, [(64, 0.0, 0.80)]),                           # E4
        (13.5, [(57, 0.0, 0.75), (58, 0.62, 0.60)]),        # A3 + Bb3  minor second
        (24.0, [(72, 0.0, 0.55)]),                          # C5
        (31.5, [(63, 0.0, 0.70), (69, 0.85, 0.60)]),        # Eb4 + A4  tritone
        (43.0, [(53, 0.0, 0.85)]),                          # F3
        (52.0, [(76, 0.0, 0.45), (77, 0.50, 0.40)]),        # E5 + F5   minor second
        (63.5, [(47, 0.0, 0.80), (53, 1.10, 0.65)]),        # B2 + F3   tritone
    ]
    notes = np.zeros(n)
    for t0, chord in events:
        for m, dl, vel in chord:
            f0 = A(m)
            dur = 13.0
            i0 = secs(t0 + dl)
            idx = (i0 + np.arange(secs(dur))) % n
            pint = np.cumsum(speed[idx]) / SR
            B = 1.2e-4 * max(1.0, f0 / 130.0) ** 1.3
            y = piano_tone(f0, dur, rng, B=B, strings=(-3.0, 1.5, 4.0) if m > 55 else (-2.5, 3.0), fmax=3400.0,
                           hammer_fc=700.0 + 500.0 * vel, tau0=3.4, tau_f=700.0, attack=0.010, pitch_int=pint)
            y *= vel * (f0 / 262.0) ** -0.25
            wrap_add(notes, fade(y, 0.0, 2.5), t0 + dl)
    notes = cband(notes, 70, 2600, 1)                                               # soft, far away
    ir = room_ir(4.2, 7202, 120, 3200, early=((0.019, 0.3), (0.037, 0.25), (0.061, 0.2), (0.089, 0.15)))
    notes = notes * 0.75 + cconv(notes, ir) * 0.55
    notes = notes / np.max(np.abs(notes)) * 0.42
    return drone + notes


# ----------------------------------------------------------------------------------------------- dread_layer (40 s loop)
def dread_layer():
    rng = np.random.default_rng(4001)
    L = 40.0
    n = secs(L)
    t = np.arange(n) / SR
    # --- bowed-string cluster: 10 saw-like voices, each gliding +-30 cents, own slow tremolo, bow jitter
    f0s = [183.0, 199.0, 217.0, 236.0, 258.0, 281.0, 307.0, 335.0, 367.0, 403.0]
    cluster = np.zeros(n)
    for v, f0 in enumerate(f0s):
        k1, k2 = rng.integers(1, 4), rng.integers(3, 7)
        cents = 30.0 * (0.65 * np.sin(2 * np.pi * k1 * t / L + rng.uniform(0, 6.28))
                        + 0.35 * np.sin(2 * np.pi * k2 * t / L + rng.uniform(0, 6.28)))
        f = f0 * 2.0 ** (cents / 1200.0)
        cyc = np.sum(f) / SR
        f *= round(cyc) / cyc                                                       # whole number of cycles per loop
        ph = 2 * np.pi * np.cumsum(f) / SR
        ph += 0.10 * cnoise(n, rng, None, 45.0, 1) + 0.03 * cnoise(n, rng, 200.0, 1500.0, 1)   # rosin / bow noise
        x = np.zeros(n)
        h = 1
        while h * f0 * 1.02 < 5200.0:
            x += (1.0 / h) * (1.0 + 0.30 * np.sin(1.3 * h + v)) * np.sin(h * ph + 0.5 * h * h)
            h += 1
        kt = int(rng.integers(13, 62))                                              # tremolo 0.33-1.5 Hz
        trem = 1.0 - 0.50 * (0.5 + 0.5 * np.sin(2 * np.pi * kt * t / L + rng.uniform(0, 6.28)))
        trem *= 1.0 + 0.10 * cnoise(n, rng, None, 9.0, 1)
        cluster += x * trem * (0.85 + 0.3 * rng.random())
    body = cband(cluster, 190.0, 2600.0, 2)
    body = body + 0.9 * cband(cband(cluster, 430.0, 560.0, 2), 430.0, 560.0, 2) \
        + 0.7 * cband(cband(cluster, 1100.0, 1500.0, 2), 1100.0, 1500.0, 2)         # instrument body formants
    body += cnoise(n, rng, 400.0, 3000.0, 1) * np.std(body) * 0.05                  # bow hair hiss
    body /= np.std(body)

    # --- bowed metal: quiet shimmering inharmonic partials 2-4 kHz (beating pairs, slow random swells)
    metal = np.zeros(n)
    for _ in range(16):
        f = round(rng.uniform(2000.0, 4000.0) * L) / L
        df = round(rng.uniform(0.3, 2.2) * L) / L
        sw = np.clip(cnoise(n, rng, None, 0.35, 2) * 0.6 + 0.35, 0.0, None) ** 1.5
        sw *= 1.0 + 0.25 * np.sin(2 * np.pi * round(rng.uniform(3.0, 7.0) * L) / L * t + rng.uniform(0, 6.28))
        p0 = rng.uniform(0, 6.28)
        metal += sw * (np.sin(2 * np.pi * f * t + p0) + 0.8 * np.sin(2 * np.pi * (f + df) * t + 2 * p0)) * (2600.0 / f)
    metal += cband(cnoise(n, rng, 2000.0, 4000.0, 3), 2000.0, 4000.0, 3) * np.std(metal) * 0.25 \
        * (0.6 + 0.4 * cnoise(n, rng, None, 0.5, 2).clip(-1, 1))
    metal /= np.std(metal)

    # --- sub pulse: slow heartbeat (lub-dub) around 40 Hz every 1.6 s -> 25 beats per loop
    sub = np.zeros(n)
    m = secs(0.75)
    tt = np.arange(m) / SR
    for i in range(25):
        for dl, amp, fa, fb in ((0.0, 1.0, 47.0, 39.0), (0.31, 0.55, 44.0, 38.0)):
            fq = fb + (fa - fb) * np.exp(-tt / 0.07)
            env = (1.0 - np.exp(-tt / 0.010)) * np.exp(-tt / 0.15)
            beat = amp * env * np.sin(2 * np.pi * np.cumsum(fq) / SR)
            wrap_add(sub, fade(beat, 0.0, 0.15), i * 1.6 + 0.2 + dl)
    sub /= np.max(np.abs(sub))

    wet = body * 0.150 + metal * 0.016
    ir = room_ir(2.6, 4002, 150, 6000, early=((0.013, 0.35), (0.029, 0.28), (0.047, 0.2)))
    wet = wet * 0.8 + cconv(wet, ir) * 0.35
    return wet + sub * 0.50


# ----------------------------------------------------------------------------------------------- piano stings
def piano_sting(seed, notes):
    rng = np.random.default_rng(seed)
    dur = 6.2
    n = secs(dur)
    y = np.zeros(n + secs(0.05))
    for m in notes:
        f0 = midi(m) * 2.0 ** (rng.uniform(-19, 19) / 1200.0)                       # the whole piano has drifted
        d1, d2 = rng.uniform(-8, -2), rng.uniform(2, 9)                             # the two strings of the note
        tone = piano_tone(f0, dur, rng, B=3.6e-4 * rng.uniform(0.8, 1.25), strings=(d1, d2), fmax=6800.0,
                          hammer_fc=4200.0, tau0=1.45, tau_f=1100.0, strike=1.0 / 7.3, attack=0.0025, slope=0.35)
        place(y, tone * rng.uniform(0.8, 1.1), rng.uniform(0.0, 0.014))             # a fist: not quite together
    y = y[:n]
    # upright soundboard: weak below ~90 Hz, a few body resonances
    y = hp(y, 75.0, 1) + 0.9 * peak(y, 196.0, 5) + 0.7 * peak(y, 415.0, 6) + 0.45 * peak(y, 1120.0, 7) \
        + 0.25 * peak(y, 2500.0, 6)
    y /= np.max(np.abs(y))
    # hammer thump through the case, key-bed knock
    t = np.arange(n) / SR
    th = lp(rng.standard_normal(n), 170.0, 2) * np.exp(-t / 0.040) * 6.0
    for f, a, tau in ((61.0, 1.0, 0.11), (96.0, 0.8, 0.085), (143.0, 0.6, 0.07), (212.0, 0.4, 0.05)):
        th += a * np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28)) * np.exp(-t / tau)
    th *= 1.0 - np.exp(-t / 0.0015)
    th /= np.max(np.abs(th))
    clack = bp(rng.standard_normal(n), 700.0, 3200.0, 1) * np.exp(-t / 0.007)
    clack /= np.max(np.abs(clack))
    y = y + 0.45 * th + 0.10 * clack
    y = np.tanh(y * 1.25) / np.tanh(1.25)
    y = lp(y, 7200.0, 2)
    y = reverb(y, room_ir(1.0, seed + 1, 150, 6000), 0.16, tail=False)
    return fade(y[:n], 0.001, 0.9)


# ----------------------------------------------------------------------------------------------- long floor creaks
def knock(rng, modes, amp, bright=1.0):
    n = secs(0.40)
    t = np.arange(n) / SR
    y = np.zeros(n)
    for f, a, tau in modes:
        y += a * np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28)) * np.exp(-t / tau)
    y *= 1.0 - np.exp(-t / 0.002)
    y += lp(rng.standard_normal(n), 850.0, 2) * np.exp(-t / 0.013) * 2.2
    y += bp(rng.standard_normal(n), 1400.0, 5200.0, 1) * np.exp(-t / 0.004) * 0.5 * bright
    return amp * y / np.max(np.abs(y))


def floor_creak(seed, dur, fpts, epts, jumps, k_end):
    rng = np.random.default_rng(seed)
    n = secs(dur)
    f = curve(fpts, n)
    f *= 1.0 + 0.045 * smooth_noise(n, 5, rng) + 0.022 * smooth_noise(n, 70, rng)
    for tj, dj in jumps:                                                            # the board lets go: pitch jumps
        f[secs(tj):] *= dj
    f = np.clip(f, 90.0, 260.0)
    env = np.clip(curve(epts, n), 0, None)
    ph = 2 * np.pi * np.cumsum(f) / SR
    x = np.zeros(n)
    wob = smooth_noise(n, 3, rng) * 0.2
    for h in range(1, 60):
        a = 1.0 / h ** 0.85 * (1.0 + 0.5 * np.sin(h * 2.1 + seed))                  # pulse-like slip wave, rich harmonics
        x += a * np.sin(h * ph + 0.3 * h * wob) * (h * f < 9500.0)
    sub = np.clip(smooth_noise(n, 2.2, rng) * 0.9, 0, 1)                            # period-doubling episodes
    for h in (1, 3, 5):
        x += 0.5 * sub / h * np.sin(h * ph / 2 + 0.7 * h)
    rough = np.clip(0.65 + 0.45 * smooth_noise(n, 30, rng), 0.05, 1.7)              # slip strength varies cycle to cycle
    stick = 1.0 - 0.9 * np.clip((smooth_noise(n, 13, rng) - 0.8) * 2.5, 0, 1)        # short "stick" drop-outs
    x *= env * rough * stick
    grit = bp(rng.standard_normal(n), 500.0, 4500.0, 1) * env * (0.4 + 0.6 * np.abs(smooth_noise(n, 50, rng)))
    x = x / np.max(np.abs(x)) + 0.10 * grit / np.max(np.abs(grit))
    # the plank and the cavity under the floor
    y = 0.55 * x + 1.0 * peak(x, 148.0, 4) + 0.9 * peak(x, 312.0, 5) + 0.8 * peak(x, 545.0, 6) + 0.55 * peak(x, 930.0, 7) \
        + 0.35 * peak(x, 1580.0, 8) + 0.2 * peak(x, 2500.0, 8)
    y = lp(hp(y, 70.0, 2), 5200.0, 2)
    y /= np.max(np.abs(y))
    out = np.zeros(n)
    out += y * 1.0
    place(out, knock(rng, ((64.0, 1.0, 0.075), (118.0, 0.8, 0.06), (197.0, 0.5, 0.045), (330.0, 0.3, 0.03)), 0.85), 0.012)
    place(out, knock(rng, ((82.0, 1.0, 0.06), (151.0, 0.8, 0.05), (262.0, 0.5, 0.035), (470.0, 0.3, 0.025)), 0.62, 1.4), k_end)
    out = np.tanh(out * 1.3) / np.tanh(1.3)
    out = reverb(out, room_ir(0.55, seed + 1, 150, 7000), 0.14, tail=False)
    return fade(out[:n], 0.002, 0.10)


CREAKS = [
    (9101, 1.35,
     [(0, 118), (0.25, 150), (0.5, 132), (0.8, 188), (1.05, 158), (1.35, 108)],
     [(0, 0), (0.07, 0), (0.13, 0.7), (0.30, 0.9), (0.41, 0.15), (0.50, 0.8), (0.84, 1.0), (0.94, 0.25), (1.03, 0.6),
      (1.16, 0.1), (1.35, 0)],
     [(0.45, 1.10), (0.96, 0.90)], 1.12),
    (9102, 1.70,
     [(0, 228), (0.3, 252), (0.6, 205), (0.9, 172), (1.2, 131), (1.5, 104), (1.7, 94)],
     [(0, 0), (0.06, 0), (0.12, 0.85), (0.38, 1.0), (0.47, 0.2), (0.56, 0.7), (0.80, 0.85), (0.90, 0.1), (1.0, 0.75),
      (1.32, 0.9), (1.46, 0.2), (1.7, 0)],
     [(0.50, 0.93), (0.93, 0.88)], 1.42),
    (9103, 1.98,
     [(0, 96), (0.35, 112), (0.7, 150), (1.0, 205), (1.25, 255), (1.5, 190), (1.75, 140), (1.98, 118)],
     [(0, 0), (0.08, 0), (0.16, 0.6), (0.50, 0.8), (0.62, 0.15), (0.72, 0.9), (1.22, 1.0), (1.30, 0.2), (1.38, 0.85),
      (1.66, 0.6), (1.78, 0.1), (1.98, 0)],
     [(0.66, 1.08), (1.33, 0.86)], 1.70),
]
STINGS = [(5101, (36, 37, 41, 42)),      # C2 C#2 F2 F#2
          (5102, (37, 38, 42)),          # C#2 D2 F#2
          (5103, (36, 39, 40, 42))]      # C2 Eb2 E2 F#2

# ----------------------------------------------------------------------------------------------- main
JOBS = [  # name, [(file stem, fn)], loop, gainDb
    ("etage_theme", [("etage_theme", etage_theme)], True, -10),
    ("dread_layer", [("dread_layer", dread_layer)], True, -8),
    ("piano_sting", [("piano_sting_%d" % (i + 1), (lambda s=s, c=c: piano_sting(s, c))) for i, (s, c) in enumerate(STINGS)],
     False, -4),
    ("floor_creak_long", [("floor_creak_long_%d" % (i + 1), (lambda a=a: floor_creak(*a))) for i, a in enumerate(CREAKS)],
     False, -4),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--no-manifest", action="store_true")
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    only = set(filter(None, a.only.split(",")))
    os.makedirs(a.out, exist_ok=True)
    entries = {}
    for name, files, loop, gain in JOBS:
        if only and name not in only:
            continue
        rels = []
        for stem, fn in files:
            x = normalize(fn(), -3.0)
            path = os.path.join(a.out, stem + ".mp3")
            write_mp3(path, x)
            rels.append(os.path.relpath(path, PC).replace(os.sep, "/"))
            print("  %-24s %6.2f s  %7.1f KiB  %s" % (stem + ".mp3", len(x) / SR, os.path.getsize(path) / 1024.0,
                                                     "loop" if loop else ""))
        entries[name] = {"files": rels, "loop": loop, "gainDb": gain}
    if not a.no_manifest:
        with open(MANIFEST, encoding="utf-8") as fh:
            text = fh.read()
        man = json.loads(text)
        man.update(entries)                       # existing keys keep their position, new ones are appended
        new = json.dumps(man, indent=1, ensure_ascii=False) + ("\n" if text.endswith("\n") else "")
        if new != text:
            with open(MANIFEST, "w", encoding="utf-8") as fh:
                fh.write(new)
            print("  manifest.json updated (%d entries)" % len(man))


if __name__ == "__main__":
    main()
