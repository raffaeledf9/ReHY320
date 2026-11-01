#!/bin/sh
# Which program listens on these ports? Search the cleaned images. Read-only.
C=${HY320_BACKUP:?set HY320_BACKUP to the folder holding your own dump of this projector, e.g. /mnt/d/hy320-backup}/cleaned
M=/mnt/hy320-p; mkdir -p $M/system $M/vendor
for n in system vendor; do
  mountpoint -q $M/$n || mount -o ro,loop,noexec,nosuid,nodev "$C/${n}_b.img" $M/$n
done
for port in 65528 14035 0xfff8 0x36d3; do
  echo "### anything mentioning $port"
  grep -rl "$port" $M/system/system/bin $M/system/system/lib $M/vendor/bin $M/vendor/lib 2>/dev/null | head -6 | sed "s|$M||"
done
echo "### socket and bind strings in the root-owned vendor services"
for b in $M/system/system/bin/systemmixservice $M/system/system/bin/isomountservice $M/system/system/bin/gpioservice $M/vendor/bin/dbgserver $M/vendor/bin/dom2reg; do
  [ -f "$b" ] || continue
  echo "--- $(basename $b) ($(stat -c %s "$b") bytes, $(file -b "$b" 2>/dev/null | cut -c1-40))"
  strings -a "$b" 2>/dev/null | grep -iE "^[0-9]{4,5}$|bind|listen|socket|port|tcp|server" | sort -u | head -8
done
for n in system vendor; do umount $M/$n; done
