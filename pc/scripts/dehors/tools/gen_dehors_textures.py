#!/usr/bin/env python3
"""Procedural textures of chapter 3, "Dehors" (the yard of the old house, at night). Re-runnable, deterministic (fixed
seeds), nothing downloaded, nothing copied from any other work.

    python3 -I pc/scripts/dehors/tools/gen_dehors_textures.py [out_dir] [--only name,name]

Default out_dir = pc/assets/dehors/textures (read by scripts/dehors/dehors_mats.gd). The script also writes the
`.import` presets of the files it creates; then run `godot --headless --path pc --import` once.

  grass.jpg / _n.png         1024, seamless, 2.2 m: a neglected wet lawn (clumps, dead patches)
  gravel.jpg / _n.png        1024, seamless, 1.6 m: driveway gravel, pebbles of 1-3 cm
  leaves.jpg / _n.png        1024, seamless, 1.8 m: a litter of dead leaves on dark soil
  bark.jpg / _n.png          512, seamless: furrowed bark
  clapboard.jpg / _n.png     1024, seamless, 1.2 m: horizontal lap siding, peeling off-white paint
  planks.jpg / _n.png        1024, seamless, 0.9 m: vertical weathered grey boards (fence, shed, playhouse)
  stone.jpg / _n.png         1024, seamless, 1.5 m: fieldstone wall with mortar (cellar, low walls)
  sand.jpg                   512, seamless: damp sand
  car_paint.jpg              512, seamless: faded burgundy paint going to rust
  trees.png                  2048x2048 RGBA atlas: 4 bare trees (512x1024 each), 2 firs, a dead bush, a hedge piece
  tuft.png                   1024x256 RGBA atlas: 4 grass / weed tufts
  glass.png                  512 RGBA: greenhouse glass (grime, algae, runs; alpha = how dirty)
  handprint.png              256 RGBA: two smeared hand prints on a dirty pane
  toolboard.jpg              1024x512: the shed's tool board, painted outlines, one empty
  window_glow.png            256x384: a lit window behind drawn curtains (emission)
  decal_leaves.png           512 RGBA: scattered dead leaves (decal)
Normal maps are OpenGL convention (+Y up).
"""
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from scipy import ndimage as ndi

HERE = os.path.dirname(os.path.abspath(__file__))
PC = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
ARGV = sys.argv[1:]
OUT = ARGV[0] if ARGV and not ARGV[0].startswith("--") else os.path.join(PC, "assets", "dehors", "textures")
ONLY = set()
if "--only" in ARGV:
    ONLY = set(filter(None, ARGV[ARGV.index("--only") + 1].split(",")))
os.makedirs(OUT, exist_ok=True)
WRITTEN = []


def want(name):
    return not ONLY or name in ONLY


def save(img, name, quality=88):
    path = os.path.join(OUT, name)
    if name.endswith(".jpg"):
        img.convert("RGB").save(path, quality=quality, optimize=True, progressive=False)
    else:
        img.save(path, optimize=True)
    WRITTEN.append(name)
    print("wrote", name, img.size)


# ------------------------------------------------------------------ helpers (periodic noise -> tileable)

def fft_noise(size, beta, seed, lo=1.0, hi=None, sx=1.0, sy=1.0):
    """Periodic 1/f^beta noise in 0..1 (sx, sy stretch the spectrum: anisotropic grain)."""
    rng = np.random.default_rng(seed)
    h, w = (size, size) if isinstance(size, int) else size
    fy = np.fft.fftfreq(h)[:, None] * h * sy
    fx = np.fft.fftfreq(w)[None, :] * w * sx
    f = np.sqrt(fx * fx + fy * fy)
    amp = np.zeros_like(f)
    m = f >= lo
    if hi:
        m &= f <= hi
    amp[m] = 1.0 / np.power(f[m], beta)
    ph = rng.uniform(0, 2 * np.pi, (h, w))
    x = np.real(np.fft.ifft2(amp * np.exp(1j * ph)))
    x -= x.min()
    return x / (x.max() + 1e-12)


def normal_map(height, strength):
    """Periodic height (float) -> RGB normal map image (OpenGL: green up)."""
    dx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) * 0.5 * strength
    dy = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) * 0.5 * strength
    nz = np.ones_like(height)
    ln = np.sqrt(dx * dx + dy * dy + nz * nz)
    n = np.stack([-dx / ln, dy / ln, nz / ln], -1)
    return Image.fromarray(np.clip((n * 0.5 + 0.5) * 255.0 + 0.5, 0, 255).astype(np.uint8), "RGB")


def to_img(rgb):
    return Image.fromarray(np.clip(rgb * 255.0 + 0.5, 0, 255).astype(np.uint8), "RGB")


def blur_wrap(a, s):
    return ndi.gaussian_filter(a, s, mode="wrap")


def stamp_wrap(dst, patch, cx, cy, mode="max"):
    """Stamps a 2D patch centred at (cx, cy) into dst with wrap-around."""
    h, w = dst.shape[:2]
    ph, pw = patch.shape[:2]
    ys = (np.arange(ph) + int(cy) - ph // 2) % h
    xs = (np.arange(pw) + int(cx) - pw // 2) % w
    ix = np.ix_(ys, xs)
    if mode == "max":
        dst[ix] = np.maximum(dst[ix], patch)
    else:
        dst[ix] = patch
    return ix


# ------------------------------------------------------------------ ground

def grass():
    S = 1024
    rng = random.Random(41)
    base = fft_noise(S, 1.6, 1) * 0.6 + fft_noise(S, 0.8, 2, lo=8) * 0.4
    dead = np.clip((fft_noise(S, 2.2, 3) - 0.56) * 5.0, 0, 1)
    # blades: three tiled canvases drawn 3x3 so that strokes wrap
    big = Image.new("RGB", (S * 3, S * 3), (0, 0, 0))
    hgt = Image.new("L", (S * 3, S * 3), 0)
    d = ImageDraw.Draw(big)
    dh = ImageDraw.Draw(hgt)
    for i in range(15000):
        x = rng.uniform(0, S)
        y = rng.uniform(0, S)
        a = rng.gauss(-math.pi / 2, 0.9)
        ln = rng.uniform(10, 34)
        k = rng.random()
        dd = dead[int(y) % S, int(x) % S]
        if rng.random() < 0.25 + 0.6 * dd:
            col = (int(70 + 60 * k), int(64 + 46 * k), int(30 + 22 * k))      # straw
        else:
            col = (int(22 + 34 * k), int(46 + 52 * k), int(16 + 20 * k))      # green
        x2 = x + math.cos(a) * ln
        y2 = y + math.sin(a) * ln
        lv = int(60 + 195 * k)
        for ox in (-S, 0, S):
            for oy in (-S, 0, S):
                if -40 < x + ox + S < S * 3 + 40:
                    d.line([(x + ox + S, y + oy + S), (x2 + ox + S, y2 + oy + S)], fill=col, width=rng.choice((1, 2, 2, 3)))
                    dh.line([(x + ox + S, y + oy + S), (x2 + ox + S, y2 + oy + S)], fill=lv, width=2)
    blades = np.asarray(big.crop((S, S, 2 * S, 2 * S)), np.float32) / 255.0
    hh = np.asarray(hgt.crop((S, S, 2 * S, 2 * S)), np.float32) / 255.0
    soil = np.stack([0.10 + 0.07 * base, 0.085 + 0.06 * base, 0.05 + 0.035 * base], -1)
    cover = (blades.sum(-1) > 0.01).astype(np.float32)[..., None]
    rgb = soil * (1 - cover) + blades * cover
    rgb *= (0.62 + 0.55 * blur_wrap(base, 6))[..., None]
    rgb = rgb * 0.8
    save(to_img(rgb), "grass.jpg")
    save(normal_map(blur_wrap(hh, 1.0) + 0.5 * base, 5.0), "grass_n.png")


def gravel():
    S = 1024
    rng = np.random.default_rng(7)
    hgt = np.zeros((S, S), np.float32)
    col = np.zeros((S, S, 3), np.float32)
    tone = fft_noise(S, 1.8, 8)
    col[:] = np.stack([0.12 + 0.05 * tone, 0.11 + 0.05 * tone, 0.10 + 0.045 * tone], -1)       # dark wet grit between stones
    n = 5200
    for i in range(n):
        t = i / n                                   # big stones first, small ones on top
        r = rng.uniform(5, 15) * (1.25 - 0.55 * t)
        ry = r * rng.uniform(0.6, 1.0)
        a = rng.uniform(0, math.pi)
        cx = rng.uniform(0, S)
        cy = rng.uniform(0, S)
        m = int(r + 3)
        yy, xx = np.mgrid[-m:m + 1, -m:m + 1].astype(np.float32)
        ca, sa = math.cos(a), math.sin(a)
        u = (xx * ca + yy * sa) / r
        v = (-xx * sa + yy * ca) / ry
        q = u * u + v * v
        dome = np.clip(1.0 - q, 0, 1) ** 0.6
        inside = q < 1.0
        base_h = 0.25 + 0.75 * t * 0.6 + rng.uniform(0, 0.25)
        patch = np.where(inside, base_h + 0.35 * dome, 0).astype(np.float32)
        ys = (np.arange(2 * m + 1) + int(cy) - m) % S
        xs = (np.arange(2 * m + 1) + int(cx) - m) % S
        ix = np.ix_(ys, xs)
        cur = hgt[ix]
        win = patch > cur
        hgt[ix] = np.where(win, patch, cur)
        g = rng.uniform(0.2, 0.62)
        warm = rng.uniform(-0.05, 0.07)
        c = np.array([g + warm, g + warm * 0.5, g - warm * 0.5], np.float32)
        if rng.random() < 0.08:
            c = np.array([0.5, 0.36, 0.26], np.float32) * rng.uniform(0.6, 1.0)      # a brick-red one
        shade = (0.55 + 0.6 * dome)[..., None]
        cc = col[ix]
        col[ix] = np.where(win[..., None], c[None, None, :] * shade, cc)
    col *= (0.75 + 0.5 * fft_noise(S, 1.2, 9, lo=4))[..., None]
    save(to_img(col * 0.82), "gravel.jpg")
    save(normal_map(blur_wrap(hgt, 0.8), 9.0), "gravel_n.png")


def _leaf_patch(rng, r):
    """One dead leaf: (alpha, shade) patches of side 2m+1."""
    m = int(r + 3)
    yy, xx = np.mgrid[-m:m + 1, -m:m + 1].astype(np.float32)
    a = rng.uniform(0, 2 * math.pi)
    ca, sa = math.cos(a), math.sin(a)
    u = (xx * ca + yy * sa) / r
    v = (-xx * sa + yy * ca) / r
    w = 0.42 * (1.0 - u * u) * (1.0 + 0.25 * np.cos(u * 9.0))          # pointed oval with a toothed edge
    w = np.clip(w, 0.0, 1.0)
    inside = (np.abs(u) < 1.0) & (np.abs(v) < w)
    vein = np.exp(-(v / 0.035) ** 2) + 0.5 * np.exp(-((np.abs(v) - np.abs(u) * 0.35) / 0.03) ** 2)
    curl = 1.0 - np.clip(np.abs(v) / (w + 1e-4), 0, 1) ** 2
    return inside, vein, curl, m


def leaves():
    S = 1024
    rng = np.random.default_rng(23)
    tone = fft_noise(S, 1.7, 24)
    col = np.stack([0.075 + 0.05 * tone, 0.06 + 0.04 * tone, 0.045 + 0.03 * tone], -1).astype(np.float32)
    hgt = (0.15 * tone).astype(np.float32)
    pal = np.array([[0.36, 0.2, 0.08], [0.42, 0.27, 0.1], [0.28, 0.15, 0.07], [0.5, 0.36, 0.14], [0.2, 0.12, 0.07],
                    [0.33, 0.25, 0.12], [0.45, 0.22, 0.09]], np.float32)
    n = 1500
    for i in range(n):
        r = rng.uniform(26, 58)
        inside, vein, curl, m = _leaf_patch(rng, r)
        ys = (np.arange(2 * m + 1) + int(rng.uniform(0, S)) - m) % S
        xs = (np.arange(2 * m + 1) + int(rng.uniform(0, S)) - m) % S
        ix = np.ix_(ys, xs)
        c = pal[rng.integers(len(pal))] * rng.uniform(0.55, 1.05)
        shade = (0.7 + 0.45 * curl - 0.3 * np.clip(vein, 0, 1))[..., None]
        col[ix] = np.where(inside[..., None], c[None, None, :] * shade, col[ix])
        lift = i / n * 0.5 + 0.3
        hgt[ix] = np.where(inside, lift + 0.25 * curl - 0.1 * np.clip(vein, 0, 1), hgt[ix])
    col *= (0.7 + 0.5 * fft_noise(S, 1.4, 25, lo=3))[..., None]
    save(to_img(col * 0.85), "leaves.jpg")
    save(normal_map(blur_wrap(hgt, 1.0), 7.0), "leaves_n.png")


def decal_leaves():
    S = 512
    rng = np.random.default_rng(31)
    rgba = np.zeros((S, S, 4), np.float32)
    pal = np.array([[0.36, 0.2, 0.08], [0.42, 0.27, 0.1], [0.28, 0.15, 0.07], [0.5, 0.36, 0.14], [0.22, 0.13, 0.07]], np.float32)
    for i in range(70):
        r = rng.uniform(14, 30)
        inside, vein, curl, m = _leaf_patch(rng, r)
        # denser toward the centre, nothing on the border
        while True:
            cx, cy = rng.normal(S / 2, S / 5.5, 2)
            if m + 2 < cx < S - m - 2 and m + 2 < cy < S - m - 2:
                break
        sl = (slice(int(cy) - m, int(cy) + m + 1), slice(int(cx) - m, int(cx) + m + 1))
        c = pal[rng.integers(len(pal))] * rng.uniform(0.6, 1.05)
        shade = (0.7 + 0.45 * curl - 0.3 * np.clip(vein, 0, 1))[..., None]
        rgba[sl][..., :3] = np.where(inside[..., None], c[None, None, :] * shade, rgba[sl][..., :3])
        rgba[sl][..., 3] = np.where(inside, 1.0, rgba[sl][..., 3])
    img = Image.fromarray(np.clip(rgba * 255 + 0.5, 0, 255).astype(np.uint8), "RGBA")
    save(img, "decal_leaves.png")


def sand():
    S = 512
    a = fft_noise(S, 0.4, 51, lo=20) * 0.5 + fft_noise(S, 1.8, 52) * 0.5
    rgb = np.stack([0.42 + 0.2 * a, 0.36 + 0.18 * a, 0.25 + 0.13 * a], -1)
    rgb *= (0.7 + 0.5 * fft_noise(S, 2.2, 53))[..., None]
    save(to_img(rgb * 0.8), "sand.jpg")


# ------------------------------------------------------------------ wood, stone, bark

def bark():
    S = 512
    ridge = fft_noise(S, 1.3, 61, sx=5.0, sy=0.6, lo=3)
    ridge = np.abs(ridge - 0.5) * 2.0
    fine = fft_noise(S, 0.9, 62, sx=3.0, sy=0.8, lo=12)
    h = 0.75 * ridge + 0.25 * fine
    rgb = np.stack([0.07 + 0.16 * h, 0.06 + 0.13 * h, 0.05 + 0.1 * h], -1)
    moss = np.clip((fft_noise(S, 2.0, 63) - 0.62) * 5, 0, 1)[..., None]
    rgb = rgb * (1 - moss * 0.6) + np.array([0.08, 0.13, 0.05]) * moss * 0.6
    save(to_img(rgb), "bark.jpg")
    save(normal_map(h, 14.0), "bark_n.png")


def clapboard():
    S = 1024
    nb = 8                                              # boards per tile, 15 cm each
    bh = S // nb
    yy = np.arange(S)[:, None].repeat(S, 1)
    v = (yy % bh) / bh                                  # 0 at the top of a board, 1 at its lower lap edge
    grain = fft_noise(S, 1.4, 71, sx=0.15, sy=4.0, lo=2)
    rows = (yy // bh)
    rng = np.random.default_rng(72)
    tone = rng.uniform(0.9, 1.05, nb)[rows]
    paint = np.stack([0.62 * tone, 0.61 * tone, 0.56 * tone], -1) * (0.9 + 0.14 * grain[..., None])
    wood = np.stack([0.36 + 0.12 * grain, 0.34 + 0.11 * grain, 0.31 + 0.1 * grain], -1)
    # paint peels along the grain, more toward the lower edge of each board
    peel_a = fft_noise(S, 1.9, 73, sx=0.6, sy=1.4)
    peel_b = fft_noise(S, 0.8, 74, lo=10, sx=0.35, sy=1.6)
    peel_n = np.zeros((S, S), np.float32)
    shifts = rng.integers(0, S, nb)
    for b in range(nb):                                 # every board flakes on its own
        m = rows == b
        peel_n[m] = (np.roll(peel_a, int(shifts[b]), 1) + 0.3 * np.roll(peel_b, int(shifts[b]) * 3, 1))[m]
    peel = np.clip((peel_n + 0.2 * v - 0.92) * 7.0, 0, 1)
    rgb = paint * (1 - peel[..., None]) + wood * peel[..., None]
    # shadow under each lap, dirt runs
    lap = np.clip(1.0 - v / 0.07, 0, 1)
    rgb *= (1.0 - 0.6 * lap)[..., None]
    runs = np.clip((fft_noise(S, 1.6, 75, sx=4.0, sy=0.25) - 0.58) * 4.0, 0, 1)
    rgb *= (1.0 - 0.3 * runs)[..., None]
    rgb *= (0.85 + 0.3 * fft_noise(S, 2.2, 76))[..., None]
    save(to_img(rgb), "clapboard.jpg")
    h = (1.0 - v) * 0.0 + v * 0.9 - 0.9 * lap + 0.12 * grain - 0.18 * peel
    save(normal_map(blur_wrap(h.astype(np.float32), 0.7), 6.0), "clapboard_n.png")


def planks():
    S = 1024
    nb = 6
    bw = S / nb
    xx = np.arange(S)[None, :].repeat(S, 0)
    rng = np.random.default_rng(81)
    col_i = (xx / bw).astype(int) % nb
    u = (xx % bw) / bw
    off = rng.uniform(0, S, nb)
    grain = np.zeros((S, S), np.float32)
    g0 = fft_noise(S, 1.5, 82, sx=5.0, sy=0.12, lo=2)
    for b in range(nb):                                 # each board its own piece of grain
        m = col_i == b
        grain[m] = np.roll(g0, int(off[b]), 0)[m]
    tone = rng.uniform(0.75, 1.1, nb)[col_i]
    rgb = np.stack([0.2 + 0.2 * grain, 0.19 + 0.185 * grain, 0.17 + 0.16 * grain], -1) * tone[..., None]
    gap = np.clip(1.0 - np.minimum(u, 1.0 - u) / 0.035, 0, 1)
    rgb *= (1.0 - 0.9 * gap)[..., None]
    # knots
    hk = np.zeros((S, S), np.float32)
    for i in range(14):
        cx, cy = rng.uniform(0, S, 2)
        r = rng.uniform(8, 20)
        m_ = int(r * 2.5)
        yy_, xx_ = np.mgrid[-m_:m_ + 1, -m_:m_ + 1].astype(np.float32)
        q = np.sqrt((xx_ / r) ** 2 + (yy_ / (r * 1.5)) ** 2)
        stamp_wrap(hk, np.clip(1.0 - q, 0, 1).astype(np.float32), cx, cy)
    rgb *= (1.0 - 0.6 * hk)[..., None]
    green = np.clip((fft_noise(S, 2.1, 83) - 0.6) * 4, 0, 1)[..., None]            # algae near the damp
    rgb = rgb * (1 - green * 0.35) + np.array([0.1, 0.15, 0.07]) * green * 0.35
    save(to_img(rgb), "planks.jpg")
    save(normal_map(blur_wrap((0.5 * grain - 1.2 * gap - 0.3 * hk).astype(np.float32), 0.7), 6.0), "planks_n.png")


def stone():
    S = 1024
    rng = np.random.default_rng(91)
    n = 120
    pts = rng.uniform(0, S, (n, 2))
    # periodic Voronoi: nearest and second nearest site
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    d1 = np.full((S, S), 1e9, np.float32)
    d2 = np.full((S, S), 1e9, np.float32)
    idx = np.zeros((S, S), np.int32)
    for i, (px, py) in enumerate(pts):
        dx = np.abs(xx - px)
        dx = np.minimum(dx, S - dx)
        dy = np.abs(yy - py) * 1.35                    # stones lie flat
        dy = np.minimum(dy, S * 1.35 - dy)
        d = np.sqrt(dx * dx + dy * dy)
        closer = d < d1
        d2 = np.where(closer, d1, np.minimum(d2, d))
        idx = np.where(closer, i, idx)
        d1 = np.where(closer, d, d1)
    edge = d2 - d1
    mortar = np.clip(1.0 - edge / 9.0, 0, 1)
    tones = rng.uniform(0.55, 1.0, n)[idx]
    warm = rng.uniform(-0.03, 0.05, n)[idx]
    rough = fft_noise(S, 1.3, 92, lo=3)
    st = np.stack([0.3 * tones + warm, 0.29 * tones + warm * 0.5, 0.27 * tones], -1) * (0.7 + 0.6 * rough[..., None])
    mo = np.stack([0.2 + 0.08 * rough, 0.19 + 0.075 * rough, 0.17 + 0.07 * rough], -1)
    rgb = st * (1 - mortar[..., None]) + mo * mortar[..., None]
    damp = np.clip((fft_noise(S, 2.2, 93) - 0.5) * 3, 0, 1)[..., None]
    rgb *= 1.0 - 0.45 * damp
    save(to_img(rgb), "stone.jpg")
    h = np.clip(edge / 14.0, 0, 1) ** 0.5 + 0.25 * rough
    save(normal_map(blur_wrap(h.astype(np.float32), 1.0), 9.0), "stone_n.png")


def car_paint():
    S = 512
    a = fft_noise(S, 1.8, 101)
    b = fft_noise(S, 1.0, 102, lo=6)
    paint = np.stack([0.3 + 0.06 * a, 0.07 + 0.02 * a, 0.07 + 0.02 * a], -1)
    rust = np.stack([0.3 + 0.16 * b, 0.15 + 0.08 * b, 0.06 + 0.03 * b], -1)
    m = np.clip((a * 0.7 + b * 0.5 - 0.72) * 6.0, 0, 1)[..., None]
    rgb = paint * (1 - m) + rust * m
    rgb *= (0.8 + 0.35 * fft_noise(S, 2.4, 103))[..., None]
    save(to_img(rgb), "car_paint.jpg")


# ------------------------------------------------------------------ trees and tufts (alpha cut-outs)

def _branch(d, rng, x, y, ang, ln, w, depth, col):
    if depth == 0 or ln < 4:
        return
    segs = 3
    for s in range(segs):
        ang += rng.gauss(0, 0.1)
        x2 = x + math.cos(ang) * ln / segs
        y2 = y + math.sin(ang) * ln / segs
        ww = max(1, int(round(w * (1 - 0.25 * s / segs))))
        d.line([(x, y), (x2, y2)], fill=col, width=ww)
        if ww > 2:
            d.ellipse([x2 - ww / 2, y2 - ww / 2, x2 + ww / 2, y2 + ww / 2], fill=col)
        x, y = x2, y2
    n = 2 if rng.random() < 0.7 else 3
    for i in range(n):
        da = rng.uniform(0.25, 0.75) * (1 if i % 2 == 0 else -1) + rng.gauss(0, 0.12)
        _branch(d, rng, x, y, ang + da - 0.06 * (ang + math.pi / 2), ln * rng.uniform(0.62, 0.8), w * rng.uniform(0.55, 0.72),
                depth - 1, col)


def _bare_tree(seed, w=512, h=1024):
    rng = random.Random(seed)
    img = Image.new("RGBA", (w * 2, h * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    col = (10 + rng.randint(0, 6), 9 + rng.randint(0, 5), 8 + rng.randint(0, 4), 255)
    x = w + rng.uniform(-20, 20)
    # trunk, slightly leaning
    _branch(d, rng, x, h * 2 - 2, -math.pi / 2 + rng.uniform(-0.1, 0.1), h * 0.62, 46 + rng.uniform(-8, 10), 9, col)
    # root flare
    d.polygon([(x - 44, h * 2), (x - 20, h * 2 - 70), (x + 20, h * 2 - 70), (x + 44, h * 2)], fill=col)
    return img.resize((w, h), Image.LANCZOS)


def _fir(seed, w=512, h=1024):
    rng = random.Random(seed)
    img = Image.new("RGBA", (w * 2, h * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    col = (7, 11, 9, 255)
    cx = w
    d.rectangle([cx - 14, h * 2 - 260, cx + 14, h * 2], fill=(11, 9, 8, 255))
    tiers = 20
    for i in range(tiers):
        t = i / (tiers - 1)
        y = 60 + (h * 2 - 330) * t
        half = 26 + (w * 0.86) * t ** 0.85 * rng.uniform(0.8, 1.0)
        drop = 110 + 60 * t
        # a ragged skirt of drooping boughs (each tier starts well inside the one above: no see-through bands)
        pts = [(cx - half * 0.35, y - 150), (cx, y - 190), (cx + half * 0.35, y - 150)]
        k = 9
        for j in range(k + 1):
            u = j / k * 2 - 1
            px = cx + u * half
            py = y + drop * (abs(u) ** 1.3) * 0.55 + rng.uniform(-14, 22) + (40 if j % 2 else 0)
            pts.append((px, py))
        d.polygon(pts, fill=col)
        for j in range(26):                                 # loose needles / gaps along the edge
            u = rng.uniform(-1, 1)
            px = cx + u * half
            py = y + drop * (abs(u) ** 1.3) * 0.55 + rng.uniform(0, 50)
            d.line([(px, py - 30), (px + rng.uniform(-12, 12), py + rng.uniform(14, 46))], fill=col, width=rng.choice((3, 4, 6)))
    return img.resize((w, h), Image.LANCZOS)


def _bush(seed, w=512, h=512):
    rng = random.Random(seed)
    img = Image.new("RGBA", (w * 2, h * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    col = (12, 10, 8, 255)
    for i in range(9):
        x = w + rng.uniform(-90, 90)
        _branch(d, rng, x, h * 2 - 2, -math.pi / 2 + rng.uniform(-0.7, 0.7), h * rng.uniform(0.5, 0.8), 12, 7, col)
    return img.resize((w, h), Image.LANCZOS)


def _hedge(seed, w=512, h=512):
    rng = np.random.default_rng(seed)
    n = fft_noise((h, w), 1.2, seed, lo=4)
    yy = np.linspace(0, 1, h)[:, None]
    top = 0.14 + 0.1 * fft_noise((1, w), 1.5, seed + 1)[0][None, :]
    a = ((yy > top) & ((n > 0.33) | (yy > 0.7))).astype(np.float32)
    holes = (fft_noise((h, w), 0.6, seed + 2, lo=14) > 0.72) & (yy < 0.75)
    a[holes] = 0.0
    a[:, 0] = a[:, -1]
    g = 0.03 + 0.06 * n
    rgba = np.stack([g * 0.8, g * 1.1, g * 0.75, a], -1)
    return Image.fromarray(np.clip(rgba * 255 + 0.5, 0, 255).astype(np.uint8), "RGBA")


def trees():
    atlas = Image.new("RGBA", (2048, 2048), (0, 0, 0, 0))
    for i in range(4):
        atlas.paste(_bare_tree(301 + i * 17), (i * 512, 0))
    atlas.paste(_fir(411), (0, 1024))
    atlas.paste(_fir(433), (512, 1024))
    atlas.paste(_bush(455), (1024, 1024))
    atlas.paste(_hedge(477), (1536, 1024))
    atlas.paste(_bush(499), (1024, 1536))
    atlas.paste(_hedge(521), (1536, 1536))
    # colour bleeding into the transparent texels (no bright halo in the mips)
    a = np.asarray(atlas, np.float32)
    a[..., 0][a[..., 3] < 8] = 10
    a[..., 1][a[..., 3] < 8] = 10
    a[..., 2][a[..., 3] < 8] = 9
    save(Image.fromarray(a.astype(np.uint8), "RGBA"), "trees.png")


def tuft():
    W, H = 1024, 256
    img = Image.new("RGBA", (W * 2, H * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    rng = random.Random(55)
    for c in range(4):
        cx = c * 512 + 256
        n = 70 if c < 3 else 26
        for i in range(n):
            x = cx + rng.gauss(0, 60)
            a = -math.pi / 2 + rng.gauss(0, 0.45)
            ln = rng.uniform(150, 480) * (0.6 if c == 1 else 1.0)
            k = rng.random()
            col = (int(34 + 50 * k), int(52 + 60 * k), int(22 + 22 * k), 255) if rng.random() < 0.6 else (int(92 + 50 * k), int(84 + 40 * k), int(40 + 20 * k), 255)
            px, py = x, H * 2
            segs = 6
            for s in range(segs):
                a += rng.gauss(0, 0.07) + (0.05 if a > -math.pi / 2 else -0.05)
                nx = px + math.cos(a) * ln / segs
                ny = py + math.sin(a) * ln / segs
                d.line([(px, py), (nx, ny)], fill=col, width=max(1, int(7 * (1 - s / segs))))
                px, py = nx, ny
            if c == 3:                                      # a seed head
                d.ellipse([px - 7, py - 16, px + 7, py + 8], fill=(90, 76, 44, 255))
    img = img.resize((W, H), Image.LANCZOS)
    a = np.asarray(img, np.float32).copy()
    for ch, v in zip(range(3), (50, 70, 30)):
        a[..., ch][a[..., 3] < 8] = v
    save(Image.fromarray(a.astype(np.uint8), "RGBA"), "tuft.png")


# ------------------------------------------------------------------ glass, prints, signs

def glass():
    S = 512
    grime = fft_noise(S, 1.9, 111)
    fine = fft_noise(S, 0.7, 112, lo=10)
    runs = np.clip((fft_noise(S, 1.5, 113, sx=5.0, sy=0.2) - 0.52) * 3.5, 0, 1)
    yy = np.linspace(0, 1, S)[:, None]
    low = np.clip((yy - 0.55) / 0.45, 0, 1) ** 1.5              # algae creeping up from the sill
    alpha = np.clip(0.16 + 0.34 * grime + 0.1 * fine + 0.25 * runs + 0.4 * low, 0.1, 0.92)
    g = 0.5 + 0.3 * grime
    rgb = np.stack([0.3 * g + 0.02, 0.36 * g + 0.05 * low, 0.3 * g], -1)
    rgba = np.concatenate([rgb, alpha[..., None]], -1)
    save(Image.fromarray(np.clip(rgba * 255 + 0.5, 0, 255).astype(np.uint8), "RGBA"), "glass.png")


def handprint():
    S = 256
    img = Image.new("L", (S * 2, S * 2), 0)
    d = ImageDraw.Draw(img)
    rng = random.Random(77)
    for hx, tilt, flip in ((150, -0.2, 1), (360, 0.15, -1)):
        hy = 300 + rng.uniform(-20, 20)
        d.ellipse([hx - 44, hy - 30, hx + 44, hy + 62], fill=235)                    # palm
        for f, (dx, ln, w) in enumerate(((-36, 78, 17), (-13, 96, 18), (11, 100, 18), (33, 84, 16))):
            a = -math.pi / 2 + tilt + (f - 1.5) * 0.11
            x0, y0 = hx + dx, hy - 22
            x1, y1 = x0 + math.cos(a) * ln, y0 + math.sin(a) * ln
            d.line([(x0, y0), (x1, y1)], fill=235, width=w)
            d.ellipse([x1 - w / 2, y1 - w / 2, x1 + w / 2, y1 + w / 2], fill=235)
        a = -math.pi / 2 + tilt - flip * 1.05                                         # thumb
        x0, y0 = hx - flip * 40, hy + 18
        d.line([(x0, y0), (x0 + math.cos(a) * 58, y0 + math.sin(a) * 58)], fill=235, width=20)
        # dragged downward
        for i in range(5):
            xs = hx + rng.uniform(-40, 40)
            d.line([(xs, hy + 40), (xs + rng.uniform(-6, 6), hy + 120 + rng.uniform(0, 60))], fill=110, width=rng.choice((8, 12, 16)))
    a = np.asarray(img.filter(ImageFilter.GaussianBlur(3)).resize((S, S), Image.LANCZOS), np.float32) / 255.0
    a *= 0.65 + 0.5 * fft_noise(S, 1.0, 78, lo=6)
    rgba = np.stack([np.full_like(a, 0.74), np.full_like(a, 0.76), np.full_like(a, 0.72), np.clip(a, 0, 1)], -1)
    save(Image.fromarray(np.clip(rgba * 255 + 0.5, 0, 255).astype(np.uint8), "RGBA"), "handprint.png")


def _font(size):
    for p in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"):
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def toolboard():
    W, H = 1024, 512
    rng = np.random.default_rng(121)
    n = fft_noise((H, W), 1.6, 122)
    base = np.stack([0.34 + 0.1 * n, 0.27 + 0.08 * n, 0.17 + 0.06 * n], -1)
    img = to_img(base)
    d = ImageDraw.Draw(img)
    for y in range(24, H, 32):                                   # peg holes
        for x in range(24, W, 32):
            d.ellipse([x - 3, y - 3, x + 3, y + 3], fill=(40, 30, 20))
    ink = (226, 220, 196)
    dark = (30, 26, 22)
    # hammer (hanging), saw, pliers, wrench, trowel: flat silhouettes of the tools still there
    d.rectangle([90, 90, 104, 330], fill=dark)
    d.rectangle([60, 70, 150, 110], fill=dark)
    d.polygon([(220, 110), (470, 150), (470, 200), (220, 230)], fill=dark)
    d.rectangle([180, 120, 228, 220], fill=(60, 36, 20))
    d.line([(560, 100), (590, 330)], fill=dark, width=14)
    d.line([(600, 100), (575, 330)], fill=dark, width=14)
    d.rectangle([690, 90, 708, 300], fill=dark)
    d.ellipse([672, 70, 726, 124], outline=dark, width=14)
    # the empty outline: long-handled bolt cutters, painted in pale paint, nothing hanging in it
    pts_a = [(820, 80), (838, 80), (852, 200), (880, 420), (858, 424), (836, 210)]
    pts_b = [(880, 80), (862, 80), (848, 200), (820, 420), (842, 424), (864, 210)]
    d.line(pts_a + [pts_a[0]], fill=ink, width=5)
    d.line(pts_b + [pts_b[0]], fill=ink, width=5)
    f = _font(30)
    f2 = _font(24)
    d.text((770, 440), "COUPE-BOULON", fill=ink, font=f)
    d.text((806, 478), "→ AU CAVEAU", fill=(214, 96, 70), font=f2)
    d.text((60, 440), "REMISE", fill=ink, font=f)
    a = np.asarray(img, np.float32) / 255.0
    a *= (0.75 + 0.4 * fft_noise((H, W), 2.0, 123))[..., None]
    save(to_img(a), "toolboard.jpg", 90)


def window_glow():
    W, H = 256, 384
    xx = np.linspace(-1, 1, W)[None, :].repeat(H, 0)
    yy = np.linspace(-1, 1, H)[:, None].repeat(W, 1)
    folds = 0.75 + 0.25 * np.sin(xx * 46.0 + 1.2 * np.sin(yy * 3.0))
    glow = np.exp(-(xx * xx * 1.2 + (yy + 0.1) ** 2 * 0.9))
    v = np.clip(0.25 + 0.75 * glow, 0, 1) * folds
    gapc = np.exp(-(xx / 0.035) ** 2) * 0.9                       # the slit between the two curtains
    rgb = np.stack([v * 1.0 + gapc, v * 0.62 + gapc * 0.8, v * 0.28 + gapc * 0.5], -1)
    save(to_img(np.clip(rgb, 0, 1)), "window_glow.png")


JOBS = [("grass", grass), ("gravel", gravel), ("leaves", leaves), ("decal_leaves", decal_leaves), ("sand", sand), ("bark", bark),
        ("clapboard", clapboard), ("planks", planks), ("stone", stone), ("car_paint", car_paint), ("trees", trees), ("tuft", tuft),
        ("glass", glass), ("handprint", handprint), ("toolboard", toolboard), ("window_glow", window_glow)]

IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="res://assets/dehors/textures/{name}"

[params]

compress/mode={mode}
compress/high_quality={hq}
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map={nm}
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
"""
HQ = {"toolboard.jpg", "trees.png", "handprint.png"}


def write_imports():
    for name in WRITTEN:
        path = os.path.join(OUT, name + ".import")
        if os.path.exists(path):
            continue                                            # keep the uid Godot assigned
        with open(path, "w") as fh:
            fh.write(IMPORT.format(name=name, mode=2, hq="true" if name in HQ else "false", nm=1 if name.endswith("_n.png") else 0))


if __name__ == "__main__":
    for name, fn in JOBS:
        if want(name):
            fn()
    write_imports()
