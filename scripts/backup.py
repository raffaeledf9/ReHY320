"""Ticket 08: golden backup of the HY320's whole eMMC over USB ADB. Read-only on the projector.

Usage:
  python -I backup.py --dest <backup> --pc-copy <dir> --expect <identify output dir>
  python -I backup.py --selftest

Every command sent to the projector is a fixed read (getprop, ls, cat of /sys, dd with if= only).
"""
import argparse, gzip, hashlib, json, re, shutil, subprocess, sys, time
from pathlib import Path

DISK = "/dev/block/mmcblk0"
SKIP_DEVICE_HASH = {"userdata", "metadata"}   # rewritten while Android runs; PC hash only
MAY_DIFFER = {"misc", "media_data"}           # small, may be touched at runtime
CHUNK = 1 << 20


def block_size(start_b, size_b):
    bs = CHUNK
    while bs > 512 and (start_b % bs or size_b % bs):
        bs //= 2
    return bs


def read_cmd(start_b, size_b):
    bs = block_size(start_b, size_b)
    cmd = f"dd if={DISK} bs={bs} skip={start_b // bs} count={size_b // bs} 2>/dev/null"
    assert "of=" not in cmd
    return cmd


def ready_serial(devices_output):
    rows = [l.split() for l in devices_output.splitlines()[1:] if l.strip()]
    usb = [r for r in rows if ":" not in r[0]]
    if len(usb) != 1 or usb[0][1] != "device":
        raise SystemExit(f"Need exactly one projector on USB in state 'device', got: {usb}")
    return usb[0][0]


def regions(parts, disk_b):
    """parts: {name: (start_b, size_b)} -> sorted list covering the whole disk, gaps included."""
    out, pos = [], 0
    for name, (start, size) in sorted(parts.items(), key=lambda kv: kv[1][0]):
        if start > pos:
            out.append((f"gap@{pos}", pos, start - pos))
        out.append((name, start, size))
        pos = start + size
    if pos < disk_b:
        out.append((f"gap@{pos}", pos, disk_b - pos))
    return out


def group_aliases(byname):
    """{alias: node} -> {node: 'a/b'}; one entry per partition even when it has several names."""
    names = {}
    for alias, node in byname.items():
        names.setdefault(node, []).append(alias)
    return {node: "/".join(sorted(n)) for node, n in names.items()}


def selftest():
    assert block_size(73728 * 512, 65536 * 512) == CHUNK
    assert block_size(4998144 * 512, 9944031 * 512) == 512
    assert "of=" not in read_cmd(0, 4096)
    assert ready_serial("List of devices attached\nABC  device product:x\n1.2.3.4:5555  device\n") == "ABC"
    try:
        ready_serial("List of devices attached\nABC  unauthorized\n")
        raise AssertionError("unauthorized accepted")
    except SystemExit:
        pass
    assert group_aliases({"UDISK": "p25", "userdata": "p25", "super": "p9"}) == {"p25": "UDISK/userdata", "p9": "super"}
    r = regions({"b": (100, 50), "a": (10, 40)}, 200)
    assert [x[0] for x in r] == ["gap@0", "a", "gap@50", "b", "gap@150"]
    assert sum(x[2] for x in r) == 200
    print("selftest ok")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dest"); ap.add_argument("--pc-copy"); ap.add_argument("--expect")
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--reuse-image", action="store_true", help="verify an existing image instead of dumping again")
    a = ap.parse_args()
    if a.selftest:
        return selftest()

    adb_exe = shutil.which("adb") or sys.exit("adb not found")
    serial = ready_serial(subprocess.run([adb_exe, "devices", "-l"], capture_output=True, text=True, check=True).stdout)

    def sh(cmd):
        return subprocess.run([adb_exe, "-s", serial, "shell", cmd], capture_output=True, text=True, check=True).stdout.strip()

    # Identity lock: same unit and build as recorded by identify.ps1.
    rec = Path(a.expect, "getprop.txt").read_text(encoding="utf-8-sig")
    want = {k: re.search(rf"^\[{re.escape(k)}\]: \[(.*)\]", rec, re.M).group(1) for k in ("ro.serialno", "ro.build.fingerprint")}
    have = {k: sh(f"getprop {k}") for k in want}
    if have != want:
        sys.exit(f"Identity mismatch: recorded {want}, connected {have}")

    dest, pcdir = Path(a.dest), Path(a.pc_copy)
    pcdir.mkdir(parents=True, exist_ok=True)
    img, gz = dest / "mmcblk0.img", pcdir / "mmcblk0.img.gz"
    if gz.exists() or (img.exists() and not a.reuse_image):
        sys.exit(f"Refusing to overwrite {gz if gz.exists() else img}")

    disk_b = int(sh("cat /sys/class/block/mmcblk0/size")) * 512
    byname = dict(re.findall(r"(\S+) -> /dev/block/(mmcblk0p\d+)", sh("ls -l /dev/block/by-name")))
    parts = {}
    for node, name in group_aliases(byname).items():
        start, size = sh(f"cat /sys/class/block/{node}/start /sys/class/block/{node}/size").split()
        parts[name] = (int(start) * 512, int(size) * 512)
    regs = regions(parts, disk_b)

    whole = hashlib.sha256()
    if a.reuse_image:
        print(f"[{time.strftime('%H:%M:%S')}] reusing {img}", flush=True)
        with open(img, "rb") as f:
            while b := f.read(CHUNK):
                whole.update(b)
    else:
        print(f"[{time.strftime('%H:%M:%S')}] dumping {disk_b} bytes to {img}", flush=True)
        with open(img, "xb") as f:
            p = subprocess.Popen([adb_exe, "-s", serial, "exec-out", f"dd if={DISK} bs={CHUNK} 2>/dev/null"], stdout=subprocess.PIPE)
            while chunk := p.stdout.read(CHUNK):
                f.write(chunk); whole.update(chunk)
            if p.wait() != 0:
                sys.exit("adb exec-out failed")
    if img.stat().st_size != disk_b:
        sys.exit(f"Size mismatch: image {img.stat().st_size}, disk {disk_b}")
    print(f"[{time.strftime('%H:%M:%S')}] size ok, sha256 {whole.hexdigest()}", flush=True)

    results, failed = [], []
    with open(img, "rb") as f:
        for name, start, size in regs:
            f.seek(start); h, left = hashlib.sha256(), size
            while left:
                b = f.read(min(CHUNK, left)); h.update(b); left -= len(b)
            row = {"name": name, "start": start, "size": size, "pc": h.hexdigest()}
            aliases = set(name.split("/"))
            if not aliases & SKIP_DEVICE_HASH:
                row["device"] = sh(f"{read_cmd(start, size)} | sha256sum").split()[0]
                row["match"] = row["device"] == row["pc"]
                if not row["match"] and not aliases & MAY_DIFFER:
                    failed.append(name)
            results.append(row)
            print(f"  {name:18} {size:>12} {row.get('match', 'pc-only')}", flush=True)

    manifest = {"taken": time.strftime("%Y-%m-%d %H:%M:%S"), "serial": have["ro.serialno"],
                "fingerprint": have["ro.build.fingerprint"], "disk_bytes": disk_b,
                "image": str(img), "image_sha256": whole.hexdigest(), "regions": results,
                "static_mismatches": failed}
    if failed:
        (dest / "manifest.json").write_text(json.dumps(manifest, indent=1))
        sys.exit(f"FAIL: static regions differ from the device: {failed}")

    print(f"[{time.strftime('%H:%M:%S')}] compressing to {gz}", flush=True)
    with open(img, "rb") as src, gzip.open(gz, "xb", compresslevel=6) as dst:
        shutil.copyfileobj(src, dst, CHUNK)
    check = hashlib.sha256()
    with gzip.open(gz, "rb") as f:
        while b := f.read(CHUNK):
            check.update(b)
    if check.hexdigest() != whole.hexdigest():
        sys.exit("FAIL: compressed copy does not decompress to the same image")
    manifest["pc_copy"] = str(gz)
    manifest["pc_copy_bytes"] = gz.stat().st_size
    for d in (dest, pcdir):
        (d / "manifest.json").write_text(json.dumps(manifest, indent=1))
    print(f"[{time.strftime('%H:%M:%S')}] DONE: golden backup verified, compressed copy verified ({gz.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
