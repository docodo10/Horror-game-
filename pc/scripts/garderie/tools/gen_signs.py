"""Signs, drawings and mural of the garderie (French, Québec). Imported by gen_textures.py (setup() then STEPS).
All artwork is original: the daycare "Les Petits Soleils", its sun mascot, the kids' names and notes."""
import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageChops

OUT = "."
FONTS = ""
save = font = fft_noise = blur_wrap = None


def setup(out, fonts, save_fn, font_fn, noise_fn, blur_fn):
    global OUT, FONTS, save, font, fft_noise, blur_wrap
    OUT, FONTS, save, font, fft_noise, blur_wrap = out, fonts, save_fn, font_fn, noise_fn, blur_fn


# ------------------------------------------------------------------ helpers

def noise_img(w, h, seed, lo=2, hi=None, beta=1.4):
    s = max(w, h)
    s2 = 1 << (s - 1).bit_length()
    n = fft_noise(min(s2, 2048), beta, seed, lo=lo, hi=hi)
    im = Image.fromarray((n * 255).astype(np.uint8), "L").resize((w, h), Image.BICUBIC)
    return np.asarray(im, np.float32) / 255.0


def kidfont(text, size):
    return font("patrick" if any(ord(c) > 127 for c in text) else "gaegu", size)


def text_center(d, xy, text, fnt, fill, stroke=0, stroke_fill=None, anchor="mm"):
    d.text(xy, text, font=fnt, fill=fill, anchor=anchor, stroke_width=stroke, stroke_fill=stroke_fill)


def age(img, seed, fade=0.12, grime=0.25, chips=0.0, chip_col=None, yellow=0.0):
    """Fades, yellows, adds grime and paint chips to an RGB image (returns RGB)."""
    w, h = img.size
    a = np.asarray(img.convert("RGB"), np.float32) / 255.0
    lum = a.mean(-1, keepdims=True)
    a = a * (1 - fade) + (lum * 0.3 + 0.7) * fade
    if yellow > 0:
        a = a * (1 - yellow) + a * np.array([1.0, 0.93, 0.75]) * yellow
    n = noise_img(w, h, seed, lo=2, hi=60)
    g = np.clip((n - 0.35) * 1.4, 0, 1)[..., None] * grime
    a = a * (1 - g * 0.55)
    if chips > 0:
        c = noise_img(w, h, seed + 1, lo=8, hi=200, beta=1.0)
        m = (c > 1.0 - chips).astype(np.float32)[..., None]
        cc = np.array(chip_col if chip_col is not None else (0.55, 0.45, 0.33), np.float32)
        a = a * (1 - m) + cc * m
    return Image.fromarray(np.clip(a * 255, 0, 255).astype(np.uint8), "RGB")


def paper(w, h, seed, tint=(0.96, 0.95, 0.9)):
    n = noise_img(w, h, seed, lo=20, hi=400, beta=0.6)
    v = 0.92 + (n - 0.5) * 0.08
    a = np.stack([v * tint[0], v * tint[1], v * tint[2]], -1)
    return Image.fromarray(np.clip(a * 255, 0, 255).astype(np.uint8), "RGB")


def crayon_line(d, pts, col, width, rng):
    """Waxy crayon stroke: several jittered thin passes."""
    for k in range(4):
        jp = [(x + rng.uniform(-width * 0.25, width * 0.25), y + rng.uniform(-width * 0.25, width * 0.25)) for x, y in pts]
        c = tuple(int(max(0, min(255, v + rng.uniform(-18, 18)))) for v in col)
        d.line(jp, fill=c, width=max(1, int(width * rng.uniform(0.45, 0.8))), joint="curve")


def crayon_fill(img, poly, col, rng, density=0.55, angle=0.6):
    """Hatched crayon fill clipped to a polygon."""
    w, h = img.size
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).polygon(poly, fill=255)
    layer = Image.new("RGB", (w, h), col)
    hat = Image.new("L", (w, h), 0)
    dh = ImageDraw.Draw(hat)
    xs = [p[0] for p in poly]
    ys = [p[1] for p in poly]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    step = 5
    L = (x1 - x0) + (y1 - y0)
    for i in range(int(-L), int(L), step):
        if rng.random() > density:
            continue
        ax = x0 + i
        dh.line([(ax, y1 + 10), (ax + (y1 - y0 + 20) * angle, y0 - 10)], fill=rng.randint(150, 255), width=rng.randint(2, 4))
    m = ImageChops.multiply(mask, hat)
    img.paste(layer, (0, 0), m)


def sun_mascot(d, cx, cy, r, rng, face=True, rays=12, col=(247, 170, 40), ray_col=(250, 204, 60), creepy=False):
    for k in range(rays):
        a = k / rays * math.tau + 0.1
        a0, a1 = a - math.pi / rays * 0.55, a + math.pi / rays * 0.55
        p = [(cx + math.cos(a0) * r * 1.08, cy + math.sin(a0) * r * 1.08), (cx + math.cos(a) * r * 1.62, cy + math.sin(a) * r * 1.62),
             (cx + math.cos(a1) * r * 1.08, cy + math.sin(a1) * r * 1.08)]
        d.polygon(p, fill=ray_col)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=col)
    d.ellipse([cx - r * 0.82, cy - r * 0.86, cx + r * 0.7, cy + r * 0.5], fill=tuple(min(255, c + 16) for c in col))
    if not face:
        return
    ew = r * 0.22
    lw = max(2, int(r * 0.06))
    for sx in (-1, 1):
        ex = cx + sx * r * 0.36
        ey = cy - r * 0.12
        if creepy:
            d.ellipse([ex - ew * 0.5, ey - ew * 0.55, ex + ew * 0.5, ey + ew * 0.55], fill=(30, 20, 15))
        else:
            d.arc([ex - ew, ey - ew * 0.7, ex + ew, ey + ew * 0.9], 200, 340, fill=(90, 40, 20), width=lw)
        d.ellipse([ex - r * 0.16 + sx * r * 0.05, cy + r * 0.12, ex + r * 0.16 + sx * r * 0.05, cy + r * 0.3], fill=(240, 120, 90))
    d.arc([cx - r * 0.42, cy - r * 0.15, cx + r * 0.42, cy + r * 0.55], 20, 160, fill=(120, 40, 25), width=lw + 1)


# ------------------------------------------------------------------ signs

def gen_sign_garderie():
    W, H = 2048, 640
    rng = random.Random(101)
    # plywood board under yellow paint
    base = np.zeros((H, W, 3), np.float32)
    grain = noise_img(W, H, 102, lo=2, hi=30)
    streak = np.asarray(Image.fromarray((noise_img(W, 64, 103, lo=4, hi=200) * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC), np.float32) / 255.0
    wood = np.stack([0.62 + streak * 0.2, 0.47 + streak * 0.15, 0.3 + streak * 0.1], -1)
    paint = np.array([0.98, 0.84, 0.36], np.float32) * (0.93 + grain[..., None] * 0.1)
    img = Image.fromarray(np.clip(paint * 255, 0, 255).astype(np.uint8), "RGB")
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([14, 14, W - 14, H - 14], radius=60, outline=(214, 74, 52), width=34)
    d.rounded_rectangle([58, 58, W - 58, H - 58], radius=40, outline=(70, 120, 200), width=8)
    sun_mascot(d, 330, H // 2 + 6, 150, rng)
    f1 = font("chewy", 250)
    f2 = font("fredoka", 118)
    text_center(d, (1210, 250), "Garderie", f1, (44, 92, 176), stroke=10, stroke_fill=(255, 250, 235))
    text_center(d, (1210, 470), "Les Petits Soleils", f2, (214, 74, 52), stroke=6, stroke_fill=(255, 250, 235))
    for sx in (560, 1880):
        d.ellipse([sx - 16, 70, sx + 16, 102], fill=(150, 150, 150), outline=(80, 80, 80), width=3)
    a = np.asarray(img, np.float32) / 255.0
    chips = noise_img(W, H, 104, lo=10, hi=300, beta=0.9)
    edge = np.zeros((H, W), np.float32)
    edge[:, :60] = 1
    edge[:, -60:] = 1
    edge[:60, :] = 1
    edge[-60:, :] = 1
    m = np.clip(((chips + edge * 0.18) - 0.78) * 8.0, 0, 1)[..., None]
    a = a * (1 - m) + wood * m
    img = Image.fromarray(np.clip(a * 255, 0, 255).astype(np.uint8), "RGB")
    img = age(img, 105, fade=0.14, grime=0.35, yellow=0.12)
    save(img, "sign_garderie.jpg", 90)


def gen_sortie():
    W, H = 512, 192
    # old style: red letters on a dark face (emissive); the letters glow
    img = Image.new("RGB", (W, H), (18, 6, 6))
    glow = Image.new("RGB", (W, H), (0, 0, 0))
    f = font("oswald", 150)
    dg = ImageDraw.Draw(glow)
    text_center(dg, (W // 2, H // 2 + 4), "SORTIE", f, (255, 40, 25))
    glow = glow.filter(ImageFilter.GaussianBlur(10))
    img = ImageChops.add(img, glow)
    d = ImageDraw.Draw(img)
    text_center(d, (W // 2, H // 2 + 4), "SORTIE", f, (255, 70, 50))
    d.polygon([(26, H // 2), (60, H // 2 - 26), (60, H // 2 + 26)], fill=(255, 60, 40))
    d.polygon([(W - 26, H // 2), (W - 60, H // 2 - 26), (W - 60, H // 2 + 26)], fill=(255, 60, 40))
    save(img, "sortie_red.png")
    # modern green pictogram sign (Québec): running figure + door + arrow
    img = Image.new("RGB", (W, 256), (12, 128, 62))
    d = ImageDraw.Draw(img)
    d.rectangle([30, 26, 168, 230], outline=(240, 250, 240), width=10)
    hx, hy = 250, 70
    d.ellipse([hx - 18, hy - 18, hx + 18, hy + 18], fill=(240, 250, 240))
    lw = 18
    pts = {"neck": (240, 96), "hip": (210, 160), "kneeF": (250, 190), "footF": (235, 232), "kneeB": (170, 180),
           "footB": (140, 210), "elbF": (280, 128), "handF": (305, 104), "elbB": (200, 118), "handB": (176, 140)}
    for a, b in [("neck", "hip"), ("hip", "kneeF"), ("kneeF", "footF"), ("hip", "kneeB"), ("kneeB", "footB"),
                 ("neck", "elbF"), ("elbF", "handF"), ("neck", "elbB"), ("elbB", "handB")]:
        d.line([pts[a], pts[b]], fill=(240, 250, 240), width=lw, joint="curve")
    d.polygon([(350, 128), (400, 80), (400, 108), (470, 108), (470, 148), (400, 148), (400, 176)], fill=(240, 250, 240))
    save(img, "sortie_green.png")


def gen_rules():
    W, H = 1024, 1400
    img = Image.new("RGB", (W, H), (246, 244, 236))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W, 210], fill=(36, 92, 170))
    sun_mascot(d, 110, 105, 56, random.Random(1), face=True)
    text_center(d, (585, 78), "RÈGLEMENTS", font("oswald", 96), (255, 255, 255))
    text_center(d, (585, 166), "des modules de jeux", font("fredoka", 58), (255, 230, 120))
    rules = [
        ("Pas de souliers dans les modules.", (220, 60, 50)),
        ("Bas obligatoires pour tous.", (240, 160, 30)),
        ("Une seule personne à la fois\ndans la glissade.", (60, 160, 70)),
        ("On glisse assis, les pieds devant.", (40, 110, 200)),
        ("Pas de nourriture ni de gomme.", (150, 70, 170)),
        ("Les 0 à 3 ans : coin des tout-petits.", (220, 60, 50)),
        ("On ne grimpe pas sur les filets.", (240, 160, 30)),
    ]
    fr = font("fredoka", 42)
    y = 280
    for i, (t, c) in enumerate(rules):
        d.ellipse([60, y - 8, 140, y + 72], fill=c)
        text_center(d, (100, y + 32), str(i + 1), font("oswald", 56), (255, 255, 255))
        d.multiline_text((175, y), t, font=fr, fill=(40, 38, 36), spacing=6)
        y += 140 if "\n" in t else 128
    text_center(d, (W // 2, H - 110), "Merci de votre collaboration !", font("fredoka", 48), (36, 92, 170))
    text_center(d, (W // 2, H - 50), "— La direction", font("patrick", 44), (90, 86, 80))
    img = age(img, 111, fade=0.08, grime=0.3, yellow=0.25)
    d = ImageDraw.Draw(img)
    d.polygon([(W - 150, 0), (W, 0), (W, 120)], fill=(70, 66, 60))     # torn corner
    save(img, "rules.jpg", 88)


def _pinned_paper(base, box, seed, draw_fn, tint=(0.97, 0.96, 0.92), rot=0.0, pin=(220, 40, 40)):
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    p = paper(w, h, seed, tint)
    draw_fn(ImageDraw.Draw(p), p, w, h)
    p = age(p, seed + 7, fade=0.06, grime=0.25, yellow=0.2)
    pa = p.convert("RGBA").rotate(rot, resample=Image.BICUBIC, expand=True)
    sh = Image.new("RGBA", pa.size, (0, 0, 0, 0))
    sh.paste((0, 0, 0, 110), (0, 0), pa.split()[3])
    sh = sh.filter(ImageFilter.GaussianBlur(6))
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    base.paste(sh, (cx - pa.size[0] // 2 + 8, cy - pa.size[1] // 2 + 10), sh)
    base.paste(pa, (cx - pa.size[0] // 2, cy - pa.size[1] // 2), pa)
    d = ImageDraw.Draw(base)
    d.ellipse([cx - 14, y0 + 6, cx + 14, y0 + 34], fill=pin, outline=(60, 20, 20), width=2)
    d.ellipse([cx - 6, y0 + 10, cx + 2, y0 + 18], fill=(255, 220, 220))


def gen_notice_board():
    W, H = 2048, 1280
    cork = Image.open(os.path.join(OUT, "cork.jpg")) if os.path.exists(os.path.join(OUT, "cork.jpg")) else Image.new("RGB", (512, 512), (170, 120, 70))
    base = Image.new("RGB", (W, H))
    for x in range(0, W, cork.size[0]):
        for y in range(0, H, cork.size[1]):
            base.paste(cork, (x, y))
    d = ImageDraw.Draw(base)
    d.rectangle([0, 0, W - 1, H - 1], outline=(120, 82, 48), width=40)
    base = base.convert("RGBA")
    fT = font("oswald", 64)
    fB = font("fredoka", 34)
    fH = font("caveat", 70)

    def menu(dd, p, w, h):
        text_center(dd, (w // 2, 60), "MENU DE LA SEMAINE", fT, (200, 60, 40))
        rows = [("Lundi", "Macaroni à la viande"), ("Mardi", "Pâté chinois"), ("Mercredi", "Soupe aux pois, pain"),
                ("Jeudi", "Spaghetti sauce maison"), ("Vendredi", "Pizza des amis")]
        y = 140
        for a, b in rows:
            dd.text((34, y), a, font=font("fredoka", 30), fill=(36, 92, 170))
            dd.text((200, y), b, font=font("fredoka", 30), fill=(50, 48, 44))
            dd.line([(40, y + 56), (w - 40, y + 56)], fill=(200, 196, 186), width=2)
            y += 74
        dd.text((34, y + 10), "Collation : pommes et fromage", font=font("patrick", 34), fill=(90, 86, 80))

    def rappel(dd, p, w, h):
        dd.rectangle([0, 0, w, 90], fill=(250, 200, 60))
        text_center(dd, (w // 2, 48), "RAPPEL AUX PARENTS", fT, (60, 40, 20))
        dd.multiline_text((36, 130), "Identifiez les bottes,\nles mitaines et les tuques\nde vos enfants.\nMerci !", font=fB, fill=(40, 38, 36), spacing=12)

    def avis(dd, p, w, h):
        text_center(dd, (w // 2, 70), "AVIS", font("oswald", 90), (30, 30, 30))
        dd.multiline_text((40, 150), "La garderie sera fermée\nà compter du lundi\n17 mars 1997,\njusqu'à nouvel ordre.", font=font("fredoka", 33), fill=(40, 38, 36), spacing=12)
        dd.text((w - 330, h - 90), "— La direction", font=font("patrick", 42), fill=(70, 66, 60))

    def note(dd, p, w, h):
        dd.multiline_text((30, 40), "Ne réveillez pas\nla gardienne.", font=fH, fill=(30, 30, 60), spacing=4)
        dd.line([(40, 210), (330, 214)], fill=(150, 20, 20), width=4)

    def drawing(dd, p, w, h):
        rng = random.Random(7)
        sun_mascot(dd, w - 90, 90, 40, rng, face=False)
        for k in range(3):
            x = 80 + k * 110
            crayon_line(dd, [(x, h - 120), (x, h - 200)], (40, 80, 200), 10, rng)
            dd.ellipse([x - 22, h - 250, x + 22, h - 206], outline=(40, 40, 40), width=5)
        crayon_line(dd, [(30, h - 60), (w - 30, h - 70)], (40, 160, 60), 12, rng)

    def polaroid(dd, p, w, h):
        dd.rectangle([20, 20, w - 20, h - 90], fill=(60, 70, 90))
        for k in range(14):
            c = random.Random(k).choice([(200, 50, 50), (40, 90, 190), (240, 190, 40), (50, 150, 70)])
            x = 30 + k * 18
            dd.rectangle([x, h - 200 - (k % 4) * 30, x + 14, h - 100], fill=c)
        dd.text((40, h - 80), "Fête d'Élodie", font=font("patrick", 40), fill=(60, 60, 70))

    _pinned_paper(base, (90, 80, 740, 760), 201, menu, rot=1.5, pin=(40, 110, 210))
    _pinned_paper(base, (800, 90, 1360, 560), 202, rappel, rot=-2.0)
    _pinned_paper(base, (1420, 70, 1960, 640), 203, avis, tint=(0.99, 0.99, 0.97), rot=0.8, pin=(40, 160, 70))
    _pinned_paper(base, (860, 640, 1260, 900), 204, note, tint=(0.98, 0.92, 0.5), rot=-6.0, pin=(240, 190, 40))
    _pinned_paper(base, (120, 820, 600, 1220), 205, drawing, tint=(0.97, 0.97, 0.95), rot=3.0)
    _pinned_paper(base, (1450, 720, 1830, 1200), 206, polaroid, tint=(0.95, 0.95, 0.93), rot=-4.0, pin=(220, 40, 40))
    img = age(base.convert("RGB"), 207, fade=0.05, grime=0.2)
    save(img, "notice_board.jpg", 88)


NAMES = ["Léa", "Mathis", "Florence", "Félix", "Zoé", "Samuel", "Rosalie", "Olivier",
         "Émile", "Charlotte", "Noah", "Alice", "Jacob", "Maëlle", "William", "Élodie"]


def gen_cubby_labels():
    W, H = 1024, 512
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    rng = random.Random(301)
    for i, name in enumerate(NAMES):
        cx, cy = (i % 4) * 256, (i // 4) * 128
        tape = Image.new("RGBA", (236, 96), (226, 214, 176, 255))
        td = ImageDraw.Draw(tape)
        for x in range(0, 236, 3):
            td.line([(x, 0), (x, rng.randint(0, 5))], fill=(0, 0, 0, 0))
            td.line([(x, 95), (x, 95 - rng.randint(0, 5))], fill=(0, 0, 0, 0))
        f = font("patrick", 64) if i % 3 else kidfont(name, 64)
        col = [(30, 30, 40), (30, 60, 150), (160, 30, 30)][i % 3]
        text_center(td, (118, 50), name, f, col + (255,))
        tape = tape.rotate(rng.uniform(-4, 4), resample=Image.BICUBIC, expand=False)
        img.paste(tape, (cx + 10, cy + 16), tape)
    save(img, "cubby_labels.png")


def _drawing(seed, kind):
    S = 512
    rng = random.Random(seed)
    p = paper(S, S, seed, (0.98, 0.97, 0.94))
    d = ImageDraw.Draw(p)
    kid = font("gaegu", 52)
    if kind == 0:   # ma garderie: frame, slide, kids, sun
        sun_mascot(d, 430, 80, 36, rng, face=False)
        for x in range(80, 330, 80):
            crayon_line(d, [(x, 420), (x, 170)], (40, 70, 200), 9, rng)
        for y in (250, 330):
            crayon_line(d, [(80, y), (320, y)], (40, 70, 200), 9, rng)
        for k, c in enumerate([(230, 200, 40), (60, 170, 60), (230, 60, 50), (40, 110, 220)]):
            crayon_line(d, [(320 + k * 10, 170 + k * 6), (380 + k * 14, 300), (470 + k * 6, 430)], c, 10, rng)
        for x in (120, 200):
            d.ellipse([x - 16, 360, x + 16, 392], outline=(30, 30, 30), width=4)
            crayon_line(d, [(x, 392), (x, 440)], (200, 60, 60), 8, rng)
        d.text((30, 20), "MA GARDERIE", font=kid, fill=(200, 40, 60))
    elif kind == 1:  # maison
        crayon_fill(p, [(120, 300), (380, 300), (380, 470), (120, 470)], (220, 120, 60), rng)
        crayon_fill(p, [(100, 300), (250, 170), (400, 300)], (180, 40, 40), rng)
        crayon_line(d, [(330, 220), (330, 160), (360, 160), (360, 240)], (90, 90, 90), 8, rng)
        crayon_fill(p, [(220, 380), (280, 380), (280, 470), (220, 470)], (90, 60, 40), rng)
        sun_mascot(d, 80, 80, 40, rng, face=True)
        crayon_line(d, [(0, 475), (512, 470)], (60, 170, 60), 14, rng)
        d.text((200, 30), "maman et moi", font=kid, fill=(40, 90, 200))
    elif kind == 2:  # la gardienne
        crayon_line(d, [(0, 470), (512, 470)], (60, 170, 60), 12, rng)
        for k in range(26):
            x = 250 + rng.uniform(-30, 30)
            crayon_line(d, [(x, 90), (x + rng.uniform(-40, 40), 300 + rng.uniform(0, 140))], (20, 20, 24), 7, rng)
        crayon_fill(p, [(215, 160), (290, 160), (310, 450), (195, 450)], (25, 25, 30), rng, density=0.9)
        d.ellipse([222, 70, 282, 140], fill=(225, 220, 210), outline=(20, 20, 20), width=4)
        crayon_line(d, [(205, 200), (120, 330), (100, 400)], (20, 20, 24), 6, rng)
        crayon_line(d, [(300, 200), (390, 330), (410, 400)], (20, 20, 24), 6, rng)
        for x, c in ((90, (230, 60, 60)), (420, (40, 110, 220))):
            d.ellipse([x - 18, 360, x + 18, 396], outline=(30, 30, 30), width=4)
            crayon_line(d, [(x, 396), (x, 450)], c, 9, rng)
        d.text((40, 20), "LA GARDIENNE", font=kid, fill=(30, 30, 30))
    else:            # Élodie: arc-en-ciel + je veux rentrer
        for k, c in enumerate([(230, 50, 50), (240, 150, 40), (240, 220, 50), (60, 170, 60), (40, 110, 220), (120, 60, 170)]):
            r = 220 - k * 22
            pts = [(256 + math.cos(a) * r, 330 - math.sin(a) * r) for a in np.linspace(0.05, math.pi - 0.05, 24)]
            crayon_line(d, pts, c, 12, rng)
        for x in (110, 400):
            crayon_fill(p, [(x, 360), (x - 30, 330), (x - 15, 315), (x, 330), (x + 15, 315), (x + 30, 330)], (230, 60, 90), rng, density=0.9)
        d.text((60, 400), "JE VEUX RENTRER", font=font("gaegu", 46), fill=(40, 40, 120))
        d.text((300, 20), "Élodie 5 ans", font=kidfont("Élodie 5 ans", 44), fill=(200, 40, 60))
    return age(p, seed + 3, fade=0.08, grime=0.2, yellow=0.25)


def gen_drawings():
    atlas = Image.new("RGB", (1024, 1024))
    for k in range(4):
        atlas.paste(_drawing(401 + k, k), ((k % 2) * 512, (k // 2) * 512))
    save(atlas, "drawings.jpg", 88)


def gen_mural():
    W, H = 4096, 1024
    rng = random.Random(501)
    yy = np.linspace(0, 1, H)[:, None]
    sky = np.stack([0.55 + yy * 0.3, 0.75 + yy * 0.17, 0.95 + yy * 0.0], -1) * np.ones((1, W, 1))
    img = Image.fromarray(np.clip(sky * 255, 0, 255).astype(np.uint8), "RGB")
    d = ImageDraw.Draw(img)
    for _ in range(9):
        cx, cy = rng.uniform(200, W - 200), rng.uniform(80, 360)
        for k in range(6):
            r = rng.uniform(40, 90)
            d.ellipse([cx + k * 55 - r, cy - r * 0.7 + rng.uniform(-20, 20), cx + k * 55 + r, cy + r * 0.7], fill=(250, 250, 248))
    # hills
    for k, (c, base_y, amp, fr) in enumerate([((120, 190, 90), 640, 90, 2.0), ((90, 165, 75), 720, 70, 3.1), ((70, 140, 62), 820, 50, 4.3)]):
        pts = [(0, H)]
        for x in range(0, W + 64, 64):
            pts.append((x, base_y - amp * math.sin(x / W * math.pi * fr + k * 1.7) - 30 * math.sin(x / W * 23 + k)))
        pts.append((W, H))
        d.polygon(pts, fill=c)
    # lake + loon
    d.ellipse([2500, 760, 3500, 900], fill=(70, 130, 200))
    d.ellipse([2900, 800, 2990, 836], fill=(25, 25, 28))
    d.ellipse([2968, 784, 3004, 812], fill=(25, 25, 28))
    d.polygon([(3000, 796), (3030, 800), (3000, 804)], fill=(40, 40, 40))
    for k in range(5):
        d.ellipse([2915 + k * 14, 812, 2921 + k * 14, 818], fill=(240, 240, 240))
    # pines + maple
    for x in [180, 300, 3620, 3760, 3900, 4010]:
        h = rng.uniform(240, 330)
        for t in range(4):
            y = 760 - t * h / 4.5
            w = (4 - t) * 38
            d.polygon([(x - w, y), (x, y - h / 3), (x + w, y)], fill=(30, 90, 55))
        d.rectangle([x - 10, 760, x + 10, 800], fill=(90, 60, 40))
    d.rectangle([3260, 520, 3290, 760], fill=(100, 64, 40))
    for _ in range(40):
        ox, oy = rng.uniform(-150, 150), rng.uniform(-120, 90)
        r = rng.uniform(50, 80)
        d.ellipse([3275 + ox - r, 470 + oy - r, 3275 + ox + r, 470 + oy + r], fill=rng.choice([(220, 70, 40), (235, 120, 40), (200, 50, 40)]))
    # the sun mascot (big) — creepy: dark eyes and long drips
    sun_mascot(d, 1100, 360, 230, rng, face=True, creepy=True)
    for sx in (-1, 1):
        x = 1100 + sx * 230 * 0.36
        for k in range(3):
            x2 = x + rng.uniform(-8, 8)
            d.line([(x2, 360 - 20), (x2 + rng.uniform(-6, 6), 360 + rng.uniform(120, 300))], fill=(60, 40, 30), width=rng.randint(4, 9))
    # children holding hands
    cols = [(230, 60, 50), (40, 110, 220), (240, 190, 40), (60, 170, 70), (160, 80, 180), (240, 130, 40)]
    for k in range(9):
        x = 1500 + k * 120
        y = 820
        c = cols[k % len(cols)]
        d.ellipse([x - 26, y - 190, x + 26, y - 138], fill=(240, 205, 170))
        d.polygon([(x - 34, y - 130), (x + 34, y - 130), (x + 46, y - 30), (x - 46, y - 30)], fill=c)
        d.line([(x - 14, y - 30), (x - 18, y + 30)], fill=(60, 60, 80), width=12)
        d.line([(x + 14, y - 30), (x + 18, y + 30)], fill=(60, 60, 80), width=12)
        d.line([(x + 34, y - 110), (x + 86, y - 96)], fill=(240, 205, 170), width=10)
    # one child has no face (just a smudge) and stands apart
    x = 2680
    d.ellipse([x - 26, 630, x + 26, 682], fill=(70, 66, 64))
    d.polygon([(x - 34, 690), (x + 34, 690), (x + 46, 790), (x - 46, 790)], fill=(40, 40, 46))
    # lettering
    f = font("chewy", 130)
    text = "Bienvenue aux Petits Soleils !"
    tw = d.textlength(text, font=f)
    d.text(((W - tw) / 2 + 400, 70), text, font=f, fill=(214, 74, 52), stroke_width=8, stroke_fill=(255, 250, 235))
    # weathering: fade, peel (grey block shows), streaks, grime at the bottom
    a = np.asarray(img, np.float32) / 255.0
    lum = a.mean(-1, keepdims=True)
    a = a * 0.78 + (lum * 0.35 + 0.65) * 0.22
    peel = noise_img(W, H, 502, lo=6, hi=300, beta=1.1)
    m = np.clip((peel - 0.8) * 9.0, 0, 1)[..., None]
    a = a * (1 - m) + np.array([0.62, 0.62, 0.6]) * m
    streak = np.asarray(Image.fromarray((noise_img(W, 32, 503, lo=20, hi=400) * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC), np.float32) / 255.0
    st = np.clip((streak - 0.62) * 3.0, 0, 1) * (np.linspace(1, 0.2, H)[:, None])
    a = a * (1 - st[..., None] * 0.35) + np.array([0.45, 0.4, 0.33]) * st[..., None] * 0.35
    g = np.linspace(0, 1, H)[:, None] ** 3 * 0.35
    a = a * (1 - g[..., None])
    save(Image.fromarray(np.clip(a * 255, 0, 255).astype(np.uint8), "RGB"), "mural.jpg", 88)


def gen_banner():
    W, H = 2048, 256
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    word = "BONNE FÊTE ÉLODIE"
    n = len(word)
    pw = W / n
    cols = [(230, 60, 50), (40, 110, 220), (240, 190, 40), (60, 170, 70), (160, 80, 180), (240, 130, 40)]
    f = font("chewy", 96)
    for i, ch in enumerate(word):
        x0 = i * pw + 6
        x1 = (i + 1) * pw - 6
        sag = math.sin(i / (n - 1) * math.pi) * 40
        y0 = 18 + sag
        if ch == " ":
            continue
        d.polygon([(x0, y0), (x1, y0), ((x0 + x1) / 2, y0 + 200)], fill=cols[i % len(cols)] + (255,))
        text_center(d, ((x0 + x1) / 2, y0 + 62), ch, f, (255, 250, 240, 255))
    pts = [(i * pw, 18 + math.sin(i / (n - 1) * math.pi) * 40) for i in range(n + 1)]
    d.line(pts, fill=(240, 240, 240, 255), width=5)
    rgb = age(img.convert("RGB"), 601, fade=0.15, grime=0.2)
    out = rgb.convert("RGBA")
    out.putalpha(img.split()[3])
    save(out, "banner.png")


def gen_signin():
    W, H = 512, 720
    p = paper(W, H, 701)
    d = ImageDraw.Draw(p)
    text_center(d, (W // 2, 40), "FEUILLE DE PRÉSENCES", font("oswald", 40), (30, 30, 30))
    text_center(d, (W // 2, 84), "semaine du 10 mars 1997", font("fredoka", 26), (60, 60, 60))
    cols = [24, 200, 300, 400, 492]
    for x in cols:
        d.line([(x, 110), (x, 690)], fill=(150, 150, 160), width=2)
    for k, t in enumerate(["Nom", "Arrivée", "Départ", "Signature"]):
        d.text((cols[k] + 8, 118), t, font=font("fredoka", 24), fill=(40, 40, 40))
    rows = [("Léa B.", "7 h 30", "16 h 45"), ("Mathis G.", "7 h 50", "17 h 05"), ("Florence L.", "8 h 05", "16 h 30"),
            ("Félix T.", "8 h 10", "17 h 20"), ("Zoé P.", "8 h 15", "16 h 55"), ("Samuel R.", "8 h 20", "17 h 30"),
            ("Rosalie D.", "8 h 30", "17 h 10"), ("Olivier M.", "8 h 40", "16 h 40"), ("Élodie T.", "7 h 45", "")]
    y = 160
    hf = font("caveat", 34)
    for i, (n, a, b) in enumerate(rows):
        d.line([(24, y - 6), (492, y - 6)], fill=(170, 170, 180), width=1)
        d.text((cols[0] + 8, y), n, font=hf, fill=(30, 40, 110))
        d.text((cols[1] + 8, y), a, font=hf, fill=(30, 40, 110))
        if b:
            d.text((cols[2] + 8, y), b, font=hf, fill=(30, 40, 110))
            d.line([(cols[3] + 10, y + 26), (cols[3] + 40, y + 10), (cols[3] + 70, y + 24)], fill=(30, 40, 110), width=2)
        y += 58
    save(age(p, 702, fade=0.05, grime=0.25, yellow=0.25), "signin.jpg", 88)


def gen_labels():
    """Small plaques: 3 x 2 grid of 340 x 256."""
    W, H = 1024, 512
    img = Image.new("RGB", (W, H), (240, 236, 226))
    d = ImageDraw.Draw(img)
    items = [("OBJETS\nPERDUS", (250, 210, 70), (40, 30, 20), "fredoka"), ("JOUETS", (60, 120, 210), (255, 255, 255), "chewy"),
             ("Coin des\ntout-petits", (240, 150, 170), (90, 30, 60), "chewy"),
             ("EMPLOYÉS\nSEULEMENT", (200, 40, 40), (255, 255, 255), "oswald"),
             ("Ne pas grimper\nsur les filets", (255, 255, 255), (200, 40, 40), "fredoka"),
             ("Toilettes", (80, 160, 90), (255, 255, 255), "fredoka")]
    for i, (t, bg, fg, fn) in enumerate(items):
        x0, y0 = (i % 3) * 341, (i // 3) * 256
        d.rectangle([x0 + 6, y0 + 6, x0 + 335, y0 + 250], fill=bg, outline=(60, 60, 60), width=4)
        f = font(fn, 40 if "\n" in t else 56)
        d.multiline_text((x0 + 170, y0 + 128), t, font=f, fill=fg, anchor="mm", align="center", spacing=8)
    save(age(img, 801, fade=0.1, grime=0.3, yellow=0.15), "labels.jpg", 88)


def gen_sun_decal():
    S = 512
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    sun_mascot(d, S // 2, S // 2, 140, random.Random(9), face=True)
    rgb = age(img.convert("RGB"), 901, fade=0.15, grime=0.25, chips=0.08, chip_col=(0.85, 0.85, 0.8))
    out = rgb.convert("RGBA")
    a = np.asarray(img.split()[3], np.float32) / 255.0
    peel = noise_img(S, S, 902, lo=8, hi=200, beta=1.0)
    a = a * np.clip(1.0 - np.clip((peel - 0.78) * 6, 0, 1), 0, 1)
    out.putalpha(Image.fromarray((a * 255).astype(np.uint8), "L"))
    save(out, "sun_decal.png")


STEPS = [("sign", gen_sign_garderie), ("sortie", gen_sortie), ("rules", gen_rules), ("notice", gen_notice_board),
         ("cubby", gen_cubby_labels), ("drawings", gen_drawings), ("mural", gen_mural), ("banner", gen_banner),
         ("signin", gen_signin), ("labels", gen_labels), ("sun", gen_sun_decal)]
