#!/usr/bin/env python3
"""Procedural textures of the garderie (La Gardienne PC). Re-runnable, deterministic (seeded).

    python3 -I pc/scripts/garderie/tools/gen_textures.py <out_dir> [--fonts DIR] [--only name,name] [--ph DIR]

Writes PNG/JPEG maps into <out_dir> (pc/assets/garderie/textures): tileable noise, EVA foam grain, vinyl wrinkles,
plastic scratches, knotted net, puzzle-mat edge SDF, acoustic ceiling tiles, decals (scuffs, spill, footprints, crayon,
grime, water stain), the neon lettering, and every French sign / drawing / mural.
--ph DIR: folder of the downloaded Poly Haven 2K/1K JPEGs -> re-encoded copies (smaller) under their own names.
Fonts (OFL / Apache, see CREDITS.md) are only used to bake text into the textures; they are not shipped.
"""
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps, ImageChops

OUT = sys.argv[1] if len(sys.argv) > 1 else "."
ARGS = sys.argv[2:]


def arg(name, default=None):
    if name in ARGS:
        i = ARGS.index(name)
        return ARGS[i + 1] if i + 1 < len(ARGS) else default
    return default


FONTS = arg("--fonts", "")
ONLY = set(filter(None, (arg("--only", "") or "").split(",")))
PH = arg("--ph", "")
os.makedirs(OUT, exist_ok=True)


def want(name):
    return not ONLY or name in ONLY


def save(img, name, quality=90):
    path = os.path.join(OUT, name)
    if name.endswith(".jpg"):
        img.convert("RGB").save(path, quality=quality, optimize=True, progressive=False)
    else:
        img.save(path, optimize=True)
    print("wrote", name, img.size)


def font(name, size):
    cands = {
        "fredoka": ["Fredoka.ttf"], "chewy": ["Chewy-Regular.ttf"], "patrick": ["PatrickHand-Regular.ttf"],
        "gaegu": ["Gaegu-Bold.ttf"], "gaegu_r": ["Gaegu-Regular.ttf"], "caveat": ["Caveat.ttf"], "oswald": ["Oswald.ttf"],
        "caveat_b": ["Caveat-Bold.ttf", "Caveat.ttf"],
    }.get(name, [name])
    for c in cands:
        for d in [FONTS, "/usr/share/fonts/truetype/dejavu"]:
            p = os.path.join(d, c) if d else c
            if os.path.exists(p):
                try:
                    f = ImageFont.truetype(p, size)
                    if name == "fredoka":
                        try:
                            f.set_variation_by_axes([600, 100])
                        except Exception:  # noqa: BLE001
                            pass
                    if name == "oswald":
                        try:
                            f.set_variation_by_axes([600])
                        except Exception:  # noqa: BLE001
                            pass
                    return f
                except OSError:
                    pass
    for p in ["/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"]:
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


# ------------------------------------------------------------------ noise helpers (all tileable)

def fft_noise(size, beta, seed, lo=1.0, hi=None):
    """Periodic 1/f^beta noise in [0,1]; lo/hi limit the frequency band (cycles per tile)."""
    rng = np.random.default_rng(seed)
    h = w = size
    fy = np.fft.fftfreq(h)[:, None] * h
    fx = np.fft.fftfreq(w)[None, :] * w
    f = np.sqrt(fx * fx + fy * fy)
    amp = np.where(f > 0, 1.0 / np.maximum(f, 1e-6) ** beta, 0.0)
    amp[f < lo] = 0.0
    if hi:
        amp[f > hi] = 0.0
    ph = rng.uniform(0, 2 * np.pi, (h, w))
    spec = amp * np.exp(1j * ph)
    n = np.real(np.fft.ifft2(spec))
    n -= n.min()
    n /= max(n.max(), 1e-9)
    return n


def blur_wrap(a, radius):
    """Gaussian blur with wrap-around (tileable), a: float array 2D."""
    h, w = a.shape
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    g = np.exp(-2.0 * (np.pi ** 2) * (radius ** 2) * (fx * fx + fy * fy))
    return np.real(np.fft.ifft2(np.fft.fft2(a) * g)).astype(np.float32)


def normal_from_height(hgt, strength):
    dx = (np.roll(hgt, -1, axis=1) - np.roll(hgt, 1, axis=1)) * 0.5
    dy = (np.roll(hgt, -1, axis=0) - np.roll(hgt, 1, axis=0)) * 0.5
    nx = -dx * strength
    ny = dy * strength
    nz = np.ones_like(hgt)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    rgb = np.stack([nx / ln, ny / ln, nz / ln], axis=-1) * 0.5 + 0.5
    return Image.fromarray(np.clip(rgb * 255.0 + 0.5, 0, 255).astype(np.uint8), "RGB")


def to_img(a):
    return Image.fromarray(np.clip(a * 255.0 + 0.5, 0, 255).astype(np.uint8), "L")


def wrap_lines(draw_fn, size, lines):
    """Calls draw_fn(offset_x, offset_y, line) for the 9 wrap copies so strokes tile."""
    for ln in lines:
        for ox in (-size, 0, size):
            for oy in (-size, 0, size):
                draw_fn(ox, oy, ln)


# ------------------------------------------------------------------ material maps

def gen_noise():
    s = 512
    r = fft_noise(s, 1.6, 11, lo=2, hi=40)
    g = fft_noise(s, 1.2, 12, lo=8, hi=120)
    b = fft_noise(s, 0.9, 13, lo=24)
    a = fft_noise(s, 2.2, 14, lo=1, hi=8)
    img = Image.merge("RGBA", [to_img(r), to_img(g), to_img(b), to_img(a)])
    save(img, "noise_rgba.png")


def gen_eva_grain():
    """EVA foam top: fine pebbled grain + a faint woven pattern."""
    s = 512
    rng = np.random.default_rng(21)
    peb = fft_noise(s, 0.6, 22, lo=60, hi=200)
    peb = np.clip((peb - 0.45) * 2.2, 0, 1)
    weave = (np.sin(np.arange(s)[None, :] * 2 * np.pi * 64 / s) * np.sin(np.arange(s)[:, None] * 2 * np.pi * 64 / s)) * 0.5 + 0.5
    hgt = peb * 0.8 + weave * 0.12 + rng.normal(0, 0.03, (s, s))
    hgt = blur_wrap(hgt.astype(np.float32), 0.7)
    save(normal_from_height(hgt, 2.2), "eva_grain_n.png")


def gen_vinyl_wrinkles():
    """Creases of vinyl wrapped around foam: long soft folds (mostly across the tube) + small crinkles."""
    s = 1024
    rng = random.Random(31)
    hgt = np.zeros((s, s), np.float32)
    canvas = Image.new("F", (s, s), 0.0)
    d = ImageDraw.Draw(canvas)
    lines = []
    for _ in range(70):
        x, y = rng.uniform(0, s), rng.uniform(0, s)
        ang = rng.gauss(0, 0.35) + (math.pi * 0.5 if rng.random() < 0.15 else 0.0)
        ln = rng.uniform(80, 420)
        wdt = rng.uniform(6, 22)
        amp = rng.uniform(0.35, 1.0) * (1 if rng.random() < 0.7 else -1)
        lines.append((x, y, ang, ln, wdt, amp))

    def draw(ox, oy, l):
        x, y, ang, ln, wdt, amp = l
        steps = 12
        pts = []
        for i in range(steps + 1):
            t = i / steps - 0.5
            bend = math.sin(t * math.pi * 2 + x) * ln * 0.06
            px = x + ox + math.cos(ang) * t * ln - math.sin(ang) * bend
            py = y + oy + math.sin(ang) * t * ln + math.cos(ang) * bend
            pts.append((px, py))
        for i in range(steps):
            fade = math.sin(math.pi * (i + 0.5) / steps)
            d.line([pts[i], pts[i + 1]], fill=amp * fade, width=max(1, int(wdt * fade)))

    # accumulate several layers so overlapping folds add up
    for chunk in range(0, len(lines), 10):
        layer = Image.new("F", (s, s), 0.0)
        d = ImageDraw.Draw(layer)
        wrap_lines(draw, s, lines[chunk:chunk + 10])
        hgt += np.asarray(layer, np.float32)
    hgt = blur_wrap(hgt / max(1e-6, np.abs(hgt).max()), 9.0)
    crinkle = fft_noise(s, 1.0, 33, lo=30, hi=160) - 0.5
    hgt = hgt / max(1e-6, np.abs(hgt).max()) + crinkle * 0.12
    save(normal_from_height(hgt, 9.0), "vinyl_wrinkle_n.png")


def gen_plastic_scratch():
    """R: scratches, G: smudges / fingerprints, B: dust specks. Tileable."""
    s = 1024
    rng = random.Random(41)
    scr = Image.new("L", (s, s), 0)
    d = ImageDraw.Draw(scr)
    lines = []
    for _ in range(420):
        x, y = rng.uniform(0, s), rng.uniform(0, s)
        ang = rng.gauss(math.pi * 0.5, 0.25) if rng.random() < 0.7 else rng.uniform(0, math.pi)
        ln = rng.expovariate(1 / 60.0) + 8
        lines.append((x, y, ang, ln, rng.randint(40, 200)))

    def draw(ox, oy, l):
        x, y, ang, ln, v = l
        d.line([(x + ox, y + oy), (x + ox + math.cos(ang) * ln, y + oy + math.sin(ang) * ln)], fill=v, width=1)

    wrap_lines(draw, s, lines)
    r = np.asarray(scr, np.float32) / 255.0
    sm = fft_noise(s, 2.0, 42, lo=3, hi=40)
    sm = np.clip((sm - 0.55) * 3.0, 0, 1)
    # fingerprints: concentric ridged ellipses
    fp = np.zeros((s, s), np.float32)
    yy, xx = np.mgrid[0:s, 0:s].astype(np.float32)
    for _ in range(14):
        cx, cy = rng.uniform(0, s), rng.uniform(0, s)
        rx, ry = rng.uniform(14, 26), rng.uniform(20, 34)
        dx = (xx - cx + s / 2) % s - s / 2
        dy = (yy - cy + s / 2) % s - s / 2
        q = np.sqrt((dx / rx) ** 2 + (dy / ry) ** 2)
        ridges = (np.sin(q * 26.0) * 0.5 + 0.5) * np.clip(1.0 - q, 0, 1)
        fp = np.maximum(fp, ridges)
    g = np.clip(sm * 0.8 + fp * 0.6, 0, 1)
    dust = fft_noise(s, 0.3, 43, lo=150)
    b = np.clip((dust - 0.7) * 4.0, 0, 1)
    img = Image.merge("RGB", [to_img(r), to_img(g), to_img(b)])
    save(img, "plastic_scratch.png")


def gen_net():
    """Knotted square net, 8 x 8 cells per tile (RGBA, alpha = rope). At the game's uv_scale 2.5 a cell is 5 cm and the
    cord 3 mm (Subliminal measure: 5-7 cm mesh, 3-4 mm cord), with 1 cm knots at the crossings, grey-black twisted
    cord (albedo ~0.07)."""
    S = 4096
    cells = 8
    cs = S / cells
    img = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(img)
    rng = random.Random(51)
    w = max(2, int(cs * 0.06))
    for i in range(cells + 1):
        for j in range(cells):
            # vertical strand segment i between knots j and j+1 (slight sag / waviness)
            x0 = i * cs + rng.uniform(-4, 4)
            pts = []
            for k in range(9):
                t = k / 8
                y = (j + t) * cs
                x = x0 + math.sin(t * math.pi) * rng.uniform(-6, 6)
                pts.append((x, y))
            for a, b in zip(pts, pts[1:]):
                d.line([a, b], fill=255, width=w)
            y0 = i * cs + rng.uniform(-4, 4)
            pts = []
            for k in range(9):
                t = k / 8
                x = (j + t) * cs
                y = y0 + math.sin(t * math.pi) * rng.uniform(-6, 6)
                pts.append((x, y))
            for a, b in zip(pts, pts[1:]):
                d.line([a, b], fill=255, width=w)
    kr = cs * 0.095
    for i in range(cells + 1):
        for j in range(cells + 1):
            cx, cy = i * cs + rng.uniform(-3, 3), j * cs + rng.uniform(-3, 3)
            rx, ry = kr * rng.uniform(0.85, 1.15), kr * rng.uniform(0.75, 1.05)
            d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=255)
    a = np.asarray(img.filter(ImageFilter.GaussianBlur(1.5)), np.float32) / 255.0
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    twist = (np.sin((xx + yy) * 0.33) * 0.5 + 0.5) * 0.4 + 0.6
    col = np.clip(twist, 0, 1)
    rgb = np.stack([col * 0.068, col * 0.07, col * 0.078], -1)
    img = Image.fromarray(np.clip(np.concatenate([rgb, a[..., None]], -1) * 255 + 0.5, 0, 255).astype(np.uint8), "RGBA")
    img = img.resize((1024, 1024), Image.LANCZOS)
    save(img, "net.png")


def gen_mat_edge():
    """Puzzle-mat (EVA tile) edge across one tile edge, as a signed-distance field.
    u (x, 128 px) = -D .. +D tile units across the edge, t (y, 1024 px) = 0..1 along it.
    Value 0.5 + sd / (2 DM): sd = signed distance to the seam in tile units (> 0 where the tile on the negative side
    owns the point), DM = 0.04. Seven dovetail teeth ~4 cm deep (60 cm tiles), plain near the corners."""
    from scipy import ndimage
    W, H = 128 * 4, 1024 * 4
    D = 0.1
    DM = 0.04
    img = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(img)

    def u2x(u):
        return (u + D) / (2 * D) * W

    d.rectangle([0, 0, u2x(0.0), H], fill=255)
    teeth = 7
    t0, t1 = 0.1, 0.9
    span = (t1 - t0) / teeth
    depth = 0.062
    for k in range(teeth):
        tc = t0 + span * (k + 0.5)
        neck = span * 0.2
        head = span * 0.33
        sign = 1 if k % 2 == 0 else -1  # +: tooth of the negative-side tile bulging into +u
        rr = span * 0.1 * H
        if sign > 0:
            poly = [(u2x(-0.01), (tc - neck) * H), (u2x(depth * 0.5), (tc - neck) * H), (u2x(depth), (tc - head) * H),
                    (u2x(depth), (tc + head) * H), (u2x(depth * 0.5), (tc + neck) * H), (u2x(-0.01), (tc + neck) * H)]
            d.polygon(poly, fill=255)
            d.rounded_rectangle([u2x(depth * 0.42), (tc - head) * H, u2x(depth), (tc + head) * H], radius=rr, fill=255)
        else:
            poly = [(u2x(0.01), (tc - neck) * H), (u2x(-depth * 0.5), (tc - neck) * H), (u2x(-depth), (tc - head) * H),
                    (u2x(-depth), (tc + head) * H), (u2x(-depth * 0.5), (tc + neck) * H), (u2x(0.01), (tc + neck) * H)]
            d.polygon(poly, fill=0)
            d.rounded_rectangle([u2x(-depth), (tc - head) * H, u2x(-depth * 0.42), (tc + head) * H], radius=rr, fill=0)
    m = np.asarray(img.filter(ImageFilter.GaussianBlur(2)), np.float32) > 127
    # signed distance in tile units (pixels are anisotropic: x 2D/W, y 1/H tile units per pixel)
    sx, sy = 2 * D / W, 1.0 / H
    din = ndimage.distance_transform_edt(m, sampling=(sy, sx))
    dout = ndimage.distance_transform_edt(~m, sampling=(sy, sx))
    sd = np.where(m, din, -dout)
    v = np.clip(0.5 + sd / (2 * DM), 0.0, 1.0).astype(np.float32)
    small = np.asarray(Image.fromarray(v, "F").resize((128, 1024), Image.BILINEAR), np.float32)
    save(Image.fromarray(np.clip(small * 255 + 0.5, 0, 255).astype(np.uint8), "L"), "mat_edge.png")


def _radial(size, power=1.0):
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    r = np.sqrt((xx - size / 2) ** 2 + (yy - size / 2) ** 2) / (size / 2)
    return np.clip(1.0 - r, 0, 1) ** power


def _rgba(rgb, a):
    a = np.clip(a, 0, 1).astype(np.float32)
    arr = np.concatenate([np.broadcast_to(np.asarray(rgb, np.float32), a.shape + (3,)), a[..., None]], -1)
    return Image.fromarray(np.clip(arr * 255 + 0.5, 0, 255).astype(np.uint8), "RGBA")


def gen_decals():
    """Garderie decals (RGBA, alpha = coverage, transparent border): rubber scuffs, a dried juice spill, dusty kid
    sneaker prints, crayon scribbles, floor grime, a ceiling water stain."""
    S = 512
    rng = random.Random(77)
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    edge = _radial(S, 0.6)
    # --- scuffs: dark rubber streaks (sneakers, chair legs dragged)
    sc = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(sc)
    for _ in range(26):
        x, y = rng.uniform(70, S - 70), rng.uniform(70, S - 70)
        ang = rng.uniform(0, math.pi)
        ln = rng.uniform(20, 95)
        bend = rng.uniform(-0.4, 0.4)
        pts = []
        for k in range(8):
            t = k / 7
            a = ang + bend * t
            pts.append((x + math.cos(a) * ln * t, y + math.sin(a) * ln * t))
        d.line(pts, fill=rng.randint(120, 255), width=rng.randint(3, 9), joint="curve")
    a = np.asarray(sc.filter(ImageFilter.GaussianBlur(1.6)), np.float32) / 255.0
    a = a * (0.55 + 0.45 * fft_noise(S, 1.2, 701, lo=8)) * edge * 0.85
    save(_rgba((0.05, 0.045, 0.04), a), "decal_scuffs.png")
    # --- dried juice spill: irregular puddle, darker coffee-ring rim
    n = fft_noise(S, 2.4, 702, lo=1, hi=24)
    blob = np.clip((n * 0.8 + _radial(S, 1.3) * 0.9 - 0.62) * 9.0, 0, 1)
    blob_b = np.asarray(Image.fromarray((blob * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(5)), np.float32) / 255.0
    rim = np.clip(blob - blob_b, 0, 1) * 3.0
    a = np.clip(blob * 0.5 + rim * 0.5, 0, 0.9) * (0.75 + 0.25 * fft_noise(S, 1.0, 703, lo=20))
    rgb = np.stack([0.28 - rim * 0.12, 0.15 - rim * 0.08, 0.05 + 0 * rim], -1)
    arr = np.concatenate([np.clip(rgb, 0, 1), a[..., None]], -1)
    save(Image.fromarray(np.clip(arr * 255 + 0.5, 0, 255).astype(np.uint8), "RGBA"), "decal_spill.png")
    # --- footprints: four small sneaker prints walking up the texture, grey dust with a tread pattern
    fp = Image.new("L", (S, S), 0)
    for k in range(4):
        cx = S * 0.5 + (-38 if k % 2 == 0 else 38)
        cy = S * (0.84 - k * 0.22)
        rot = rng.uniform(-0.15, 0.15)
        sole = Image.new("L", (90, 200), 0)
        sd = ImageDraw.Draw(sole)
        sd.ellipse([8, 0, 82, 120], fill=255)
        sd.ellipse([14, 125, 76, 198], fill=255)
        sd.rectangle([20, 60, 70, 150], fill=255)
        tread = Image.new("L", (90, 200), 0)
        td = ImageDraw.Draw(tread)
        for ty in range(0, 200, 12):
            td.line([(0, ty), (90, ty + 6)], fill=255, width=5)
        sole = ImageChops.multiply(sole, tread.point(lambda v: int(90 + v * 0.65)))
        sole = sole.rotate(math.degrees(rot), expand=True)
        fp.paste(sole, (int(cx - sole.width / 2), int(cy - sole.height / 2)), sole)
    a = np.asarray(fp.filter(ImageFilter.GaussianBlur(1.2)), np.float32) / 255.0
    a = a * (0.35 + 0.4 * fft_noise(S, 1.4, 704, lo=6)) * 0.55
    save(_rgba((0.5, 0.48, 0.44), a), "decal_footprints.png")
    # --- crayon scribbles (waxy, grainy strokes in three colours)
    cols = [(0.62, 0.06, 0.05), (0.08, 0.2, 0.55), (0.1, 0.42, 0.12)]
    rgb = np.zeros((S, S, 3), np.float32)
    acc = np.zeros((S, S), np.float32)
    for ci, colr in enumerate(cols):
        im = Image.new("L", (S, S), 0)
        d = ImageDraw.Draw(im)
        x, y = rng.uniform(140, S - 140), rng.uniform(140, S - 140)
        pts = []
        for k in range(40):
            x += rng.uniform(-40, 40)
            y += rng.uniform(-22, 22) + (14 if k % 2 else -14)
            x = min(max(x, 60), S - 60)
            y = min(max(y, 60), S - 60)
            pts.append((x, y))
        d.line(pts, fill=255, width=7, joint="curve")
        m = np.asarray(im, np.float32) / 255.0
        grain = (fft_noise(S, 0.2, 705 + ci, lo=100) > 0.42).astype(np.float32)
        m = m * (0.4 + 0.6 * grain)
        rgb += m[..., None] * np.asarray(colr, np.float32)
        acc += m
    a = np.clip(acc, 0, 1) * edge * 0.9
    rgb = rgb / np.maximum(acc[..., None], 1e-3)
    arr = np.concatenate([np.clip(rgb, 0, 1), a[..., None]], -1)
    save(Image.fromarray(np.clip(arr * 255 + 0.5, 0, 255).astype(np.uint8), "RGBA"), "decal_crayon.png")
    # --- floor grime: soft dark blotches
    n = fft_noise(S, 2.0, 706, lo=2)
    a = np.clip((n - 0.42) / 0.58, 0, 1) * _radial(S, 0.9) * 1.1
    save(_rgba((0.12, 0.1, 0.075), np.clip(a, 0, 0.75)), "decal_grime.png")
    # --- ceiling water stain: tide lines (rings of a dried leak) around a brown core
    n = fft_noise(S, 2.2, 707, lo=1, hi=16)
    r = np.sqrt((xx - S / 2) ** 2 + (yy - S / 2) ** 2) / (S / 2) + (n - 0.5) * 0.45
    core = np.clip(1.0 - r / 0.75, 0, 1)
    rings = np.clip(1.0 - np.abs(np.sin(r * 19.0)) * 3.0, 0, 1) * (r < 0.8)
    a = np.clip(core * 0.45 + rings * 0.35, 0, 0.85)
    rgb = np.stack([0.42 - rings * 0.12, 0.32 - rings * 0.1, 0.18 - rings * 0.06], -1)
    arr = np.concatenate([np.clip(rgb, 0, 1), a[..., None]], -1)
    save(Image.fromarray(np.clip(arr * 255 + 0.5, 0, 255).astype(np.uint8), "RGBA"), "decal_water.png")


def gen_neon():
    """Our own neon lettering "Les Petits Soleils" (handwritten script, Caveat Bold, OFL): glass-tube emission mask
    (RGB = bright core falling off to the tube edge, A = tube coverage). The sign's sun is real 3D tubing."""
    from scipy import ndimage
    W, H = 2048, 512
    size = 300
    f = font("caveat_b", size)
    img = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(img)
    text = "Les Petits Soleils"
    bb = d.textbbox((0, 0), text, font=f)
    tw, th = bb[2] - bb[0], bb[3] - bb[1]
    s = min((W - 80) / tw, (H - 70) / th, 1.0)
    if s < 1.0:
        f = font("caveat_b", int(size * s))
        bb = d.textbbox((0, 0), text, font=f)
        tw, th = bb[2] - bb[0], bb[3] - bb[1]
    d.text(((W - tw) / 2 - bb[0], (H - th) / 2 - bb[1]), text, font=f, fill=255)
    m = np.asarray(img, np.float32) > 127
    dist = ndimage.distance_transform_edt(m).astype(np.float32)
    a = np.clip(dist / 1.5, 0, 1)
    prof = np.clip(dist / 6.0, 0, 1) ** 0.6
    rgb = np.clip(0.5 + 0.5 * prof, 0, 1)
    arr = np.stack([rgb, rgb, rgb, a], -1)
    save(Image.fromarray(np.clip(arr * 255 + 0.5, 0, 255).astype(np.uint8), "RGBA"), "neon_text.png")


def gen_ceiling_tiles():
    """Mineral-fibre acoustic tiles (2' x 2'): 4 variants side by side (clean, stained, stained ring, sagging/dark)."""
    T = 512
    rng = random.Random(61)
    albedo = Image.new("RGB", (T * 4, T), (0, 0, 0))
    hgt_all = np.zeros((T, T * 4), np.float32)
    for v in range(4):
        base = np.full((T, T), 0.86, np.float32)
        n = fft_noise(T, 1.0, 62 + v, lo=6, hi=200)
        base += (n - 0.5) * 0.06
        hgt = np.zeros((T, T), np.float32)
        layer = Image.new("L", (T, T), 0)
        dd = ImageDraw.Draw(layer)
        for _ in range(900):
            x, y = rng.uniform(0, T), rng.uniform(0, T)
            pts = [(x, y)]
            ang = rng.uniform(0, math.tau)
            for _ in range(rng.randint(2, 6)):
                ang += rng.gauss(0, 0.9)
                x += math.cos(ang) * rng.uniform(2, 6)
                y += math.sin(ang) * rng.uniform(2, 6)
                pts.append((x, y))
            dd.line(pts, fill=255, width=rng.choice([1, 1, 2]))
        fis = np.asarray(layer.filter(ImageFilter.GaussianBlur(0.8)), np.float32) / 255.0
        hgt -= fis
        base -= fis * 0.18
        # bevelled tile edge
        e = np.minimum(np.minimum(np.arange(T)[None, :], T - 1 - np.arange(T)[None, :]),
                       np.minimum(np.arange(T)[:, None], T - 1 - np.arange(T)[:, None])).astype(np.float32)
        bev = np.clip(e / 10.0, 0, 1)
        hgt += bev * 0.8
        base *= 0.82 + 0.18 * bev
        col = np.stack([base, base * 0.985, base * 0.95], -1)
        if v >= 1:
            # water stain(s): brownish blotch with darker tide ring
            yy, xx = np.mgrid[0:T, 0:T].astype(np.float32)
            for _ in range(1 if v != 2 else 2):
                cx, cy = rng.uniform(T * 0.25, T * 0.75), rng.uniform(T * 0.25, T * 0.75)
                rad = rng.uniform(T * 0.18, T * 0.4)
                wob = fft_noise(T, 1.5, 70 + v, lo=2, hi=20)
                q = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / rad + (wob - 0.5) * 0.5
                inside = np.clip(1.0 - q, 0, 1) ** 0.6
                ring = np.exp(-((q - 1.0) / 0.05) ** 2)
                stain = np.array([0.72, 0.58, 0.38], np.float32)
                k = np.clip(inside * 0.45 + ring * 0.6, 0, 1)[..., None]
                col = col * (1 - k) + col * stain * k
        if v == 3:
            dark = fft_noise(T, 1.8, 80, lo=1, hi=10)
            k = np.clip((dark - 0.3) * 1.6, 0, 1)[..., None] * 0.75
            col = col * (1 - k) + np.array([0.28, 0.25, 0.2], np.float32) * k
        albedo.paste(Image.fromarray(np.clip(col * 255, 0, 255).astype(np.uint8), "RGB"), (v * T, 0))
        hgt_all[:, v * T:(v + 1) * T] = hgt
    save(albedo, "ceiling_tiles.jpg", 88)
    save(normal_from_height(hgt_all, 3.0), "ceiling_tiles_n.png")


def gen_cork():
    s = 512
    n1 = fft_noise(s, 0.4, 91, lo=60)
    n2 = fft_noise(s, 1.2, 92, lo=4, hi=60)
    v = 0.55 + (n1 - 0.5) * 0.5 + (n2 - 0.5) * 0.25
    col = np.stack([v * 0.78, v * 0.55, v * 0.33], -1)
    save(Image.fromarray(np.clip(col * 255, 0, 255).astype(np.uint8), "RGB"), "cork.jpg", 88)


def reencode_polyhaven():
    """Copies the downloaded Poly Haven maps at a sane JPEG quality (q 86) under their own names."""
    if not PH or not os.path.isdir(PH):
        return
    for f in sorted(os.listdir(PH)):
        if not f.endswith(".jpg"):
            continue
        im = Image.open(os.path.join(PH, f))
        im.load()
        q = 90 if "_nor_" in f else 86
        save(im.convert("RGB"), "ph_" + f, q)


if __name__ == "__main__":
    steps = [("noise", gen_noise), ("eva", gen_eva_grain), ("wrinkle", gen_vinyl_wrinkles), ("scratch", gen_plastic_scratch),
             ("net", gen_net), ("matedge", gen_mat_edge), ("ceiling", gen_ceiling_tiles), ("cork", gen_cork),
             ("decals", gen_decals), ("neon", gen_neon),
             ("ph", reencode_polyhaven)]
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    try:
        import gen_signs  # noqa: F401  (same folder: signs, drawings, mural)
        steps += gen_signs.STEPS
        gen_signs.setup(OUT, FONTS, save, font, fft_noise, blur_wrap)
    except ImportError as e:
        print("signs skipped:", e)
    for name, fn in steps:
        if want(name):
            fn()
