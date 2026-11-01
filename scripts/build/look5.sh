#!/bin/bash
# Read-only: the app's player and the service paths that report playback to UxPlay.
MNT=/mnt/hy320-build
mountpoint -q "$MNT" || { mkdir -p "$MNT"; mount -o loop,noatime ${HY320_BUILD:?set HY320_BUILD to your own folder}/build.img "$MNT"; }
K=$MNT/src/app/src/main/kotlin/io/github/jqssun/airplay
echo "== AirPlayVideoPlayer.kt"; awk '{ printf "%d: %s\n", NR, $0 }' "$K/renderer/AirPlayVideoPlayer.kt"
echo "== AirPlayService.kt video section"
grep -n "onVideo\|_endVideoPlayback\|airPlayVideoPlayer\.\|_videoPollSuppressed\|_lastVideoPollAt\|onVideoSessionPoll" "$K/service/AirPlayService.kt"
echo "== glue update_playback_info"; S=$MNT/src/app/src/main/cpp
grep -n "android_callbacks_update_playback_info" -A 18 "$S/android_raop_callbacks.c" | head -30
