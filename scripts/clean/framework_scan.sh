#!/bin/sh
# Does the vendor-patched framework contain network destinations or app-store hooks?
M=/mnt/hy320-tr; mkdir -p $M/system
mountpoint -q $M/system || mount -o ro,loop,noexec,nosuid,nodev ${HY320_BACKUP:?set HY320_BACKUP to your own folder}/cleaned/system_b.img $M/system
F=$M/system/system/framework
for j in services.jar framework.jar; do
  echo "######## $j"
  echo "--- web addresses and domains"
  strings -a "$F/$j" | grep -oE 'https?://[A-Za-z0-9./:_-]{6,60}' | sort -u | head -15
  strings -a "$F/$j" | grep -oE '[a-z0-9-]+\.(com|cn|net|xyz|top|io)([/:][A-Za-z0-9./_-]*)?' | sort -u | head -20
  echo "--- app-store and market hooks"
  strings -a "$F/$j" | grep -iE 'dangbei|market|appstore|silent|install_package|pm install' | sort -u | head -12
done
echo "######## keystone and sensor hooks in the framework (useful for ticket 19)"
strings -a "$F/services.jar" | grep -iE 'hotack|keystone' | sort -u | head -25
umount $M/system
