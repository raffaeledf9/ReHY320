#!/bin/sh
# Read the small vendor scripts, what triggers them, and clues from the qw binary. Read-only.
OUT=${HY320_BACKUP:?set HY320_BACKUP to your own folder}/analysis/inventory
S=/mnt/hy320/system/system
{
  for f in preinstall appsdisable gmsopt; do
    echo "######## /system/bin/$f"; cat "$S/bin/$f" 2>/dev/null; echo
  done
  echo "######## does iosmain exist?"; ls -l "$S/bin/iosmain" 2>&1
  echo
  echo "######## what starts replace_file / netflix_copy / qw"
  grep -rn 'replace_file\|netflix_copy\|replace_start\|start qw\|disable qw' $S/etc/init /mnt/hy320/vendor/etc/init 2>/dev/null | sed 's|/mnt/hy320||'
  echo
  echo "######## services defined in system, full list"
  grep -rh '^service ' $S/etc/init 2>/dev/null | sort
  echo
  echo "######## printable strings in /system/bin/qw that look like ports, paths or hosts"
  strings -n 5 "$S/bin/qw" 2>/dev/null | grep -niE 'socket|port|listen|bind|[0-9]{4,5}$|/data/|/system/|su$|superuser|magisk|http|\.com|\.cn' | head -40
  echo
  echo "######## qw file type"
  head -c 64 "$S/bin/qw" | od -An -c | head -2
} > "$OUT/suspects2.txt"
cat "$OUT/suspects2.txt"
