"""List and extract the logical partitions inside an Android 'super' image (read-only).

Usage: python -I parse_super.py <super.img> [out-dir] [--slot N]
       python -I parse_super.py --selftest
Without out-dir it only lists. Metadata slot N is 0 for A, 1 for B. Nothing is ever written to the input.
"""
import json, struct, sys
from pathlib import Path

GEOMETRY_OFFSET = 4096
GEOMETRY_MAGIC = 0x616C4467
HEADER_MAGIC = 0x414C5030
SECTOR = 512
CHUNK = 1 << 20


def read_geometry(buf):
    magic, struct_size = struct.unpack_from("<II", buf, 0)
    if magic != GEOMETRY_MAGIC:
        raise SystemExit(f"Not LP geometry: magic {magic:#x}")
    max_size, slot_count, block_size = struct.unpack_from("<III", buf, 4 + 4 + 32)
    return {"struct_size": struct_size, "metadata_max_size": max_size,
            "metadata_slot_count": slot_count, "logical_block_size": block_size}


def read_metadata(f, geom, slot=0):
    base = GEOMETRY_OFFSET + 2 * 4096 + slot * geom["metadata_max_size"]
    f.seek(base)
    head = f.read(256)
    if struct.unpack_from("<I", head, 0)[0] != HEADER_MAGIC:
        raise SystemExit(f"No LP metadata header in slot {slot}")
    header_size = struct.unpack_from("<I", head, 4 + 2 + 2)[0]
    off = 4 + 2 + 2 + 4 + 32 + 4 + 32          # start of the four table descriptors
    desc = [struct.unpack_from("<III", head, off + 12 * i) for i in range(4)]
    f.seek(base + header_size)
    tables = f.read(struct.unpack_from("<I", head, 4 + 2 + 2 + 4 + 32)[0])

    def rows(i, size_check):
        offset, count, entry = desc[i]
        if entry != size_check:
            raise SystemExit(f"Unexpected entry size {entry} for table {i}")
        return [tables[offset + entry * n: offset + entry * (n + 1)] for n in range(count)]

    parts = []
    for raw in rows(0, 52):
        name = raw[:36].split(b"\0")[0].decode()
        attributes, first_extent, num_extents, group = struct.unpack_from("<IIII", raw, 36)
        parts.append({"name": name, "attributes": attributes,
                      "first_extent": first_extent, "num_extents": num_extents, "group": group})
    extents = []
    for raw in rows(1, 24):
        num_sectors, target_type, target_data, target_source = struct.unpack("<QIQI", raw)
        extents.append({"num_sectors": num_sectors, "type": target_type,
                        "target_sector": target_data, "source": target_source})
    devices = []
    for raw in rows(3, 64):
        first_logical_sector, alignment, alignment_offset, size = struct.unpack_from("<QIIQ", raw)
        devices.append({"name": raw[24:60].split(b"\0")[0].decode(),
                        "first_logical_sector": first_logical_sector, "size": size})
    return parts, extents, devices


def partition_extents(p, extents):
    return extents[p["first_extent"]: p["first_extent"] + p["num_extents"]]


def check(parts, extents, super_size):
    for p in parts:
        for e in partition_extents(p, extents):
            if e["type"] != 0:
                raise SystemExit(f"{p['name']}: non-linear extent, cannot extract")
            end = (e["target_sector"] + e["num_sectors"]) * SECTOR
            if end > super_size:
                raise SystemExit(f"{p['name']}: extent ends at {end}, past super size {super_size}")


def selftest():
    geom = read_geometry(struct.pack("<II", GEOMETRY_MAGIC, 52) + b"\0" * 32 + struct.pack("<III", 65536, 2, 4096))
    assert geom["metadata_max_size"] == 65536 and geom["logical_block_size"] == 4096
    try:
        read_geometry(b"\0" * 64); raise AssertionError("bad magic accepted")
    except SystemExit:
        pass
    parts = [{"name": "x", "first_extent": 1, "num_extents": 1}]
    ext = [{"num_sectors": 2, "type": 0, "target_sector": 0, "source": 0},
           {"num_sectors": 2, "type": 0, "target_sector": 10, "source": 0}]
    assert partition_extents(parts[0], ext) == [ext[1]]
    check(parts, ext, 12 * SECTOR)
    try:
        check(parts, ext, 8 * SECTOR); raise AssertionError("out-of-range extent accepted")
    except SystemExit:
        pass
    print("selftest ok")


def main():
    if sys.argv[1:2] == ["--selftest"]:
        return selftest()
    args = sys.argv[1:]
    slot = 0
    if "--slot" in args:
        i = args.index("--slot")
        slot = int(args[i + 1]); del args[i:i + 2]
    img = Path(args[0])
    outdir = Path(args[1]) if len(args) > 1 else None
    size = img.stat().st_size
    with open(img, "rb") as f:
        f.seek(GEOMETRY_OFFSET)
        geom = read_geometry(f.read(4096))
        if slot >= geom["metadata_slot_count"]:
            raise SystemExit(f"Slot {slot} beyond slot count {geom['metadata_slot_count']}")
        parts, extents, devices = read_metadata(f, geom, slot)
        check(parts, extents, size)
        print(json.dumps({"geometry": geom, "block_devices": devices}, indent=1))
        if outdir:
            outdir.mkdir(parents=True, exist_ok=True)
        for p in parts:
            total = sum(e["num_sectors"] for e in partition_extents(p, extents)) * SECTOR
            print(f"{p['name']:20} {total:>12}  extents={p['num_extents']} attr={p['attributes']}")
            if not outdir:
                continue
            with open(outdir / f"{p['name']}.img", "wb") as o:
                for e in partition_extents(p, extents):
                    f.seek(e["target_sector"] * SECTOR)
                    left = e["num_sectors"] * SECTOR
                    while left:
                        b = f.read(min(CHUNK, left))
                        o.write(b); left -= len(b)


if __name__ == "__main__":
    main()
