"""Applies the HY320 end-of-video fix to AirPlay Server v0.0.36, in the source tree inside the build image.

    python3 patch.py /mnt/hy320-build/src

THE BUG. When a video ends (or the player errors), the app releases its player at once
and pushes duration = -1. The sender's next GET /playback-info finds that sentinel, and
UxPlay answers with no body, closes the connection and resets the HLS session. The iPad
keeps its AirPlay route, but the receiver has hung up on its player mid-session: the
open player can no longer send the next episode, and the end is never reported as one.

THE FIX. Keep the player when it ends or fails. Its report tick goes on answering polls
with where it stopped -- at the end, position = duration and rate 0, which is how a real
Apple TV reports a finished item -- and the sender ends the session itself: POST /stop, or
a /play of the next item (play() already recycles the player for that). If the sender
does neither within FINISHED_HOLD_MS, the old teardown runs as a fallback.

The edits themselves are in patch_edits.py. Every one must match exactly once, or nothing
is written: a mismatch means the source is not the version they were written against.
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from patch_edits import edits  # noqa: E402

ROOT = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "/mnt/hy320-build/src")
PART = sys.argv[2] if len(sys.argv) > 2 else "app"   # "app", or "uxplay" with ROOT = the submodule

pending = {}
for rel, changes in edits(PART).items():
    path = ROOT / rel
    text = path.read_text(encoding="utf-8")
    for old, new in changes:
        n = text.count(old)
        if n != 1:
            sys.exit(f"{rel}: expected 1 match, found {n}, for:\n{old}")
        text = text.replace(old, new)
    pending[path] = text
for path, text in pending.items():
    path.write_text(text, encoding="utf-8")
    print(f"patched {path.relative_to(ROOT)}")
