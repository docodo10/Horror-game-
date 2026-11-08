"""Godot Decal textures for the surfaces module (pc/assets/hires/decals/<id>/): albedo.png (RGBA, straight alpha:
colour where the stain is, alpha = coverage with soft edges so the decal box never shows), orm.jpg (R occlusion,
G roughness, B metallic) where the stain changes the sheen.
usage: python3 -I process_decals.py RAW_DIR OUT_DIR [id ...]
"""
import os, sys, json
import numpy as np
from PIL import Image

RAW, OUT = sys.argv[1], sys.argv[2]
ONLY = set(sys.argv[3:])
REPORT = {}
rng = np.random.default_rng(7)


def p(d, name):
    return os.path.join(RAW, d, name)


def load(path, mode, box=None, size=None):
    im = Image.open(path).convert(mode)
    if box:
        w, h = im.size
        im = im.crop((int(box[0] * w), int(box[1] * h), int(box[2] * w), int(box[3] * h)))
    if size and im.size != size:
        im = im.resize(size, Image.LANCZOS)
    return np.asarray(im, dtype=np.float32) / 255.0


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def smooth_noise(h, w, cells, seed):
    r = np.random.default_rng(seed).random((cells, cells)).astype(np.float32)
    return np.asarray(Image.fromarray((r * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC), np.float32) / 255.0


def radial(h, w, inner, outer, wobble, seed):
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    r = np.hypot((x + 0.5) / w - 0.5, (y + 0.5) / h - 0.5)
    r = r + wobble * (smooth_noise(h, w, 5, seed) - 0.5) + 0.04 * (smooth_noise(h, w, 13, seed + 1) - 0.5)
    return 1.0 - smoothstep(inner, outer, r)


def side_fade(h, w, sx=0.15, top=0.0, bottom=0.0):
    x = (np.arange(w, dtype=np.float32) + 0.5) / w
    fx = smoothstep(0, sx, x) * smoothstep(0, sx, 1 - x)
    y = (np.arange(h, dtype=np.float32) + 0.5) / h
    fy = np.ones_like(y)
    if top:
        fy *= smoothstep(0, top, y)
    if bottom:
        fy *= smoothstep(0, bottom, 1 - y)
    return fy[:, None] * fx[None, :]


def write(did, col, alpha, rough=None, notes='', out=None):
    if ONLY and did not in ONLY:
        return
    if out:  # resample to the shipped size (alpha-weighted colour so dark fringes do not bleed)
        W0, H0 = out
        alpha = np.clip(alpha, 0, 1)
        if col.ndim == 1:
            col = np.broadcast_to(col, alpha.shape + (3,))
        pre = np.concatenate([col * alpha[..., None], alpha[..., None]], -1)
        pre = np.stack([np.asarray(Image.fromarray(pre[..., k].astype(np.float32), 'F').resize((W0, H0), Image.LANCZOS)) for k in range(4)], -1)
        alpha = np.clip(pre[..., 3], 0, 1)
        col = np.clip(pre[..., :3] / np.maximum(alpha[..., None], 1e-4), 0, 1)
        if rough is not None:
            rough = np.asarray(Image.fromarray(np.asarray(rough, np.float32), 'F').resize((W0, H0), Image.LANCZOS))
    o = os.path.join(OUT, did)
    os.makedirs(o, exist_ok=True)
    H, W = alpha.shape
    alpha = np.clip(alpha, 0, 1)
    if col.ndim == 1:
        col = np.broadcast_to(col, (H, W, 3))
    col = np.clip(col, 0, 1)
    wsum = alpha.sum() + 1e-6
    mean = (col * alpha[..., None]).sum((0, 1)) / wsum
    col = col * (alpha[..., None] > 0.004) + mean * (alpha[..., None] <= 0.004)   # flat colour under alpha 0 (smaller PNG)
    rgba = np.concatenate([col, alpha[..., None]], -1)
    Image.fromarray((rgba * 255 + 0.5).astype(np.uint8), 'RGBA').save(os.path.join(o, 'albedo.png'), optimize=True)
    files = ['albedo.png']
    if rough is not None:
        rs = Image.fromarray((np.clip(rough, 0, 1) * 255 + 0.5).astype(np.uint8), 'L').resize((max(64, W // 2), max(64, H // 2)), Image.LANCZOS)
        r = np.asarray(rs, np.float32) / 255.0
        orm = np.stack([np.ones_like(r), r, np.zeros_like(r)], -1)
        Image.fromarray((orm * 255 + 0.5).astype(np.uint8), 'RGB').save(os.path.join(o, 'orm.jpg'), quality=90, subsampling=0)
        files.append('orm.jpg')
    kb = sum(os.path.getsize(os.path.join(o, f)) for f in files) // 1024
    edge = float(max(alpha[0].max(), alpha[-1].max(), alpha[:, 0].max(), alpha[:, -1].max()))
    REPORT[did] = dict(size=[W, H], kB=kb, files=files, alpha_mean=round(float(alpha.mean()), 3), edge_alpha_max=round(edge, 3),
                       mean_rgb=[round(float(c), 3) for c in mean], notes=notes)
    print(did, REPORT[did], flush=True)


def tea(lum, dark, light):
    t = np.clip(lum, 0, 1)[..., None]
    return np.array(dark, np.float32) * (1 - t) + np.array(light, np.float32) * t


# 1. leak streaks (ceiling leak run-down on a wall): Leaking003 central half (full 2K resolution), top edge hard
a = load(p('acg_Leaking003_2k', 'Leaking003_2K-JPG_Opacity.jpg'), 'L', box=(0.25, 0, 0.75, 1))
c = load(p('acg_Leaking003_2k', 'Leaking003_2K-JPG_Color.jpg'), 'L', box=(0.25, 0, 0.75, 1))
H, W = a.shape
al = np.clip(a * 1.15, 0, 1) * side_fade(H, W, 0.2, 0.0, 0.1)
lum = (c - c.min()) / (np.percentile(c, 99) - c.min() + 1e-6)
col = tea(lum, (0.30, 0.21, 0.11), (0.66, 0.55, 0.36))
write('leak_streaks', col, al, rough=0.72 + 0.1 * (1 - al), notes='ambientCG Leaking003 (opacity x side fades, top edge hard), recoloured tea-brown')

# 2. rising damp at the foot of a wall: Leaking008 (2048x512) -> 1024x256, bottom edge hard
a = load(p('acg_Leaking008_2k', 'Leaking008_2K-JPG_Opacity.jpg'), 'L', size=(1024, 256))
c = load(p('acg_Leaking008_2k', 'Leaking008_2K-JPG_Color.jpg'), 'L', size=(1024, 256))
H, W = a.shape
al = np.clip(a * 1.1, 0, 1) * side_fade(H, W, 0.18, 0.06, 0.0)
col = tea(c / (c.max() + 1e-6), (0.16, 0.14, 0.11), (0.42, 0.37, 0.29))
write('rising_damp', col, al, rough=0.6 + 0.3 * (1 - al), notes='ambientCG Leaking008 (opacity x side fades, bottom edge hard), dark damp grey-brown, glossier when wet')

# 3. rust drip under a screw / the breaker panel: Leaking010C central quarter -> 256x1024
a = load(p('acg_Leaking010C_2k', 'Leaking010C_2K-JPG_Opacity.jpg'), 'L', box=(0.375, 0, 0.625, 1), size=(256, 1024))
c = load(p('acg_Leaking010C_2k', 'Leaking010C_2K-JPG_Color.jpg'), 'RGB', box=(0.375, 0, 0.625, 1), size=(256, 1024))
H, W = a.shape
al = np.clip(a * 1.6, 0, 1) * side_fade(H, W, 0.22, 0.0, 0.04)
lum = c.mean(-1)
col = tea(lum / (np.percentile(lum, 99) + 1e-6), (0.20, 0.08, 0.03), (0.55, 0.30, 0.12))
write('rust_drip', col, al, rough=0.8 + 0.1 * (1 - al), notes='ambientCG Leaking010C (central quarter, opacity x 1.6 x side fades), rust brown')

# 4. hand smudges (greasy prints): Fingerprints009 1024 crop at full resolution, radial falloff
a = load(p('acg_Fingerprints009_2k', 'Fingerprints009_2K-JPG_Opacity.jpg'), 'L', box=(0.2, 0.2, 0.7, 0.7))
H, W = a.shape
al = np.clip(a * 1.35, 0, 1) ** 1.2 * radial(H, W, 0.16, 0.48, 0.12, 3)
col = np.array([0.33, 0.29, 0.25], np.float32) * (0.85 + 0.3 * smooth_noise(H, W, 9, 4)[..., None])
write('hand_smudges', col, al, rough=0.85 - 0.45 * al, notes='ambientCG Fingerprints009 (crop, opacity x 1.35 x radial), greasy = glossier', out=(512, 512))

# 5. wall grime patch: SurfaceImperfections008 -> 1024, radial
a = load(p('acg_SurfaceImperfections008_2k', 'SurfaceImperfections008_2K-JPG_Opacity.jpg'), 'L', size=(1024, 1024))
H, W = a.shape
al = np.clip((a - 0.15) * 1.5, 0, 1) * radial(H, W, 0.15, 0.47, 0.16, 5)
col = np.array([0.24, 0.21, 0.17], np.float32) * (0.8 + 0.4 * smooth_noise(H, W, 7, 6)[..., None])
write('grime', col, al, rough=np.full((H, W), 0.92, np.float32), notes='ambientCG SurfaceImperfections008 (opacity-0.15 x 1.5 x radial)', out=(512, 512))

# 6. rubber scuffs: Smear005 band -> 1024x512, side fades
a = load(p('acg_Smear005_2k', 'Smear005_2K-JPG_Opacity.jpg'), 'L', box=(0, 0.3, 1, 0.8), size=(1024, 512))
H, W = a.shape
al = np.clip(a * 1.2, 0, 1) * side_fade(H, W, 0.12, 0.06, 0.06)
col = np.array([0.14, 0.125, 0.11], np.float32)
write('scuffs', col, al, rough=0.85 - 0.3 * al, notes='ambientCG Smear005 (band, opacity x side fades), dark rubber', out=(512, 256))

# 7. floor dirt patch (carpet / concrete): SurfaceImperfections001 -> 1024, radial
a = load(p('acg_SurfaceImperfections001_2k', 'SurfaceImperfections001_2K-JPG_Opacity.jpg'), 'L', size=(1024, 1024))
H, W = a.shape
al = np.clip(a * 1.6, 0, 1) * radial(H, W, 0.1, 0.46, 0.15, 8)
col = np.array([0.30, 0.25, 0.19], np.float32) * (0.8 + 0.4 * smooth_noise(H, W, 6, 9)[..., None])
write('dirt_patch', col, al, notes='ambientCG SurfaceImperfections001 (opacity x 1.6 x radial), warm dirt', out=(512, 512))

# 8. muddy footprints: Footsteps004 (512x2048 trail, ~4.6 mm/px), crop of 4 prints -> 256x1024 (decal ~0.95 x 1.9 m); prints = darker than the flat ground of the colour map
c = load(p('acg_Footsteps004_2k', 'Footsteps004_2K-JPG_Color.jpg'), 'L', box=(0.3, 0.55, 0.7, 0.95), size=(256, 1024))
H, W = c.shape
flat = np.median(c)
pr = np.clip((flat - c) / 0.16, 0, 1)
fade = 0.35 + 0.65 * np.linspace(0.0, 1.0, H, dtype=np.float32)[:, None] ** 0.8      # fainter toward the top (shoes clean)
al = np.clip(pr * 1.4, 0, 1) * fade * side_fade(H, W, 0.05, 0.03, 0.03) * (0.75 + 0.25 * smooth_noise(H, W, 11, 10))
col = np.array([0.24, 0.19, 0.14], np.float32)
write('footprints', col, al, notes='ambientCG Footsteps004 (print mask = darker than ground, fading along the trail), muddy brown')

# 9. ceiling water-stain tide ring (derived from SurfaceImperfections002 opacity), 1024
a_src = load(p('acg_SurfaceImperfections002_2k', 'SurfaceImperfections002_2K-JPG_Opacity.jpg'), 'L', size=(1024, 1024))
H = W = 1024
y, x = np.mgrid[0:H, 0:W].astype(np.float32)
r = np.hypot((x + 0.5) / W - 0.5, (y + 0.5) / H - 0.5)
n1 = smooth_noise(H, W, 7, 11) - 0.5
n2 = smooth_noise(H, W, 17, 12) - 0.5
n3 = smooth_noise(H, W, 40, 13) - 0.5
rr = r + 0.08 * n1 + 0.025 * n2 + 0.006 * n3
R0 = 0.33
brk = smoothstep(-0.25, 0.2, smooth_noise(H, W, 11, 14) - 0.5)
tide = np.exp(-((rr - R0) / 0.008) ** 2) * (0.35 + 0.65 * brk)
halo = np.exp(-((rr - (R0 - 0.02)) / 0.03) ** 2) * 0.35
old1 = np.exp(-((rr - (R0 - 0.075)) / 0.007) ** 2) * 0.55 * smoothstep(-0.05, 0.25, n2 + 0.1)
old2 = np.exp(-((rr - (R0 - 0.14)) / 0.006) ** 2) * 0.4 * smoothstep(0.0, 0.3, -n1 + 0.05)
fill = (1 - smoothstep(R0 - 0.03, R0 + 0.005, rr)) * (0.06 + 0.3 * np.clip(a_src - 0.2, 0, 1) + 0.12 * smoothstep(-0.2, 0.3, n2))
al = np.clip(tide + halo + old1 + old2 + fill, 0, 1) * (1 - smoothstep(0.43, 0.49, r))
line = np.clip(tide + old1 + old2, 0, 1)[..., None]
light = np.array([0.66, 0.53, 0.32], np.float32)
dark = np.array([0.36, 0.23, 0.10], np.float32)
col = light * (1 - line) + dark * line
write('water_ring', col, al, rough=0.9 - 0.1 * al, notes='DERIVED: noisy annulus tide lines x SurfaceImperfections002 opacity blotches, tea-brown', out=(768, 768))

# 10. mould colony (derived from Wallpaper002C: darkness vs clean paper x noisy radial falloff), 1024
cc = load(p('acg_Wallpaper002C_2k', 'Wallpaper002C_2K-JPG_Color.jpg'), 'RGB', size=(1024, 1024))
lum = cc @ np.array([0.2126, 0.7152, 0.0722], np.float32)
white = np.percentile(lum, 97)
dk = np.clip((white - lum) / (white - np.percentile(lum, 3)), 0, 1)
H = W = 1024
mask = radial(H, W, 0.08, 0.45, 0.22, 21)
clumps = smoothstep(0.35, 0.75, smooth_noise(H, W, 9, 22))
al = np.clip(dk * 1.6, 0, 1) ** 1.1 * mask * (0.45 + 0.55 * clumps)
blk = np.array([0.05, 0.06, 0.04], np.float32)
grn = np.array([0.28, 0.30, 0.20], np.float32)
t = np.clip(dk * 1.3, 0, 1)[..., None]
col = (grn * (1 - t) + blk * t) * (0.8 + 0.4 * cc)
write('mold', col, al, rough=np.full((H, W), 0.97, np.float32), notes='DERIVED: ambientCG Wallpaper002C darkness x noisy radial falloff, olive-black', out=(512, 512))

# 11. pipe leak: fan-shaped seep under a pipe penetration (Leaking006) -> 512x1024, top hole kept
a = load(p('acg_Leaking006_2k', 'Leaking006_2K-JPG_Opacity.jpg'), 'L', box=(0.25, 0, 0.75, 1), size=(512, 1024))
c = load(p('acg_Leaking006_2k', 'Leaking006_2K-JPG_Color.jpg'), 'RGB', box=(0.25, 0, 0.75, 1), size=(512, 1024))
H, W = a.shape
yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
fan_w = 0.06 + 0.4 * (yy + 0.5) / H
fan = 1.0 - smoothstep(fan_w * 0.55, fan_w, np.abs((xx + 0.5) / W - 0.5) + 0.03 * (smooth_noise(H, W, 9, 31) - 0.5))
al = np.clip(a * 0.9, 0, 1) * fan * side_fade(H, W, 0.08, 0.0, 0.12)
lum = c.mean(-1)
col = tea(lum / (np.percentile(lum, 99) + 1e-6), (0.22, 0.17, 0.11), (0.50, 0.43, 0.32))
write('pipe_leak', col, al, rough=0.75 + 0.1 * (1 - al), notes='ambientCG Leaking006 (central half, opacity x side fades), yellow-brown seep')


# 12. crayon scribbles (7 cells, like the web Details crayon atlas): waxy strokes with wall-grain dropout
def crayon_cell(seed, kind):
    from PIL import ImageDraw
    S = 384
    R = np.random.default_rng(seed)
    im = Image.new('L', (S, S), 0)
    colim = Image.new('RGB', (S, S), (0, 0, 0))
    dr = ImageDraw.Draw(im)
    dc = ImageDraw.Draw(colim)
    pal = [(200, 53, 42), (47, 95, 179), (63, 154, 60), (232, 184, 30), (236, 138, 36), (109, 63, 168), (28, 26, 29), (224, 106, 148)]

    def stroke(pts, col, w):
        dr.line(pts, fill=255, width=w, joint='curve')
        dc.line(pts, fill=col, width=w, joint='curve')
    if kind == 'scribble':
        for k in range(3):
            col = pal[R.integers(0, len(pal))]
            cx, cy = R.uniform(90, 290, 2)
            pts = [(cx + R.normal(0, 60), cy + R.normal(0, 40)) for _ in range(28)]
            stroke(pts, col, int(R.integers(5, 9)))
    elif kind == 'sun':
        col = pal[3]
        cx, cy, r = 190, 180, 60
        pts = [(cx + r * np.cos(t) + R.normal(0, 3), cy + r * np.sin(t) + R.normal(0, 3)) for t in np.linspace(0, 6.6, 40)]
        stroke(pts, col, 8)
        for t in np.linspace(0, 6.28, 11)[:-1]:
            stroke([(cx + 75 * np.cos(t), cy + 75 * np.sin(t)), (cx + 120 * np.cos(t) + R.normal(0, 6), cy + 120 * np.sin(t) + R.normal(0, 6))], pal[4], 6)
    elif kind == 'house':
        col = pal[0]
        stroke([(110, 300), (110, 190), (270, 190), (270, 300), (110, 300)], col, 7)
        stroke([(95, 195), (190, 105), (285, 195)], pal[6], 7)
        stroke([(170, 300), (170, 245), (210, 245), (210, 300)], pal[1], 6)
    elif kind == 'figures':
        for k, x in enumerate((120, 200, 280)):
            col = pal[[6, 1, 7][k]]
            h = [150, 120, 95][k]
            y0 = 320 - h
            pts = [(x + 22 * np.cos(t), y0 + 22 * np.sin(t)) for t in np.linspace(0, 6.5, 24)]
            stroke(pts, col, 6)
            stroke([(x, y0 + 22), (x, y0 + h * 0.65)], col, 6)
            stroke([(x - 30, y0 + h * 0.35), (x + 30, y0 + h * 0.35)], col, 6)
            stroke([(x, y0 + h * 0.65), (x - 22, 320)], col, 6)
            stroke([(x, y0 + h * 0.65), (x + 22, 320)], col, 6)
    elif kind == 'zigzag':
        col = pal[2]
        pts = [(40 + i * 30, 190 + (45 if i % 2 else -45) + R.normal(0, 8)) for i in range(11)]
        stroke(pts, col, 8)
        pts = [(50 + i * 28, 280 + (25 if i % 2 else -25)) for i in range(11)]
        stroke(pts, pal[5], 6)
    elif kind == 'spiral':
        col = pal[5]
        t = np.linspace(0, 18, 140)
        pts = [(190 + 7 * tt * np.cos(tt), 190 + 7 * tt * np.sin(tt)) for tt in t]
        stroke(pts, col, 6)
    else:  # hearts / tally marks
        col = pal[7]
        for k in range(6):
            x = 80 + k * 40
            stroke([(x, 140 + R.normal(0, 5)), (x + R.normal(0, 6), 250)], pal[6] if k == 4 else col, 7)
        stroke([(70, 200), (300, 190)], pal[6], 6)
    a = np.asarray(im, np.float32) / 255.0
    cc = np.asarray(colim, np.float32) / 255.0
    grain = np.asarray(Image.fromarray((np.random.default_rng(seed + 50).random((S, S)) * 255).astype(np.uint8)).resize((S, S)), np.float32) / 255.0
    a = a * np.clip(0.35 + 0.9 * grain, 0, 1)        # wax skips over the wall texture
    a = np.clip(a * 0.95, 0, 1)
    cc = cc / np.maximum(a[..., None] / 0.95 + 1e-3, 1.0) if False else cc
    return cc, a


for i, kind in enumerate(['scribble', 'sun', 'house', 'figures', 'zigzag', 'spiral', 'tally']):
    col, al = crayon_cell(100 + i, kind)
    write('crayon_%d' % i, col, al, rough=0.55 + 0.4 * (1 - al), notes='procedural crayon %s (waxy strokes, grain dropout)' % kind, out=(256, 256))

rp = os.path.join(os.path.dirname(OUT.rstrip('/')), 'decals_report.json')
json.dump(REPORT, open(rp, 'w'), indent=1)
