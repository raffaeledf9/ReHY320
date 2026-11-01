#!/bin/sh
A=${HY320_BACKUP:?set HY320_BACKUP to your own folder}/analysis
mkdir -p /mnt/hy320/system /mnt/hy320/vendor /mnt/hy320/product
for n in system vendor product; do
  case $n in system|vendor|product) img=$A/logical/${n}_b.img ;; esac
  mountpoint -q /mnt/hy320/$n || mount -o ro,loop,noexec,nosuid,nodev "$img" /mnt/hy320/$n 2>/dev/null
done
echo "### rules that set the permission of the raw storage device"
grep -rn 'mmcblk0' /mnt/hy320/system/system/etc/ueventd.rc /mnt/hy320/vendor/ueventd.rc /mnt/hy320/vendor/etc/ueventd.rc 2>/dev/null | sed 's|/mnt/hy320||'
echo
echo "### all ueventd files present"
find /mnt/hy320 -name 'ueventd*' 2>/dev/null | sed 's|/mnt/hy320||'
echo
echo "### where the five pre-authorised app names sit"
grep -n 'wohuatv\|ksj\|duer' /mnt/hy320/system/system/etc/selinux/plat_seapp_contexts | sed 's|/mnt/hy320||'
