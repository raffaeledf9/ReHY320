#!/bin/sh
# Copy the apps that hide behind stock-looking names, and pull keystone clues. Read-only.
A=${HY320_BACKUP:?set HY320_BACKUP to your own folder}/analysis
OUT=$A/inventory
APKS=$A/apks
mkdir -p "$APKS" /tmp/dex

for p in /mnt/hy320/system/system/app/TengYunH713TVApp_HY/TengYunH713TVApp_HY.apk \
         /mnt/hy320/system/system/app/NFXAccessibility_1.0.63/NFXAccessibility_1.0.63.apk \
         /mnt/hy320/system/system/app/RKMusic/RKMusic.apk \
         /mnt/hy320/system/system/priv-app/PlayStoreTv/PlayStoreTv.apk; do
  [ -f "$p" ] && cp -n "$p" "$APKS/$(basename "$(dirname "$p")")__$(basename "$p")"
done
echo "apks now: $(ls -1 "$APKS" | wc -l)"

{
  echo "######## libkeystone.so: exported names and settings it reads"
  strings -n 4 /mnt/hy320/system/system/lib/libkeystone.so 2>/dev/null \
    | grep -iE 'keystone|trapez|corner|warp|persist\.|hotack|sys\.|vertex|quad|homograph|setKeystone|getKeystone|\.ini|/data/|/oem/' | sort -u
  echo
  echo "######## libsurfaceflinger.so: keystone-related names"
  strings -n 4 /mnt/hy320/system/system/lib/libsurfaceflinger.so 2>/dev/null \
    | grep -iE 'keystone|trapez|corner|warp' | sort -u
  echo
  echo "######## camprjspe.ini (projection config)"
  head -c 2000 /mnt/hy320/system/system/camprjspe.ini 2>/dev/null
  echo
  echo "######## which apps mention keystone, anti_shake, motor or the gsensor"
  for apk in /mnt/hy320/system/system/app/*/*.apk /mnt/hy320/system/system/priv-app/*/*.apk /mnt/hy320/product/app/*/*.apk; do
    rm -rf /tmp/dex/*; unzip -o -q -d /tmp/dex "$apk" 'classes*.dex' 2>/dev/null || continue
    hits=$(cat /tmp/dex/*.dex 2>/dev/null | strings -n 5 | grep -ioE 'keystone[A-Za-z]*|anti_shake|motor_ctrl|gsensor_data|setKeystone|KeystoneManager|trapez[A-Za-z]*' | sort -u | tr '\n' ' ')
    [ -n "$hits" ] && echo "$(basename "$apk"): $hits"
  done
} > "$OUT/keystone2.txt" 2>/dev/null
cat "$OUT/keystone2.txt"
