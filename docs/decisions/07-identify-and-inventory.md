# 07 Identify the unit and list what's installed

Type: task
Status: resolved
Blocked by: 03

## Question

Which exact board and firmware does this HY320 run, and what is installed on it? HITL: with the user's yes, turn on USB debugging, connect over the cable with no network, and record the device identity, panel resolution, storage layout and full package list. Read-only otherwise.

## Answer

Read on 2026-10-19 over USB (Wi-Fi off) with [identify.ps1](../../scripts/identify.ps1); raw output in [unit/20261019-222433](../reference/stock-unit).

- Connection: works with a real USB-A to USB-A cable (the first cable/adapter chain carried no data). Windows sees one device, VID 1F3A PID 1001 "HY320", with no extra driver; nothing else appeared.
- Chip and system: Allwinner H713 (sun50iw12p1) confirmed, Android 11, build UI_Veng.projector.20241225.164550, security patch 2022-02-05, 32-bit apps only, "user" build, active slot B.
- Panel: native 1920x1080.
- Identity: the build pretends to be Google's ADT-3 (manufacturer "askey"); the real model shows only in the model name.
- ADB on this unit asks for key approval (unlike the sister units in the research), and the shell is not root. A network ADB port (5555) is preset for when Wi-Fi is on.
- Storage: 7,650,410,496 bytes, 25 partitions (system, product and vendor inside "super"; data in "userdata"). The raw storage node is readable and writable by any app: the backup can read it, and the cleaning must close it. No separate eMMC boot areas are visible.
- Packages: 113, none installed by the user, 2 disabled (MTP, NFC). Known-bad ones present: StoreOS and EventUploadService (in /system), HtcOtaUpdate and SN_and_MAC/writesn (in /product). SilentSDK is not present: in this factory-reset state it has not been downloaded yet, because the projector has stayed offline. Vendor casting stack present: mphotool AirPlay/DLNA/USB cast, htc samescreen, toofifi line server, Allwinner Miracast. Launcher: com.htc.htclauncherhighenglishd08 (/system); vendor settings: com.htc.htcsettings (/product). No com.hysd.vafocus: the automatic keystone component from ticket 04 does not exist on this unit, so where keystone lives goes to ticket 18.
