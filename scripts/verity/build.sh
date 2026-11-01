#!/bin/sh
# Rebuild the verification data over the cleaned file systems, with our own key.
# Works on copies in signed/; the cleaned images stay as they are. Nothing touches the projector.
set -e
D=/usr/local/src/hy320-verity
AVB="python2 $D/avbtool"
KEY=$D/hy320_avb.pem
PUB=$D/hy320_avb.avbpubkey
C=${HY320_BACKUP:?set HY320_BACKUP to the folder holding your own dump of this projector, e.g. /mnt/d/hy320-backup}/cleaned
S=$HY320_BACKUP/signed
P=$HY320_BACKUP/analysis/partitions
FEC=${FEC:---do_not_generate_fec}
SALT=2dce92049871165e758ccb37c810c3cc886ee0bd01fab5c122790c43cddd7b3a
FP='Allwinner/h713_tuna_p3/h713-tuna_p3:11/RP1A.201005.006/hotack12251645:user/release-keys'
mkdir -p $S

# partition name : partition size (from this unit's own layout)
set -- "system:1045372928" "vendor:115232768" "product:323276800"
for spec in "$@"; do
  name=${spec%%:*}; size=${spec##*:}
  echo "######## $name: hash tree and error correction"
  cp "$C/${name}_b.img" "$S/${name}_b.img"
  $AVB add_hashtree_footer \
    --image "$S/${name}_b.img" \
    --partition_name "$name" \
    --partition_size "$size" \
    --hash_algorithm sha1 \
    --block_size 4096 \
    --salt "$SALT" \
    $FEC \
    --algorithm SHA256_RSA2048 \
    --key "$KEY" \
    --rollback_index 0
  got=$(stat -c %s "$S/${name}_b.img")
  [ "$got" = "$size" ] || { echo "  SIZE WRONG: $got, expected $size"; exit 1; }
  echo "  size $got as expected"
  $AVB info_image --image "$S/${name}_b.img" | grep -E 'Image Size|Tree Size|FEC size|Salt|Root Digest|Hash Algorithm|Block Size|Partition Name' | sed 's/^/  /'
done

echo "######## the two chained verification partitions"
$AVB make_vbmeta_image --output "$S/vbmeta_system.img" \
  --include_descriptors_from_image "$S/system_b.img" \
  --prop "com.android.build.system.fingerprint:$FP" \
  --prop com.android.build.system.os_version:11 \
  --prop com.android.build.system.security_patch:2022-02-05 \
  --algorithm SHA256_RSA2048 --key "$KEY" --rollback_index 1644019200 --flags 0 --padding_size 65536
$AVB make_vbmeta_image --output "$S/vbmeta_vendor.img" \
  --include_descriptors_from_image "$S/vendor_b.img" \
  --prop "com.android.build.vendor.fingerprint:$FP" \
  --prop com.android.build.vendor.os_version:11 \
  --algorithm SHA256_RSA2048 --key "$KEY" --rollback_index 1644019200 --flags 0 --padding_size 65536

echo "######## the top-level verification partition"
$AVB make_vbmeta_image --output "$S/vbmeta.img" \
  --include_descriptors_from_image "$P/boot_b.img" \
  --include_descriptors_from_image "$P/dtbo_b.img" \
  --include_descriptors_from_image "$P/vendor_boot_b.img" \
  --include_descriptors_from_image "$S/product_b.img" \
  --chain_partition vbmeta_system:1:"$PUB" \
  --chain_partition vbmeta_vendor:2:"$PUB" \
  --prop "com.android.build.product.fingerprint:$FP" \
  --prop com.android.build.product.os_version:11 \
  --prop com.android.build.product.security_patch:2022-02-05 \
  --prop "com.android.build.vendor_boot.fingerprint:$FP" \
  --prop "com.android.build.boot.fingerprint:$FP" \
  --prop com.android.build.boot.os_version:11 \
  --prop "com.android.build.dtbo.fingerprint:$FP" \
  --algorithm SHA256_RSA2048 --key "$KEY" --rollback_index 0 --flags 0 --padding_size 131072

for f in vbmeta vbmeta_system vbmeta_vendor; do
  echo "--- $f.img: $(stat -c %s $S/$f.img) bytes"
done
echo "######## what the top-level one now contains"
$AVB info_image --image "$S/vbmeta.img" | sed 's/^/  /'
