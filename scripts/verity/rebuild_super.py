"""Write the signed partitions back into a copy of the container, at their own extents.

The container's layout is not changed: each logical partition keeps exactly the extents
the device already uses, so only their contents differ. The original container is never
modified, and the result is checked by reading the extents back out.

Usage: python -I rebuild_super.py <super.img> <signed dir> <out super.img>
       python -I rebuild_super.py --selftest
"""
import hashlib, struct, sys
from pathlib import Path

GEOMETRY_OFFSET = 4096
GEOMETRY_MAGIC = 0x616C4467
HEADER_MAGIC = 0x414C5030
SECTOR = 512
CHUNK = 1 << 20
SLOT = 1                      # metadata copy 1 is the live one on this unit
WANTED = {"system_b": "system_b.img", "vendor_b": "vendor_b.img", "product_b": "product_b.img"}


def read_metadata(f):
    f.seek(GEOMETRY_OFFSET)
    geo = f.read(4096)
    if struct.unpack_from("<I", geo, 0)[0] != GEOMETRY_MAGIC:
        raise SystemExit("not a container image")
    max_size = struct.unpack_from("<I", geo, 40)[0]
    base = GEOMETRY_OFFSET + 2 * 4096 + SLOT * max_size
    f.seek(base)
    head = f.read(256)
    if struct.unpack_from("<I", head, 0)[0] != HEADER_MAGIC:
        raise SystemExit(f"no metadata in copy {SLOT}")
    header_size = struct.unpack_from("<I", head, 8)[0]
    tables_size = struct.unpack_from("<I", head, 44)[0]
    desc = [struct.unpack_from("<III", head, 80 + 12 * i) for i in range(4)]
    f.seek(base + header_size)
    tables = f.read(tables_size)

    def rows(i, entry_size):
        offset, count, entry = desc[i]
        if entry != entry_size:
            raise SystemExit(f"unexpected entry size {entry} in table {i}")
        return [tables[offset + entry * n: offset + entry * (n + 1)] for n in range(count)]

    parts = []
    for raw in rows(0, 52):
        name = raw[:36].split(b"\0")[0].decode()
        _, first, num, _ = struct.unpack_from("<IIII", raw, 36)
        parts.append((name, first, num))
    extents = []
    for raw in rows(1, 24):
        num_sectors, target_type, target_data, _ = struct.unpack("<QIQI", raw)
        extents.append((num_sectors, target_type, target_data))
    return parts, extents


def extents_of(name, parts, extents):
    for pname, first, num in parts:
        if pname == name:
            out = []
            for num_sectors, target_type, target_sector in extents[first:first + num]:
                if target_type != 0:
                    raise SystemExit(f"{name}: non-linear extent")
                out.append((target_sector * SECTOR, num_sectors * SECTOR))
            return out
    raise SystemExit(f"{name}: not in the container metadata")


def selftest():
    parts = [("system_b", 0, 2), ("vendor_b", 2, 1)]
    extents = [(2, 0, 10), (4, 0, 20), (8, 0, 40)]
    assert extents_of("system_b", parts, extents) == [(5120, 1024), (10240, 2048)]
    assert extents_of("vendor_b", parts, extents) == [(20480, 4096)]
    try:
        extents_of("nope", parts, extents); raise AssertionError("missing name accepted")
    except SystemExit:
        pass
    try:
        extents_of("system_b", [("system_b", 0, 1)], [(2, 1, 10)]); raise AssertionError("non-linear accepted")
    except SystemExit:
        pass
    print("selftest ok")


def main():
    if sys.argv[1:2] == ["--selftest"]:
        return selftest()
    src, signed, out = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
    if out.exists():
        raise SystemExit(f"{out} exists already; refusing to overwrite")
    with open(src, "rb") as f:
        parts, extents = read_metadata(f)
    print(f"copying the container ({src.stat().st_size:,} bytes)", flush=True)
    with open(src, "rb") as a, open(out, "wb") as b:
        while chunk := a.read(CHUNK):
            b.write(chunk)

    for name, filename in WANTED.items():
        img = signed / filename
        regions = extents_of(name, parts, extents)
        total = sum(size for _, size in regions)
        if img.stat().st_size != total:
            raise SystemExit(f"{name}: image is {img.stat().st_size:,} bytes but its extents hold {total:,}")
        print(f"{name}: writing {total:,} bytes over {len(regions)} extent(s)", flush=True)
        with open(img, "rb") as s, open(out, "r+b") as d:
            for offset, size in regions:
                d.seek(offset)
                left = size
                while left:
                    buf = s.read(min(CHUNK, left))
                    d.write(buf)
                    left -= len(buf)

    print("reading the extents back out to check", flush=True)
    for name, filename in WANTED.items():
        want = hashlib.sha256((signed / filename).read_bytes()).hexdigest()
        got = hashlib.sha256()
        with open(out, "rb") as d:
            for offset, size in extents_of(name, parts, extents):
                d.seek(offset)
                left = size
                while left:
                    buf = d.read(min(CHUNK, left))
                    got.update(buf)
                    left -= len(buf)
        print(f"  {name}: {'matches' if got.hexdigest() == want else 'DOES NOT MATCH'}")
        if got.hexdigest() != want:
            raise SystemExit("the rebuilt container does not read back correctly")
    print(f"done: {out} ({out.stat().st_size:,} bytes)")


if __name__ == "__main__":
    main()
