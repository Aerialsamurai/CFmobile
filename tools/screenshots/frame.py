"""Rounds the corners of the raw screenshots (like a phone screen) and writes the final README images.
Usage: python3 tools/screenshots/frame.py docs/screenshots
"""
import sys, glob, os
from PIL import Image, ImageDraw

folder = sys.argv[1]
for raw in sorted(glob.glob(os.path.join(folder, "*.raw.png"))):
    im = Image.open(raw).convert("RGB")
    w, h = im.size
    radius = 96
    mask = Image.new("L", (w * 2, h * 2), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, w * 2 - 1, h * 2 - 1), radius * 2, fill=255)
    mask = mask.resize((w, h), Image.LANCZOS)
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.paste(im, (0, 0), mask)
    # thin bezel line so dark screens don't vanish into a dark README background
    border = Image.new("RGBA", (w * 2, h * 2), (0, 0, 0, 0))
    ImageDraw.Draw(border).rounded_rectangle((1, 1, w * 2 - 2, h * 2 - 2), radius * 2, outline=(110, 110, 120, 255), width=4)
    out = Image.alpha_composite(out, border.resize((w, h), Image.LANCZOS))
    dst = raw.replace(".raw.png", ".png")
    out.save(dst, optimize=True)
    os.remove(raw)
    print(dst, os.path.getsize(dst) // 1024, "KB")
