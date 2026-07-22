#!/usr/bin/env python3
"""Quantize the rendered sprite PNGs to palette PNGs (huge size win, no
visible loss on these soft-gradient sprites). Usage: compress_pngs.py <dir>"""
import sys
from pathlib import Path
from PIL import Image

d = Path(sys.argv[1])
method = None
for name in ("LIBIMAGEQUANT", "MEDIANCUT", "FASTOCTREE"):
    if hasattr(Image.Quantize, name):
        try:
            Image.new("RGBA", (4, 4)).quantize(colors=8, method=getattr(Image.Quantize, name))
            method = getattr(Image.Quantize, name)
            print("quantize method:", name)
            break
        except Exception:
            continue

total = 0
for p in sorted(d.glob("drum_*.png")):
    img = Image.open(p).convert("RGBA")
    q = img.quantize(colors=256, method=method, dither=Image.Dither.FLOYDSTEINBERG)
    out = p.with_suffix(".q.png")
    q.save(out, optimize=True)
    before, after = p.stat().st_size, out.stat().st_size
    total += after
    print(f"{p.name}: {before//1024}KB -> {after//1024}KB")
print(f"total quantized: {total/1024/1024:.2f} MB")
