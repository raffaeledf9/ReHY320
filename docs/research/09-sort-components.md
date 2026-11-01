# 09 Sort every component — findings

What was examined: the golden backup only, on the PC, 2026-10-20. The live partitions were copied out of the image, checked against the recorded hashes, and mounted read-only (no execute, no setuid) inside WSL. Apps were read with the Android SDK tools. Nothing from the image was run, and the projector was not connected.

Scripts used, all in `HY320/scripts/analysis/`: `extract.py`, `parse_super.py`, `analyze.sh`, `collect.sh`, `collect2.sh`, `suspects.sh`, `suspects2.sh`, `props_acl*.sh`, `inspect_apks.ps1`, `shared_uid.ps1`. Raw output: `<backup>\analysis\inventory\`.

## What the backup contains

The 2 GB container holds three file systems for the active half of the device: the Android system (1,045 MB), vendor (115 MB) and product (323 MB), all clean ext4. A leftover copy-on-write area from an earlier update is present but already merged (the update state folder is empty), so the backup holds exactly what the projector runs.

113 apps: 71 stock Android, 5 Google, 37 vendor.

## Good news, measured rather than assumed

- No setuid or setgid programs anywhere in system, vendor or product. The extra root helper reported on sibling models does not exist here.
- No world-writable files in those partitions.
- The `/oem` partition holds only a tilt-sensor calibration file and a media folder. There is no override file that could re-enable anything, and it is mounted without device or setuid rights.
- Google Play Store and Play Services are present, so Netflix and similar apps may behave better than on a device without them.

## Bad news, also measured

- **A root service runs at every boot.** `/system/bin/qw`, started by `qw.rc` as root in the earliest service class, is a renamed copy of the well-known Superuser root daemon (its own text references that project and its control socket). Nothing on the device needs it. Remove the program and its startup file.
- **A silent app installer runs at every boot.** `/system/bin/preinstall` installs any `.apk` it finds in a `preinstall` folder at the top level of any mounted volume, remembering what it already did. Remove the script and its startup file.
- **Two scripts weaken Google's own protection.** `/system/bin/appsdisable` and `/system/bin/gmsopt` run once as root after boot and switch off the startup components of every Google app, which is what disables Play Protect. Remove both and their startup files.
- **A USB customisation path exists.** `/system/bin/replace_file.sh`, triggered by a property, copies a boot logo, a property-override file and apps from a `resource_update` folder on removable media into `/oem`, and writes into the bootloader area. Remove the script and its trigger.
- **The security policy pre-authorises five app names.** The policy file grants system-account privileges to apps named `com.wohuatv.launcher`, `com.ksj.ottgame`, `com.ksj.ott.keep`, `com.ksj.ott.store` and `com.stb.duer.apps.xtvott`. None is installed, but any app with one of those names, dropped into a privileged folder, would gain system rights. Remove those five lines.
- **SELinux is switched off.** The device boots with the kernel setting `permissive`, so the whole mandatory-access-control layer only logs instead of blocking. Whether it can be switched to enforcing without breaking vendor code is a question for ticket 11.
- **Most vendor apps share the system account.** Twenty of them, including the ones below, declare the shared system user, so they cannot be restricted individually: blocking that account would also block Android itself. Anything in this group is either trusted or removed; there is no middle option.
- Three apps fail signature verification outright: the office suite and two of the vendor casting apps.
- All vendor apps are signed with the public Android test keys, so any app signed with those keys would be treated as part of the system. That cannot be fixed by deleting files; it is a reason to keep treating the projector as a low-trust device.

## Proposed keep-list

### Keep: stock Android
All 71 stock packages, except the two the user already disabled (MTP file transfer and NFC), which have no use here and can stay disabled or be removed.

### Keep: Allwinner hardware support
| Component | Why |
|---|---|
| `com.softwinner.awsource`, `com.softwinner.awlivetv`, `com.softwinner.vis` | HDMI input: the source picker, the viewer and the input service |
| `com.softwinner.awmanager`, `com.softwinner.settingsassist`, `com.softwinner.settingssetup`, `com.softwinner.provision` | Small helpers the stock settings rely on; none can reach the network |
| `com.softwinner.tvvolume` | Volume display |
| `com.softwinner.theme.color`, `com.softwinner.theme.icon` | Appearance overlays |
| `com.softwinner.ImageParser`, `com.softwinner.screenshot` | Image handling and screenshots |
| `multi_ir` service and its vendor half | The infrared remote. Essential. |
| `gpioservice`, `isomountservice`, `blank_screen`, `systemmix` | Allwinner system services. `systemmix` runs as root with its own policy label and needs a closer look in ticket 11 before it is kept. |
| All vendor hardware services (display, audio, video, Wi-Fi, Bluetooth, camera, power, thermal, keymaster, Widevine) | The hardware layer |

### Keep with a reason, to be decided in ticket 10
| Component | Why it is a candidate | Catch |
|---|---|---|
| `com.htc.htcsettings` (vendor settings) | Holds the keystone correction screen and the projection settings. See ticket 18. | Shares the system account, asks for internet and 33 permissions. Either it stays as trusted, or ticket 19's own app replaces it. |
| `com.htc.closedialog` | Controls the focus motor | Shares the system account, persistent, asks for network state |
| `com.htc.screensaver` | The screen dimming the user complains about | No permissions at all. Removing it is one way to stop the projector dimming. |
| `com.android.nfx` (Netflix helper) | Remote-control support for the Netflix app the user wants | Not a stock Android app despite the name. No internet permission. |

### Remove: unwanted or hostile
| Component | What it is |
|---|---|
| `com.htc.storeos` | Installs apps without asking |
| `com.htc.eventuploadservice` | Sends usage data out |
| `com.htc.htcotaupdate` | The vendor updater, the channel the rest arrived through |
| `com.hotack.writesn` | Writes the serial number and address; a factory tool with internet access |
| `com.hotack.hotackfeaturestest`, `com.htc.hyk_test` (43 MB), `com.softwinner.dragonbox`, `com.softwinner.dragonatt`, `com.softwinner.agingdragonbox` | Factory test apps, several with full network access |
| `android.rockchip.update.service` | An updater for a different manufacturer's chip, with internet access and system rights |
| `com.softwinner.update` | Second updater |
| `com.htc.htclauncherhighenglishd08` | The stock launcher, to be replaced (the user's decision) |
| `com.android.toofifi` (file `TengYunH713TVApp_HY.apk`), `com.toofifi.lineserver`, `com.mphotool.airplay`, `com.mphotool.dlna`, `com.mphotool.usbcastserver`, `com.htc.samescreen`, `com.softwinner.miracastReceiver` | The whole vendor casting stack, replaced by the open-source AirPlay app. The first one hides behind a stock-looking name. |
| `com.mobisystems.office` (95 MB) | Office suite, fails signature verification |
| `com.softwinner.TvdVideo`, `com.softwinner.TvdFileManager`, `com.android.music` (a Rockchip app), `com.softwinner.awlogsettings`, `com.allwinnertech.packageoverride` | Bloat, replaced by open-source apps |
| Programs: `qw`, `preinstall`, `appsdisable`, `gmsopt`, `replace_file.sh`, `logcatshell.sh` (writes log files to internal storage forever), and the leftover `eshare.sh` and `netflix_copy.sh` (the latter is empty) | See the list above |
| Startup files for all of the above, plus the leftover `iosmain` entry whose program does not exist | |
| The five pre-authorised app names in the policy file | |

### Replace with open-source apps
Launcher (FLauncher), file manager (Material Files), casting (AirPlay Server), plus ticket 19's small app for keystone and shortcuts.

### Undecided, needs ticket 11
Google Play Services, Play Store and the Google service framework. They are the reason Netflix may work better, but they also talk to Google constantly. Keeping them conflicts with a quiet device; removing them may break the streaming apps.

## Open points

- `systemmix` (a 4 KB root program with its own policy label) and `/vendor/bin/dbgserver`, `dom2reg` and `tvserver` were not examined in detail. Ticket 11 should check them before they are kept.
- Whether the system partition can be changed at all without tripping verified boot is ticket 11's first question. The boot state says the device is locked but the trust chain is off.
- Removing the stock launcher and the vendor settings app together would leave no keystone screen until ticket 19's app exists. Order matters in the runbook.
- The empty update-snapshot area could be reclaimed, but touching the partition layout is riskier than leaving 662 MB unused.
