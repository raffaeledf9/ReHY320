#!/bin/sh
# Read-only recovery-mode checks using the addresses from the tool's own chip table
# (H713: scratch 0x10c000, spl 0x104000, chip-id registers 0x03006200).
S=/usr/local/src/sunxi-tools-h713/sunxi-fel
set -e
echo "### chip identification"
$S version
echo "### 32 bytes of the scratch area (0x10c000)"
$S hexdump 0x10c000 32
echo "### 32 bytes of the load area (0x104000)"
$S hexdump 0x104000 32
echo "### the chip's own identity registers (0x03006200)"
$S hexdump 0x03006200 16
echo "### unique chip id as the tool reads it"
$S --sid-dump 2>/dev/null || $S --list --verbose
echo "### all read checks passed"
