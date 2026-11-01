#!/bin/sh
# Read the vendor settings app's own feature configuration. Read-only.
M=/mnt/hy320-cfg; mkdir -p $M
mountpoint -q $M || mount -o ro,loop,noexec,nosuid,nodev ${HY320_BACKUP:?set HY320_BACKUP to your own folder}/analysis/logical/product_b.img $M
echo "######## /product/etc/config.ini (the vendor settings app's feature switches)"
sed -n '30,200p' $M/etc/config.ini 2>/dev/null
echo
echo "######## other configuration files in /product/etc"
ls -l $M/etc 2>/dev/null | head -30
umount $M
