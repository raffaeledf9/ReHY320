"""Compare the key that signs this device's verified-boot data with Android's public test keys.

If it is a public test key, the cleaned partitions can be re-signed properly, and verified boot
can stay switched on. If not, verification has to be relaxed instead.

Usage: python -I vbmeta_key.py <vbmeta.img> <testkey.pem> [...]
       python -I vbmeta_key.py --selftest
"""
import base64, hashlib, re, struct, sys
from pathlib import Path


def avb_modulus(vbmeta: bytes) -> bytes:
    """The RSA modulus from an AVB public key blob inside a vbmeta image."""
    auth_size = struct.unpack_from(">Q", vbmeta, 12)[0]
    key_off, key_size = struct.unpack_from(">QQ", vbmeta, 64)
    if key_size == 0:
        raise SystemExit("vbmeta carries no public key (unsigned)")
    blob = vbmeta[256 + auth_size + key_off: 256 + auth_size + key_off + key_size]
    bits = struct.unpack_from(">I", blob, 0)[0]
    n_bytes = bits // 8
    return blob[8: 8 + n_bytes]


def pem_modulus(pem_text: str) -> bytes:
    """The RSA modulus from a PEM key, found as the longest DER INTEGER."""
    body = "".join(l for l in pem_text.splitlines() if "-----" not in l)
    der = base64.b64decode(body)
    best = b""
    i = 0
    while i < len(der) - 3:
        if der[i] == 0x02 and der[i + 1] == 0x82:                  # INTEGER, 2-byte length
            length = int.from_bytes(der[i + 2:i + 4], "big")
            val = der[i + 4: i + 4 + length]
            if val[:1] == b"\0":
                val = val[1:]
            if len(val) > len(best):
                best = val
            i += 4 + length
        else:
            i += 1
    if not best:
        raise SystemExit("No modulus found in PEM")
    return best


def selftest():
    blob = struct.pack(">II", 2048, 0) + bytes(range(256)) + b"\0" * 256
    vb = bytearray(256 + 100)
    struct.pack_into(">Q", vb, 12, 100)          # auth block size
    struct.pack_into(">QQ", vb, 64, 0, len(blob))  # key offset, size
    vb += blob
    assert avb_modulus(bytes(vb)) == bytes(range(256))
    # A DER integer of 3 bytes wrapped in a fake PEM must come back exactly.
    der = b"\x30\x06" + b"\x02\x82\x00\x03" + b"\xaa\xbb\xcc"
    pem = "-----BEGIN X-----\n" + base64.b64encode(der).decode() + "\n-----END X-----\n"
    assert pem_modulus(pem) == b"\xaa\xbb\xcc"
    try:
        pem_modulus("-----BEGIN X-----\n" + base64.b64encode(b"\x30\x00").decode() + "\n-----END X-----")
        raise AssertionError("empty PEM accepted")
    except SystemExit:
        pass
    print("selftest ok")


def main():
    if sys.argv[1:2] == ["--selftest"]:
        return selftest()
    n = avb_modulus(Path(sys.argv[1]).read_bytes())
    print(f"device key: {len(n) * 8} bits, sha256 {hashlib.sha256(n).hexdigest()[:32]}")
    for p in sys.argv[2:]:
        try:
            m = pem_modulus(Path(p).read_text(encoding="utf-8", errors="replace"))
        except SystemExit as e:
            print(f"  {Path(p).name}: {e}")
            continue
        same = "MATCH" if m == n else "different"
        print(f"  {Path(p).name}: {len(m) * 8} bits, sha256 {hashlib.sha256(m).hexdigest()[:32]} -> {same}")


if __name__ == "__main__":
    main()
