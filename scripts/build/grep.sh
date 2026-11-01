#!/bin/bash
# Read-only look into the source inside the image: what the end-of-video patch touches.
S=/mnt/hy320-build/src/app/src/main/kotlin/io/github/jqssun/airplay
cd "$S" || exit 1
echo "== AirPlayService.kt"
grep -n "_videoPlaybackActive\|_endVideoPlayback\|onEnded\|_videoPollSuppressed\|_lastVideoPollAt\|VideoPollPending\|override fun onVideoPlay\|onConnectionDestroy" service/AirPlayService.kt
echo "== other users"
grep -rn "videoPlaybackActive\|stopVideoPlayback\|videoPollPending" --include=*.kt . | grep -v "service/AirPlayService.kt"
echo "== around the poll-pending flag"
sed -n 130,150p service/AirPlayService.kt
