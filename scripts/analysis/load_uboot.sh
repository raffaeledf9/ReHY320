#!/bin/sh
# Load the installer U-Boot into the projector's memory through recovery mode.
# Writes nothing to storage: the U-Boot's own boot command only exposes the
# storage to the PC as a USB drive, which we then read.
S=/usr/local/src/sunxi-tools-h713/sunxi-fel
IMG=${HY320_UBOOT:?set HY320_UBOOT to the folder holding the H713 U-Boot build, e.g. /tmp/h713-uboot}/u-boot-installer.bin
echo "### chip before loading"
$S version || exit 1
echo "### loading U-Boot (nothing is written to storage)"
$S uboot "$IMG"
echo "### load command returned $?"
