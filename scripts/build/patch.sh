#!/bin/bash
# Applies the HY320 end-of-video fix to the clean v0.0.36 tree in the image, shows the diff.
#
#   powershell -File scripts\build\start.ps1 patch      (log: <build>\patch.log)
#
# Resets the tree to the tag first, so running it twice cannot apply the edits twice.
set -euo pipefail
MNT=/mnt/hy320-build
IMG=${HY320_BUILD:?set HY320_BUILD to your own folder}/build.img
# Passed in by start.ps1, which knows where the repository is; this script is piped
# into bash, so it cannot work that out from $0.
REPO=${REPO:?set REPO to the scripts/build folder of this repository, as WSL sees it}
mountpoint -q "$MNT" || { mkdir -p "$MNT"; mount -o loop,noatime "$IMG" "$MNT"; }

sudo -u "#${SUDO_UID:-1000}" env MNT="$MNT" REPO="$REPO" bash <<'USER'
set -euo pipefail
cd "$MNT/src"
UX=app/src/main/cpp/third_party/UxPlay
P=app/src/main/cpp/patches/UxPlay
OURS="$P/0010-hy320-new-url-is-new-video.patch"
git checkout -q -- .
rm -f "$OURS"
git -C "$UX" reset -q --hard
mkdir -p "$MNT/patch"
for f in patch.py patch_edits.py; do sed 's/\r$//' "$REPO/$f" > "$MNT/patch/$f"; done

echo "== app sources"
python3 "$MNT/patch/patch.py" "$MNT/src" app

echo "== UxPlay: the app's own patches first, then ours on top, kept as $OURS"
for p in $(ls "$P"/*.patch | sort); do git -C "$UX" apply --unidiff-zero "$PWD/$p"; done
git -C "$UX" add -A
python3 "$MNT/patch/patch.py" "$MNT/src/$UX" uxplay
git -C "$UX" --no-pager diff > "$OURS"
git -C "$UX" reset -q --hard
echo "-- check: the full series applies cleanly to a clean UxPlay"
for p in $(ls "$P"/*.patch | sort); do git -C "$UX" apply --check --unidiff-zero "$PWD/$p" 2>&1 \
    || { echo "FAILS: $p"; exit 1; }; git -C "$UX" apply --unidiff-zero "$PWD/$p"; done
git -C "$UX" reset -q --hard
echo "series ok: $(ls "$P"/*.patch | wc -l) patches"

git --no-pager diff --stat
{ git --no-pager diff; cat "$OURS"; } > $HY320_BUILD/out/hy320-fixes.patch
git --no-pager diff
cat "$OURS"
USER
