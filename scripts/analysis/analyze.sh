#!/bin/sh
# Mount the extracted partitions read-only and collect everything ticket 09 needs.
# Read-only, noexec, nosuid, nodev throughout: nothing from the image can run.
A=${HY320_BACKUP:?set HY320_BACKUP to your own folder}/analysis
OUT=$A/inventory
mkdir -p "$OUT"

mnt() { # mnt <name> <image> [extra-options]
  mkdir -p /mnt/hy320/$1
  mountpoint -q /mnt/hy320/$1 && return 0
  mount -o ro,loop,noexec,nosuid,nodev$3 "$2" /mnt/hy320/$1 2>/dev/null \
    || echo "NOT MOUNTED: $1 ($2)"
}
mnt system  "$A/logical/system_b.img"
mnt vendor  "$A/logical/vendor_b.img"
mnt product "$A/logical/product_b.img"
mnt metadata "$A/partitions/metadata.img" ,noload
mnt oem     "$A/partitions/media_data.img"
echo "mounted:"; mount | grep /mnt/hy320 | sed 's/ type / /' | awk '{print "  "$3}'

{
  echo "######## metadata partition (update/snapshot state)"
  find /mnt/hy320/metadata -printf '%M %10s %p\n' 2>/dev/null
  echo
  echo "######## oem partition (customer files)"
  find /mnt/hy320/oem -printf '%M %10s %p\n' 2>/dev/null
  echo
  echo "######## .rc files"
  find /mnt/hy320 -name '*.rc' -printf '%10s %p\n' 2>/dev/null | sort -k2
  echo
  echo "######## service definitions and property triggers"
  find /mnt/hy320 -name '*.rc' 2>/dev/null -exec grep -Hn '^service \|^on property\|^    exec\|^exec \|^    start ' {} \;
  echo
  echo "######## shell scripts"
  find /mnt/hy320 -name '*.sh' -printf '%10s %p\n' 2>/dev/null | sort -k2
} > "$OUT/startup.txt"

find /mnt/hy320 -name '*.apk' -printf '%10s %p\n' 2>/dev/null | sort -k2 > "$OUT/apks.txt"
find /mnt/hy320 -path '*/bin/*' -type f -printf '%M %10s %p\n' 2>/dev/null | sort -k4 > "$OUT/binaries.txt"
for f in $(find /mnt/hy320 -maxdepth 3 -name 'build.prop' -o -maxdepth 3 -name '*.prop' 2>/dev/null); do
  echo "######## $f"; cat "$f"
done > "$OUT/props.txt" 2>/dev/null

for n in startup apks binaries props; do echo "$n.txt: $(wc -l < "$OUT/$n.txt") lines"; done
