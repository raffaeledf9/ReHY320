# 08 Golden backup and recovery check

Type: task
Status: resolved
Blocked by: 03, 07

## Question

Can this unit be fully backed up and recovered? HITL: take the golden backup to the external drive, verify its checksum, make the compressed second copy on the PC, and prove the recovery path and fastboot with read-only checks. Records the backup's location, size, checksum and device identity for the safety gate.

## Progress

Golden backup done and verified on 2026-10-19 with [backup.py](../../scripts/backup.py) (read-only on the projector):
- Image: `<backup>\mmcblk0.img` on an external drive (exFAT). Only that one folder is written to; no other volume on the drive is touched.
- Size 7,650,410,496 bytes; SHA-256 `1c0c36a0f73d85a813df5630ef1fe35f5b0b7b9e81963949a9d9070257a3e77e`.
- Every fixed region (bootloaders, env, boot, vendor_boot, super, vbmeta, dtbo, frp, private, misc, media_data, gaps) matches the projector's own SHA-256 of the same bytes. Only metadata and userdata (also named UDISK) were not compared, because Android rewrites them while running.
- Second copy: `HY320\.scratch\golden\mmcblk0.img.gz` on the PC (1,308,605,921 bytes), verified to decompress to the same SHA-256.
- Manifest with per-region hashes and the device identity: `manifest.json` next to each copy.
- A first run stopped on a script bug (the data partition has two names); fixed, and the existing image was re-verified rather than copied again. Its log is kept as `backup-log-run1-alias-bug.txt`.
- The projector was kept awake during the run with harmless key presses over ADB; no setting was changed.

## Answer

Yes: the unit is fully backed up and both recovery routes answer. Safety-gate status: golden backup verified with a second copy, recovery path proven, fastboot answering, identity recorded (serial and fingerprint in the manifest).

Golden backup: see Progress above (`<backup>\mmcblk0.img`, SHA-256 `1c0c36a0…a3e77e`, compressed copy in `HY320\.scratch\golden`).

Fastboot (2026-10-20, read-only):
- Entered with `adb reboot bootloader`; Windows sees "USB Developer", VID 1F3A PID 1010, and needs Google's USB driver from the Android SDK (`extras\google\usb_driver`), assigned by hand in Device Manager as "Android Bootloader Interface". Done by the user.
- `fastboot getvar`: product = the serial, secure = yes; unlocked, current-slot, is-userspace, version-bootloader and slot-count = "not supported". `fastboot reboot` returns to Android.

Recovery mode (FEL, 2026-10-20, read-only):
- Entry that works: a full cold start. Unplug both power and USB (the USB cable powers the unit, so unplugging power alone is not a restart), hold the button above the HDMI port, plug in USB, then power, keep holding about 3 s. The projector stays dark. Unplugging only the power twice did not work.
- Windows sees VID 1F3A PID EFE8 with no driver; Windows' built-in "WinUsb Device" driver was assigned by hand (done by the user) so usbipd can share it.
- usbipd-win was already installed but too old (2.4.1) for this WSL (3.0.3, kernel 6.18); upgraded to 5.3.0 with winget (installer hash verified; the installer asks for a PC restart to complete).
- Ubuntu's own `sunxi-tools` package (1.4.2) in WSL Ubuntu 20.04 (WSL must be kept running for the attach). `sunxi-fel version` printed `AWUSBFEX soc=00001860(unknown) … scratchpad=00001500`: the chip's ROM answered; 0x1860 is the H713 (the old packaged tool just lacks its name). Writing through FEL would need the H713-specific fork; that belongs to ticket 11.
- Afterwards the device was detached and unshared. usbipd's own firewall rule (inbound TCP 3240, all profiles, local subnet) is still enabled: the user decides whether to disable it between recovery sessions.
- Leaving FEL: unplug power and USB.
