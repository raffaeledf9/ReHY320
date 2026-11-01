#!/bin/sh
# Find the largest block that can be written into the projector's memory.
# Only the chip's scratch area is touched; storage is never written.
S=/usr/local/src/sunxi-tools-h713/sunxi-fel
T=/tmp/felprobe
mkdir -p $T
$S version || exit 1
for n in 64 1024 4096 16384 32768; do
  dd if=/dev/urandom of=$T/b bs=1 count=$n status=none
  printf '%6d bytes: ' $n
  if $S write 0x10c000 $T/b >/dev/null 2>&1; then echo "ok"; else echo "FAILED - this is the limit"; exit 0; fi
done
echo "all sizes up to 32 KB wrote fine"
