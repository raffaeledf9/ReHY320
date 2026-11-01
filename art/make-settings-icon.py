"""Draws the Settings tile for the projector's own menu.

    python art/make-settings-icon.py

A cog, for Android's own settings, which the menu now opens directly rather than
sending you back to the home screen for them. Drawn here because no vendor icon
exists for it, to the same measure as the rest -- 240x210, the menu's two blues,
a glyph 108 pixels across the diagonal -- so it sits among them without standing
out.

Eight teeth rather than the six or twelve a cog is often drawn with: at this size
six reads as a flower and twelve closes up into a disc.
"""
import math
import pathlib

from PIL import Image, ImageDraw

HERE = pathlib.Path(__file__).resolve().parent
ASSETS = HERE.parent / "app" / "assets"

CANVAS = (240, 210)
PLAIN = (70, 100, 234, 255)
CHOSEN = (36, 169, 241, 255)
TARGET_DIAGONAL = 108.0

OVER = 4
SIDE = 160
TEETH = 8


def glyph():
    big = Image.new("RGBA", (SIDE * OVER, SIDE * OVER), (255, 255, 255, 0))
    pen = ImageDraw.Draw(big)
    white = (255, 255, 255, 255)

    centre = SIDE * OVER / 2.0
    crown = SIDE * OVER * 0.47        # out to the flat top of a tooth
    root = SIDE * OVER * 0.355        # the body the teeth stand on

    # The outline is walked all the way round rather than built tooth by tooth, so
    # crown and root stay true arcs and the two meet on a straight flank. A tooth is
    # centred on each period: flat on top for TOP of it, sloping for FLANK, then the
    # valley, and the same again mirrored on the way down.
    top, flank = 0.15, 0.07
    points = []
    samples = 24 * TEETH
    for k in range(samples):
        angle = 2 * math.pi * k / samples
        phase = (k / samples * TEETH) % 1.0
        away = min(phase, 1.0 - phase)          # 0 on a tooth's centre line
        if away <= top:
            radius = crown
        elif away >= top + flank:
            radius = root
        else:
            radius = crown + (root - crown) * (away - top) / flank
        points.append((centre + radius * math.cos(angle),
                       centre + radius * math.sin(angle)))
    pen.polygon(points, fill=white)

    # The hub, cut clean through: the draw writes pixels rather than blending, so
    # a transparent fill takes the middle back out again.
    hub = SIDE * OVER * 0.165
    pen.ellipse([centre - hub, centre - hub, centre + hub, centre + hub],
                fill=(255, 255, 255, 0))

    small = big.resize((SIDE, SIDE), Image.LANCZOS)
    return small.crop(small.getbbox())


def main():
    mark = glyph()
    w, h = mark.size
    scale = TARGET_DIAGONAL / math.hypot(w, h)
    size = (max(1, round(w * scale)), max(1, round(h * scale)))
    mark = mark.resize(size, Image.LANCZOS)
    for suffix, colour in (("", PLAIN), ("_focus", CHOSEN)):
        tile = Image.new("RGBA", CANVAS, colour)
        tile.alpha_composite(mark, ((CANVAS[0] - size[0]) // 2,
                                    (CANVAS[1] - size[1]) // 2))
        tile.save(ASSETS / f"icon_mode_settings{suffix}.png")
    print(f"settings glyph {w}x{h} -> {size[0]}x{size[1]}, "
          f"diagonal {math.hypot(*size):.1f} (target {TARGET_DIAGONAL})")


if __name__ == "__main__":
    main()
