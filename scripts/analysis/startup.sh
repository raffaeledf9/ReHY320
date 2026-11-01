#!/bin/sh
# Report startup scripts, services and the update/snapshot state. Read-only.
OUT=${HY320_BACKUP:?set HY320_BACKUP to your own folder}/analysis/inventory
mkdir -p "$OUT"
{
  echo "######## metadata partition tree"
  find /mnt/hy320/metadata -printf '%M %10s %p\n' 2>/dev/null
  echo
  echo "######## .rc files present"
  find /mnt/hy320 -name '*.rc' -printf '%10s %p\n' 2>/dev/null | sort -k2
  echo
  echo "######## every 'service' line with its exec path"
  for f in $(find /mnt/hy320 -name '*.rc' 2>/dev/null); do
    grep -Hn '^service \|^    exec\|^exec_start\|^on property\|^    start ' "$f" 2>/dev/null
  done
  echo
  echo "######## .sh scripts outside bin"
  find /mnt/hy320 -name '*.sh' -printf '%10s %p\n' 2>/dev/null | sort -k2
} > "$OUT/startup.txt"
wc -l < "$OUT/startup.txt"
sed -n '1,40p' "$OUT/startup.txt"
