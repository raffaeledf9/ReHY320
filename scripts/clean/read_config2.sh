#!/bin/sh
M=/mnt/hy320-cfg; mkdir -p $M
mountpoint -q $M || mount -o ro,loop,noexec,nosuid,nodev ${HY320_BACKUP:?set HY320_BACKUP to your own folder}/analysis/logical/product_b.img $M
sed -n '100,200p' $M/etc/config.ini 2>/dev/null
echo "--- files in /product/etc:"
ls $M/etc
cp $M/etc/config.ini $HY320_BACKUP/analysis/inventory/product-config.ini 2>/dev/null && echo "saved a copy of config.ini"
umount $M
