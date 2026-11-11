"""Builds the comparison board + frequency chart from the rendered concepts and stats.json.
Usage: python3 -I tools/research/compose.py <dir with concept-*.raw.png> <stats.json>"""
import json, os, sys
from PIL import Image, ImageDraw, ImageFont

d, stats_path = sys.argv[1], sys.argv[2]

def font(size, bold=False):
    for p in ["/usr/share/fonts/truetype/dejavu/DejaVuSans%s.ttf" % ("-Bold" if bold else ""), "/usr/share/fonts/dejavu/DejaVuSans%s.ttf" % ("-Bold" if bold else "")]:
        if os.path.exists(p): return ImageFont.truetype(p, size)
    return ImageFont.load_default()

def rounded(im, radius=96):
    w, h = im.size
    m = Image.new("L", (w * 2, h * 2), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, w * 2 - 1, h * 2 - 1), radius * 2, fill=255)
    m = m.resize((w, h), Image.LANCZOS)
    o = Image.new("RGBA", (w, h), (0, 0, 0, 0)); o.paste(im.convert("RGB"), (0, 0), m)
    b = Image.new("RGBA", (w * 2, h * 2), (0, 0, 0, 0))
    ImageDraw.Draw(b).rounded_rectangle((1, 1, w * 2 - 2, h * 2 - 2), radius * 2, outline=(110, 110, 120, 255), width=4)
    return Image.alpha_composite(o, b.resize((w, h), Image.LANCZOS))

CONCEPTS = [
    ("speed", "A · Speed row", "The 10 symbols that save the most taps,\nno scrolling. Hold a key for variants."),
    ("swipe", "B · Swipe keys", "Tap = main symbol, swipe = alternates\nprinted on the key (Textastic style)."),
    ("smart", "C · Smart row", "First keys change with what you just typed\n(cin → >>). Symbols only, no words."),
    ("grid", "D · Two-row grid", "16 keys always visible, nothing to open.\nUses ~48 px more screen."),
    ("keyboard", "E · Code keyboard", "Replaces the iPhone keyboard: symbols and\ndigits always on screen (biggest change)."),
    ("current", "F · Current version", "Quick keys + category buttons\n(what is in the app now)."),
]
phones = {}
for key, _, _ in CONCEPTS:
    im = Image.open(os.path.join(d, f"concept-{key}.raw.png"))
    r = rounded(im)
    r.save(os.path.join(d, f"concept-{key}.png"), optimize=True)
    phones[key] = r

# ---- board
PW = 340; PH = int(PW * 844 / 390)
M = 36; CAP = 96; COLS = 3
W = COLS * PW + (COLS + 1) * M
H = 2 * (PH + CAP) + 3 * M + 70
board = Image.new("RGB", (W, H), (16, 16, 18))
dr = ImageDraw.Draw(board)
dr.text((M, 22), "Shortcut-bar concepts (mock-ups)", font=font(26, True), fill=(235, 235, 240))
for i, (key, title, desc) in enumerate(CONCEPTS):
    c, r = i % COLS, i // COLS
    x = M + c * (PW + M); y = 70 + M + r * (PH + CAP + M)
    ph = phones[key].resize((PW, PH), Image.LANCZOS)
    board.paste(ph, (x, y), ph)
    dr.text((x, y + PH + 12), title, font=font(20, True), fill=(10, 132, 255) if key != "current" else (150, 150, 158))
    dr.multiline_text((x, y + PH + 42), desc, font=font(14), fill=(190, 190, 198), spacing=4)
board.save(os.path.join(d, "board.png"), optimize=True)

# ---- frequency chart
s = json.load(open(stats_path))
f = s["per_1000_chars"]
layer = {}
for c in ";:()-/&\"@$.,?!'": layer[c] = 1
for c in "[]{}#%^*+=_\\|~<>": layer[c] = 2
extra = {1: 2, 2: 3}
rows = sorted(((c, f[c], layer[c], f[c] * extra[layer[c]]) for c in f if c in layer), key=lambda r: -r[3])[:20]
mx = rows[0][3]
CW, RH = 1100, 38
CH = 150 + len(rows) * RH + 70
ch = Image.new("RGB", (CW, CH), (16, 16, 18))
d2 = ImageDraw.Draw(ch)
d2.text((30, 22), "Which symbols are worth a spot on the bar?", font=font(26, True), fill=(235, 235, 240))
d2.text((30, 62), f"Measured on {s['files']} real competitive-programming C++ files ({s['lines']:,} lines).", font=font(15), fill=(170, 170, 178))
d2.text((30, 86), "Bar length = taps saved per 1,000 typed characters. A symbol on the iPhone's ‘#+=’ page costs 3 extra taps, on ‘123’ 2 extra.", font=font(13), fill=(150, 150, 158))
y = 130
for c, v, l, sv in rows:
    d2.text((40, y + 3), c if c != "\\" else "\\", font=font(22, True), fill=(235, 235, 240))
    bw = int((CW - 520) * sv / mx)
    col = (255, 159, 10) if l == 2 else (10, 132, 255)
    d2.rounded_rectangle((100, y + 4, 100 + bw, y + RH - 8), 6, fill=col)
    d2.text((110 + bw, y + 6), f"{sv:.0f}", font=font(15, True), fill=(235, 235, 240))
    d2.text((CW - 380, y + 7), f"{v:5.1f} per 1,000 chars   ·   in {s['files_with_pct'][c]:.0f}% of files", font=font(14), fill=(170, 170, 178))
    y += RH
d2.rounded_rectangle((100, y + 18, 124, y + 36), 4, fill=(10, 132, 255)); d2.text((132, y + 18), "on the ‘123’ page", font=font(14), fill=(190, 190, 198))
d2.rounded_rectangle((330, y + 18, 354, y + 36), 4, fill=(255, 159, 10)); d2.text((362, y + 18), "on the ‘#+=’ page (hardest to reach)", font=font(14), fill=(190, 190, 198))
ch.save(os.path.join(d, "symbol-frequency.png"), optimize=True)
print("board", board.size, "chart", ch.size)
