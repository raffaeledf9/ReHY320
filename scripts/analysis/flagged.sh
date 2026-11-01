#!/bin/sh
# Second pass: metadata partition (journal not replayed) and the flagged-file scan.
A=${HY320_BACKUP:?set HY320_BACKUP to your own folder}/analysis
OUT=$A/inventory
mkdir -p "$OUT" /mnt/hy320/metadata
mountpoint -q /mnt/hy320/metadata || \
  mount -o ro,loop,noexec,nosuid,nodev,noload "$A/partitions/metadata.img" /mnt/hy320/metadata || \
  echo "metadata: not mountable, skipped"
find /mnt/hy320/metadata -printf '%M %u %g %10s %p -> %l\n' 2>/dev/null | sed 's|/mnt/hy320/metadata||' > "$OUT/metadata.txt"
echo "metadata: $(wc -l < "$OUT/metadata.txt") entries"
{
  echo "## setuid / setgid files"
  find /mnt/hy320 -perm /6000 -printf '%M %u %g %10s %p\n' 2>/dev/null
  echo
  echo "## world-writable files (not symlinks)"
  find /mnt/hy320 -perm -0002 ! -type l -printf '%M %u %g %10s %p\n' 2>/dev/null
} > "$OUT/flagged.txt"
cat "$OUT/flagged.txt"
