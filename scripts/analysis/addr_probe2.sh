#!/bin/sh
S=/usr/local/src/sunxi-tools-h713/sunxi-fel
T=/tmp/ap2; mkdir -p $T
$S version || { echo "session dead"; exit 1; }
for n in 4096 16384 32768; do
  dd if=/dev/urandom of=$T/b bs=1 count=$n status=none
  printf '%6d bytes at 0x104000: ' $n
  if $S write 0x104000 $T/b >/dev/null 2>&1; then echo ok; else echo "FAILED"; exit 0; fi
done
echo "32 KB at the load address is fine too"
