#!/bin/sh
# The real check: recompute each hash tree from the image content and compare, and follow
# the chain from the top-level partition. Read-only.
#
# The tool looks for sibling images named <partition>.img, so a directory of links with
# those names is set up first. Exit status is tracked properly this time, with no pipes
# swallowing it.
D=/usr/local/src/hy320-verity
AVB="python2 $D/avbtool"
PUB=$D/hy320_avb.pub.pem
S=${HY320_BACKUP:?set HY320_BACKUP to the folder holding your own dump of this projector, e.g. /mnt/d/hy320-backup}/signed
P=$HY320_BACKUP/analysis/partitions
L=$D/verify
rm -rf $L; mkdir -p $L
for n in system vendor product; do ln -s "$S/${n}_b.img" "$L/${n}.img"; done
for n in boot dtbo vendor_boot; do ln -s "$P/${n}_b.img" "$L/${n}.img"; done
for f in vbmeta vbmeta_system vbmeta_vendor; do ln -s "$S/$f.img" "$L/$f.img"; done

fail=0
for n in system vendor product; do
  echo "######## $n: recomputing the tree from the content"
  out=$($AVB verify_image --image "$L/$n.img" --key "$PUB" 2>&1); rc=$?
  echo "$out" | sed 's/^/  /'
  [ $rc -eq 0 ] || fail=1
done

echo "######## the whole chain from the top-level partition"
out=$($AVB verify_image --image "$L/vbmeta.img" --key "$PUB" --follow_chain_partitions 2>&1); rc=$?
echo "$out" | sed 's/^/  /'
[ $rc -eq 0 ] || fail=1

if [ $fail -eq 0 ]; then echo "RESULT: every tree recomputed and matched, and the chain verified"
else echo "RESULT: at least one check failed (see above)"; fi
exit $fail
