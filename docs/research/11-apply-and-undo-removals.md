# 11 How removals are applied and undone — findings

Examined in the golden backup on 2026-10-20 with `parse_vbmeta.py`, `vbmeta_key.py`, `extract.py` and read-only mounts. The projector was not connected. Everything marked "to test" needs one careful step on the device, and each of those steps has its undo named here.

## The obstacle: the three partitions we need to change are verified at boot

Android's verified boot covers this firmware completely:

| Protected part | How |
|---|---|
| system, vendor, product | A hashtree over every block (dm-verity). Any changed byte is detected when it is read. |
| boot, vendor_boot, dtbo | A plain hash over the whole image |

The verification data is signed with **the manufacturer's own 2048-bit key**. I compared it against all three of Android's published test keys: no match. So the signature cannot be reproduced, and a modified partition cannot be re-signed to look legitimate. Deleting a file from the system partition therefore cannot be done while verification stays switched on.

That leaves one route, which is the usual one for this family of devices: **relax verification by changing two flags in the verification data, then make the changes.**

- The flags live at a known fixed position in the small `vbmeta` partition (both are off today). Setting them tells Android to skip verification and the hashtree.
- The partition is 128 KB and we hold a byte-exact copy, so the undo is to write the original back.
- This only works if the bootloader itself does not insist on a valid signature. The signs are good: the device reports its trust chain as off and no secure operating system present, and the same has been reported on sibling models. **It is still the single most important thing to test**, and the test is reversible.

If the bootloader turns out to enforce the signature, the project stops at that point and the projector stays as it is: a dormant HDMI-only device. There is no third route, and I would rather say so now than discover it halfway.

## How a change reaches the projector

Three ways to write, in the order the runbook should try them:

1. **Fastboot** (already proven to answer, and it reported the write-protection state as "secure: yes" but gave no lock state). Whether it accepts writes has to be tested.
2. **The chip's recovery mode**, already proven to answer on this unit. Writing through it needs the H713-specific open-source tool rather than the one in Ubuntu's archive.
3. **From Android itself.** The vendor deliberately leaves the raw storage device readable and writable by everyone (`/vendor/ueventd.rc` sets it to 0666), so even an ordinary app can write to it. This is a serious hole and a cleaning item in its own right, but it is also a usable write path for areas that are not currently mounted. The live system partitions cannot be rewritten this way while Android runs on them.

### The safe way to test writing

The partition literally named `empty` is 15 MB of nothing but zeros. Write a recognisable pattern into it, read it back over USB, compare, then write zeros back. That proves the write path with no risk to anything the projector needs, and it is the first device write in the runbook.

## Where the things to delete actually live

| Partition | What goes |
|---|---|
| system (inside the 2 GB container, active half) | The root daemon `qw`, the silent installer `preinstall`, the two scripts that disable Google's protection, the USB customisation script, the logging script, the leftover casting scripts, all of their startup files in `/system/etc/init`, the apps StoreOS and EventUploadService, the stock launcher, the casting apps, the factory test apps, and the five pre-authorised app names in `/system/etc/selinux/plat_seapp_contexts` (lines 4 to 8) |
| product | The vendor updater, the serial-number writer, the factory test apps, the office suite, the Rockchip updater, and later the vendor settings app |
| vendor | One line in `ueventd.rc`, to stop the raw storage being writable by everything |

The file systems are ordinary ext4, and files can be deleted in the extracted images on the PC without mounting them. Nothing is resized, so the container layout stays valid and only the changed partitions need writing back.

## The undo, for every step

Every change is undone by writing the original bytes back from the golden backup, whose per-partition hashes are in `manifest.json`. In order of size: the verification data (128 KB), the vendor partition (115 MB), the product partition (323 MB), the system partition (1,045 MB), or the whole 7.65 GB image as the last resort. Because we hold the entire original, no change in this project is one-way, as long as the projector can still be reached in one of the three ways above.

## What must not be touched

- `private` (16 MB, currently all zeros) and `frp` (36 bytes of content): reserved for device keys and factory-reset protection.
- `Reserve0`: holds a small file system with vendor data.
- `misc`: holds the boot control data that selects which half of the firmware runs.
- `/system/camprjspe.ini`: the projection geometry constants for this exact unit (focal length, offsets, backlight), with its own checksum.
- The 662 MB of leftover update space inside the container: unused, but reclaiming it means touching the layout for no benefit.

## Two findings worth noting

- **No device keys are provisioned.** The partition reserved for the DRM keybox is entirely empty. That independently confirms the expectation that paid streaming on the projector runs at standard definition at best, and it is not something cleaning can change.
- **`permissive` comes from the vendor boot image.** The kernel command line that switches off the mandatory-access-control layer sits in the vendor boot image, which is hash-protected. So switching it to enforcing is possible only after verification is relaxed, and it means rewriting that image. That is ticket 20's decision; my advice is to leave it until the cleaned system has been running for a while, because the vendor's own code has never been tested with that layer switched on, and a device that will not boot is a worse outcome than one with a protection layer in logging mode.

## Order for the runbook

1. Test writing on the `empty` partition, then restore it.
2. Relax verification; reboot; confirm the projector still starts. Undo is in hand.
3. Write the cleaned product partition; reboot; check.
4. Write the cleaned system partition; reboot; check.
5. Write the one-line vendor change.
6. Install the open-source apps, then remove the vendor settings app once its replacement is proven.
7. Only later, and separately: the security settings of ticket 20.

Each step is one write with one undo, and the projector is checked between steps.

## Still to test on the device

- Whether the bootloader accepts relaxed verification data. Everything else depends on this.
- Whether fastboot accepts writes at all on this unit.
- Whether Android's recovery mode offers a USB connection, as a third way in.
- Whether the projector boots with the hashtree ignored (it should, the data simply goes unchecked).

## How the cleaned partitions get written — settled on the device (2026-10-22)

The three partitions to clean live inside the 2 GB `super` container, and this bootloader has no support for writing them individually. The container as a whole is written instead, and fastboot handles the 32 MB transfer limit by itself: it split the 2 GB image into 64 sparse pieces of about 32 MB and wrote them all in roughly six minutes.

Proven by writing the **unchanged** container back and verifying: Android booted, and reading all 2 GB back from the device gave exactly the hash the golden backup records. Nothing changed, and the mechanism is confirmed.

So the procedure is:
1. Modify the extracted file systems on the PC (delete files; nothing is resized, so the container layout stays valid).
2. Rebuild the container image from them.
3. Write it with one fastboot command, which sparsifies it automatically.
4. Reboot, then read the container back and compare its hash with what was written.
5. Undo: write the original container from the golden backup the same way, about six minutes.

A consequence worth stating plainly: once the container holds modified partitions, verification can never be switched back on, because the contents no longer match the manufacturer's signed hashes. Relaxed verification is permanent for this projector from the moment it is cleaned.

## The cleaning was built and checked on the PC (2026-10-22)

Scripts in `HY320/scripts/clean/`: `plan.py` turns the approved keep-list into an exact list of paths, resolving every app through the unit's own package list and refusing to run if a named app is missing or if a kept app would be caught; `apply.py` copies each file system and applies the plan to the copy; `verify.sh` and `verify2.sh` check the result; `zerofree.sh` zeroes the freed blocks. The plan itself is at `clean/clean-plan.json`, and the cleaned images are in `<backup>\cleaned\`. The originals were never touched.

What came out:
- **system**: 19 apps and 13 programs and startup files removed, about 195 MB, and the five pre-authorised app names deleted from the policy file. The file system checks clean and now has 174 MB free where it had almost none.
- **product**: 7 apps removed, about 243 MB, of which the office suite alone was 177 MB. Checks clean, 227 MB free.
- **vendor**: one line changed, so the raw storage device becomes `0440 root shell` instead of readable and writable by every app. Nothing deleted. This file system is completely full, so the edit had to be written in place at the same length rather than rewriting the file, which is now how the script does it.

Checked afterwards, by mounting the cleaned copies read-only: every removal confirmed gone, every item on the keep-list confirmed present (HDMI input, the infrared remote, the display library, the Netflix helper, the Play Store, the vendor settings app, the focus helper), both edits in place, and no pre-authorised names left in the policy.

Two notes carried forward:
- Three startup entries now point at programs that are gone (`eshare.sh`, `netflix_copy.sh`, `replace_file.sh`), because their definitions sit inside the big `init.rc` rather than in files of their own. Harmless: init logs an error and nothing starts. Editing `init.rc` was judged riskier than the benefit.
- Some vendor configuration files still name removed apps (`lmkd_whitelist`, `hideApp.ini`, `config.ini`). Naming an app that is not installed does nothing; left alone deliberately.

Still to do before anything is written to the projector: rebuild the verification data over these images (ticket 25), then rebuild the container and write it.
