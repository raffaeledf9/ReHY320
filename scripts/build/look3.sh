#!/bin/bash
# Read-only: the pieces a currentItemChanged event and a uuid in /playback-info would need,
# in the UxPlay tree of the image (the build leaves the patch series applied there).
MNT=/mnt/hy320-build
mountpoint -q "$MNT" || { mkdir -p "$MNT"; mount -o loop,noatime ${HY320_BUILD:?set HY320_BUILD to your own folder}/build.img "$MNT"; }
S=$MNT/src/app/src/main/cpp
U=$S/third_party/UxPlay/lib
cd "$U" || exit 1
echo "== helpers"; grep -n "reverse_request_init\|httpd_get_connection_socket_by_type\|^int httpd_get_connection_socket\|httpd_count_connection_type\|CONNECTION_TYPE_PTTH" *.c *.h | head -20
echo "== fcup_request.h (how the reverse channel is written)"; awk '{ printf "%d: %s\n", NR, $0 }' fcup_request.h | sed -n '1,140p'
echo "== create_playback_info_plist_xml"; s=$(grep -n "^int create_playback_info_plist_xml" http_handlers.h | cut -d: -f1); awk -v a=$s 'NR>=a && NR<=a+60 { printf "%d: %s\n", NR, $0 }' http_handlers.h
echo "== playback_info_t"; grep -n "typedef struct playback_info_s" -A 22 raop.h
echo "== action: start and end"; s=$(grep -n "^http_handler_action(" http_handlers.h | cut -d: -f1); awk -v a=$s 'NR>=a && NR<=a+75 { printf "%d: %s\n", NR, $0 }' http_handlers.h
e=$(grep -n "unknown action type (unhandled)" http_handlers.h | cut -d: -f1); awk -v a=$e 'NR>=a-3 && NR<=a+30 { printf "%d: %s\n", NR, $0 }' http_handlers.h
echo "== playlistRemove branch"; s=$(grep -n 'if (!strcmp(type,"playlistRemove"))' http_handlers.h | cut -d: -f1); awk -v a=$s 'NR>=a && NR<=a+22 { printf "%d: %s\n", NR, $0 }' http_handlers.h
echo "== hls_get_current_video / get_playlist_by_uuid"; grep -n "hls_get_current_video\|^get_playlist_by_uuid" -A 14 http_handlers.h | head -40
echo "== raop struct video fields"; grep -n "current_video\|removed_video\|video_play_conn\|airplay_video\[" raop.c | head -20
echo "== how the request is dispatched to handlers (response for void handlers)"; grep -n "http_handler_action\|http_handler_playback_info" raop.c raop_handlers.h | head
echo "== glue: update_playback_info and acquire"; sed -n '120,145p;300,385p' "$S/android_raop_callbacks.c"
