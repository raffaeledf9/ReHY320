#!/bin/sh
# Remove the two programs that wait for network connections, from a copy of the vendor
# partition, then rebuild its hash tree and its verification partition. The projector is
# not touched. Starts from the partition the projector is running now.
set -e
C=${HY320_BACKUP:?set HY320_BACKUP to your own folder}/cleaned
S=$HY320_BACKUP/signed
D=/usr/local/src/hy320-verity
AVB="python2 $D/avbtool"
SALT=2dce92049871165e758ccb37c810c3cc886ee0bd01fab5c122790c43cddd7b3a
FP='Allwinner/h713_tuna_p3/h713-tuna_p3:11/RP1A.201005.006/hotack12251645:user/release-keys'
M=/mnt/hy320-fs
mkdir -p $M

GONE="bin/dbgserver etc/init/dbgserver.rc lib/hw/sound_trigger.primary.ares.so"
KEEP="bin/hw/android.hardware.audio.service lib/hw/audio.primary.ares.so
      lib/hw/android.hardware.soundtrigger@2.0-impl.so etc/fstab.sun50iw12p1
      bin/hw/tvserver etc/init/tvserver.rc lib/hw/audio.usb.default.so bin/toybox_vendor"

echo "### copying the vendor partition the projector is running"
rm -f "$C/vendor_b-noserv.img"
cp "$C/vendor_b-avb.img" "$C/vendor_b-noserv.img"
mount -o rw,loop,noexec,nosuid,nodev "$C/vendor_b-noserv.img" $M
before=$(find $M -type f | wc -l)

echo "### the three files, before"
for f in $GONE; do
  [ -e "$M/$f" ] || { echo "  NOT THERE TO BEGIN WITH: $f"; umount $M; exit 1; }
  ls -l "$M/$f" | sed 's/^/  /'
done

echo "### removing them"
for f in $GONE; do rm -f "$M/$f"; done

echo "### checking"
fail=0
for f in $GONE; do
  if [ -e "$M/$f" ]; then echo "  STILL THERE: $f"; fail=1; else echo "  gone:  $f"; fi
done
for f in $KEEP; do
  if [ -e "$M/$f" ]; then echo "  kept:  $f"; else echo "  LOST: $f"; fail=1; fi
done
after=$(find $M -type f | wc -l)
echo "  files: $before -> $after"
[ $((before - after)) = 3 ] || { echo "  WRONG NUMBER OF FILES CHANGED"; fail=1; }
umount $M
[ $fail = 0 ] || { echo "CHECK FAILED, nothing signed"; exit 1; }

e2fsck -fn "$C/vendor_b-noserv.img" >/dev/null 2>&1 && echo "  file system clean" \
  || { echo "  FILE SYSTEM PROBLEM"; exit 1; }
command -v zerofree >/dev/null 2>&1 || apt-get install -y -qq zerofree >/dev/null 2>&1
e2fsck -fp "$C/vendor_b-noserv.img" >/dev/null 2>&1 || true
zerofree "$C/vendor_b-noserv.img" && echo "  freed blocks zeroed"

echo "### keeping the versions now on the projector, so they can be put back"
[ -f "$S/vendor_b-avb-signed.img" ] || cp "$S/vendor_b.img" "$S/vendor_b-avb-signed.img"
[ -f "$S/vbmeta_vendor-avb.img" ]   || cp "$S/vbmeta_vendor.img" "$S/vbmeta_vendor-avb.img"

echo "### signing the new vendor partition with our key"
cp "$C/vendor_b-noserv.img" "$S/vendor_b.img"
$AVB add_hashtree_footer --image "$S/vendor_b.img" --partition_name vendor \
  --partition_size 115232768 --hash_algorithm sha1 --block_size 4096 --salt "$SALT" \
  --do_not_generate_fec --algorithm SHA256_RSA2048 --key "$D/hy320_avb.pem" --rollback_index 0
[ "$(stat -c %s "$S/vendor_b.img")" = 115232768 ] || { echo "  SIZE WRONG"; exit 1; }
$AVB info_image --image "$S/vendor_b.img" | grep -E 'Image Size|Tree Size|Root Digest|Salt' | sed 's/^/  /'

echo "### rebuilding vendor's verification partition"
$AVB make_vbmeta_image --output "$S/vbmeta_vendor.img" \
  --include_descriptors_from_image "$S/vendor_b.img" \
  --prop "com.android.build.vendor.fingerprint:$FP" \
  --prop com.android.build.vendor.os_version:11 \
  --algorithm SHA256_RSA2048 --key "$D/hy320_avb.pem" \
  --rollback_index 1644019200 --flags 0 --padding_size 65536
echo "  $(stat -c %s "$S/vbmeta_vendor.img") bytes"

echo "### checking vendor against its own new tree"
L=$D/verify3; rm -rf $L; mkdir -p $L
ln -s "$S/vendor_b.img" "$L/vendor.img"
ln -s "$S/vbmeta_vendor.img" "$L/vbmeta_vendor.img"
$AVB verify_image --image "$L/vendor.img" --key "$D/hy320_avb.pub.pem" | sed 's/^/  /'
