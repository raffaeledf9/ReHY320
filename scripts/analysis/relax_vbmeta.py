"""Produce a copy of the verification partition with its two check flags set.

Everything else in the image is left byte for byte as it was, so the change is
exactly four bytes. The original is written out alongside for the undo.

Usage: python -I relax_vbmeta.py <vbmeta.img> <out-dir>
       python -I relax_vbmeta.py --selftest
"""
import hashlib, struct, sys
from pathlib import Path

FLAGS_OFFSET = 120          # in the packed, big-endian vbmeta header
HASHTREE_DISABLED = 1
VERIFICATION_DISABLED = 2


def set_flags(img: bytes, flags: int) -> bytes:
    if img[:4] != b"AVB0":
        raise SystemExit("not a verification image")
    out = bytearray(img)
    struct.pack_into(">I", out, FLAGS_OFFSET, flags)
    return bytes(out)


def read_flags(img: bytes) -> int:
    return struct.unpack_from(">I", img, FLAGS_OFFSET)[0]


def selftest():
    img = bytearray(256)
    img[:4] = b"AVB0"
    struct.pack_into(">I", img, FLAGS_OFFSET, 0)
    img[200] = 0x7F                                   # some unrelated content
    out = set_flags(bytes(img), HASHTREE_DISABLED | VERIFICATION_DISABLED)
    assert read_flags(out) == 3
    assert len(out) == len(img)
    assert out[:FLAGS_OFFSET] == bytes(img)[:FLAGS_OFFSET], "bytes before the flags changed"
    assert out[FLAGS_OFFSET + 4:] == bytes(img)[FLAGS_OFFSET + 4:], "bytes after the flags changed"
    assert read_flags(set_flags(out, 0)) == 0, "flags cannot be cleared again"
    try:
        set_flags(b"XXXX" + bytes(300), 3); raise AssertionError("wrong magic accepted")
    except SystemExit:
        pass
    print("selftest ok")


def main():
    if sys.argv[1:2] == ["--selftest"]:
        return selftest()
    src, outdir = Path(sys.argv[1]), Path(sys.argv[2])
    outdir.mkdir(parents=True, exist_ok=True)
    img = src.read_bytes()
    before = read_flags(img)
    if before != 0:
        raise SystemExit(f"expected no flags set in the original, found {before}")
    relaxed = set_flags(img, HASHTREE_DISABLED | VERIFICATION_DISABLED)
    changed = sum(1 for a, b in zip(img, relaxed) if a != b)
    (outdir / "vbmeta-original.img").write_bytes(img)
    (outdir / "vbmeta-relaxed.img").write_bytes(relaxed)
    print(f"original: {len(img)} bytes, flags {before}, sha256 {hashlib.sha256(img).hexdigest()[:16]}")
    print(f"relaxed:  {len(relaxed)} bytes, flags {read_flags(relaxed)}, sha256 {hashlib.sha256(relaxed).hexdigest()[:16]}")
    print(f"bytes that differ: {changed} (expected 1 to 4)")


if __name__ == "__main__":
    main()
