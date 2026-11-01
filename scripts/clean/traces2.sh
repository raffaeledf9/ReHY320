#!/bin/sh
# Where are the remaining mentions? Mount read-only and grep the files, not the raw image.
C=${HY320_BACKUP:?set HY320_BACKUP to your own folder}/cleaned
M=/mnt/hy320-tr; mkdir -p $M/system $M/product
for n in system product; do
  mountpoint -q $M/$n || mount -o ro,loop,noexec,nosuid,nodev "$C/${n}_b.img" $M/$n
done
echo "### files still naming a removed app"
grep -rl 'com.htc.storeos\|com.hotack.writesn\|com.mobisystems.office\|com.android.toofifi' $M/system $M/product 2>/dev/null | sed "s|$M||"
echo "### file systems still check out after zeroing"
for n in system product; do umount $M/$n; e2fsck -fn "$C/${n}_b.img" >/dev/null 2>&1 && echo "  $n: clean" || echo "  $n: PROBLEM"; done
