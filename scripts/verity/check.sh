#!/bin/sh
# Check the rebuilt verification data: each partition against its own tree, and the
# chain from the top-level partition down to the other two. Read-only.
D=/usr/local/src/hy320-verity
AVB="python2 $D/avbtool"
PUB=$D/hy320_avb.pub.pem
S=${HY320_BACKUP:?set HY320_BACKUP to the folder holding your own dump of this projector, e.g. /mnt/d/hy320-backup}/signed
fail=0

for n in system vendor product; do
  echo "######## $n: does the image match its own hash tree, and is it signed with our key?"
  if $AVB verify_image --image "$S/${n}_b.img" --key "$PUB" 2>&1 | sed 's/^/  /'; then :; else fail=1; fi
done

echo "######## the chain from the top-level partition"
$AVB verify_image --image "$S/vbmeta.img" --key "$PUB" 2>&1 | sed 's/^/  /' || fail=1

echo "######## what each chained partition carries"
for f in vbmeta_system vbmeta_vendor; do
  echo "--- $f"
  $AVB info_image --image "$S/$f.img" | grep -E 'Partition Name|Root Digest|Rollback|Release|Public key|Flags' | sed 's/^/  /'
done

echo "######## the chains and properties in the top-level partition"
$AVB info_image --image "$S/vbmeta.img" | grep -E 'Partition Name|Rollback Index Location|Hash Algorithm|Digest|Key|Prop' | sed 's/^/  /'

[ "$fail" = 0 ] && echo "ALL CHECKS PASSED" || echo "SOMETHING FAILED"
