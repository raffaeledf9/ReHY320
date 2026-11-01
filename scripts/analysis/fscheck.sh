#!/bin/sh
# Report the file system type and state of each extracted image. Read-only.
cd ${HY320_BACKUP:?set HY320_BACKUP to your own folder}/analysis || exit 1
for p in logical/system_b.img logical/vendor_b.img logical/product_b.img \
         partitions/metadata.img partitions/media_data.img partitions/private.img; do
  echo "=== $p"
  dumpe2fs -h "$p" 2>/dev/null | grep -E 'volume name|Filesystem state|Block count|Block size:|Last mounted on|Filesystem UUID'
  od -An -tx1 -N2 -j1080 "$p" | tr -d ' \n'
  echo "  <- ext4 magic bytes at 1080 (53ef = ext4)"
done
