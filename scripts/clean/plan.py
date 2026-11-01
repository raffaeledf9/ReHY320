"""Turn the approved keep-list into an exact list of paths to delete, inside each image.

Reads the unit's own package list so every app is resolved to the real directory on the
device, and fails loudly if a named package is not found or if something meant to be kept
would be deleted. Produces a plan only; nothing is modified.

Usage: python -I plan.py <packages-all.txt> <out plan.json>
       python -I plan.py --selftest
"""
import json, sys
from pathlib import Path

# Apps to remove, by package name, with the reason (ticket 09 proposal, ticket 10 approval).
REMOVE_APPS = {
    "com.htc.storeos": "installs apps without asking",
    "com.htc.eventuploadservice": "sends usage data out",
    "com.htc.htcotaupdate": "the vendor updater, how the rest arrived",
    "com.hotack.writesn": "factory tool that writes the serial number, has internet access",
    "com.hotack.hotackfeaturestest": "factory test app",
    "com.htc.hyk_test": "factory test app, 43 MB",
    "com.softwinner.dragonbox": "factory test app with full network access",
    "com.softwinner.dragonatt": "factory test app",
    "com.softwinner.agingdragonbox": "factory test app",
    "android.rockchip.update.service": "updater for a different manufacturer's chip",
    "com.softwinner.update": "second updater",
    "com.htc.htclauncherhighenglishd08": "the stock launcher, replaced",
    "com.android.toofifi": "vendor casting app hiding behind a stock-looking name",
    "com.toofifi.lineserver": "vendor casting",
    "com.mphotool.airplay": "vendor casting, fails signature verification",
    "com.mphotool.dlna": "vendor casting",
    "com.mphotool.usbcastserver": "vendor casting, fails signature verification",
    "com.htc.samescreen": "vendor casting",
    "com.softwinner.miracastReceiver": "vendor casting, replaced",
    "com.mobisystems.office": "office suite, 95 MB, fails signature verification",
    "com.softwinner.TvdVideo": "bloat, replaced",
    "com.softwinner.TvdFileManager": "bloat, replaced",
    "com.android.music": "a Rockchip music app, bloat",
    "com.softwinner.awlogsettings": "vendor logging settings",
    "com.allwinnertech.packageoverride": "bloat",
    "com.htc.screensaver": "vendor screensaver, replaced (ticket 22)",
}

# Apps that must survive; the plan fails if any of these would be touched.
KEEP_APPS = {
    "com.softwinner.awsource", "com.softwinner.awlivetv", "com.softwinner.vis",
    "com.softwinner.awmanager", "com.softwinner.settingsassist", "com.softwinner.settingssetup",
    "com.softwinner.provision", "com.softwinner.tvvolume", "com.softwinner.theme.color",
    "com.softwinner.theme.icon", "com.softwinner.ImageParser", "com.softwinner.screenshot",
    "com.htc.closedialog", "com.android.nfx", "com.htc.htcsettings",
    "com.google.android.gms", "com.google.android.gsf", "com.android.vending",
}

# Programs and startup files to remove, by path inside the image.
REMOVE_FILES = {
    "system": [
        ("system/bin/qw", "a renamed Superuser root daemon, started at every boot"),
        ("system/etc/init/qw.rc", "starts the root daemon"),
        ("system/bin/preinstall", "installs any app it finds in a preinstall folder"),
        ("system/etc/init/preinstall.rc", "starts the silent installer"),
        ("system/bin/appsdisable", "switches off Google's own protection"),
        ("system/etc/init/appsdisable.rc", "starts it"),
        ("system/bin/gmsopt", "switches off Google's own protection"),
        ("system/etc/init/gmsopt.rc", "starts it"),
        ("system/bin/replace_file.sh", "copies a boot logo, properties and apps from removable media"),
        ("system/bin/logcatshell.sh", "writes log files to internal storage forever"),
        ("system/etc/init/logcatshell.rc", "starts the logger"),
        ("system/bin/eshare.sh", "leftover of a casting app that is not installed"),
        ("system/bin/netflix_copy.sh", "empty leftover"),
    ],
    "vendor": [],
    "product": [],
}

# In-place edits, as (path, exact old line or block, replacement, reason).
EDITS = {
    "vendor": [
        ("ueventd.rc",
         "/dev/block/mmcblk0          0666    system      system",
         "/dev/block/mmcblk0          0440    root        shell",
         "the vendor lets every app read and write the whole storage (ticket 20)"),
    ],
    "system": [
        ("system/etc/selinux/plat_seapp_contexts",
         "user=system isPrivApp=true name=com.wohuatv.launcher domain=system_app type=system_app_data_file\n"
         "user=system isPrivApp=true name=com.ksj.ottgame domain=system_app type=system_app_data_file\n"
         "user=system isPrivApp=true name=com.ksj.ott.keep domain=system_app type=system_app_data_file\n"
         "user=system isPrivApp=true name=com.ksj.ott.store domain=system_app type=system_app_data_file\n"
         "user=system isPrivApp=true name=com.stb.duer.apps.xtvott domain=system_app type=system_app_data_file\n",
         "",
         "five app names the policy pre-authorises for system privileges (ticket 10)"),
    ],
}

IMAGE_OF = {"/system": "system", "/vendor": "vendor", "/product": "product"}


def parse_packages(text):
    """{package: path} from the device's own 'pm list packages -f' output."""
    out = {}
    for line in text.splitlines():
        line = line.strip().removeprefix("package:")
        if "=" not in line:
            continue
        path, _, name = line.rpartition("=")
        out[name] = path
    return out


def app_dir(path):
    """The directory holding an APK, which is what gets deleted."""
    return path.rsplit("/", 1)[0]


def locate(packages):
    """Which image each app lives in, and the path inside that image."""
    plan, problems = {"system": [], "vendor": [], "product": []}, []
    for pkg, reason in sorted(REMOVE_APPS.items()):
        path = packages.get(pkg)
        if not path:
            problems.append(f"{pkg}: not installed on this unit")
            continue
        for prefix, image in IMAGE_OF.items():
            if path.startswith(prefix + "/"):
                inside = path[1:] if image == "system" else path[len(prefix) + 1:]
                plan[image].append({"path": app_dir(inside), "package": pkg, "reason": reason})
                break
        else:
            problems.append(f"{pkg}: lives at {path}, which is not in an image we rebuild")
    return plan, problems


def check_keeps(plan, packages):
    """No kept app may sit inside a directory the plan deletes."""
    bad = []
    doomed = {(image, e["path"]) for image, es in plan.items() for e in es}
    for pkg in sorted(KEEP_APPS):
        path = packages.get(pkg)
        if not path:
            continue
        for prefix, image in IMAGE_OF.items():
            if path.startswith(prefix + "/"):
                inside = path[1:] if image == "system" else path[len(prefix) + 1:]
                for img, d in doomed:
                    if img == image and (inside == d or inside.startswith(d + "/")):
                        bad.append(f"{pkg} at {path} sits inside {d}, which the plan deletes")
    return bad


def selftest():
    pk = parse_packages("package:/system/app/A/A.apk=com.htc.storeos\n"
                        "package:/product/app/B/B.apk=com.htc.htcotaupdate\n"
                        "package:/system/app/A/C.apk=com.softwinner.awlivetv\n")
    assert pk["com.htc.storeos"] == "/system/app/A/A.apk"
    assert app_dir("/system/app/A/A.apk") == "/system/app/A"
    plan, problems = locate(pk)
    assert {e["path"] for e in plan["system"]} == {"system/app/A"}, plan["system"]
    assert {e["path"] for e in plan["product"]} == {"app/B"}, plan["product"]
    assert any("not installed" in p for p in problems), "missing packages must be reported"
    # The kept app shares directory A with a removed one: that must be caught.
    bad = check_keeps(plan, pk)
    assert bad and "awlivetv" in bad[0], bad
    print("selftest ok")


def main():
    if sys.argv[1:2] == ["--selftest"]:
        return selftest()
    packages = parse_packages(Path(sys.argv[1]).read_text(encoding="utf-8-sig"))
    plan, problems = locate(packages)
    for image, entries in REMOVE_FILES.items():
        plan[image] += [{"path": p, "reason": r} for p, r in entries]
    bad = check_keeps(plan, packages)
    out = {"delete": plan,
           "edit": {img: [{"path": p, "old": o, "new": n, "reason": r} for p, o, n, r in es]
                    for img, es in EDITS.items()},
           "not_found": problems, "would_break_keeps": bad}
    Path(sys.argv[2]).write_text(json.dumps(out, indent=1), encoding="utf-8")
    for image in ("system", "vendor", "product"):
        print(f"=== {image}: {len(plan[image])} paths to delete, {len(out['edit'].get(image, []))} files to edit")
        for e in plan[image]:
            print(f"   - {e['path']:58} {e['reason']}")
        for e in out["edit"].get(image, []):
            print(f"   ~ {e['path']:58} {e['reason']}")
    print(f"\npackages named but not installed: {problems or 'none'}")
    print(f"kept apps the plan would break: {bad or 'none'}")
    if bad:
        raise SystemExit("plan refuses to proceed: it would delete something meant to be kept")


if __name__ == "__main__":
    main()
