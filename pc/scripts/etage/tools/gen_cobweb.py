#!/usr/bin/env python3
"""Corner cobweb (RGBA, white threads on transparent): the web hangs from the top-left corner of the image, so the
quad that carries it is placed with that corner in the corner of two walls (or of a wall and the ceiling).

    python3 -I pc/scripts/etage/tools/gen_cobweb.py      -> pc/assets/garderie/textures/cobweb.png (512 x 512)
"""
import math, os, random
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "assets", "garderie", "textures", "cobweb.png")
S = 1024
random.seed(7)
img = Image.new("L", (S, S), 0)
d = ImageDraw.Draw(img)
# radial threads from the corner, unevenly spaced, slightly sagging
angles = sorted(random.uniform(0.04, math.pi / 2 - 0.04) for _ in range(11)) + [0.0, math.pi / 2]
angles.sort()
lengths = [S * random.uniform(0.55, 0.98) for _ in angles]
radials = []
for a, L in zip(angles, lengths):
    pts = []
    for i in range(41):
        t = i / 40.0
        sag = math.sin(t * math.pi) * L * 0.035 * (0.5 + random.random() * 0.1)
        x = math.cos(a) * L * t + math.sin(a) * sag * 0.3
        y = math.sin(a) * L * t + sag
        pts.append((x, y))
    radials.append(pts)
    d.line(pts, fill=215, width=3)
# cross threads between neighbouring radials: sagging arcs, some missing, some broken
for ring in range(1, 15):
    t = ring / 15.0 + random.uniform(-0.01, 0.01)
    for j in range(len(radials) - 1):
        if random.random() < 0.14:
            continue
        a = radials[j][min(40, int(t * 40 * random.uniform(0.96, 1.04)))]
        b = radials[j + 1][min(40, int(t * 40 * random.uniform(0.96, 1.04)))]
        mid = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
        r = math.hypot(*mid)
        k = 1.0 - 0.06 * random.uniform(0.5, 1.5)           # the arc sags toward the corner
        c = (mid[0] * k, mid[1] * k + r * 0.012)
        arc = [((1 - u) ** 2 * a[0] + 2 * (1 - u) * u * c[0] + u ** 2 * b[0], (1 - u) ** 2 * a[1] + 2 * (1 - u) * u * c[1] + u ** 2 * b[1]) for u in [i / 12.0 for i in range(13)]]
        if random.random() < 0.1:
            arc = arc[: random.randint(4, 9)]             # a broken thread hanging
        d.line(arc, fill=random.randint(120, 190), width=2)
# a few loose strands hanging down, dust clots
for _ in range(7):
    p = random.choice(random.choice(radials)[10:])
    L = random.uniform(30, 130)
    d.line([p, (p[0] + random.uniform(-8, 8), p[1] + L)], fill=120, width=2)
for _ in range(60):
    p = random.choice(random.choice(radials)[4:])
    r = random.uniform(1.5, 4.5)
    d.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=random.randint(90, 180))
soft = img.filter(ImageFilter.GaussianBlur(1.6))
halo = img.filter(ImageFilter.GaussianBlur(7)).point(lambda v: int(v * 0.35))
alpha = Image.eval(Image.merge("L", [soft]), lambda v: min(255, int(v * 1.25)))
alpha = Image.composite(alpha, halo, alpha.point(lambda v: 255 if v > 18 else 0))
alpha = alpha.resize((512, 512), Image.LANCZOS)
rgba = Image.merge("RGBA", [Image.new("L", (512, 512), 236), Image.new("L", (512, 512), 234), Image.new("L", (512, 512), 226), alpha])
rgba.save(OUT)
print("wrote", os.path.normpath(OUT), rgba.size)
