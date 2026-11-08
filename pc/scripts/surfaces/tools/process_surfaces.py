"""Build the surfaces module texture sets (pc/assets/hires/<set>/) from the downloaded CC0 sources.
usage: python3 -I process_surfaces.py RAW_DIR OUT_DIR [set ...]
Per set: albedo.jpg (sRGB; L when the source colour is only a variation map), normal.jpg (OpenGL, Y+),
mask.jpg (linear, 4:4:4: R = ambient occlusion, G = height, B = roughness).
shared/: noise.png (512 RGBA tileable fbm), grunge.jpg (2K tileable: R smudges/spots, G vertical streaks, B scuffs).
"""
import os, sys, json
import numpy as np
from PIL import Image

RAW, OUT = sys.argv[1], sys.argv[2]
ONLY = set(sys.argv[3:])
REPORT = {}


def src(d, name):
    p = os.path.join(RAW, d, name)
    if not os.path.exists(p):
        raise SystemExit('missing ' + p)
    return p


def load(p, mode, size=None):
    im = Image.open(p).convert(mode)
    if size and im.size != size:
        im = im.resize(size, Image.LANCZOS)
    return im


def arr(im):
    return np.asarray(im, dtype=np.float32) / 255.0


def img(a, mode):
    return Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8), mode)


def save_jpg(im, path, q, sub=2):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im.save(path, quality=q, optimize=True, subsampling=sub)
    return os.path.getsize(path)


def make_set(name, d, colour, normal, ao, height, rough, colour_mode='RGB', q_col=86, q_nrm=88, q_mask=88,
             size=None, rough_remap=None, levels=False, notes=''):
    if ONLY and name not in ONLY:
        return
    o = os.path.join(OUT, name)
    sizes = {}
    c = load(src(d, colour), 'RGB', size)
    W, H = c.size
    if colour_mode == 'L':
        L = arr(c.convert('L'))
        if levels:  # normalise the variation map around 0.5 (shader uses it as a relative modulation)
            lo, hi = np.percentile(L, 1), np.percentile(L, 99)
            L = 0.5 + (L - np.median(L)) / max(1e-3, (hi - lo)) * 0.5
        sizes['albedo'] = save_jpg(img(np.stack([L, L, L], -1), 'RGB'), os.path.join(o, 'albedo.jpg'), q_col)  # grey RGB (safe sRGB import)
    else:
        sizes['albedo'] = save_jpg(c, os.path.join(o, 'albedo.jpg'), q_col)
    n = load(src(d, normal), 'RGB', (W, H))
    sizes['normal'] = save_jpg(n, os.path.join(o, 'normal.jpg'), q_nrm, sub=0)
    a = arr(load(src(d, ao), 'L', (W, H))) if ao else np.ones((H, W), np.float32)
    h = arr(load(src(d, height), 'L', (W, H))) if height else np.full((H, W), 0.5, np.float32)
    if rough:
        r = arr(load(src(d, rough), 'L', (W, H)))
    else:
        r = np.full((H, W), 0.8, np.float32)
    if rough_remap:
        r = np.clip(rough_remap[0] + rough_remap[1] * (r - rough_remap[2]), 0, 1)
    mask = np.stack([a, h, r], -1)
    sizes['mask'] = save_jpg(img(mask, 'RGB'), os.path.join(o, 'mask.jpg'), q_mask, sub=0)
    REPORT[name] = dict(source=d, size=[W, H], kB={k: v // 1024 for k, v in sizes.items()},
                        total_kB=sum(sizes.values()) // 1024,
                        stats=dict(ao_mean=round(float(a.mean()), 3), h_std=round(float(h.std()), 3),
                                   rough_mean=round(float(r.mean()), 3), rough_std=round(float(r.std()), 3)),
                        notes=notes)
    print(name, REPORT[name], flush=True)


# ------------------------------------------------------------------ tileable noise helpers (FFT based = periodic)
def spectral_noise(n, beta, seed, lo=1.0, hi=None, aniso=(1.0, 1.0)):
    rng = np.random.default_rng(seed)
    w = rng.standard_normal((n, n)).astype(np.float32)
    F = np.fft.fft2(w)
    fy = np.fft.fftfreq(n)[:, None] * n / aniso[1]
    fx = np.fft.fftfreq(n)[None, :] * n / aniso[0]
    f = np.sqrt(fx * fx + fy * fy)
    f[0, 0] = 1.0
    amp = 1.0 / np.power(f, beta / 2.0)
    amp[f < lo] = 0.0
    if hi:
        amp *= np.exp(-(f / hi) ** 2)
    amp[0, 0] = 0.0
    out = np.real(np.fft.ifft2(F * amp)).astype(np.float32)
    out = (out - out.mean()) / (out.std() + 1e-6)
    return out


def norm01(x, p0=0.5, p1=99.5):
    lo, hi = np.percentile(x, p0), np.percentile(x, p1)
    return np.clip((x - lo) / (hi - lo + 1e-6), 0, 1)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def make_shared():
    if ONLY and 'shared' not in ONLY:
        return
    o = os.path.join(OUT, 'shared')
    os.makedirs(o, exist_ok=True)
    N = 512
    r = norm01(spectral_noise(N, 3.2, 11, lo=1.0, hi=40))      # cloudy, large features
    g = norm01(spectral_noise(N, 2.6, 12, lo=1.0, hi=90))      # medium mottling
    b = norm01(spectral_noise(N, 1.8, 13, lo=2.0, hi=220))     # fine grain
    blot = spectral_noise(N, 3.0, 14, lo=2.0, hi=60)           # sparse blotches (stains)
    a = smoothstep(1.1, 2.4, blot) * norm01(spectral_noise(N, 2.0, 15, lo=4.0, hi=200)) ** 0.5
    rgba = np.stack([r, g, b, np.clip(a, 0, 1)], -1)
    p = os.path.join(o, 'noise.png')
    Image.fromarray((rgba * 255 + 0.5).astype(np.uint8), 'RGBA').save(p, optimize=True)
    sizes = {'noise': os.path.getsize(p)}
    # grunge 2K: R = smudges/spots (SurfaceImperfections008 opacity), G = vertical streaks (procedural), B = scuffs (Smear005)
    G = 2048
    sm = arr(load(src('acg_SurfaceImperfections008_2k', 'SurfaceImperfections008_2K-JPG_Opacity.jpg'), 'L', (G, G)))
    sm = norm01(sm, 1, 99.7)
    # streaks: individual run-down lines (water / dirt), each with a start, a length, a width and a gentle meander;
    # wrapped in x and y so the map tiles. Value = strength (fades along the run, broken by fine noise).
    rng = np.random.default_rng(21)
    st = np.zeros((G, G), np.float32)
    yy = np.arange(G, dtype=np.float32)[:, None]
    xx = np.arange(G, dtype=np.float32)[None, :]
    fine = norm01(spectral_noise(G, 1.6, 23, lo=8.0, hi=500))
    for i in range(170):
        x0 = rng.uniform(0, G)
        w = rng.uniform(1.5, 7.0) * (2.2 if rng.random() < 0.12 else 1.0)
        y0 = rng.uniform(0, G)
        ln = rng.uniform(0.15, 0.85) * G
        s = rng.uniform(0.35, 1.0)
        t = np.mod(yy - y0, G) / ln                                   # 0 at the start, 1 at the end
        along = np.where(t <= 1.0, smoothstep(0.0, 0.04, t) * np.power(np.clip(1 - t, 0, 1), 1.3), 0.0)
        mx = x0 + 6.0 * np.sin(yy / G * 2 * np.pi * rng.integers(1, 4) + rng.uniform(0, 6.28))
        dx = np.abs(np.mod(xx - mx + G / 2, G) - G / 2)
        prof = np.exp(-(dx / w) ** 2)
        st = np.maximum(st, s * along * prof)
    st = np.clip(st * (0.55 + 0.6 * fine), 0, 1)
    sc = load(src('acg_Smear005_2k', 'Smear005_2K-JPG_Opacity.jpg'), 'L', (G, G))
    sc = norm01(arr(sc), 1, 99.8)
    grunge = np.stack([sm, st, sc], -1)
    p = os.path.join(o, 'grunge.jpg')
    sizes['grunge'] = save_jpg(img(grunge, 'RGB'), p, 88, sub=0)
    REPORT['shared'] = dict(kB={k: v // 1024 for k, v in sizes.items()},
                            notes='noise.png: R/G/B fbm (large/medium/fine), A sparse blotches; grunge.jpg: R SurfaceImperfections008 '
                                  'opacity, G procedural vertical streaks, B Smear005 opacity (all tileable)')
    print('shared', REPORT['shared'], flush=True)


make_set('wall_plaster', 'ph_painted_plaster_wall_2k', 'painted_plaster_wall_diff_2k.jpg', 'painted_plaster_wall_nor_gl_2k.jpg',
         'painted_plaster_wall_ao_2k.jpg', 'painted_plaster_wall_disp_2k.jpg', 'painted_plaster_wall_rough_2k.jpg',
         notes='Poly Haven painted_plaster_wall (2 m): painted plaster, fine stipple, faint stains')
make_set('ceiling_knockdown', 'ph_ceiling_interior_2k', 'ceiling_interior_diff_2k.jpg', 'ceiling_interior_nor_gl_2k.jpg',
         'ceiling_interior_ao_2k.jpg', 'ceiling_interior_disp_2k.jpg', 'ceiling_interior_rough_2k.jpg', colour_mode='L', levels=True,
         notes='Poly Haven ceiling_interior (2 m): knockdown / dripped paint ceiling; albedo = normalised luminance variation')
make_set('carpet', 'acg_Carpet016_2k', 'Carpet016_2K-JPG_Color.jpg', 'Carpet016_2K-JPG_NormalGL.jpg',
         'Carpet016_2K-JPG_AmbientOcclusion.jpg', 'Carpet016_2K-JPG_Displacement.jpg', 'Carpet016_2K-JPG_Roughness.jpg',
         q_nrm=84, notes='ambientCG Carpet016: beige cut-pile carpet')
make_set('trim_paint', 'acg_PaintedWood009C_2k', 'PaintedWood009C_2K-JPG_Color.jpg', 'PaintedWood009C_2K-JPG_NormalGL.jpg',
         'PaintedWood009C_2K-JPG_AmbientOcclusion.jpg', 'PaintedWood009C_2K-JPG_Displacement.jpg', 'PaintedWood009C_2K-JPG_Roughness.jpg',
         q_nrm=86, notes='ambientCG PaintedWood009C: worn off-white painted wood, grain, cracks')
make_set('block_paint', 'acg_PaintedBricks004_2k', 'PaintedBricks004_2K-JPG_Color.jpg', 'PaintedBricks004_2K-JPG_NormalGL.jpg',
         'PaintedBricks004_2K-JPG_AmbientOcclusion.jpg', 'PaintedBricks004_2K-JPG_Displacement.jpg', 'PaintedBricks004_2K-JPG_Roughness.jpg',
         colour_mode='L', levels=True, q_nrm=86, notes='ambientCG PaintedBricks004: painted block wall (relief in normal/AO/height)')
make_set('wallpaper', 'acg_Wallpaper002B_2k', 'Wallpaper002B_2K-JPG_Color.jpg', 'Wallpaper002B_2K-JPG_NormalGL.jpg',
         None, 'Wallpaper002B_2K-JPG_Displacement.jpg', 'Wallpaper002B_2K-JPG_Roughness.jpg',
         notes='ambientCG Wallpaper002B: textured wallpaper with mould/damp stains')
make_set('concrete_wall', 'ph_concrete_wall_007_2k', 'concrete_wall_007_diff_2k.jpg', 'concrete_wall_007_nor_gl_2k.jpg',
         'concrete_wall_007_ao_2k.jpg', 'concrete_wall_007_disp_2k.jpg', 'concrete_wall_007_rough_2k.jpg',
         notes='Poly Haven concrete_wall_007 (2.16 m): raw cast concrete, formwork lines, tie holes, stains (nook walls of the re-exported level)')
make_shared()
rp = os.path.join(OUT, '..', 'hires_report.json')
if os.path.exists(rp):
    old = json.load(open(rp))
    old.update(REPORT)
    REPORT = old
json.dump(REPORT, open(os.path.join(os.path.dirname(OUT.rstrip('/')), 'hires_report.json'), 'w'), indent=1)
