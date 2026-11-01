"""Draws the File server tile for the projector's own menu.

    python art/make-server-icon.py

A folder with a signal coming off it: the storage, reachable over the network.
Drawn here because no vendor icon exists for it, to the same measure as the rest
-- 240x210, the menu's two blues, a glyph 108 pixels across the diagonal -- so it
sits among them without standing out.

Deliberately not the drop box's tray-and-down-arrow: that one only takes files
in, while this shares a folder both ways, and the two should not look alike.
"""
import math
import pathlib

from PIL import Image, ImageDraw

HERE = pathlib.Path(__file__).resolve().parent
ASSETS = HERE.parents[1] / "app" / "assets"

CANVAS = (240, 210)
PLAIN = (70, 100, 234, 255)
CHOSEN = (36, 169, 241, 255)
TARGET_DIAGONAL = 108.0

OVER = 4
W, H = 170, 150
STROKE = 12


def glyph():
    big = Image.new("RGBA", (W * OVER, H * OVER), (255, 255, 255, 0))
    pen = ImageDraw.Draw(big)
    white = (255, 255, 255, 255)

    # The folder: a tab, then the body, filling the lower left.
    left, right = 0, int(W * 0.72) * OVER
    top, bottom = int(H * 0.42) * OVER, H * OVER
    tab_right = int(W * 0.34) * OVER
    pen.rounded_rectangle([left, top - STROKE * OVER, tab_right, top + STROKE * OVER],
                          radius=4 * OVER, fill=white)
    pen.rounded_rectangle([left, top, right, bottom], radius=5 * OVER, fill=white)

    # The signal, from the folder's top right corner outwards.
    cx, cy = right - STROKE * OVER // 2, top
    for radius in (int(W * 0.17), int(W * 0.29), int(W * 0.41)):
        r = radius * OVER
        pen.arc([cx - r, cy - r, cx + r, cy + r], start=265, end=355,
                fill=white, width=STROKE * OVER)

    small = big.resize((W, H), Image.LANCZOS)
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
        tile.save(ASSETS / f"icon_mode_server{suffix}.png")
    print(f"server glyph {w}x{h} -> {size[0]}x{size[1]}, "
          f"diagonal {math.hypot(*size):.1f} (target {TARGET_DIAGONAL})")


if __name__ == "__main__":
    main()
