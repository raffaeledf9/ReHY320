# 13 Launcher and file manager: findings

Researched 2026-10-19 from the web only. Nothing was downloaded, installed or run. Every claim has a source and a confidence mark: **high** means read in source code or official docs; **medium** means a single first-party statement or a sister-device report; **low** means inference or anecdote.

## Short answer

- **Yes, FLauncher can be the only home app.** It declares itself a HOME app, has a 32-bit ARM build, and is built for a remote. Use **osrosal's fork, v2025.07.001**: the original has had no release since April 2023 and shipped Firebase analytics.
- **Settings tile: works.** FLauncher adds one on its own.
- **HDMI and keystone tiles: not automatic.** FLauncher only shows apps that register a normal launcher entry. It cannot open a named screen such as `com.softwinner.awlivetv/.MainActivity`.
  - Option 1: the vendor HDMI app already has a launcher entry. Only the unit can say.
  - Option 2: a tiny open-source shim app with one launcher entry per tile. It fits in the same APK as the keystone app, if that app gets built.
- **Removing the stock launcher: stock Android needs nothing from it beyond some home app.**
  - Settings carries a fallback home screen that hands over to FLauncher at boot.
  - The risks are vendor-specific: the keystone and projection screens, and any vendor service the launcher hosts.
  - Disable it first (reversible) and test. Remove it only after the tests pass.
- **Material Files: usable with the remote, and it installs APKs.**
  - v1.7.5 (Sept 2026) has a TV launcher entry, a fresh D-pad fix, and an "Install" action for APKs.
  - Use the **F-Droid build**: the GitHub build carries Firebase and nags for Google Play services.
- **Projectivy is a workable fallback, but heavier on trust.**
  - In its favour: it is actively maintained, has a 32-bit build, and uses less memory than FLauncher.
  - Against it: it is closed source, uses the network (update checks, wallpapers, and opt-in anonymous usage and crash reports asked at first launch), and offers an optional accessibility service. On the H726 sister firmware its "Inputs" entries could not open HDMI either; expect the same here.

## 1. FLauncher

### Which build

| Build | Latest | Status | 32-bit ARM APK | Notes |
|---|---|---|---|---|
| Original, gitlab.com/flauncher/flauncher | 0.18.0, 2023-04-21 | Last commit 2023-03-03; dead | One universal APK | Ships Firebase analytics and Crashlytics (osrosal's fork lists their removal) |
| **osrosal/flauncher (fork)** | **v2025.07.001, 2025-07-27** | Not archived; last push 2025-07-27; 34 open issues | `flauncher-armeabi-v7a-release.apk` (10.6 MB) | Firebase and Unsplash removed; built and signed by GitHub Actions from the public workflow |
| LeanBitLab/LtvLauncher (fork of osrosal) | pre-release, pushed 2026-10-19 | Active | Yes | Adds weather, data-usage widget, notification overlays and an accessibility service: more network and permissions. Not suited to a low-trust device |

- **Original:** last release 0.18.0 (2023-04-21) and last commit 2023-03-03. **High.** [GitLab releases API](https://gitlab.com/api/v4/projects/flauncher%2Fflauncher/releases), [GitLab commits API](https://gitlab.com/api/v4/projects/26632151/repository/commits?per_page=10)
- **Original README:** names only Google Play as a source, says it was tested only on a Chromecast with Google TV, and calls itself early-stage. **High.** [README](https://gitlab.com/flauncher/flauncher/-/raw/master/README.md)
- **Neither F-Droid nor IzzyOnDroid lists FLauncher** under `me.efesser.flauncher`: both pages return 404. **Medium.** [f-droid.org](https://f-droid.org/en/packages/me.efesser.flauncher/), [IzzyOnDroid](https://apt.izzysoft.de/fdroid/index/apk/me.efesser.flauncher)
- **osrosal releases and repo state:** release v2025.07.001 contains per-ABI and universal APKs. **High.** [GitHub releases API](https://api.github.com/repos/osrosal/flauncher/releases?per_page=5), [repo API](https://api.github.com/repos/osrosal/flauncher)
- **osrosal changelog:** Firebase analytics, Crashlytics and Unsplash removed; Flutter 3.24.5. **High.** [CHANGELOG](https://raw.githubusercontent.com/osrosal/flauncher/master/CHANGELOG.md)
- **osrosal build pipeline:** release APKs are built in GitHub Actions on each push to master and signed with a keystore stored in repository secrets. **High.** [workflow](https://raw.githubusercontent.com/osrosal/flauncher/master/.github/workflows/continuous-release.yml), [build.gradle](https://raw.githubusercontent.com/osrosal/flauncher/master/android/app/build.gradle)
- **No signing fingerprint is published.** Record the certificate SHA-256 on the PC with `apksigner verify --print-certs` before the first install. Android then refuses any later update signed differently. **High** (Android behaviour; no fingerprint found in the repo).
- **Building it yourself in WSL** (Flutter 3.24.5, Java 17, per the workflow) is the most trustworthy option. It costs several GB of SDKs, and the APK is signed with your own key. **Medium.**
- **LtvLauncher:** features and channels as in the table. **Medium.** [repo API](https://api.github.com/repos/LeanBitLab/LtvLauncher), [README](https://github.com/LeanBitLab/LtvLauncher)

### Will it run on this projector

- **Android 11, 32-bit:** minSdk 21 and targetSdk 35, with an armeabi-v7a APK. **High.** [build.gradle](https://raw.githubusercontent.com/osrosal/flauncher/master/android/app/build.gradle), [releases](https://api.github.com/repos/osrosal/flauncher/releases?per_page=5)
  - No report from an H713 or any projector was found. One issue reporter ran it on an Android 11 armeabi-v7a TV (TCL). **Low.** [issue list](https://api.github.com/repos/osrosal/flauncher/issues?state=all&per_page=30&sort=updated)
- **Home app:** the main activity declares MAIN with the HOME, DEFAULT, LAUNCHER and LEANBACK_LAUNCHER categories. It is not direct-boot-aware, which is normal for a launcher. **High.** [manifest](https://raw.githubusercontent.com/osrosal/flauncher/master/android/app/src/main/AndroidManifest.xml)
- **Network:** the release manifest lists only ACCESS_NETWORK_STATE, ACCESS_WIFI_STATE and REQUEST_DELETE_PACKAGES. INTERNET appears only in the debug manifest, where a comment says Flutter needs it for debugging and hot reload.
  - So the release APK probably cannot reach the network at all, which suits probation. **Medium**: plugins could merge permissions in. Confirm on the PC with `aapt2 dump permissions` before install. [debug manifest](https://raw.githubusercontent.com/osrosal/flauncher/master/android/app/src/debug/AndroidManifest.xml), [pubspec](https://raw.githubusercontent.com/osrosal/flauncher/master/pubspec.yaml)
- **Remote:** FLauncher is built for D-pad TV use, and its fork maps Escape to Back. **Medium.** [CHANGELOG](https://raw.githubusercontent.com/osrosal/flauncher/master/CHANGELOG.md)
- **Memory:**
  - In one `top` reading, FLauncher used about 182 MB resident while focused, against about 104 MB for Projectivy. **Medium**, one report; the reporter did not name the device (another commenter in the thread used a Shield).
  - High CPU while focused comes from the card highlight animation. Turning it off in settings cut CPU from up to 60% to about 5%. **Medium.**
  - On 1 GB RAM, turn the animation off. [osrosal #22](https://github.com/osrosal/flauncher/issues/22)
- **Known 2025.07.001 bug:** deleting both default sections can trap navigation until a restart. The reporter went back to v2024.12.004. Clearing app data may also have helped. **Low.** Advice: keep one section, or use v2024.12.004. [osrosal #44](https://github.com/osrosal/flauncher/issues/44)

### Which tiles it can show (from the source code)

- **App list:** built from two queries, one for `CATEGORY_LEANBACK_LAUNCHER` and one for `CATEGORY_LAUNCHER` (the second becomes the "non-TV apps"). Apps open through their package's launch intent. **High.** [MainActivity.java](https://raw.githubusercontent.com/osrosal/flauncher/master/android/app/src/main/java/me/efesser/flauncher/MainActivity.java)
- **Settings:** if neither `com.android.tv.settings` (TV entry) nor `com.android.settings` (launcher entry) is listed, FLauncher adds a Settings tile using `Settings.ACTION_SETTINGS`. That matches H713 builds, whose Settings has no launcher icon ([02b data](02b-planning-facts-data.json), features finding 5). **High.** [MainActivity.java](https://raw.githubusercontent.com/osrosal/flauncher/master/android/app/src/main/java/me/efesser/flauncher/MainActivity.java)
- **No custom tiles:** FLauncher has no pinned shortcuts, no intent URIs and no explicit components. A tile for `com.softwinner.awlivetv/.MainActivity`, or for a vendor keystone activity, is impossible unless that package has a launcher entry. **High** (same file).
- **HDMI options:**
  1. The vendor source picker `com.softwinner.awsource` may already have a launcher entry. On an H726 sister unit it was reachable through Projectivy's "mobile apps" list. **Medium**, sister device. [battleof3](https://github.com/battleof3/magcubic-h726-cleanup)
  2. Otherwise, a shim: an activity with a launcher entry that starts `awlivetv/.MainActivity` (plus `--es input_source HDMI2` if this unit needs it, as the H726 did) and then closes. probonopd wrote one for the HY300 Pro+, but it has **no licence**, so write your own; it is about ten lines. **High** that it exists and is unlicensed. [allwinner-hdmi](https://github.com/probonopd/allwinner-hdmi), [repo API](https://api.github.com/repos/probonopd/allwinner-hdmi)
- **Keystone:** if ticket 04 leads to an own keystone app, give it a launcher entry and FLauncher shows it with no extra work. The HDMI shim can live in the same APK. **High** (follows from the app-list code).
- **File manager:** Material Files registers both LAUNCHER and LEANBACK_LAUNCHER with a TV banner, so it appears as a TV app. **High** (see section 3).
- **LtvLauncher's HDMI selector would probably not help.** On the H726 sister firmware the standard TV-input intents do not open HDMI; that is why Projectivy's "Inputs" fail there. The H713 HY300 Pro+ HDMI app also starts awlivetv by explicit component, which points the same way. **Medium.** [battleof3](https://github.com/battleof3/magcubic-h726-cleanup)

### Making it the home app

- **`cmd package set-home-activity`** in Android 11 takes a package or component and calls `RoleManager.addRoleHolderAsUser(ROLE_HOME, ...)`. It prints "Error: Failed to set default home." when the role is refused. **High.** [PackageManagerShellCommand (android11)](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android11-release/services/core/java/com/android/server/pm/PackageManagerShellCommand.java)
- **`cmd role add-role-holder [--user USER_ID] ROLE PACKAGE`** does the same through the role service. **High.** [RoleManagerShellCommand (android11)](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android11-release/services/core/java/com/android/server/role/RoleManagerShellCommand.java)
- **The HOME role only accepts a package with a MAIN + HOME activity.** **High.** [roles.xml (android11)](https://raw.githubusercontent.com/aosp-mirror/platform_packages_apps_packageinstaller/android11-release/res/xml/roles.xml)
- **Correction to earlier data.** Ticket 02 recorded `set-home-activity` as failing on an H713, which made it look unreliable. But that gist pointed it at Zapp, a TV-streaming app with no HOME activity, so the failure was expected. It says nothing about the command with a real launcher. An H726 guide uses `set-home-activity` for Projectivy as its step to make it the launcher, but reports no output, so success there is likely, not proven. **High** for Zapp's manifest; **medium** for the conclusion. [gist](https://gist.github.com/probonopd/3ad6b7777caea1503f00d5fe7710ad06), [Zapp manifest](https://raw.githubusercontent.com/cemrich/zapp/main/app/src/main/AndroidManifest.xml), [battleof3](https://github.com/battleof3/magcubic-h726-cleanup)
- **Checking the result:** `cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME` prints the winning home activity, and `query-activities` lists every candidate. Both exist in Android 11. **High.** [PackageManagerShellCommand (android11)](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android11-release/services/core/java/com/android/server/pm/PackageManagerShellCommand.java)
- **FLauncher's own README** suggests remapping the Home button or disabling the stock launcher. Neither is needed if the HOME role takes. **High.** [README](https://gitlab.com/flauncher/flauncher/-/raw/master/README.md)
- **Back button:** in the fork it can be set to do nothing, to avoid dropping into the clock or screensaver by accident. **High.** [CHANGELOG](https://raw.githubusercontent.com/osrosal/flauncher/master/CHANGELOG.md)

## 2. Removing the stock launcher: what Android itself needs

- **There is always a fallback home.** AOSP Settings declares `FallbackHome` (MAIN + HOME, priority -1000). At boot it shows a "finishing boot" screen until the user is unlocked, then closes as soon as another home app resolves. **High.**
  - If no other home app exists, it logs "User unlocked but no home" and retries every 500 ms forever. The screen stays stuck on "finishing boot". This is the real failure mode if FLauncher is missing or broken.
  - Recovery is over ADB, or through the recovery path, so ADB over USB must be proven before the stock launcher goes.
  - [FallbackHome.java (android11)](https://android.googlesource.com/platform/packages/apps/Settings/+/refs/heads/android11-release/src/com/android/settings/FallbackHome.java), [Settings manifest (android11)](https://android.googlesource.com/platform/packages/apps/Settings/+/refs/heads/android11-release/AndroidManifest.xml)
- **With the stock launcher gone,** FLauncher is the only normal-priority HOME candidate, so it wins over FallbackHome even without being set as default. **Medium**, an inference from the priority values. Setting the role explicitly first removes the doubt.
- **Recents:** in AOSP, `config_recentsComponentName` names the launcher's Recents activity, with SystemUI's own Recents as the documented alternative. If the vendor pointed it at the stock launcher, Recents dies with it. On a remote with no Recents key, that matters little. **High** for the config; impact **low**. [config.xml (android11)](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android11-release/core/res/res/values/config.xml)
- **Setup wizard:** disable or remove the vendor setup wizard only after `device_provisioned` and `user_setup_complete` are both 1, as ticket 02 found. **Medium.** [02b data](02b-planning-facts-data.json), features finding 5.
- **Vendor-specific risks** (not Android's needs, but what actually bites):
  - **Keystone, projection orientation and initial-angle screens** live inside the stock launcher on sister units. This is ticket 04's question. **Medium.** [maximilian-sh](https://github.com/maximilian-sh/hy350max-badbox-removal), [gist](https://gist.github.com/probonopd/3ad6b7777caea1503f00d5fe7710ad06)
  - **Hidden services.** On Google TV devices, disabling the stock launcher together with Google's setup wizard (`setupwraith`) broke casting after a reboot on a Chromecast, and input switching on a Xiaomi TV; which of the two packages caused it is not known. FLauncher's own README warns that disabling the stock launcher can stop the remote's YouTube button. Stock launchers can host services beyond the home screen. This unit's equivalent might be HDMI auto-switch, the screensaver host, or the remote's special keys; unknown. **Low**, other devices. [osrosal #48](https://github.com/osrosal/flauncher/issues/48), [osrosal #55](https://github.com/osrosal/flauncher/issues/55)
  - **Vendor launcher fronts first at boot** on H726, being direct-boot-aware, with `persist.sys.homePackage` ignored. This matters only while the stock launcher is still installed (the Contained state, or if keystone forces keeping it). Removal makes it moot. **Medium.** [schaumann](https://github.com/schaumann-byte/hy300-projector-homeassistant)
- **Safe order:**
  1. Install FLauncher.
  2. Set the HOME role and check it with `resolve-activity`.
  3. Disable the stock launcher with `pm disable-user` (undo: `pm enable`).
  4. Reboot and test Home, HDMI, Settings, keystone, focus and USB media.
  5. Remove the stock launcher only once all of that passes.

  **Medium**: this matches the "install before disabling" advice in every source in [02b data](02b-planning-facts-data.json).

## 3. Material Files

- **Current build and distribution:**
  - v1.7.5, released 2026-09-20 on GitHub. **High.** [releases API](https://api.github.com/repos/zhanghai/MaterialFiles/releases?per_page=3)
  - On F-Droid, 1.7.5 (versionCode 40) was added 2026-09-22. It is built and signed by F-Droid, needs Android 6.0+, includes armeabi-v7a, and lists no anti-features. **High.** [F-Droid](https://f-droid.org/en/packages/me.zhanghai.android.files/)
- **Use the F-Droid build, not the GitHub one.**
  - The GitHub and Play builds include Firebase and Crashlytics; the maintainer says the F-Droid build has neither. **High.** [#1347](https://github.com/zhanghai/MaterialFiles/issues/1347)
  - The GitHub 1.7.5 APK raises a Google Play services notification on devices without Play services. It is fixed in source, but no new tagged release exists yet. The F-Droid build is unaffected. **High.** [#1630](https://github.com/zhanghai/MaterialFiles/issues/1630)
  - The F-Droid and GitHub builds have different signing keys, so you cannot switch between them later without uninstalling. **High.** [#1633](https://github.com/zhanghai/MaterialFiles/issues/1633)
  - The maintainer also re-uploaded the F-Droid-built APK to GitHub as `app-release-fdroid.apk`. **Medium.** [#1630](https://github.com/zhanghai/MaterialFiles/issues/1630), [releases API](https://api.github.com/repos/zhanghai/MaterialFiles/releases?per_page=3)
- **Remote use:**
  - The manifest declares an Android TV banner, a LEANBACK_LAUNCHER entry, and touchscreen and leanback as not required. **High.** [manifest](https://raw.githubusercontent.com/zhanghai/MaterialFiles/master/app/src/main/AndroidManifest.xml)
  - The TV launcher entry came back in March 2024, after a Play-policy workaround had switched it off. **High.** [#997](https://github.com/zhanghai/MaterialFiles/issues/997)
  - A D-pad dead end in the multi-select toolbar (you could not move right to Copy or Delete) was fixed on 2026-09-18 in f983dc4, which is included in v1.7.5. **High.** [PR #1550](https://github.com/zhanghai/MaterialFiles/pull/1550), [compare f983dc4...v1.7.5](https://api.github.com/repos/zhanghai/MaterialFiles/compare/f983dc4...v1.7.5)
  - "Full Android TV support" is still an open request, and no maintainer statement on full remote coverage was found. So expect usable rather than polished. **Medium.** [#903](https://github.com/zhanghai/MaterialFiles/issues/903)
- **Installing APKs:**
  - It declares REQUEST_INSTALL_PACKAGES and handles `application/vnd.android.package-archive`. **High.** [manifest](https://raw.githubusercontent.com/zhanghai/MaterialFiles/master/app/src/main/AndroidManifest.xml)
  - The "Open Android packages" setting offers View, Install, or Ask. **High.** [#1595](https://github.com/zhanghai/MaterialFiles/issues/1595) Install hands the APK to the system package installer, which shows its own dialog. **Medium** (seen in a log in [#822](https://github.com/zhanghai/MaterialFiles/issues/822), not documented).
  - Since Android 8, each installing app needs the user's per-app "Install unknown apps" permission. **High.** [Android Developers blog](https://android-developers.googleblog.com/2017/08/making-it-safer-to-get-apps-on-android-o.html)
  - So Material Files works as the USB-stick install fallback. Grant it "Install unknown apps" only for that session and revoke it afterwards, in the spirit of install sessions. **Medium.**
  - One 2022 report, still open: installing an APK from a microSD card failed as invalid, while the same file installed from internal storage. Waiting a few seconds on the installer dialog before pressing Install worked. **Low.** [#822](https://github.com/zhanghai/MaterialFiles/issues/822)
- **USB media:**
  - It needs "All files access" (MANAGE_EXTERNAL_STORAGE). If the settings screen is missing, as on some TV builds (fixed in-app in 1.7.0), it can be granted from the PC with `adb shell appops set --uid me.zhanghai.android.files MANAGE_EXTERNAL_STORAGE allow`. **High.** [#875](https://github.com/zhanghai/MaterialFiles/issues/875), [Android docs](https://developer.android.com/training/data-storage/manage-all-files)
  - It also holds INTERNET (for SMB, FTP and WebDAV), so it is a possible probation destination only if you add a server. **High.** [F-Droid](https://f-droid.org/en/packages/me.zhanghai.android.files/)

## 4. Projectivy as the fallback

| | FLauncher (osrosal) | Projectivy |
|---|---|---|
| Source | GPL-3.0, public | Closed; the GitHub repo holds only configs and an issue tracker |
| Latest | 2025-07-27 | 4.72, 2026-10-03 (GitHub APK); 4.72 on APKMirror 2026-10-10 |
| 32-bit build | armeabi-v7a APK | APKMirror bundle "arm64-v8a + armeabi-v7a, Android 6.0+"; developer APK on GitHub |
| Signer | osrosal's key, no published fingerprint | APKMirror shows cert CN=Despesse Mickael, SHA-256 `f6697bf4082ee97511e4de07863193884a015b7ab5860430321bda1042b0aadd` |
| Network | Probably none (no INTERNET in release manifest) | Self-update check against its GitHub config when not installed from Play; wallpaper providers; opt-in anonymous usage and crash reports asked at first launch. It also asks to read the on-device TV listings (local, not shown to be network) |
| HDMI tile | Only via a launcher entry or a shim | Same problem: its "Inputs" could not open HDMI on the H726 sister firmware; awsource was reachable as a "mobile app" there |
| Custom tiles | None | Listing says app shortcuts and renaming are supported |
| Stock-launcher override | Not needed once the stock launcher is removed | Accessibility-service override, optional, unreliable per users; not needed once removed |
| Memory (Shield, focused) | about 182 MB | about 104 MB |

Sources for the table:
- **Projectivy repo, self-update and APK:** **high.** [miproja1 README](https://raw.githubusercontent.com/spocky/miproja1/master/README.md), [releases API](https://api.github.com/repos/spocky/miproja1/releases?per_page=3)
- **APKMirror variants and certificate:** **high.** [APKMirror 4.72](https://www.apkmirror.com/apk/spocky/projectivy-launcher-android-tv/projectivy-launcher-android-tv-4-72-release/)
- **Listing claims** (optional accessibility service, premium features, "no data collected", which the listing says of the accessibility service only): from the developer's listing, as mirrored. **Medium.**
- **First-launch prompts** (TV listings, notification access, anonymous usage and crash reporting): one walkthrough. **Medium.** [Make Tech Easier](https://maketecheasier.com/?p=813115) [APKMirror](https://www.apkmirror.com/apk/spocky/projectivy-launcher-android-tv/)
- **Accessibility override behaviour:** user reports. **Low.** [Android Authority](https://www.androidauthority.com/google-tv-update-blocks-projectivy-override-3649445)
- **HDMI and `set-home-activity` on H726:** **medium**; the guide lists the command but reports no output. [battleof3](https://github.com/battleof3/magcubic-h726-cleanup)
- **Memory:** **medium.** [osrosal #22](https://github.com/osrosal/flauncher/issues/22)

**Verdict.** Keep FLauncher first. It is open source, probably has no network access, and is fully enough for a tile grid. Projectivy wins on maintenance and polish. Use it only if FLauncher misbehaves on the unit.

With Projectivy, the probation log will show its update and wallpaper hosts, and they must be explained. Answer No to anonymous usage and crash reporting at first launch. Leave its accessibility service off: once the stock launcher is removed, it has no job.

## 5. Only the unit can answer (read-only, from the golden backup or `adb shell`)

1. **Which packages have launcher entries:** `cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER`, and the same with `LEANBACK_LAUNCHER`. This decides whether HDMI (awsource or awlivetv) and the keystone screen get tiles by themselves or need the shim.
2. **Current home candidates and winner:** `query-activities` / `resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME`. Also: is the vendor setup wizard still a candidate?
3. **What the stock launcher hosts beyond the home screen:** `dumpsys package <stock launcher>` (services, receivers, activities). Is it the Recents provider? `cmd overlay lookup android android:string/config_recentsComponentName` (the `lookup` subcommand exists in Android 11: [OverlayManagerShellCommand](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android11-release/services/core/java/com/android/server/om/OverlayManagerShellCommand.java)).
4. **Whether `set-home-activity` / `cmd role add-role-holder` accepts FLauncher on this build.** This is a settings write: it needs the user's yes, and it belongs to the runbook, not the map.
5. **Whether the remote's Home key just sends HOME,** or a vendor service sends it to the stock launcher by name. Test in the Contained state, after disabling the stock launcher and rebooting.
6. **Whether HDMI needs an extra** such as `input_source HDMI2`: `dumpsys tv_input | grep HdmiInputService`.
7. **Whether the "All files access" and "Install unknown apps" screens exist** in this unit's Settings, or need the appops route.
8. **Whether `com.android.packageinstaller` is present and unmodified,** and whether the firmware blocks installs from non-whitelisted installers (the vendor `preinstall` / `appsdisable` binaries noted in ticket 02). It must stay on the keep-list.
9. **How FLauncher behaves on 1 GB RAM:** is it killed and slow to return after Netflix? Turn the highlight animation off first.

## Verification

Checked 2026-10-19 by an independent pass: each cited source was reopened and, where possible, set against a second source. Web only; nothing downloaded or run.

### Fixed in place

1. **Projectivy `set-home-activity` on H726:** the text said it "worked". The battleof3 guide only lists the command as its step to make Projectivy the launcher and reports no output. Reworded to "likely, not proven". [battleof3 README](https://raw.githubusercontent.com/battleof3/magcubic-h726-cleanup/main/README.md)
2. **"On this firmware" HDMI claims:** the evidence that Projectivy's Inputs and standard TV-input intents fail comes from the H726 sister unit (Android 14), not this H713 unit. Reworded in three places. The H713 HY300 Pro+ HDMI app starting awlivetv by explicit component is added as supporting evidence. [battleof3](https://github.com/battleof3/magcubic-h726-cleanup), [allwinner-hdmi](https://github.com/probonopd/allwinner-hdmi)
3. **Memory reading:** the 182 MB / 104 MB `top` figures come from a reporter who did not name the device; "on a Shield" was another commenter. Reworded. [osrosal #22](https://github.com/osrosal/flauncher/issues/22)
4. **Settings tile condition:** the code also checks `com.android.tv.settings`, not only `com.android.settings`. Added. [MainActivity.java](https://raw.githubusercontent.com/osrosal/flauncher/master/android/app/src/main/java/me/efesser/flauncher/MainActivity.java)
5. **Hidden services:** in both Google TV reports the user disabled the stock launcher and the setup wizard (`setupwraith`) together, so the cause is not pinned on the launcher. Reworded. Added the FLauncher README warning that disabling the stock launcher can stop the remote's YouTube button. [osrosal #48](https://github.com/osrosal/flauncher/issues/48), [osrosal #55](https://github.com/osrosal/flauncher/issues/55), [README](https://gitlab.com/flauncher/flauncher/-/raw/master/README.md)
6. **Projectivy network:** "TV guide" was not supported as a network feature. The app asks to read on-device TV listings, which is local. The walkthrough also shows a first-launch opt-in for anonymous usage and crash reporting. Table and short answer corrected, and the probation advice now says to answer No. [Make Tech Easier](https://maketecheasier.com/?p=813115), [APKMirror listing](https://www.apkmirror.com/apk/spocky/projectivy-launcher-android-tv/)
7. **"No data collected":** the listing says this of the accessibility service only. Scoped. [APKMirror listing](https://www.apkmirror.com/apk/spocky/projectivy-launcher-android-tv/)
8. **Material Files #822:** the report is about an install from microSD failing as invalid, with a wait-then-Install workaround. "Arriving corrupted" was looser than the source. Reworded. [#822](https://github.com/zhanghai/MaterialFiles/issues/822)
9. **"Install hands the APK to the system installer":** this is not in #1595. It is seen in a #822 log. Downgraded to medium and re-cited.

### Claim by claim

| # | Claim | Verdict | Note and source |
|---|---|---|---|
| 1 | Original FLauncher: last release 0.18.0 on 2023-04-21, last commit 2023-03-03 | Confirmed | Commit 4930cd73 (highlight-animation setting). [releases](https://gitlab.com/api/v4/projects/flauncher%2Fflauncher/releases), [commits](https://gitlab.com/api/v4/projects/26632151/repository/commits?per_page=5) |
| 2 | Original ships Firebase analytics and Crashlytics | Confirmed | Its pubspec also lists `firebase_remote_config` and `unsplash_client`. [pubspec](https://gitlab.com/flauncher/flauncher/-/raw/master/pubspec.yaml) |
| 3 | Original README: Play badge only, tested only on Chromecast with Google TV, early stage | Confirmed | It recommends a Home-button remap as the safer route. [README](https://gitlab.com/flauncher/flauncher/-/raw/master/README.md) |
| 4 | Not on F-Droid or IzzyOnDroid | Confirmed (medium) | Both pages return 404; a search found no listing either. [F-Droid](https://f-droid.org/en/packages/me.efesser.flauncher/), [IzzyOnDroid](https://apt.izzysoft.de/fdroid/index/apk/me.efesser.flauncher) |
| 5 | osrosal v2025.07.001, 2025-07-27; armeabi-v7a APK about 10.6 MB; not archived; 34 open issues; GPL-3.0 | Confirmed | 10,581,743 bytes. GitHub lists the repo as not a fork; the description names the upstream. [releases](https://api.github.com/repos/osrosal/flauncher/releases?per_page=5), [repo](https://api.github.com/repos/osrosal/flauncher) |
| 6 | Fork removed Firebase, Crashlytics and Unsplash; Flutter 3.24.5; Escape maps to Back; Back can do nothing | Confirmed | [CHANGELOG](https://raw.githubusercontent.com/osrosal/flauncher/master/CHANGELOG.md) |
| 7 | APKs built and signed in GitHub Actions on push to master, keystore from secrets | Confirmed | Secret `KEYSTORE_FILE_BASE64` plus three password and alias secrets; Java 17. [workflow](https://raw.githubusercontent.com/osrosal/flauncher/master/.github/workflows/continuous-release.yml), [build.gradle](https://raw.githubusercontent.com/osrosal/flauncher/master/android/app/build.gradle) |
| 8 | No published signing fingerprint | Confirmed | README names only GitHub releases and Actions artifacts. [README](https://raw.githubusercontent.com/osrosal/flauncher/master/README.md) |
| 9 | minSdk 21, targetSdk 35 | Confirmed | compileSdk 35 as well. [build.gradle](https://raw.githubusercontent.com/osrosal/flauncher/master/android/app/build.gradle) |
| 10 | Main activity has MAIN with HOME, DEFAULT, LAUNCHER, LEANBACK_LAUNCHER; not direct-boot-aware | Confirmed | It also carries LAUNCHER_APP. [manifest](https://raw.githubusercontent.com/osrosal/flauncher/master/android/app/src/main/AndroidManifest.xml) |
| 11 | Release manifest has no INTERNET; debug manifest adds it for Flutter tooling | Confirmed; conclusion stays medium | The pubspec has no networking package (`image_picker`, `drift`, `package_info_plus` and similar). A merged plugin permission is still possible, so the `aapt2` check stands. [pubspec](https://raw.githubusercontent.com/osrosal/flauncher/master/pubspec.yaml), [debug manifest](https://raw.githubusercontent.com/osrosal/flauncher/master/android/app/src/debug/AndroidManifest.xml) |
| 12 | App list from LEANBACK_LAUNCHER and LAUNCHER queries; launch via the package launch intent | Confirmed | Leanback intent first, then the normal one. [MainActivity.java](https://raw.githubusercontent.com/osrosal/flauncher/master/android/app/src/main/java/me/efesser/flauncher/MainActivity.java) |
| 13 | No custom tiles, intent URIs or explicit components | Confirmed | One nuance: an internal `launchActivityFromAction` starts a bare action, used for the Settings tile. It is not user-configurable and cannot name a component. Same file. |
| 14 | Memory 182 MB vs 104 MB; animation off cut CPU from up to 60% to about 5% | Partly | Numbers confirmed; the CPU figure is the maintainer's. The device is not stated (fixed). [#22](https://github.com/osrosal/flauncher/issues/22) |
| 15 | 2025.07.001 navigation trap after deleting both sections | Confirmed | Closed by the reporter on 2025-07-29 with no maintainer reply; the reporter links it to #8. [#44](https://github.com/osrosal/flauncher/issues/44) |
| 16 | An Android 11 armeabi-v7a TCL TV ran it; no projector reports | Confirmed | TCL 50C645 in #11. [issues](https://api.github.com/repos/osrosal/flauncher/issues?state=all&per_page=30&sort=updated) |
| 17 | awsource reachable as a "mobile app" in Projectivy on H726; HDMI needs `--es input_source HDMI2` there | Confirmed | Sister device only. [battleof3](https://raw.githubusercontent.com/battleof3/magcubic-h726-cleanup/main/README.md) |
| 18 | probonopd allwinner-hdmi exists for HY300 Pro+ and has no licence | Confirmed | API licence is null and no LICENSE file is visible. The gist ties HY300 Pro+ to the H713. "About ten lines" is unverified. [repo API](https://api.github.com/repos/probonopd/allwinner-hdmi), [repo](https://github.com/probonopd/allwinner-hdmi), [gist](https://gist.github.com/probonopd/3ad6b7777caea1503f00d5fe7710ad06) |
| 19 | `set-home-activity` takes a package or component, calls `addRoleHolderAsUser(ROLE_HOME, ...)`, prints "Error: Failed to set default home." | Confirmed | Help text says only the package name matters. [PackageManagerShellCommand](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android11-release/services/core/java/com/android/server/pm/PackageManagerShellCommand.java) |
| 20 | `cmd role add-role-holder [--user USER_ID] ROLE PACKAGE` | Confirmed | It takes optional FLAGS. [RoleManagerShellCommand](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android11-release/services/core/java/com/android/server/role/RoleManagerShellCommand.java) |
| 21 | HOME role requires a MAIN + HOME activity | Confirmed | The role is exclusive and has no default holders. [roles.xml](https://raw.githubusercontent.com/aosp-mirror/platform_packages_apps_packageinstaller/android11-release/res/xml/roles.xml) |
| 22 | The ticket 02 failure targeted Zapp, which has no HOME activity | Confirmed | Zapp's filters are LAUNCHER and LEANBACK_LAUNCHER only. The gist device is an H713. [gist](https://gist.github.com/probonopd/3ad6b7777caea1503f00d5fe7710ad06), [Zapp manifest](https://raw.githubusercontent.com/cemrich/zapp/main/app/src/main/AndroidManifest.xml) |
| 23 | `set-home-activity` for Projectivy worked on H726 | Partly | Listed as a step, with no output reported (fixed). [battleof3](https://raw.githubusercontent.com/battleof3/magcubic-h726-cleanup/main/README.md) |
| 24 | `resolve-activity` and `query-activities` exist with `--brief` in Android 11 | Confirmed | [PackageManagerShellCommand](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android11-release/services/core/java/com/android/server/pm/PackageManagerShellCommand.java) |
| 25 | FallbackHome: MAIN + HOME + DEFAULT at priority -1000; logs "User unlocked but no home" and retries every 500 ms | Confirmed | The finishing-boot view appears after 2 s, and only when provisioned. Whether this unit's Settings carries FallbackHome is a unit check. [FallbackHome.java](https://android.googlesource.com/platform/packages/apps/Settings/+/refs/heads/android11-release/src/com/android/settings/FallbackHome.java), [Settings manifest](https://android.googlesource.com/platform/packages/apps/Settings/+/refs/heads/android11-release/AndroidManifest.xml) |
| 26 | `config_recentsComponentName` names the launcher's Recents, with SystemUI's as the alternative | Confirmed | The AOSP default is `com.android.launcher3/com.android.quickstep.RecentsActivity`. [config.xml](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android11-release/core/res/res/values/config.xml) |
| 27 | `cmd overlay lookup` exists in Android 11 | Confirmed | Syntax `lookup [--verbose] PACKAGE-TO-LOAD PACKAGE:TYPE/NAME` matches the command given. [OverlayManagerShellCommand](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android11-release/services/core/java/com/android/server/om/OverlayManagerShellCommand.java) |
| 28 | Keystone, projection and initial-angle screens live in the stock launcher on sister units | Confirmed (sister devices) | HY350 Max: `CorrectionActivity`, `ProjectActivity`, `InitAngleActivity` in `com.htc.magcubicos`. H713 HY300 Pro+: the keystone UI is gone once LuminaOS is disabled. [maximilian-sh](https://github.com/maximilian-sh/hy350max-badbox-removal), [gist](https://gist.github.com/probonopd/3ad6b7777caea1503f00d5fe7710ad06) |
| 29 | Disabling the stock launcher broke casting and input switching on Google TV devices | Partly | The setup wizard was disabled at the same time (fixed). [#48](https://github.com/osrosal/flauncher/issues/48), [#55](https://github.com/osrosal/flauncher/issues/55) |
| 30 | H726 vendor launcher is direct-boot-aware, fronts at boot, and ignores `persist.sys.homePackage` | Confirmed | HY300 Pro+ "H726 Standard", Android 14. [schaumann](https://github.com/schaumann-byte/hy300-projector-homeassistant) |
| 31 | LtvLauncher adds weather, data usage, notification overlays, an accessibility service and an HDMI selector; based on osrosal | Confirmed (medium) | Pushed 2026-10-19; GPL-3.0; 32-bit APK offered. Its "zero network telemetry" claim sits beside weather fetching, so network use is still real. [repo API](https://api.github.com/repos/LeanBitLab/LtvLauncher), [README](https://github.com/LeanBitLab/LtvLauncher) |
| 32 | Material Files v1.7.5 on GitHub 2026-09-20; F-Droid 1.7.5 (versionCode 40) added 2026-09-22, F-Droid-signed, Android 6.0+, armeabi-v7a, no anti-features | Confirmed | [releases](https://api.github.com/repos/zhanghai/MaterialFiles/releases?per_page=3), [F-Droid](https://f-droid.org/en/packages/me.zhanghai.android.files/) |
| 33 | GitHub and Play builds carry Firebase and Crashlytics; F-Droid has neither | Confirmed (medium on Crashlytics) | #1347 states the F-Droid side; #1630's fix to Firebase start-up shows the GitHub build has Firebase. [#1347](https://github.com/zhanghai/MaterialFiles/issues/1347), [#1630](https://github.com/zhanghai/MaterialFiles/issues/1630) |
| 34 | GitHub 1.7.5 raises a Play services notification; fixed in source (c8d13ec), no new release; F-Droid unaffected; F-Droid APK re-uploaded to GitHub | Confirmed | [#1630](https://github.com/zhanghai/MaterialFiles/issues/1630) |
| 35 | F-Droid and GitHub builds have different signers | Confirmed | Maintainer: the F-Droid build is "built and signed by F-Droid". [#1633](https://github.com/zhanghai/MaterialFiles/issues/1633) |
| 36 | Manifest: TV banner, LEANBACK_LAUNCHER, touchscreen and leanback not required, REQUEST_INSTALL_PACKAGES, APK MIME, INTERNET, MANAGE_EXTERNAL_STORAGE | Confirmed | The APK MIME sits in the archive-viewer filter. [manifest](https://raw.githubusercontent.com/zhanghai/MaterialFiles/master/app/src/main/AndroidManifest.xml) |
| 37 | TV launcher entry restored March 2024 after a Play-policy disable | Confirmed | Revert 9f1134a; issue closed 2024-03-04. [#997](https://github.com/zhanghai/MaterialFiles/issues/997) |
| 38 | D-pad multi-select fix f983dc4 (2026-09-18) is in v1.7.5 | Confirmed | Compare shows v1.7.5 ahead by 15 and behind by 0. PR #1550 was closed in favour of the maintainer's commit, not merged. [PR #1550](https://github.com/zhanghai/MaterialFiles/pull/1550), [compare](https://api.github.com/repos/zhanghai/MaterialFiles/compare/f983dc4...v1.7.5) |
| 39 | "Full Android TV support" still open; no maintainer statement | Confirmed | [#903](https://github.com/zhanghai/MaterialFiles/issues/903) |
| 40 | Open Android packages: View, Install, Ask | Confirmed | The issue itself is a request for an "Open with" option and is still open. [#1595](https://github.com/zhanghai/MaterialFiles/issues/1595) |
| 41 | Android 8+ per-app "Install unknown apps" permission | Confirmed | [Android Developers blog](https://android-developers.googleblog.com/2017/08/making-it-safer-to-get-apps-on-android-o.html) |
| 42 | Missing "All files access" screen on TV, handled in-app around 1.7.0; appops grant from the PC | Confirmed | Commit a14e14f (2024-03-10, milestone v1.7.0) predates 1.7.3. The appops command is from the Android docs, not #875. [#875](https://github.com/zhanghai/MaterialFiles/issues/875), [Android docs](https://developer.android.com/training/data-storage/manage-all-files) |
| 43 | microSD APK problem (#822) | Partly | Reworded (fixed). [#822](https://github.com/zhanghai/MaterialFiles/issues/822) |
| 44 | Projectivy repo holds configs and the tracker; GitHub APK 4.72 on 2026-10-03 | Confirmed | The asset is `ProjectivyLauncher-4.72-c97-xda-release.apk` (11.4 MB). Which ABIs it holds and who signed it were not checked. [README](https://raw.githubusercontent.com/spocky/miproja1/master/README.md), [releases](https://api.github.com/repos/spocky/miproja1/releases?per_page=3) |
| 45 | APKMirror 4.72 on 2026-10-10: arm64-v8a + armeabi-v7a bundle for Android 6.0+; cert CN=Despesse Mickael, SHA-256 f6697bf4... | Confirmed | Also an armeabi-v7a-only bundle for Android 12L+, not for this unit. [APKMirror 4.72](https://www.apkmirror.com/apk/spocky/projectivy-launcher-android-tv/projectivy-launcher-android-tv-4-72-release/) |
| 46 | Projectivy network: update check, wallpapers, TV guide | Partly | "TV guide" is unsupported as network use; an opt-in for usage and crash reports was found (fixed). [Make Tech Easier](https://maketecheasier.com/?p=813115) |
| 47 | The accessibility override is unreliable per users | Confirmed (low) | The Android Authority page returned 403; a search snippet and 4.63 release notes about mistaken overrides agree. No traffic audit of Projectivy was found. [search hit](https://www.androidauthority.com/google-tv-update-blocks-projectivy-override-3649445), [Privacy Guides thread](https://discuss.privacyguides.net/t/pojectivy-launcher-privacy-and-launchers-genegrally/34179) |

No key claim was refuted outright. The FLauncher-first recommendation and the safe order (install, set role, disable, reboot-test, then remove) stand.
