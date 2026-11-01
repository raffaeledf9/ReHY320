#!/bin/sh
cd /tmp/vb || exit 1
rm -rf rd; mkdir rd; cd rd
lz4 -d -q ../ramdisk.img ../ramdisk.cpio 2>/dev/null && cpio -idm < ../ramdisk.cpio 2>/dev/null
echo "### top level of the ramdisk"
ls -a
echo "### any mount table inside"
find . -name 'fstab*' -o -name '*.rc' | head -20
for f in $(find . -name 'fstab*'); do
  echo "=== $f"
  grep -E '^(system|vendor|product)' "$f" | tr -s ' '
done
