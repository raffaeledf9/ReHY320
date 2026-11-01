"""Make the recovery tool send data in 4 KB pieces.

This unit stops answering if a single transfer at the load address is 16 KB or
more, while 4 KB always works. Each piece is a complete, protocol-legal request,
so only the transfer size changes.

Usage: python3 -I chunk_patch.py <path to fel_lib.c>   (inside WSL)
       python3 -I chunk_patch.py --selftest
"""
import re, sys
from pathlib import Path

CHUNK_HELPER = """
/* This device stops answering if a single write transfer is 16 KiB or more, so
 * every write goes out in pieces. Each piece is a complete FEL write request. */
#define AW_FEL_WRITE_CHUNK 4096
static void aw_fel_write_chunked(feldev_handle *dev, const void *buf,
				 uint32_t offset, size_t len, bool progress)
{
	const uint8_t *p = buf;
	while (len > 0) {
		size_t n = len > AW_FEL_WRITE_CHUNK ? AW_FEL_WRITE_CHUNK : len;
		aw_send_fel_request(dev, AW_FEL_1_WRITE, offset, n);
		aw_usb_write(dev, p, n, progress);
		aw_read_fel_status(dev);
		p += n;
		offset += n;
		len -= n;
	}
}
"""

RAW_OLD = """	aw_send_fel_request(dev, AW_FEL_1_WRITE, offset, len);
	aw_usb_write(dev, buf, len, false);
	aw_read_fel_status(dev);
}"""
RAW_NEW = """	aw_fel_write_chunked(dev, buf, offset, len, false);
}"""

BUF_OLD = """	aw_send_fel_request(dev, AW_FEL_1_WRITE, offset, len);
	aw_usb_write(dev, buf, len, progress);
	aw_read_fel_status(dev);
}"""
BUF_NEW = """	aw_fel_write_chunked(dev, buf, offset, len, progress);
}"""


def patch(src: str) -> str:
    if "aw_fel_write_chunked" in src:
        raise SystemExit("already patched")
    anchor = "/* AW_FEL_1_WRITE request */"
    if anchor not in src:
        raise SystemExit("cannot find where to insert the helper")
    src = src.replace(anchor, CHUNK_HELPER + anchor, 1)
    for old, new, what in ((RAW_OLD, RAW_NEW, "raw write"), (BUF_OLD, BUF_NEW, "buffered write")):
        if src.count(old) != 1:
            raise SystemExit(f"expected exactly one {what} body, found {src.count(old)}")
        src = src.replace(old, new, 1)
    return src


def selftest():
    sample = ("/* AW_FEL_1_WRITE request */\n"
              "static void aw_fel_write_raw(x)\n{\n\tif (len == 0)\n\t\treturn;\n\n" + RAW_OLD + "\n\n"
              "void aw_fel_write_buffer(y)\n{\n\tif (len == 0)\n\t\treturn;\n\n" + BUF_OLD + "\n")
    out = patch(sample)
    assert "aw_fel_write_chunked(dev, buf, offset, len, false);" in out
    assert "aw_fel_write_chunked(dev, buf, offset, len, progress);" in out
    assert out.count("AW_FEL_1_WRITE, offset, n") == 1, "only the helper may send requests"
    assert "aw_usb_write(dev, buf, len" not in out, "old direct transfers must be gone"
    try:
        patch(out); raise AssertionError("double patch accepted")
    except SystemExit:
        pass
    try:
        patch("nothing here"); raise AssertionError("missing anchor accepted")
    except SystemExit:
        pass
    print("selftest ok")


if __name__ == "__main__":
    if sys.argv[1:2] == ["--selftest"]:
        selftest()
    else:
        p = Path(sys.argv[1])
        backup = p.with_suffix(p.suffix + ".orig")
        if not backup.exists():
            backup.write_text(p.read_text(encoding="utf-8"), encoding="utf-8")
        p.write_text(patch(backup.read_text(encoding="utf-8")), encoding="utf-8")
        print(f"patched {p} (original kept as {backup.name})")
