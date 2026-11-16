#!/usr/bin/env python3
"""Procedural textures of the level "L'etage" (ground floor of an old wooden house at night). Re-runnable, deterministic
(fixed seeds), nothing downloaded, nothing copied from any other work.

    python3 -I pc/scripts/etage/tools/gen_etage_textures.py [out_dir] [--only name,name]

Default out_dir = pc/assets/garderie/textures (the folder the material loader reads). Then write the `.import` presets
for the NEW files only (see pc/scripts/garderie/tools/write_imports.py) and run `godot --headless --path pc --import`.

  wallpaper_house.jpg / _n.png   1024, seamless, 1.06 m (two 53 cm strips, seams at x = 256 and 768): dark bottle-green
                                 damask (ochre motif every 26.5 cm, half-drop), grime, water runs, lifted seams, tears
  plaster_old.jpg / _n.png       1024, seamless, 2 m: off-white ceiling plaster, hairline cracks, water rings, flakes
  rug_runner.jpg                 512x1024, seamless along v only (length), 0.8 m x 1.6 m: worn dark red hallway runner
  night_window.png               512x768, not tiling: night sky seen through a window, backlit clouds, bare branches
  portraits_atlas.jpg            1024, 2x2 atlas of sepia photographs (generic drawn figures, no likeness)
  sheet_n.png                    512, seamless normal map of a cotton dust sheet (weave + soft wrinkles)
Normal maps are OpenGL convention (+Y up).
"""
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi

HERE = os.path.dirname(os.path.abspath(__file__))
PC = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
ARGV = sys.argv[1:]
OUT = ARGV[0] if ARGV and not ARGV[0].startswith("--") else os.path.join(PC, "assets", "garderie", "textures")


def arg(name, default=None):
    if name in ARGV:
        i = ARGV.index(name)
        return ARGV[i + 1] if i + 1 < len(ARGV) else default
    return default


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


def normal_from_height(hgt, strength, wrap_x=True):
    if wrap_x:
        dx = (np.roll(hgt, -1, axis=1) - np.roll(hgt, 1, axis=1)) * 0.5
    else:
        dx = np.gradient(hgt, axis=1)
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
    if np.ndim(t) == 2 and np.ndim(a) != 2:
        t = t[..., None]
    return a * (1.0 - t) + np.asarray(b, np.float32) * t


def rgb_img(a):
    return Image.fromarray(np.clip(a * 255.0 + 0.5, 0, 255).astype(np.uint8), "RGB")


def arr(img):
    return np.asarray(img, np.float32) / 255.0


def luma(c):
    return c[..., 0] * 0.2126 + c[..., 1] * 0.7152 + c[..., 2] * 0.0722


def wrapd(d, S):
    """Signed periodic distance."""
    return (d + S / 2.0) % S - S / 2.0


def V(*c):
    return np.array(c, np.float32)


def wrap_lines(S, k, lines):
    """Antialiased periodic polylines: lines = [(points, width_px)], drawn in the 9 neighbouring tiles."""
    img = Image.new("L", (S * k, S * k), 0)
    d = ImageDraw.Draw(img)
    for pts, w in lines:
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        for ox in (-S, 0, S):
            if max(xs) + ox < -4 or min(xs) + ox > S + 4:
                continue
            for oy in (-S, 0, S):
                if max(ys) + oy < -4 or min(ys) + oy > S + 4:
                    continue
                d.line([((x + ox) * k, (y + oy) * k) for x, y in pts], fill=255, width=max(1, int(round(w * k))),
                       joint="curve")
    return arr(img.resize((S, S), Image.LANCZOS))


# ------------------------------------------------------------------ damask wallpaper

def leaf_poly(x0, y0, ang, L, W, bend=0.0, n=16):
    """Pointed leaf from its base, heading `ang`, curling by `bend` radians over its length -> (outline, midrib)."""
    left, right, mid = [], [], []
    x, y = x0, y0
    for i in range(n + 1):
        s = i / n
        a = ang + bend * s
        if i:
            x += math.cos(a) * L / n
            y += math.sin(a) * L / n
        w = W * math.sin(math.pi * s ** 0.8) ** 0.8
        nx, ny = -math.sin(a), math.cos(a)
        left.append((x + nx * w, y + ny * w))
        right.append((x - nx * w, y - ny * w))
        mid.append((x, y))
    return left + right[::-1], mid


def _damask_unit():
    """256x256 unit (26.5 cm) drawn at 4x: returns (fill, carve, ogee) masks in [0,1]. The motif is centred; the
    half-drop copy is added by the caller."""
    k = 4
    U = 256 * k
    m = Image.new("L", (U, U), 0)
    d = ImageDraw.Draw(m)
    c = Image.new("L", (U, U), 0)
    dc = ImageDraw.Draw(c)
    og = Image.new("L", (U, U), 0)
    do = ImageDraw.Draw(og)

    def P(pts):
        return [(x * k, y * k) for x, y in pts]

    def mir(pts):
        return [(256 - x, y) for x, y in pts]

    def leaf(x0, y0, deg, L, W, bend=0.0, vein=True):
        poly, mid = leaf_poly(x0, y0, math.radians(deg), L, W, math.radians(bend))
        for pp in (poly, mir(poly)):
            d.polygon(P(pp), fill=255)
        if vein:
            mm = mid[2:int(len(mid) * 0.82)]
            for pp in (mm, mir(mm)):
                dc.line(P(pp), fill=255, width=int(1.25 * k))

    def dot(cx, cy, rx, ry=None, img=d):
        ry = ry or rx
        for x in (cx, 256 - cx):
            img.ellipse([(x - rx) * k, (cy - ry) * k, (x + rx) * k, (cy + ry) * k], fill=255)

    def scroll(cx, cy, r0, a0, a1, w0, w1, shrink=0.82, leaves=()):
        n = 90
        for i in range(n + 1):
            t = i / n
            a = math.radians(a0 + (a1 - a0) * t)
            r = r0 * (1 - shrink * t)
            x, y = cx + r * math.cos(a), cy + r * math.sin(a)
            w = w0 + (w1 - w0) * t
            dot(x, y, w)
        dot(cx + r0 * (1 - shrink) * math.cos(math.radians(a1)), cy + r0 * (1 - shrink) * math.sin(math.radians(a1)),
            w1 * 1.9)
        for t, L, W, turn in leaves:
            a = math.radians(a0 + (a1 - a0) * t)
            r = r0 * (1 - shrink * t)
            x, y = cx + r * math.cos(a), cy + r * math.sin(a)
            leaf(x, y, math.degrees(a) + turn, L, W, bend=28)

    # upper palmette
    leaf(128, 142, -90, 76, 10.5)
    leaf(128, 142, -114, 63, 9, -12)
    leaf(128, 142, -138, 51, 8, -20)
    leaf(128, 142, -162, 39, 7, -30)
    leaf(128, 142, -188, 28, 6, -42)
    # lower pendant palmette
    leaf(128, 148, 90, 64, 9.5)
    leaf(128, 148, 116, 50, 8, 16)
    leaf(128, 148, 142, 38, 7, 26)
    leaf(128, 148, 168, 27, 6, 38)
    # centre boss
    dot(128, 145, 10, 12)
    dc.ellipse([(128 - 4.5) * k, (145 - 6) * k, (128 + 4.5) * k, (145 + 6) * k], fill=255)
    d.ellipse([(128 - 2) * k, (145 - 3) * k, (128 + 2) * k, (145 + 3) * k], fill=255)
    # big lower C-scrolls with leaflets, small upper scrolls
    scroll(80, 172, 35, 55, 470, 6.0, 2.2, leaves=((0.10, 20, 5, 55), (0.24, 22, 5.5, 60), (0.38, 20, 5, 62), (0.5, 15, 4, 65)))
    scroll(86, 92, 19, 130, 500, 4.2, 1.7, leaves=((0.12, 14, 3.6, 60), (0.3, 13, 3.4, 62)))
    # finial and drop
    leaf(128, 64, -90, 36, 6.2)
    leaf(128, 62, -140, 22, 4.6, -26)
    dot(128, 19, 3.6)
    dot(128, 8.5, 2.2, 3.4)
    leaf(128, 212, 140, 18, 4, 22, vein=False)
    dot(128, 224, 4.0, 6.2)
    dot(128, 237, 2.8)
    dot(128, 247, 1.8, 2.6)

    # ogee lattice between the half-drop columns (a beaded stem), periodic in y
    def xl(y):
        return 64 - 37 * math.cos(2 * math.pi * (y - 128) / 256.0)

    for off in (-256, 0, 256):
        pts = [(xl(y), y + off) for y in range(0, 257, 2)]
        for pp in (pts, mir(pts)):
            do.line(P(pp), fill=255, width=int(2.3 * k), joint="curve")
        for j in range(16):
            y = 8 + j * 16
            r = 3.0 if j % 2 == 0 else 1.9
            dot(xl(y), y + off, r, img=do)

    def down(i):
        return np.clip(arr(i.resize((256, 256), Image.LANCZOS)), 0, 1)

    return down(m), down(c), down(og)


def gen_wallpaper_house():
    S = 1024
    f, c, og = _damask_unit()
    f = np.maximum(f, np.roll(f, (128, 128), axis=(0, 1)))
    c = np.maximum(c, np.roll(c, (128, 128), axis=(0, 1)))
    f = np.maximum(f, og)
    fill = np.tile(f, (4, 4))
    carve = np.tile(c, (4, 4))
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)

    fine = fft_noise(S, 0.3, 9101, lo=90)
    fibre = fft_noise(S, 0.8, 9102, lo=30, hi=400, sx=0.12, sy=1.0)        # vertical paper fibres
    lo = eq(fft_noise(S, 1.9, 9103, lo=1, hi=6))
    lo2 = eq(fft_noise(S, 1.8, 9113, lo=1, hi=9))
    md = eq(fft_noise(S, 1.4, 9104, lo=3, hi=30))
    hi_ = eq(fft_noise(S, 1.0, 9107, lo=12, hi=90))

    ground = V(0.085, 0.200, 0.142)
    ground_hi = V(0.110, 0.240, 0.165)          # satin tone-on-tone halo around the motif
    gold = V(0.640, 0.510, 0.225)
    gold_d = V(0.400, 0.300, 0.120)

    halo = np.clip(blur_wrap(fill, 5.0) * 1.6, 0, 1)
    col = np.empty((S, S, 3), np.float32)
    col[:] = ground
    col = mix(col, ground_hi, halo * 0.55)
    rib = 0.5 + 0.5 * np.sin(2 * np.pi * xx / 3.2)                          # fine vertical ribbing of the ground
    col *= (0.93 + 0.07 * rib * (1 - fill))[..., None]
    col *= (0.93 + 0.10 * fine + 0.07 * (fibre - 0.5))[..., None]

    # faded, unevenly rubbed gold print (darker in the middle of each shape, carved veins show the ground)
    motif = fill * (1.0 - 0.85 * carve)
    shade = np.clip(blur_wrap(fill, 2.2), 0, 1)
    ink = (0.45 + 0.55 * sstep(0.22, 0.62, fine)) * (0.50 + 0.50 * md) * (0.65 + 0.35 * lo2)
    g = mix(gold, gold_d, sstep(0.55, 1.0, shade) * 0.6)
    g = g * (0.86 + 0.28 * hi_)[..., None]
    col = mix(col, g, motif * ink * 0.92)

    # ---- ageing: grime (darker, browner), fading
    grime = np.clip(lo * 1.25 - 0.15, 0, 1)
    col = mix(col, col * V(0.56, 0.54, 0.50), grime * 0.75)
    col = mix(col, col * V(0.80, 0.74, 0.62), np.clip(md * 2 - 1.1, 0, 1) * 0.45)
    soot = np.clip(fft_noise(S, 1.0, 9108, lo=14, hi=110) * 6 - 4.3, 0, 1)
    col = mix(col, col * V(0.55, 0.50, 0.44), soot * 0.5 * (0.3 + 0.7 * lo))

    # ---- water stains running down (head at the top, fading downwards, brown tide lines)
    rng = np.random.default_rng(9120)
    wash = np.zeros((S, S), np.float32)
    tide = np.zeros((S, S), np.float32)
    for i in range(8):
        x0 = rng.uniform(0, S)
        y0 = rng.uniform(0, S)
        L = rng.uniform(380, 900)
        w0 = rng.uniform(9, 30)
        p1, p2 = rng.uniform(0, 6.28, 2)
        dy = (yy - y0) % S
        s = dy / L
        on = (s < 1.0).astype(np.float32)
        xc = x0 + 10 * np.sin(dy / 83.0 + p1) + 4 * np.sin(dy / 23.0 + p2) + (md - 0.5) * 9
        dx = np.abs(wrapd(xx - xc, S))
        sc = np.clip(s, 0.0, 1.0)
        w = w0 * (0.55 + 0.6 * np.clip(np.sin(np.pi * sc ** 0.6), 0, 1) ** 0.7) * (1.0 - 0.55 * sc)
        w = np.maximum(w, 1.5)
        a = on * sstep(0.0, 0.03, s) * (1.0 - sc) ** 0.6
        wash = np.maximum(wash, a * sstep(w, w * 0.55, dx))
        tide = np.maximum(tide, a * np.exp(-((dx - w) / 1.7) ** 2) * (0.55 + 0.45 * hi_))
    drip = eq(fft_noise(S, 1.9, 9105, lo=1, hi=40, sx=0.22, sy=1.0))
    wash = np.maximum(wash, sstep(0.90, 0.95, drip) * 0.7)
    tide = np.maximum(tide, np.clip(sstep(0.88, 0.905, drip) - sstep(0.91, 0.95, drip), 0, 1) * 0.7)
    washed = col * V(1.10, 1.02, 0.86) + V(0.045, 0.040, 0.022)                 # dye bleached, yellowed, chalky
    col = mix(col, washed, wash * 0.60)
    col = mix(col, col * V(0.50, 0.40, 0.27), tide * 0.62)

    # ---- two 53 cm strips: seams at x = 256 and 768, lifted in places (curled edge, shadow, brown backing)
    seam = np.zeros((S, S), np.float32)
    liftm = np.zeros((S, S), np.float32)
    curl = np.zeros((S, S), np.float32)
    gapm = np.zeros((S, S), np.float32)
    for sx_, ph in ((256.0, 0.0), (768.0, 2.1)):
        wob = 0.6 * np.sin(yy / 37.0 + sx_)
        dx = xx - sx_ - wob
        gap = 0.55 + 0.45 * np.sin(2 * np.pi * yy * 11 / S + sx_ * 0.01) * np.sin(2 * np.pi * yy * 60 / S)
        seam = np.maximum(seam, np.exp(-(dx / 0.9) ** 2) * (0.45 + 0.55 * gap))
        la = np.clip(np.sin(2 * np.pi * yy * 2 / S + ph) * 0.7 + np.sin(2 * np.pi * yy * 5 / S + ph * 3) * 0.6 - 0.72, 0, 1)
        la = np.clip(la * 2.6, 0, 1)                                         # where this seam has let go
        opening = la * 5.5
        gapm = np.maximum(gapm, sstep(0.0, 1.2, opening - np.abs(dx - opening * 0.5) * 2.0 + 0.2) * (la > 0.02))
        curl = np.maximum(curl, la * np.exp(-((dx - opening - 3.5) / 3.2) ** 2))
        liftm = np.maximum(liftm, np.exp(-((dx - 3.5) / 3.0) ** 2) * 0.6 + np.exp(-((dx + 2.5) / 2.0) ** 2) * 0.25)
    strip_b = ((xx >= 256) & (xx < 768)).astype(np.float32)
    col *= (1.0 - 0.03 * strip_b)[..., None]
    col = mix(col, col * V(0.45, 0.40, 0.32), seam * 0.6)
    col = mix(col, col * 1.06, liftm * 0.5)
    backing = V(0.300, 0.205, 0.120) * (0.75 + 0.5 * fibre)[..., None] * (0.85 + 0.3 * fine)[..., None]
    col = mix(col, backing * 0.55, gapm * 0.95)
    col = mix(col, col * 1.45 + V(0.02, 0.025, 0.02), curl * 0.55)
    dirtseam = np.clip(blur_wrap(seam, 6.0) * 3.0, 0, 1)
    col = mix(col, col * V(0.70, 0.64, 0.54), dirtseam * 0.45 * md)

    # ---- small tears: brown backing paper, pale torn fibre edge, shadow under the upper lip
    tear = np.zeros((S, S), np.float32)
    tn = fft_noise(S, 1.15, 9130, lo=4, hi=110)
    for cx, cy, rx, ry, rot in ((610, 180, 17, 52, 0.30), (132, 650, 34, 13, -0.2), (905, 820, 11, 30, 0.1),
                                (776, 430, 8, 40, 0.03), (350, 930, 17, 9, 0.6)):
        dx = wrapd(xx - cx, S)
        dy = wrapd(yy - cy, S)
        u = dx * math.cos(rot) + dy * math.sin(rot)
        v = -dx * math.sin(rot) + dy * math.cos(rot)
        v = v + 0.5 * ry * (np.abs(u) / rx)                                  # torn downwards to a ragged point
        e = (u / rx) ** 2 + (v / ry) ** 2
        tear = np.maximum(tear, sstep(1.0, 0.90, e + (tn - 0.5) * 2.6))
    edge = np.clip(ndi.maximum_filter(tear, size=3, mode="wrap") - tear, 0, 1) * sstep(0.25, 0.8, hi_)
    shadow = np.clip(np.roll(tear, 3, axis=0) * tear - 0.0, 0, 1)
    lip = np.clip(tear - np.roll(tear, 4, axis=0), 0, 1)                     # just under the upper edge
    back2 = V(0.250, 0.185, 0.125) * (0.70 + 0.55 * fibre)[..., None] * (0.80 + 0.4 * fine)[..., None]
    back2 = mix(back2, V(0.34, 0.32, 0.28) * (0.8 + 0.4 * fine)[..., None], sstep(0.55, 0.8, md) * 0.7)   # bare plaster shows
    col = mix(col, back2 * (0.75 + 0.3 * md)[..., None], tear)
    col = mix(col, col * 0.45, lip * 0.8)
    col = mix(col, V(0.40, 0.37, 0.29) * (0.8 + 0.4 * fine)[..., None], edge * 0.65)
    del shadow

    # overall level: reads dark (mean luminance ~ 22 %)
    col = np.clip(col, 0, 1)
    col *= 0.222 / float(luma(col).mean())
    print("  wallpaper_house mean luminance %.3f" % float(luma(np.clip(col, 0, 1)).mean()))
    save(rgb_img(col), "wallpaper_house.jpg", 88)

    h = (fine - 0.5) * 0.5 + (fibre - 0.5) * 0.7 + motif * 0.14 - seam * 0.9 + liftm * 0.4 + (md - 0.5) * 0.7
    h += curl * 2.4 - gapm * 1.6 - tear * 1.1 + edge * 0.7 + tide * 0.25 + (lo2 - 0.5) * 0.8
    save(normal_from_height(blur_wrap(h.astype(np.float32), 0.6), 0.9), "wallpaper_house_n.png")


# ------------------------------------------------------------------ old ceiling plaster

def _cracks(S, seed):
    rnd = random.Random(seed)
    lines = []
    anchors = []

    def walk(x, y, a, steps, w0, depth):
        pts = [(x, y)]
        for i in range(steps):
            a += rnd.gauss(0, 0.20)
            if rnd.random() < 0.07:
                a += rnd.choice((-1, 1)) * rnd.uniform(0.5, 1.1)
            x += math.cos(a) * 6.0
            y += math.sin(a) * 6.0
            pts.append((x, y))
            if depth < 2 and rnd.random() < 0.035 and i > 4:
                walk(x, y, a + rnd.choice((-1, 1)) * rnd.uniform(0.5, 1.2), rnd.randint(12, 55), w0 * 0.7, depth + 1)
        n = len(pts)
        for j in range(0, n - 1, 8):
            t = j / max(1, n - 1)
            lines.append((pts[j:j + 9], w0 * (1.0 - 0.6 * t)))
        anchors.append(pts[len(pts) // 3])

    for _ in range(6):
        walk(rnd.uniform(0, S), rnd.uniform(0, S), rnd.uniform(0, 6.28), rnd.randint(50, 150), rnd.uniform(0.75, 1.25), 0)
    return wrap_lines(S, 2, lines), anchors


def gen_plaster_old():
    S = 1024
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    fine = fft_noise(S, 0.2, 9201, lo=120)
    grain = fft_noise(S, 0.9, 9202, lo=25, hi=300)
    trowel = fft_noise(S, 1.6, 9203, lo=2, hi=40, sx=0.35, sy=1.0)           # long soft float marks
    trowel2 = fft_noise(S, 1.6, 9213, lo=2, hi=40, sx=1.0, sy=0.3)
    lo = eq(fft_noise(S, 2.0, 9204, lo=1, hi=5))
    md = eq(fft_noise(S, 1.5, 9205, lo=3, hi=28))
    warp = fft_noise(S, 1.8, 9206, lo=1, hi=10)
    crack, anchors = _cracks(S, 9207)
    crack = np.clip(crack * 1.3, 0, 1)

    col = np.empty((S, S, 3), np.float32)
    col[:] = V(0.820, 0.800, 0.740)
    col *= (0.90 + 0.07 * grain + 0.06 * fine + 0.10 * (trowel - 0.5) + 0.08 * (trowel2 - 0.5))[..., None]
    # age: yellowing, grey soot shadows, dull blotches
    col = mix(col, col * V(0.95, 0.89, 0.74), np.clip(lo * 1.3 - 0.3, 0, 1) * 0.50)
    col = mix(col, col * V(0.80, 0.79, 0.78), np.clip(md * 1.6 - 0.8, 0, 1) * 0.45)
    specks = np.clip(fft_noise(S, 0.6, 9208, lo=40, hi=200) * 9 - 7.0, 0, 1)
    col = mix(col, col * V(0.60, 0.52, 0.40), specks * 0.5)

    # yellow-brown water rings (several tide lines each)
    fillm = np.zeros((S, S), np.float32)
    ring = np.zeros((S, S), np.float32)
    for cx, cy, R, squash in ((300, 260, 150, 1.25), (770, 660, 105, 0.8), (640, 180, 46, 1.15)):
        dx = wrapd(xx - cx, S)
        dy = wrapd(yy - cy, S) * squash
        r = np.sqrt(dx * dx + dy * dy) * (1.0 + 0.55 * (warp - 0.5)) + (md - 0.5) * 14
        inside = sstep(R, R - 5, r)
        fillm = np.maximum(fillm, inside * (0.35 + 0.65 * sstep(0.0, R, r)))
        for kf, a in ((1.0, 1.0), (0.80, 0.55), (0.56, 0.4), (0.33, 0.3)):
            ring = np.maximum(ring, a * np.exp(-((r - R * kf) / 2.4) ** 2) * (0.55 + 0.45 * grain))
            ring = np.maximum(ring, a * 0.45 * sstep(R * kf, R * kf - 16, r) * sstep(R * kf - 34, R * kf - 10, r))
    col = mix(col, col * V(0.92, 0.84, 0.64), fillm * 0.50)
    col = mix(col, col * V(0.66, 0.52, 0.32), ring * 0.55)

    # flaked patches: the skim coat has come off, grey sandy undercoat shows, sharp edge
    fn = fft_noise(S, 1.0, 9209, lo=5, hi=120)
    flake = np.zeros((S, S), np.float32)
    spots = [(anchors[0][0], anchors[0][1], 34), (anchors[3][0], anchors[3][1], 24), (anchors[5][0], anchors[5][1], 28),
             (330, 300, 30), (700, 880, 18)]
    for cx, cy, R in spots:
        dx = wrapd(xx - cx, S)
        dy = wrapd(yy - cy, S)
        e = np.sqrt(dx * dx + dy * dy) / R
        flake = np.maximum(flake, sstep(1.0, 0.95, e + (fn - 0.5) * 3.4))
    under = V(0.640, 0.610, 0.545) * (0.74 + 0.34 * grain + 0.26 * fine)[..., None]
    under = mix(under, under * V(0.80, 0.72, 0.58), fillm * 0.6)
    rim_dark = np.clip(flake - np.roll(np.roll(flake, 3, axis=0), 2, axis=1), 0, 1)      # shadow under the upper-left edge
    rim_lite = np.clip(np.roll(np.roll(flake, 2, axis=0), 1, axis=1) - flake, 0, 1)      # lit lower-right lip
    loose = np.clip(ndi.maximum_filter(flake, size=13, mode="wrap") - flake, 0, 1)       # paint about to go
    col = mix(col, under, flake)
    col = mix(col, col * 0.55, rim_dark * 0.75)
    col = mix(col, col * 1.10, np.clip(rim_lite, 0, 1) * 0.6)
    col = mix(col, col * 1.05, loose * 0.5 * md)

    # hairline cracks (dark core, faint stained halo)
    halo = np.clip(blur_wrap(crack, 3.0) * 2.2, 0, 1)
    col = mix(col, col * V(0.90, 0.85, 0.74), halo * 0.4)
    col = mix(col, col * V(0.36, 0.33, 0.29), crack * 0.75)
    save(rgb_img(col), "plaster_old.jpg", 88)

    h = (fine - 0.5) * 0.35 + (grain - 0.5) * 0.9 + (trowel - 0.5) * 2.2 + (trowel2 - 0.5) * 1.6 + (lo - 0.5) * 1.5
    h += -crack * 1.6 - flake * 2.2 + flake * (grain - 0.5) * 1.5 + loose * md * 0.8 + ring * 0.25
    save(normal_from_height(blur_wrap(h.astype(np.float32), 0.6), 1.1), "plaster_old_n.png")


# ------------------------------------------------------------------ hallway runner carpet (v wraps, u does not)

def gen_rug_runner():
    W, H = 512, 1024
    KW, KH = 128, 256                                # knots (4 px = 6 mm each)
    RED, RED2, CREAM, OCHRE, NAVY, DARK = range(6)
    pal = np.array([[0.330, 0.062, 0.058], [0.240, 0.045, 0.048], [0.700, 0.615, 0.440], [0.590, 0.410, 0.150],
                    [0.085, 0.095, 0.130], [0.095, 0.065, 0.055]], np.float32)
    idx = np.zeros((KH, KW), np.int32)
    half = KW // 2
    for j in range(KH):
        for i in range(half):
            c = RED
            if i < 3:
                c = DARK
            elif i < 6:
                c = (CREAM, NAVY, CREAM)[i - 3]
            elif i < 24:
                # main border: cream ground, stepped diamonds every 32 knots, crosses between, running-dog edges
                u = i - 14.5
                v = (j % 32) - 15.5
                dd = abs(u) / 7.5 + abs(v) / 13.0
                c = CREAM
                if i in (6, 23):
                    c = OCHRE if ((i + j) % 4) < 2 else NAVY
                elif dd < 0.36:
                    c = NAVY
                elif dd < 0.68:
                    c = OCHRE
                elif dd < 1.0:
                    c = RED
                else:
                    v2 = ((j + 16) % 32) - 15.5
                    if (abs(u) < 1 and abs(v2) < 3.5) or (abs(v2) < 1 and abs(u) < 3.5):
                        c = NAVY
                    elif abs(abs(u) - 6) < 0.6 and int(abs(v2)) % 4 < 2 and abs(v2) < 6:
                        c = OCHRE
            elif i < 27:
                c = (NAVY, OCHRE, NAVY)[i - 24]
            else:
                # field: staggered small diamonds, a row of stepped lozenge medallions down the middle
                u = i - 63.5
                v = (j % 64) - 31.5
                dm = abs(u) / 17.0 + abs(v) / 26.0
                if dm < 0.30:
                    c = OCHRE
                elif dm < 0.52:
                    c = NAVY
                elif dm < 0.78:
                    c = RED2
                elif dm < 1.0:
                    c = CREAM if int(abs(u) + abs(v)) % 3 == 0 else OCHRE
                else:
                    a = (i - 27) % 16 - 7.5
                    b = ((j + (8 if ((i - 27) // 16) % 2 else 0)) % 16) - 7.5
                    ds = abs(a) + abs(b)
                    if ds < 1.2:
                        c = OCHRE
                    elif ds < 3.2:
                        c = RED2
                    elif abs(ds - 5) < 0.6:
                        c = NAVY if (i + j) % 2 else RED
            idx[j, i] = c
            idx[j, KW - 1 - i] = c
    rng = np.random.default_rng(9301)
    knot = rng.uniform(0.86, 1.10, (KH, KW)).astype(np.float32)
    col = pal[idx] * knot[..., None]
    col = np.repeat(np.repeat(col, 4, axis=0), 4, axis=1)                     # (1024, 512, 3)

    N = lambda beta, seed, **kw: fft_noise(1024, beta, seed, **kw)[:, :W]     # periodic in v
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    # hand-woven irregularity: rows and columns wander by a pixel or two
    sx = (N(1.6, 9302, lo=1, hi=12) - 0.5) * 9.0
    sy = (N(1.6, 9303, lo=1, hi=12) - 0.5) * 7.0
    cc = np.stack([ndi.map_coordinates(col[..., k], [(yy + sy) % H, np.clip(xx + sx, 0, W - 1)], order=1, mode="grid-wrap")
                   for k in range(3)], axis=-1)
    col = cc
    # abrash (dye lots change along the length) and pile shading
    row = fft_noise(1024, 1.2, 9304, lo=2, hi=60, sx=0.0001, sy=1.0)[:, :W]
    col *= (0.90 + 0.20 * row)[..., None]
    pile = 0.80 + 0.20 * np.abs(np.sin(np.pi * (yy + sy) / 4.0)) ** 0.6 * (0.75 + 0.25 * np.abs(np.sin(np.pi * (xx + sx) / 4.0)))
    fine = N(0.2, 9305, lo=120)
    tuft = N(0.8, 9306, lo=40, hi=350, sx=1.0, sy=0.45)
    col *= (pile * (0.84 + 0.20 * fine + 0.16 * tuft))[..., None]
    col = np.stack([ndi.gaussian_filter(col[..., k], 0.7, mode=("wrap", "nearest")) for k in range(3)], axis=-1)

    lo = eq(N(1.9, 9307, lo=1, hi=6))
    md = eq(N(1.4, 9308, lo=3, hi=30))
    hi_ = eq(N(1.0, 9309, lo=14, hi=110))
    # general fading / sun and wash: colours pulled towards a dusty brown
    dusty = luma(col)[..., None] * V(1.05, 0.92, 0.74)
    col = mix(col, dusty, 0.20 + 0.20 * lo)

    # threadbare path down the middle: pile gone, grey-beige foundation (warp / weft grid) shows
    cx = W * 0.5 + (N(1.8, 9310, lo=1, hi=5)[:, :1] - 0.5) * 70 + (md - 0.5) * 30
    hw = 105 + (N(1.8, 9311, lo=1, hi=4)[:, :1] - 0.5) * 60
    t = 1.0 - np.abs(xx - cx) / hw
    wear = np.clip(t * 1.5 + (md - 0.5) * 0.9 + (hi_ - 0.5) * 0.5, 0, 1)
    wear = sstep(0.25, 1.0, wear)
    warp_t = 0.5 + 0.5 * np.sin(2 * np.pi * (xx + sx) / 4.0)
    weft_t = 0.5 + 0.5 * np.sin(2 * np.pi * (yy + sy) / 4.0)
    found = V(0.400, 0.350, 0.270) * (0.62 + 0.30 * warp_t * weft_t + 0.22 * fine)[..., None]
    found = mix(found, col * 1.15, 0.30)                                      # a ghost of the pattern remains
    col = mix(col, found, wear * 0.90)
    # edge wear near the binding, a few bald spots elsewhere
    spots = sstep(0.93, 0.985, md) * (1 - wear)
    col = mix(col, found, spots * 0.7)

    # dirt: trodden-in dark soil (strongest along the path edges), stains
    path_edge = np.clip(1.0 - np.abs(np.abs(xx - cx) - hw * 0.8) / 60.0, 0, 1)
    dirt = np.clip(lo * 0.9 + path_edge * 0.45 + (md - 0.5) * 0.5 - 0.25, 0, 1)
    col = mix(col, col * V(0.50, 0.46, 0.40), dirt * 0.75)
    stain = sstep(0.90, 0.96, eq(N(1.8, 9312, lo=2, hi=14)))
    col = mix(col, col * V(0.52, 0.45, 0.36), stain * 0.6)
    # frayed overcast edges
    ed = np.minimum(xx, W - 1 - xx)
    fray = sstep(7.0, 0.0, ed + (hi_ - 0.5) * 8)
    col = mix(col, col * 0.45, fray * 0.8)
    col *= 0.92
    save(rgb_img(np.clip(col, 0, 1)), "rug_runner.jpg", 88)


# ------------------------------------------------------------------ bare trees (night window, winter photograph)

def limb(d, x, y, ang, length, width, depth, rnd, k, fill, up=0.0):
    n = max(3, int(length / 13))
    a = ang
    for i in range(n):
        a += rnd.uniform(-0.24, 0.24) + up * math.sin(-math.pi / 2 - a) * 0.12
        x2 = x + math.cos(a) * length / n
        y2 = y + math.sin(a) * length / n
        w = width * (1.0 - 0.55 * (i + 1) / n)
        ww = max(1, int(round(w * k)))
        d.line([x * k, y * k, x2 * k, y2 * k], fill=fill, width=ww)
        if ww > 2:
            d.ellipse([x2 * k - ww / 2, y2 * k - ww / 2, x2 * k + ww / 2, y2 * k + ww / 2], fill=fill)
        x, y = x2, y2
        if depth > 0 and i > 0 and rnd.random() < 0.5:
            limb(d, x, y, a + rnd.choice((-1, 1)) * rnd.uniform(0.4, 1.0), length * rnd.uniform(0.42, 0.7), w * 0.6,
                 depth - 1, rnd, k, fill, up)
    if depth > 0:
        for s in (-1, 1):
            limb(d, x, y, a + s * rnd.uniform(0.2, 0.55), length * rnd.uniform(0.5, 0.7), width * 0.42, depth - 1, rnd, k,
                 fill, up)


def gen_night_window():
    W, H = 512, 768
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    u = xx / W
    v = yy / H
    top = V(0.012, 0.020, 0.048)
    bot = V(0.050, 0.075, 0.135)
    col = mix(np.broadcast_to(top, (H, W, 3)).copy(), bot, v ** 0.85)
    # the moon is out of frame, above the top right corner
    dm = np.sqrt(((u - 1.12) * W / H) ** 2 + (v + 0.10) ** 2)
    glow = np.exp(-(dm / 0.42) ** 2)
    wide = np.exp(-(dm / 0.95) ** 2)
    col += glow[..., None] * V(0.110, 0.145, 0.215) + wide[..., None] * V(0.02, 0.03, 0.05)
    # torn clouds, stretched along a slight diagonal, lit from behind (bright thin edges, dark cores)
    n1 = fft_noise(1024, 1.75, 9401, lo=1, hi=200, sx=0.55, sy=1.0)
    n2 = fft_noise(1024, 1.3, 9402, lo=6, hi=300, sx=0.6, sy=1.0)
    sk = [(yy + xx * 0.22) % 1024, xx]
    c1 = ndi.map_coordinates(eq(n1), sk, order=1, mode="grid-wrap")
    c2 = ndi.map_coordinates(n2, sk, order=1, mode="grid-wrap")
    dens = sstep(0.42, 0.86, c1 + (c2 - 0.5) * 0.55)
    thin = dens * (1.0 - dens) * 4.0
    lit = (thin * 0.85 + dens * 0.25) * (0.12 + 1.35 * wide)
    col = col * (1.0 - 0.45 * dens * (1.0 - wide))[..., None]
    col += lit[..., None] * V(0.150, 0.185, 0.255)
    # a few faint stars in the gaps
    rng = np.random.default_rng(9403)
    for _ in range(70):
        x, y = int(rng.uniform(0, W)), int(rng.uniform(0, H * 0.8))
        col[y, x] += (1.0 - dens[y, x]) ** 3 * rng.uniform(0.03, 0.14) * V(0.9, 0.95, 1.0)
    col = np.stack([ndi.gaussian_filter(col[..., k], 0.6) for k in range(3)], axis=-1)

    # black bare branches reaching in from both edges
    k = 3
    m = Image.new("L", (W * k, H * k), 0)
    d = ImageDraw.Draw(m)
    rnd = random.Random(9404)
    for x0, y0, a0, L, w in ((-14, 300, -0.30, 250, 10), (-14, 560, -0.55, 235, 8), (-10, 700, -0.15, 180, 6),
                             (-12, 120, 0.25, 150, 5)):
        limb(d, x0, y0, a0, L, w, 4, rnd, k, 255, up=0.5)
    for x0, y0, a0, L, w in ((526, 210, math.pi + 0.35, 240, 9), (526, 470, math.pi + 0.5, 250, 9),
                             (522, 690, math.pi + 0.2, 190, 6), (524, 60, math.pi - 0.2, 130, 4)):
        limb(d, x0, y0, a0, L, w, 4, rnd, k, 255, up=0.5)
    br = ndi.gaussian_filter(arr(m.resize((W, H), Image.LANCZOS)), 0.55)
    col = mix(col, V(0.006, 0.008, 0.012), np.clip(br * 1.25, 0, 1))
    # keep it dark: max luminance <= 34 %; dither against banding
    col = np.clip(col, 0, None)
    mx = float(luma(col).max())
    if mx > 0.34:
        col *= 0.34 / mx
    col += (rng.random((H, W, 1)).astype(np.float32) - 0.5) * (1.6 / 255.0)
    col = np.clip(col, 0, 1)
    print("  night_window luminance max %.3f mean %.3f" % (float(luma(col).max()), float(luma(col).mean())))
    save(rgb_img(col), "night_window.png")


# ------------------------------------------------------------------ sepia photographs (generic drawn figures)

class Pen:
    """Greyscale drawing surface (512 units, 2x supersampled) with a scale / offset transform."""

    def __init__(self, base, k=2):
        self.k = k
        self.img = Image.fromarray(np.clip(base * 255, 0, 255).astype(np.uint8), "L").resize((512 * k, 512 * k), Image.BILINEAR)
        self.d = ImageDraw.Draw(self.img)
        self.s, self.ox, self.oy = 1.0, 0.0, 0.0

    def T(self, x, y):
        return ((x * self.s + self.ox) * self.k, (y * self.s + self.oy) * self.k)

    def poly(self, pts, v):
        self.d.polygon([self.T(*p) for p in pts], fill=v)

    def ell(self, cx, cy, rx, ry, v):
        x0, y0 = self.T(cx - rx, cy - ry)
        x1, y1 = self.T(cx + rx, cy + ry)
        self.d.ellipse([x0, y0, x1, y1], fill=v)

    def rect(self, x0, y0, x1, y1, v):
        a, b = self.T(x0, y0)
        c, e = self.T(x1, y1)
        self.d.rectangle([a, b, c, e], fill=v)

    def line(self, pts, v, w):
        ww = max(1, int(round(w * self.s * self.k)))
        self.d.line([self.T(*p) for p in pts], fill=v, width=ww, joint="curve")
        if ww > 3:
            for p in (pts[0], pts[-1]):
                x, y = self.T(*p)
                self.d.ellipse([x - ww / 2, y - ww / 2, x + ww / 2, y + ww / 2], fill=v)

    def get(self):
        return arr(self.img.resize((512, 512), Image.LANCZOS))


def backdrop(seed, top, bottom, floor_y=None, floor_v=0.3):
    yy, xx = np.mgrid[0:512, 0:512].astype(np.float32)
    g = top + (bottom - top) * (yy / 511.0)
    g = g + (fft_noise(512, 2.0, seed, lo=1, hi=12) - 0.5) * 0.22           # painted studio cloth
    g -= 0.10 * np.exp(-(((xx - 256) / 300.0) ** 2)) * 0 + 0.0
    if floor_y is not None:
        g = np.where(yy > floor_y, floor_v + (yy - floor_y) / 512.0 * 0.15, g)
    return np.clip(g, 0, 1).astype(np.float32)


def draw_woman(p, face=True):
    """Seated woman, dark dress, hair in a bun, hands on her lap (base frame: head at 256,134)."""
    DRESS, DRESS2, SKIN, HAIR, WOOD = 30, 44, 176, 34, 52
    # chair back
    for x in (170, 342):
        p.line([(x, 150), (x, 345)], WOOD, 13)
        p.ell(x, 143, 9, 10, WOOD + 8)
    p.line([(170, 166), (342, 166)], WOOD, 12)
    p.line([(170, 262), (342, 262)], WOOD - 6, 9)
    # skirt (seated: spreads to the bottom of the frame), folds
    p.poly([(200, 298), (312, 298), (372, 372), (404, 512), (108, 512), (140, 372)], DRESS)
    for x0, x1 in ((222, 196), (250, 240), (282, 296), (305, 338), (190, 150), (330, 372)):
        p.line([(x0, 352), ((x0 + x1) / 2 + 3, 430), (x1, 512)], DRESS2, 3.5)
    # torso, puffed sleeves, arms folded down to the lap
    p.poly([(190, 196), (322, 196), (306, 304), (206, 304)], DRESS)
    p.ell(196, 222, 27, 34, DRESS + 3)
    p.ell(316, 222, 27, 34, DRESS + 3)
    p.line([(190, 232), (184, 298)], DRESS + 4, 31)
    p.line([(322, 232), (328, 298)], DRESS + 4, 31)
    p.line([(184, 298), (238, 334)], DRESS + 6, 25)
    p.line([(328, 298), (274, 336)], DRESS + 6, 25)
    p.line([(196, 252), (200, 292)], DRESS2 + 8, 3)
    p.line([(316, 252), (312, 292)], DRESS2 + 8, 3)
    for x in range(232, 284, 9):                                              # buttons down the bodice
        pass
    for y in range(214, 296, 16):
        p.ell(256, y, 2.6, 2.6, 70)
    # cuffs and hands (one over the other)
    p.line([(232, 330), (242, 337)], 150, 9)
    p.line([(280, 332), (270, 339)], 150, 9)
    p.ell(249, 341, 15, 9, SKIN - 8)
    p.ell(264, 344, 15, 9, SKIN)
    p.line([(255, 342), (275, 346)], SKIN - 40, 1.4)
    # neck, lace collar, brooch
    p.rect(244, 160, 268, 198, SKIN - 22)
    p.poly([(226, 190), (256, 182), (286, 190), (276, 208), (256, 200), (236, 208)], 196)
    p.ell(256, 203, 4.5, 5.5, 60)
    # hair (centre parting, ears covered) with a bun on top, face
    p.ell(256, 68, 20, 18, HAIR - 4)
    p.ell(256, 120, 39, 47, HAIR)
    p.ell(256, 136, 29.5, 38, SKIN)
    p.poly([(228, 112), (256, 84), (284, 112), (270, 100), (256, 97), (242, 100)], HAIR)
    if face:
        p.line([(240, 122), (251, 121)], 96, 1.8)                             # brows
        p.line([(261, 121), (272, 122)], 96, 1.8)
        p.ell(245.5, 129, 4.6, 2.4, 70)                                       # eyes
        p.ell(266.5, 129, 4.6, 2.4, 70)
        p.line([(257, 130), (254, 147), (259, 148)], 128, 1.6)                # nose
        p.line([(247, 158), (256, 159.5), (265, 158)], 96, 1.9)               # closed mouth
        p.ell(256, 166, 9, 3, 150)
        p.line([(230, 140), (233, 158), (244, 170)], 140, 3)                  # cheek shadow
    p.line([(256, 84), (256, 97)], 90, 1.2)                                   # parting


def photo_finish(g, seed, lo=0.10, hi=0.90, blur=1.0, fox=1.0, scratches=9, vig=0.42):
    """Greyscale drawing (0..1) -> faded sepia print: soft focus, uneven exposure, grain, vignette, foxing, scratches."""
    rng = np.random.default_rng(seed)
    S = 512
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    g = ndi.gaussian_filter(g, blur)
    g = g * (0.86 + 0.28 * fft_noise(S, 2.0, seed + 1, lo=1, hi=5))
    g = lo + (hi - lo) * np.clip(g, 0, 1) ** 0.92
    grain = ndi.gaussian_filter(rng.standard_normal((S, S)).astype(np.float32), 0.7) * 0.055
    grain += ndi.gaussian_filter(rng.standard_normal((S, S)).astype(np.float32), 1.8) * 0.05
    g = g + grain * (0.6 + 0.8 * (1 - g))
    r = np.sqrt(((xx - 256) / 256.0) ** 2 + ((yy - 256) / 256.0) ** 2)
    g = g * (1.0 - vig * sstep(0.55, 1.30, r))
    g = np.clip(g, 0, 1)
    dark, midc, lite = V(0.095, 0.062, 0.040), V(0.470, 0.365, 0.250), V(0.860, 0.790, 0.640)
    t = g[..., None]
    col = np.where(t < 0.5, dark + (midc - dark) * (t / 0.5), midc + (lite - midc) * ((t - 0.5) / 0.5))
    # yellowed silvering at the edges, foxing spots
    edge = sstep(0.75, 1.35, r) * (0.5 + 0.5 * fft_noise(S, 1.6, seed + 2, lo=2, hi=20))
    col = mix(col, col * V(0.90, 0.80, 0.62) + V(0.03, 0.025, 0.01), edge * 0.6)
    fx = np.zeros((S, S), np.float32)
    for _ in range(int(46 * fox)):
        x, y = rng.uniform(0, S, 2)
        rr = rng.uniform(1.2, 5.5) if rng.random() < 0.85 else rng.uniform(6, 11)
        fx = np.maximum(fx, np.exp(-(((xx - x) ** 2 + (yy - y) ** 2) / (rr * rr))) * rng.uniform(0.35, 0.9))
    fx *= 0.6 + 0.8 * fft_noise(S, 0.8, seed + 3, lo=20, hi=120)
    col = mix(col, col * V(0.62, 0.42, 0.24) + V(0.05, 0.02, 0.0), np.clip(fx, 0, 1) * 0.75)
    # scratches (pale, through the emulsion) and dust
    k = 2
    sc = Image.new("L", (S * k, S * k), 0)
    d = ImageDraw.Draw(sc)
    for _ in range(scratches):
        x, y = rng.uniform(-40, S + 40, 2)
        a = rng.normal(1.3, 0.5)
        L = rng.uniform(60, 330)
        pts = [(x, y)]
        for _i in range(6):
            a += rng.normal(0, 0.05)
            x += math.cos(a) * L / 6
            y += math.sin(a) * L / 6
            pts.append((x, y))
        d.line([(px * k, py * k) for px, py in pts], fill=int(rng.uniform(90, 230)), width=int(rng.choice((1, 1, 2, 3))))
    for _ in range(60):
        x, y = rng.uniform(0, S * k, 2)
        rr = rng.uniform(0.6, 2.4)
        d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=int(rng.uniform(80, 220)))
    scm = arr(sc.resize((S, S), Image.LANCZOS))
    col = mix(col, V(0.90, 0.85, 0.72), np.clip(scm * 1.2, 0, 1) * 0.8)
    return np.clip(col, 0, 1)


def portrait_scratched():
    p = Pen(backdrop(9501, 0.50, 0.38, floor_y=452, floor_v=0.26))
    p.s, p.ox, p.oy = 1.0, 0.0, 8.0
    draw_woman(p, face=True)
    col = photo_finish(p.get(), 9502, scratches=8)
    # the face gouged out with a sharp tool: bare paper, hard back-and-forth strokes
    rng = np.random.default_rng(9503)
    k = 3
    m = Image.new("L", (512 * k, 512 * k), 0)
    d = ImageDraw.Draw(m)
    cx, cy = 256, 143
    for i in range(64):
        base = (0.55, -0.75, 1.45)[i % 3]
        a = base + rng.normal(0, 0.16)
        L = rng.uniform(26, 62) if i < 54 else rng.uniform(70, 120)
        ox, oy = rng.normal(0, 13), rng.normal(0, 17)
        x0, y0 = cx + ox - math.cos(a) * L / 2, cy + oy - math.sin(a) * L / 2
        x1, y1 = cx + ox + math.cos(a) * L / 2, cy + oy + math.sin(a) * L / 2
        xm, ym = (x0 + x1) / 2 + rng.normal(0, 2.5), (y0 + y1) / 2 + rng.normal(0, 2.5)
        d.line([(x0 * k, y0 * k), (xm * k, ym * k), (x1 * k, y1 * k)], fill=255, width=int(rng.choice((2, 3, 3, 4, 6))),
               joint="curve")
    sm = arr(m.resize((512, 512), Image.LANCZOS))
    paper = V(0.930, 0.900, 0.810) * (0.90 + 0.14 * fft_noise(512, 0.6, 9504, lo=30)[..., None])
    sh = np.clip(np.roll(np.roll(sm, 1, axis=0), 1, axis=1) - sm, 0, 1)        # dark burr beside each gouge
    col = mix(col, col * 0.45, sh * 0.8)
    col = mix(col, paper, np.clip(sm * 1.15, 0, 1) * 0.96)
    return col


def portrait_children():
    yy, xx = np.mgrid[0:512, 0:512].astype(np.float32)
    g = np.full((512, 512), 0.56, np.float32) + (fft_noise(512, 1.8, 9511, lo=1, hi=30) - 0.5) * 0.12
    p = Pen(g)
    for y in range(6, 420, 19):                                               # clapboards
        p.line([(0, y), (512, y)], 92, 2.2)
        p.line([(0, y + 2.6), (512, y + 2.6)], 168, 1.2)
    p.rect(160, 34, 352, 420, 178)                                            # door casing
    p.rect(174, 48, 338, 420, 50)                                             # door
    for x0, y0, x1, y1 in ((188, 62, 250, 190), (262, 62, 324, 190), (188, 206, 250, 300), (262, 206, 324, 300),
                           (188, 316, 250, 404), (262, 316, 324, 404)):
        p.rect(x0, y0, x1, y1, 38)
        p.line([(x0, y1), (x1, y1), (x1, y0)], 70, 1.6)
    p.ell(326, 262, 5, 5, 120)
    p.rect(120, 418, 392, 446, 150)                                           # step
    p.rect(120, 444, 392, 450, 70)
    p.rect(0, 448, 512, 512, 96)                                              # ground
    rnd = random.Random(9512)
    faces = []

    def child(x, head_y, feet_y, girl, tone, hair, r=19):
        sh = head_y + r + 6                                                   # shoulders
        hip = sh + (feet_y - sh) * 0.55
        w = r * 1.55
        if girl:
            p.poly([(x - w * 0.8, sh), (x + w * 0.8, sh), (x + w * 1.35, hip + 22), (x - w * 1.35, hip + 22)], tone)
            p.line([(x - w * 0.4, sh + 12), (x - w * 0.6, hip + 18)], max(0, tone - 26), 2)
            p.line([(x + w * 0.3, sh + 16), (x + w * 0.5, hip + 18)], max(0, tone - 26), 2)
            leg = 58
            top = hip + 20
        else:
            p.poly([(x - w * 0.85, sh), (x + w * 0.85, sh), (x + w * 0.8, hip), (x - w * 0.8, hip)], tone)
            p.poly([(x - w * 0.8, hip - 2), (x + w * 0.8, hip - 2), (x + w * 0.78, hip + 26), (x - w * 0.78, hip + 26)],
                   max(0, tone - 14))
            p.poly([(x - 9, sh), (x + 9, sh), (x, sh + 16)], 200)
            leg = 150
            top = hip + 24
        p.line([(x - w * 0.9, sh + 5), (x - w * 1.05, hip + 4)], max(0, tone - 8), r * 0.62)   # arms at the sides
        p.line([(x + w * 0.9, sh + 5), (x + w * 1.05, hip + 4)], max(0, tone - 8), r * 0.62)
        p.ell(x - w * 1.06, hip + 9, 5, 6, 165)
        p.ell(x + w * 1.06, hip + 9, 5, 6, 165)
        for s in (-1, 1):
            p.line([(x + s * w * 0.36, top), (x + s * w * 0.38, feet_y - 4)], leg, r * 0.50)
            p.ell(x + s * w * 0.46, feet_y, 9, 5, 28)
        p.rect(x - 5, head_y + r - 4, x + 5, sh + 2, 160)
        p.ell(x, head_y - 3, r + 2.5, r + 2, hair)                            # hair
        if girl:
            p.ell(x - r - 1, head_y + 8, 6, 15, hair)
            p.ell(x + r + 1, head_y + 8, 6, 15, hair)
        p.ell(x, head_y + 2, r - 2.5, r, 172)
        faces.append((x, head_y + 2, r))

    child(176, 232, 420, True, 196, 40)
    child(256, 214, 420, False, 46, 60)
    child(338, 240, 420, True, 150, 52)
    child(214, 318, 488, False, 62, 36, r=20)
    child(302, 326, 488, True, 205, 70, r=20)
    del rnd
    g = p.get()
    # every face worn away to a pale blur (the emulsion rubbed off)
    n = fft_noise(512, 1.2, 9513, lo=8, hi=90)
    rub = np.zeros((512, 512), np.float32)
    for x, y, r in faces:
        e = np.sqrt((xx - x) ** 2 + ((yy - y) / 1.1) ** 2) / (r * 1.08)
        rub = np.maximum(rub, sstep(1.0, 0.5, e + (n - 0.5) * 0.9))
    g = mix(g, 0.90 + (n - 0.5) * 0.10, ndi.gaussian_filter(rub, 2.0) * 0.95)
    return photo_finish(g, 9514, blur=1.1, scratches=11)


def portrait_house():
    yy, xx = np.mgrid[0:512, 0:512].astype(np.float32)
    sky = 0.50 + 0.22 * (yy / 340.0) + (fft_noise(512, 2.0, 9521, lo=1, hi=14, sx=0.5) - 0.5) * 0.16
    snow = 0.80 - 0.10 * ((yy - 340) / 172.0) + (fft_noise(512, 1.8, 9522, lo=1, hi=40, sx=0.35) - 0.5) * 0.16
    g = np.where(yy > 338 + 6 * np.sin(xx / 70.0), snow, sky).astype(np.float32)
    p = Pen(g)
    rnd = random.Random(9523)
    # distant tree line
    for x in range(-10, 530, 13):
        hgt = rnd.uniform(18, 46)
        p.line([(x, 340), (x + rnd.uniform(-4, 4), 340 - hgt)], 112, 2.0)
        p.line([(x, 340 - hgt * 0.5), (x + rnd.uniform(-9, 9), 340 - hgt * 0.95)], 118, 1.2)
    # the house: side-gabled, snow on the roof, chimney, small porch
    p.rect(150, 214, 392, 356, 58)
    for y in range(222, 356, 9):
        p.line([(150, y), (392, y)], 44, 1.2)
    p.poly([(132, 218), (166, 138), (376, 138), (410, 218)], 196)             # snow-covered roof
    p.poly([(132, 218), (410, 218), (408, 226), (134, 226)], 40)              # eave shadow
    p.line([(166, 138), (376, 138)], 150, 2)
    p.poly([(210, 214), (220, 190), (260, 180), (300, 196), (330, 214)], 120)  # bare patch where snow slid
    p.rect(318, 104, 342, 150, 48)
    p.rect(314, 98, 346, 106, 205)
    p.rect(150, 214, 158, 356, 40)
    p.rect(384, 214, 392, 356, 76)
    for x0, lit in ((176, False), (316, True)):
        p.rect(x0 - 5, 243, x0 + 45, 313, 150)                                # casing
        p.rect(x0, 248, x0 + 40, 308, 236 if lit else 26)
        p.line([(x0 + 20, 248), (x0 + 20, 308)], 60 if lit else 110, 2.4)
        p.line([(x0, 278), (x0 + 40, 278)], 60 if lit else 110, 2.4)
        p.rect(x0 - 6, 308, x0 + 46, 314, 215)                                # snow on the sill
    p.rect(250, 262, 292, 356, 132)
    p.rect(255, 267, 287, 356, 34)                                            # door
    p.poly([(238, 262), (304, 262), (298, 250), (244, 250)], 205)             # porch hood with snow
    p.rect(240, 354, 302, 362, 190)
    p.poly([(138, 356), (404, 356), (420, 372), (120, 372)], 222)             # drift against the wall
    # bare trees, fence
    k = p.k
    for x0, y0, L, w, s in ((62, 420, 250, 12, 9524), (466, 400, 220, 10, 9525), (22, 380, 120, 5, 9526)):
        limb(p.d, x0, y0, -math.pi / 2 + random.Random(s).uniform(-0.12, 0.12), L, w, 4, random.Random(s), k, 34, up=0.9)
    for x in range(8, 520, 46):
        yb = 430 + 10 * math.sin(x / 90.0)
        p.line([(x, yb), (x + 2, yb - 44)], 48, 5)
        p.ell(x + 2, yb - 46, 5, 3, 225)
    p.line([(-5, 402 + 0), (520, 398)], 56, 2.5)
    p.line([(-5, 418), (520, 414)], 56, 2.5)
    g = p.get()
    # glow of the single lit window
    gl = np.exp(-(((xx - 336) / 46.0) ** 2 + ((yy - 278) / 50.0) ** 2))
    g = np.clip(g + gl * 0.16, 0, 1)
    # dusk falling: darken everything but the window
    g = g * (0.78 + 0.22 * np.clip(gl * 2.0, 0, 1))
    return photo_finish(g, 9527, lo=0.09, hi=0.92, blur=0.9, scratches=10)


def portrait_burnt():
    p = Pen(backdrop(9531, 0.48, 0.36))
    p.s = 1.32
    p.ox, p.oy = 256 - 256 * 1.32, 196 - 136 * 1.32
    draw_woman(p, face=True)
    eyes = [p.T(245.5, 129), p.T(266.5, 129)]
    eyes = [(x / p.k, y / p.k) for x, y in eyes]
    col = photo_finish(p.get(), 9532, blur=1.2, fox=1.6, scratches=6)
    yy, xx = np.mgrid[0:512, 0:512].astype(np.float32)
    # water damage: tide-marked blotches, emulsion mottled and lifted towards the bottom-left
    w = eq(fft_noise(512, 1.9, 9533, lo=1, hi=24))
    w = np.clip(w + 0.30 * np.clip((yy - xx * 0.5 - 180) / 380.0, 0, 1), 0, 1.5)
    wet = sstep(0.62, 0.70, w)
    tide = np.clip(sstep(0.60, 0.63, w) - sstep(0.635, 0.675, w), 0, 1)
    mott = fft_noise(512, 1.0, 9534, lo=10, hi=110)
    col = mix(col, col * V(1.08, 0.98, 0.80) + V(0.10, 0.085, 0.05), wet * (0.35 + 0.5 * mott))
    lifted = wet * sstep(0.58, 0.72, mott) * sstep(0.85, 1.15, w)
    col = mix(col, V(0.800, 0.740, 0.600) * (0.85 + 0.3 * mott)[..., None], lifted * 0.85)
    col = mix(col, col * V(0.58, 0.45, 0.30), tide * (0.30 + 0.35 * mott))
    for ky in (0.25, 0.5, 0.75):                                              # cockled paper: faint light / dark waves
        col *= (1.0 + 0.035 * np.sin(yy / 23.0 + ky * 9 + 3 * w))[..., None]
    # the eyes: two holes burnt through the paper (black void, charred rim, scorched halo)
    hn = fft_noise(512, 1.3, 9535, lo=6, hi=90)
    for (ex, ey), R in zip(eyes, (11.5, 10.0)):
        r = np.sqrt((xx - ex) ** 2 + ((yy - ey) * 1.12) ** 2) + (hn - 0.5) * 9.0
        scorch = sstep(R * 3.0, R * 1.05, r)
        char = sstep(R * 1.5, R * 1.02, r)
        hole = sstep(R, R - 1.2, r)
        col = mix(col, col * V(0.62, 0.42, 0.22), scorch * 0.85)
        col = mix(col, V(0.070, 0.045, 0.030), char * 0.92)
        col = mix(col, V(0.012, 0.010, 0.010), hole)
        rim = np.exp(-((r - R * 1.08) / 1.0) ** 2) * (hn > 0.52)
        col = mix(col, V(0.33, 0.24, 0.15), rim * 0.35)
    return np.clip(col, 0, 1)


def gen_portraits_atlas():
    atlas = Image.new("RGB", (1024, 1024))
    for k, fn in enumerate((portrait_scratched, portrait_children, portrait_house, portrait_burnt)):
        atlas.paste(rgb_img(fn()), ((k % 2) * 512, (k // 2) * 512))
    save(atlas, "portraits_atlas.jpg", 88)


# ------------------------------------------------------------------ cotton dust sheet (normal map only)

def gen_sheet_n():
    S = 512
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    # plain weave, 128 threads per tile each way, threads of uneven thickness (slubs)
    slub_x = fft_noise(S, 1.0, 9601, lo=4, hi=120, sx=1.0, sy=0.06)           # varies along x, constant along a warp thread
    slub_y = fft_noise(S, 1.0, 9602, lo=4, hi=120, sx=0.06, sy=1.0)
    wx = (fft_noise(S, 1.6, 9603, lo=1, hi=10) - 0.5) * 3.0                   # threads not perfectly straight
    wy = (fft_noise(S, 1.6, 9604, lo=1, hi=10) - 0.5) * 3.0
    a = np.sin(2 * np.pi * (xx + wx) / 4.0)
    b = np.sin(2 * np.pi * (yy + wy) / 4.0)
    weave = a * b * 0.5 + 0.25 * np.abs(a) * (0.6 + 0.8 * slub_y) + 0.25 * np.abs(b) * (0.6 + 0.8 * slub_x)
    fuzz = fft_noise(S, 0.4, 9605, lo=60) - 0.5
    # soft irregular wrinkles: broad folds plus a few sharper creases (ridged noise) in two directions
    w1 = fft_noise(S, 2.4, 9606, lo=1, hi=10, sx=1.0, sy=0.55) - 0.5
    r1 = 1.0 - np.abs(fft_noise(S, 1.9, 9607, lo=1, hi=9, sx=0.6, sy=1.0) * 2.0 - 1.0)
    r2 = 1.0 - np.abs(fft_noise(S, 1.9, 9608, lo=2, hi=12, sx=1.0, sy=0.5) * 2.0 - 1.0)
    wr = w1 * 15.0 + blur_wrap((r1 ** 3).astype(np.float32), 3.0) * 6.0 + blur_wrap((r2 ** 4).astype(np.float32), 2.5) * 3.0
    h = wr + weave * 0.75 + fuzz * 0.5
    save(normal_from_height(h.astype(np.float32), 1.0), "sheet_n.png")


if __name__ == "__main__":
    jobs = [("wallpaper_house", gen_wallpaper_house), ("plaster_old", gen_plaster_old), ("rug_runner", gen_rug_runner),
            ("night_window", gen_night_window), ("portraits_atlas", gen_portraits_atlas), ("sheet_n", gen_sheet_n)]
    for name, fn in jobs:
        if want(name):
            fn()
