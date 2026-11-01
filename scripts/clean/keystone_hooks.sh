#!/bin/sh
M=/mnt/hy320-tr; mkdir -p $M/system
mountpoint -q $M/system || mount -o ro,loop,noexec,nosuid,nodev ${HY320_BACKUP:?set HY320_BACKUP to your own folder}/cleaned/system_b.img $M/system
F=$M/system/system/framework/services.jar
echo "### keystone, sensor and motor strings in the framework"
strings -a "$F" | grep -iE 'hotack|keystone|motor|vaf' | sort -u
umount $M/system
