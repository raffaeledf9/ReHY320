#!/bin/bash
# Read-only: why the sender's controls stop following the video after a playlistInsert.
# Shows UxPlay's /playback-info and /action replies, how the reverse (event) channel is used,
# and the glue's playback-info path, in the tree as the build sees it (0001-0010 applied to
# a scratch copy).
MNT=/mnt/hy320-build
mountpoint -q "$MNT" || { mkdir -p "$MNT"; mount -o loop,noatime ${HY320_BUILD:?set HY320_BUILD to your own folder}/build.img "$MNT"; }
S=$MNT/src/app/src/main/cpp
T=$(mktemp -d); cp -r "$S/third_party/UxPlay/lib" "$T/"; cd "$T" && git init -q .
# the build leaves the series applied in the submodule; apply only if it is clean
if ! grep -q hy320_playlist_insert lib/http_handlers.h; then
    for p in $(ls $S/patches/UxPlay/*.patch | sort); do git apply --unidiff-zero "$p" || echo "apply failed $p"; done
fi
grep -c hy320 lib/http_handlers.h | sed 's/^/hy320 lines in http_handlers.h: /'
H=lib/http_handlers.h
show() { awk -v a="$1" -v b="$2" 'NR>=a && NR<=b { printf "%d: %s\n", NR, $0 }' "$3"; }
fn() { local s; s=$(grep -n "^$1(" "$2" | head -1 | cut -d: -f1); [ -n "$s" ] && show $((s-1)) $((s+${3:-80})) "$2"; }
echo "===== functions in $H"; grep -n "^http_handler_\|^static .*(\|^hy320" $H | head -60
echo "===== playback_info"; fn http_handler_playback_info $H 90
echo "===== action (tail: replies)"; s=$(grep -n "^http_handler_action(" $H | cut -d: -f1); show $((s+60)) $((s+200)) $H | grep -n "response\|errorCode\|post_action\|playlistRemove\|playlistInsert\|goto\|return\|finish" | head -60
echo "===== rate / scrub"; fn http_handler_rate $H 40; fn http_handler_scrub $H 40
echo "===== reverse / PTTH / event"; grep -rn "PTTH\|CONNECTION_TYPE_\|reverse_request\|/event\|httpd_get_connection_socket" lib/*.c lib/*.h | head -40
echo "===== airplay_video getters"; grep -n "^[a-z].*get_\|^[a-z].*set_" lib/airplay_video.c | head -40
echo "===== glue: playback info / video callbacks"
grep -n "playback_info\|on_video_play\|video_rate\|video_scrub\|position\|duration" "$S/android_raop_callbacks.c" | head -60
echo "===== native_bridge: playback info"
grep -n "playback\|Playback\|position\|duration" "$S/native_bridge.cpp" | head -40
K=$MNT/src/app/src/main/kotlin/io/github/jqssun/airplay
echo "===== kotlin: report playback"
grep -n "_reportPlaybackInfo\|setPlaybackInfo\|nativeSetPlayback\|fun play(\|fun scrub\|fun setRate\|currentPosition\|duration" "$K/renderer/AirPlayVideoPlayer.kt" | head -40
rm -rf "$T"
