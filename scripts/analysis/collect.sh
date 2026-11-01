#!/bin/sh
# Copy the non-AOSP apps out for inspection and search for the keystone implementation.
# Read-only on the images; copies land under the analysis folder.
A=${HY320_BACKUP:?set HY320_BACKUP to your own folder}/analysis
OUT=$A/inventory
APKS=$A/apks
mkdir -p "$APKS"

# Apps whose path does not look like stock Android.
find /mnt/hy320 -name '*.apk' 2>/dev/null | grep -viE '/apex/|/(system|product)/(app|priv-app|framework)/[A-Z][A-Za-z]*/\1' > /tmp/all_apks
: > "$OUT/apk_copy.log"
while read -r p; do
  case "$p" in
    */Aw*|*/Htc*|*/HTC*|*/Hotack*|*/HYK*|*/StoreOS*|*/EventUpload*|*/Ft*|*/iOS*|*/USBCast*|*/ScreenCast*|*/Screen*|*/Miracast*|*/Tvd*|*/Dragon*|*/ImageParser*|*/Update*|*/CloseDialog*|*/SN_and_MAC*|*/PackageOverride*|*/Settings*|*/Video*|*/Package*)
      cp -n "$p" "$APKS/$(basename "$(dirname "$p")")__$(basename "$p")" && echo "copied $p" >> "$OUT/apk_copy.log" ;;
  esac
done < /tmp/all_apks
echo "apks copied: $(ls -1 "$APKS" | wc -l)"

{
  echo "######## files whose name mentions keystone, warp, trapezoid, projector or gsensor"
  find /mnt/hy320 -iname '*keystone*' -o -iname '*warp*' -o -iname '*trapez*' -o -iname '*projector*' -o -iname '*gsensor*' -o -iname '*prj*' 2>/dev/null | sed 's|/mnt/hy320||'
  echo
  echo "######## libraries and binaries containing the word keystone"
  for f in $(find /mnt/hy320/system/system/lib /mnt/hy320/system/system/bin /mnt/hy320/vendor/lib /mnt/hy320/vendor/bin -type f 2>/dev/null); do
    if strings -n 6 "$f" 2>/dev/null | grep -qiE 'keystone|trapez'; then echo "$f"; fi
  done | sed 's|/mnt/hy320||'
  echo
  echo "######## keystone-ish properties in the prop files"
  grep -rhiE 'keystone|trapez|hotack|prj|sensor' /mnt/hy320/*/build.prop /mnt/hy320/system/system/build.prop /mnt/hy320/vendor/build.prop /mnt/hy320/product/build.prop 2>/dev/null | sort -u
  echo
  echo "######## sysfs paths mentioned in init scripts (display, fan, keystone)"
  grep -rhoE '/sys/[A-Za-z0-9_./*-]+' /mnt/hy320/system/system/etc/init /mnt/hy320/vendor/etc/init 2>/dev/null | sort -u
} > "$OUT/keystone.txt"
wc -l < "$OUT/keystone.txt"
cat "$OUT/keystone.txt"
