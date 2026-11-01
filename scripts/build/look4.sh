#!/bin/bash
# Read-only: exact text (cat -A: tabs ^I, line ends $) where hy320.5 edits UxPlay.
MNT=/mnt/hy320-build
mountpoint -q "$MNT" || { mkdir -p "$MNT"; mount -o loop,noatime ${HY320_BUILD:?set HY320_BUILD to your own folder}/build.img "$MNT"; }
U=$MNT/src/app/src/main/cpp/third_party/UxPlay/lib
cd "$U" || exit 1
H=http_handlers.h
at() { awk -v a="$1" -v b="$2" 'NR>=a && NR<=b { printf "%d: %s\n", NR, $0 }' "$3" | cat -A | sed 's/\$$//'; }
s=$(grep -n "^int create_playback_info_plist_xml" $H | cut -d: -f1); echo "== create ($s)"; at $s $((s+8)) $H
echo "== playback_info handler"; at 379 400 $H
echo "== raop.h struct"; at 37 41 raop.h
e=$(grep -n "unknown action type (unhandled)" $H | cut -d: -f1); echo "== action end"; at $((e-1)) $((e+6)) $H
echo "== set_property actionAtItemEnd"; grep -n "actionAtItemEnd" -B2 -A6 $H | cat -A | sed 's/\$$//'
echo "== includes"; grep -n "#include" raop.c | head -30
echo "== httpd PTTH read side"; at 455 480 httpd.c
echo "== Android build flags for UxPlay"; grep -rn "ANDROID\|system_properties" $MNT/src/app/src/main/cpp/CMakeLists.txt | head; grep -rln "__ANDROID__" . | head
