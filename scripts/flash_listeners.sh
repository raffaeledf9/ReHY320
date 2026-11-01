#!/bin/bash
# Write the vendor change that removes the two network listeners, and check it.
#   preflight  - in Android: confirm identity and that the projector holds what we expect
#   flash      - in fastboot: write the container and vendor's verification partition
#   verify     - in Android: read both back, confirm the files and the ports are gone
# Nothing is written except by "flash".
set -u
# The projector. Set ANDROID_SERIAL, or let it take the only device attached.
SERIAL="${ANDROID_SERIAL:-$(adb devices | awk 'NR==2{print $1}')}"
S=${HY320_BACKUP:?set HY320_BACKUP to the folder holding your own dump of this projector, e.g. /mnt/d/hy320-backup}/signed
SUPER_OFF_BLK=585        # 585 * 512K = 306,708,480
SUPER_CNT=4096           # 4096 * 512K = 2 GB
VBV_OFF_BLK=37711       # 37711 * 64K = 2,471,428,096 (slot B, the live one)
GONE="/vendor/bin/dbgserver /vendor/etc/init/dbgserver.rc /vendor/lib/hw/sound_trigger.primary.ares.so"

dev_hash_super() { adb -s $SERIAL shell "dd if=/dev/block/mmcblk0 bs=524288 skip=$SUPER_OFF_BLK count=$SUPER_CNT 2>/dev/null | sha256sum" | cut -d' ' -f1; }
dev_hash_vbv()   { adb -s $SERIAL shell "dd if=/dev/block/mmcblk0 bs=65536 skip=$VBV_OFF_BLK count=1 2>/dev/null | sha256sum" | cut -d' ' -f1; }
pc_hash()        { sha256sum "$1" | cut -d' ' -f1; }
say()            { printf '%-46s %s\n' "$1" "$2"; }

case "${1:-}" in

preflight)
  echo "### identity"
  adb -s $SERIAL get-state >/dev/null 2>&1 || { echo "  the projector is not in Android over USB"; exit 1; }
  say "serial" "$(adb -s $SERIAL shell getprop ro.serialno | tr -d '\r')"
  say "build"  "$(adb -s $SERIAL shell getprop ro.build.version.incremental | tr -d '\r')"
  [ "$(adb -s $SERIAL shell getprop ro.serialno | tr -d '\r')" = "$SERIAL" ] || { echo "  SERIAL MISMATCH"; exit 1; }
  echo "### the three files are still there (so we are removing from the expected state)"
  for f in $GONE; do
    adb -s $SERIAL shell "[ -e $f ] && echo present || echo MISSING" | tr -d '\r' | while read -r r; do say "  $f" "$r"; done
  done
  echo "### the chip-maker's service is still listening"
  adb -s $SERIAL shell 'grep -q ":FFF8 " /proc/net/tcp && echo "  port 65528 listening" || echo "  port 65528 NOT listening"' | tr -d '\r'
  echo "### what the projector is running now (about two minutes)"
  want=$(pc_hash "$S/super-avb.img"); got=$(dev_hash_super)
  say "  container on the projector" "$got"
  say "  super-avb.img on the PC" "$want"
  [ "$got" = "$want" ] && echo "  MATCH: the projector holds the container we last wrote" \
                       || { echo "  NO MATCH - stop and work out why before writing"; exit 1; }
  echo "### what will be written"
  say "  super-noserv.img" "$(pc_hash "$S/super-noserv.img")"
  say "  vbmeta_vendor.img" "$(pc_hash "$S/vbmeta_vendor.img")"
  ;;

flash)
  echo "### fastboot"
  fastboot devices | tr -d '\r' | sed 's/^/  /'
  fastboot devices | grep -q "$SERIAL" || { echo "  the projector is not in fastboot"; exit 1; }
  for f in super-noserv.img vbmeta_vendor.img; do [ -f "$S/$f" ] || { echo "  missing $f"; exit 1; }; done
  echo "### writing the container (about twenty minutes)"
  fastboot flash super "$S/super-noserv.img" || { echo "  WRITE FAILED"; exit 1; }
  echo "### writing vendor's verification partition"
  fastboot flash vbmeta_vendor "$S/vbmeta_vendor.img" || { echo "  WRITE FAILED"; exit 1; }
  echo "### restarting"
  fastboot reboot
  ;;

verify)
  echo "### reading the container back (about two minutes)"
  want=$(pc_hash "$S/super-noserv.img"); got=$(dev_hash_super)
  say "  read from the projector" "$got"
  say "  written from the PC" "$want"
  [ "$got" = "$want" ] && echo "  CONTAINER MATCHES" || echo "  CONTAINER DOES NOT MATCH"
  echo "### reading vendor's verification partition back"
  wantv=$(pc_hash "$S/vbmeta_vendor.img"); gotv=$(dev_hash_vbv)
  say "  read from the projector" "$gotv"
  say "  written from the PC" "$wantv"
  [ "$gotv" = "$wantv" ] && echo "  VERIFICATION PARTITION MATCHES" || echo "  DOES NOT MATCH"
  echo "### the three files"
  for f in $GONE; do
    adb -s $SERIAL shell "[ -e $f ] && echo STILL THERE || echo gone" | tr -d '\r' | while read -r r; do say "  $f" "$r"; done
  done
  echo "### what is listening now"
  adb -s $SERIAL shell 'cat /proc/net/tcp; echo ---; cat /proc/net/tcp6' | tr -d '\r' | sed 's/^/  /'
  echo "### audio is alive"
  adb -s $SERIAL shell 'ps -A -o USER,PID,NAME | grep -E "audioserver|audio.service"' | tr -d '\r' | sed 's/^/  /'
  say "  audio devices" "$(adb -s $SERIAL shell 'dumpsys audio 2>/dev/null | grep -c .' | tr -d '\r') lines of audio state"
  echo "### anything crashed since the restart"
  adb -s $SERIAL shell 'ls -l /data/tombstones/ 2>/dev/null | tail -3' | tr -d '\r' | sed 's/^/  /'
  adb -s $SERIAL shell 'logcat -d -b crash 2>/dev/null | tail -5' | tr -d '\r' | sed 's/^/  /'
  ;;

*) echo "usage: $0 preflight|flash|verify"; exit 2 ;;
esac
