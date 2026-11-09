#!/usr/bin/env python3
"""Contact sheet of garderie preview renders.
    python3 -I contact_sheet.py <out.jpg> <cols> <label=path> [<label=path> ...]
"""
import sys

from PIL import Image, ImageDraw, ImageFont

out = sys.argv[1]
cols = int(sys.argv[2])
items = [a.split("=", 1) for a in sys.argv[3:]]
tw, th = 640, 360
pad = 6
cap = 26
rows = (len(items) + cols - 1) // cols
sheet = Image.new("RGB", (cols * (tw + pad) + pad, rows * (th + cap + pad) + pad), (14, 14, 16))
d = ImageDraw.Draw(sheet)
try:
    f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 17)
except OSError:
    f = ImageFont.load_default()
for i, (label, path) in enumerate(items):
    im = Image.open(path).convert("RGB").resize((tw, th), Image.LANCZOS)
    x = pad + (i % cols) * (tw + pad)
    y = pad + (i // cols) * (th + cap + pad)
    sheet.paste(im, (x, y + cap))
    d.text((x + 4, y + 4), label, font=f, fill=(255, 214, 90))
sheet.save(out, quality=88)
print("wrote", out, sheet.size)
