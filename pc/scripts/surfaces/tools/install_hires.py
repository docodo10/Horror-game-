"""Copy the built texture sets into pc/assets/hires/ and write Godot .import presets next to them
(VRAM compressed + mipmaps; normal maps in normal-map mode; the small fbm noise lossless).
usage: python3 -I install_hires.py BUILD_HIRES_DIR PC_HIRES_DIR
"""
import os, shutil, sys

src, dst = sys.argv[1], sys.argv[2]
PARAMS = """[params]

compress/mode={mode}
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map={normal}
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
total = 0
for root, dirs, files in os.walk(src):
    rel = os.path.relpath(root, src)
    for f in sorted(files):
        if not f.lower().endswith(('.jpg', '.png')):
            continue
        sp = os.path.join(root, f)
        dp = os.path.join(dst, rel, f) if rel != '.' else os.path.join(dst, f)
        os.makedirs(os.path.dirname(dp), exist_ok=True)
        shutil.copyfile(sp, dp)
        total += os.path.getsize(dp)
        res_path = 'res://assets/hires/' + os.path.relpath(dp, dst).replace(os.sep, '/')
        normal = 1 if f.startswith('normal') else 2
        mode = 0 if f == 'noise.png' else 2
        imp = dp + '.import'
        if os.path.exists(imp):
            # keep Godot's generated uid / dest paths; only rewrite the params block
            text = open(imp).read()
            head = text.split('[params]')[0]
            open(imp, 'w').write(head + PARAMS.format(mode=mode, normal=normal))
        else:
            open(imp, 'w').write('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[deps]\n\nsource_file="%s"\n\n' % res_path
                                 + PARAMS.format(mode=mode, normal=normal))
print('installed %.1f MB' % (total / 1e6))
