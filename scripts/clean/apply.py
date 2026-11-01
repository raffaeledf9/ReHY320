"""Apply the deletion plan to copies of the extracted file systems. Runs inside WSL.

The originals are never touched: each image is copied first, and the copy is mounted
read-write only for as long as the changes take. Every edit must match its expected text
exactly, or nothing is written at all.

Usage: python3 -I apply.py <plan.json> <source dir> <work dir> [--image system|vendor|product]
       python3 -I apply.py --selftest
"""
import json, shutil, subprocess, sys
from pathlib import Path

SOURCE_NAME = {"system": "system_b.img", "vendor": "vendor_b.img", "product": "product_b.img"}
MOUNT = Path("/mnt/hy320-work")


def run(*cmd, check=True):
    return subprocess.run(cmd, capture_output=True, text=True, check=check)


def plan_for(plan, image):
    return plan["delete"].get(image, []), plan.get("edit", {}).get(image, [])


def apply_edit(root: Path, edit: dict) -> str:
    """Replace exact text in a file, or refuse.

    These file systems are packed with no free blocks, so when the replacement is no
    longer than the original the bytes are overwritten in place, padded with spaces,
    which needs no new blocks. Only a shrinking edit rewrites the file.
    """
    f = root / edit["path"]
    if not f.is_file():
        raise SystemExit(f"{edit['path']}: not found, refusing")
    raw = f.read_bytes()
    old, new = edit["old"].encode(), edit["new"].encode()
    if raw.count(old) != 1:
        raise SystemExit(f"{edit['path']}: expected text appears {raw.count(old)} times, refusing")
    if new and len(new) <= len(old):
        padded = new + b" " * (len(old) - len(new))
        with open(f, "r+b") as fh:
            fh.seek(raw.index(old))
            fh.write(padded)
        return f"edited {edit['path']} in place ({len(old)} bytes)"
    f.write_bytes(raw.replace(old, new, 1))
    return f"edited {edit['path']} ({len(raw)} -> {len(raw) - len(old) + len(new)} bytes)"


def delete(root: Path, entry: dict) -> str:
    target = root / entry["path"]
    if not target.exists():
        return f"MISSING (already absent): {entry['path']}"
    size = sum(x.stat().st_size for x in target.rglob("*") if x.is_file()) if target.is_dir() else target.stat().st_size
    shutil.rmtree(target) if target.is_dir() else target.unlink()
    return f"deleted {entry['path']} ({size:,} bytes)"


def selftest(tmp=Path("/tmp/applytest")):
    shutil.rmtree(tmp, ignore_errors=True)
    (tmp / "d" / "sub").mkdir(parents=True)
    (tmp / "d" / "sub" / "f").write_text("x" * 10)
    (tmp / "keep").write_text("keep me")
    (tmp / "cfg").write_text("a\nTARGET\nb\n")
    assert "deleted d" in delete(tmp, {"path": "d"})
    assert not (tmp / "d").exists() and (tmp / "keep").exists()
    assert "MISSING" in delete(tmp, {"path": "gone"})
    assert "edited cfg" in apply_edit(tmp, {"path": "cfg", "old": "TARGET\n", "new": ""})
    assert (tmp / "cfg").read_text() == "a\nb\n"
    # A same-length-or-shorter replacement must be written in place and padded.
    (tmp / "inplace").write_text("x 0666 system\n")
    assert "in place" in apply_edit(tmp, {"path": "inplace", "old": "0666 system", "new": "0440 root"})
    assert (tmp / "inplace").read_text() == "x 0440 root  \n", repr((tmp / "inplace").read_text())
    for bad in ({"path": "cfg", "old": "TARGET\n", "new": ""}, {"path": "nope", "old": "x", "new": "y"}):
        try:
            apply_edit(tmp, bad); raise AssertionError("refusal expected")
        except SystemExit:
            pass
    pl = {"delete": {"system": [{"path": "a"}]}, "edit": {"system": [{"path": "b", "old": "o", "new": "n"}]}}
    assert plan_for(pl, "system") == ([{"path": "a"}], [{"path": "b", "old": "o", "new": "n"}])
    assert plan_for(pl, "vendor") == ([], [])
    shutil.rmtree(tmp, ignore_errors=True)
    print("selftest ok")


def main():
    if sys.argv[1:2] == ["--selftest"]:
        return selftest()
    plan = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    src, work = Path(sys.argv[2]), Path(sys.argv[3])
    only = sys.argv[sys.argv.index("--image") + 1] if "--image" in sys.argv else None
    work.mkdir(parents=True, exist_ok=True)
    MOUNT.mkdir(exist_ok=True)

    for image in ("system", "vendor", "product"):
        if only and image != only:
            continue
        deletions, edits = plan_for(plan, image)
        if not deletions and not edits:
            print(f"=== {image}: nothing to do")
            continue
        source, target = src / SOURCE_NAME[image], work / SOURCE_NAME[image]
        print(f"=== {image}: copying {source.name} ({source.stat().st_size:,} bytes)", flush=True)
        shutil.copyfile(source, target)
        run("mount", "-o", "rw,loop,noexec,nosuid,nodev", str(target), str(MOUNT))
        try:
            for e in deletions:
                print("   " + delete(MOUNT, e), flush=True)
            for e in edits:
                print("   " + apply_edit(MOUNT, e), flush=True)
        finally:
            run("umount", str(MOUNT))
        chk = run("e2fsck", "-fn", str(target), check=False)
        print(f"   file system check: {'clean' if chk.returncode == 0 else 'PROBLEM'}")
        if chk.returncode != 0:
            print(chk.stdout[-800:])
            raise SystemExit(f"{image}: the modified file system does not check out")
        print(f"   wrote {target}")


if __name__ == "__main__":
    main()
