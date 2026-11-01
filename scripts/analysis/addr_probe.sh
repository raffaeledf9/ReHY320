#!/bin/sh
# Which memory addresses accept a write? Only chip memory is touched.
S=/usr/local/src/sunxi-tools-h713/sunxi-fel
T=/tmp/ap; mkdir -p $T
dd if=/dev/urandom of=$T/b bs=1 count=1024 status=none
$S version || { echo "session dead, needs a cold start"; exit 1; }
for a in 0x10c000 0x104000 0x11f000 0x100000 0x102000 0x118000; do
  printf '%-10s ' "$a"
  if $S write $a $T/b >/dev/null 2>&1; then echo "write ok"; else echo "WRITE FAILED"; exit 0; fi
done
echo "all probed addresses accepted a write"
