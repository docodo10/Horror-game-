#!/usr/bin/env python3
"""Garderie look-dev measurements (La Gardienne PC), matching the Subliminal gap analysis method.

    python3 -I pc/scripts/garderie/tools/measure.py grade <in.png> <out.png> [--grade look|zone]
    python3 -I pc/scripts/garderie/tools/measure.py stats <img> [<img> ...] [--grade look|zone|none] [--json out.json]
    python3 -I pc/scripts/garderie/tools/measure.py sheet <spec.json> <out.jpg>

grade: the look module's display-space post pass (shaders/look_postfx.gdshader, look_rig.gd TUNE_DEFAULTS, "high"):
  saturation 0.92, gain (1.02, 1, 0.97), gamma (1, 0.99, 1), toe 0.06, S-curve contrast 0.1, vignette 0.34, black lift
  (0.010, 0.0088, 0.0072). "zone" = the garderie grade the gap analysis recommends to the look module (sat 1.06,
  contrast 0.18, neutral gain, lift (0.003, 0.0027, 0.0024)). Renders of preview.gd are AgX at exposure 1 (the look's).
stats (display luma = Rec.709 weights on sRGB-encoded values; like subliminal/tools/stats.py):
  p5 / p50 / p95 / p99 display luma, floor pool contrast = linear-luminance p90 / p50 over the bottom 38 % of the frame,
  primaries = median HSV S / V of red, yellow, blue pixels (S > 0.35, V > 0.05), CCT (McCamy) of near-white surfaces
  (S < 0.22, brightest 30 %, unclipped).
sheet: {"title", "cell": [w, h], "rows": [{"ref": [path, crop|null, label], "ours": [path, crop|null, label], "note"}]}
"""
import json
import math
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

LUMA = np.array([0.2126, 0.7152, 0.0722], np.float32)
GRADES = {
    "look": dict(sat=0.92, gain=(1.02, 1.0, 0.97), gamma=(1.0, 0.99, 1.0), toe=0.06, contrast=0.1, vignette=0.34,
                 lift=(0.010, 0.0088, 0.0072)),
    "zone": dict(sat=1.06, gain=(1.0, 1.0, 1.0), gamma=(1.0, 0.99, 1.0), toe=0.06, contrast=0.18, vignette=0.34,
                 lift=(0.003, 0.0027, 0.0024)),
}


def srgb2lin(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def load(path):
    return np.asarray(Image.open(path).convert("RGB"), np.float32) / 255.0


def grade(a, g):
    p = GRADES[g]
    H, W, _ = a.shape
    aspect = W / H
    inv_corner = 1.0 / (0.25 * aspect * aspect + 0.25)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    dx = ((xx + 0.5) / W - 0.5) * aspect
    dy = (yy + 0.5) / H - 0.5
    r2 = (dx * dx + dy * dy) * inv_corner
    col = a.copy()
    L = (col @ LUMA)[..., None]
    col = np.maximum(L + (col - L) * p["sat"], 0.0)
    col = np.power(np.maximum(col * np.array(p["gain"], np.float32), 0.0), np.array(p["gamma"], np.float32))
    col = np.clip(col, 0.0, 1.0)
    t = p["toe"]
    col = col * (col + 0.75 * t) / (col + t + 1e-5) * ((1.0 + t) / (1.0 + 0.75 * t))
    col = col + (col * col * (3.0 - 2.0 * col) - col) * p["contrast"]
    vq = 1.0 + p["vignette"] * r2
    col = col / (vq * vq)[..., None]
    lift = np.array(p["lift"], np.float32)
    col = col + lift * (1.0 - col)
    return np.clip(col, 0.0, 1.0)


def hsv(a):
    mx = a.max(2)
    mn = a.min(2)
    d = mx - mn
    s = np.where(mx > 1e-4, d / np.maximum(mx, 1e-4), 0.0)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    h = np.zeros_like(mx)
    m = d > 1e-4
    rr = m & (mx == r)
    gg = m & (mx == g) & ~rr
    bb = m & ~rr & ~gg
    h[rr] = ((g - b)[rr] / d[rr]) % 6.0
    h[gg] = (b - r)[gg] / d[gg] + 2.0
    h[bb] = (r - g)[bb] / d[bb] + 4.0
    return h * 60.0, s, mx


def cct(a):
    L = a @ LUMA
    h, s, v = hsv(a)
    thr = np.percentile(L, 70)
    m = (s < 0.22) & (L >= thr) & (a.max(2) < 0.97) & (L > 0.08)
    if m.sum() < 200:
        return float("nan")
    rgb = srgb2lin(a[m]).mean(0)
    M = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    X, Y, Z = M @ rgb
    sm = X + Y + Z
    x, y = X / sm, Y / sm
    n = (x - 0.3320) / (0.1858 - y)
    return float(449 * n ** 3 + 3525 * n ** 2 + 6823.3 * n + 5520.33)


def stats(a):
    H, W, _ = a.shape
    L = a @ LUMA
    lin = srgb2lin(a)
    Ll = lin @ LUMA
    p = np.percentile(L, [5, 50, 95, 99])
    floor = Ll[int(H * 0.62):]
    fp50 = float(np.percentile(floor, 50))
    fp90 = float(np.percentile(floor, 90))
    h, s, v = hsv(a)
    out = dict(p5=float(p[0]), p50=float(p[1]), p95=float(p[2]), p99=float(p[3]), floor_p90_p50=fp90 / max(fp50, 1e-5),
               cct=cct(a), crush=float((L < 0.02).mean()))
    sel = (s > 0.35) & (v > 0.05)
    for name, (h0, h1) in {"red": (345, 15), "yellow": (35, 60), "blue": (200, 250)}.items():
        hm = ((h >= h0) | (h <= h1)) if h0 > h1 else ((h >= h0) & (h <= h1))
        m = sel & hm
        if m.sum() > 150:
            out[name] = [float(np.median(s[m])), float(np.median(v[m])), int(m.sum())]
    return out


def fmt(st):
    t = "p5 %.3f p50 %.3f p95 %.3f p99 %.3f floor p90/p50 %.1f CCT %s" % (
        st["p5"], st["p50"], st["p95"], st["p99"], st["floor_p90_p50"], "%.0fK" % st["cct"] if not math.isnan(st["cct"]) else "-")
    for k in ["red", "yellow", "blue"]:
        if k in st:
            t += "  %s S%.2f V%.2f" % (k[0].upper(), st[k][0], st[k][1])
    return t


def cmd_grade(args):
    g = "look"
    if "--grade" in args:
        g = args[args.index("--grade") + 1]
    a = load(args[0])
    out = grade(a, g)
    Image.fromarray((out * 255 + 0.5).astype(np.uint8)).save(args[1])


def cmd_stats(args):
    g = "look"
    js = None
    if "--grade" in args:
        g = args[args.index("--grade") + 1]
    if "--json" in args:
        js = args[args.index("--json") + 1]
    files = [f for i, f in enumerate(args) if not f.startswith("--") and (i == 0 or args[i - 1] not in ("--grade", "--json"))]
    res = {}
    for f in files:
        a = load(f)
        if g != "none":
            a = grade(a, g)
        st = stats(a)
        res[f] = st
        print("%-40s %s" % (f.split("/")[-1], fmt(st)))
    if js:
        json.dump(res, open(js, "w"), indent=1)


def cmd_sheet(args):
    spec = json.load(open(args[0]))
    out = args[1]
    W, H = spec.get("cell", [800, 450])
    F = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 17)
    FB = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 26)
    FS = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 15)
    rows = spec["rows"]
    cols = spec.get("cols", ["ref", "ours"])
    heads = spec.get("heads", ["SUBLIMINAL (ref)", "LA GARDIENNE (ours)"])
    head, lab, note = 74, 26, 44
    S = Image.new("RGB", (len(cols) * (W + 10) + 10, head + len(rows) * (H + lab + note) + 10), (14, 14, 16))
    d = ImageDraw.Draw(S)
    d.text((12, 10), spec["title"], font=FB, fill=(240, 240, 240))
    hc = [(255, 200, 80), (120, 200, 255), (160, 255, 160)]
    for i, hd in enumerate(heads):
        d.text((10 + i * (W + 10) + W // 2 - 90, head - 26), hd, font=F, fill=hc[i % 3])

    def cell(p):
        path, crop = p[0], p[1]
        im = Image.open(path).convert("RGB")
        if crop:
            if all(isinstance(v, float) and v <= 1.0 for v in crop):
                crop = [int(crop[0] * im.width), int(crop[1] * im.height), int(crop[2] * im.width), int(crop[3] * im.height)]
            im = im.crop(tuple(crop))
        s = max(W / im.width, H / im.height)
        im = im.resize((max(W, round(im.width * s)), max(H, round(im.height * s))), Image.LANCZOS)
        x = (im.width - W) // 2
        y = (im.height - H) // 2
        return im.crop((x, y, x + W, y + H))

    y = head
    for r in rows:
        for i, k in enumerate(cols):
            if k not in r:
                continue
            x = 10 + i * (W + 10)
            S.paste(cell(r[k]), (x, y + lab))
            d.text((x + 4, y + 4), r[k][2], font=FS, fill=hc[i % 3])
        if r.get("note"):
            d.text((12, y + lab + H + 6), r["note"], font=FS, fill=(220, 220, 220))
        y += H + lab + note
    S.save(out, quality=90)
    print(out, S.size)


if __name__ == "__main__":
    {"grade": cmd_grade, "stats": cmd_stats, "sheet": cmd_sheet}[sys.argv[1]](sys.argv[2:])
