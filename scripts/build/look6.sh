#!/bin/bash
# Read-only: how UxPlay reads the sender's replies on the reverse (PTTH) connection.
MNT=/mnt/hy320-build
mountpoint -q "$MNT" || { mkdir -p "$MNT"; mount -o loop,noatime ${HY320_BUILD:?set HY320_BUILD to your own folder}/build.img "$MNT"; }
cd "$MNT/src/app/src/main/cpp/third_party/UxPlay/lib" || exit 1
grep -n "is_reverse\|reverse" raop.c httpd.c http_request.c | head -30
echo ----
n=$(grep -n "http_request_get_reverse\|http_request_is_reverse\|is_reverse" raop.c | head -1 | cut -d: -f1)
[ -n "$n" ] && awk -v a=$((n-8)) -v b=$((n+30)) 'NR>=a && NR<=b { printf "%d: %s\n", NR, $0 }' raop.c
