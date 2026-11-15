#!/usr/bin/env python3
"""Procedural textures of the three extra garderie rooms (dortoir, bureau, toilettes). Re-runnable, deterministic (seeded).

    python3 -I pc/scripts/garderie/tools/gen_rooms_textures.py [out_dir] [--fonts DIR] [--only name,name]

Defaults: out_dir = pc/assets/garderie/textures, fonts = pc/assets/fonts (Special Elite = typed text, Caveat = handwriting;
both only baked into the textures). Then run write_imports.py on the folder and `godot --headless --path pc --import`.

  tiles_wall.jpg / _n.png / _orm.jpg   1024, seamless, 1.2 m: 8x8 glazed 15 cm wall tiles, grout, cracks, chips, rust streaks
  tiles_floor.jpg / _n.png / _orm.jpg  1024, seamless, 1.2 m: 12x12 matte 10 cm floor tiles, grey-green / teal checker
  wallpaper_nursery.jpg / _n.png       1024, seamless, 1.06 m (two 53 cm strips): stars, moons, clouds, aged
  carpet.jpg / _n.png                  512, seamless, 0.6 m: low-pile blue-grey commercial carpet
  star_cookie.png                      512, light-projector cookie of the night-light (stars + crescent on black)
  docs_atlas.jpg                       1024, 2x2 atlas of office papers (presence sheet, nap schedule, notice, phone list)
  drawings2.jpg                        1024, 2x2 atlas of children's crayon drawings
Normal maps are OpenGL convention (+Y up), ORM = R ambient occlusion, G roughness, B metal (0).
"""
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
PC = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
ARGV = sys.argv[1:]
OUT = ARGV[0] if ARGV and not ARGV[0].startswith("--") else os.path.join(PC, "assets", "garderie", "textures")


def arg(name, default=None):
    if name in ARGV:
        i = ARGV.index(name)
        return ARGV[i + 1] if i + 1 < len(ARGV) else default
    return default


FONTS = arg("--fonts", os.path.join(PC, "assets", "fonts"))
ONLY = set(filter(None, (arg("--only", "") or "").split(",")))
os.makedirs(OUT, exist_ok=True)


def want(name):
    return not ONLY or name in ONLY


def save(img, name, quality=88):
    path = os.path.join(OUT, name)
    if name.endswith(".jpg"):
        img.convert("RGB").save(path, quality=quality, optimize=True, progressive=False)
    else:
        img.save(path, optimize=True)
    print("wrote", name, img.size)


def font(kind, size):
    rel = {"type": "special_elite/SpecialElite-Regular.ttf", "hand": "caveat/Caveat-Medium.ttf",
           "hand_b": "caveat/Caveat-Bold.ttf"}[kind]
    return ImageFont.truetype(os.path.join(FONTS, rel), size)


# ------------------------------------------------------------------ helpers (all noise is periodic -> tileable)

def fft_noise(size, beta, seed, lo=1.0, hi=None, sx=1.0, sy=1.0):
    """Periodic 1/f^beta noise in [0,1]; lo/hi = frequency band (cycles per tile); sx/sy stretch the grain."""
    rng = np.random.default_rng(seed)
    fy = np.fft.fftfreq(size)[:, None] * size * sy
    fx = np.fft.fftfreq(size)[None, :] * size * sx
    f = np.sqrt(fx * fx + fy * fy)
    amp = np.where(f > 0, 1.0 / np.maximum(f, 1e-6) ** beta, 0.0)
    amp[f < lo] = 0.0
    if hi:
        amp[f > hi] = 0.0
    spec = amp * np.exp(1j * rng.uniform(0, 2 * np.pi, (size, size)))
    n = np.real(np.fft.ifft2(spec))
    n -= n.min()
    n /= max(n.max(), 1e-9)
    return n.astype(np.float32)


def eq(n):
    """Histogram-equalise a noise field to a uniform [0,1] distribution (predictable thresholds)."""
    flat = n.ravel()
    order = np.argsort(flat)
    out = np.empty_like(flat)
    out[order] = np.linspace(0, 1, flat.size, dtype=np.float32)
    return out.reshape(n.shape)


def blur_wrap(a, radius):
    h, w = a.shape
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    g = np.exp(-2.0 * (np.pi ** 2) * (radius ** 2) * (fx * fx + fy * fy))
    return np.real(np.fft.ifft2(np.fft.fft2(a) * g)).astype(np.float32)


def normal_from_height(hgt, strength):
    dx = (np.roll(hgt, -1, axis=1) - np.roll(hgt, 1, axis=1)) * 0.5
    dy = (np.roll(hgt, -1, axis=0) - np.roll(hgt, 1, axis=0)) * 0.5
    nx = -dx * strength
    ny = dy * strength          # image y points down -> +Y up (OpenGL)
    nz = np.ones_like(hgt)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    rgb = np.stack([nx / ln, ny / ln, nz / ln], axis=-1) * 0.5 + 0.5
    return Image.fromarray(np.clip(rgb * 255.0 + 0.5, 0, 255).astype(np.uint8), "RGB")


def sstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def mix(a, b, t):
    if t.ndim == 2:
        t = t[..., None]
    return a * (1.0 - t) + np.asarray(b, np.float32) * t


def rgb_img(a):
    return Image.fromarray(np.clip(a * 255.0 + 0.5, 0, 255).astype(np.uint8), "RGB")


def arr(img):
    return np.asarray(img, np.float32) / 255.0


# ------------------------------------------------------------------ ceramic tiles (wall + floor)

def tile_grid(S, n, r_corner):
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    p = S / n
    u = (xx + 0.5) / p
    v = (yy + 0.5) / p
    ix = np.floor(u).astype(np.int32) % n
    iy = np.floor(v).astype(np.int32) % n
    fu = u - np.floor(u)
    fv = v - np.floor(v)
    du = np.minimum(fu, 1 - fu) * p
    dv = np.minimum(fv, 1 - fv) * p
    q = np.hypot(np.maximum(r_corner - du, 0), np.maximum(r_corner - dv, 0))
    d = np.where((du < r_corner) | (dv < r_corner), r_corner - q, np.minimum(du, dv))   # px to the grout axis
    return xx, yy, ix, iy, fu, fv, d, p


def crack_and_chips(S, p, rng, crack_tiles, chip_corners, chip_size):
    """Hairline cracks crossing whole tiles + broken corners. Returns (crack, chip) masks in [0,1]."""
    crack = Image.new("L", (S, S), 0)
    dc = ImageDraw.Draw(crack)
    for tx, ty in crack_tiles:
        x0, y0 = tx * p, ty * p
        if rng.random() < 0.5:   # top edge -> bottom edge
            a = (x0 + rng.uniform(0.2, 0.8) * p, y0 + 2)
            b = (x0 + rng.uniform(0.2, 0.8) * p, y0 + p - 2)
        else:                    # left edge -> right edge
            a = (x0 + 2, y0 + rng.uniform(0.2, 0.8) * p)
            b = (x0 + p - 2, y0 + rng.uniform(0.2, 0.8) * p)
        pts = []
        k = 9
        for i in range(k + 1):
            t = i / k
            j = 0.0 if i in (0, k) else p * 0.045
            pts.append((a[0] + (b[0] - a[0]) * t + rng.uniform(-j, j), a[1] + (b[1] - a[1]) * t + rng.uniform(-j, j)))
        dc.line(pts, fill=255, width=1)
        m = pts[rng.integers(3, 6)]           # one short branch
        ang = rng.uniform(0, 2 * math.pi)
        ln = p * rng.uniform(0.18, 0.3)
        e = (min(max(m[0] + math.cos(ang) * ln, x0 + 3), x0 + p - 3), min(max(m[1] + math.sin(ang) * ln, y0 + 3), y0 + p - 3))
        mid = ((m[0] + e[0]) / 2 + rng.uniform(-3, 3), (m[1] + e[1]) / 2 + rng.uniform(-3, 3))
        dc.line([m, mid, e], fill=200, width=1)
    chip = Image.new("L", (S, S), 0)
    dh = ImageDraw.Draw(chip)
    for tx, ty, cx, cy in chip_corners:
        X, Y = (tx + cx) * p, (ty + cy) * p
        sx, sy = (1 if cx == 0 else -1), (1 if cy == 0 else -1)
        a, b = chip_size * rng.uniform(0.75, 1.2), chip_size * rng.uniform(0.7, 1.15)
        pts = [(X + sx * 1, Y + sy * 1), (X + sx * a, Y + sy * 1), (X + sx * a * 0.78, Y + sy * b * 0.3),
               (X + sx * a * 0.5, Y + sy * b * 0.62), (X + sx * a * 0.24, Y + sy * b * 0.8), (X + sx * 1, Y + sy * b)]
        dh.polygon(pts, fill=255)
    cr = np.clip(arr(crack.filter(ImageFilter.GaussianBlur(0.55))) * 2.2, 0, 1)
    ch = arr(chip.filter(ImageFilter.GaussianBlur(0.8)))
    return cr, ch


def gen_tiles_wall():
    S, n = 1024, 8
    rng = np.random.default_rng(7101)
    xx, yy, ix, iy, fu, fv, d, p = tile_grid(S, n, 5.0)
    g2 = 1.5                                            # grout half width (px) -> ~3 mm joint
    tile = sstep(g2 - 0.7, g2 + 0.7, d)
    bevel = sstep(g2 - 0.2, g2 + 4.5, d)
    tone = rng.normal(0, 1, (n, n)).astype(np.float32)[iy, ix]
    warm = rng.normal(0, 1, (n, n)).astype(np.float32)[iy, ix]
    rtile = rng.uniform(0, 1, (n, n)).astype(np.float32)[iy, ix]
    tiltx = rng.normal(0, 1, (n, n)).astype(np.float32)[iy, ix]
    tilty = rng.normal(0, 1, (n, n)).astype(np.float32)[iy, ix]
    mott = fft_noise(S, 1.8, 7102, lo=2, hi=30)
    speck = fft_noise(S, 0.0, 7103, lo=140)
    gr_lo = eq(fft_noise(S, 1.6, 7104, lo=1, hi=9))
    gr_hi = fft_noise(S, 1.0, 7105, lo=10, hi=200)
    gr_md = eq(fft_noise(S, 1.9, 7106, lo=3))

    col = np.empty((S, S, 3), np.float32)
    col[:] = np.array([0.868, 0.858, 0.800], np.float32)
    col *= (1.0 + 0.030 * tone)[..., None]
    col[..., 0] *= 1.0 + 0.012 * warm
    col[..., 2] *= 1.0 - 0.018 * warm
    col *= (0.955 + 0.09 * mott)[..., None]
    col *= (0.988 + 0.024 * speck)[..., None]
    # a few tiles are replacements / more yellowed
    old = (rtile > 0.86).astype(np.float32)
    col = mix(col, col * np.array([1.0, 0.975, 0.90]), old * 0.5)

    # grime: film on the glaze, thick near the joints
    grime = np.clip(gr_lo * 1.55 - 0.45, 0, 1) * (0.45 + 0.55 * gr_hi)
    edge = np.exp(-np.maximum(d - g2, 0) / 6.5)
    edge2 = np.exp(-np.maximum(d - g2, 0) / 22.0)
    dirt = np.clip(edge * (0.30 + 0.9 * grime) + edge2 * grime * 0.45, 0, 1)
    col = mix(col, col * np.array([0.50, 0.42, 0.30]), dirt * 0.85)
    film = sstep(0.45, 1.0, gr_md) ** 2 * (0.4 + 0.6 * gr_lo)
    col = mix(col, col * np.array([0.80, 0.74, 0.60]), film * 0.5)
    # soap / splash specks
    sp = np.clip(fft_noise(S, 0.6, 7107, lo=40, hi=200) * 6.0 - 4.3, 0, 1) * gr_lo
    col = mix(col, col * np.array([0.62, 0.55, 0.44]), sp * 0.5)

    # rust / dirty-water streaks running down (wrap in x and y)
    rust = np.zeros((S, S), np.float32)
    grey = np.zeros((S, S), np.float32)
    spots = np.zeros((S, S), np.float32)
    specs = [(0.19, 2, 520, 9.0, 1.0, 0), (0.455, 5, 380, 6.5, 0.8, 0), (0.80, 1, 640, 11.0, 0.9, 0),
             (0.62, 6, 300, 8.0, 0.8, 1), (0.33, 4, 450, 14.0, 0.7, 1)]
    for k, (xr, row, L, w, amp, kind) in enumerate(specs):
        x0 = xr * S
        y0 = row * p + 1.0
        ty = (yy - y0) % S
        t = ty / L
        wob = 5.0 * np.sin(ty / 61.0 + k * 1.7) + 2.5 * np.sin(ty / 23.0 + k)
        dx = ((xx - x0 - wob + S / 2) % S) - S / 2
        prof = np.exp(-(dx / (w * (0.7 + 1.1 * t))) ** 2)
        fall = np.where(t < 1.0, (1.0 - np.clip(t, 0, 1)) ** 1.4 * np.clip(ty / 5.0, 0, 1), 0.0)
        fine = 0.55 + 0.45 * np.sin(dx * 1.3 + k * 2.0) * np.sin(dx * 0.47 + 1.0)   # ragged rivulets inside the streak
        s = prof * fall * amp * (0.6 + 0.4 * gr_hi) * (0.75 + 0.25 * fine)
        if kind == 0:
            rust = np.maximum(rust, s)
            dy0 = ((yy - y0 + S / 2) % S) - S / 2
            spots = np.maximum(spots, np.exp(-((dx / 5.0) ** 2 + (dy0 / 3.5) ** 2)))
        else:
            grey = np.maximum(grey, s)
    col = mix(col, col * np.array([0.72, 0.47, 0.24]), np.clip(rust * 1.15, 0, 1) * 0.8)
    col = mix(col, col * np.array([0.60, 0.56, 0.48]), grey * 0.6)

    # grout
    gcol = np.empty((S, S, 3), np.float32)
    gcol[:] = np.array([0.285, 0.275, 0.255], np.float32)
    gcol *= (0.72 + 0.55 * gr_hi)[..., None]
    mould = np.clip(gr_lo * 2.4 - 1.25, 0, 1)
    gcol = mix(gcol, np.array([0.075, 0.07, 0.06]), mould * 0.85)
    gcol = mix(gcol, gcol * np.array([0.85, 0.55, 0.32]), np.clip(rust * 1.5, 0, 1) * 0.7)
    gcol = mix(gcol, np.array([0.20, 0.10, 0.05]), spots * 0.9)

    crack, chip = crack_and_chips(S, p, rng, [(2, 1), (5, 4), (1, 6)], [(6, 2, 0, 1), (3, 6, 1, 0)], 22.0)
    crack *= tile
    chip *= tile
    halo = np.clip(blur_wrap(crack, 2.5) * 2.2, 0, 1)
    col = mix(col, col * np.array([0.72, 0.64, 0.52]), halo * 0.5)
    col = mix(col, np.array([0.16, 0.13, 0.10]), crack * 0.85)
    bisc = np.array([0.56, 0.47, 0.37], np.float32) * (0.65 + 0.6 * gr_hi)[..., None]
    chip_edge = np.clip(chip * (1 - chip) * 4.0, 0, 1)
    col = mix(col, bisc, chip)
    col = mix(col, np.array([0.22, 0.18, 0.14]), chip_edge * 0.6)
    col = mix(col, np.array([0.20, 0.10, 0.05]), spots * tile * 0.75)

    out = mix(gcol, col * (0.84 + 0.16 * bevel)[..., None], tile)
    save(rgb_img(out), "tiles_wall.jpg", 88)

    pillow = (1 - (2 * fu - 1) ** 2) * (1 - (2 * fv - 1) ** 2)
    h = bevel * (1.0 + 0.25 * pillow + 0.22 * (tiltx * (fu - 0.5) + tilty * (fv - 0.5)))
    h += (mott - 0.5) * 0.05 * tile
    h -= crack * 0.45 + chip * 0.6 * (0.7 + 0.6 * gr_hi)
    h += (gr_hi - 0.5) * 0.22 * (1 - tile)
    save(normal_from_height(h.astype(np.float32), 5.0), "tiles_wall_n.png")

    ao = (0.50 + 0.50 * sstep(g2 - 0.5, g2 + 7.0, d)) * (1 - 0.25 * chip) * (1 - 0.3 * crack)
    r_tile = np.clip(0.215 + 0.04 * (rtile - 0.5) * 2 + 0.05 * (mott - 0.5), 0.15, 0.30)
    r_tile = r_tile + np.clip(dirt * 0.75 + film * 0.5 + rust * 0.5 + grey * 0.4 + sp * 0.5, 0, 1) * (0.86 - r_tile)
    r_tile = np.maximum(r_tile, np.maximum(crack, chip) * 0.9)
    r_grout = np.clip(0.90 + (gr_hi - 0.5) * 0.10, 0.85, 0.95)
    rough = r_grout * (1 - tile) + r_tile * tile
    orm = np.stack([ao, rough, np.zeros_like(ao)], -1)
    save(rgb_img(orm), "tiles_wall_orm.jpg", 90)


def gen_tiles_floor():
    S, n = 1024, 12
    rng = np.random.default_rng(7201)
    xx, yy, ix, iy, fu, fv, d, p = tile_grid(S, n, 3.0)
    g2 = 1.5
    tile = sstep(g2 - 0.7, g2 + 0.7, d)
    bevel = sstep(g2 - 0.2, g2 + 3.2, d)
    chk = ((ix + iy) % 2).astype(np.float32)
    tone = rng.normal(0, 1, (n, n)).astype(np.float32)[iy, ix]
    hue = rng.normal(0, 1, (n, n)).astype(np.float32)[iy, ix]
    tiltx = rng.normal(0, 1, (n, n)).astype(np.float32)[iy, ix]
    tilty = rng.normal(0, 1, (n, n)).astype(np.float32)[iy, ix]
    speck = fft_noise(S, 0.0, 7202, lo=110)
    mott = fft_noise(S, 1.5, 7203, lo=6, hi=80)
    w_lo = eq(fft_noise(S, 1.7, 7204, lo=1, hi=7))
    w_md = eq(fft_noise(S, 1.2, 7205, lo=5, hi=50))
    hi = fft_noise(S, 0.9, 7206, lo=20, hi=260)

    pale = np.array([0.585, 0.625, 0.555], np.float32)
    teal = np.array([0.120, 0.255, 0.265], np.float32)
    col = mix(np.broadcast_to(pale, (S, S, 3)).copy(), teal, chk)
    col *= (1.0 + 0.05 * tone)[..., None]
    col[..., 1] *= 1.0 + 0.02 * hue
    col[..., 2] *= 1.0 - 0.03 * hue
    col *= (0.90 + 0.20 * speck)[..., None] * (0.93 + 0.14 * mott)[..., None]
    # wear: the matte glaze of the dark tiles is rubbed pale in the traffic zones, mostly in the tile centres
    centre = sstep(0.0, 26.0, d)
    wear = np.clip(w_lo * 1.6 - 0.55, 0, 1) * (0.35 + 0.65 * w_md) * (0.35 + 0.65 * centre)
    col = mix(col, np.array([0.33, 0.39, 0.37]), wear * chk * 0.62)
    col = mix(col, col * np.array([1.08, 1.06, 1.02]), wear * (1 - chk) * 0.5)
    # dirt: brown-grey film, heavier near the joints and in patches
    edge = np.exp(-np.maximum(d - g2, 0) / 5.0)
    patch = np.clip((1 - w_lo) * 1.7 - 0.75, 0, 1)
    dirt = np.clip(edge * (0.35 + 0.6 * w_md) + patch * (0.35 + 0.65 * hi), 0, 1)
    dcol = np.array([0.20, 0.17, 0.13], np.float32)
    col = mix(col, col * 0.45 + dcol * 0.55, dirt * 0.62)
    stain = np.clip(eq(fft_noise(S, 1.9, 7207, lo=2, hi=6)) * 9.0 - 8.1, 0, 1)
    ring = np.clip(stain * (1 - stain) * 4, 0, 1)
    col = mix(col, col * np.array([0.60, 0.52, 0.42]), stain * 0.55 + ring * 0.25)
    grit = np.clip(fft_noise(S, 0.3, 7208, lo=60) * 8.0 - 5.7, 0, 1)
    col = mix(col, np.array([0.10, 0.09, 0.08]), grit * 0.45)

    gcol = np.empty((S, S, 3), np.float32)
    gcol[:] = np.array([0.115, 0.105, 0.092], np.float32)
    gcol *= (0.65 + 0.7 * hi)[..., None]
    gcol = mix(gcol, np.array([0.24, 0.22, 0.19]), np.clip(w_md * 2 - 1.3, 0, 1) * 0.6)   # dusty, lighter joints

    crack, chip = crack_and_chips(S, p, rng, [(3, 2), (8, 7), (10, 3)],
                                  [(5, 5, 0, 0), (1, 9, 1, 1), (7, 1, 1, 0), (10, 10, 0, 1)], 15.0)
    crack *= tile
    chip *= tile
    col = mix(col, np.array([0.07, 0.06, 0.05]), crack * 0.85)
    bisc = np.array([0.50, 0.38, 0.29], np.float32) * (0.6 + 0.6 * hi)[..., None]
    col = mix(col, bisc, chip)
    col = mix(col, np.array([0.10, 0.08, 0.07]), np.clip(chip * (1 - chip) * 4, 0, 1) * 0.6)

    out = mix(gcol, col * (0.80 + 0.20 * bevel)[..., None], tile)
    save(rgb_img(out), "tiles_floor.jpg", 88)

    h = bevel * (1.0 + 0.10 * (1 - (2 * fu - 1) ** 2) * (1 - (2 * fv - 1) ** 2) + 0.20 * (tiltx * (fu - 0.5) + tilty * (fv - 0.5)))
    h += ((speck - 0.5) * 0.06 + (mott - 0.5) * 0.08) * tile
    h -= crack * 0.5 + chip * 0.65 * (0.7 + 0.6 * hi) + wear * chk * 0.03
    h += (hi - 0.5) * 0.3 * (1 - tile)
    save(normal_from_height(h.astype(np.float32), 4.0), "tiles_floor_n.png")

    ao = (0.50 + 0.50 * sstep(g2 - 0.5, g2 + 6.0, d)) * (1 - 0.3 * chip) * (1 - 0.3 * crack) * (1 - 0.12 * dirt)
    r_tile = np.clip(0.62 + 0.05 * tone + 0.10 * (speck - 0.5) + 0.12 * wear + 0.2 * dirt + 0.15 * stain - 0.06 * chk, 0.5, 0.92)
    r_tile = np.maximum(r_tile, np.maximum(crack, chip) * 0.93)
    r_grout = np.clip(0.92 + (hi - 0.5) * 0.08, 0.86, 0.97)
    rough = r_grout * (1 - tile) + r_tile * tile
    save(rgb_img(np.stack([ao, rough, np.zeros_like(ao)], -1)), "tiles_floor_orm.jpg", 90)


# ------------------------------------------------------------------ nursery wallpaper

def star_pts(cx, cy, r, rot, n=5, inner=0.46):
    pts = []
    for i in range(n * 2):
        a = rot + i * math.pi / n - math.pi / 2
        rr = r if i % 2 == 0 else r * inner
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    return pts


def _wallpaper_unit():
    """256x256 motif unit drawn at 4x: returns (fill, outline) masks in [0,1], 256 px."""
    k = 4
    U = 256 * k
    m = Image.new("L", (U, U), 0)
    d = ImageDraw.Draw(m)

    def star(cx, cy, r, rot):
        d.polygon([(x * k, y * k) for x, y in star_pts(cx, cy, r, rot)], fill=255)

    def moon(cx, cy, r, ang):
        d.ellipse([(cx - r) * k, (cy - r) * k, (cx + r) * k, (cy + r) * k], fill=255)
        ox, oy = math.cos(ang) * r * 0.48, math.sin(ang) * r * 0.48
        r2 = r * 0.86
        d.ellipse([(cx + ox - r2) * k, (cy + oy - r2) * k, (cx + ox + r2) * k, (cy + oy + r2) * k], fill=0)

    def cloud(cx, cy, s):
        for ox, oy, r in ((-17, 2, 11), (-3, -7, 15), (14, -1, 12), (26, 5, 8), (-28, 6, 7)):
            d.ellipse([(cx + (ox - r) * s) * k, (cy + (oy - r) * s) * k, (cx + (ox + r) * s) * k, (cy + (oy + r) * s) * k], fill=255)
        d.rounded_rectangle([(cx - 34 * s) * k, (cy + 1 * s) * k, (cx + 33 * s) * k, (cy + 13 * s) * k], radius=6 * s * k, fill=255)

    moon(62, 60, 24, -0.5)
    star(186, 66, 21, 0.18)
    cloud(70, 190, 1.0)
    star(196, 192, 13, -0.3)
    cloud(150, 124, 0.55)
    for cx, cy, r, rot in ((128, 22, 6.5, 0.4), (22, 124, 7, -0.2), (236, 128, 5.5, 0.1), (126, 232, 7, 0.6),
                           (238, 240, 5, 0.0), (104, 84, 4.5, 0.9), (18, 234, 4.5, 0.3)):
        star(cx, cy, r, rot)
    for cx, cy in ((150, 40), (228, 22), (20, 20), (112, 160), (236, 84), (30, 162), (160, 250), (88, 132)):
        d.ellipse([(cx - 2) * k, (cy - 2) * k, (cx + 2) * k, (cy + 2) * k], fill=255)
    out = ImageChops.subtract(m.filter(ImageFilter.MaxFilter(5)), m.filter(ImageFilter.MinFilter(7)))
    f = arr(m.resize((256, 256), Image.LANCZOS))
    o = arr(out.resize((256, 256), Image.LANCZOS))
    return np.clip(f, 0, 1), np.clip(o, 0, 1)


def gen_wallpaper():
    S = 1024
    f, o = _wallpaper_unit()
    # half-drop repeat: 512x256 super unit (second column shifted by half a unit), tiled 2x4
    f2 = np.concatenate([f, np.roll(np.roll(f, 128, axis=0), 0, axis=1)], axis=1)
    o2 = np.concatenate([o, np.roll(o, 128, axis=0)], axis=1)
    fill = np.tile(f2, (4, 2))
    outl = np.tile(o2, (4, 2))
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)

    fine = fft_noise(S, 0.3, 7301, lo=90)
    fibre = fft_noise(S, 0.8, 7302, lo=30, hi=400, sx=0.12, sy=1.0)        # vertical paper fibres
    lo = eq(fft_noise(S, 1.9, 7303, lo=1, hi=6))
    md = eq(fft_noise(S, 1.4, 7304, lo=3, hi=30))
    drip = eq(fft_noise(S, 1.9, 7305, lo=1, hi=40, sx=0.30, sy=1.0))        # stains elongated downwards

    paper = np.empty((S, S, 3), np.float32)
    paper[:] = np.array([0.900, 0.862, 0.720], np.float32)
    paper *= (0.955 + 0.06 * fine + 0.05 * (fibre - 0.5))[..., None]
    ink = (0.62 + 0.38 * sstep(0.25, 0.6, fine)) * (0.80 + 0.2 * md)       # uneven, faded print
    blue_l = np.array([0.490, 0.610, 0.740], np.float32)
    blue_d = np.array([0.290, 0.410, 0.580], np.float32)
    # the outline plate is printed ~1 px off register
    outl = np.roll(np.roll(outl, 1, axis=1), 1, axis=0)
    col = mix(paper, paper * 0.25 + blue_l * 0.75, fill * ink * 0.85)
    col = mix(col, col * 0.25 + blue_d * 0.75, outl * ink * 0.8)

    # ageing: yellow-brown patches, tide-marked water stains, general fade
    yellow = np.clip(lo * 1.3 - 0.25, 0, 1)
    col = mix(col, col * np.array([0.95, 0.87, 0.68]), yellow * 0.6)
    col = mix(col, col * np.array([0.90, 0.84, 0.70]), np.clip(md * 2 - 1.2, 0, 1) * 0.35)
    st = sstep(0.875, 0.93, drip)
    tide = np.clip(sstep(0.855, 0.885, drip) - sstep(0.89, 0.93, drip), 0, 1)
    col = mix(col, col * np.array([0.93, 0.86, 0.70]), st * 0.32)
    col = mix(col, col * np.array([0.78, 0.66, 0.46]), tide * 0.30 * (0.4 + 0.6 * md))
    foxing = np.clip(fft_noise(S, 0.9, 7306, lo=20, hi=120) * 7 - 5.3, 0, 1) * yellow
    col = mix(col, col * np.array([0.72, 0.58, 0.38]), foxing * 0.5)

    # two 53 cm strips: seams at x = 256 and 768
    seam = np.zeros((S, S), np.float32)
    lift = np.zeros((S, S), np.float32)
    for sx_ in (256.0, 768.0):
        wob = 0.6 * np.sin(yy / 37.0 + sx_)
        dx = xx - sx_ - wob
        gap = 0.55 + 0.45 * np.sin(yy / 91.0 + sx_ * 0.01) * np.sin(yy / 17.0)
        seam = np.maximum(seam, np.exp(-(dx / 0.9) ** 2) * (0.45 + 0.55 * gap))
        lift = np.maximum(lift, np.exp(-((dx - 3.5) / 3.0) ** 2) * 0.6 + np.exp(-((dx + 2.5) / 2.0) ** 2) * 0.25)
    strip_b = ((xx >= 256) & (xx < 768)).astype(np.float32)
    col *= (1.0 - 0.018 * strip_b)[..., None]
    col = mix(col, col * np.array([0.52, 0.44, 0.32]), seam * 0.55)
    col = mix(col, col * 1.035, lift * 0.5)
    dirtseam = blur_wrap(seam, 5.0) * 3.0
    col = mix(col, col * np.array([0.88, 0.80, 0.64]), np.clip(dirtseam, 0, 1) * 0.35 * md)
    save(rgb_img(col), "wallpaper_nursery.jpg", 88)

    h = (fine - 0.5) * 0.5 + (fibre - 0.5) * 0.7 + fill * 0.10 + outl * 0.08 - seam * 0.9 + lift * 0.5 + (st - 0.5) * 0.25
    h += (md - 0.5) * 0.6                                   # slight bubbling of the old paper
    save(normal_from_height(h.astype(np.float32), 0.9), "wallpaper_nursery_n.png")


# ------------------------------------------------------------------ carpet

def gen_carpet():
    S = 512
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    wx = (fft_noise(S, 1.2, 7401, lo=4, hi=40) - 0.5) * 7.0
    wy = (fft_noise(S, 1.2, 7402, lo=4, hi=40) - 0.5) * 7.0
    pitch = 4.0                                             # 128 loops per tile (4.7 mm)
    loops = 0.5 + 0.25 * np.cos(2 * np.pi * (xx + wx) / pitch) + 0.25 * np.cos(2 * np.pi * (yy + wy) / pitch)
    fib = fft_noise(S, 0.2, 7403, lo=50)
    fib2 = fft_noise(S, 0.9, 7404, lo=12, hi=120)
    h = 0.50 * loops + 0.38 * fib + 0.12 * fib2
    tuft = eq(fft_noise(S, 0.4, 7405, lo=40, hi=128))       # heathered yarn: per-tuft colour
    lo = eq(fft_noise(S, 1.8, 7406, lo=1, hi=6))
    md = eq(fft_noise(S, 1.3, 7407, lo=4, hi=30))

    c_mid = np.array([0.285, 0.345, 0.420], np.float32)
    c_dark = np.array([0.150, 0.190, 0.255], np.float32)
    c_light = np.array([0.470, 0.510, 0.550], np.float32)
    c_fleck = np.array([0.520, 0.470, 0.380], np.float32)
    col = np.empty((S, S, 3), np.float32)
    col[:] = c_mid
    col = mix(col, c_dark, sstep(0.55, 0.9, tuft) * 0.8)
    col = mix(col, c_light, sstep(0.45, 0.1, tuft) * 0.0 + sstep(0.72, 1.0, 1 - tuft) * 0.65)
    fleck = np.clip(fft_noise(S, 0.2, 7408, lo=50, hi=200) * 9 - 6.6, 0, 1)
    col = mix(col, c_fleck, fleck * 0.55)
    col *= (0.60 + 0.85 * h)[..., None]                    # pile shading: dark between the loops
    # traffic wear / dust: flatter and greyer in patches
    worn = np.clip(lo * 1.5 - 0.55, 0, 1)
    grey = col.mean(-1, keepdims=True)
    col = mix(col, grey * np.array([1.02, 1.0, 0.95]) * 1.05, worn * 0.4)
    # stains: a couple of darker blobs with a ring
    sn = fft_noise(S, 1.5, 7409, lo=3, hi=48)
    field = np.zeros((S, S), np.float32)
    for sx_, sy_, sr in ((0.31, 0.36, 46.0), (0.73, 0.71, 30.0)):
        ddx = ((xx - sx_ * S + S / 2) % S) - S / 2
        ddy = ((yy - sy_ * S + S / 2) % S) - S / 2
        field = np.maximum(field, np.exp(-(ddx * ddx + ddy * ddy * 1.5) / (sr * sr)))
    field = field + (sn - 0.5) * 1.1 * np.clip(field * 3, 0, 1)
    stain = sstep(0.42, 0.80, field)
    ring = np.clip(sstep(0.33, 0.44, field) - sstep(0.46, 0.60, field), 0, 1)
    col = mix(col, col * np.array([0.62, 0.54, 0.45]), stain * (0.24 + 0.2 * md))
    col = mix(col, col * np.array([0.74, 0.66, 0.56]), ring * 0.16)
    col = mix(col, col * np.array([0.80, 0.76, 0.70]), np.clip(md * 2 - 1.35, 0, 1) * 0.5)
    lint = np.clip(fft_noise(S, 0.0, 7410, lo=80) * 14 - 11.6, 0, 1)
    col = mix(col, np.array([0.62, 0.60, 0.55]), lint * 0.5)
    save(rgb_img(col), "carpet.jpg", 88)
    hn = h * (1 - 0.45 * worn) - stain * 0.05
    save(normal_from_height(hn.astype(np.float32), 3.2), "carpet_n.png")


# ------------------------------------------------------------------ night-light projector cookie

def gen_star_cookie():
    S, k = 512, 2
    U = S * k
    rng = random.Random(7501)
    R = S / 2
    cx = cy = S / 2
    moon_c = (cx - 62, cy - 48, 40)
    placed = [moon_c[:2] + (moon_c[2] + 10,)]
    stars = []
    kinds = ["star"] * 34 + ["dot"] * 14 + ["spark"] * 12
    rng.shuffle(kinds)
    for kind in kinds:
        r = {"star": rng.uniform(5, 15), "dot": rng.uniform(1.8, 3.6), "spark": rng.uniform(9, 19)}[kind]
        for _ in range(400):
            a = rng.uniform(0, 2 * math.pi)
            rad = math.sqrt(rng.random()) * (R * 0.80)
            x, y = cx + math.cos(a) * rad, cy + math.sin(a) * rad
            if all(math.hypot(x - px, y - py) > r + pr + 7 for px, py, pr in placed):
                placed.append((x, y, r))
                stars.append((kind, x, y, r, rng.uniform(-0.5, 0.5), rng.uniform(0.62, 1.0)))
                break
    img = np.zeros((U, U), np.float32)
    for kind, x, y, r, rot, br in stars:
        lay = Image.new("L", (U, U), 0)
        d = ImageDraw.Draw(lay)
        if kind == "star":
            d.polygon([(px * k, py * k) for px, py in star_pts(x, y, r, rot, 5, 0.47)], fill=255)
        elif kind == "dot":
            d.ellipse([(x - r) * k, (y - r) * k, (x + r) * k, (y + r) * k], fill=255)
        else:
            d.polygon([(px * k, py * k) for px, py in star_pts(x, y, r, rot * 0.3, 4, 0.2)], fill=255)
        box = [int(max(0, (x - r - 14) * k)), int(max(0, (y - r - 14) * k)), int(min(U, (x + r + 14) * k)), int(min(U, (y + r + 14) * k))]
        crop = lay.crop(box)
        soft = arr(crop.filter(ImageFilter.GaussianBlur(0.9 + r * 0.10 * k)))
        glow = arr(crop.filter(ImageFilter.GaussianBlur(4.0 * k)))
        img[box[1]:box[3], box[0]:box[2]] += (soft * 0.95 + glow * 0.45) * br
    lay = Image.new("L", (U, U), 0)
    d = ImageDraw.Draw(lay)
    mx, my, mr = moon_c
    d.ellipse([(mx - mr) * k, (my - mr) * k, (mx + mr) * k, (my + mr) * k], fill=255)
    d.ellipse([(mx + 17 - mr * 0.88) * k, (my - 9 - mr * 0.88) * k, (mx + 17 + mr * 0.88) * k, (my - 9 + mr * 0.88) * k], fill=0)
    img += arr(lay.filter(ImageFilter.GaussianBlur(2.2))) * 0.95 + arr(lay.filter(ImageFilter.GaussianBlur(10))) * 0.35
    yy, xx = np.mgrid[0:U, 0:U].astype(np.float32)
    rr = np.hypot(xx + 0.5 - U / 2, yy + 0.5 - U / 2) / (U / 2)
    img *= 1.0 - sstep(0.60, 0.86, rr)
    img = np.clip(img, 0, 1)
    im = Image.fromarray((img * 255 + 0.5).astype(np.uint8), "L").resize((S, S), Image.LANCZOS)
    a = np.asarray(im).copy()
    b = int(S * 0.065)
    a[:b, :] = 0
    a[-b:, :] = 0
    a[:, :b] = 0
    a[:, -b:] = 0
    save(Image.merge("RGB", [Image.fromarray(a, "L")] * 3), "star_cookie.png")


# ------------------------------------------------------------------ office papers (2x supersampled cells)

INK_BLUE = (28, 40, 110)
INK_BLACK = (26, 24, 30)
INK_RED = (150, 28, 30)


def typed(d, x, y, text, size, rng, anchor="l", dark=38):
    """Typewriter text, one character at a time (uneven baseline and ink). anchor l / m / r on x."""
    f = font("type", size)
    adv = f.getlength("M")
    w = adv * len(text)
    x0 = x - (w / 2 if anchor == "m" else w if anchor == "r" else 0)
    for i, ch in enumerate(text):
        if ch == " ":
            continue
        g = int(dark + rng.uniform(-14, 40))
        d.text((x0 + i * adv + rng.uniform(-0.8, 0.8), y + rng.uniform(-1.6, 1.6)), ch, font=f, fill=(g, g, g + 4))
    return x0, w


def handwrite(img, x, y, text, size, col, rng, rot=None, bold=True):
    f = font("hand_b" if bold else "hand", size)
    bb = f.getbbox(text)
    w, h = bb[2] + 24, bb[3] + 30
    lay = Image.new("L", (w, h), 0)
    ImageDraw.Draw(lay).text((10, 6), text, font=f, fill=255)
    lay = lay.rotate(rng.uniform(-2.5, 2.5) if rot is None else rot, resample=Image.BICUBIC, expand=True)
    img.paste(Image.new("RGB", lay.size, col), (int(x), int(y)), lay.point(lambda v: int(v * 0.92)))


def pen(d, pts, col, width, rng, wob=2.0, passes=1):
    """Ball-point line through pts with a slightly shaky hand."""
    for _ in range(passes):
        out = []
        for (x0, y0), (x1, y1) in zip(pts[:-1], pts[1:]):
            n = max(2, int(math.hypot(x1 - x0, y1 - y0) / 22))
            for i in range(n):
                t = i / n
                out.append((x0 + (x1 - x0) * t + rng.uniform(-wob, wob), y0 + (y1 - y0) * t + rng.uniform(-wob, wob)))
        out.append(pts[-1])
        d.line(out, fill=col, width=width, joint="curve")


def scribble(d, box, col, width, rng, rows=7, passes=2):
    x0, y0, x1, y1 = box
    for _ in range(passes):
        pts = []
        x, up = x0 - 8.0, rng.random() < 0.5
        while x < x1 + 8:
            pts.append((x + rng.uniform(-10, 10), (y0 if up else y1) + rng.uniform(-14, 10)))
            x += rng.uniform(6, 40)
            up = not up
        pen(d, pts, col, width, rng, wob=3.0)
        ym = y0 + (y1 - y0) * rng.uniform(0.25, 0.75)
        pen(d, [(x0 - 6, ym + rng.uniform(-8, 8)), ((x0 + x1) / 2, ym + rng.uniform(-10, 10)), (x1 + 8, ym + rng.uniform(-8, 8))],
            col, width + 1, rng, wob=4.0)


def doc_sheet(seed):
    U = 1024
    fine = fft_noise(U, 0.4, seed, lo=60)
    a = np.empty((U, U, 3), np.float32)
    a[:] = np.array([0.925, 0.895, 0.790], np.float32)
    a *= (0.965 + 0.07 * fine)[..., None]
    return rgb_img(a)


def doc_finish(img, seed, folds):
    """Yellowing, edge foxing, fold creases, pin holes; returns the 512 px cell."""
    U = 1024
    a = arr(img)
    yy, xx = np.mgrid[0:U, 0:U].astype(np.float32)
    lo = eq(fft_noise(U, 1.8, seed + 1, lo=1, hi=6))
    md = eq(fft_noise(U, 1.9, seed + 2, lo=3))
    a = mix(a, a * np.array([0.95, 0.88, 0.70]), np.clip(lo * 1.3 - 0.35, 0, 1) * 0.45)
    eg = np.minimum(np.minimum(xx, U - 1 - xx), np.minimum(yy, U - 1 - yy))
    edge = np.exp(-eg / 40.0) * (0.55 + 0.6 * md)
    a = mix(a, a * np.array([0.82, 0.72, 0.52]), np.clip(edge, 0, 1) * 0.5)
    stain = sstep(0.93, 0.97, eq(fft_noise(U, 2.0, seed + 3, lo=1, hi=5)))
    a = mix(a, a * np.array([0.88, 0.80, 0.62]), stain * 0.4)
    for axis, pos in folds:
        c = (yy if axis == "h" else xx) - pos * U
        brk = 0.55 + 0.45 * md
        a *= (1.0 - 0.16 * np.exp(-(c / 1.6) ** 2) * brk)[..., None]
        a *= (1.0 + 0.045 * np.exp(-((c + 5) / 4.0) ** 2) - 0.035 * np.exp(-((c - 6) / 5.0) ** 2))[..., None]
    for px, py in ((44, 44), (U - 44, 46)):
        r = np.hypot(xx - px, yy - py)
        a = mix(a, a * np.array([0.72, 0.52, 0.34]), np.exp(-(r / 13.0) ** 2) * 0.55)     # rust halo of the pin
        a = mix(a, np.array([0.07, 0.06, 0.05]), 1.0 - sstep(4.2, 6.0, r))
    return rgb_img(a).resize((512, 512), Image.LANCZOS)


def doc_presence():
    rng = random.Random(7601)
    img = doc_sheet(7601)
    d = ImageDraw.Draw(img)
    typed(d, 512, 50, "FEUILLE DE PRÉSENCE", 56, rng, "m")
    typed(d, 60, 126, "Les Petits Soleils", 36, rng)
    typed(d, 556, 130, "Semaine du", 30, rng)
    handwrite(img, 760, 100, "7 nov.", 60, INK_BLUE, rng)
    x0, x1, xn = 60, 964, 430
    cw = (x1 - xn) / 5.0
    yt, hh, rh = 190, 66, 84
    yb = yt + hh + 8 * rh
    line = (52, 50, 54)
    for y in [yt, yt + hh] + [yt + hh + (i + 1) * rh for i in range(8)]:
        d.line([(x0, y + rng.uniform(-1, 1)), (x1, y + rng.uniform(-1, 1))], fill=line, width=3)
    for x in [x0, xn] + [xn + (i + 1) * cw for i in range(5)]:
        d.line([(x + rng.uniform(-1, 1), yt), (x + rng.uniform(-1, 1), yb)], fill=line, width=3)
    typed(d, x0 + 20, yt + 14, "NOM DE L'ENFANT", 30, rng)
    for i, ch in enumerate("LMMJV"):
        typed(d, xn + (i + 0.5) * cw, yt + 10, ch, 42, rng, "m")
    names = ["Léa", "Mathis", "Simon", "Chloé", "Émile", "Rosalie", "Jérémie", "Noémie"]
    marks = ["vvvvv", "vv-vv", "vvvvv", "vvvv-", "v-vvv", "vv   ", "v    ", "vvv  "]
    for r, (name, mk) in enumerate(zip(names, marks)):
        y = yt + hh + r * rh
        handwrite(img, x0 + 18 + rng.uniform(-4, 8), y + 2, name, 64, INK_BLUE, rng)
        for c, m in enumerate(mk):
            cxm = xn + (c + 0.5) * cw + rng.uniform(-8, 8)
            cym = y + rh / 2 + rng.uniform(-5, 5)
            if m == "v":
                pen(d, [(cxm - 22, cym), (cxm - 8, cym + 20), (cxm + 26, cym - 26)], INK_BLUE, 5, rng, wob=1.5)
            elif m == "-":
                pen(d, [(cxm - 18, cym + 2), (cxm + 18, cym - 2)], INK_BLUE, 5, rng, wob=1.5)
    for r in (5, 6, 7):   # crossed out by hand, pressed hard
        y = yt + hh + r * rh + rh / 2
        pen(d, [(x0 + 6, y + rng.uniform(-10, 10)), (xn + 40, y + rng.uniform(-8, 8)), (x1 - 8, y + rng.uniform(-12, 12))],
            INK_BLACK, 6, rng, wob=3.0, passes=2)
    return doc_finish(img, 7610, [("h", 0.502), ("v", 0.497)])


def doc_sieste():
    rng = random.Random(7602)
    img = doc_sheet(7602)
    d = ImageDraw.Draw(img)
    typed(d, 512, 70, "HORAIRE DE LA SIESTE", 58, rng, "m")
    d.line([(150, 150), (874, 151)], fill=(50, 48, 52), width=4)
    d.line([(150, 162), (874, 163)], fill=(50, 48, 52), width=2)
    typed(d, 512, 205, "13 h à 15 h", 96, rng, "m", dark=30)
    typed(d, 512, 345, "- Les Petits Soleils -", 32, rng, "m", dark=60)
    rules = ["On ferme les yeux.", "On ne parle pas.", "On ne se lève pas.", "La gardienne veille."]
    y = 450
    for i, r in enumerate(rules):
        typed(d, 130, y, "%d." % (i + 1), 50, rng)
        xs, w = typed(d, 230, y, r, 50, rng)
        if i == 3:
            for k in range(2):
                yy_ = y + 70 + k * 15
                pen(d, [(xs - 10, yy_ + rng.uniform(-3, 3)), (xs + w * 0.5, yy_ + rng.uniform(-4, 4)), (xs + w + 14, yy_ + rng.uniform(-3, 3))],
                    INK_RED, 6, rng, wob=1.8)
        y += 118
    return doc_finish(img, 7620, [("h", 0.335), ("h", 0.668)])


def doc_avis():
    rng = random.Random(7603)
    img = doc_sheet(7603)
    d = ImageDraw.Draw(img)
    x0, w = typed(d, 512, 70, "AVIS AUX PARENTS", 66, rng, "m", dark=30)
    d.line([(x0, 150), (x0 + w, 151)], fill=(44, 42, 46), width=4)
    typed(d, 950, 200, "Le 9 novembre 1994", 34, rng, "r")
    lines = ["Chers parents,", "", "La garderie Les Petits Soleils", "est fermée jusqu'à nouvel ordre.", "",
             "Veuillez reprendre les effets", "de vos enfants au vestiaire.", "", "Merci de votre compréhension."]
    y = 290
    for ln in lines:
        if ln:
            typed(d, 80, y, ln, 40, rng)
        y += 58 if ln else 26
    typed(d, 600, y + 30, "La direction", 40, rng)
    sy_ = y + 150
    pts = [(560, sy_), (600, sy_ - 50), (625, sy_ + 20), (650, sy_ - 38), (676, sy_ + 14), (700, sy_ - 22), (728, sy_ + 10),
           (760, sy_ - 30), (790, sy_ + 6), (850, sy_ - 8), (930, sy_ - 16)]
    pen(d, pts, INK_BLUE, 5, rng, wob=2.5)
    pen(d, [(585, sy_ + 28), (760, sy_ + 20), (905, sy_ + 26)], INK_BLUE, 4, rng, wob=2.0)
    typed(d, 80, 930, "Garderie en milieu familial - novembre 1994", 24, rng, dark=70)
    return doc_finish(img, 7630, [("h", 0.34), ("h", 0.672)])


def doc_numeros():
    rng = random.Random(7604)
    img = doc_sheet(7604)
    d = ImageDraw.Draw(img)
    typed(d, 512, 66, "NUMÉROS IMPORTANTS", 60, rng, "m", dark=30)
    d.line([(110, 144), (914, 145)], fill=(50, 48, 52), width=4)
    d.line([(110, 156), (914, 157)], fill=(50, 48, 52), width=2)
    rows = [("Urgence", "9-1-1"), ("Centre antipoison", "555-0142"), ("Dr Gagnon, pédiatre", "555-0117"),
            ("Plombier", "555-0129"), ("Mme Lavoie, voisine", "555-0163"), ("La gardienne (soir)", "555-0188")]
    y = 230
    for i, (lab, num) in enumerate(rows):
        typed(d, 70, y, lab, 40, rng)
        xs, w = typed(d, 950, y, num, 40, rng, "r")
        f = font("type", 40)
        xa = 70 + f.getlength("M") * (len(lab) + 1)
        k = 0
        while xa + k * 24 < xs - 20:
            d.ellipse([xa + k * 24, y + 30, xa + k * 24 + 5, y + 35], fill=(70, 68, 72))
            k += 1
        if i == 5:
            scribble(d, (60, y - 8, 960, y + 52), INK_BLACK, 6, rng, rows=13, passes=3)
        y += 100
    handwrite(img, 380, y - 4, "ne plus appeler", 66, INK_BLACK, rng, rot=3.0)
    handwrite(img, 90, 900, "pédiatre : fermé le vendredi", 46, INK_BLUE, rng, rot=-1.0, bold=False)
    return doc_finish(img, 7640, [("h", 0.5), ("v", 0.503)])


def gen_docs_atlas():
    atlas = Image.new("RGB", (1024, 1024))
    for k, fn in enumerate((doc_presence, doc_sieste, doc_avis, doc_numeros)):
        atlas.paste(fn(), ((k % 2) * 512, (k // 2) * 512))
    save(atlas, "docs_atlas.jpg", 90)


# ------------------------------------------------------------------ crayon drawings (2x supersampled cells)

LETTERS = {
    "E": [[(0.6, 0), (0, 0), (0, 1), (0.6, 1)], [(0, 0.5), (0.45, 0.5)]],
    "N": [[(0, 1), (0, 0), (0.6, 1), (0.6, 0)]],
    "B": [[(0, 0), (0, 1)], [(0, 0), (0.42, 0.04), (0.55, 0.25), (0.4, 0.47), (0, 0.5)],
          [(0, 0.5), (0.5, 0.58), (0.62, 0.78), (0.45, 0.98), (0, 1)]],
    "A": [[(0, 1), (0.3, 0), (0.6, 1)], [(0.12, 0.62), (0.5, 0.62)]],
    "S": [[(0.58, 0.14), (0.34, 0), (0.1, 0.1), (0.05, 0.3), (0.3, 0.48), (0.55, 0.66), (0.55, 0.88), (0.3, 1), (0.02, 0.86)]],
    "Z": [[(0, 0), (0.6, 0), (0, 1), (0.6, 1)]],
}


class Crayon:
    """Waxy crayon on toothy paper. Coordinates are given in 512 px cell space, drawn at 2x."""

    def __init__(self, seed, tint=(0.955, 0.935, 0.86)):
        self.k = 2
        self.U = 512 * self.k
        self.rng = random.Random(seed)
        fine = fft_noise(self.U, 0.3, seed, lo=70)
        self.tooth = sstep(0.30, 0.62, eq(fft_noise(self.U, 0.5, seed + 1, lo=40, hi=300)))
        self.press = 0.72 + 0.28 * eq(fft_noise(self.U, 1.5, seed + 2, lo=2, hi=20))
        self.a = np.empty((self.U, self.U, 3), np.float32)
        self.a[:] = np.array(tint, np.float32)
        self.a *= (0.965 + 0.07 * fine)[..., None]

    def _wobble(self, pts, width, amp):
        k, rng = self.k, self.rng
        out = []
        for (x0, y0), (x1, y1) in zip(pts[:-1], pts[1:]):
            n = max(1, int(math.hypot(x1 - x0, y1 - y0) / 14))
            for i in range(n):
                t = i / n
                out.append([x0 + (x1 - x0) * t, y0 + (y1 - y0) * t])
        out.append(list(pts[-1]))
        ox = oy = 0.0
        res = []
        for x, y in out:
            ox = ox * 0.6 + rng.gauss(0, amp)
            oy = oy * 0.6 + rng.gauss(0, amp)
            res.append(((x + ox) * k, (y + oy) * k))
        return res

    def _mask(self, pts, width, amp):
        m = Image.new("L", (self.U, self.U), 0)
        d = ImageDraw.Draw(m)
        p = self._wobble(pts, width, amp)
        w = max(2, int(width * self.k))
        d.line(p, fill=255, width=w, joint="curve")
        for x, y in (p[0], p[-1]):
            d.ellipse([x - w / 2, y - w / 2, x + w / 2, y + w / 2], fill=255)
        return m

    def _apply(self, mask, col, strength):
        al = arr(mask.filter(ImageFilter.GaussianBlur(1.3)))
        al = al * (0.22 + 0.78 * self.tooth) * self.press * strength
        c = np.array(col, np.float32) / 255.0
        self.a = self.a * (1 - al[..., None]) + (self.a * c * 0.45 + c * 0.55) * al[..., None]

    def line(self, pts, col, width=7, passes=2, amp=None, strength=0.8):
        for _ in range(passes):
            self._apply(self._mask(pts, width * self.rng.uniform(0.75, 1.05), width * 0.16 if amp is None else amp), col, strength)

    def fill(self, poly, col, width=7, angle=0.9, spacing=9, strength=0.75, sloppy=5.0, passes=1):
        """Back-and-forth scribble clipped (loosely) to a polygon."""
        rng, k = self.rng, self.k
        pm = Image.new("L", (self.U, self.U), 0)
        ImageDraw.Draw(pm).polygon([((x + rng.uniform(-sloppy, sloppy)) * k, (y + rng.uniform(-sloppy, sloppy)) * k) for x, y in poly], fill=255)
        xs = [p[0] for p in poly]
        ys = [p[1] for p in poly]
        cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
        rad = math.hypot(max(xs) - min(xs), max(ys) - min(ys)) / 2 + 12
        for ps in range(passes):
            ang = angle + ps * 1.1
            ca, sa = math.cos(ang), math.sin(ang)
            pts = []
            n = int(2 * rad / spacing)
            for i in range(n + 1):
                t = -rad + i * spacing + rng.uniform(-2.5, 2.5)
                s = rad * (1 if i % 2 == 0 else -1) * rng.uniform(0.9, 1.05)
                pts.append((cx + ca * t - sa * s, cy + sa * t + ca * s))
            m = self._mask(pts, width, 1.2)
            self._apply(ImageChops.multiply(m, pm), col, strength)

    def scribble(self, cx, cy, rx, ry, col, width=8, passes=3, strength=0.85, spacing=11):
        """Angry back-and-forth scribble over an elliptical area: ragged edge, visible strokes."""
        rng = self.rng
        for _ in range(passes):
            ang = rng.uniform(0, math.pi)
            ca, sa = math.cos(ang), math.sin(ang)
            n = max(4, int(2 * max(rx, ry) / spacing))
            pts = []
            for i in range(n + 1):
                t = (-1 + 2 * i / n) + rng.uniform(-0.06, 0.06)
                s = (1 if i % 2 == 0 else -1) * rng.uniform(0.55, 1.15) * math.sqrt(max(0.08, 1 - t * t * 0.8))
                pts.append((cx + (ca * t - sa * s) * rx, cy + (sa * t + ca * s) * ry))
            self._apply(self._mask(pts, width * rng.uniform(0.8, 1.1), 1.5), col, strength)

    def circle(self, cx, cy, r, col, width=6, passes=2, strength=0.8, ry=None):
        ry = r if ry is None else ry
        a0 = self.rng.uniform(0, 6.28)
        pts = [(cx + math.cos(a0 + t) * r, cy + math.sin(a0 + t) * ry) for t in np.linspace(0, 2 * math.pi * 1.06, 20)]
        self.line(pts, col, width, passes, amp=max(0.5, r * 0.035), strength=strength)

    def disc(self, cx, cy, r, col, strength=0.85, passes=2):
        poly = [(cx + math.cos(t) * r, cy + math.sin(t) * r) for t in np.linspace(0, 2 * math.pi, 16, endpoint=False)]
        self.fill(poly, col, width=max(4, r * 0.35), spacing=max(3, r * 0.3), strength=strength, sloppy=1.5, passes=passes)

    def text(self, s, x, y, h, col, width=7, gap=0.28, lean=0.0):
        rng = self.rng
        for ch in s:
            if ch == " ":
                x += h * 0.5
                continue
            dy = rng.uniform(-h * 0.07, h * 0.07)
            sc = h * rng.uniform(0.9, 1.08)
            for stroke in LETTERS[ch.upper()]:
                self.line([(x + (px + lean * (1 - py)) * sc, y + dy + py * sc) for px, py in stroke], col, width, 2, amp=h * 0.018)
            x += sc * (0.6 + gap)

    def stick(self, x, y, hgt, col, body=None, dress=False, hand_l=None, hand_r=None, width=5):
        """Tiny stick child standing on y; returns hand positions."""
        r = hgt * 0.17
        hy = y - hgt + r
        self.circle(x, hy, r, (40, 36, 34), width=width * 0.8, passes=2)
        neck, hip = hy + r, y - hgt * 0.36
        body = body or col
        if dress:
            self.fill([(x, neck), (x - hgt * 0.22, hip + 4), (x + hgt * 0.22, hip + 4)], body, width=5, spacing=5, strength=0.85, sloppy=2)
        self.line([(x, neck), (x, hip)], body, width)
        self.line([(x, hip), (x - hgt * 0.14, y)], col, width)
        self.line([(x, hip), (x + hgt * 0.14, y)], col, width)
        sh = neck + hgt * 0.08
        hl = hand_l or (x - hgt * 0.26, sh + hgt * 0.16)
        hr = hand_r or (x + hgt * 0.26, sh + hgt * 0.16)
        self.line([(x, sh), hl], col, width)
        self.line([(x, sh), hr], col, width)
        return hl, hr

    def finish(self, seed):
        a = self.a
        lo = eq(fft_noise(self.U, 1.8, seed, lo=1, hi=6))
        md = eq(fft_noise(self.U, 1.9, seed + 1, lo=3))
        a = mix(a, a * np.array([0.95, 0.88, 0.72]), np.clip(lo * 1.3 - 0.3, 0, 1) * 0.5)
        yy, xx = np.mgrid[0:self.U, 0:self.U].astype(np.float32)
        eg = np.minimum(np.minimum(xx, self.U - 1 - xx), np.minimum(yy, self.U - 1 - yy))
        a = mix(a, a * np.array([0.84, 0.75, 0.56]), np.clip(np.exp(-eg / 36.0) * (0.5 + 0.6 * md), 0, 1) * 0.5)
        a = mix(a, a * np.array([0.84, 0.78, 0.66]), sstep(0.55, 1.0, md) ** 2 * 0.4)        # smudges
        lum = a.mean(-1, keepdims=True)
        a = a * 0.9 + lum * 0.1                                                                # slightly faded
        return rgb_img(a).resize((512, 512), Image.LANCZOS)


BLACK = (22, 20, 24)
BROWN = (120, 72, 38)
RED = (196, 44, 40)
BLUE = (44, 84, 176)
GREEN = (58, 140, 62)
YELLOW = (238, 190, 30)
ORANGE = (226, 126, 40)
PINK = (222, 110, 150)
GREY = (120, 120, 126)
PURPLE = (116, 70, 150)


def draw_house():
    c = Crayon(7701)
    c.fill([(8, 8), (330, 8), (330, 40), (8, 40)], BLUE, width=8, angle=1.45, spacing=10, strength=0.6)       # strip of sky
    c.line([(6, 446), (130, 442), (300, 448), (506, 443)], GREEN, 9, 3)
    for x in range(20, 500, 34):
        c.line([(x, 446), (x + c.rng.uniform(-5, 5), 428 + c.rng.uniform(-4, 4))], GREEN, 5, 1)
    c.fill([(88, 262), (272, 262), (272, 442), (88, 442)], ORANGE, width=8, angle=0.7, spacing=11, strength=0.55)
    c.line([(88, 262), (88, 442), (272, 442), (272, 262), (88, 262)], BROWN, 7, 2)
    c.fill([(70, 262), (180, 160), (292, 262)], RED, width=8, angle=0.3, spacing=8, strength=0.8)
    c.line([(70, 262), (180, 160), (292, 262), (70, 262)], RED, 7, 2)
    c.line([(232, 205), (232, 168), (252, 168), (252, 224)], BROWN, 6, 2)
    c.fill([(150, 352), (198, 352), (198, 442), (150, 442)], BROWN, width=7, angle=1.5, spacing=7, strength=0.85)
    c.disc(190, 400, 4, YELLOW, passes=1)
    c.line([(216, 292), (254, 292), (254, 330), (216, 330), (216, 292)], BLUE, 5, 2)
    c.line([(235, 292), (235, 330)], BLUE, 4, 1)
    c.line([(216, 311), (254, 311)], BLUE, 4, 1)
    c.disc(418, 92, 40, YELLOW, strength=0.9, passes=3)
    c.circle(418, 92, 40, ORANGE, 5, 1, strength=0.6)
    for i in range(11):
        a = i * 2 * math.pi / 11 + 0.2
        c.line([(418 + math.cos(a) * 52, 92 + math.sin(a) * 52), (418 + math.cos(a) * (76 + c.rng.uniform(-6, 10)), 92 + math.sin(a) * (76 + c.rng.uniform(-6, 10)))], YELLOW, 7, 2)
    mid = (388, 388)
    c.stick(352, 444, 104, BLUE, hand_r=mid)
    c.stick(424, 444, 94, RED, body=PINK, dress=True, hand_l=mid)
    for x, hy in ((352, 358), (424, 366)):    # smiles
        c.line([(x - 6, hy + 4), (x, hy + 8), (x + 6, hy + 4)], BLACK, 3, 1, amp=0.4)
        c.disc(x - 6, hy - 4, 1.6, BLACK, passes=1)
        c.disc(x + 6, hy - 4, 1.6, BLACK, passes=1)
    return c.finish(7711)


def draw_woman():
    c = Crayon(7702)
    c.line([(6, 474), (200, 470), (506, 476)], GREY, 8, 2)
    # the two tiny children first (she is drawn over everything)
    mid = (424, 440)
    c.stick(398, 472, 62, RED, hand_r=mid, width=4)
    c.stick(452, 473, 56, BLUE, hand_l=mid, width=4)
    for x, hy in ((398, 420), (452, 427)):
        c.disc(x - 4, hy - 2, 1.4, BLACK, passes=1)
        c.disc(x + 4, hy - 2, 1.4, BLACK, passes=1)
        c.line([(x - 4, hy + 6), (x, hy + 4), (x + 4, hy + 6)], BLACK, 2.5, 1, amp=0.3)
    # the woman: far too tall, dress pressed hard in black, arms hanging to the floor and reaching
    c.fill([(184, 112), (220, 112), (252, 470), (150, 470)], BLACK, width=9, angle=1.35, spacing=6, strength=0.92, sloppy=6, passes=2)
    c.line([(186, 112), (150, 470)], BLACK, 7, 2)
    c.line([(218, 112), (252, 470)], BLACK, 7, 2)
    c.line([(202, 96), (202, 118)], BLACK, 8, 2)
    c.circle(202, 68, 27, BLACK, 7, 3, ry=31)
    c.disc(202, 28, 15, BLACK, strength=0.95, passes=3)                                    # hair bun
    c.line([(176, 58), (184, 44), (202, 38), (222, 44), (228, 58)], BLACK, 9, 3)          # hair
    c.disc(192, 66, 4.5, BLACK, strength=0.95, passes=3)                                   # eyes, no mouth
    c.disc(213, 66, 4.5, BLACK, strength=0.95, passes=3)
    la = [(188, 126), (120, 250), (84, 380), (70, 468)]
    ra = [(216, 126), (296, 236), (340, 350), (366, 418)]
    c.line(la, BLACK, 6, 3)
    c.line(ra, BLACK, 6, 3)
    for dx, dy in ((-22, 16), (-12, 26), (0, 30), (12, 26), (22, 14)):
        c.line([(70, 468), (70 + dx, 468 + dy)], BLACK, 4, 2, amp=0.6)
    for dx, dy in ((26, -6), (30, 6), (26, 18), (16, 28), (4, 30)):
        c.line([(366, 418), (366 + dx, 418 + dy)], BLACK, 4, 2, amp=0.6)
    return c.finish(7712)


def draw_beds():
    c = Crayon(7703)
    # night window with a moon
    c.fill([(206, 36), (306, 36), (306, 128), (206, 128)], (40, 50, 110), width=8, angle=0.8, spacing=7, strength=0.75)
    c.line([(206, 36), (306, 36), (306, 128), (206, 128), (206, 36)], BROWN, 6, 2)
    c.line([(256, 36), (256, 128)], BROWN, 5, 1)
    c.line([(206, 82), (306, 82)], BROWN, 5, 1)
    c.disc(282, 60, 10, YELLOW, strength=0.95, passes=3)
    c.line([(6, 420), (250, 416), (506, 422)], BROWN, 7, 2)
    blankets = [BLUE, GREEN, PINK, PURPLE]
    for i, cx in enumerate((70, 192, 314, 438)):
        y = 372
        c.line([(cx - 50, y - 44), (cx - 50, y + 40)], BROWN, 6, 2)                         # headboard + leg
        c.line([(cx - 50, y), (cx + 50, y), (cx + 50, y + 40)], BROWN, 6, 2)
        c.line([(cx - 50, y + 22), (cx + 50, y + 22)], BROWN, 5, 1)
        c.fill([(cx - 18, y - 22), (cx + 48, y - 20), (cx + 50, y + 2), (cx - 18, y + 2)], blankets[i], width=7, angle=0.6, spacing=7, strength=0.8)
        c.circle(cx - 33, y - 14, 11, BLACK, 4, 2)
        if i != 2:
            c.line([(cx - 39, y - 15), (cx - 35, y - 13)], BLACK, 2.5, 1, amp=0.2)          # closed eyes
            c.line([(cx - 31, y - 13), (cx - 27, y - 15)], BLACK, 2.5, 1, amp=0.2)
            zx, zy = cx - 14, y - 66
            for j, hz in enumerate((22, 17, 13)):
                c.text("Z", zx, zy, hz, BLUE, width=4 if j == 0 else 3)
                zx += hz * 0.95
                zy -= hz * 1.0 + 5
    # the third bed: scribbled over, hard, in black
    cx, y = 314, 372
    c.scribble(cx, y - 6, 66, 54, BLACK, width=8, passes=4, strength=0.85, spacing=11)
    c.scribble(cx - 6, y - 10, 40, 34, BLACK, width=8, passes=2, strength=0.9, spacing=9)
    return c.finish(7713)


def draw_door():
    c = Crayon(7704)
    c.fill([(62, 84), (226, 84), (226, 420), (62, 420)], BROWN, width=9, angle=1.4, spacing=10, strength=0.6)
    c.line([(62, 420), (62, 84), (226, 84), (226, 420)], BROWN, 8, 3)
    c.line([(86, 110), (202, 110), (202, 200), (86, 200), (86, 110)], (92, 54, 28), 5, 1)
    c.line([(86, 330), (202, 330), (202, 398), (86, 398), (86, 330)], (92, 54, 28), 5, 1)
    c.disc(208, 300, 7, YELLOW, strength=0.95, passes=2)
    c.line([(20, 422), (250, 420)], GREY, 7, 2)
    # big padlock
    sh = [(144 + math.cos(t) * 26, 244 - math.sin(t) * 34) for t in np.linspace(0, math.pi, 12)]
    c.line([(170, 262)] + sh + [(118, 262)], GREY, 9, 3)
    c.fill([(104, 250), (184, 250), (184, 318), (104, 318)], BLACK, width=8, angle=0.4, spacing=6, strength=0.95, sloppy=3, passes=2)
    c.line([(104, 250), (184, 250), (184, 318), (104, 318), (104, 250)], BLACK, 7, 2)
    c.disc(144, 278, 7, YELLOW, strength=0.95, passes=2)
    c.line([(144, 282), (144, 302)], YELLOW, 5, 2)
    # stairs going down into the dark
    pts = [(262, 196)]
    x, y = 262, 196
    for i in range(6):
        x += 38
        pts.append((x, y))
        y += 44
        pts.append((x, y))
    c.scribble(440, 450, 58, 50, BLACK, width=9, passes=5, strength=0.88, spacing=10)
    c.scribble(446, 462, 36, 30, BLACK, width=9, passes=2, strength=0.9, spacing=8)
    c.line(pts, BLACK, 7, 3)
    c.line([(262, 196), (262, 240), (454, 462)], BLACK, 5, 2)
    c.text("EN BAS", 256, 40, 46, RED, width=7)
    c.line([(456, 112), (460, 176)], RED, 7, 2)                                             # arrow pointing down
    c.line([(440, 154), (460, 180), (480, 152)], RED, 7, 2)
    return c.finish(7714)


def gen_drawings2():
    atlas = Image.new("RGB", (1024, 1024))
    for k, fn in enumerate((draw_house, draw_woman, draw_beds, draw_door)):
        atlas.paste(fn(), ((k % 2) * 512, (k // 2) * 512))
    save(atlas, "drawings2.jpg", 88)


if __name__ == "__main__":
    jobs = [("tiles_wall", gen_tiles_wall), ("tiles_floor", gen_tiles_floor), ("wallpaper_nursery", gen_wallpaper),
            ("carpet", gen_carpet), ("star_cookie", gen_star_cookie), ("docs_atlas", gen_docs_atlas), ("drawings2", gen_drawings2)]
    for name, fn in jobs:
        if want(name):
            fn()
