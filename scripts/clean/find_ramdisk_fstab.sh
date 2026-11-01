#!/bin/sh
# Where does first-stage start-up get its mount table? Look inside vendor_boot. Read-only.
P=${HY320_BACKUP:?set HY320_BACKUP to your own folder}/analysis/partitions
T=/tmp/vb; rm -rf $T; mkdir -p $T; cd $T
python3 - "$P/vendor_boot_b.img" <<'PY'
import struct, sys, pathlib
b = pathlib.Path(sys.argv[1]).read_bytes()
assert b[:8] == b"VNDRBOOT", b[:8]
hdr_ver, page = struct.unpack_from("<II", b, 8)
ramdisk_size = struct.unpack_from("<I", b, 24)
# vendor_boot v3: magic(8) version(4) page_size(4) kernel_addr(4) ramdisk_addr(4) vendor_ramdisk_size(4)
vrs = struct.unpack_from("<I", b, 24)[0]
hdr_size = struct.unpack_from("<I", b, 24+2048+4+4+16)[0] if hdr_ver >= 3 else 0
off = (2112 + page - 1) // page * page if False else None
# The ramdisk begins at the first page boundary after the header.
start = ((0x800 + 0x4 + 0x4 + 0x10 + 0x4 + 0x4 + 0x8) + page - 1)
start = ((2112 + page - 1) // page) * page
print("header version", hdr_ver, "page size", page, "vendor ramdisk size", vrs, "ramdisk starts near", start)
pathlib.Path("/tmp/vb/ramdisk.img").write_bytes(b[start:start+vrs])
PY
echo "### ramdisk format"
head -c 6 ramdisk.img | od -An -c | tr -s ' '
file -b ramdisk.img 2>/dev/null
echo "### unpacking and looking for a mount table"
mkdir -p rd && cd rd
if head -c 2 ../ramdisk.img | od -An -tx1 | grep -q '1f 8b'; then zcat ../ramdisk.img | cpio -idm 2>/dev/null
elif head -c 4 ../ramdisk.img | grep -qa '\x04\x22\x4d\x18'; then lz4 -d -q ../ramdisk.img - 2>/dev/null | cpio -idm 2>/dev/null
else cpio -idm < ../ramdisk.img 2>/dev/null; fi
echo "--- files found:"; ls -a | head -20
echo "--- any mount table:"; find . -name 'fstab*' | head
for f in $(find . -name 'fstab*'); do echo "=== $f"; grep -E '^(system|vendor|product)' "$f" | tr -s ' '; done
