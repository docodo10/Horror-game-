#!/usr/bin/env python3
"""Fear module — synthesizes every sound of res://assets/audio/fear/ (CC0: generated from scratch here, no recordings).

    python3 pc/scripts/fear/tools/make_fear_sounds.py [--seed N] [--out DIR]

Writes Ogg Vorbis files (ffmpeg + libvorbis) and manifest.json (same shape as res://assets/audio/manifest.json, loaded by
the Audio autoload as an extra manifest). Deterministic for a given seed. Every file is peak-normalised to -2 dBFS (loops -3 dBFS) like
the recorded library; loudness in the game comes from manifest gainDb + scripts/audio/sound_defs.gd.

Sounds (see FEAR_SOUNDS in scripts/audio/sound_defs.gd):
  fear_heartbeat_1..3   one "lub-dub", chest-felt (40-130 Hz body + saturation harmonics so laptop speakers hear it);
                        the fear module fires one per beat at the simulated heart rate (rate pitch-up shortens it)
  fear_rumble           20 s seamless loop: infrasonic-ish rumble (brown noise < 60 Hz, 31/33.5 Hz beating sines)
  fear_drone            30 s seamless stereo loop: dissonant cluster (minor seconds, tritone), glassy highs, breath
  fear_tinnitus_1..2    6 s ear ring after the loudest scares (one ear louder)
  fear_sub_hit_1..2     sub-bass impact (70 -> 28 Hz pitch drop) for big moments
  fear_stinger_1..3     dissonant string screech stab (glimpses)
  fear_stinger_big_1..2 jumpscare layer: brass/string cluster hit + timpani boom + screech + crash
  fear_riser_1          2.6 s reverse swell (tension under a stare)
  fear_crash_1..2       heavy box falling off a shelf: impact, bounces, scattering clatter, rolling tail
  fear_ball_1..3        rubber ball bounce
  fear_distant_1..3     distant heavy thud / door somewhere in the house, long dark tail
  fear_scratch_1..2     nails scratching inside the wall (stick-slip friction)
"""
import argparse
import json
import os
import subprocess
import sys

import numpy as np
from scipy import signal

SR = 44100
HERE = os.path.dirname(os.path.abspath(__file__))
PC = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
DEFAULT_OUT = os.path.join(PC, "assets", "audio", "fear")

rng = np.random.default_rng(1994)


# ----------------------------------------------------------------------------------------------- helpers
def t_axis(dur):
    return np.arange(int(round(dur * SR))) / SR


def env_ad(n, attack, decay, sr=SR):
    """Attack (linear) then exponential decay (time constant `decay`)."""
    t = np.arange(n) / sr
    a = np.clip(t / max(attack, 1e-4), 0.0, 1.0)
    return a * np.exp(-np.maximum(t - attack, 0.0) / max(decay, 1e-4))


def damped(freq, dur, decay, attack=0.002, phase=0.0, glide=None):
    t = t_axis(dur)
    if glide is None:
        ph = 2 * np.pi * freq * t + phase
    else:
        f1, tau = glide  # exponential glide from freq to f1 with time constant tau
        f = f1 + (freq - f1) * np.exp(-t / tau)
        ph = 2 * np.pi * np.cumsum(f) / SR + phase
    return np.sin(ph) * env_ad(len(t), attack, decay)


def place(buf, x, at):
    i = int(round(at * SR))
    if i >= len(buf):
        return buf
    j = min(len(buf), i + len(x))
    buf[i:j] += x[: j - i]
    return buf


def lp(x, hz, order=4):
    sos = signal.butter(order, hz, "low", fs=SR, output="sos")
    return signal.sosfilt(sos, x, axis=0)


def hp(x, hz, order=2):
    sos = signal.butter(order, hz, "high", fs=SR, output="sos")
    return signal.sosfilt(sos, x, axis=0)


def bp(x, lo, hi, order=2):
    sos = signal.butter(order, [lo, hi], "band", fs=SR, output="sos")
    return signal.sosfilt(sos, x, axis=0)


def noise(n):
    return rng.standard_normal(n)


def brown(n):
    b = np.cumsum(rng.standard_normal(n))
    b = hp(b, 8.0, 2)
    return b / (np.max(np.abs(b)) + 1e-9)


def saw(freq_t, n_harm=24):
    """Band-limited sawtooth from an instantaneous frequency array."""
    ph = 2 * np.pi * np.cumsum(freq_t) / SR
    out = np.zeros_like(ph)
    f0 = float(np.max(freq_t))
    for k in range(1, n_harm + 1):
        if k * f0 > SR * 0.45:
            break
        out += np.sin(k * ph) / k
    return out


def reverb(x, rt=1.6, pre=0.012, lowpass_hz=6000.0, mix=0.35, stereo=False):
    """Synthetic diffuse reverb: convolution with exponentially decaying filtered noise."""
    n = int(rt * SR * 1.2)
    t = np.arange(n) / SR
    chans = []
    for _ in range(2 if stereo else 1):
        ir = noise(n) * np.exp(-6.9 * t / rt)
        ir = lp(ir, lowpass_hz, 2)
        ir = np.concatenate([np.zeros(int(pre * SR)), ir])
        ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
        chans.append(ir)
    if x.ndim == 1 and not stereo:
        wet = signal.fftconvolve(x, chans[0])[: len(x) + len(chans[0])]
        dry = np.concatenate([x, np.zeros(len(wet) - len(x))])
        return dry * (1 - mix) + wet * mix
    if x.ndim == 1:
        x = np.stack([x, x], axis=1)
    outs = []
    for c in range(2):
        wet = signal.fftconvolve(x[:, c], chans[c])
        dry = np.concatenate([x[:, c], np.zeros(len(wet) - len(x))])
        outs.append(dry * (1 - mix) + wet * mix)
    return np.stack(outs, axis=1)


def soft(x, drive=1.5):
    return np.tanh(x * drive) / np.tanh(drive)


def fade_tail(x, sec=0.05):
    n = min(len(x), int(sec * SR))
    w = np.linspace(1.0, 0.0, n)
    if x.ndim == 2:
        w = w[:, None]
    x[-n:] *= w
    return x


def trim_silence(x, thr_db=-62.0):
    a = np.abs(x) if x.ndim == 1 else np.max(np.abs(x), axis=1)
    thr = np.max(a) * 10 ** (thr_db / 20)
    idx = np.nonzero(a > thr)[0]
    if len(idx) == 0:
        return x
    end = min(len(x), idx[-1] + int(0.05 * SR))
    return fade_tail(x[:end].copy(), 0.04)


def normalize(x, peak_db=-1.0):
    m = np.max(np.abs(x)) + 1e-12
    return x * (10 ** (peak_db / 20) / m)


def loopify(x, xfade):
    """Makes a seamless loop: the last `xfade` seconds are crossfaded (equal power) into the start."""
    n = int(xfade * SR)
    body = x[:-n].copy()
    tail = x[-n:]
    w = np.linspace(0.0, 1.0, n)
    if x.ndim == 2:
        w = w[:, None]
    body[:n] = body[:n] * np.sqrt(w) + tail * np.sqrt(1.0 - w)
    return body


def q(freq, period):
    """Rounds a frequency to a whole number of cycles over `period` seconds (seamless loops)."""
    return round(freq * period) / period


# ----------------------------------------------------------------------------------------------- sounds
def heartbeat(var):
    r = np.random.default_rng(100 + var)
    det = 1.0 + r.uniform(-0.05, 0.05)
    dur = 0.62
    out = np.zeros(int(dur * SR))
    # S1 "lub": mitral/tricuspid closure — low, round, slightly longer
    lub = (damped(55 * det, 0.3, 0.070, 0.007) * 1.0 + damped(39 * det, 0.3, 0.09, 0.009) * 0.6
           + damped(98 * det, 0.3, 0.045, 0.005) * 0.75 + damped(146 * det, 0.3, 0.03, 0.004) * 0.45
           + damped(210 * det, 0.3, 0.018, 0.003) * 0.2)
    thud = bp(noise(len(lub)), 60.0, 420.0, 2) * env_ad(len(lub), 0.005, 0.03) * 0.5
    place(out, lub + thud, 0.008)
    # S2 "dub": aortic/pulmonary closure — higher, shorter, a little quieter
    dub_at = 0.008 + r.uniform(0.215, 0.255)
    dub = (damped(68 * det, 0.25, 0.048, 0.005) * 0.75 + damped(48 * det, 0.25, 0.055, 0.006) * 0.4
           + damped(124 * det, 0.25, 0.034, 0.004) * 0.7 + damped(188 * det, 0.25, 0.02, 0.003) * 0.35)
    dthud = bp(noise(len(dub)), 80.0, 520.0, 2) * env_ad(len(dub), 0.004, 0.02) * 0.45
    place(out, (dub + dthud) * r.uniform(0.62, 0.78), dub_at)
    out = soft(out * 1.8, 2.2)            # chest saturation: harmonics at 100-300 Hz carry it on small speakers
    out = lp(out, 1100.0, 2)
    return trim_silence(out)


def rumble():
    period = 20.0
    n = int((period + 1.5) * SR)
    t = np.arange(n) / SR
    b = lp(brown(n), 58.0, 4)
    b /= np.max(np.abs(b)) + 1e-9
    # slow swells (whole cycles over the loop)
    am = 0.65 + 0.35 * np.sin(2 * np.pi * q(0.1, period) * t + 0.4) * np.sin(2 * np.pi * q(0.23, period) * t + 1.3)
    s = (np.sin(2 * np.pi * q(31.0, period) * t) * 0.5 + np.sin(2 * np.pi * q(33.5, period) * t + 0.7) * 0.45
         + np.sin(2 * np.pi * q(46.2, period) * t + 2.0) * 0.12)
    x = b * am * 0.9 + s * (0.55 + 0.45 * np.sin(2 * np.pi * q(0.05, period) * t))
    growl = bp(brown(n), 55.0, 150.0, 2)
    growl /= np.max(np.abs(growl)) + 1e-9
    x = x + growl * 0.35 * (0.6 + 0.4 * np.sin(2 * np.pi * q(0.15, period) * t + 2.2))
    x = soft(x, 1.8)
    x = lp(x, 190.0, 2)
    return loopify(x, 1.5)


def drone():
    period = 30.0
    n = int((period + 2.0) * SR)
    t = np.arange(n) / SR
    L = np.zeros(n)
    R = np.zeros(n)
    # low cluster: A1 / Bb1 (minor 2nd) + Eb2 (tritone) — bowed saw voices with slow periodic drift
    voices = [(55.0, 0.36, -0.3), (58.27, 0.28, 0.35), (77.78, 0.26, 0.0), (110.0, 0.14, -0.5), (116.54, 0.12, 0.5)]
    for i, (f, a, pan) in enumerate(voices):
        f = q(f, period)
        drift = 1.0 + 0.0025 * np.sin(2 * np.pi * q(0.033 * (i + 1), period) * t + i)
        v = saw(f * drift, 12)
        v = lp(v, 420.0 + 80 * i, 2)
        amp = a * (0.7 + 0.3 * np.sin(2 * np.pi * q(1 / 15.0 * (1 + i % 3), period) * t + 0.9 * i))
        L += v * amp * (1 - max(pan, 0))
        R += v * amp * (1 + min(pan, 0))
    # mid "strings": B3 / C4 rubbing, very slow tremolo
    for i, (f, pan) in enumerate([(246.94, -0.6), (261.63, 0.6), (369.99, 0.0)]):
        f = q(f, period)
        vib = 1.0 + 0.003 * np.sin(2 * np.pi * q(4.8 + i * 0.4, period) * t)
        v = lp(saw(f * vib, 10), 1600.0, 2)
        sw = 0.5 + 0.5 * np.sin(2 * np.pi * q(1 / 10.0, period) * t + 2.1 * i)
        L += v * 0.13 * sw * (1 - max(pan, 0))
        R += v * 0.13 * sw * (1 + min(pan, 0))
    # glassy highs: A5 / Bb5 / E6 sine cluster, beating
    for i, (f, pan) in enumerate([(880.0, -0.8), (932.33, 0.8), (1318.5, -0.2), (1244.5, 0.3)]):
        f = q(f, period)
        g = np.sin(2 * np.pi * f * t) * (0.5 + 0.5 * np.sin(2 * np.pi * q(1 / 7.5, period) * t + i * 1.7)) ** 2
        L += g * 0.035 * (1 - max(pan, 0))
        R += g * 0.035 * (1 + min(pan, 0))
    # breath: band of noise swelling
    for ch, arr in ((0, L), (1, R)):
        nb = bp(noise(n), 280.0, 900.0, 2)
        nb /= np.max(np.abs(nb)) + 1e-9
        arr += nb * 0.06 * (0.5 + 0.5 * np.sin(2 * np.pi * q(1 / 6.0, period) * t + ch * 1.2))
    x = np.stack([L, R], axis=1)
    x = soft(x * 0.9, 1.2)
    return loopify(x, 2.0)


def tinnitus(var):
    dur = 6.2
    t = t_axis(dur)
    f = 6100.0 if var == 1 else 4350.0
    tone = np.sin(2 * np.pi * f * t) + 0.25 * np.sin(2 * np.pi * (f + 3.1) * t + 0.4)
    wob = 1.0 + 0.08 * np.sin(2 * np.pi * 0.7 * t) + 0.04 * np.sin(2 * np.pi * 2.3 * t)
    e = np.clip(t / 0.05, 0, 1) * np.where(t < 0.6, 1.0, np.exp(-(t - 0.6) / 1.6))
    x = tone * wob * e
    near, far = (1.0, 0.35) if var == 1 else (0.35, 1.0)
    return fade_tail(np.stack([x * near, x * far], axis=1), 0.2)


def sub_hit(var):
    r = np.random.default_rng(300 + var)
    dur = 2.6
    body = damped(72.0 * r.uniform(0.95, 1.05), dur, 0.75, 0.003, glide=(27.0, 0.22))
    boom = lp(noise(int(dur * SR)), 110.0, 4) * env_ad(int(dur * SR), 0.004, 0.35) * 2.5
    click = lp(noise(int(0.02 * SR)), 1800.0, 2) * env_ad(int(0.02 * SR), 0.0005, 0.004) * 0.6
    x = body + boom
    place(x, click, 0.0)
    x = soft(x * 1.4, 2.2)
    return trim_silence(lp(x, 2500.0, 2))


def strings_cluster(freqs, dur, attack, decay, sustain, vib_rate, vib_depth, bright, glide=0.0, seed=0, pans=None):
    r = np.random.default_rng(seed)
    n = int(dur * SR)
    t = np.arange(n) / SR
    L = np.zeros(n)
    R = np.zeros(n)
    for i, f in enumerate(freqs):
        vr = vib_rate * r.uniform(0.9, 1.1)
        vib = 1.0 + vib_depth * np.sin(2 * np.pi * vr * t + r.uniform(0, 6.28)) * np.clip(t / 0.25, 0, 1)
        gl = 1.0 + glide * np.clip(t / dur, 0, 1) ** 1.5
        jitter = 1.0 + 0.002 * lp(noise(n), 30.0, 2) / 0.05
        ft = f * vib * gl * jitter
        v = saw(ft, 30)
        v = lp(v, bright, 2)
        e = np.clip(t / attack, 0, 1) * (sustain + (1 - sustain) * np.exp(-t / decay)) * np.clip((dur - t) / 0.4, 0, 1)
        pan = pans[i] if pans else r.uniform(-0.7, 0.7)
        L += v * e * (1 - max(pan, 0))
        R += v * e * (1 + min(pan, 0))
    # bow / rosin noise on the attack
    bn = bp(noise(n), 2500.0, 7000.0, 2) * env_ad(n, attack * 0.5, 0.12) * 0.25
    L += bn
    R += bn * 0.9
    return np.stack([L, R], axis=1)


def stinger(var):
    if var == 1:   # high screech cluster, sharp sforzando
        x = strings_cluster([1567.98, 1661.22, 1760.0, 2217.46], 2.3, 0.012, 0.2, 0.14, 6.6, 0.012, 7000.0, seed=11)
        low = strings_cluster([98.0, 103.83, 138.59], 2.3, 0.008, 0.25, 0.15, 5.0, 0.004, 1400.0, seed=12, pans=[-0.3, 0.3, 0.0])
        x = x * 0.8 + low * 0.9
    elif var == 2:  # falling screech (pitch sags)
        x = strings_cluster([1864.66, 1975.53, 2093.0], 2.4, 0.01, 0.28, 0.18, 7.2, 0.015, 8000.0, glide=-0.16, seed=21)
        low = strings_cluster([82.41, 87.31], 2.4, 0.006, 0.3, 0.2, 4.0, 0.004, 1200.0, seed=22, pans=[-0.4, 0.4])
        x = x * 0.75 + low
    else:           # rising, whining cluster
        x = strings_cluster([1174.66, 1244.51, 1661.22], 2.1, 0.02, 0.4, 0.3, 7.8, 0.01, 6000.0, glide=0.12, seed=31)
        low = strings_cluster([73.42, 77.78], 2.1, 0.01, 0.35, 0.25, 3.5, 0.004, 1000.0, seed=32, pans=[-0.3, 0.3])
        x = x * 0.8 + low * 0.8
    hit = sub_hit(var)[: int(0.9 * SR)] * 0.5
    x[: len(hit)] += np.stack([hit, hit], axis=1)
    x = soft(x * 0.8, 1.3)
    x = reverb(x, rt=1.5, pre=0.015, lowpass_hz=7000.0, mix=0.32, stereo=True)
    return trim_silence(x)


def stinger_big(var):
    r = np.random.default_rng(400 + var)
    dur = 3.2
    n = int(dur * SR)
    t = np.arange(n) / SR
    # brass / low strings cluster with an instant attack
    low = strings_cluster([55.0, 58.27, 82.41, 87.31, 116.54], dur, 0.004, 0.35, 0.18, 4.0, 0.003, 2200.0, seed=410 + var)
    high = strings_cluster([2093.0, 2217.46, 2349.32, 2959.96] if var == 1 else [1760.0, 1864.66, 2489.02, 2637.02],
                           dur, 0.006, 0.22, 0.25, 8.0, 0.018, 9000.0, glide=-0.08 if var == 2 else 0.05, seed=420 + var)
    boom = sub_hit(var)[:n]
    boom = np.pad(boom, (0, n - len(boom)))
    crash = hp(noise(n), 3500.0, 2) * env_ad(n, 0.001, 0.45) * 0.35
    crash2 = hp(noise(n), 3500.0, 2) * env_ad(n, 0.001, 0.5) * 0.35
    x = low * 0.9 + high * 0.55
    x[:, 0] += boom * 1.1 + crash
    x[:, 1] += boom * 1.1 + crash2
    x = soft(x * 1.1, 2.0)
    x = reverb(x, rt=2.0, pre=0.01, lowpass_hz=6000.0, mix=0.3, stereo=True)
    _ = r
    return trim_silence(x)


def riser():
    dur = 2.6
    n = int(dur * SR)
    t = np.arange(n) / SR
    k = t / dur
    e = (k ** 3.0) * np.clip((dur - t) / 0.03, 0, 1)
    out = np.zeros((n, 2))
    # sweeping noise band: process in short blocks with a moving band-pass
    blk = 1024
    for ch in range(2):
        nz = noise(n)
        y = np.zeros(n)
        zi = None
        for s in range(0, n, blk):
            c = 300.0 * (16.0 ** (s / n))
            sos = signal.butter(2, [c * 0.7, c * 1.4], "band", fs=SR, output="sos")
            if zi is None:
                zi = np.zeros((sos.shape[0], 2))
            y[s:s + blk], zi = signal.sosfilt(sos, nz[s:s + blk], zi=zi)
        out[:, ch] = y / (np.max(np.abs(y)) + 1e-9)
    tones = np.zeros(n)
    for f in (220.0, 233.08, 329.63):
        ft = f * (1.0 + 1.2 * k ** 2)
        tones += np.sin(2 * np.pi * np.cumsum(ft) / SR)
    out[:, 0] = (out[:, 0] * 0.8 + tones * 0.12) * e
    out[:, 1] = (out[:, 1] * 0.8 + tones * 0.12) * e
    return out


def modal(freqs_decays, dur, amp=1.0, attack=0.0008):
    n = int(dur * SR)
    out = np.zeros(n)
    for f, d, a in freqs_decays:
        out += damped(f, dur, d, attack, phase=rng.uniform(0, 6.28)) * a
    return out * amp


def crash(var):
    r = np.random.default_rng(500 + var)
    dur = 2.2
    out = np.zeros(int(dur * SR))

    def impact(scale, at, bright):
        m = modal([(180 * scale, 0.09, 1.0), (262 * scale, 0.07, 0.7), (415 * scale, 0.05, 0.5),
                   (690 * scale, 0.035, 0.35), (1120 * scale, 0.02, 0.25), (1730 * scale, 0.012, 0.15)], 0.45)
        thump = damped(78 * scale, 0.45, 0.11, 0.002) * 1.3
        nz = lp(noise(len(m)), bright, 2) * env_ad(len(m), 0.0005, 0.018) * 2.2
        nz += hp(noise(len(m)), 2500.0, 2) * env_ad(len(m), 0.0004, 0.006) * 1.2
        place(out, (m + thump + nz), at)

    impact(r.uniform(0.95, 1.05), 0.0, 5000.0)
    impact(r.uniform(1.0, 1.1), 0.11 + r.uniform(0, 0.03), 4000.0)
    place(out, modal([(240, 0.05, 0.4), (520, 0.03, 0.25)], 0.2), 0.2 + r.uniform(0, 0.04))
    # scattering small objects (pens, toys, a tin) with decreasing loudness
    at = 0.08
    for i in range(int(r.integers(9, 15))):
        at += r.uniform(0.025, 0.11)
        f = r.uniform(1800, 5200)
        click = modal([(f, r.uniform(0.008, 0.03), 1.0), (f * 1.53, 0.01, 0.4)], 0.06) * (0.9 * np.exp(-at / 0.5))
        place(out, click, at)
    # something round rolls away
    roll_n = int(1.2 * SR)
    roll = bp(noise(roll_n), 300.0, 1400.0, 2) * (0.5 + 0.5 * np.sin(2 * np.pi * 7.0 * np.arange(roll_n) / SR))
    roll *= np.exp(-np.arange(roll_n) / SR / 0.45) * 0.12
    place(out, roll, 0.35)
    out = soft(out * 0.9, 1.4)
    return trim_silence(out)


def ball(var):
    r = np.random.default_rng(600 + var)
    f = r.uniform(130, 175)
    x = damped(f, 0.3, 0.05, 0.001, glide=(f * 0.82, 0.04)) * 1.0
    x += damped(f * 3.1, 0.3, 0.018, 0.0008) * 0.35
    x += damped(r.uniform(430, 560), 0.3, 0.03, 0.0008) * 0.3   # hollow cavity
    x += damped(r.uniform(1300, 1900), 0.3, 0.006, 0.0004) * 0.45
    x += hp(noise(len(x)), 1500.0, 2) * env_ad(len(x), 0.0003, 0.003) * 0.9
    return trim_silence(soft(x, 1.2))


def distant(var):
    r = np.random.default_rng(700 + var)
    dur = 0.6
    base = np.zeros(int(dur * SR))
    if var == 1:      # heavy thud upstairs (a body? a chair?)
        place(base, damped(58, 0.5, 0.14, 0.003) * 1.2 + lp(noise(int(0.5 * SR)), 300, 2) * env_ad(int(0.5 * SR), 0.002, 0.05), 0.0)
    elif var == 2:    # a door slammed far away
        place(base, modal([(110, 0.12, 1.0), (180, 0.08, 0.6), (330, 0.05, 0.4)], 0.5) + lp(noise(int(0.5 * SR)), 900, 2) * env_ad(int(0.5 * SR), 0.001, 0.02), 0.0)
        place(base, modal([(140, 0.05, 0.3)], 0.2), 0.09)
    else:             # something dragged then dropped
        drag_n = int(0.45 * SR)
        drag = bp(noise(drag_n), 150, 600, 2) * np.sin(np.linspace(0, np.pi, drag_n)) * 0.35
        base = np.concatenate([drag, np.zeros(int(0.6 * SR))])
        place(base, damped(64, 0.5, 0.12, 0.003) * 1.1, 0.45)
    x = lp(base, 700.0 + 200 * r.random(), 2)
    x = reverb(x, rt=3.6, pre=0.05, lowpass_hz=1200.0, mix=0.62)
    return trim_silence(soft(x * 1.2, 1.3), -58.0)


def scratch(var):
    r = np.random.default_rng(800 + var)
    dur = 2.8
    n = int(dur * SR)
    out = np.zeros(n)
    t = 0.0
    # stick-slip: irregular impulses whose rate follows the stroke speed
    while t < dur - 0.05:
        k = t / dur
        stroke = np.sin(np.pi * ((k * 3.0) % 1.0)) ** 0.7   # three strokes
        rate = 25 + 90 * stroke
        t += (1.0 / rate) * r.uniform(0.5, 1.5)
        a = 0.2 + 0.8 * stroke
        i = int(t * SR)
        if i < n:
            out[i] += a * r.uniform(0.5, 1.0) * (1 if r.random() < 0.5 else -1)
    res = np.zeros(n)
    for f, q_ in ((1250, 18), (2300, 22), (3700, 25), (5200, 30)):
        b, a = signal.iirpeak(f * r.uniform(0.95, 1.05), q_, fs=SR)
        res += signal.lfilter(b, a, out)
    body = lp(out, 400.0, 2) * 2.0
    x = res * 0.6 + body
    x = lp(x, 4500.0, 2)
    return trim_silence(soft(x * 3.0, 1.5))


# ----------------------------------------------------------------------------------------------- output
def write_ogg(path, x, quality=4):
    x = np.asarray(x, dtype=np.float64)
    ch = 1 if x.ndim == 1 else x.shape[1]
    pcm = np.clip(x, -1.0, 1.0).astype("<f4").tobytes()
    cmd = ["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", str(ch), "-i", "-",
           "-c:a", "libvorbis", "-q:a", str(quality), path]
    subprocess.run(cmd, input=pcm, check=True)


def main():
    global rng
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--seed", type=int, default=1994)
    a = ap.parse_args()
    rng = np.random.default_rng(a.seed)
    os.makedirs(a.out, exist_ok=True)

    jobs = {
        "fear_heartbeat": ([lambda v=v: heartbeat(v) for v in (1, 2, 3)], False, 0),
        "fear_rumble": ([rumble], True, 0),
        "fear_drone": ([drone], True, 0),
        "fear_tinnitus": ([lambda v=v: tinnitus(v) for v in (1, 2)], False, 0),
        "fear_sub_hit": ([lambda v=v: sub_hit(v) for v in (1, 2)], False, 0),
        "fear_stinger": ([lambda v=v: stinger(v) for v in (1, 2, 3)], False, 0),
        "fear_stinger_big": ([lambda v=v: stinger_big(v) for v in (1, 2)], False, 0),
        "fear_riser": ([riser], False, 0),
        "fear_crash": ([lambda v=v: crash(v) for v in (1, 2)], False, 0),
        "fear_ball": ([lambda v=v: ball(v) for v in (1, 2, 3)], False, 0),
        "fear_distant": ([lambda v=v: distant(v) for v in (1, 2, 3)], False, 0),
        "fear_scratch": ([lambda v=v: scratch(v) for v in (1, 2)], False, 0),
    }
    manifest = {}
    total = 0
    for name, (fns, loop, gain) in jobs.items():
        files = []
        for i, fn in enumerate(fns):
            x = normalize(fn(), -3.0 if loop else -2.0)
            fname = f"{name}_{i + 1}.ogg" if len(fns) > 1 else f"{name}.ogg"
            path = os.path.join(a.out, fname)
            write_ogg(path, x, 8 if loop else 5)
            sz = os.path.getsize(path)
            total += sz
            dur = len(x) / SR
            files.append(f"assets/audio/fear/{fname}")
            print(f"  {fname:28s} {dur:6.2f} s  {'stereo' if x.ndim == 2 else 'mono  '}  {sz / 1024:7.1f} KiB")
        # no gainDb: the level lives in scripts/audio/sound_defs.gd (manifest gainDb would override it)
        manifest[name] = {"files": files, "loop": loop}
    with open(os.path.join(a.out, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=1)
        f.write("\n")
    print(f"[fear-sounds] {sum(len(m['files']) for m in manifest.values())} files, {total / 1024 / 1024:.2f} MiB -> {a.out}")


if __name__ == "__main__":
    sys.exit(main())
