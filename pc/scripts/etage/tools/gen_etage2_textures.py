#!/usr/bin/env python3
"""Procedural textures of the rooms added to "L'etage" (kitchen, pantry, bathroom, stairwell). Re-runnable,
deterministic (fixed seeds), nothing downloaded, nothing copied from any other work. Lettering uses the fonts the game
already ships (pc/assets/fonts: Gelasio, Caveat, Special Elite - all OFL).

    python3 -I pc/scripts/etage/tools/gen_etage2_textures.py [out_dir] [--only name,name]

Default out_dir = pc/assets/garderie/textures (the folder the material loader reads). The `.import` presets of the new
files are written next to them (same presets as pc/scripts/garderie/tools/write_imports.py); then run
`godot --headless --path pc --import`.

  lino_checker.jpg       1024, seamless, 1.6 m (8 x 8 checks of 20 cm): worn kitchen linoleum, cream / bottle green
  calendar_1994.jpg      512x768: wall calendar, "NOVEMBRE 1994" (the 1st is a Tuesday), days 1-11 crossed in pencil.
                         The day grid is CAL_* below (etage_layout.gd repeats those numbers to place the red ring).
  digits_hand.png        1280x512, 5 x 2 cells: the digits 0-9 drawn by hand (white, alpha) - traced in the steam of
                         the bathroom mirror, written on the paper under the pillow
  fog_mirror.png         512, alpha: condensation on a mirror (denser at the top, runs of drops)
  etage_labels.jpg       1024, 2 x 2 atlas: the fuse board's card, four jar labels, the tin of fuses, a key tag
  steam_puff.png         128, alpha: one soft puff of steam (particles)
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
FONTS = os.path.join(PC, "assets", "fonts")
ARGV = sys.argv[1:]
OUT = ARGV[0] if ARGV and not ARGV[0].startswith("--") else os.path.join(PC, "assets", "garderie", "textures")

# the calendar's day grid, in pixels of the 512 x 768 page (7 columns Monday..Sunday, 5 rows)
CAL_X0, CAL_Y0, CAL_CW, CAL_CH = 40.0, 392.0, 432.0 / 7.0, 68.0


def arg(name, default=None):
    if name in ARGV:
        i = ARGV.index(name)
        return ARGV[i + 1] if i + 1 < len(ARGV) else default
    return default


ONLY = set(filter(None, (arg("--only", "") or "").split(",")))
os.makedirs(OUT, exist_ok=True)

IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="{src}"

[params]

compress/mode={mode}
compress/high_quality={hq}
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
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


def want(name):
    return not ONLY or name in ONLY


def save(img, name, mode=2, hq=False, quality=90):
    path = os.path.join(OUT, name)
    if name.endswith(".jpg"):
        img.convert("RGB").save(path, quality=quality, optimize=True, progressive=False)
    else:
        img.save(path, optimize=True)
    imp = path + ".import"
    if not os.path.exists(imp):
        rel = os.path.relpath(path, PC).replace(os.sep, "/")
        with open(imp, "w") as fh:
            fh.write(IMPORT.format(src="res://" + rel, mode=mode, hq="true" if hq else "false"))
    print("wrote", name, img.size)


def font(name, size):
    return ImageFont.truetype(os.path.join(FONTS, name), size)


def fft_noise(size, beta, seed):
    """Periodic 1/f^beta noise in 0..1 (tileable)."""
    rng = np.random.default_rng(seed)
    f = np.fft.fftfreq(size)
    fx, fy = np.meshgrid(f, f)
    r = np.sqrt(fx * fx + fy * fy)
    r[0, 0] = 1.0
    spec = (rng.standard_normal((size, size)) + 1j * rng.standard_normal((size, size))) / r ** beta
    spec[0, 0] = 0
    x = np.real(np.fft.ifft2(spec))
    x = (x - x.min()) / (x.max() - x.min() + 1e-12)
    return x


# ------------------------------------------------------------------ lino_checker.jpg

def lino():
    n = 1024
    k = 8
    cs = n // k
    yy, xx = np.mgrid[0:n, 0:n]
    check = ((xx // cs + yy // cs) % 2).astype(np.float64)
    cream = np.array([0.66, 0.62, 0.5])
    green = np.array([0.17, 0.24, 0.2])
    img = cream[None, None, :] * (1 - check[..., None]) + green[None, None, :] * check[..., None]
    # each tile a little different, marbled veins inside the tiles
    rng = np.random.default_rng(7)
    tone = rng.uniform(0.9, 1.06, (k, k))
    img *= np.kron(tone, np.ones((cs, cs)))[..., None]
    vein = fft_noise(n, 1.7, 11)
    vein = np.abs(vein - 0.5) * 2.0
    img *= (0.86 + 0.14 * np.clip(vein * 3.0, 0, 1))[..., None]
    # joints between the tiles: thin, dark, filled with dirt
    jx = np.minimum(xx % cs, cs - xx % cs)
    jy = np.minimum(yy % cs, cs - yy % cs)
    joint = np.clip(1.0 - np.minimum(jx, jy) / 2.2, 0, 1)
    img *= (1.0 - 0.6 * joint)[..., None]
    # wear: large dull patches where feet went, yellowing, fine scratches
    wear = fft_noise(n, 2.4, 3)
    img = img * (0.84 + 0.2 * wear[..., None]) + np.array([0.05, 0.035, 0.0])[None, None, :] * (1 - wear[..., None])
    grime = np.clip((fft_noise(n, 2.0, 5) - 0.55) * 3.0, 0, 1)
    img *= (1.0 - 0.45 * grime)[..., None]
    sc = Image.new("L", (n, n), 0)
    d = ImageDraw.Draw(sc)
    r = random.Random(21)
    for _ in range(160):
        x, y = r.uniform(0, n), r.uniform(0, n)
        a = r.uniform(0, math.pi)
        ln = r.uniform(20, 140)
        for ox in (-n, 0, n):
            for oy in (-n, 0, n):
                d.line([(x + ox, y + oy), (x + ox + math.cos(a) * ln, y + oy + math.sin(a) * ln)], fill=r.randint(60, 150), width=1)
    s = np.asarray(sc, np.float64) / 255.0
    img = img * (1.0 - 0.25 * s[..., None]) + 0.08 * s[..., None]
    img += (np.random.default_rng(9).standard_normal((n, n, 1))) * 0.012
    save(Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)), "lino_checker.jpg")


# ------------------------------------------------------------------ calendar_1994.jpg

def calendar():
    w, h = 512, 768
    rng = random.Random(1994)
    paper = np.ones((h, w, 3)) * np.array([0.86, 0.82, 0.7])
    tone = ndi.zoom(np.random.default_rng(4).random((12, 8)), (h / 12, w / 8), order=3)[:h, :w]
    paper *= (0.9 + 0.12 * tone)[..., None]
    img = Image.fromarray((np.clip(paper, 0, 1) * 255).astype(np.uint8))
    d = ImageDraw.Draw(img)
    # the picture: a low sun behind bare hills and a line of poplars (drawn, two inks)
    px0, py0, px1, py1 = 34, 40, 478, 300
    d.rectangle([px0, py0, px1, py1], fill=(196, 172, 128))
    for i in range(26):
        t = i / 25.0
        yy = py0 + int((py1 - py0) * 0.62 * t)
        d.rectangle([px0, yy, px1, yy + 8], fill=(int(200 - 40 * t), int(170 - 50 * t), int(126 - 40 * t)))
    d.ellipse([300, 110, 372, 182], fill=(226, 196, 120))
    pts = [(px0, 230)]
    for x in range(px0, px1 + 1, 12):
        pts.append((x, 214 + 22 * math.sin(x * 0.013) + 9 * math.sin(x * 0.041 + 1.0)))
    pts += [(px1, py1), (px0, py1)]
    d.polygon(pts, fill=(92, 78, 60))
    pts = [(px0, 262)]
    for x in range(px0, px1 + 1, 12):
        pts.append((x, 252 + 14 * math.sin(x * 0.02 + 2.0)))
    pts += [(px1, py1), (px0, py1)]
    d.polygon(pts, fill=(58, 50, 42))
    for i in range(7):
        x = 70 + i * 34 + rng.randint(-5, 5)
        top = 150 + rng.randint(-14, 20)
        d.polygon([(x - 7, 246), (x, top), (x + 7, 246)], fill=(44, 40, 34))
    d.rectangle([px0, py0, px1, py1], outline=(60, 50, 40), width=2)
    # the hole it hangs by
    d.ellipse([w // 2 - 7, 12, w // 2 + 7, 26], fill=(40, 34, 28))
    title = font("gelasio/Gelasio-Bold.ttf", 40)
    d.text((w // 2, 338), "NOVEMBRE 1994", font=title, fill=(74, 30, 26), anchor="mm")
    head = font("gelasio/Gelasio-Bold.ttf", 20)
    num = font("gelasio/Gelasio-Regular.ttf", 30)
    for c, ch in enumerate("LMMJVSD"):
        d.text((CAL_X0 + (c + 0.5) * CAL_CW, CAL_Y0 - 16), ch, font=head, fill=(74, 30, 26) if c == 6 else (50, 44, 38), anchor="mm")
    d.line([CAL_X0, CAL_Y0 - 2, CAL_X0 + 7 * CAL_CW, CAL_Y0 - 2], fill=(50, 44, 38), width=2)
    for day in range(1, 31):
        idx = day                                   # the 1st is a Tuesday: Monday's cell of the first row is empty
        c, r = idx % 7, idx // 7
        cx = CAL_X0 + (c + 0.5) * CAL_CW
        cy = CAL_Y0 + (r + 0.5) * CAL_CH
        d.text((cx, cy), str(day), font=num, fill=(120, 36, 30) if c == 6 or day in (1, 11) else (44, 40, 36), anchor="mm")
        if day <= 11:
            # crossed out in pencil, one stroke a day
            a = rng.uniform(-0.25, 0.25)
            ln = 22
            dx, dy = math.cos(0.9 + a) * ln, math.sin(0.9 + a) * ln
            d.line([cx - dx, cy - dy, cx + dx, cy + dy], fill=(96, 92, 88), width=2)
    img = img.filter(ImageFilter.GaussianBlur(0.5))
    # foxing, a ring left by a cup, the corners curled darker
    a = np.asarray(img, np.float64) / 255.0
    fox = np.clip((ndi.zoom(np.random.default_rng(8).random((48, 32)), (h / 48, w / 32), order=3)[:h, :w] - 0.74) * 4.0, 0, 1)
    a *= (1.0 - 0.12 * fox)[..., None]
    yy, xx = np.mgrid[0:h, 0:w]
    edge = np.minimum(np.minimum(xx, w - 1 - xx), np.minimum(yy, h - 1 - yy)) / 40.0
    a *= (0.8 + 0.2 * np.clip(edge, 0, 1))[..., None]
    save(Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)), "calendar_1994.jpg", hq=True, quality=92)


# ------------------------------------------------------------------ digits_hand.png

def digits():
    cw = 256
    img = Image.new("L", (cw * 5, cw * 2), 0)
    f = font("caveat/Caveat-Bold.ttf", 250)
    rng = random.Random(5)
    for i in range(10):
        cell = Image.new("L", (cw, cw), 0)
        d = ImageDraw.Draw(cell)
        d.text((cw // 2, cw // 2 + 6), str(i), font=f, fill=255, anchor="mm", stroke_width=5, stroke_fill=255)
        cell = cell.rotate(rng.uniform(-6, 6), resample=Image.BICUBIC)
        img.paste(cell, ((i % 5) * cw, (i // 5) * cw))
    a = np.asarray(img.filter(ImageFilter.GaussianBlur(2.2)), np.float64) / 255.0
    # a finger's stroke: full in the middle, uneven along its edges
    n = ndi.zoom(np.random.default_rng(6).random((64, 160)), (8, 8), order=3)[:cw * 2, :cw * 5]
    a = np.clip((a - 0.28 - 0.14 * (n - 0.5)) * 3.2, 0, 1)
    out = np.zeros((cw * 2, cw * 5, 4), np.uint8)
    out[..., :3] = 255
    out[..., 3] = (a * 255).astype(np.uint8)
    save(Image.fromarray(out, "RGBA"), "digits_hand.png", mode=0)


# ------------------------------------------------------------------ fog_mirror.png

def fog():
    n = 512
    base = fft_noise(n, 1.6, 31)
    fine = fft_noise(n, 0.6, 32)
    yy, xx = np.mgrid[0:n, 0:n]
    a = 0.72 + 0.22 * (base - 0.5) + 0.1 * (fine - 0.5)
    a *= 1.0 - 0.3 * (yy / n) ** 2                         # thinner toward the bottom
    # runs of drops: thin clear streaks that start somewhere and go down, a fat drop at the end
    rng = random.Random(33)
    runs = Image.new("L", (n, n), 0)
    d = ImageDraw.Draw(runs)
    for _ in range(22):
        x = rng.uniform(10, n - 10)
        y0 = rng.uniform(40, n * 0.75)
        ln = rng.uniform(60, 260)
        pts = []
        for s in range(0, int(ln), 6):
            pts.append((x + 3.0 * math.sin(s * 0.05 + x), y0 + s))
        if len(pts) > 1:
            d.line(pts, fill=255, width=rng.choice([2, 3, 3, 4]))
            ex, ey = pts[-1]
            d.ellipse([ex - 4, ey - 3, ex + 4, ey + 7], fill=255)
    r = np.asarray(runs.filter(ImageFilter.GaussianBlur(1.2)), np.float64) / 255.0
    a = np.clip(a * (1.0 - 0.85 * r), 0, 1)
    # the edges of the glass stay a little clearer
    edge = np.minimum(np.minimum(xx, n - 1 - xx), np.minimum(yy, n - 1 - yy)) / 46.0
    a *= 0.55 + 0.45 * np.clip(edge, 0, 1)
    out = np.zeros((n, n, 4), np.uint8)
    out[..., 0] = 214
    out[..., 1] = 222
    out[..., 2] = 220
    out[..., 3] = (np.clip(a, 0, 1) * 255).astype(np.uint8)
    save(Image.fromarray(out, "RGBA"), "fog_mirror.png", mode=0)


# ------------------------------------------------------------------ steam_puff.png

def steam():
    n = 128
    yy, xx = np.mgrid[0:n, 0:n]
    r = np.sqrt((xx - n / 2 + 0.5) ** 2 + (yy - n / 2 + 0.5) ** 2) / (n / 2)
    blob = np.clip(1.0 - r, 0, 1) ** 1.6
    noise = ndi.zoom(np.random.default_rng(41).random((10, 10)), n / 10, order=3)[:n, :n]
    a = np.clip(blob * (0.7 + 0.6 * (noise - 0.5)), 0, 1)
    out = np.zeros((n, n, 4), np.uint8)
    out[..., :3] = 235
    out[..., 3] = (a * 255).astype(np.uint8)
    save(Image.fromarray(out, "RGBA"), "steam_puff.png", mode=0)


# ------------------------------------------------------------------ etage_labels.jpg

def aged(size, base, seed):
    w, h = size
    t = ndi.zoom(np.random.default_rng(seed).random((8, 8)), (h / 8, w / 8), order=3)[:h, :w]
    a = np.ones((h, w, 3)) * np.array(base) * (0.88 + 0.14 * t)[..., None]
    return Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))


def labels():
    n = 1024
    c = n // 2
    img = Image.new("RGB", (n, n), (200, 190, 160))
    # cell 0 (top left): the card of the fuse board, typed, one line corrected by hand
    card = aged((c, c), (0.84, 0.79, 0.62), 51)
    d = ImageDraw.Draw(card)
    ty = font("special_elite/SpecialElite-Regular.ttf", 38)
    hand = font("caveat/Caveat-Bold.ttf", 50)
    d.rectangle([14, 14, c - 14, c - 14], outline=(40, 34, 28), width=3)
    d.text((c // 2, 58), "TABLEAU", font=ty, fill=(36, 30, 26), anchor="mm")
    d.line([40, 88, c - 40, 88], fill=(36, 30, 26), width=2)
    rows = ["1  COULOIR", "2  SALON", "3  CHAMBRE", "4  PRISES", "5  CHAUFFE-EAU"]
    for i, t in enumerate(rows):
        d.text((48, 108 + i * 68), t, font=ty, fill=(36, 30, 26))
    d.text((70, 438), "+ salle de bain", font=hand, fill=(40, 46, 96))
    img.paste(card, (0, 0))
    # cell 1 (top right): four jar labels, handwritten
    jf = font("caveat/Caveat-Bold.ttf", 54)
    js = font("caveat/Caveat-Medium.ttf", 40)
    names = [("Mirabelles", "1993"), ("Cornichons", "août 94"), ("Haricots", "verts"), ("Mûres", "sept. 94")]
    for i, (a, b) in enumerate(names):
        lab = aged((c // 2, c // 2), (0.88, 0.85, 0.74), 60 + i)
        d = ImageDraw.Draw(lab)
        d.rectangle([10, 10, c // 2 - 10, c // 2 - 10], outline=(60, 70, 120), width=4)
        d.rectangle([20, 20, c // 2 - 20, c // 2 - 20], outline=(60, 70, 120), width=1)
        d.text((c // 4, c // 4 - 26), a, font=jf, fill=(30, 34, 80), anchor="mm")
        d.text((c // 4, c // 4 + 36), b, font=js, fill=(30, 34, 80), anchor="mm")
        img.paste(lab, (c + (i % 2) * (c // 2), (i // 2) * (c // 2)))
    # cell 2 (bottom left): the tin of spare fuses
    tin = aged((c, c), (0.5, 0.2, 0.14), 71)
    d = ImageDraw.Draw(tin)
    bf = font("gelasio/Gelasio-Bold.ttf", 78)
    sf = font("gelasio/Gelasio-Regular.ttf", 44)
    d.rectangle([24, 24, c - 24, c - 24], outline=(214, 190, 130), width=6)
    d.text((c // 2, 190), "FUSIBLES", font=bf, fill=(224, 200, 140), anchor="mm")
    d.text((c // 2, 300), "porcelaine  ·  10 A", font=sf, fill=(224, 200, 140), anchor="mm")
    d.line([90, 250, c - 90, 250], fill=(214, 190, 130), width=3)
    d.text((c // 2, 400), "boîte de 6", font=sf, fill=(214, 190, 130), anchor="mm")
    img.paste(tin, (0, c))
    # cell 3 (bottom right): the tag tied to the bedroom key (top half), a strip of sticking plaster (bottom half)
    tag = aged((c, c // 2), (0.8, 0.72, 0.52), 81)
    d = ImageDraw.Draw(tag)
    d.ellipse([28, c // 4 - 16, 60, c // 4 + 16], fill=(40, 34, 28))
    d.text((c // 2 + 20, c // 4), "chambre", font=font("caveat/Caveat-Bold.ttf", 120), fill=(30, 34, 80), anchor="mm")
    img.paste(tag, (c, c))
    strip = aged((c, c // 2), (0.82, 0.8, 0.72), 82)
    d = ImageDraw.Draw(strip)
    d.text((c // 2, c // 4), "ne pas ouvrir", font=font("caveat/Caveat-Bold.ttf", 96), fill=(120, 30, 26), anchor="mm")
    img.paste(strip, (c, c + c // 2))
    img = img.filter(ImageFilter.GaussianBlur(0.6))
    save(img, "etage_labels.jpg", hq=True, quality=92)


if want("lino_checker"):
    lino()
if want("calendar_1994"):
    calendar()
if want("digits_hand"):
    digits()
if want("fog_mirror"):
    fog()
if want("steam_puff"):
    steam()
if want("etage_labels"):
    labels()
