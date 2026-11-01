#!/bin/sh
# Load the installer U-Boot in small pieces, so one big transfer cannot time out.
# Everything goes into the projector's memory; storage is never written.
S=/usr/local/src/sunxi-tools-h713/sunxi-fel
D=${HY320_UBOOT:?set HY320_UBOOT to the folder holding the H713 U-Boot build, e.g. /tmp/h713-uboot}
ADDR=0x4a000000
echo "### 1. chip"
$S version || exit 1
echo "### 2. load and run the first stage (32 KB) - brings up main memory"
$S spl "$D/spl.bin" || { echo "FAILED at the 32 KB transfer"; exit 1; }
echo "### 3. can main memory be read now?"
$S hexdump $ADDR 16 || { echo "FAILED: main memory not answering, board timings differ"; exit 1; }
echo "### 4. load U-Boot in 64 KB pieces"
off=0
for f in $(ls "$D"/chunk_*.bin | sort); do
  a=$(printf '0x%x' $((0x4a000000 + off)))
  $S write $a "$f" || { echo "FAILED at piece $f (address $a)"; exit 1; }
  off=$((off + $(stat -c %s "$f")))
done
echo "### loaded $off bytes"
echo "### 5. start it"
$S exe $ADDR
echo "### start command returned $?"
