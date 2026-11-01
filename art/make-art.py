"""Draws the app's pictures from art.html and puts them where the build wants them.

    python art/make-art.py

The two symbols are Bootstrap Icons (MIT): `projector` for the launcher icon and
the TV banner, `hdmi` for the menu entry. `art.html` paints each one onto a
canvas at the exact size needed, in the projector's own blues, and leaves the
PNG bytes in a hidden element. Headless Edge renders the page and prints the
DOM, because the browser pane cannot script a local file and the page needs no
server this way.
"""
import base64, pathlib, re, subprocess, sys

HERE = pathlib.Path(__file__).resolve().parent
APP = HERE.parents[1] / "app"
EDGE = pathlib.Path(r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe")
TARGETS = {
    "icon_mode_hdmi": APP / "assets" / "icon_mode_hdmi.png",
    "icon_mode_hdmi_focus": APP / "assets" / "icon_mode_hdmi_focus.png",
    "icon": APP / "res" / "drawable-nodpi" / "icon.png",
    "banner": APP / "res" / "drawable-nodpi" / "banner.png",
}

if not EDGE.is_file():
    sys.exit(f"no browser to draw with at {EDGE}")

dom = subprocess.run([str(EDGE), "--headless", "--disable-gpu", "--no-sandbox", "--dump-dom",
                      (HERE / "art.html").as_uri()],
                     capture_output=True, text=True, timeout=120).stdout
block = re.search(r'id="data"[^>]*>(.*?)</pre>', dom, re.S)
if not block:
    sys.exit("the page did not leave its data element behind; did the script fail?")

wrote = []
for line in block.group(1).strip().splitlines():
    name, _, b64 = line.strip().partition(" ")
    if name in TARGETS and b64:
        TARGETS[name].parent.mkdir(parents=True, exist_ok=True)
        TARGETS[name].write_bytes(base64.b64decode(b64))
        wrote.append(name)
missing = sorted(set(TARGETS) - set(wrote))
if missing:
    sys.exit(f"the page did not draw: {', '.join(missing)}")
print("drew " + ", ".join(wrote))
