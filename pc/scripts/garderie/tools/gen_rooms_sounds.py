#!/usr/bin/env python3
"""Synthesizes the sounds of the three extra garderie rooms (dortoir, bureau, toilettes). Everything is generated from
scratch (numpy / scipy), nothing recorded, no existing melody. Deterministic (fixed seeds).

    python3 -I pc/scripts/garderie/tools/gen_rooms_sounds.py [--out DIR] [--no-manifest]

Writes mono 44.1 kHz MP3 (ffmpeg + libmp3lame, 128 kbps, peak -3 dBFS) into pc/assets/audio/garderie/ and adds / refreshes
its own entries in pc/assets/audio/manifest.json (other entries are left untouched, same formatting). Then run
`godot --headless --path pc --import` once so Godot writes the .mp3.import sidecars.

  music_box     ~24 s  original 3/4 lullaby on a steel-comb music box that winds down and stops mid-phrase
  phone_ring    2.4 s  one ring of an electromechanical two-gong telephone bell (25 Hz clapper) + ringing tail
  phone_pickup  0.5 s  handset lifted: plastic clack + hook-switch click
  phone_line    8 s    telephone-band line hiss + hum, three slow close breaths, hang-up click
  water_drip    12 s   seamless loop: 8 irregular drips in a sink, tiled room (silent at both ends)
  stall_creak   2.5 s  slow metal hinge creak (stick-slip squeal) of a toilet-stall door
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
DEFAULT_OUT = os.path.join(PC, "assets", "audio", "garderie")
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
           "-fflags", "+bitexact", "-flags:a", "+bitexact", "-c:a", "libmp3lame", "-b:a", "128k", path]
    subprocess.run(cmd, input=pcm, check=True)


# ----------------------------------------------------------------------------------------------- music box
NOTE = {"D4": 293.66, "E4": 329.63, "G4": 392.00, "A4": 440.00, "B4": 493.88, "C5": 523.25, "D5": 587.33, "E5": 659.26,
        "F#5": 739.99, "G5": 783.99, "A5": 880.00, "B5": 987.77, "C6": 1046.50, "D6": 1174.66, "E6": 1318.51}

# Original tune written for this game (E minor, 3/4). (note, beats) per bar; accompaniment = one low tine on beat 1 and two
# soft inner tines on beats 2 and 3.
MELODY = [
    [("E6", 1), ("B5", 1), ("G5", 1)], [("A5", 2), ("B5", 1)], [("C6", 1), ("B5", 1), ("A5", 1)], [("B5", 3)],
    [("E6", 1), ("B5", 1), ("G5", 1)], [("A5", 2), ("F#5", 1)], [("G5", 1), ("A5", 1), ("F#5", 1)], [("E5", 3)],
    [("G5", 1), ("B5", 1), ("D6", 1)], [("C6", 2), ("A5", 1)], [("B5", 1), ("C6", 1), ("D6", 1)], [("E6", 3)],
]
CHORDS = [("E4", "G4", "B4"), ("A4", "C5", "E5"), ("A4", "C5", "E5"), ("E4", "G4", "B4"),
          ("E4", "G4", "B4"), ("D4", "A4", "D5"), ("A4", "C5", "E5"), ("E4", "G4", "B4"),
          ("G4", "B4", "D5"), ("C5", "E5", "G5"), ("G4", "B4", "D5"), ("E4", "G4", "B4")]


def tine(freq, vel, rng, dur=2.6):
    """One tooth of the steel comb: fundamental + inharmonic partials (~3.0x, ~5.4x), instant attack, exponential decay."""
    n = secs(dur)
    t = np.arange(n) / SR
    tau = 0.30 * (700.0 / freq) ** 0.35            # ~1-1.5 s to fall 40 dB, shorter for the small high teeth
    x = np.sin(2 * np.pi * freq * t) * np.exp(-t / tau)
    x += 0.30 * np.sin(2 * np.pi * freq * 2.99 * t + 0.4) * np.exp(-t / (tau * 0.42))
    x += 0.16 * np.sin(2 * np.pi * freq * 5.41 * t + 1.1) * np.exp(-t / (tau * 0.22))
    x += 0.06 * np.sin(2 * np.pi * freq * 8.93 * t + 2.0) * np.exp(-t / (tau * 0.10))
    pl = hp(rng.standard_normal(secs(0.004)), 2500) * np.exp(-np.arange(secs(0.004)) / (0.0009 * SR))   # pin letting go
    x[:len(pl)] += 0.22 * pl
    return x * vel


def music_box():
    rng = np.random.default_rng(1994)
    beat = 0.70
    wind_t0, wind_len = 17.6, 6.0
    stop_t = 22.60                                   # the cylinder stalls here: no pin plucks a tooth after this

    def slow(t):                                     # tempo stretch of the dying spring
        u = np.clip((t - wind_t0) / wind_len, 0, 1.2)
        return 1.0 + 1.9 * u ** 1.6

    def sag(t):                                      # pitch sags a little (about -45 cents at the end)
        u = np.clip((t - wind_t0) / wind_len, 0, 1.2)
        return 1.0 - 0.026 * u ** 1.8

    # beat index -> time, integrating the tempo curve
    def beat_time(b):
        t, done = 0.0, 0.0
        step = 0.05
        while done < b - 1e-9:
            s = min(step, b - done)
            t += s * beat * slow(t)
            done += s
        return t

    detune = {k: 2 ** (rng.uniform(-9, 9) / 1200.0) for k in NOTE}      # each tooth is a bit off, always the same way
    events = []
    b = 0.0
    for bar, chord in zip(MELODY, CHORDS):
        events.append((b, chord[0], 0.55))
        events.append((b + 1, chord[1], 0.30))
        events.append((b + 2, chord[2], 0.30))
        bb = b
        for name, beats in bar:
            events.append((bb, name, 1.0))
            bb += beats
        b += 3
    total = 24.0
    buf = np.zeros(secs(total + 3.0))
    last = 0.0
    played = []
    for bt, name, vel in sorted(events):
        t = beat_time(bt)
        if t > stop_t:
            continue
        t += rng.normal(0, 0.007) + (0.012 if vel < 0.9 else 0.0) * rng.random()
        t = max(t, 0.0)
        f = NOTE[name] * detune[name] * sag(t)
        place(buf, tine(f, vel * rng.uniform(0.8, 1.0), rng), t + 0.05)
        last = max(last, t)
        played.append((round(t, 2), name))
    # mechanism: governor whirr + gear-tooth ticks, slowing with the spring and stopping with the cylinder
    n = len(buf)
    t = np.arange(n) / SR
    run = np.clip((stop_t + 0.25 - t) / 0.4, 0, 1) * np.clip(t / 0.15, 0, 1)
    whirr = bp(rng.standard_normal(n), 900, 4200, 1) * (0.6 + 0.4 * np.sin(2 * np.pi * np.cumsum(31.0 / slow(t)) / SR))
    ticks = np.zeros(n)
    tt = 0.03
    k = 0
    while tt < stop_t + 0.2:
        c = hp(rng.standard_normal(secs(0.003)), 1800) * np.exp(-np.arange(secs(0.003)) / (0.0006 * SR))
        place(ticks, c * rng.uniform(0.5, 1.0) * (1.0 if k % 6 else 1.8), tt)
        tt += (1.0 / 13.0) * slow(tt) * rng.uniform(0.94, 1.06)
        k += 1
    mech = (whirr * 0.012 + bp(ticks, 1500, 7000, 1) * 0.05) * run
    x = hp(buf, 220) + mech
    x = x + 0.35 * peak(x, 1250, 3.0) + 0.2 * peak(x, 2900, 4.0)       # the little wooden box
    x = reverb(x, room_ir(0.38, 11, 250, 7000), 0.16, tail=False)
    x = x[:secs(total)]
    print("    music box: %d notes, last ones: %s" % (len(played), played[-5:]))
    return fade(x, 0.002, 0.5)


# ----------------------------------------------------------------------------------------------- telephone
def bell_ir(f0, rng, dur=0.7):
    n = secs(dur)
    t = np.arange(n) / SR
    ratios = [1.0, 2.32, 2.76, 4.07, 5.43, 6.91, 8.6]
    amps = [1.0, 0.55, 0.40, 0.34, 0.24, 0.13, 0.07]
    taus = [0.17, 0.12, 0.10, 0.065, 0.045, 0.03, 0.02]
    x = np.zeros(n)
    for r, a, tau in zip(ratios, amps, taus):
        f = f0 * r * rng.uniform(0.995, 1.005)
        if f > 19000:
            continue
        ph = rng.uniform(0, 2 * np.pi)
        x += a * np.exp(-t / tau) * (np.sin(2 * np.pi * f * t + ph) + 0.6 * np.sin(2 * np.pi * f * 1.0045 * t + ph * 1.7))
    return x


def phone_ring():
    rng = np.random.default_rng(555)
    ring_len, tail_len = 2.0, 0.4
    n = secs(ring_len + tail_len)
    rate = 25.0
    out = np.zeros(n + secs(0.8))
    click = np.zeros(len(out))
    for b, (f0, off, g) in enumerate(((1310.0, 0.0, 1.0), (1625.0, 0.5, 0.92))):
        train = np.zeros(n)
        k = 0
        while True:
            ts = (k + off) / rate + rng.normal(0, 0.0007) + 0.004
            if ts >= ring_len:
                break
            a = rng.uniform(0.8, 1.0) * min(1.0, 0.45 + ts / 0.09) * g      # the clapper builds up over the first strokes
            train[secs(ts)] += a
            c = bp(rng.standard_normal(secs(0.002)), 2000, 7500, 1) * np.exp(-np.arange(secs(0.002)) / (0.0005 * SR))
            place(click, c * a, ts)
            k += 1
        out[:n + secs(0.7) - 1] += signal.fftconvolve(train, bell_ir(f0, rng))[:n + secs(0.7) - 1]
    t = np.arange(len(out)) / SR
    armature = bp(signal.square(2 * np.pi * rate * 2 * t + 0.3) * (t < ring_len), 160, 620, 1)    # buzz of the body
    x = out / np.max(np.abs(out)) + 0.05 * click / (np.max(np.abs(click)) + 1e-9) + 0.045 * armature
    x = hp(x, 250)
    x = np.tanh(x * 1.4) / 1.4
    x = reverb(x, room_ir(0.30, 12, 300, 8000), 0.10, tail=False)
    return fade(x[:n], 0.001, 0.06)


def phone_pickup():
    rng = np.random.default_rng(556)
    n = secs(0.5)
    x = np.zeros(n)
    t = np.arange(secs(0.12)) / SR

    def thunk(modes, scale):
        y = np.zeros(len(t))
        for f, tau, a in modes:
            y += a * np.sin(2 * np.pi * f * rng.uniform(0.97, 1.03) * t + rng.uniform(0, 6.28)) * np.exp(-t / tau)
        nb = bp(rng.standard_normal(len(t)), 800, 6000, 1) * np.exp(-t / 0.004)
        return (y + 0.6 * nb) * scale

    plastic = [(640, 0.012, 1.0), (1480, 0.009, 0.7), (2550, 0.006, 0.5), (4100, 0.004, 0.3)]
    place(x, thunk(plastic, 0.8), 0.030)                         # handset leaves the cradle
    place(x, thunk([(f * 1.12, tau, a) for f, tau, a in plastic], 0.45), 0.052)
    # hook switch springs up: sharp click + tiny spring tink
    sw = [(2900, 0.004, 1.0), (4700, 0.003, 0.7), (1900, 0.006, 0.5)]
    place(x, thunk(sw, 1.0), 0.150)
    place(x, thunk(sw, 0.35), 0.163)
    tk = np.arange(secs(0.25)) / SR
    place(x, 0.05 * np.sin(2 * np.pi * 3350 * tk) * np.exp(-tk / 0.035), 0.152)
    place(x, 0.035 * (np.sin(2 * np.pi * 1310 * tk) + 0.5 * np.sin(2 * np.pi * 3040 * tk)) * np.exp(-tk / 0.12), 0.034)   # bells shiver
    # hand / cord rustle
    rus = bp(rng.standard_normal(n), 500, 5000, 1) * curve([(0, 0), (0.03, 0.5), (0.1, 0.25), (0.22, 0.45), (0.36, 0.15), (0.5, 0)], n)
    x += 0.035 * rus * (0.5 + 0.5 * np.abs(smooth_noise(n, 40, rng)))
    x = reverb(hp(x, 180), room_ir(0.25, 13, 300, 8000), 0.08, tail=False)
    return fade(x[:n], 0.001, 0.05)


def phone_line():
    rng = np.random.default_rng(557)
    total = 8.0
    n = secs(total)
    t = np.arange(n) / SR
    hang = 7.62
    live = (t < hang).astype(float)
    hiss = rng.standard_normal(n) * 0.055 * (1.0 + 0.25 * smooth_noise(n, 0.7, rng))
    hum = sum(a * np.sin(2 * np.pi * f * t + p) for f, a, p in ((120, 0.02, 0.3), (180, 0.03, 1.0), (300, 0.022, 2.1), (420, 0.012, 0.7), (540, 0.008, 1.9)))
    crack = np.zeros(n)
    for _ in range(14):
        i = rng.integers(0, secs(hang) - 200)
        crack[i:i + rng.integers(2, 9)] += rng.uniform(-1, 1) * 0.5
    breath = np.zeros(n)

    def one(dur, shape, lo_, hi_, gain, rasp=0.0):
        m = secs(dur)
        u = np.linspace(0, 1, m)
        env = u ** shape[0] * (1 - u) ** shape[1]
        env /= env.max()
        y = bp(rng.standard_normal(m), lo_, hi_, 2)
        y += 0.5 * peak(rng.standard_normal(m), (lo_ * hi_) ** 0.5 * (0.8 + 0.5 * u.mean()), 2.5)
        trem = 1.0 + 0.22 * smooth_noise(m, 9, rng)
        if rasp > 0:
            trem *= 1.0 - rasp * (0.5 + 0.5 * np.sin(2 * np.pi * 27 * u * dur + 0.25 * smooth_noise(m, 5, rng)))
        return y / (np.std(y) + 1e-9) * env * trem * gain

    #          start  inhale s  exhale s  level
    sched = [(0.75, 0.95, 1.30, 0.22), (3.25, 1.05, 1.45, 0.30), (5.55, 0.85, 1.15, 0.42)]
    for k, (t0, d_in, d_out, g) in enumerate(sched):
        place(breath, one(d_in, (1.6, 0.9), 900, 3000, g * 0.75), t0)                              # in: thin, airy
        place(breath, one(d_out, (0.8, 1.8), 380, 1700, g, rasp=0.25 + 0.2 * k), t0 + d_in + 0.14)  # out: lower, close, rasping
        place(breath, one(d_out, (0.6, 2.4), 1500, 3300, g * 0.35), t0 + d_in + 0.14)
    x = (hiss + hum + crack * 0.06 + breath) * live
    # hang-up: hook-switch clunk, then a dead line
    tc = np.arange(secs(0.3)) / SR
    clunk = (np.sin(2 * np.pi * 520 * tc) * np.exp(-tc / 0.012) + 0.7 * np.sin(2 * np.pi * 1700 * tc + 1) * np.exp(-tc / 0.006)
             + 0.8 * rng.standard_normal(len(tc)) * np.exp(-tc / 0.003))
    place(x, clunk * 0.9, hang)
    place(x, clunk * 0.35, hang + 0.045)
    x = bp(x, 300, 3400, 4)                                      # telephone band
    x = np.tanh(x * 2.2) / 2.2                                   # carbon-microphone grit
    x = bp(x, 300, 3400, 2)
    return fade(x, 0.02, 0.08)


# ----------------------------------------------------------------------------------------------- washroom
def water_drip():
    rng = np.random.default_rng(558)
    total = 12.0
    n = secs(total)
    dry = np.zeros(n)
    times = [0.62, 1.94, 3.18, 4.87, 5.52, 7.41, 8.96, 10.22]    # 8 irregular drips; nothing in the last 1.7 s
    for i, t0 in enumerate(times):
        m = secs(0.25)
        t = np.arange(m) / SR
        f0 = rng.uniform(900, 1250)
        f1 = f0 * rng.uniform(1.30, 1.45)                        # quick upward glide, stays within 900-1800 Hz
        f = f1 + (f0 - f1) * np.exp(-t / rng.uniform(0.012, 0.022))
        ph = 2 * np.pi * np.cumsum(f) / SR
        tau = rng.uniform(0.022, 0.038)
        g = rng.uniform(0.6, 1.0)
        plip = np.sin(ph) * np.exp(-t / tau) * np.clip(t / 0.0015, 0, 1)
        plip += 0.18 * np.sin(2 * ph + 0.5) * np.exp(-t / (tau * 0.5))
        tick = hp(rng.standard_normal(m), 3500) * np.exp(-t / 0.0012) * 0.25         # the drop hitting the film of water
        place(dry, (plip + tick) * g, t0)
        if rng.random() < 0.6:                                   # small secondary droplet
            f0b = min(f0 * rng.uniform(1.15, 1.3), 1300)
            fb = f0b * 1.35 + (f0b - f0b * 1.35) * np.exp(-t / 0.01)
            place(dry, 0.3 * g * np.sin(2 * np.pi * np.cumsum(fb) / SR) * np.exp(-t / 0.014), t0 + rng.uniform(0.07, 0.12))
        tb = np.arange(secs(0.2)) / SR                           # faint ping of the basin
        place(dry, 0.04 * g * np.sin(2 * np.pi * rng.uniform(2250, 2400) * tb) * np.exp(-tb / 0.03), t0 + 0.002)
    ir = room_ir(0.75, 14, 600, 11000, early=((0.0043, 0.5), (0.0079, 0.42), (0.0121, 0.36), (0.0173, 0.3), (0.0246, 0.24)))
    x = reverb(dry, ir, 0.42, tail=False)
    x = hp(x, 300)
    # the loop point must be silent on both sides (also hides the MP3 encoder padding)
    t = np.arange(n) / SR
    x *= np.clip((t - 0.25) / 0.2, 0, 1) * np.clip((total - 0.45 - t) / 0.5, 0, 1)
    return x


def stall_creak():
    rng = np.random.default_rng(559)
    total = 2.5
    n = secs(total)
    f = curve([(0, 415), (0.3, 505), (0.55, 455), (0.8, 560), (1.05, 700), (1.25, 640), (1.45, 790), (1.65, 880),
               (1.9, 770), (2.1, 600), (2.3, 500), (2.5, 430)], n)
    f *= 1.0 + 0.035 * smooth_noise(n, 5, rng) + 0.02 * smooth_noise(n, 90, rng)
    # stick-slip: the pitch jumps when the hinge lets go
    for tj, dj in ((0.62, 0.93), (1.32, 1.07), (1.98, 0.94)):
        f[secs(tj):] *= dj
    f = np.clip(f, 400, 900)
    env = curve([(0, 0), (0.07, 0.45), (0.4, 0.8), (0.56, 0.2), (0.66, 0.75), (1.2, 1.0), (1.3, 0.35), (1.38, 0.95),
                 (1.9, 0.8), (1.99, 0.3), (2.08, 0.6), (2.35, 0.25), (2.5, 0)], n)
    rough = np.clip(0.7 + 0.35 * smooth_noise(n, 28, rng), 0.05, 1.5)
    ph = 2 * np.pi * np.cumsum(f) / SR
    x = np.zeros(n)
    for h in range(1, 19):
        a = 1.0 / h ** 1.15 * (1.0 + 0.4 * np.sin(h * 1.7))       # uneven harmonic series (pulse-like friction wave)
        x += a * np.sin(h * ph + 0.3 * h * smooth_noise(n, 3, rng) * 0.2) * (h * f < 17000)
    # squeal irregularities: period-doubling episodes and short "stick" drop-outs
    sub = np.clip(smooth_noise(n, 2.5, rng) * 0.8, 0, 1)
    for h in (1, 3, 5, 7):
        x += 0.4 * sub / h * np.sin(h * ph / 2 + 0.7 * h)
    stick = 1.0 - 0.85 * np.clip((smooth_noise(n, 16, rng) - 1.0) * 2.5, 0, 1)
    x *= env * rough * stick
    grit = bp(rng.standard_normal(n), 1500, 8000, 1) * env * (0.5 + 0.5 * np.abs(smooth_noise(n, 60, rng)))
    x = x + 0.12 * grit * np.max(np.abs(x))
    y = 0.5 * x + 0.9 * peak(x, 1180, 9) + 0.8 * peak(x, 2360, 11) + 0.6 * peak(x, 3900, 12) + 0.3 * peak(x, 5600, 10)   # door panel
    y = hp(y, 300)
    y = np.tanh(y / np.max(np.abs(y)) * 1.6)
    y = reverb(y, room_ir(0.8, 15, 500, 10000), 0.22, tail=False)
    return fade(y[:n], 0.005, 0.12)


# ----------------------------------------------------------------------------------------------- main
JOBS = [  # name, fn, loop, gainDb
    ("music_box", music_box, False, -4),
    ("phone_ring", phone_ring, False, -2),
    ("phone_pickup", phone_pickup, False, -6),
    ("phone_line", phone_line, False, -6),
    ("water_drip", water_drip, True, -10),
    ("stall_creak", stall_creak, False, -6),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--no-manifest", action="store_true")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    entries = {}
    for name, fn, loop, gain in JOBS:
        x = normalize(fn(), -3.0)
        path = os.path.join(a.out, name + ".mp3")
        write_mp3(path, x)
        rel = os.path.relpath(path, PC).replace(os.sep, "/")
        entries[name] = {"files": [rel], "loop": loop, "gainDb": gain}
        print("  %-14s %6.2f s  %6.1f KiB  %s" % (name + ".mp3", len(x) / SR, os.path.getsize(path) / 1024.0, "loop" if loop else ""))
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
