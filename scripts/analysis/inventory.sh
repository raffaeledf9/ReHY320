#!/bin/sh
# Mount the extracted partitions read-only and write a full file inventory.
# Read-only, noexec, nosuid, nodev: nothing from the image can run.
set -e
A=${HY320_BACKUP:?set HY320_BACKUP to the folder holding your own dump of this projector, e.g. /mnt/d/hy320-backup}/analysis
OUT=$A/inventory
mkdir -p "$OUT" /mnt/hy320
for n in system vendor product metadata; do
  case $n in
    metadata) img=$A/partitions/metadata.img ;;
    *) img=$A/logical/${n}_b.img ;;
  esac
  mkdir -p /mnt/hy320/$n
  mountpoint -q /mnt/hy320/$n || mount -o ro,loop,noexec,nosuid,nodev "$img" /mnt/hy320/$n
  find /mnt/hy320/$n -printf '%M %u %g %10s %p -> %l\n' 2>/dev/null | sed "s|/mnt/hy320/$n||" > "$OUT/$n.txt"
  echo "$n: $(wc -l < "$OUT/$n.txt") entries"
done
# Things that deserve a second look, gathered in one place.
{
  echo "## setuid / setgid files"
  find /mnt/hy320 -perm /6000 -printf '%M %u %g %10s %p\n' 2>/dev/null
  echo
  echo "## world-writable files"
  find /mnt/hy320 -perm -0002 ! -type l -printf '%M %u %g %10s %p\n' 2>/dev/null
} > "$OUT/flagged.txt"
echo "flagged: $(grep -c . "$OUT/flagged.txt") lines"
