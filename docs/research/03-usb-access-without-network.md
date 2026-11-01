# 03 USB access without a network: findings

Ticket: [03 USB access without a network](../decisions/03-usb-access-without-network.md). Researched 2026-10-19. Web research only. Nothing was downloaded, installed or run, and no device was touched.

Confidence: **High** means a primary source says so for this chip or this tool. **Medium** means a primary source says so for a sister H713 unit (HY300 Pro+, HY310), or it is a strong inference from source code. **Low** means a single forum report, or an inference that still needs checking. Lines marked *(reasoning)* are my own conclusions with no source behind them.

## Short answer

All three connections use the **same cable and the same port**: a USB-A to USB-A cable from any PC USB port to the projector's own USB-A port. That port is the chip's OTG port, the only one that can act as a USB *device* towards a PC. Normally it is a *host* port for USB sticks.

| Mode | How you get there | What the projector needs | What the PC needs | Read-only check that proves it |
|---|---|---|---|---|
| **Normal debugging (ADB)** | Normal boot | Developer options on, **USB debugging on** (the one allowed settings change), "Allow USB debugging?" accepted with the remote | Platform-tools `adb`. Driver: maybe none (see below), else the Google USB Driver | `adb devices -l` shows the unit as `device` |
| **Fastboot** | `adb reboot bootloader` | Nothing extra | Platform-tools `fastboot`. Driver: probably the Google USB Driver, installed by hand | `fastboot devices`, then `fastboot getvar ...` |
| **FEL (the chip's USB recovery mode)** | Unplug power, hold the button above the HDMI port, plug power in, release after about 2 s. Alternatives: hold Vol+ on the remote at power-on, or `fastboot oem efex` from fastbootd | Nothing. It lives in the chip's ROM | Nothing for the first check. For the full check: the patched open-source `sunxi-fel`, which is a Linux build, so it runs in WSL 2 through usbipd-win | Windows lists `USB\VID_1F3A&PID_EFE8`. Then `sunxi-fel version` prints `AWUSBFEX soc=00001860(H713)` |

**Full copy:** with ADB working, the PC reads the whole eMMC through the cable and writes it straight to a file on the external drive, which is plugged into the PC, not the projector. Run it in **cmd.exe**, not Windows PowerShell 5.1, because 5.1 corrupts binary output. Then verify:

- the file size is exactly the eMMC size;
- the SHA-256 hash of every partition matches what the projector reports for the same sectors (only the partitions Android writes to while running may differ);
- the hash of the file itself becomes the golden checksum.

The rest of this file gives the detail and the evidence.

## The cable and the port (shared by all three modes)

- **Cable.** The H713 tools document a USB A-to-A cable between the projector and the PC for FEL ([well0nez FLASHING.md](https://github.com/well0nez/allwinner-h713-linux/blob/main/FLASHING.md), [androidpctv HY300/HY320/L018](https://androidpctv.com/firmware-magcubic-hy300-hy320/)). High.
- **Take a cable with the power wire (VBUS) cut, if you can get one.** The installer's own FEL instructions say: "It takes a USB A-to-A cable whose power wire is cut" ([h713/fel.py](https://raw.githubusercontent.com/well0nez/allwinner-h713-linux/main/installer/h713/fel.py)). Medium. The same project's FLASHING.md instead says the device "is powered from USB" through the A-to-A cable, so a switched socket will not restart it and you must unplug the cable first ([FLASHING.md](https://github.com/well0nez/allwinner-h713-linux/blob/main/FLASHING.md)). The HY300 Pro+ notes show the same thing: with only the A-A cable connected and no mains power, a red LED comes on ([probonopd gist](https://gist.github.com/probonopd/3ad6b7777caea1503f00d5fe7710ad06)). So a normal A-A cable joins the PC's 5 V supply to the projector's. A cut-VBUS cable avoids that and lets a plain power-off actually power it off. *(reasoning)* Whether ADB still connects over a cut-VBUS cable in normal boot is not documented. Check it on the unit.
- **Which projector port.** It is the rear USB-A port. On the HY300 family that is the only USB port ("the projector's rear USB-A port", [lolmam USB_BURN_GUIDE](https://github.com/lolmam/HY300-H713-Research/blob/main/Firmware/USB_BURN_GUIDE.md)). The factory sheet lists one "USB" for the HY320 (earlier research, [02a](02a-feasibility-data.json)). Medium. FEL always shows up on the chip's OTG connector ([linux-sunxi FEL](https://linux-sunxi.org/FEL), seen in search results only, because the page returns 403), and FEL works over this port on sister units. So this port is the OTG one. Medium.
- **Which PC port.** Any USB port. An older Allwinner guide recommends USB 2.0 ports for Allwinner tools ([androidpctv Allwinner guide](https://androidpctv.com/firmware-update-guide-for-tv-box-with-allwinner-soc/), via [02a](02a-feasibility-data.json)). Low. Plug in directly, not through a hub *(reasoning)*.

## 1. Normal debugging (ADB) over the cable

**Settings on the projector**

- Enable Developer options by tapping **Build number** seven times in About. Then turn on **USB debugging** under Developer options ([Android: developer options](https://developer.android.com/studio/debug/dev-options), [Android: adb](https://developer.android.com/tools/adb)). High. On the HY300 Pro+, Developer mode came from tapping the model name in About ([probonopd gist](https://gist.github.com/probonopd/3ad6b7777caea1503f00d5fe7710ad06)). Low. Where it sits on the HY320 has to be found on the unit.
- **Turning on USB debugging turns off the USB port for sticks, mice and keyboards.** On the HY300 Pro+, with USB debugging on, "USB peripherals like network, mouse, keyboard then won't work anymore" ([probonopd gist](https://gist.github.com/probonopd/3ad6b7777caea1503f00d5fe7710ad06)). Medium. That fits the vendor switching the only port from host to device role, the way older Allwinner boards switch it through a sysfs node (`usb_device` / `usb_host`, [PINE64 forum](https://forum.pine64.org/showthread.php?tid=5611)). Low, inference. Consequences:
  - While ADB is in use, nothing can be plugged into the projector. That includes the external drive, which is why the backup goes through the PC.
  - Turn USB debugging off again afterwards to get USB media playback back *(reasoning)*.
- The first connection shows an RSA prompt on the projector ([Android: adb](https://developer.android.com/tools/adb)). Accept it with the remote and tick "always allow". The earlier research found that if the vendor's SystemUI lacks this dialog, the request queues and is never shown, so `adb` stays `unauthorized` ([02b](02b-planning-facts-data.json)). Medium. On sister units the stock firmware runs ADB with no authentication at all ([02a](02a-feasibility-data.json)); if the HY320 does the same, no prompt appears and the unit shows as `device` straight away *(added by the checker)*.

**Driver on the PC**

- Android 11's `adbd` itself sends Microsoft OS descriptors. These declare the compatible ID `WINUSB` and the ADB interface GUID `{F72FE0D4-CBCB-407D-8814-9ED673D0DD6B}` ([AOSP android11 usb_ffs.cpp](https://android.googlesource.com/platform/system/core/+/refs/heads/android11-release/adb/daemon/usb_ffs.cpp)). High. Since Windows 8, a device that reports `WINUSB` gets the in-box WinUSB driver with no INF ([Microsoft: WinUSB device](https://learn.microsoft.com/en-us/windows-hardware/drivers/usbcon/automatic-installation-of-winusb)). High. So **ADB may work on Windows 11 with no driver install**, but only if the vendor's USB setup turns on the "OS descriptors" switch of the USB gadget (`os_desc/use`, `qw_sign`, `b_vendor_code`, [kernel configfs ABI](https://www.kernel.org/doc/Documentation/ABI/testing/configfs-usb-gadget)). AOSP's generic `init.usb.configfs.rc` does not set it ([AOSP android11](https://android.googlesource.com/platform/system/core/+/refs/heads/android11-release/rootdir/init.usb.configfs.rc)); Google's own Pixel device files do ([crosshatch init.hardware.usb.rc](https://android.googlesource.com/device/google/crosshatch/+/9c3f15462f57e9ebcc941c47ca03daf49176e4d3/init.hardware.usb.rc)). Whether the HY320's vendor files do is unknown, so check it on the unit. Low. *(Corrected by the checker: was "probably works", Medium.)*
- If Device Manager instead shows the device with a yellow mark under "Other devices", install Google's official **Google USB Driver** by hand: Update driver, then Browse my computer, then the `usb_driver` folder ([Android: OEM USB drivers](https://developer.android.com/studio/run/oem-usb), [Android: Google USB Driver](https://developer.android.com/studio/run/win-usb)). High that this is the official procedure. Google says the driver is for Google devices and that editing its INF for other devices triggers security warnings ([same pages](https://developer.android.com/studio/run/oem-usb)). Forcing it onto an Allwinner device is common practice but not documented by Google. Low.
- **Do not use Zadig for ADB or fastboot.** Both `adb` and `fastboot` on Windows look for devices only under the ADB interface class GUID (`AdbEnumInterfaces(ANDROID_USB_CLASS_ID ...)`, [AOSP fastboot usb_windows.cpp](https://android.googlesource.com/platform/system/core/+/refs/heads/main/fastboot/usb_windows.cpp)). High. A generic WinUSB install from Zadig would most likely register a different GUID, so `adb` and `fastboot` would not see the device. Medium, inference.

**Read-only check:** `adb devices -l` lists the unit as `device`. `offline` means not responding ([Android: adb](https://developer.android.com/tools/adb)), and `unauthorized` means the PC's key was not accepted ([AOSP adb keystore.md](https://android.googlesource.com/platform/packages/modules/adb/+/fdbd8a5f/docs/dev/keystore.md)). High. Use `adb -d` to address the USB device ([same](https://developer.android.com/tools/adb)).

## 2. Fastboot

- **Enter:** `adb reboot bootloader` ([AOSP: flashing devices](https://source.android.com/docs/setup/test/running)). High. The HY300 Pro+ Magisk guide uses exactly this, then `fastboot devices`, and leaves with `fastboot reboot` ([lolmam MAGISK_GUIDE](https://github.com/lolmam/HY300-H713-Research/blob/main/Root/MAGISK_GUIDE.md)). Medium for the HY320.
- **Which fastboot you are in:** `fastboot getvar is-userspace` returns `no` in the bootloader's fastboot and `yes` in fastbootd, the one inside recovery ([AOSP fastbootd](https://source.android.com/docs/core/architecture/bootloader/fastbootd)). High. Record it, because `oem efex` and `adb reboot fastboot` behave differently in each.
- **Read-only checks:** `fastboot devices`, then `fastboot getvar product`, `getvar secure`, `getvar unlocked`, `getvar current-slot`, `getvar is-userspace`. On the HY300 Pro+ it reports `secure: yes`, `unlocked: no` ([lolmam FASTBOOT_RESEARCH](https://github.com/lolmam/HY300-H713-Research/blob/main/Boot/FASTBOOT_RESEARCH.md)). Medium.
- **Never run these in fastboot:**
  - `fastboot oem lock`, because it "executes a wipe of userdata";
  - anything that targets slot `_b`, such as `set_active b`, because the `_b` partitions are zero-filled placeholders, so the unit would not boot;
  - `flash`, `erase`, `-w` and `oem unlock`

  ([lolmam FASTBOOT_RESEARCH](https://github.com/lolmam/HY300-H713-Research/blob/main/Boot/FASTBOOT_RESEARCH.md), [02a](02a-feasibility-data.json)). Medium.
- **Driver:** Google does not document fastboot drivers for non-Google devices. The vendor bootloader's USB IDs are unknown. Expect the same choice as for ADB: no driver if Windows matches it by itself, else the Google USB Driver's "Android Bootloader Interface" by hand. Low. Check on the unit by reading the hardware ID in Device Manager while in fastboot.
- **Leave:** `fastboot reboot` ([lolmam MAGISK_GUIDE](https://github.com/lolmam/HY300-H713-Research/blob/main/Root/MAGISK_GUIDE.md)). Medium.

## 3. FEL, the chip's USB recovery mode

**What it is:** a routine in the chip's BootROM for programming and recovery over USB. It cannot be erased by software. The chip enters it when a button is held at power-on, or by itself when no valid boot image is found ([linux-sunxi FEL](https://linux-sunxi.org/FEL), search results only; "FEL is in the BROM and cannot be bricked from software", [well0nez](https://github.com/well0nez/allwinner-h713-linux/blob/main/FLASHING.md) via [02a](02a-feasibility-data.json)). High.

**How to enter it** (no settings needed on the projector):

1. **Button.** Unplug the power, hold the button, plug the power in, keep holding about two more seconds, then let go. "The device stays dark while it does -- that is how it should be" ([h713/fel.py](https://raw.githubusercontent.com/well0nez/allwinner-h713-linux/main/installer/h713/fel.py), HY310 "reset button"). For HY300/HY320/L018 the button is "above the HDMI port", pressed with a paperclip, with the A-A cable connected before power ([androidpctv](https://androidpctv.com/firmware-magcubic-hy300-hy320/)). Medium for the HY320.
2. **Remote.** Hold **Vol+** during power-on until the PC detects the device ([lolmam UART_FEL](https://github.com/lolmam/HY300-H713-Research/blob/main/Hardware/UART_FEL.md), [BOOT_MODES](https://github.com/lolmam/HY300-H713-Research/blob/main/Boot/BOOT_MODES.md)). Medium. **Do not hold Home at power-on.** On the HY300 Pro+ it "triggers an automatic factory data wipe" ([BOOT_MODES](https://github.com/lolmam/HY300-H713-Research/blob/main/Boot/BOOT_MODES.md)). Medium.
3. **From fastbootd:** `fastboot oem efex` reboots into FEL ([FASTBOOT_RESEARCH](https://github.com/lolmam/HY300-H713-Research/blob/main/Boot/FASTBOOT_RESEARCH.md)). It works by setting the Android property `sys.powerctl` to `reboot,efex`, and lolmam's FEL page names it as a command of "userspace fastbootd" ([UART_FEL](https://github.com/lolmam/HY300-H713-Research/blob/main/Hardware/UART_FEL.md)). So reach it with `adb reboot fastboot`, not `adb reboot bootloader`. Medium. *(Corrected by the checker: was "from fastboot".)* Prefer the button: it needs no running software and is the route you will need when nothing boots *(reasoning)*.
4. A fourth route reported on the HY300 Pro+: no mains power, A-A cable only (the projector is powered by the PC), then press the power button ([probonopd gist](https://gist.github.com/probonopd/3ad6b7777caea1503f00d5fe7710ad06)). Low. It needs a cable that carries power.

**Read-only proof, in two steps**

1. **Without any tool.** In FEL the chip shows up as USB `1f3a:efe8` ([lolmam FEL_RESEARCH](https://github.com/lolmam/HY300-H713-Research/blob/main/FEL/FEL_RESEARCH.md); dmesg reads "sunxi SoC OTG connector in FEL/flashing mode", [probonopd gist](https://gist.github.com/probonopd/3ad6b7777caea1503f00d5fe7710ad06)). High. On Windows, Device Manager or PowerShell already shows it, even with no driver: `Get-PnpDevice -PresentOnly | Where-Object InstanceId -like '*VID_1F3A&PID_EFE8*'` ([Microsoft: Get-PnpDevice](https://learn.microsoft.com/en-us/powershell/module/pnpdevice/get-pnpdevice)). High. This proves that the BootROM answered the PC over this cable and port.
2. **Handshake with the chip.** Run `sunxi-fel version`. The man page says it "prints some static data, among other things containing the detected SoC", and so it only reads ([sunxi-fel(1)](https://manpages.debian.org/bookworm/sunxi-tools/sunxi-fel.1)). High. On the H713 you need the patched build: stock `sunxi-fel` times out on the H713 ([lolmam FEL_RESEARCH](https://github.com/lolmam/HY300-H713-Research/blob/main/FEL/FEL_RESEARCH.md), [FLASHING.md](https://github.com/well0nez/allwinner-h713-linux/blob/main/FLASHING.md)). The patched build comes from the GPL fork [YuujiLab/sunxi-tools](https://github.com/YuujiLab/sunxi-tools), or as the `sunxi-fel` asset of the well0nez releases. That asset is "the FEL tool for x86-64 Linux ... Needs libusb-1.0", and **there is no Windows build** ([releases](https://github.com/well0nez/allwinner-h713-linux/releases)). High.
   - **Expected output:** `AWUSBFEX soc=00001860(H713) ...`. The fork's SoC table has `0x1860 /* Allwinner H713 / sun50iw12p1 */`, while `0x1855` is the A133 ([soc_info.c](https://raw.githubusercontent.com/YuujiLab/sunxi-tools/master/soc_info.c)). The installer aborts unless it sees `00001860` ([fel.py](https://raw.githubusercontent.com/well0nez/allwinner-h713-linux/main/installer/h713/fel.py)). High for what the tools say; Medium that the HY320 prints it, because lolmam reports `00001855` (see Corrections).
   - **On this PC:** run it in WSL 2 Ubuntu, after handing the USB device over with the open-source **usbipd-win**, which is GPL-3.0 and documented by Microsoft. In an admin PowerShell: `usbipd list`, `usbipd bind --busid <id>`, then `usbipd attach --wsl --busid <id>`. Then `lsusb` in Ubuntu should show `1f3a:efe8` ([Microsoft: connect USB to WSL](https://learn.microsoft.com/en-us/windows/wsl/connect-usb)). High for the procedure. Requirements: Windows 11, the distro set to WSL 2, and kernel 5.10.60.1 or newer ([same](https://learn.microsoft.com/en-us/windows/wsl/connect-usb)). Two cautions:
     - The usbipd install adds a firewall rule that lets "all local subnets" connect to the service on TCP port 3240 ([same](https://learn.microsoft.com/en-us/windows/wsl/connect-usb), [usbipd-win](https://github.com/dorssel/usbipd-win)). Narrow or remove that rule, because the PC is on the home LAN *(reasoning)*.
     - Whether usbipd can share a device that Windows has no driver for, such as the FEL device, is not documented. Low.
   - **Native Windows instead:** this would need a Windows build of the patched `sunxi-fel` (none is published) plus a WinUSB driver bound to `1f3a:efe8` with Zadig. Zadig is GPLv3 and libwdi-based ([Zadig](https://zadig.akeo.ie/)), and WinUSB is what libusb recommends ([libusb Windows wiki](https://github.com/libusb/libusb/wiki/Windows)). High for the drivers. Not recommended: it means building the tool yourself.
   - Only `version`, `sid`, `-l`, `read` and `hexdump` read without changing anything ([sunxi-fel(1)](https://manpages.debian.org/bookworm/sunxi-tools/sunxi-fel.1)). `uboot`, `write`, `exec`, `reset64` and the `spiflash-*` commands load or run code, so they are not part of the read-only check.

**Leave FEL:** cut the power. If the cable carries power, unplug the cable too, then power on normally ([FLASHING.md](https://github.com/well0nez/allwinner-h713-linux/blob/main/FLASHING.md)). FEL runs from RAM and keeps nothing *(reasoning, consistent with "not one byte onto the eMMC" in [fel.py](https://raw.githubusercontent.com/well0nez/allwinner-h713-linux/main/installer/h713/fel.py))*.

**What this proof does not show** (matters for the safety gate in ticket 08): it shows that the ROM answers, not that the golden backup can be written back.

- A raw `dd` image cannot go back through PhoenixSuit, which writes IMAGEWTY `update.img` files ([02a](02a-feasibility-data.json)).
- The open-source way back is to load a U-Boot into RAM over FEL that "lets it expose the eMMC as a USB drive", then write the image to that drive ([h713-install](https://raw.githubusercontent.com/well0nez/allwinner-h713-linux/main/installer/h713-install)). That U-Boot is built for the HY310, and wrong DRAM settings can hang (in RAM only) ([02a](02a-feasibility-data.json)). It has never been tried on an HY320.
- A RAM-only middle step exists: `u-boot-h713-probe.bin`, "the read-only probe for H713 boards nobody has measured yet" ([releases](https://github.com/well0nez/allwinner-h713-linux/releases)). It still runs code on the unit, so it is a decision for ticket 08, not part of this read-only check.

**Why not PhoenixSuit.** It is Allwinner's closed-source Windows flasher. I found no official Allwinner download page; guides send you to board vendors' pages or mirrors ([Radxa](https://docs.radxa.com/en/cubie/a5e/other-system/android/install-system/emmc), search). Low. Radxa says you must disable all Core Isolation options before its driver installs ([Radxa](https://docs.radxa.com/en/cubie/a5e/other-system/android/install-system/emmc)). Medium. That fails the "official or open-source" rule and would weaken the PC's security, and none of the checks above needs it.

## 4. Full copy straight to the external drive, and how to verify it

**Prerequisites**

- The external drive is plugged into the PC, because the projector's port is busy as the ADB device. It must be formatted **NTFS or exFAT**, with at least 8 GB free. FAT32 caps a file at 4 GiB ([Microsoft: file system comparison](https://learn.microsoft.com/en-us/windows/win32/fileio/filesystem-functionality-comparison)). High. The eMMC is 7,818,182,656 bytes on the HY300 Pro+ ([lolmam EMMC_DUMPING](https://github.com/lolmam/HY300-H713-Research/blob/main/Firmware/EMMC_DUMPING.md)). Medium for the HY320.
- **Readability.** On the HY300 Pro+ the shell user can read `/dev/block/mmcblk0` without root, while the per-partition nodes are not readable ([EMMC_DUMPING](https://github.com/lolmam/HY300-H713-Research/blob/main/Firmware/EMMC_DUMPING.md), [02a](02a-feasibility-data.json)). well0nez reports the same for stock Magcubic firmware ([magcubic-root](https://github.com/well0nez/magcubic-root)). Medium. If this is not true on the HY320, the ADB route is closed and only the FEL route below is left.
- **It is also writable** (`rw-rw-rw-`, no root needed, [magcubic-root](https://github.com/well0nez/magcubic-root)). So a typo that puts the eMMC after `of=` instead of `if=` overwrites the internal storage at once. Only ever use `/dev/block/...` after `if=` *(added by the checker)*.
- **`mmcblk0` is not the whole chip.** eMMC hardware boot areas appear separately as `/dev/mmcblk0boot0` and `/dev/mmcblk0boot1`, read-only by default ([Linux kernel: MMC partitions](https://docs.kernel.org/driver-api/mmc/mmc-dev-parts.html)). High. The earlier research only copied `mmcblk0`. Check whether these exist and are readable, and copy them too.

**Commands** (read-only on the projector)

Look first:

```
adb -d shell ls -l /dev/block/mmcblk0 /dev/block/mmcblk0boot0 /dev/block/mmcblk0boot1
adb -d shell cat /sys/block/mmcblk0/size
```

The second command gives the sector count. Multiply by 512 for bytes ([EMMC_DUMPING](https://github.com/lolmam/HY300-H713-Research/blob/main/Firmware/EMMC_DUMPING.md)).

Copy. Type this in **cmd.exe**, where `E:` is the external drive:

```
adb -d exec-out "dd if=/dev/block/mmcblk0 bs=1M 2>/dev/null" > <backup>\mmcblk0.img
```

Repeat for `mmcblk0boot0` and `mmcblk0boot1` if they are readable.

Why it is written this way:

- **`exec-out`, not `shell`.** `exec-out` returns raw data ([Android: adb](https://developer.android.com/tools/adb)). High.
- **`2>/dev/null` is required.** Without the shell protocol, adbd merges stderr into the same stream ("Raw protocol doesn't support multiple output streams, so combine stdout and stderr", [AOSP shell_service.cpp](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/daemon/shell_service.cpp)). High. `dd` prints its records summary to stderr at the end ([AOSP toybox dd.c](https://android.googlesource.com/platform/external/toybox/+/refs/heads/android11-release/toys/pending/dd.c)), so without the redirect that text ends up inside the image. `status=none` also works ([same](https://android.googlesource.com/platform/external/toybox/+/refs/heads/android11-release/toys/pending/dd.c)). The earlier command in the feasibility report lacks this.
- **cmd.exe, not Windows PowerShell 5.1.** In 5.1, "If you redirect byte-stream data, PowerShell treats the data as strings. This redirection results in corrupted data" ([about_Redirection 5.1](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_redirection?view=powershell-5.1)). High. PowerShell 7.4 and later keep the bytes ([about_Redirection 7.5](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_redirection?view=powershell-7.5)). High. cmd.exe's `>` opens the file and hands it to the program as its output ([Microsoft: command redirection](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-xp/bb490982(v=technet.10))). Medium that this is byte-exact; the checks below catch it if not.

**Verification**

1. **Size.** `(Get-Item <backup>\mmcblk0.img).Length` must equal sectors × 512 exactly. If the file is larger, stderr text got in. If it is smaller, the copy stopped early *(reasoning)*.
2. **Whole-disk hash.** On the projector: `adb -d shell sha256sum /dev/block/mmcblk0`. On the PC: `Get-FileHash <backup>\mmcblk0.img`. Its default is SHA-256 ([Microsoft: Get-FileHash](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/get-filehash?view=powershell-5.1)). `sha256sum`, `dd`, `blockdev` and `cmp` are all in Android 11's toybox ([AOSP toybox Android.bp](https://android.googlesource.com/platform/external/toybox/+/refs/heads/android11-release/Android.bp)). High. If the two hashes match, the copy is proven.
3. **If they differ, compare partition by partition.** They probably will differ: Android keeps writing to its data partitions while it runs, so two reads of a live disk rarely agree *(reasoning)*. Inside `adb -d shell`, hash each partition's sector range from the readable whole-disk node, because the partition nodes themselves are not readable:

   ```
   for p in /sys/block/mmcblk0/mmcblk0p*; do s=$(cat $p/start); c=$(cat $p/size); echo "$(grep PARTNAME $p/uevent) $s $c $(dd if=/dev/block/mmcblk0 bs=512 skip=$s count=$c 2>/dev/null | sha256sum)"; done
   ```

   The start and size files are the ones the Magisk guide uses ([MAGISK_GUIDE](https://github.com/lolmam/HY300-H713-Research/blob/main/Root/MAGISK_GUIDE.md)). Hash the same ranges of the image file on the PC with `dd ... | sha256sum` in Git Bash or WSL. Every partition must match, except the ones Android writes while running. Expect `userdata` (named `UDISK`), `metadata` and `misc`, from the 26-partition layout ([lolmam PARTITION_LAYOUT](https://github.com/lolmam/HY300-H713-Research/blob/main/Firmware/PARTITION_LAYOUT.md) via [02a](02a-feasibility-data.json)). Medium. `media_data` may differ too: it is mounted as `/oem` (FAT, world-writable on sister units, [02a](02a-feasibility-data.json)) *(added by the checker)*. **These must match**, because Android does not write them while running (the first ones) or they exist only on this unit (the last ones): `bootloader_a`, `env_a`, `boot_a`, `vendor_boot_a`, `super`, `dtbo_a`, `vbmeta*`, and the device-unique `private`, `Reserve0_*` and the 1 MiB secure-storage range at LBA 12288, which lies outside any named partition ([FLASHING.md](https://github.com/well0nez/allwinner-h713-linux/blob/main/FLASHING.md) via [02a](02a-feasibility-data.json)). Hash that range the same way with `skip=12288 count=2048`. Record which partitions differed and why.
4. **Golden checksum.** The SHA-256 of the image file is the golden checksum. The compressed second copy on the PC counts as verified only when it decompresses to the same hash (ticket 08) *(reasoning)*.

**Fallback if the shell cannot read `mmcblk0`: copy over FEL.**

- `h713-install dump --full` loads U-Boot into RAM over FEL, exposes the eMMC as a USB drive and copies all of it: "7.3 GB, about 17 minutes".
- It computes a SHA-256, writes a manifest, and checks samples of the dump against the device. A mismatch exits with code 7 ([h713-install](https://raw.githubusercontent.com/well0nez/allwinner-h713-linux/main/installer/h713-install)). High for what the tool does.
- Here nothing is running on the projector, so the copy should be exactly consistent *(reasoning)*.
- Limits on this PC:
  - FLASHING.md asks for Linux, Python 3.9+ and sudo ([FLASHING.md](https://github.com/well0nez/allwinner-h713-linux/blob/main/FLASHING.md)); the script's own header says Linux and Windows with Python 3.9+ ([h713-install](https://raw.githubusercontent.com/well0nez/allwinner-h713-linux/main/installer/h713-install)). Ubuntu 20.04's default `python3` is 3.8, with 3.9 available as a separate package ([Ubuntu: available Python versions](https://documentation.ubuntu.com/ubuntu-for-developers/reference/availability/python/)). High.
  - The Windows path is "untested" ([FLASHING.md](https://github.com/well0nez/allwinner-h713-linux/blob/main/FLASHING.md)).
  - Under WSL the device changes identity mid-run (FEL first, then a USB drive). usbipd must re-attach after "the device resets" ([usbipd-win](https://github.com/dorssel/usbipd-win)), and one report says the stock WSL kernel lacks a USB-drive driver (search result, unverified). Low.
  - It runs HY310-built U-Boot code on an HY320.
  - When a USB drive appears, Windows may mount its FAT partitions. `mountvol /n` turns off automatic mounting of new basic volumes, and it stays off for the whole PC until `mountvol /e` turns it back on ([Microsoft: mountvol](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/mountvol)). High for the command; whether it also covers this removable device is unverified.

  Treat this route as a separate decision, not a default.

**Never do this while backing up:** leave a stick or drive with an `update/` folder in the projector at cold boot. U-Boot's `auto_update_check` will try to flash `update/update.img` from it ([lolmam USB_BURN_GUIDE](https://github.com/lolmam/HY300-H713-Research/blob/main/Firmware/USB_BURN_GUIDE.md)). High.

## Tools, all official or open source

| Tool | Status | Needed for |
|---|---|---|
| Android SDK Platform-Tools (`adb`, `fastboot`) | Official, Google; already on the PC | ADB, fastboot, backup |
| Google USB Driver | Official, Google ([page](https://developer.android.com/studio/run/win-usb)) | Only if Windows does not match ADB or fastboot by itself |
| Windows built-ins: cmd.exe, `Get-FileHash`, `Get-PnpDevice` | Official, Microsoft | Copying, hashing, seeing FEL |
| WSL 2 + usbipd-win | Official Microsoft procedure; usbipd-win is GPL-3.0 | `sunxi-fel version` |
| Patched `sunxi-fel` (YuujiLab fork / well0nez release) | GPL | FEL handshake |
| Zadig (WinUSB) | GPLv3 | Only for a native Windows `sunxi-fel`, which does not exist yet |
| PhoenixSuit | Closed source, no official download found, may need Core Isolation off | **Not used** |
| On the projector: toybox `dd`, `sha256sum` | Part of AOSP | Copy and device-side hashes |

## Corrections to the earlier research

- **FEL SoC ID.** [02a](02a-feasibility-data.json) and lolmam give `0x1855` / `soc=00001855(H713)`. The fork that actually works on the H713 names `0x1860` as the H713 and `0x1855` as the A133, and the installer checks for `00001860` ([soc_info.c](https://raw.githubusercontent.com/YuujiLab/sunxi-tools/master/soc_info.c), [fel.py](https://raw.githubusercontent.com/well0nez/allwinner-h713-linux/main/installer/h713/fel.py)). Expect `00001860`. Medium, not High: the two community sources disagree, upstream sunxi-tools has no `0x1860` entry at all and maps `0x1855` to the A133 ([linux-sunxi soc_info.c](https://raw.githubusercontent.com/linux-sunxi/sunxi-tools/master/soc_info.c)), and only the well0nez tool is reported working on real hardware (HY310 "verified", [README](https://github.com/well0nez/allwinner-h713-linux)). *(Confidence note added by the checker.)*
- **The dump command** in the [feasibility report](../FEASIBILITY.md) needs two fixes: `2>/dev/null` (or `status=none`) on the device side, and cmd.exe instead of Windows PowerShell 5.1 on the PC side. Otherwise the image is silently wrong.
- **The eMMC boot areas** `mmcblk0boot0/1` were not part of the earlier "full" copy.
- **Dumping to a stick plugged into the projector** (lolmam method B) does not fit this plan. With USB debugging on, the only port is no longer a host port (HY300 Pro+ evidence above), and network ADB is ruled out until Clean.

## Can only be confirmed on the unit

1. How many USB-A ports the HY320 has, and that the rear one is the OTG port, which shows up as `1f3a:efe8` in FEL.
2. That USB debugging switches that port to device mode and the PC sees ADB over the A-A cable, including with a cut-VBUS cable.
3. Whether Windows binds ADB (and fastboot) by itself or needs the Google USB Driver, and the USB hardware IDs in each mode.
4. That the "Allow USB debugging?" prompt appears and can be accepted with the remote.
5. That the shell user can read `/dev/block/mmcblk0`, and whether `mmcblk0boot0/1` exist and are readable. Also the eMMC size.
6. That `adb reboot bootloader` lands in fastboot, which kind it is (`getvar is-userspace`), and the `getvar` values.
7. Which FEL entry works on this unit (where the button is, whether Vol+ works) and that `sunxi-fel version` reports `soc=00001860`.
8. Which partitions differ between the live unit and the copy. Only the ones Android writes to may differ.

On the PC, not the unit: whether Ubuntu 20.04 runs as WSL 2 (`wsl -l -v`) with a new enough kernel, and whether usbipd can pass the driverless FEL device through.

## Verification

Independent check, 2026-10-19. I opened every source cited above again and looked for other sources that could prove the claims wrong. Web research only; nothing was downloaded, installed or run. Verdicts: **confirmed** (the source says it and nothing contradicts it), **partly** (true with a correction or a caveat), **refuted**, **unverified** (no source reachable either way).

**Fixed in place** (each marked in the text):

1. ADB with no driver: "probably" became "maybe", Medium became Low. Android's adbd does carry the Microsoft OS descriptors, but Windows sees them only if the vendor's USB setup turns them on, and AOSP's generic setup does not.
2. `fastboot oem efex` works from **fastbootd** (`adb reboot fastboot`), not from the bootloader's fastboot (`adb reboot bootloader`).
3. The FEL SoC ID `00001860` went from High to Medium, with the reason given.
4. "Device-unique regions" was the wrong name for the list of partitions that must match. Most of them are only unchanged while Android runs. Renamed, and `media_data` added to the list that may differ.
5. Added: `mmcblk0` is world-*writable* on stock firmware, so `/dev/block/...` must only ever follow `if=`.
6. Added: on stock sister units ADB has no authentication, so no prompt may appear.
7. `h713-install`: the script says it runs on Linux and Windows; FLASHING.md says Linux. Both are now given.
8. `mountvol /n` stays on for the whole PC until `mountvol /e`.
9. Radxa's Core Isolation advice is not specific to Windows 11. Removed "On Windows 11".
10. `unauthorized` now cites AOSP's keystore.md, because the adb page does not define it.

| # | Claim | Verdict | Note and source |
|---|---|---|---|
| 1 | FEL uses a USB A-to-A cable | confirmed | [FLASHING.md](https://github.com/well0nez/allwinner-h713-linux/blob/main/FLASHING.md), [androidpctv](https://androidpctv.com/firmware-magcubic-hy300-hy320/) ("USB-A to USB-A cable") |
| 2 | Installer wants a cable with the power wire cut; the plain cable powers the unit | confirmed | [fel.py](https://raw.githubusercontent.com/well0nez/allwinner-h713-linux/main/installer/h713/fel.py) "power wire is cut"; FLASHING.md "powered from USB"; [probonopd](https://gist.github.com/probonopd/3ad6b7777caea1503f00d5fe7710ad06) red LED on USB alone. Whether ADB works over a cut cable is still unverified. |
| 3 | The rear USB-A port is the only USB port and the OTG one | partly | lolmam says "rear USB-A port" but gives no port count ([USB_BURN_GUIDE](https://github.com/lolmam/HY300-H713-Research/blob/main/Firmware/USB_BURN_GUIDE.md)); retail listings say "1x USB port". FEL waits for commands on the OTG interface (linux-sunxi [FEL](https://linux-sunxi.org/FEL), search snippet only, page returns 403). That it is the OTG port is an inference from FEL working on it. |
| 4 | Developer options: tap Build number 7 times; USB debugging under Developer options | confirmed | [dev-options](https://developer.android.com/studio/debug/dev-options). The Android TV location is not documented there. HY300 Pro+: tapping the model name ([probonopd](https://gist.github.com/probonopd/3ad6b7777caea1503f00d5fe7710ad06)). |
| 5 | USB debugging makes the port stop working for sticks, mice and keyboards | confirmed (sister unit) | probonopd says so. The host/device sysfs switch is shown on a PINE64 board ([forum](https://forum.pine64.org/showthread.php?tid=5611)); that the HY320 works the same way is still an inference. |
| 6 | Android 11 adbd sends MS OS descriptors (`WINUSB`, GUID `{F72FE0D4-...}`) | confirmed | [usb_ffs.cpp android11](https://android.googlesource.com/platform/system/core/+/refs/heads/android11-release/adb/daemon/usb_ffs.cpp) |
| 7 | So ADB "probably" needs no driver on Windows | partly, **fixed** | Windows loads WinUSB by itself for a `WINUSB` device ([Microsoft](https://learn.microsoft.com/en-us/windows-hardware/drivers/usbcon/automatic-installation-of-winusb)). But the OS string is sent only when the gadget's `os_desc/use` switch is on ([kernel ABI](https://www.kernel.org/doc/Documentation/ABI/testing/configfs-usb-gadget)). AOSP's generic [init.usb.configfs.rc](https://android.googlesource.com/platform/system/core/+/refs/heads/android11-release/rootdir/init.usb.configfs.rc) has no os_desc lines; Pixel's [init.hardware.usb.rc](https://android.googlesource.com/device/google/crosshatch/+/9c3f15462f57e9ebcc941c47ca03daf49176e4d3/init.hardware.usb.rc) adds them. Unknown for the HY320. |
| 8 | Google USB Driver: official, installed by hand, editing the INF gives security warnings | confirmed | [oem-usb](https://developer.android.com/studio/run/oem-usb), [win-usb](https://developer.android.com/studio/run/win-usb) (required for Google devices; other devices use the OEM's driver) |
| 9 | Windows `adb` and `fastboot` find devices only by the ADB interface GUID, so avoid Zadig for them | confirmed (code); inference on Zadig | `AdbEnumInterfaces(usb_class_id ...)` in [fastboot usb_windows.cpp](https://android.googlesource.com/platform/system/core/+/refs/heads/main/fastboot/usb_windows.cpp) and [adb client usb_windows.cpp](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/client/usb_windows.cpp). That Zadig registers a different GUID is still an inference. |
| 10 | `adb devices` states | partly, **fixed** | `offline`/`device` are on [adb](https://developer.android.com/tools/adb). `unauthorized` is not on that page; it comes from [keystore.md](https://android.googlesource.com/platform/packages/modules/adb/+/fdbd8a5f/docs/dev/keystore.md). |
| 11 | RSA prompt on first connection | partly, **caveat added** | True when ADB authentication is on ([adb](https://developer.android.com/tools/adb)). Sister units run ADB with no authentication ([02a](02a-feasibility-data.json)), so the prompt may not appear at all. |
| 12 | `adb reboot bootloader` enters fastboot | confirmed | [AOSP running](https://source.android.com/docs/setup/test/running); used on HY300 Pro+ ([MAGISK_GUIDE](https://github.com/lolmam/HY300-H713-Research/blob/main/Root/MAGISK_GUIDE.md)) |
| 13 | `getvar is-userspace`: `no` in the bootloader, `yes` in fastbootd | confirmed | [AOSP fastbootd](https://source.android.com/docs/core/architecture/bootloader/fastbootd) |
| 14 | HY300 Pro+ fastboot: `secure: yes`, `unlocked: no`; `oem lock` wipes userdata; `_b` partitions are zero-filled | confirmed (single source) | [FASTBOOT_RESEARCH](https://github.com/lolmam/HY300-H713-Research/blob/main/Boot/FASTBOOT_RESEARCH.md), [PARTITION_LAYOUT](https://github.com/lolmam/HY300-H713-Research/blob/main/Firmware/PARTITION_LAYOUT.md). The source does not mention `product` or `current-slot`, and "set_active b would not boot" is an inference. |
| 15 | `fastboot oem efex` enters FEL "from fastboot" | partly, **fixed** | It sets `sys.powerctl` to `reboot,efex` (FASTBOOT_RESEARCH), which is an Android-side mechanism, and [UART_FEL](https://github.com/lolmam/HY300-H713-Research/blob/main/Hardware/UART_FEL.md) names fastbootd. |
| 16 | FEL is in the BootROM and cannot be erased by software | confirmed | FLASHING.md "cannot be bricked from software"; linux-sunxi FEL (snippet) |
| 17 | Button entry: unplug, hold, power in, about 2 s; the unit stays dark; the button is above HDMI | confirmed (sister units) | [fel.py](https://raw.githubusercontent.com/well0nez/allwinner-h713-linux/main/installer/h713/fel.py) (HY310 reset button); [androidpctv](https://androidpctv.com/firmware-magcubic-hy300-hy320/) (paperclip, above HDMI, cable before power). HY320-specific steps are not given. |
| 18 | Remote Vol+ gives FEL; Home gives a factory wipe | partly | Stated in [BOOT_MODES](https://github.com/lolmam/HY300-H713-Research/blob/main/Boot/BOOT_MODES.md) and [UART_FEL](https://github.com/lolmam/HY300-H713-Research/blob/main/Hardware/UART_FEL.md), but with no test method or results shown. Vol+ is a standard Allwinner FEL key (linux-sunxi FEL snippet). Keep Medium for Vol+, and keep the warning about Home. |
| 19 | Power button with only the A-A cable connected | confirmed (single report) | [probonopd](https://gist.github.com/probonopd/3ad6b7777caea1503f00d5fe7710ad06) |
| 20 | FEL device is `1f3a:efe8`; `Get-PnpDevice -PresentOnly` shows it | confirmed | probonopd, [FEL_RESEARCH](https://github.com/lolmam/HY300-H713-Research/blob/main/FEL/FEL_RESEARCH.md); [Get-PnpDevice](https://learn.microsoft.com/en-us/powershell/module/pnpdevice/get-pnpdevice) has `-PresentOnly` and `InstanceId` |
| 21 | `sunxi-fel version` only reads | confirmed | [man page](https://manpages.debian.org/bookworm/sunxi-tools/sunxi-fel.1): it shows the BROM version as static data. `dump` is also read-only and was missing from the list. The `spiflash-*` commands do send code to the chip; not relevant here. |
| 22 | Stock `sunxi-fel` fails on the H713 | confirmed | lolmam: a USB bulk-send timeout; FLASHING.md: the stock tool "does not work here" (it does not say "timeout") |
| 23 | Patched tool from YuujiLab fork / well0nez release, x86-64 Linux only, needs libusb | confirmed | [fork](https://github.com/YuujiLab/sunxi-tools) (GPLv2+, a fork of linux-sunxi); [releases](https://github.com/well0nez/allwinner-h713-linux/releases) v0.95-beta: x86-64 Linux build, needs libusb-1.0; no Windows build listed |
| 24 | Expected `soc=00001860`; lolmam's `00001855` is wrong | partly, **confidence lowered** | YuujiLab `soc_info.c` has `0x1860 /* Allwinner H713 / sun50iw12p1 */`; fel.py aborts if 0x1860 is not found. lolmam prints `soc=00001855(H713)`. Upstream [soc_info.c](https://raw.githubusercontent.com/linux-sunxi/sunxi-tools/master/soc_info.c) has no 0x1860 and calls 0x1855 the A133, so lolmam's label comes from a modified table. 0x1860 is better supported (the tool is "HY310 verified"), but this is not settled. |
| 25 | usbipd-win: GPL-3.0; `list`/`bind` (admin)/`attach --wsl`; Windows 11, WSL 2, kernel 5.10.60.1+; firewall rule for all local subnets, TCP 3240; re-attach after the device resets | confirmed | [Microsoft connect-usb](https://learn.microsoft.com/en-us/windows/wsl/connect-usb), [usbipd-win](https://github.com/dorssel/usbipd-win). Small point: `attach` itself no longer needs admin. |
| 26 | usbipd can pass on a device that has no Windows driver | unverified | No source found either way |
| 27 | Zadig is GPLv3 and based on libwdi; libusb recommends WinUSB through Zadig | confirmed | [Zadig](https://zadig.akeo.ie/), [libusb wiki](https://github.com/libusb/libusb/wiki/Windows) |
| 28 | Read-only FEL commands vs ones that load or run code | confirmed | man page (see 21) |
| 29 | Leave FEL by cutting power (and unplugging a cable that carries power) | confirmed | FLASHING.md: unplug the cable first; the USB-drive mode ends only with a power cycle; fel.py "not one byte onto the eMMC" |
| 30 | `h713-install`: U-Boot over FEL shows the eMMC as a USB drive; `dump --full` "7.3 GB, about 17 minutes"; SHA-256, manifest, sample check, exit code 7 | confirmed | [h713-install](https://raw.githubusercontent.com/well0nez/allwinner-h713-linux/main/installer/h713-install) |
| 31 | `u-boot-h713-probe.bin` is a read-only probe that runs in RAM | confirmed | [releases](https://github.com/well0nez/allwinner-h713-linux/releases) |
| 32 | `h713-install` needs Linux, Python 3.9+, sudo; Windows untested | partly, **fixed** | FLASHING.md asks for Linux, Python 3.9+ and sudo, and says nobody has run the Windows path; the script header says Linux and Windows. |
| 33 | Ubuntu 20.04: default Python 3.8, 3.9 available | confirmed | [Ubuntu](https://ubuntu.com/developers/docs/reference/availability/python/) (the old URL now redirects here); 3.9 is in universe, not main |
| 34 | PhoenixSuit: no official download; Radxa says to turn Core Isolation off | partly, **fixed** | [Radxa](https://docs.radxa.com/en/cubie/a5e/other-system/android/install-system/emmc) says to disable all Core Isolation options, but the page does not say Windows 11 |
| 35 | FAT32 caps files at 4 GiB | confirmed | [Microsoft](https://learn.microsoft.com/en-us/windows/win32/fileio/filesystem-functionality-comparison) |
| 36 | HY300 Pro+ eMMC = 7,818,182,656 bytes; shell user can read `mmcblk0` | confirmed (sister units) | [EMMC_DUMPING](https://github.com/lolmam/HY300-H713-Research/blob/main/Firmware/EMMC_DUMPING.md) (15,269,888 sectors); independently [magcubic-root](https://github.com/well0nez/magcubic-root): `rw-rw-rw-`, no root needed. That the partition nodes are 0600 comes only from [02a](02a-feasibility-data.json); EMMC_DUMPING does not say it. |
| 37 | Boot areas `mmcblk0boot0/1` are separate and read-only by default | confirmed | [kernel MMC doc](https://docs.kernel.org/driver-api/mmc/mmc-dev-parts.html): write access is off by default. EMMC_DUMPING never mentions them, which supports "not part of the earlier copy". |
| 38 | `exec-out` is raw and merges stderr into the data; `dd` writes its summary to stderr; `status=none` exists | confirmed | `exec:` uses `SubprocessProtocol::kNone` ([services.cpp](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/daemon/services.cpp)), and a non-shell protocol merges stderr into stdout ([shell_service.cpp](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/daemon/shell_service.cpp)); android11 toybox [dd.c](https://android.googlesource.com/platform/external/toybox/+/refs/heads/android11-release/toys/pending/dd.c) prints records to stderr and offers `status=none`. lolmam's Method A has no redirect, and it expects the "bytes copied" line, so the correction stands. |
| 39 | Windows PowerShell 5.1 corrupts binary redirection; 7.4+ keeps the bytes | confirmed | [5.1](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_redirection?view=powershell-5.1) says the result is corrupted data; [7.5](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_redirection?view=powershell-7.5) says 7.4 and later keep the bytes (stdout only, not `2>&1`) |
| 40 | cmd.exe `>` is byte-exact | partly | The cited XP page only describes handles; no page says "binary safe". The size and hash checks catch it if this is wrong. Medium is fair. |
| 41 | `Get-FileHash` defaults to SHA-256; toybox has `sha256sum`, `dd`, `blockdev`, `cmp` | confirmed | [Get-FileHash](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/get-filehash?view=powershell-5.1); android11 [Android.bp](https://android.googlesource.com/platform/external/toybox/+/refs/heads/android11-release/Android.bp) (`sha256sum` is a symlink to md5sum.c) |
| 42 | Partition start/size from `/sys/block/mmcblk0/mmcblk0pN/` | confirmed | [MAGISK_GUIDE](https://github.com/lolmam/HY300-H713-Research/blob/main/Root/MAGISK_GUIDE.md) step 2 |
| 43 | 26 partitions, `UDISK`, `metadata`, `misc` | confirmed | [PARTITION_LAYOUT](https://github.com/lolmam/HY300-H713-Research/blob/main/Firmware/PARTITION_LAYOUT.md) |
| 44 | Secure storage at LBA 12288, 1 MiB, outside the partitions; device-only regions | confirmed | FLASHING.md: LBA 12288-14335; device-only: Reserve0_a/b, private, secure-storage |
| 45 | `auto_update_check` flashes `update/update.img` from a stick at cold boot | partly | [USB_BURN_GUIDE](https://github.com/lolmam/HY300-H713-Research/blob/main/Firmware/USB_BURN_GUIDE.md): it looks for `update/auto_update.txt` first, and refuses images that are not newer than `firmware_version`. The warning stays valid: keep sticks out of the projector. |
| 46 | `mountvol /n` disables automatic mounting | confirmed, **fixed** | [mountvol](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/mountvol): new basic volumes only; it is a PC-wide setting, reverted with `/e` |

**Practical notes from the check, no source needed:**

- The partition-by-partition loop reads `super` 512 bytes at a time, so it is slow (millions of reads), but correct.
- cmd.exe's `>` fails if `<backup>` does not exist. Create the folder first.

None of the key claims was refuted. The main corrections are the driver-free ADB claim and the fastbootd route to `oem efex`.
