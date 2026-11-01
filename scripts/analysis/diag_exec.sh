#!/bin/sh
# One session, maximum information. Stops at the first failure and says what it means.
# Everything happens in chip memory; storage is only read, never written.
S=/usr/local/src/sunxi-tools-h713/sunxi-fel
N=/usr/local/src/sunxi-tools-h713/sunxi-fel-noicache
D=${HY320_UBOOT:?set HY320_UBOOT to the folder holding the H713 U-Boot build, e.g. /tmp/h713-uboot}
T=/tmp/diag; mkdir -p $T

alive() { $S version >/dev/null 2>&1; }

echo "### 1. is the chip answering?"
$S version || { echo "session dead before we started - needs a cold start"; exit 1; }

echo "### 2. can it run code at all? (a single return instruction)"
printf '\x1e\xff\x2f\xe1' > $T/ret.bin      # bx lr
$S write 0x10c000 $T/ret.bin && $S exe 0x10c000
if alive; then echo "   YES - running code is fine, and the chip survived it"; else
  echo "   NO - running any code stops it answering. The whole approach is out."; exit 1; fi

echo "### 3. the instruction-cache step the tool normally runs first"
$S hexdump 0x10c000 16 >/dev/null 2>&1 || true
if alive; then echo "   still alive"; fi

echo "### 4. load the boot stage with the instruction-cache step SKIPPED"
if $N spl "$D/spl.bin"; then
  echo "   loaded and started"
else
  echo "   FAILED even with that step skipped"; alive && echo "   (chip still answering)"; exit 1
fi

echo "### 5. is main memory up now?"
$N hexdump 0x4a000000 16 || { echo "   main memory not answering: this board's timings differ from the HY310"; exit 1; }

echo "### 6. load U-Boot itself, in pieces"
off=0
for f in $(ls "$D"/chunk_*.bin | sort); do
  a=$(printf '0x%x' $((0x4a000000 + off)))
  $N write $a "$f" || { echo "   FAILED at $f"; exit 1; }
  off=$((off + $(stat -c %s "$f")))
done
echo "   loaded $off bytes"

echo "### 7. start U-Boot (it should offer the storage to the PC as a USB drive)"
$N exe 0x4a000000
echo "### done"
