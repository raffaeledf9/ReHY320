"""Copy partitions out of the golden image, read-only, into the analysis folder.

Usage: python -I extract.py <image> <manifest.json> <out-dir> [name ...]
       python -I extract.py --selftest
"""
import hashlib, json, sys
from pathlib import Path

CHUNK = 1 << 20
DEFAULT = ["super", "boot_b", "vendor_boot_b", "dtbo_b", "env_b", "misc", "media_data", "private", "frp"]


def pick(regions, wanted):
    """Region rows whose name (or any alias) is wanted, keeping manifest order."""
    out = []
    for r in regions:
        aliases = set(r["name"].split("/"))
        if aliases & set(wanted):
            out.append(r)
    missing = set(wanted) - {a for r in out for a in r["name"].split("/")}
    if missing:
        raise SystemExit(f"Not in manifest: {sorted(missing)}")
    return out


def copy_region(img, start, size, dest):
    h = hashlib.sha256()
    with open(img, "rb") as f, open(dest, "wb") as o:
        f.seek(start)
        left = size
        while left:
            b = f.read(min(CHUNK, left))
            if not b:
                raise SystemExit(f"Short read at {dest}")
            o.write(b); h.update(b); left -= len(b)
    return h.hexdigest()


def selftest():
    rows = [{"name": "super", "start": 0, "size": 4}, {"name": "UDISK/userdata", "start": 4, "size": 4}]
    assert [r["name"] for r in pick(rows, ["super"])] == ["super"]
    assert [r["name"] for r in pick(rows, ["userdata"])] == ["UDISK/userdata"]
    try:
        pick(rows, ["nope"]); raise AssertionError("missing name accepted")
    except SystemExit:
        pass
    print("selftest ok")


def main():
    if sys.argv[1:2] == ["--selftest"]:
        return selftest()
    img, man, outdir = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
    wanted = sys.argv[4:] or DEFAULT
    manifest = json.loads(man.read_text(encoding="utf-8"))
    outdir.mkdir(parents=True, exist_ok=True)
    done = {}
    for r in pick(manifest["regions"], wanted):
        name = r["name"].split("/")[0]
        dest = outdir / f"{name}.img"
        digest = copy_region(img, r["start"], r["size"], dest)
        expect = r.get("pc")
        ok = (digest == expect) if expect else None
        done[name] = {"file": str(dest), "size": r["size"], "sha256": digest, "matches_manifest": ok}
        print(f"{name:16} {r['size']:>12}  manifest-match={ok}")
    (outdir / "extracted.json").write_text(json.dumps(done, indent=1))


if __name__ == "__main__":
    main()
