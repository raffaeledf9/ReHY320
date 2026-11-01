#!/bin/sh
# Read-only: try the memory areas this chip actually reports.
S=/usr/local/src/sunxi-tools-h713/sunxi-fel
$S version
for a in 0x00100000 0x0010C000 0x00120000 0x00121500 0x00028000 0x00044000; do
  printf '%s: ' "$a"
  out=$($S hexdump $a 16 2>&1 | head -2 | tr '\n' ' ')
  echo "$out"
done
