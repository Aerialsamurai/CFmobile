"""Turns a rounded-square logo on a white background into a full-bleed 1024x1024 iOS app icon.

iOS applies its own rounded mask, so the icon must be a plain square with no transparency and no white corners.
We crop to the logo's bounding box, fit a smooth colour gradient to the clean outer ring of the logo, and use that
fit to fill the corners/edges. The central glyph is left untouched.

Usage: python3 tools/make_icon.py <input-image> <output.png>
"""
import sys
import numpy as np
from PIL import Image, ImageFilter

src, dst = sys.argv[1], sys.argv[2]
im = Image.open(src).convert("RGB")
a = np.asarray(im).astype(np.float64)

# helpers (PIL-only so no scipy is needed)
def erode(mask, px):
    # pad with False first so the mask also shrinks away from the image border
    padded = np.pad(mask, px + 1, constant_values=False)
    m = Image.fromarray((padded * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(2 * px + 1))
    return (np.asarray(m) > 127)[px + 1:-(px + 1), px + 1:-(px + 1)]

def blur(arr, r):
    return np.asarray(Image.fromarray((arr * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(r))).astype(np.float64) / 255

# 1. the logo = pixels that aren't (near) white background. The glyph is white too, but it sits inside the logo,
#    so fill each row/column between its first and last non-background pixel (the logo is convex).
bg = (a.min(axis=2) > 238)
logo = ~bg
rows = np.zeros_like(logo); cols = np.zeros_like(logo)
for y in range(logo.shape[0]):
    xs_ = np.where(logo[y])[0]
    if len(xs_) > 20: rows[y, xs_.min():xs_.max() + 1] = True
for x in range(logo.shape[1]):
    ys_ = np.where(logo[:, x])[0]
    if len(ys_) > 20: cols[ys_.min():ys_.max() + 1, x] = True
logo = rows & cols
ys, xs = np.where(logo)
y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
side = min(y1 - y0, x1 - x0)
cy, cx = (y0 + y1) // 2, (x0 + x1) // 2
y0, x0 = cy - side // 2, cx - side // 2
crop = a[y0:y0 + side, x0:x0 + side]
inside = logo[y0:y0 + side, x0:x0 + side]
print("logo box", (x0, y0, side), "inside fraction", inside.mean().round(3))

# 2. clean samples of the background gradient: inside the logo, away from the edge and away from the glyph
h = side
safe = erode(inside, 14)
yy, xx = np.mgrid[0:h, 0:h]
glyph_box = (xx > h * 0.14) & (xx < h * 0.86) & (yy > h * 0.14) & (yy < h * 0.86)
sample = safe & ~glyph_box
print("gradient samples", int(sample.sum()))

# 3. fit a quadratic surface per channel
def design(x, y):
    x = x / h; y = y / h
    return np.stack([np.ones_like(x), x, y, x * y, x * x, y * y], axis=-1)

A = design(xx[sample].astype(float), yy[sample].astype(float))
coef = [np.linalg.lstsq(A, crop[..., c][sample], rcond=None)[0] for c in range(3)]
full = design(xx.astype(float), yy.astype(float))
fit = np.stack([full @ coef[c] for c in range(3)], axis=-1)
err = np.abs(fit[sample] - crop[sample]).mean()
print("mean fit error (0-255):", round(float(err), 2))

# 4. keep original pixels in the safely-inside region, use the fit elsewhere, feather the seam
keep = erode(inside, 10)
w = blur(keep.astype(float), 5)[..., None]
w = np.clip((w - 0.5) * 2 + 0.5, 0, 1)
out = crop * w + fit * (1 - w)
out = np.clip(out, 0, 255).astype(np.uint8)

icon = Image.fromarray(out).resize((1024, 1024), Image.LANCZOS)
icon.save(dst, "PNG")
print("saved", dst, icon.size, icon.mode)
