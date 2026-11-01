"""Pull one partition out of the compressed golden copy and verify it against the manifest.

Usage: python -I from_golden_gz.py <mmcblk0.img.gz> <manifest.json> <partition> <out file>
       python -I from_golden_gz.py --selftest
"""
import gzip, hashlib, io, json, sys
from pathlib import Path

CHUNK = 1 << 20


def region(manifest: dict, name: str) -> dict:
    hits = [r for r in manifest["regions"] if name in r["name"].split("/")]
    if len(hits) != 1:
        raise SystemExit(f"{name}: found {len(hits)} regions with that name")
    return hits[0]


def extract(stream, start: int, size: int) -> bytes:
    """Read size bytes at start from a stream that can only go forwards."""
    left = start
    while left:
        n = min(CHUNK, left)
        if len(stream.read(n)) != n:
            raise SystemExit("compressed copy ended before the region started")
        left -= n
    out = bytearray()
    while len(out) < size:
        b = stream.read(min(CHUNK, size - len(out)))
        if not b:
            raise SystemExit("compressed copy ended inside the region")
        out += b
    return bytes(out)


def selftest():
    m = {"regions": [{"name": "a", "start": 0, "size": 4}, {"name": "UDISK/userdata", "start": 4, "size": 4}]}
    assert region(m, "userdata")["start"] == 4
    try:
        region(m, "nope"); raise AssertionError("missing name accepted")
    except SystemExit:
        pass
    data = bytes(range(32))
    assert extract(io.BytesIO(data), 8, 4) == bytes(range(8, 12))
    try:
        extract(io.BytesIO(data), 30, 8); raise AssertionError("short read accepted")
    except SystemExit:
        pass
    print("selftest ok")


def main():
    if sys.argv[1:2] == ["--selftest"]:
        return selftest()
    gz, man, name, out = sys.argv[1], Path(sys.argv[2]), sys.argv[3], Path(sys.argv[4])
    r = region(json.loads(man.read_text(encoding="utf-8")), name)
    with gzip.open(gz, "rb") as f:
        data = extract(f, r["start"], r["size"])
    digest = hashlib.sha256(data).hexdigest()
    if digest != r["pc"]:
        raise SystemExit(f"{name}: extracted data does not match the manifest ({digest} vs {r['pc']})")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(data)
    print(f"{name}: {len(data)} bytes, sha256 matches the manifest, written to {out}")


if __name__ == "__main__":
    main()
