"""Read an Android verified-boot (vbmeta) image: its flags and what it protects. Read-only.

Usage: python -I parse_vbmeta.py <vbmeta.img> [...]
       python -I parse_vbmeta.py --selftest

Field offsets follow AOSP's packed, big-endian AvbVBMetaImageHeader and descriptor structs.
"""
import struct, sys
from pathlib import Path

MAGIC = b"AVB0"
FLAG_HASHTREE_DISABLED = 1
FLAG_VERIFICATION_DISABLED = 2
DESC = {0: "property", 1: "hashtree", 2: "hash", 3: "kernel_cmdline", 4: "chain_partition"}


def header(buf):
    if buf[:4] != MAGIC:
        raise SystemExit("Not a vbmeta image")
    major, minor = struct.unpack_from(">II", buf, 4)
    auth_size, aux_size = struct.unpack_from(">QQ", buf, 12)
    desc_off, desc_size = struct.unpack_from(">QQ", buf, 96)
    rollback = struct.unpack_from(">Q", buf, 112)[0]
    flags, ril = struct.unpack_from(">II", buf, 120)
    release = buf[128:176].split(b"\0")[0].decode(errors="replace")
    return {"version": f"{major}.{minor}", "auth_block": auth_size, "aux_block": aux_size,
            "descriptors_offset": desc_off, "descriptors_size": desc_size,
            "rollback_index": rollback, "flags": flags, "rollback_index_location": ril,
            "release": release}


def flag_names(flags):
    out = []
    if flags & FLAG_HASHTREE_DISABLED:
        out.append("verity (hashtree) DISABLED")
    if flags & FLAG_VERIFICATION_DISABLED:
        out.append("verification DISABLED")
    return out or ["none (verification and verity both active)"]


def _text(body, off, length):
    return body[off: off + length].decode(errors="replace")


def descriptors(buf, h):
    base = 256 + h["auth_block"] + h["descriptors_offset"]
    end = base + h["descriptors_size"]
    out, off = [], base
    while off + 16 <= end:
        tag, nbf = struct.unpack_from(">QQ", buf, off)
        body = buf[off + 16: off + 16 + nbf]
        row = {"type": DESC.get(tag, f"tag{tag}")}
        if tag == 1 and len(body) >= 164:        # hashtree: body offsets per AvbHashtreeDescriptor - 16
            image_size = struct.unpack_from(">Q", body, 4)[0]
            data_block, hash_block = struct.unpack_from(">II", body, 28)
            algo = body[56:88].split(b"\0")[0].decode(errors="replace")
            name_len, salt_len, digest_len = struct.unpack_from(">III", body, 88)
            row.update(partition=_text(body, 164, name_len), image_size=image_size,
                       hash=algo, data_block=data_block, hash_block=hash_block,
                       digest=body[164 + name_len + salt_len: 164 + name_len + salt_len + digest_len].hex()[:32])
        elif tag == 2 and len(body) >= 116:      # hash
            image_size = struct.unpack_from(">Q", body, 0)[0]
            algo = body[8:40].split(b"\0")[0].decode(errors="replace")
            name_len, salt_len, digest_len = struct.unpack_from(">III", body, 40)
            row.update(partition=_text(body, 116, name_len), image_size=image_size, hash=algo,
                       digest=body[116 + name_len + salt_len: 116 + name_len + salt_len + digest_len].hex()[:32])
        elif tag == 4 and len(body) >= 76:       # chain to another vbmeta
            ril, name_len, key_len = struct.unpack_from(">III", body, 0)
            row.update(partition=_text(body, 76, name_len), key_bytes=key_len, rollback_location=ril)
        elif tag == 3 and len(body) >= 8:        # kernel cmdline
            flags, length = struct.unpack_from(">II", body, 0)
            row.update(flags=flags, text=_text(body, 8, length)[:300])
        elif tag == 0 and len(body) >= 16:       # property
            key_len, val_len = struct.unpack_from(">QQ", body, 0)
            row.update(key=_text(body, 16, key_len), value=_text(body, 16 + key_len + 1, val_len))
        out.append(row)
        off += 16 + ((nbf + 7) & ~7)
    return out


def selftest():
    assert flag_names(0) == ["none (verification and verity both active)"]
    assert flag_names(1) == ["verity (hashtree) DISABLED"]
    assert len(flag_names(3)) == 2
    # A minimal header with known values must parse back exactly.
    buf = bytearray(256)
    buf[0:4] = MAGIC
    struct.pack_into(">II", buf, 4, 1, 0)
    struct.pack_into(">QQ", buf, 12, 576, 1024)
    struct.pack_into(">QQ", buf, 96, 0, 80)
    struct.pack_into(">Q", buf, 112, 3)
    struct.pack_into(">II", buf, 120, 1, 0)
    buf[128:136] = b"avbtool\0"
    h = header(bytes(buf))
    assert h == {"version": "1.0", "auth_block": 576, "aux_block": 1024, "descriptors_offset": 0,
                 "descriptors_size": 80, "rollback_index": 3, "flags": 1,
                 "rollback_index_location": 0, "release": "avbtool"}, h
    try:
        header(b"XXXX" + b"\0" * 300); raise AssertionError("bad magic accepted")
    except SystemExit:
        pass
    print("selftest ok")


def main():
    if sys.argv[1:2] == ["--selftest"]:
        return selftest()
    for path in sys.argv[1:]:
        buf = Path(path).read_bytes()
        h = header(buf)
        print(f"=== {Path(path).name}")
        print(f"  avb {h['version']}, release {h['release']!r}, rollback index {h['rollback_index']}")
        print(f"  flags {h['flags']}: {', '.join(flag_names(h['flags']))}")
        for d in descriptors(buf, h):
            extra = " ".join(f"{k}={v}" for k, v in d.items() if k != "type")
            print(f"  {d['type']:16} {extra}")


if __name__ == "__main__":
    main()
