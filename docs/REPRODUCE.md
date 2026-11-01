# Doing this to your own HY320

Read all of this before you plug anything in.

## Before anything else

**This was done once, to one projector.** Every command here was run for real
and the results are in [docs/research/](research/), but "it worked on mine" is
the whole of the evidence. There is no test suite and no second unit.

**Your firmware is probably not byte-identical to mine.** These boxes ship under
many names with the same Allwinner H713 board and differing builds. The
partition layout, the package list, even the name of the vendor settings app may
differ. **Nothing here should be flashed without first dumping your own
firmware and comparing it** — step 1 and step 2 exist for exactly that, and if
they disagree with [docs/reference/stock-unit/](reference/stock-unit/) then the
images in step 5 are wrong for your device and you must build your own.

**You can brick it.** The way back is holding the power button while it starts,
which reaches fastboot with no Android running, and writing the original
partition back. That only works if you made the backup in step 2. If you skip
step 2 there is no way back.

**It voids whatever warranty you have**, and it disables the vendor's update
path on purpose.

**What this does not fix** is in the README: Android 11 with security patches
that stopped in February 2022, no DRM keys, no Google Cast.

---

## The three ways into the projector

| Mode | How to get there | What it is for |
|---|---|---|
| Android | switch it on normally | reading partitions back, settings, installing apps |
| Fastboot | `adb reboot bootloader`, **or hold the power button while it starts** | every write |
| Recovery | mains first, then USB, holding the button above HDMI | identifying the chip; it cannot write on this unit |

A quirk worth knowing: after a power cycle the USB port comes up in the wrong
mode and the PC sees nothing. Switch USB debugging off and on again on the
projector. A plain reboot does not need this.

---

## Step 1 — Identify your unit

```bash
export ANDROID_SERIAL=<from: adb devices>
bash scripts/analysis/inventory.sh
```

Compare the result with [docs/reference/stock-unit/](reference/stock-unit/) —
`getprop.txt`, `by-name.txt`, `partitions.txt`, `packages-all.txt`. What matters:

- the board is `sun50iw12p1` (H713) and the build fingerprint matches,
- `by-name.txt` lists the same partitions in the same order,
- `packages-all.txt` contains the same vendor packages.

**If these differ, stop following this document as a recipe** and use it as a
description of a method instead. The reasoning for every removal is in
[clean/clean-plan.json](../clean/clean-plan.json) and
[docs/research/09-sort-components.md](research/09-sort-components.md); you can
redo that work against your own package list.

## Step 2 — Back everything up

This is the step that makes every later one reversible. Do not skip it.

```bash
export HY320_BACKUP=/mnt/d/hy320-backup   # wherever you want ~8 GB to live
python scripts/backup.py                  # full eMMC image + per-partition hashes
```

**`HY320_BACKUP` is how every later script finds your dump.** Nothing in this
repository has a path of its own baked in. The scripts that build and verify the
images run under WSL and want the Linux form (`/mnt/d/...`); the PowerShell ones
want the Windows form. If you set it on the Windows side, add `HY320_BACKUP/p`
to `WSLENV` and WSL translates it for you.

You want the whole `mmcblk0` image (about 7.7 GB on this unit), a `manifest.json`
of per-partition SHA-256s, and a second copy somewhere else. Verify the copy
before you continue — read it back and compare the hash, do not trust that the
write succeeded.

## Step 3 — Relax verification, so a modified system will boot

Android Verified Boot will refuse a system partition you have changed. The
change is one byte in a 128 KB partition and is undone by writing the original
back.

See [docs/research/25-rebuild-verification.md](research/25-rebuild-verification.md)
for what the flag means, then `scripts/verity/`.

## Step 4 — Decide what comes out, and build the cleaned image

[clean/clean-plan.json](../clean/clean-plan.json) is the list from this unit:
what is removed, what is kept, and why for each. Read it rather than running it
blind — it is the part of this project most specific to one firmware.

```bash
bash scripts/clean/run_apply.sh     # builds super-cleaned.img from your dump
bash scripts/verity/build.sh        # new hash trees
bash scripts/verity/build_vbmeta.sh # signed with YOUR key, not mine
```

The AVB key is generated here and never leaves your machine. There is no key in
this repository to use instead; see [EXTERNAL.md](EXTERNAL.md).

## Step 5 — Write it

```bash
fastboot flash super        super-cleaned.img
fastboot flash vbmeta       vbmeta.img
fastboot flash vbmeta_system vbmeta_system.img
fastboot flash vbmeta_vendor vbmeta_vendor.img
```

About seven minutes. Then **read every partition back and compare hashes**:
fastboot reports success even when it has written nothing.

It should boot as before, minus the removed apps, falling back to Android's own
basic home screen because the stock launcher is gone.

**If it does not boot:** hold the power button while it starts for fastboot,
then write back `vbmeta-relaxed.img` (128 KB, undoes only the new hash trees)
or the original container (about seven minutes, undoes everything).

## Step 6 — Confirm what the cleaning did

```bash
bash scripts/clean/verify.sh
bash scripts/clean/find_ports.sh    # nothing should listen that should not
```

Check by hand that keystone from the remote and the HDMI input still work. If
they do not, the vendor settings app is still your fallback until step 10.

## Step 7 — Root, so the modules can be installed

Patch your own `boot_b` with Magisk, as in
[docs/research/30-root.md](research/30-root.md). Keep the original image: it is
the undo.

## Step 8 — Install the apps

```powershell
pwsh scripts/apps/fetch.ps1          # downloads and verifies digest + signer
```
```bash
bash scripts/install_apps.sh         # installs, re-checking each digest
```

Then build the two apps in this repository:

```powershell
pwsh app/build.ps1
pwsh app/build.ps1 -Source ..\keyboard -Apk projector-keyboard-1.0.apk
```

Install both, set `com.hy320.tools/.LauncherActivity` as the home screen, and
enable the keyboard in Android's input settings.

Then the root side — the modules, the two scripts that run from `service.d`, and
the small dex one of them needs:

```bash
bash scripts/install_magisk.sh      # modules, service.d scripts, audioparam.dex
bash scripts/clean/less-surface.sh  # builds the eighth module: seven marker files
adb reboot
```

`install_magisk.sh` reads every file back off the device after pushing it and
stops if one does not match, because `adb push` reports success for a file that
landed nowhere. It also strips carriage returns on the way: Android's shell
stops at the first one, with an error that names a command ending in `\r`.

What ends up installed:

| | |
|---|---|
| `hy320_no_vendor_settings` | hides the vendor settings app |
| `hy320_less_surface` | hides seven unused components that hold `INTERNET` |
| `hy320_no_plain_adb` | closes the factory's open port 5555 — **leave it on** |
| `hy320_adb_wifi` | TLS wireless debugging; the only one meant to be toggled |
| `hy320_miracast` | ships **disabled**; needs an APK of your own, see [EXTERNAL.md](EXTERNAL.md) |

The two adb modules are deliberately separate. A disabled Magisk module does
not run at all, so if closing 5555 lived inside the wireless-debugging toggle,
switching debugging off would hand the factory's open port back.

Wireless debugging is off until you enable `hy320_adb_wifi` in the Magisk app
and reboot. Find the projector with `adb mdns services` — the port is random and
changes every boot — then `adb connect <ip>:<port>`. Only a key the projector
has already authorised can connect. On Windows that discovery is silent unless
you set `ADB_MDNS_OPENSCREEN=1`; `adb mdns check` reporting version `0.0.0` is
the symptom.

## Step 9 — Standby

Seven settings, and this firmware's settings store is modified, so check they
survive a restart: `bash scripts/standby.sh`.

## Step 10 — Probation

Do not put it on your home network yet.

1. On the router: connection logging on, a fixed address for the projector, log
   sent to your PC.
2. Projector on the **guest** network — internet, no reach into your LAN.
3. Collect for seven days and explain every destination.

```bash
python scripts/probation/pull.py     # the projector's own record
python scripts/probation/analyze.py .scratch/probation-log <projector-ip> \
       scripts/probation/expected.txt scripts/probation/ioc.txt
```

`expected.txt` is an allow-list you must edit for your own house — it currently
contains the author's AirPlay sender and video sources as examples. A verdict of
`CHECK` means a person has to decide with the diary; `FAIL` means stop.

**Pass:** every destination accounted for. **Fail:** back offline, investigate.

## Step 11 — Join the home network

Then AirPlay from an iPad works (both ends must share a network), and the Play
Store signs in. See the note on certification in [EXTERNAL.md](EXTERNAL.md).

## Step 12 — Close the storage access, last of all

1. Read every partition back; record the hashes of the finished system beside
   the backup.
2. Write the vendor partition with the storage device set to `0440 root shell`:
   no app can read or write it, the PC still can over USB debugging.
3. Verify, then switch USB debugging off — which also gives the USB port back to
   sticks.

After this, checking integrity means turning debugging on again. Do it last, and
not until the projector has been boring for a while.

Switching USB debugging off ends wireless debugging with it: the two share one
adbd, and there is no way to keep the network one and drop the cable. So this
step is the end of being able to work on the projector, not a step along the
way. Nothing is left exposed by waiting, because the port that was open from the
factory is shut by `hy320_no_plain_adb` from step 8, whatever else is enabled.

---

## Afterwards

- **Keep the browser engine current.** `/product/app/webview` is an ordinary
  updatable component and is what renders untrusted content; it matters more
  than the Android version does.
- SELinux is left permissive. Switching it to enforcing is its own job with its
  own undo, and means rewriting the vendor boot image.
- The verification has no error-correction data. The system is fully checked
  without it; what is missing is repairing a few bad blocks by itself.
