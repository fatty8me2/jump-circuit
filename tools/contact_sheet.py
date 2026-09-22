"""Tile PNG frames into one contact sheet: python tools/contact_sheet.py <dir> <out.png> [cols]"""
import sys, glob, os
from PIL import Image
files = sorted(glob.glob(os.path.join(sys.argv[1], "*.png")))
cols = int(sys.argv[3]) if len(sys.argv) > 3 else 3
w, h = 640, 360
rows = (len(files) + cols - 1) // cols
sheet = Image.new("RGB", (cols * w, rows * h))
for i, f in enumerate(files):
    sheet.paste(Image.open(f).convert("RGB").resize((w, h)), ((i % cols) * w, (i // cols) * h))
sheet.save(sys.argv[2])
print(len(files), "frames")
