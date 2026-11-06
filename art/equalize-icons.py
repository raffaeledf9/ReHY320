"""Rebuilds the menu icons so every white glyph is the same optical size, centred.

    python art/equalize-icons.py

It reads `art/original-icons/`, which is not in this repository: those are the
vendor's own icons, lifted off the device, and not mine to redistribute. So this
runs only for someone who has pulled them from their own unit. It is kept as the
record of how the tiles were measured and sized.

The vendor's own icons were drawn to no common measure: the keystone glyph is
61x56, the HDMI one 132x50, and the screen saver one 141x88 on a 390x315 canvas
where every other icon is 240x210 -- which is why it sat higher than the rest,
since the app sizes each icon from its own aspect ratio.

So each icon is rebuilt from the glyph of its *normal* variant, lifted off its
background by its near-white pixels, scaled so every glyph shares one diagonal,
and dropped in the middle of a fresh 240x210 rectangle. Both variants come from
that one glyph, so they can no longer drift apart: only the colour behind them
differs. Diagonal rather than width or height, because the glyphs are different
shapes -- matching widths alone would leave the squarer ones looking far heavier
than the wide flat ones.

Reads the untouched copies in original-icons/ every time, so it can be re-run
and the target changed without the sizes creeping.
"""
import math, pathlib
from PIL import Image

HERE = pathlib.Path(__file__).resolve().parent
ORIGINALS = HERE / "original-icons"
ASSETS = HERE.parent / "app" / "assets"

CANVAS = (240, 210)
PLAIN = (70, 100, 234, 255)
CHOSEN = (36, 169, 241, 255)
TARGET_DIAGONAL = 108.0
NAMES = ["trapezoid", "color", "zoom", "projection", "screensaver", "hdmi"]

def glyph_of(path):
    """The white mark alone, cropped, as an image with everything else clear."""
    im = Image.open(path).convert("RGBA")
    px = im.load()
    w, h = im.size
    out = Image.new("RGBA", im.size, (255, 255, 255, 0))
    op = out.load()
    xs, ys = [], []
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a <= 128:
                continue
            # How white it is, which doubles as the coverage of the mark: the two
            # backgrounds are strongly coloured, so a grey edge pixel is a soft edge.
            lo = min(r, g, b)
            if lo > 110:
                op[x, y] = (255, 255, 255, int(min(255, (lo - 110) * 255 / 145)))
                if lo > 200:
                    xs.append(x); ys.append(y)
    if not xs:
        raise SystemExit(f"no glyph found in {path.name}")
    return out.crop((min(xs), min(ys), max(xs) + 1, max(ys) + 1))

def build(name):
    mark = glyph_of(ORIGINALS / f"icon_mode_{name}.png")
    w, h = mark.size
    scale = TARGET_DIAGONAL / math.hypot(w, h)
    size = (max(1, round(w * scale)), max(1, round(h * scale)))
    mark = mark.resize(size, Image.LANCZOS)
    for suffix, colour in (("", PLAIN), ("_focus", CHOSEN)):
        tile = Image.new("RGBA", CANVAS, colour)
        tile.alpha_composite(mark, ((CANVAS[0] - size[0]) // 2, (CANVAS[1] - size[1]) // 2))
        tile.save(ASSETS / f"icon_mode_{name}{suffix}.png")
    return w, h, size

print(f"{'icon':<14}{'was':<12}{'now':<12}")
for n in NAMES:
    w, h, size = build(n)
    print(f"  {n:<12}{f'{w}x{h}':<12}{f'{size[0]}x{size[1]}':<12}")
