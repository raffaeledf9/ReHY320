#!/bin/sh
# Check the cleaned images: what is gone, what survived, what still mentions the removals.
# Read-only on the cleaned copies.
C=${HY320_BACKUP:?set HY320_BACKUP to the folder holding your own dump of this projector, e.g. /mnt/d/hy320-backup}/cleaned
M=/mnt/hy320-check
mkdir -p $M/system $M/vendor $M/product
for n in system vendor product; do
  mountpoint -q $M/$n || mount -o ro,loop,noexec,nosuid,nodev "$C/${n}_b.img" $M/$n || echo "NOT MOUNTED: $n"
done

echo "######## must be gone"
for p in system/bin/qw system/bin/preinstall system/bin/appsdisable system/bin/gmsopt \
         system/etc/init/qw.rc system/app/StoreOS system/app/EventUploadService-V1 \
         system/app/HTCLauncherEN_QZ-V1 system/app/TengYunH713TVApp_HY; do
  [ -e "$M/system/$p" ] && echo "  STILL THERE: /system/$p" || echo "  gone: /system/$p"
done
for p in app/HtcOtaUpdate_QZ-V1 app/SN_and_MAC app/HtcOfficeSuite app/HYK_TEST_T08-V2; do
  [ -e "$M/product/$p" ] && echo "  STILL THERE: /product/$p" || echo "  gone: /product/$p"
done

echo "######## must have survived"
for p in system/app/AwLiveTv system/app/AwSource system/priv-app/VideoInputService \
         system/bin/multi_ir system/app/NFXAccessibility_1.0.63 system/priv-app/PlayStoreTv \
         system/system_ext/priv-app/SystemUI system/bin/surfaceflinger system/lib/libkeystone.so; do
  [ -e "$M/system/$p" ] && echo "  kept: /system/$p" || echo "  MISSING: /system/$p"
done
for p in app/HotackSettingsT08_QZ app/CloseDialog_L010 app/webview; do
  [ -e "$M/product/$p" ] && echo "  kept: /product/$p" || echo "  MISSING: /product/$p"
done

echo "######## the two edits"
grep -n 'mmcblk0 ' $M/vendor/ueventd.rc | head -3
echo "  pre-authorised app names left in the policy: $(grep -c 'wohuatv\|ksj\|duer' $M/system/system/etc/selinux/plat_seapp_contexts 2>/dev/null)"

echo "######## startup entries whose program is now gone (harmless, but listed)"
for f in $(find $M/system/system/etc/init -name '*.rc' 2>/dev/null); do
  grep -h '^service ' "$f" 2>/dev/null
done | awk '{print $3}' | sort -u | while read -r exe; do
  case "$exe" in /system/*) [ -e "$M/system${exe#/system}" ] || echo "  missing program: $exe";; esac
done
grep -h '^service ' $M/system/system/etc/init/hw/init.rc | awk '{print $3}' | sort -u | while read -r exe; do
  case "$exe" in /system/*) [ -e "$M/system${exe#/system}" ] || echo "  missing program (init.rc): $exe";; esac
done

echo "######## anything still naming a removed app"
for name in com.htc.storeos com.htc.eventuploadservice com.htc.htcotaupdate com.hotack.writesn \
            com.android.toofifi com.htc.samescreen com.htc.htclauncherhighenglishd08; do
  hits=$(grep -rl "$name" $M/system/system/etc $M/product/etc 2>/dev/null | head -4 | tr '\n' ' ')
  [ -n "$hits" ] && echo "  $name still named in: $hits"
done

echo "######## free space in each cleaned image"
df -h $M/system $M/vendor $M/product 2>/dev/null | tail -n +2
for n in system vendor product; do umount $M/$n 2>/dev/null; done
