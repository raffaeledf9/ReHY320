#!/bin/sh
# Read-only: identify the chip, then read the scratch area it reports itself.
# Stops at the first failure so one bad request cannot wedge the mode.
S=/usr/local/src/sunxi-tools-h713/sunxi-fel
set -e
echo "### chip identification"
$S version
echo "### 32 bytes at the scratch address the chip reports"
$S hexdump 0x00121500 32
echo "### 64 bytes further into the same area"
$S hexdump 0x00122000 64
echo "### all read checks passed"
