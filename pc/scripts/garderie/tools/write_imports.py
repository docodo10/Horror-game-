#!/usr/bin/env python3
"""Writes Godot .import presets for the garderie textures (VRAM compressed + mipmaps; normal maps as RGTC;
masks that must stay exact are lossless). Godot completes them (uid, dest paths) on the next import.

    python3 -I pc/scripts/garderie/tools/write_imports.py pc/assets/garderie/textures
"""
import os
import sys

TEMPLATE = """[remap]

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
compress/normal_map={nm}
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

LOSSLESS = {"mat_edge.png"}
HQ = {"sign_garderie.jpg", "rules.jpg", "notice_board.jpg", "signin.jpg", "labels.jpg", "cubby_labels.png", "banner.png"}

d = sys.argv[1]
res_root = d[d.index("pc/") + 3:] if "pc/" in d else d
for f in sorted(os.listdir(d)):
    if not f.lower().endswith((".png", ".jpg", ".jpeg")):
        continue
    nm = 1 if ("_n.png" in f or "_nor_" in f) else 0
    mode = 0 if f in LOSSLESS else 2
    hq = "true" if f in HQ else "false"
    src = "res://" + os.path.join(res_root, f)
    path = os.path.join(d, f + ".import")
    keep = None
    if os.path.exists(path):
        with open(path) as fh:
            old = fh.read()
        # keep the uid Godot assigned (stable references)
        for line in old.splitlines():
            if line.startswith("uid="):
                keep = line
    text = TEMPLATE.format(src=src, mode=mode, nm=nm, hq=hq)
    if keep:
        text = text.replace('type="CompressedTexture2D"\n', 'type="CompressedTexture2D"\n' + keep + "\n", 1)
    with open(path, "w") as fh:
        fh.write(text)
    print("import preset", f, "normal" if nm else "", "lossless" if mode == 0 else "")
