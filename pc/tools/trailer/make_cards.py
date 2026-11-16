#!/usr/bin/env python3
"""Trailer text cards and title, 1920x1080 at 60 fps: tracked serif capitals that drift apart, glow, a little
chromatic fringe, film grain, flicker and short glitches. One .mp4 per card (video only).

    python3 pc/tools/trailer/make_cards.py /abs/out_dir [card ...]
"""
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H, FPS = 1920, 1080, 60
HERE = os.path.dirname(os.path.abspath(__file__))
FONTS = os.path.join(HERE, "..", "..", "assets", "fonts")
SERIF = os.path.join(FONTS, "gelasio", "Gelasio-Regular.ttf")
SERIF_B = os.path.join(FONTS, "gelasio", "Gelasio-Bold.ttf")
TYPE = os.path.join(FONTS, "special_elite", "SpecialElite-Regular.ttf")
SANS = os.path.join(FONTS, "atkinson_hyperlegible", "AtkinsonHyperlegible-Regular.ttf")
HAND = os.path.join(FONTS, "caveat", "Caveat-Bold.ttf")

BONE = np.array([0.93, 0.89, 0.82], np.float32)
RED = np.array([0.80, 0.11, 0.08], np.float32)
DIM = np.array([0.62, 0.60, 0.56], np.float32)

_fonts = {}


def font(path, size):
    key = (path, round(size * 4) / 4)
    if key not in _fonts:
        _fonts[key] = ImageFont.truetype(path, key[1])
    return _fonts[key]


def smooth(t):
    t = min(1.0, max(0.0, t))
    return t * t * (3 - 2 * t)


def text_layer(text, path, size, tracking, cy, alphas=None, jitter=0.0, rng=None, cx=W / 2):
    """Luminance layer (float32 0..1) of one line of tracked text centred on (cx, cy)."""
    f = font(path, size)
    adv = [f.getlength(ch) + tracking * size for ch in text]
    total = sum(adv) - tracking * size
    img = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(img)
    x = cx - total / 2
    asc, desc = f.getmetrics()
    base = cy + asc * 0.36
    for i, ch in enumerate(text):
        a = 1.0 if alphas is None else alphas[i]
        if a > 0.004 and ch != " ":
            jx = jy = 0.0
            if jitter > 0 and rng is not None:
                jx, jy = rng.normal(0, jitter, 2)
            d.text((x + jx, base + jy), ch, font=f, fill=int(255 * min(1.0, a)), anchor="ls")
        x += adv[i]
    return np.asarray(img, np.float32) / 255.0


def fit(text, path, size, tracking, max_w=1640):
    f = font(path, size)
    total = sum(f.getlength(ch) + tracking * size for ch in text)
    return size * min(1.0, max_w / total)


def glow(layer, radius):
    img = Image.fromarray((np.clip(layer, 0, 1) * 255).astype(np.uint8))
    return np.asarray(img.filter(ImageFilter.GaussianBlur(radius)), np.float32) / 255.0


def shift(a, dx):
    if dx == 0:
        return a
    out = np.zeros_like(a)
    if dx > 0:
        out[:, dx:] = a[:, :-dx]
    else:
        out[:, :dx] = a[:, -dx:]
    return out


class Look:
    """Grain, vignette, flicker and glitches shared by every card."""

    def __init__(self, seed):
        self.rng = np.random.default_rng(seed)
        g = np.random.default_rng(7)
        self.grain = [g.normal(0, 1, (H // 2, W // 2)).astype(np.float32) for _ in range(9)]
        yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
        r = np.sqrt(((xx - W / 2) / (W * 0.62)) ** 2 + ((yy - H / 2) / (H * 0.62)) ** 2)
        self.vig = np.clip(1.0 - r, 0, 1) ** 1.6
        self.i = 0

    def finish(self, layers, glitch=0.0, flicker=1.0, haze=0.012):
        """layers: list of (luminance, rgb colour, fringe px). Returns the uint8 frame."""
        frame = np.zeros((H, W, 3), np.float32)
        for lum, col, ca in layers:
            ca = int(round(ca + glitch * 9))
            frame[..., 0] += shift(lum, -ca) * col[0]
            frame[..., 1] += lum * col[1]
            frame[..., 2] += shift(lum, ca) * col[2]
        if glitch > 0:
            n = int(3 + glitch * 7)
            for _ in range(n):
                y0 = int(self.rng.integers(H * 0.3, H * 0.7))
                hh = int(self.rng.integers(4, 46))
                dx = int(self.rng.normal(0, 46 * glitch))
                frame[y0:y0 + hh] = np.roll(frame[y0:y0 + hh], dx, axis=1)
            frame *= 1.0 + 0.5 * glitch
        frame *= flicker
        frame += (haze * flicker) * self.vig[..., None] * np.array([1.0, 0.96, 0.9], np.float32)
        g = self.grain[self.i % len(self.grain)]
        if (self.i // len(self.grain)) % 2:
            g = g[::-1, ::-1]
        g = np.repeat(np.repeat(g, 2, axis=0), 2, axis=1)
        frame += (0.011 + 0.03 * frame.mean(axis=2, keepdims=True)) * g[..., None]
        self.i += 1
        return (np.clip(frame, 0, 1) * 255).astype(np.uint8)

    def flick(self, f, strength=1.0):
        """A film-lamp flicker: mostly steady, now and then a dip."""
        v = 1.0 - 0.035 * strength * abs(self.rng.normal())
        if self.rng.random() < 0.035 * strength:
            v *= self.rng.uniform(0.45, 0.8)
        return v


class Writer:
    def __init__(self, path):
        self.p = subprocess.Popen(
            ["ffmpeg", "-y", "-v", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS),
             "-i", "-", "-c:v", "libx264", "-preset", "fast", "-crf", "12", "-pix_fmt", "yuv420p", "-r", str(FPS), path],
            stdin=subprocess.PIPE)

    def add(self, frame):
        self.p.stdin.write(frame.tobytes())

    def close(self):
        self.p.stdin.close()
        self.p.wait()


def envelope(f, n, fade_in, fade_out):
    return smooth(f / fade_in) * smooth((n - f) / fade_out)


def glitch_times(rng, n, count):
    out = {}
    for _ in range(count):
        t0 = int(rng.integers(int(n * 0.25), int(n * 0.9)))
        for k in range(int(rng.integers(2, 5))):
            out[t0 + k] = float(rng.uniform(0.35, 1.0))
    return out


def card_line(path, text, n=150, colour=BONE, size=74, seed=1, scrawl=None, shake=False, glitches=2, fnt=SERIF,
              track0=0.16, track1=0.24):
    look = Look(seed)
    w = Writer(path)
    gl = glitch_times(look.rng, n, glitches)
    if shake:                                   # the line breaks up at the end
        for k in range(n - 16, n):
            gl[k] = 0.3 + 0.7 * (k - (n - 16)) / 16.0
    for f in range(n):
        t = f / (n - 1)
        tr = track0 + (track1 - track0) * t
        sz = fit(text, fnt, size * (1.0 + 0.035 * t), tr)
        env = envelope(f, n, 34, 9 if shake else 16)
        g = gl.get(f, 0.0)
        txt, fo, col = text, fnt, colour
        if scrawl and g > 0.6:                  # a child's hand shows through for a frame or two
            txt, fo, col = scrawl, HAND, np.array([0.9, 0.86, 0.8], np.float32)
            sz = fit(txt, fo, size * 1.5, 0.02)
            tr = 0.02
        jit = (2.2 * max(0.0, (f - (n - 50)) / 50.0)) if shake else 0.0
        lum = text_layer(txt, fo, sz, tr, H / 2, jitter=jit, rng=look.rng) * env
        halo = glow(lum, 16)
        w.add(look.finish([(lum, col, 1.0), (halo, col * 0.55, 2.0)], glitch=g, flicker=look.flick(f)))
    w.close()


def card_typed(path, text, n=150, seed=2):
    """Typewriter: the date is typed, key by key."""
    look = Look(seed)
    w = Writer(path)
    start, per = 22, 6
    for f in range(n):
        shown = min(len(text), max(0, (f - start) // per + 1)) if f >= start else 0
        alphas = [1.0 if i < shown else 0.0 for i in range(len(text))]
        if 0 < shown <= len(text) and f >= start and (f - start) % per < 2 and shown - 1 < len(text):
            alphas[shown - 1] = 1.6          # the struck key is a touch brighter
        env = smooth((n - f) / 20.0)
        lum = text_layer(text, TYPE, 58, 0.12, H / 2, alphas=alphas) * env
        cursor = np.zeros((H, W), np.float32)
        if shown >= len(text) and (f // 18) % 2 == 0 and f < n - 20:
            f_ = font(TYPE, 58)
            total = sum(f_.getlength(ch) + 0.12 * 58 for ch in text)
            x0 = int(W / 2 + total / 2 + 6)
            cursor[H // 2 - 26:H // 2 + 22, x0:x0 + 5] = 0.8
        lum = np.clip(lum + cursor * env, 0, 1.6)
        halo = glow(np.clip(lum, 0, 1), 12)
        w.add(look.finish([(np.clip(lum, 0, 1), DIM * 1.25, 1.0), (halo, DIM * 0.5, 1.0)], flicker=look.flick(f, 0.6)))
    w.close()


def card_title(path, n=600, seed=9):
    """LA GARDIENNE: the letters come on one by one like failing tubes; chapters, then where to play."""
    look = Look(seed)
    rng = look.rng
    w = Writer(path)
    title = "LA GARDIENNE"
    on_at = [int(rng.integers(10, 80)) for _ in title]
    on_at[3] = 4                                # the G first
    dips = glitch_times(rng, n, 3)
    sub1 = "CHAPITRE 1 · LE SOUS-SOL          CHAPITRE 2 · L’ÉTAGE"
    sub2 = "DISPONIBLE SUR PC"
    sub3 = "À jouer la nuit, avec des écouteurs."
    for f in range(n):
        t = f / (n - 1)
        alphas = []
        for i, _ in enumerate(title):
            k = f - on_at[i]
            if k < 0:
                a = 0.0
            elif k < 26:                        # stutters on
                a = 1.0 if rng.random() < 0.35 + k / 40.0 else 0.08
            else:
                a = 1.0 if rng.random() > 0.004 else 0.25
            alphas.append(a)
        out = smooth((n - f) / 36.0)
        tr = 0.20 + 0.05 * t
        sz = fit(title, SERIF_B, 150 * (1.0 + 0.03 * t), tr, 1700)
        lum = text_layer(title, SERIF_B, sz, tr, H * 0.44, alphas=alphas) * out
        halo = glow(lum, 26)
        rule = np.zeros((H, W), np.float32)
        rw = int(520 * smooth((f - 95) / 50.0))
        if rw > 0:
            rule[int(H * 0.565):int(H * 0.565) + 3, W // 2 - rw:W // 2 + rw] = 1.0
        a1 = smooth((f - 120) / 40.0) * smooth((330 - f) / 30.0)
        a2 = smooth((f - 350) / 36.0)
        a3 = smooth((f - 400) / 40.0)
        layers = [(lum, BONE, 1.0), (halo, RED * 0.9, 3.0), (rule * out, RED, 0.0)]
        if a1 > 0:
            layers.append((text_layer(sub1, SANS, 30, 0.22, H * 0.635) * a1 * out, DIM, 0.0))
        if a2 > 0:
            layers.append((text_layer(sub2, SANS, 38, 0.34, H * 0.635) * a2 * out, BONE * 0.92, 0.0))
        if a3 > 0:
            layers.append((text_layer(sub3, SERIF, 30, 0.04, H * 0.71) * a3 * out, DIM * 0.9, 0.0))
        w.add(look.finish(layers, glitch=dips.get(f, 0.0) * (0.6 if f < 330 else 0.0), flicker=look.flick(f, 0.7), haze=0.016))
    w.close()


CARDS = {
    "c1_date": lambda p: card_typed(p, "NOVEMBRE 1994", 150),
    "c2_fermee": lambda p: card_line(p, "LA GARDERIE A FERMÉ SES PORTES.", 150, seed=11, glitches=1),
    "c3_enfants": lambda p: card_line(p, "LES ENFANTS SONT PARTIS.", 150, seed=12, scrawl="elle nous regarde dormir", glitches=2),
    "c4_restee": lambda p: card_line(p, "ELLE EST RESTÉE.", 150, colour=RED, size=92, seed=13, glitches=2, fnt=SERIF_B),
    "c5_bruit": lambda p: card_line(p, "NE FAIS PAS DE BRUIT.", 120, seed=14, glitches=1),
    "c6_yeux": lambda p: card_line(p, "NE LA QUITTE PAS DES YEUX.", 126, seed=15, shake=True, glitches=1),
    "c7_title": lambda p: card_title(p, 600),
}

if __name__ == "__main__":
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    for name in (sys.argv[2:] or list(CARDS)):
        CARDS[name](os.path.join(out, name + ".mp4"))
        print("card", name, flush=True)
