#!/bin/bash
# Proves the build can live on an exFAT drive: an ext4 image file on it, loop-mounted in WSL,
# gives Linux permissions, symlinks and case sensitivity that exFAT itself lacks.
# Measures small-file and bulk write speed, then removes everything it made.
IMG=${HY320_BUILD:?set HY320_BUILD to your own folder}/test.img
MNT=/mnt/hy320-build
mountpoint -q "$MNT" || { truncate -s 2G "$IMG"; mkfs.ext4 -q -F "$IMG"; mkdir -p "$MNT"; mount -o loop "$IMG" "$MNT"; }
mountpoint "$MNT"
cd "$MNT" || exit 1
rm -rf t big link
mkdir t
S=$(date +%s%N)
for i in $(seq 1 3000); do echo y > "t/g$i"; done
sync
E=$(date +%s%N)
echo "3000 small files: $(( (E - S) / 1000000 )) ms"
ln -s t link && ls -ld link
touch t/Case t/case && echo "case-sensitive: $(ls t | grep -ci '^case$') entries"
dd if=/dev/zero of=big bs=1M count=500 conv=fsync 2>&1 | tail -1
cd /
umount "$MNT" && echo UNMOUNTED
rm -f "$IMG"
ls -la $HY320_BUILD
