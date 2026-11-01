#!/bin/sh
# Does recovery mode run 64-bit code? The chip is 64-bit; the tool assumes 32-bit.
# Only chip memory is touched. Each step checks the chip is still answering.
S=/usr/local/src/sunxi-tools-h713/sunxi-fel
T=/tmp/x64; mkdir -p $T
alive() { $S version >/dev/null 2>&1; }

echo "### chip"
$S version || { echo "session dead - needs a cold start"; exit 1; }

# AArch64 "ret" = 0xd65f03c0, little endian.
printf '\xc0\x03\x5f\xd6' > $T/ret64.bin
echo "### writing a 64-bit return instruction and running it"
$S write 0x10c000 $T/ret64.bin || { echo "write failed"; exit 1; }
$S exe 0x10c000
if alive; then
  echo "RESULT: 64-bit code runs and the chip survived. The tool's 32-bit assumption is the bug."
else
  echo "RESULT: it stopped answering with 64-bit code too, so running code over recovery mode is simply not usable here."
fi
