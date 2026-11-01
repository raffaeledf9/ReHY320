#!/bin/sh
# Read-only checks against the projector in recovery mode with the H713-capable tool.
# Reads chip memory only; nothing is written anywhere.
S=/usr/local/src/sunxi-tools-h713/sunxi-fel
echo "### USB devices"
lsusb | grep -i 1f3a || echo "no Allwinner device visible in WSL"
echo "### recovery devices the tool can see"
$S --list --verbose 2>&1
echo "### chip identification"
$S version 2>&1
echo "### 64 bytes of chip memory at the boot ROM address"
$S hexdump 0x0 64 2>&1
echo "### 32 bytes of on-chip RAM"
$S hexdump 0x00020000 32 2>&1
