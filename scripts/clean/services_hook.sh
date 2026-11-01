#!/bin/sh
# What does the framework's services.jar say about the removed apps? Read-only.
M=/mnt/hy320-tr; mkdir -p $M/system
mountpoint -q $M/system || mount -o ro,loop,noexec,nosuid,nodev ${HY320_BACKUP:?set HY320_BACKUP to your own folder}/cleaned/system_b.img $M/system
J=$M/system/system/framework/services.jar
echo "### which removed app names appear"
for n in com.htc.storeos com.hotack.writesn com.mobisystems.office com.android.toofifi \
         com.htc.htcotaupdate com.htc.samescreen com.htc.htclauncherhighenglishd08; do
  c=$(strings -a "$J" | grep -c "^$n$\|$n" || true)
  [ "$c" -gt 0 ] && echo "  $n appears $c time(s)"
done
echo "### vendor-looking strings near them"
strings -a "$J" | grep -nE 'com\.(htc|hotack|android\.toofifi|mobisystems)' | head -20
echo "### any vendor class names in the framework"
strings -a "$J" | grep -iE 'hotack|htc/|toofifi|^Lcom/htc' | head -15
umount $M/system
