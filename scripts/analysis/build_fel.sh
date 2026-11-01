#!/bin/sh
# Build the H713-capable sunxi-fel from source in WSL. Nothing is written to any device.
set -e
SRC=/usr/local/src
mkdir -p $SRC
apt-get install -y -qq git build-essential pkg-config libusb-1.0-0-dev zlib1g-dev >/dev/null 2>&1 || true
if [ ! -d $SRC/sunxi-tools-h713 ]; then
  git clone --depth 1 https://github.com/YuujiLab/sunxi-tools.git $SRC/sunxi-tools-h713
fi
cd $SRC/sunxi-tools-h713
echo "### source commit"
git log -1 --format='%H %ad %s'
echo "### does it know the H713 (0x1860)?"
grep -n '0x1860\|sun50iw12\|H713' soc_info.c | head
echo "### licence"
head -3 LICENSE.md 2>/dev/null || head -3 COPYING 2>/dev/null
echo "### building"
make -s sunxi-fel 2>&1 | tail -5
./sunxi-fel --help 2>&1 | head -30
echo "### built binary"
ls -l ./sunxi-fel
