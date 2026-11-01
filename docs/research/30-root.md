# Root on this projector, and the XDA thread that suggested it

## The thread

<https://xdaforums.com/t/root-hy320-rom-alliwava.4789173/> — five real posts.

It is **not a custom ROM**. It is the stock Alliwava/Hotack firmware
(`HY320_user_public_en_E_F_weidong_OTA_2024-11-19-1632.img`) with Magisk already in it,
flashed with Phoenix Suite over FEL (volume up held at power-on). Afterwards the author
re-enables the HTC launcher with MENU, UP, RIGHT, DOWN, LEFT and uninstalls eight
packages: MobiSystems Office, `agingdragonbox`, `dragonbox`, `softwinnerdragon.att`,
`eshare.linedisplay.receiver`, `htc.hyk_test`, `hotack.hotackfeaturestest`, `calculator2`.

Why it was not used:

- Same vendor stack. It keeps `com.htc.htcsettings`, the app we found carrying Baidu
  analytics with the serial and MAC address plus a RecoverySystem update path, and it
  touches none of the native services.
- Three of its eight removals overlap ours; this projector had twenty-six packages removed
  plus the root daemon, the silent installer, the two scripts that disabled Google's
  protection, `dbgserver` and the sound-trigger listener, each verified by reading the
  partitions back.
- No independent confirmation: three of the five posts are people asking for working
  re-uploads, and there is not one report of a successful flash, nor anything about what
  works or breaks.
- An unverified multi-gigabyte image from a stranger's Drive or MediaFire, on the one
  device whose whole purpose is being trustworthy.
- Its flashing route may not even work here: this unit's FEL can read and write memory but
  **cannot execute code**, and Phoenix Suite depends on executing a loader.

## What was taken from it

The idea of root, applied to our own boot image.

| Fact | Value |
|---|---|
| `boot_b` | sector 336896, 64 MB, header v3, kernel 21,971,244, ramdisk 13,710,626 |
| `init_boot` | none (Android 11) |
| Layout | virtual A/B, dynamic partitions, active slot `_b` |
| Magisk | v30.7, official release, ships `armeabi-v7a`, which is all this unit has |
| AVB | not enforced: vbmeta signed with **our own** key already boots |
| SELinux | permissive already, so `magiskpolicy` had nothing to fight |

Patched on the projector with `boot_patch.sh` and the five `armeabi-v7a` binaries from the
APK, `KEEPVERITY=true KEEPFORCEENCRYPT=true PATCHVBMETAFLAG=false RECOVERYMODE=false
LEGACYSAR=false`. Magisk chose `metadata` as its pre-init partition.

The three `Failed to patch` lines it printed are the Samsung-only kernel hexpatches (RKP,
defex, `proca_config`), whose byte patterns are absent from an Allwinner kernel.

## What root was actually for

1. **Live keystone.** The compositor takes the private call only from the system; an
   ordinary app is refused with `Permission Denial: can't access SurfaceFlinger uid=10041`.
   Through superuser it goes through. See [29-keystone-mechanism.md](29-keystone-mechanism.md).
2. **Removing the vendor settings app** with a Magisk module instead of a twenty-one
   minute container write, reversibly and without touching a partition.
3. Still available if wanted: per-app network rules, installing our own app as a system
   app, and switching SELinux to enforcing.

## The cost, stated plainly

Root is a standing privilege: anything that gets code execution on the projector can ask
for it. Today nothing listens but AirPlay and Magisk prompts per app, but it widens what a
break-in could do. It also fails any integrity check, so the Play Store may refuse to work
at all — this unit has no DRM keys anyway. A factory reset will not remove it, since it
lives in the boot image.
