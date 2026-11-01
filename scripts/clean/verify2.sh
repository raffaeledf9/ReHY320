#!/bin/sh
# Second pass: which startup entries really have no program left, what the leftover
# vendor config files say, and zero the freed space so removed content is really gone.
C=${HY320_BACKUP:?set HY320_BACKUP to your own folder}/cleaned
M=/mnt/hy320-check
mkdir -p $M/system $M/vendor $M/product
for n in system vendor product; do
  mountpoint -q $M/$n || mount -o ro,loop,noexec,nosuid,nodev "$C/${n}_b.img" $M/$n
done

echo "######## startup entries with no program left (paths resolved correctly this time)"
{ find $M/system/system/etc/init -name '*.rc' -exec grep -h '^service ' {} \; 2>/dev/null; } \
  | awk '{print $3}' | sort -u | while read -r exe; do
  case "$exe" in
    /system/*) [ -e "$M/system$exe" ] || echo "  dangling: $exe" ;;
    /apex/*|/vendor/*) ;;
    *) echo "  (not checked) $exe" ;;
  esac
done

echo "######## leftover vendor config that still names removed apps"
echo "--- /product/etc/hideApp.ini"; head -20 $M/product/etc/hideApp.ini 2>/dev/null
echo "--- /product/etc/config.ini"; head -30 $M/product/etc/config.ini 2>/dev/null
echo "--- lmkd_whitelist lines naming removed apps: $(grep -c 'htc\|toofifi\|hotack' $M/system/system/etc/lmkd_whitelist 2>/dev/null)"

for n in system vendor product; do umount $M/$n; done

echo "######## zeroing the freed space so removed content is really gone"
command -v zerofree >/dev/null || { apt-get install -y -qq zerofree >/dev/null 2>&1; }
for n in system product; do
  if command -v zerofree >/dev/null; then
    before=$(du -b --apparent-size "$C/${n}_b.img" | cut -f1)
    zerofree -v "$C/${n}_b.img" 2>&1 | tail -1
    echo "  $n: zeroed (image stays $before bytes)"
  else
    echo "  zerofree not available; freed blocks still hold the old content"
  fi
done

echo "######## leftover strings of removed apps in the cleaned images"
for n in system product; do
  printf '  %s: ' "$n"
  c=$(grep -c -a 'com.htc.storeos' "$C/${n}_b.img" 2>/dev/null || echo 0)
  echo "occurrences of a removed package name in the raw image: $c"
done
