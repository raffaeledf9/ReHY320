# Map: HY320 rework

## Destination

An approved runbook that takes the Dormant HY320 to Deployed: every step decided, the automation scripts specified, every device write paired with its undo. Building and running the scripts follows the runbook, outside this map.

## Notes

- Domain: replacing the software of a consumer Android 11 projector (Allwinner H713 per the order sheet) from a Windows 11 PC with WSL Ubuntu 20.04.
- Vocabulary: use the terms in [GLOSSARY.md](../GLOSSARY.md).
- Skills: HITL tickets call grilling and domain-modeling; research tickets call research; a keystone app, if one is needed, goes through prototype.
- Standing rules live in [01 Charting decisions](decisions/01-charting-decisions.md). Most important: the projector stays offline until Clean, official or open-source tools only, and the user's yes before every device write.
- Execution inside the map: only tickets 07 and 08, and only read-only steps on the projector. The one settings change allowed there is turning on USB debugging, with the user's yes.

## Decisions so far

- [01 Charting decisions](decisions/01-charting-decisions.md): destination, scope, safety rules and network plan from four grilling rounds.
- [02 Feasibility research](decisions/02-feasibility-research.md): AirPlay, APK installs and a clean launcher are feasible; Google Cast is not; the malware needs physical removal before the projector goes online.
- [06 Router facts](decisions/06-router-facts.md): the thirteen settings to read off the router before probation, where each one lives in the stock web page, and what each is needed for.
- [07 Identify the unit and list what's installed](decisions/07-identify-and-inventory.md): H713, Android 11, native 1080p, fake Google ADT-3 identity, ADB needs key approval; malware stage 1 present, SilentSDK not yet downloaded; no auto-keystone component.
- [08 Golden backup and recovery check](decisions/08-golden-backup-and-recovery-check.md): verified 7.65 GB image on the external drive plus a compressed copy on the PC; fastboot answers; recovery mode proven by a cold start with the button; the safety gate's checks all pass.
- [03 USB access without a network](decisions/03-usb-access-without-network.md): one A-to-A link covers debugging, fastboot and recovery mode; the backup only ever reads from the projector's storage.
- [04 How keystone works](decisions/04-how-keystone-works.md): correction happens in Android's display system and auto keystone in a separate vendor component; only the manual screens live in the launcher.
- [05 Netflix casting and app sources](decisions/05-netflix-and-app-sources.md): iPad-to-Chromecast Netflix still works on Standard/Premium plans; projector APKs come from APKMirror with pinned certificates.
- [13 Launcher and file manager](decisions/13-launcher-and-file-manager.md): FLauncher can be the only home app; Material Files works with the remote; HDMI and keystone tiles need a small own app.
- [14 AirPlay Server on this projector](decisions/14-airplay-server.md): version 0.0.36 from GitHub, checked against F-Droid's certificate; very likely fine with iPadOS 26.6.2.
- [16 Probation tooling](decisions/16-probation-tooling.md): router syslog to a small Python receiver on the PC (router-only firewall rule); every destination explained against baseline, expected apps and malware lists.
- [09 Sort every component](decisions/09-sort-components.md): keep stock Android, Allwinner hardware support and the remote; remove the vendor updaters, store, uploader, test apps, casting stack and bloat, plus a root daemon, a silent installer and two scripts that disable Google's protection; SELinux is switched off on this unit.
- [18 Can an own app set keystone and orientation](decisions/18-own-app-keystone-access.md): keystone is four corners held as system properties, so an own app can set them; the screens live in the vendor settings app, not the launcher; automatic keystone has no component on this unit.
- [10 Approve the keep-list](decisions/10-approve-keep-list.md): approved; the vendor settings app goes only once its replacement is proven, Google components stay (Play Store on trial), the screensaver becomes a replaceable image with a 30-minute default timeout, both small helpers stay.
- [11 How removals are applied and undone](decisions/11-apply-and-undo-removals.md): the partitions are verified with the manufacturer's own key, so they cannot be re-signed; the only route is relaxing verification by two flags, then writing cleaned partitions, with the golden backup as the undo for every step. No DRM keys are provisioned on this unit.
- [23 Prove that writing works, reversibly](decisions/23-prove-the-write-path.md): writing works through fastboot, verified by read-back and by restoring a region byte-identical to the backup; fastboot is reachable with no Android by holding the power button at start-up; recovery mode can read but not run code. Step C (relaxing verification) still to do.
- [24 Does the bootloader accept relaxed verification](decisions/24-relax-verification.md): yes. One byte changed, the projector boots normally, and all three protected partitions now mount unverified at full size. The cleaning can go ahead.
- [12 What stays on the finished system](decisions/12-final-system-shape.md): USB debugging off so USB sticks keep working; files reach the projector by it pulling from a read-only share on the PC; no cleaning tools left behind; relaxed verification is permanent.
- [22 Standby, dimming and the screensaver](decisions/22-standby-and-dimming.md): five Android power settings give the behaviour asked for; sleeping off, screensaver on, the "attentive" timer off, and the stay-awake key written explicitly or the screensaver never starts; the image lives in the shared Pictures folder.
- [15 How files and apps reach the projector](decisions/15-install-sessions.md): a dedicated account owns a read-only share on the PC, the projector's file manager pulls from it, no obsolete protocol needed; the installer permission goes to the file manager alone, under "Security and restrictions" on this firmware.
- [25 Rebuild verification with our own key](decisions/25-rebuild-verification.md): reproducible with Google's own tool and our own key; done in two passes, the first writing only the verification partitions to prove the bootloader reports the digest as Android expects.
- Cleaning built and verified on the PC (not yet written to the projector): see [research/11-apply-and-undo-removals.md](research/11-apply-and-undo-removals.md) and the scripts in `HY320/scripts/clean/`. 195 MB removed from system, 243 MB from product, two files edited, every removal and every keep checked.
- Verification rebuilt with our own key and the container rebuilt, both verified on the PC: see [research/25-rebuild-verification.md](research/25-rebuild-verification.md). Ready to write in `<backup>\signed\`.
- The three open-source apps downloaded and checked against their publishers' digests: [research/26-apps-downloaded.md](research/26-apps-downloaded.md).
- The projector's own small app built from source: keystone, projection, screensaver, an HDMI tile, a tile through to Android's settings, and three of the remote's dead keys answered. See [19 Keystone, shortcuts and screensaver app](decisions/19-keystone-and-shortcuts-app.md).
- [27 Could a newer Android go on this projector](research/27-newer-android.md): no. 32-bit only caps a generic image at Android 12, and such an image replaces the system partition where this projector's keystone, focus, remote and HDMI input live.
- [17 Approve the runbook](decisions/17-approve-runbook.md): **approved on 2026-10-22. The destination is reached and this map is complete**; what remains is executing the runbook (the author's execution diary, not published).
- [20 Security settings](decisions/20-security-settings.md): the blocking layer is switched on later as its own step; the open raw-storage access closes as the final change; the pre-authorised app names go with the cleaning. **Revised 2026-10-22:** verification is rebuilt with our own key, there is no root and no debuggable build, and the storage device becomes readable by the PC only (0440 root shell) instead of being closed.

## Open after deployment began

The map was complete when the runbook was approved on 2026-10-22. This was reopened on
2026-10-25, during deployment, because removing the vendor settings app took two of its
features with it.

- [31 Bring back brightness and colour](decisions/31-brightness-and-colour.md): the vendor
  app set them through the projector's own display service (`ITvServer`, with
  `factorySetPanelValue` and `getColorTemperature`), not through properties. The policy on
  this unit already lets an ordinary app reach that service, which is what blocked the
  live keystone, so there is a real route to try; a picture-quality HAL named in the same
  policy is a second, unexplored one. **Answered 2026-10-25: yes, and without superuser.**
  The values sit behind `ITvServer`, getter 98 and setter 97, brightness identifier 1 and
  colour temperature 12; a change made from an ordinary shell was visible on the wall. The
  picture-quality HAL named in the policy does not exist on this unit. **Resolved:** the identifiers were
  told apart on a plain blue screen (2 saturation, 3 contrast, 4 hue, 5 no visible effect),
  and the app now has a Picture screen that needs no superuser.
- Automatic keystone went with the same app and is **not** reopened: it reads the
  time-of-flight sensor from inside that app, so it would have to be rebuilt rather than
  called. Raise it as its own ticket if it is ever wanted.

## Not yet specified

- A fallback way to reach the projector without a network, needed only if USB access fails on this unit.
- A boot helper that keeps the new launcher as home, needed only if the system falls back to something else.
- The full specification of the automation scripts: assembled from the resolved tickets for the runbook.

## Out of scope

- A Google Cast receiver on the projector: the Chromecast on HDMI covers it.
- Replacing the ASUS router: a later recommendation, not this effort.
- Play Store and Google services on the projector.
- Community or vendor firmware images.
- A non-Android operating system.
- Any change to the iPad.
- Building and running the scripts: follows the runbook.
