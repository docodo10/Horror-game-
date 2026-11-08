"""Re-encode the Poly Haven 2K model maps into OUT/models/<model>/{albedo,normal,arm|rough}.jpg.
usage: python3 -I process_models.py RAW_DIR OUT_DIR"""
import os, sys
from PIL import Image

raw, out = os.path.join(sys.argv[1], 'models_2k'), os.path.join(sys.argv[2], 'models')
total = 0
for model in sorted(os.listdir(raw)):
    src = os.path.join(raw, model)
    dst = os.path.join(out, model)
    os.makedirs(dst, exist_ok=True)
    for f in sorted(os.listdir(src)):
        kind = 'albedo' if '_diff_' in f else 'normal' if '_nor_gl_' in f else 'arm' if '_arm_' in f else 'rough' if '_rough_' in f else None
        if not kind:
            continue
        im = Image.open(os.path.join(src, f))
        im = im.convert('L' if kind == 'rough' else 'RGB')
        p = os.path.join(dst, kind + '.jpg')
        q = 88 if kind == 'normal' else 86
        im.save(p, quality=q, optimize=True, subsampling=0 if kind in ('normal', 'arm') else 2)
        total += os.path.getsize(p)
    print(model, sorted(os.listdir(dst)), sum(os.path.getsize(os.path.join(dst, x)) for x in os.listdir(dst)) // 1024, 'kB')
print('total %.1f MB' % (total / 1e6))
