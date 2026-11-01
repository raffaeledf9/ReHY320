"""Add the verification flag to the mount table, keeping the file exactly as long.

The vendor file system has no free blocks, so the file cannot grow. The flag is paid for
by reclaiming spaces from the padding between columns, which the mount table ignores.

Usage: python3 -I enable_avb.py <path to fstab>
       python3 -I enable_avb.py --selftest
"""
import re, sys
from pathlib import Path

# partition name -> the flag Android needs to find that partition's hash tree
FLAGS = {
    "system": ",avb=vbmeta_system",     # its descriptor is in the chained vbmeta_system
    "vendor": ",avb=vbmeta_vendor",     # likewise vbmeta_vendor
    "product": ",avb",                  # its descriptor is in the top-level vbmeta
}


def patch_line(line, flag):
    """Append the flag and take the same number of characters out of the padding."""
    if "avb" in line:
        raise SystemExit("this line already asks for verification")
    stripped = line.rstrip("\n")
    newline = "\n" if line.endswith("\n") else ""
    widened = stripped + flag
    need = len(flag)
    # Shorten the longest run of spaces, never below two, so the columns stay readable.
    for _ in range(need):
        runs = sorted(re.finditer(r" {3,}", widened), key=lambda m: m.end() - m.start())
        if not runs:
            raise SystemExit("not enough padding to pay for the flag")
        longest = runs[-1]
        widened = widened[:longest.start()] + widened[longest.start():longest.end() - 1] + widened[longest.end():]
    if len(widened) != len(stripped):
        raise SystemExit(f"length changed: {len(stripped)} -> {len(widened)}")
    return widened + newline


def patch(text):
    out, changed = [], 0
    for line in text.splitlines(keepends=True):
        name = line.split()[0] if line.strip() and not line.lstrip().startswith("#") else None
        if name in FLAGS:
            line = patch_line(line, FLAGS[name])
            changed += 1
        out.append(line)
    if changed != len(FLAGS):
        raise SystemExit(f"expected {len(FLAGS)} lines to change, changed {changed}")
    result = "".join(out)
    if len(result) != len(text):
        raise SystemExit("the file length changed")
    return result


def selftest():
    sample = ("# a comment\n"
              "system     /system      ext4     ro,barrier=1          wait,logical,slotselect\n"
              "vendor     /vendor      ext4     ro,barrier=1          wait,logical,slotselect\n"
              "product    /product     ext4     ro,barrier=1          wait,logical,slotselect\n"
              "/dev/block/x /oem vfat nodev wait\n")
    out = patch(sample)
    assert len(out) == len(sample), (len(out), len(sample))
    for want in (",avb=vbmeta_system", ",avb=vbmeta_vendor"):
        assert want in out, want
    assert out.splitlines()[0] == "# a comment", "comments must be untouched"
    assert out.splitlines()[4] == "/dev/block/x /oem vfat nodev wait", "other lines must be untouched"
    for a, b in zip(sample.splitlines(), out.splitlines()):
        assert len(a) == len(b), (a, b)
    try:
        patch(out); raise AssertionError("patching twice should be refused")
    except SystemExit:
        pass
    try:
        patch_line("system /system ext4 ro wait\n", ",avb=vbmeta_system")
        raise AssertionError("a line with no padding should be refused")
    except SystemExit:
        pass
    print("selftest ok")


if __name__ == "__main__":
    if sys.argv[1:2] == ["--selftest"]:
        selftest()
    else:
        p = Path(sys.argv[1])
        before = p.read_text(encoding="utf-8")
        after = patch(before)
        with open(p, "r+b") as f:        # in place, no new blocks
            f.write(after.encode())
        print(f"patched {p}, still {p.stat().st_size} bytes")
        for line in after.splitlines():
            if line.split() and line.split()[0] in FLAGS:
                print("  " + line)
