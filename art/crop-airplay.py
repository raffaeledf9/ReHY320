"""Lifts the AirPlay app's own mark out of a screenshot, for the menu icon.

    python art/crop-airplay.py <screenshot.png> <out.png>

The app ships its icon as a vector buried in compiled resources, so the quickest
honest source is a picture of it on the projector's own screen. The mark is dark
on white there, which is the opposite of every other menu glyph, so this keeps
the shape and throws the colour away: darkness becomes coverage, and the caller
paints it white on the palette blue.
"""
import pathlib
import sys

from PIL import Image

BOX = (140, 590, 290, 740)      # the first Apps tile's icon, on a 1920x1080 shot


def main():
    source = pathlib.Path(sys.argv[1])
    out = pathlib.Path(sys.argv[2])
    im = Image.open(source).convert("RGBA").crop(BOX)
    px = im.load()
    w, h = im.size
    mark = Image.new("RGBA", im.size, (255, 255, 255, 0))
    mp = mark.load()
    xs, ys = [], []
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            dark = 255 - max(r, g, b)       # how far from white this pixel is
            if dark > 40:
                mp[x, y] = (255, 255, 255, min(255, int(dark * 255 / 215)))
                if dark > 150:
                    xs.append(x)
                    ys.append(y)
    if not xs:
        raise SystemExit("no mark found in that box")
    mark.crop((min(xs), min(ys), max(xs) + 1, max(ys) + 1)).save(out)
    print(f"mark {max(xs) - min(xs) + 1}x{max(ys) - min(ys) + 1} -> {out}")


if __name__ == "__main__":
    main()
