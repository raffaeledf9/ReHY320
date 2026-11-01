# 09 Sort every component

Type: research
Status: resolved
Blocked by: 04, 07, 08

## Question

Going through this unit's golden backup, analysed offline on the PC: which components are stock Android, which are Allwinner hardware support, which vendor parts does a kept feature need, and which are everything else? Produces the proposed keep-list, with the reason for each vendor part kept.

## Answer

The keep-list is proposed in [research/09-sort-components.md](../research/09-sort-components.md).

Measured facts that change the plan: no setuid programs and no world-writable files exist here, `/oem` has no override file, and Play Services and the Play Store are present. But the device boots with SELinux switched off (permissive), a renamed root daemon (`qw`) starts at every boot, a script installs any app it finds in a `preinstall` folder, two scripts disable Google's own protection, a USB customisation path can write into `/oem` and the bootloader area, and the security policy pre-authorises five app names that are not installed. Twenty vendor apps share the system account, so they cannot be restricted individually: each is either trusted or removed.

Keep: all stock Android, the Allwinner hardware support and the infrared remote. Remove: the vendor updaters and store, the data uploader, the factory test apps, the whole vendor casting stack (one of which hides behind a stock-looking name), the office suite, the bloat, and the programs and startup files listed above. Replace: launcher, file manager, casting, plus ticket 19's app. To decide in ticket 10: the vendor settings app (it holds the keystone screen), the focus-motor helper, the screensaver (the cause of the dimming), the Netflix remote helper, and whether Google Play Services stay.
