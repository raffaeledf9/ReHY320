#!/bin/sh
M=/mnt/hy320-fs; mkdir -p $M
mountpoint -q $M || mount -o ro,loop,noexec,nosuid,nodev ${HY320_BACKUP:?set HY320_BACKUP to your own folder}/cleaned/vendor_b.img $M
echo "### the mount table, with every space shown"
grep -nE '^(system|vendor|product)[[:space:]]' $M/etc/fstab.sun50iw12p1 | cat -A | sed 's/\$$//'
echo "### file size"
stat -c %s $M/etc/fstab.sun50iw12p1
echo "### free blocks in this file system"
df -B1 $M | tail -1
umount $M
