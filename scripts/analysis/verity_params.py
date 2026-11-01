"""Print the full verity parameters of each partition, as the device's own data records them.

These are what a rebuilt system would have to reproduce to get the checking back.

Usage: python -I verity_params.py <vbmeta.img> [...]
       python -I verity_params.py --selftest
"""
import struct, sys
from pathlib import Path


def header(buf):
    """Just the fields needed to find the descriptor list (packed, big-endian)."""
    if buf[:4] != b"AVB0":
        raise SystemExit("not a verification image")
    auth_block = struct.unpack_from(">Q", buf, 12)[0]
    desc_off, desc_size = struct.unpack_from(">QQ", buf, 96)
    return {"auth_block": auth_block, "descriptors_offset": desc_off, "descriptors_size": desc_size}


def hashtrees(buf):
    out = []
    h = header(buf)
    base = 256 + h["auth_block"] + h["descriptors_offset"]
    end = base + h["descriptors_size"]
    off = base
    while off + 16 <= end:
        tag, nbf = struct.unpack_from(">QQ", buf, off)
        body = buf[off + 16: off + 16 + nbf]
        if tag == 1:                                     # hashtree descriptor
            fields = {}
            fields["dm_verity_version"] = struct.unpack_from(">I", body, 0)[0]
            fields["image_size"] = struct.unpack_from(">Q", body, 4)[0]
            fields["tree_offset"], fields["tree_size"] = struct.unpack_from(">QQ", body, 12)
            fields["data_block"], fields["hash_block"], fields["fec_roots"] = struct.unpack_from(">III", body, 28)
            fields["fec_offset"], fields["fec_size"] = struct.unpack_from(">QQ", body, 40)
            fields["algorithm"] = body[56:88].split(b"\0")[0].decode(errors="replace")
            nl, sl, dl = struct.unpack_from(">III", body, 88)
            fields["flags"] = struct.unpack_from(">I", body, 100)[0]
            fields["partition"] = body[164:164 + nl].decode(errors="replace")
            fields["salt"] = body[164 + nl:164 + nl + sl].hex()
            fields["root_digest"] = body[164 + nl + sl:164 + nl + sl + dl].hex()
            out.append(fields)
        off += 16 + ((nbf + 7) & ~7)
    return out


def selftest():
    # A descriptor list whose only hashtree entry must be found after a property entry.
    def desc(tag, body):
        return struct.pack(">QQ", tag, len(body)) + body + bytes(-len(body) % 8)
    ht = bytearray(164)
    struct.pack_into(">I", ht, 0, 1)
    struct.pack_into(">Q", ht, 4, 4096)
    struct.pack_into(">III", ht, 28, 4096, 4096, 2)
    ht[56:60] = b"sha1"
    struct.pack_into(">III", ht, 88, 6, 2, 3)
    body = bytes(ht) + b"system" + b"\xaa\xbb" + b"\x01\x02\x03"
    blob = desc(0, b"\x00" * 32) + desc(1, body)
    buf = bytearray(256)
    buf[:4] = b"AVB0"
    struct.pack_into(">II", buf, 4, 1, 0)
    struct.pack_into(">QQ", buf, 12, 0, len(blob))
    struct.pack_into(">QQ", buf, 96, 0, len(blob))
    out = hashtrees(bytes(buf) + blob)
    assert len(out) == 1, out
    assert out[0]["partition"] == "system" and out[0]["salt"] == "aabb" and out[0]["root_digest"] == "010203"
    assert out[0]["algorithm"] == "sha1" and out[0]["image_size"] == 4096
    print("selftest ok")


def main():
    if sys.argv[1:2] == ["--selftest"]:
        return selftest()
    for p in sys.argv[1:]:
        for f in hashtrees(Path(p).read_bytes()):
            print(f"=== {f['partition']} (from {Path(p).name})")
            print(f"  filesystem size {f['image_size']:,} bytes")
            print(f"  hashtree at {f['tree_offset']:,}, size {f['tree_size']:,}")
            print(f"  error correction: roots {f['fec_roots']}, at {f['fec_offset']:,}, size {f['fec_size']:,}")
            print(f"  blocks: data {f['data_block']}, hash {f['hash_block']}; algorithm {f['algorithm']}; verity version {f['dm_verity_version']}; flags {f['flags']}")
            print(f"  salt {f['salt']}")
            print(f"  root digest {f['root_digest']}")


if __name__ == "__main__":
    main()
