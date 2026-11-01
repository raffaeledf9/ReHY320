"""Draws the AirPlay tile for the projector's own menu.

    python art/crop-airplay.py <screenshot.png> art/airplay-mark.png
    python art/make-airplay-icon.py

The mark is the AirPlay app's own, lifted off a screenshot by crop-airplay.py --
the app ships its icon as a vector inside compiled resources, so a picture of it
on the projector's screen is the quickest honest source. It arrives as coverage
with the colour thrown away, which is exactly what is wanted: here it is painted
white on the menu's two blues.

Everything else matches equalize-icons.py, which rebuilt the vendor's five: the
same 240x210 canvas, the same two background colours, the same 108-pixel
diagonal. So this tile cannot look like a visitor among the others.
"""
import math
import pathlib

from PIL import Image

HERE = pathlib.Path(__file__).resolve().parent
ASSETS = HERE.parents[1] / "app" / "assets"
MARK = HERE / "airplay-mark.png"

CANVAS = (240, 210)
PLAIN = (70, 100, 234, 255)
CHOSEN = (36, 169, 241, 255)
TARGET_DIAGONAL = 108.0


def main():
    mark = Image.open(MARK).convert("RGBA")
    mark = mark.crop(mark.getbbox())
    w, h = mark.size
    scale = TARGET_DIAGONAL / math.hypot(w, h)
    size = (max(1, round(w * scale)), max(1, round(h * scale)))
    mark = mark.resize(size, Image.LANCZOS)
    for suffix, colour in (("", PLAIN), ("_focus", CHOSEN)):
        tile = Image.new("RGBA", CANVAS, colour)
        tile.alpha_composite(mark, ((CANVAS[0] - size[0]) // 2,
                                    (CANVAS[1] - size[1]) // 2))
        tile.save(ASSETS / f"icon_mode_airplay{suffix}.png")
    print(f"airplay mark {w}x{h} -> {size[0]}x{size[1]}, "
          f"diagonal {math.hypot(*size):.1f} (target {TARGET_DIAGONAL})")


if __name__ == "__main__":
    main()
