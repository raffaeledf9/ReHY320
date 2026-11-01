#!/bin/bash
# Read-only: UxPlay /play end-to-end for a direct URL, as the build sees it (patches 0001-0009
# applied to a scratch copy), and the glue around playlistRemove.
MNT=/mnt/hy320-build
mountpoint -q "$MNT" || { mkdir -p "$MNT"; mount -o loop,noatime ${HY320_BUILD:?set HY320_BUILD to your own folder}/build.img "$MNT"; }
S=$MNT/src/app/src/main/cpp
T=$(mktemp -d); cp -r "$S/third_party/UxPlay/lib" "$T/"; cd "$T" && git init -q .
for p in $(ls $S/patches/UxPlay/000*.patch | sort); do git apply --unidiff-zero "$p" || echo "apply failed $p"; done
awk 'NR>=749 && NR<=800 { printf "%d: %s\n", NR, $0 }' lib/http_handlers.h
echo ...
awk 'NR>=955 && NR<=1022 { printf "%d: %s\n", NR, $0 }' lib/http_handlers.h
echo "== MAX_AIRPLAY_VIDEO / MIN_STORED"; grep -rn "define MAX_AIRPLAY_VIDEO\|define MIN_STORED" lib/
echo "== video_play_conn"; grep -n "video_play_conn" lib/*.c lib/*.h | head
echo "== glue playlist_remove"; grep -n "_video_playlist_remove" -A 8 "$S/android_raop_callbacks.c" | head -12
rm -rf "$T"
