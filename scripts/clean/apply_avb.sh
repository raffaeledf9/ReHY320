#!/bin/sh
# Turn runtime verification on: edit the vendor mount table, then rebuild vendor's hash
# tree and its verification partition. Works on copies; the projector is not touched.
set -e
C=${HY320_BACKUP:?set HY320_BACKUP to your own folder}/cleaned
S=$HY320_BACKUP/signed
D=/usr/local/src/hy320-verity
R=$(cd "$(dirname "$0")/../.." && pwd)   # this repository, wherever it was cloned
AVB="python2 $D/avbtool"
SALT=2dce92049871165e758ccb37c810c3cc886ee0bd01fab5c122790c43cddd7b3a
FP='Allwinner/h713_tuna_p3/h713-tuna_p3:11/RP1A.201005.006/hotack12251645:user/release-keys'
M=/mnt/hy320-fs
mkdir -p $M

echo "### editing the mount table in a copy of the cleaned vendor partition"
cp "$C/vendor_b.img" "$C/vendor_b-avb.img"
mount -o rw,loop,noexec,nosuid,nodev "$C/vendor_b-avb.img" $M
python3 -I "$R/scripts/clean/enable_avb.py" \
  $M/etc/fstab.sun50iw12p1
umount $M
e2fsck -fn "$C/vendor_b-avb.img" >/dev/null 2>&1 && echo "  file system still clean" || { echo "  FILE SYSTEM PROBLEM"; exit 1; }

echo "### rebuilding vendor's hash tree with our key"
cp "$C/vendor_b-avb.img" "$S/vendor_b.img"
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
L=$D/verify2; rm -rf $L; mkdir -p $L
ln -s "$S/vendor_b.img" "$L/vendor.img"
ln -s "$S/vbmeta_vendor.img" "$L/vbmeta_vendor.img"
$AVB verify_image --image "$L/vendor.img" --key "$D/hy320_avb.pub.pem" | sed 's/^/  /'
