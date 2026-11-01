#!/bin/sh
# Rebuild only the top-level verification partition, without duplicating the properties
# that the boot images already carry in their own footers. Also export a PEM public key,
# which is what the verify command expects.
set -e
D=/usr/local/src/hy320-verity
AVB="python2 $D/avbtool"
KEY=$D/hy320_avb.pem
PUB=$D/hy320_avb.avbpubkey
S=${HY320_BACKUP:?set HY320_BACKUP to the folder holding your own dump of this projector, e.g. /mnt/d/hy320-backup}/signed
P=$HY320_BACKUP/analysis/partitions
FP='Allwinner/h713_tuna_p3/h713-tuna_p3:11/RP1A.201005.006/hotack12251645:user/release-keys'

[ -f $D/hy320_avb.pub.pem ] || openssl rsa -in "$KEY" -pubout -out $D/hy320_avb.pub.pem 2>/dev/null
echo "### public key in PEM form: $(stat -c %s $D/hy320_avb.pub.pem) bytes"

# Only product's properties are passed here: boot, dtbo and vendor_boot carry their own.
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
  --algorithm SHA256_RSA2048 --key "$KEY" --rollback_index 0 --flags 0 --padding_size 131072

echo "### size: $(stat -c %s $S/vbmeta.img) bytes"
echo "### descriptors and properties, each should appear once"
$AVB info_image --image "$S/vbmeta.img" | grep -E 'descriptor|Partition Name|Prop:|Rollback Index Location' | sed 's/^/  /'
echo "### property count: $($AVB info_image --image "$S/vbmeta.img" | grep -c 'Prop:') (the original had 7)"
