# 14 AirPlay Server on this projector: findings

Researched 2026-10-19 for ticket [14](../decisions/14-airplay-server.md). Sources are the app's own repository and source code, F-Droid's build metadata, Android and Apple documentation, and the issue trackers of the app and of UxPlay, the engine underneath it. The earlier verified data is in [02a-feasibility-data.json](02a-feasibility-data.json) (the `airplay` section). Confidence is marked per claim: high, medium or low. "Inference" means my reading of the sources, not something a source states.

## Short answer

- **Version and channel:** v0.0.36 from GitHub Releases. It is a single APK that includes the 32-bit `armeabi-v7a` code. Take a newer one if it exists on install day. F-Droid is behind at 0.0.31 and lacks fixes that matter on a projector.
- **Authenticity:** two checks on the PC before install. First, the file's SHA-256 must match the digest GitHub shows. Second, the signing certificate's SHA-256 must be `64ca1fa39ddf9e0e89c57d73fb681d2a5b35ae20f071771e2eb401b5032ef1a9`, the key that F-Droid pins for this app.
- **iPadOS 26.6.2:** very likely works. No report names 26.6.2 exactly. UxPlay is confirmed working with iOS 26.6, and 26.6.2 only fixes software updates over cellular.
- **Ports:** TCP 7000 (adjustable), mDNS on UDP 5353, and a few random TCP/UDP ports during each session. It listens on all interfaces, IPv4 and IPv6.
- **Boot:** yes. "Start server at boot" exists and is on by default. The app must be opened once after install.
- **Volume:** if the volume jumps to 100% on connect, turn off "Sync sender volume" (on by default). The maintainer gives that as the fix for #53.
- **Low-end devices:** one user runs it on an HY300 (H713, Android 11, 32-bit) and calls it "the only free receiver I found that works on this projector". Known risks are listed in section 7. No one has published performance numbers for 1 GB of RAM.

## 1 Which version, from where

| Channel | Newest version | Date | Notes |
|---|---|---|---|
| GitHub Releases | v0.0.36 | 19 Oct 2026 | Files: `app-release.apk` (26.1 MB), `app-release.aab` and the source code. Built by the project's GitHub Actions workflow when a version tag is pushed. |
| F-Droid | 0.0.31 | 26 Aug 2026 | Marked "built and signed by the original developer". F-Droid's build recipe already names 0.0.33 as current, but 0.0.33 is not published yet. |
| Google Play | listed in the README | n/a | Not usable here: no Play Store on the projector. The Play page could not be read. |

- GitHub v0.0.36 is the latest, after v0.0.32 to v0.0.35 on 16 to 19 Oct (high). [releases](https://github.com/jqssun/android-airplay-server/releases), [v0.0.36 files](https://github.com/jqssun/android-airplay-server/releases/expanded_assets/v0.0.36), [workflow](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/.github/workflows/apk.yml)
- F-Droid's newest build is 0.0.31, and its recipe lists `CurrentVersion: 0.0.33` (high). [F-Droid page](https://f-droid.org/en/packages/io.github.jqssun.airplay/), [F-Droid recipe](https://gitlab.com/fdroid/fdroiddata/-/raw/master/metadata/io.github.jqssun.airplay.yml)
- **Why GitHub over F-Droid:** several bugs were fixed after 0.0.31 and closed on 19 Oct 2026, the day v0.0.34 to v0.0.36 came out. The maintainer only says the fixes are in "the latest build" and does not name a version. Closing date high, exact version medium.
  - [#52](https://github.com/jqssun/android-airplay-server/issues/52): with PIN required, the app did not come to the front, and the PIN only showed in a notification that Android TV launchers do not display. Reported on an HY300 with Android 11.
  - [#49](https://github.com/jqssun/android-airplay-server/issues/49): AirPlay video (HLS) playback failed.
  - [#53](https://github.com/jqssun/android-airplay-server/issues/53): volume was locked at 100%. The maintainer says the fix works only with "Sync sender volume" turned off, and that setting is on by default (see section 4).
  - [#51](https://github.com/jqssun/android-airplay-server/issues/51): the H.265 decoder was not used.
  - The release titles hint at where the fixes landed: v0.0.34 "api", v0.0.35 "pin", v0.0.36 "decoder" (low: inference from titles only). [releases](https://github.com/jqssun/android-airplay-server/releases)
- **32-bit:** the build file compiles all ABIs into one APK with no splits, and F-Droid lists `arm64-v8a, armeabi-v7a, x86_64` for its APK (high). [build file](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/app/build.gradle.kts), [F-Droid page](https://f-droid.org/en/packages/io.github.jqssun.airplay/)
- **Android version:** the v0.0.36 build file sets `minSdk = 23` (Android 6) and `targetSdk = 37`. F-Droid lists Android 7.0+ for 0.0.31. Either way, Android 11 is covered (high). [build file](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/app/build.gradle.kts)
- **Trade-off:** v0.0.36 is one day old and the project shipped four releases in four days. If it misbehaves, the fallback is v0.0.33 (the version F-Droid's recipe targets) or 0.0.31. This advice is an inference.

## 2 Checking authenticity

Do these steps on the PC before the APK goes to the projector.

1. **Get the file only from** `github.com/jqssun/android-airplay-server/releases`. This is the repository F-Droid builds from (high). [F-Droid recipe](https://gitlab.com/fdroid/fdroiddata/-/raw/master/metadata/io.github.jqssun.airplay.yml)
2. **Check the file hash.** GitHub computes a SHA-256 digest for every release file when it is uploaded and shows it on the release page (high). [GitHub changelog](https://github.blog/changelog/2025-06-03-releases-now-expose-digests-for-release-assets/)
   - For v0.0.36, `app-release.apk` is `b8c7c595ed93f91562feedce92c27800f08f9c84df424f6ac2045e82324cf2a4` (high). [v0.0.36 files](https://github.com/jqssun/android-airplay-server/releases/expanded_assets/v0.0.36)
   - On Windows, `Get-FileHash app-release.apk` (SHA-256 by default) prints the value to compare. It prints upper case, so compare ignoring case. [Get-FileHash](https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/get-filehash)
   - This only proves the file is what was uploaded. It does not prove who uploaded it.
3. **Check the signing certificate.** This is the check that ties the file to the developer.
   - F-Droid's recipe pins `AllowedAPKSigningKeys: 64ca1fa39ddf9e0e89c57d73fb681d2a5b35ae20f071771e2eb401b5032ef1a9` (high). [F-Droid recipe](https://gitlab.com/fdroid/fdroiddata/-/raw/master/metadata/io.github.jqssun.airplay.yml)
   - F-Droid defines that value as the lowercase SHA-256 fingerprint of the signing certificate. It is read with `apksigner verify --print-certs app-release.apk` (Android SDK build-tools) or `keytool -printcert -jarfile` (any JDK) (high). [F-Droid reference](https://f-droid.org/docs/Build_Metadata_Reference/)
   - The `apksigner` printout shows the fingerprint without colons. `keytool` shows it with colons and in upper case, so remove the colons before comparing.
   - The F-Droid pin sits in a separate repository with its own review, so a stolen GitHub account alone could not change it (inference).
   - `apksigner` comes with the SDK build-tools, not with platform-tools, so the PC may not have it yet. Whether it does is unknown.
4. **Android checks every update after that.** Android installs an update only if its certificate matches the installed app's (high). [Android app signing](https://developer.android.com/studio/publish/app-signing)
   - The maintainer says GitHub and F-Droid builds use the same key, so you can switch between them without uninstalling (medium: maintainer's statement). [#7](https://github.com/jqssun/android-airplay-server/issues/7)
5. **Strongest check (optional):** wait until F-Droid publishes the same version.
   - F-Droid rebuilds the app from source and publishes the developer-signed APK only when its rebuild matches (high). [F-Droid reproducible builds](https://f-droid.org/docs/Reproducible_Builds/)
   - For this app, F-Droid says its versions are "built and signed by the original developer", so that match has held so far. [F-Droid page](https://f-droid.org/en/packages/io.github.jqssun.airplay/)
- **No tracking found:** F-Droid lists no anti-features. The build file contains no analytics, crash-reporting or Google services libraries (high). [F-Droid page](https://f-droid.org/en/packages/io.github.jqssun.airplay/), [build file](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/app/build.gradle.kts)
- **Do not mix in Play copies.** The release workflow signs with a keystore named `upload.jks`. With Play App Signing, Google re-signs with its own key, so a Play copy may carry a different certificate (low: inference from the file name). [workflow](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/.github/workflows/apk.yml), [Android app signing](https://developer.android.com/studio/publish/app-signing)

## 3 iPadOS 26.6.2

**Verdict:** very likely works (medium-high). Confirm with a test on the unit.

- iOS/iPadOS 26.0 and 26.1 broke PIN display and discovery for third-party receivers, and Apple fixed it in 26.2 (high). [Prowise](https://service.prowise.com/hc/en-gb/articles/29653730908178-AirPlay-issues-resolved-by-update-to-iOS-iPadOS-macOS-26-2)
- The UxPlay maintainer wrote "I can confirm that uxplay works with iOS 26.6 clients" (high). The app is built on UxPlay's library. [UxPlay #547](https://github.com/FDH2/UxPlay/issues/547), [app README](https://github.com/jqssun/android-airplay-server)
- Apple's notes for iPadOS 26.6.2 mention only a fix for downloading software updates over cellular, with nothing about AirPlay (high). The newest iPadOS listed is 26.7.1. [Apple: iPadOS 26 updates](https://support.apple.com/en-hk/123074)
- The app patches UxPlay's PIN pairing (`0008-fix-pin-pairing-proof-length.patch`) (high that the patch exists; what it changes for iPadOS is not documented). [patches](https://github.com/jqssun/android-airplay-server/tree/main/app/src/main/cpp/patches/UxPlay)
- The app's tracker has no iPad-specific bug reports (high). [search](https://github.com/jqssun/android-airplay-server/issues?q=is%3Aissue%20iPad)
- **If the iPad updates later:** UxPlay's README warns that future iOS versions may drop the "Legacy Protocol" it depends on. A problem with the iOS 27 beta is "(probably?) fixed" but not confirmed, so re-test AirPlay after any iPad update (medium). [UxPlay README](https://github.com/FDH2/UxPlay), [UxPlay #535](https://github.com/FDH2/UxPlay/issues/535)

## 4 Features

What it does (high). [README](https://github.com/jqssun/android-airplay-server), [store description](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/fastlane/metadata/android/en-US/full_description.txt)

- Screen mirroring with H.264 or H.265 decoding, and control over resolution, overscan and frame rate.
- Audio in AAC-ELD, AAC-LC and ALAC, with latency control and a software decoder as fallback.
- Video playback (HLS) with downloads and remote controls, and music with track info and cover art.
- Android TV support: D-pad navigation, picture-in-picture, automatic resolution and mode switching.
- Optional PIN, labelled "Require PIN (Beta)".
- A debug overlay showing FPS, bitrate, codec, resolution and dropped frames. Useful for the first test on the unit.
- A wired secondary display for macOS/iPadOS over USB tethering. Whether the projector's USB port can do USB tethering is unknown.
- Settings over ADB: `am broadcast -n io.github.jqssun.airplay/.SettingsReceiver -a io.github.jqssun.airplay.SET_SETTING --es key <key> --es value <value>`, and `LIST_SETTINGS` to print them as JSON (high). The README says to open the app (`MainActivity`) before `LIST_SETTINGS`. The JSON comes back as the broadcast's result data, with each key's value and default, and unknown keys or bad values are refused (high). [README](https://github.com/jqssun/android-airplay-server), [SettingsReceiver.kt](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/app/src/main/kotlin/io/github/jqssun/airplay/SettingsReceiver.kt)
  - The receiver requires `android.permission.DUMP`, so only the ADB shell or the system can use it, not other apps (high). [manifest](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/app/src/main/AndroidManifest.xml)
  - This fits install sessions: the runbook can set the name, PIN and boot start from the PC (inference).

Defaults from the code (high). [Prefs.kt](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/app/src/main/kotlin/io/github/jqssun/airplay/Prefs.kt), [strings](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/app/src/main/res/values/strings.xml)

| Setting | Key | Default |
|---|---|---|
| Server name | `server_name` | "Android AirPlay" |
| Server port | `server_port` | 7000 |
| Require PIN | `require_pin` | off |
| Start server at boot | `boot_auto_start` | on |
| Start server automatically (when the app opens) | `auto_start` | on |
| Run in background | `run_in_background` | on |
| Open this application on connect | `launch_on_connect` | on |
| Keep screen on | `keep_screen_on` | on |
| Allow new connections ("Drop current sender when a new one connects") | `allow_new_conn` | on |
| Resolution | `resolution` | auto |
| Max frame rate | `max_fps` | 60 |
| H.265 | `h265` | auto |
| Sync sender volume ("Use sender volume for receiver volume automatically") | `sync_client_volume` | on. Turn it off if the volume jumps to 100% (#53). |

**PIN:**
- With the PIN off and "Allow new connections" on, any device on the Wi-Fi can take over the screen. For a low-trust device on the home Wi-Fi, turning the PIN on is the sensible choice. This needs a build newer than 0.0.31 because of #52 (inference).
- The app's text says it asks for a "4-digit PIN for each new connection". UxPlay describes its PIN as asked once, when a client connects for the first time (high for both texts). Which one applies to the app is not documented, so observe it on the unit. [strings](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/app/src/main/res/values/strings.xml), [UxPlay README](https://github.com/FDH2/UxPlay)
- If PIN generation fails, the code falls back to the fixed PIN 1234 and logs an error (high, from code; the trigger is unlikely). [native_bridge.cpp](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/app/src/main/cpp/native_bridge.cpp)

What it does not do (high):
- **No DRM content**, for example the Apple TV app. [README](https://github.com/jqssun/android-airplay-server)
- **No Google Cast and no Miracast.** Neither is in the feature list. [README](https://github.com/jqssun/android-airplay-server)
- **AirPlay 2 only through the "Legacy Protocol"**, with "some features missing". [UxPlay README](https://github.com/FDH2/UxPlay)
- **AirPlay video (not mirroring) needs internet on the projector.** UxPlay streams YouTube video "directly from YouTube servers ... without passing through the client", and upstream UxPlay supports only YouTube for this. The app's patch `0004-video-sender-compat` lifts that YouTube-only check (other senders only log a warning) and adds playback of direct http(s) video URLs. So the projector fetches the video from whatever server the URL names, not only YouTube. Mirroring stays inside the home network. Medium: inference from the README wording and the patch code. *(Corrected in verification: the original said HLS works only for YouTube.)* [UxPlay README](https://github.com/FDH2/UxPlay), [patch 0004](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/app/src/main/cpp/patches/UxPlay/0004-video-sender-compat.patch)

## 5 Network ports

From the app's source and the UxPlay library it compiles in:

| What | Protocol and port | Notes |
|---|---|---|
| Discovery (mDNS) | UDP 5353, multicast 224.0.0.251 | Registered through Android's own network service discovery. Advertises `_airplay._tcp` always and `_raop._tcp` while audio advertising is on (high). [AirPlayService.kt](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/app/src/main/kotlin/io/github/jqssun/airplay/service/AirPlayService.kt), [NsdServiceManager.kt](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/app/src/main/kotlin/io/github/jqssun/airplay/discovery/NsdServiceManager.kt) |
| AirPlay control and HTTP | TCP 7000 (setting "Server port") | Both services are announced on this port. It is bound to every interface (`INADDR_ANY` and `in6addr_any`) and accepts at most 12 connections. The app's own player also reads its HLS playlist from it (`localhost:7000/master.m3u8`) (high). [native_bridge.cpp](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/app/src/main/cpp/native_bridge.cpp), [UxPlay httpd.c](https://raw.githubusercontent.com/FDH2/UxPlay/master/lib/httpd.c), [UxPlay netutils.c](https://raw.githubusercontent.com/FDH2/UxPlay/master/lib/netutils.c), [#49](https://github.com/jqssun/android-airplay-server/issues/49) |
| Mirroring video | TCP, random port | Chosen by the operating system for each session (high, see below). |
| Audio, timing, control | UDP, three random ports | Same as above (high). |
| Outgoing to the iPad | HTTP to the iPad's announced `_dacp._tcp` port | Remote control of the sender's playback (high). [DacpController.kt](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/app/src/main/kotlin/io/github/jqssun/airplay/audio/DacpController.kt) |
| Outgoing to the internet | The video's own servers (YouTube or another site) | Only during AirPlay video, not mirroring (medium, section 4). |

- **Why the random ports:** UxPlay sets all its session ports to 0 at start-up and only fixes them when `raop_set_tcp_ports` or `raop_set_udp_ports` is called. Desktop UxPlay calls them for its `-p` option. The app never calls them, and with port 0 the operating system picks a free port (high). [UxPlay raop.c](https://raw.githubusercontent.com/FDH2/UxPlay/master/lib/raop.c), [native_bridge.cpp](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/app/src/main/cpp/native_bridge.cpp), [UxPlay README](https://github.com/FDH2/UxPlay)
- **Apple's generic list:** Apple's AirPlay port list (TCP 5000/6000/7000 and others) describes Apple's own devices. This app listens only on 7000 plus the session ports. [Apple ports](https://support.apple.com/en-us/103229)
- **For the router-side checks:** the deployed projector should show TCP 7000 open because of this app. The session ports should appear only while something is casting (medium: inference from where the code opens them). Any other open port must come from something else.

## 6 Start at boot

Yes (high). [BootReceiver.kt](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/app/src/main/kotlin/io/github/jqssun/airplay/BootReceiver.kt), [manifest](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/app/src/main/AndroidManifest.xml), [Prefs.kt](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/app/src/main/kotlin/io/github/jqssun/airplay/Prefs.kt)

- A receiver listens for `BOOT_COMPLETED` and `QUICKBOOT_POWERON`. If "Start server at boot" is on, which is the default, it starts the server as a foreground service with a low-priority notification.
- Nothing appears on screen until an iPad connects. The app then comes to the front only if "Open this application on connect" can start an activity from the background.

Caveats:
- **Open the app once after install, and never force-stop it.** Android does not deliver broadcasts such as boot-completed to an app that is newly installed and never opened, or that was force-stopped (high). [Android 3.1 launch controls](https://developer.android.com/about/versions/android-3.1#launchcontrols)
- **"Display over other apps" must be granted.** Since Android 10, an app may start an activity from the background only under certain conditions, and this permission is one of them (high). [Android background starts](https://developer.android.com/guide/components/activities/background-starts)
  - Without it, the iPad connects but the picture may not come to the front. With PIN on, the PIN may never show (#52).
  - On the HY300 report, the permission was granted and the log showed the background start allowed (high). [#52](https://github.com/jqssun/android-airplay-server/issues/52)
  - Android Go builds for low-RAM devices turn this permission and picture-in-picture off by default (high). Whether this firmware is configured that way is unknown. [Android Go](https://developer.android.com/guide/topics/androidgo)
- **No automatic retry.** If the server fails to start, for example because another receiver already holds port 7000, the service stops (high, from code).
  - Nothing restarts it on network changes. Opening the app starts it again.
  - Port 7000 could only be taken by a leftover vendor casting receiver; that is an inference. Earlier research reports stock vendor casting on related units listening on 0.0.0.0:7000 (not observed on an HY320), so it must be gone or disabled first (F12 in [02a data](02a-feasibility-data.json)). [AirPlayService.kt](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/app/src/main/kotlin/io/github/jqssun/airplay/service/AirPlayService.kt)
- **Wi-Fi at boot.** On Android 11, the start-up check (`hasLocalNetwork`) always passes; it only tests a permission that exists on newer Android (high). [Permissions.kt](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/app/src/main/kotlin/io/github/jqssun/airplay/Permissions.kt)
  - The server binds every interface, so a late Wi-Fi connection should not stop it (high).
  - Whether the iPad discovers the projector when Wi-Fi comes up after boot depends on Android's mDNS service. Test it with a cold boot.

## 7 Known problems on low-end devices

| Problem | Status | Relevance here |
|---|---|---|
| Mirroring dies within a second because SELinux blocks `/dev/ashmem` (Hisense TV, MediaTek, Android 10, SELinux enforcing). Audio-only works. [#50](https://github.com/jqssun/android-airplay-server/issues/50) | **Open**, no maintainer reply | Apps that target Android 10 or newer cannot open `/dev/ashmem` directly, and this app targets API 37 ([Android 10 changes](https://developer.android.com/about/versions/10/behavior-changes-10)). One study of HY300 stock firmware reports SELinux permissive ([lolmam](https://github.com/lolmam/HY300-H713-Research)), and the HY300 user's mirroring works (#52). So it is probably not a problem on this family (medium). Test on the unit. |
| Black screen when the iPad's stream exceeds the hardware decoder's limits, and a first keyframe lost during slow decoder start (OnePlus; "legacy Google TV"). [#30](https://github.com/jqssun/android-airplay-server/issues/30), [#7](https://github.com/jqssun/android-airplay-server/issues/7) | Fixed 16 Jul 2026 (PR #31: resolution scaled to the decoder's limits, software fallback, longer wait for the first frame) | Exactly the kind of problem a weak chip has (high that it is fixed). Workaround from #7: stop mirroring on the iPad, wait about 5 s, mirror again. |
| H.265 decoder ignored (MediaTek). [#51](https://github.com/jqssun/android-airplay-server/issues/51) | Fixed after 0.0.31 | On "auto", hardware H.265 is trusted only if the decoder's name is on an allowlist, or if it reports low-latency support (Android 11+) or a high media performance class. The allowlist has no Allwinner prefix but takes any `c2.` (Codec2) decoder. The H.265 setting can now force it on and skip the list. Apple senders switch to H.265 only when the receiver asks for more than 1080p, so at this projector's 1920x1080 H.264 is used anyway (medium; maintainer's statement in #51). *(Corrected in verification: the original said "Allwinner is not on it" and "720p projector".)* [DecoderSelector.kt](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/app/src/main/kotlin/io/github/jqssun/airplay/renderer/DecoderSelector.kt), [02a data](02a-feasibility-data.json) |
| Screensaver or sleep during mirroring when started at boot (Android TV 9). [#9](https://github.com/jqssun/android-airplay-server/issues/9) | Fixed 5 Jul 2026 | Relevant because boot start is planned. Check that the projector's own sleep timer does not cut in. |
| TV turns itself off during sessions (Fire TV). [#38](https://github.com/jqssun/android-airplay-server/issues/38) | Closed by the reporter the same day, saying they had missed an earlier issue (probably #9); cause not stated | Same check as above. |
| PIN not shown on Android TV launchers (HY300, H713, Android 11, 32-bit). [#52](https://github.com/jqssun/android-airplay-server/issues/52) | Fixed after 0.0.31 | Directly relevant; it is the reason to use the GitHub build. |
| AirPlay video (HLS) fails; volume locked at 100%. [#49](https://github.com/jqssun/android-airplay-server/issues/49), [#53](https://github.com/jqssun/android-airplay-server/issues?q=is%3Aissue) | Fixed after 0.0.31 | Same as above. |
| Upstream UxPlay's YouTube (HLS) handling is fragile. [UxPlay #550](https://github.com/FDH2/UxPlay/issues/550): a crash when a video ends or the user seeks. It sits in desktop UxPlay's X11 full-screen code, which the app does not use (it plays HLS with its own ExoPlayer), but the maintainer says HLS "needs work" on end of stream and ad breaks. [UxPlay #596](https://github.com/FDH2/UxPlay/issues/596): YouTube from an iPad stays black when the iPad re-pairs mid-session and the playlist arrives on a different connection; not a crash. *(Corrected in verification: the original described both as crashes.)* | Both open upstream | The app carries its own HLS patches (0001 to 0003, 0009). Whether they cover these cases is unknown. YouTube video is the least certain feature. [patches](https://github.com/jqssun/android-airplay-server/tree/main/app/src/main/cpp/patches/UxPlay) |

- **Performance on 1 GB RAM:** there are no reports on the H713 beyond the #52 user saying mirroring "starts once the PIN is entered" (high that nothing more exists in the tracker). [issues](https://github.com/jqssun/android-airplay-server/issues?q=is%3Aissue)
- If the picture stutters, lower the `resolution` (for example `1280x720`, below the panel's native 1920x1080 from the factory spec sheet in earlier research) and `max_fps` (for example 30). Also avoid software decoding: on four Cortex-A53 cores it is unlikely to keep up with 1080p (low: inference). *(Corrected in verification: the original called 1280x720 the native size; 02a says 1920x1080, and 720p is the different "HY320 Mini".)* [Prefs.kt](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/app/src/main/kotlin/io/github/jqssun/airplay/Prefs.kt), [02a data](02a-feasibility-data.json)

## Can only be confirmed on the unit

1. Mirroring from the iPad (iPadOS 26.6.2) starts and keeps running. Also check audio-only AirPlay, and YouTube video once the projector has internet.
2. The SELinux mode (`getenforce`), and whether mirroring survives past the first second (#50).
3. Which video decoders the firmware offers: names, and whether H.264 at the panel resolution plays smoothly. Check FPS and dropped frames in the debug overlay.
4. Memory headroom with 1 GB of RAM while mirroring, alongside the launcher and kept features.
5. Whether "Display over other apps" can be granted on this firmware, and whether the build is low-RAM (Go-style) (`getprop ro.config.low_ram`).
6. After a cold boot, the server is running and the iPad sees the projector without the app being opened. Also check that Wi-Fi coming up late does not hide it.
7. How the PIN behaves: asked once per iPad or on every connection.
8. The open ports seen from the router side: TCP 7000 while idle, nothing else from this app.
9. Whether the projector's sleep timer or screensaver interrupts long sessions.
10. Whether the projector's USB port can do USB tethering. Only matters for the wired display feature.

## Verification

An independent check on 2026-10-19. I reopened every cited source and read the app's dependency catalogue, `SettingsReceiver.kt`, patches 0004 and 0009, UxPlay's `raop_handlers.h`, and the UxPlay issues again. Corrections made in place are marked *(Corrected in verification)* above, or listed below as "fixed".

| # | Key claim | Verdict | Note | Source |
|---|---|---|---|---|
| 1 | v0.0.36 is the newest GitHub release, 19 Oct 2026, after v0.0.32 to v0.0.35 on 16 to 19 Oct | confirmed | Titles: 0.0.34 "api", 0.0.35 "pin", 0.0.36 "decoder". 0.0.31 came out on GitHub on 23 Aug. | [releases](https://github.com/jqssun/android-airplay-server/releases) |
| 2 | `app-release.apk` is 26.1 MB, SHA-256 `b8c7c595…cf2a4` | confirmed | The digest on the release page matches character for character. | [v0.0.36 files](https://github.com/jqssun/android-airplay-server/releases/expanded_assets/v0.0.36) |
| 3 | F-Droid's newest is 0.0.31 (26 Aug 2026); its recipe says CurrentVersion 0.0.33 | confirmed | 0.0.33 is in the recipe's Builds list but not yet on the site. | [F-Droid page](https://f-droid.org/en/packages/io.github.jqssun.airplay/), [recipe](https://gitlab.com/fdroid/fdroiddata/-/raw/master/metadata/io.github.jqssun.airplay.yml) |
| 4 | Built by GitHub Actions on a tag push, signed with `upload.jks` | confirmed | The workflow also runs on `release/**` branches and by hand. | [workflow](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/.github/workflows/apk.yml) |
| 5 | One universal APK with `armeabi-v7a`; minSdk 23, targetSdk 37 | confirmed | No `splits` block. The maintainer confirms "universal package for now" in #53. | [build file](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/app/build.gradle.kts), [#53](https://github.com/jqssun/android-airplay-server/issues/53) |
| 6 | Pinned signing key `64ca1fa3…f1a9`, defined as the lowercase SHA-256 of the signing certificate, read with apksigner or keytool | confirmed | | [recipe](https://gitlab.com/fdroid/fdroiddata/-/raw/master/metadata/io.github.jqssun.airplay.yml), [F-Droid reference](https://f-droid.org/docs/Build_Metadata_Reference/) |
| 7 | GitHub computes a SHA-256 for each asset at upload | confirmed | | [GitHub changelog](https://github.blog/changelog/2025-06-03-releases-now-expose-digests-for-release-assets/) |
| 8 | `Get-FileHash` uses SHA-256 by default and prints upper case | confirmed | | [Get-FileHash](https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/get-filehash) |
| 9 | F-Droid publishes the developer-signed APK only when its rebuild matches, and otherwise skips that version | confirmed | | [Reproducible builds](https://f-droid.org/docs/Reproducible_Builds/) |
| 10 | GitHub and F-Droid builds share one key | confirmed (maintainer's statement) | Quote: "GitHub releases use the same signing keys as the F-Droid ones". | [#7](https://github.com/jqssun/android-airplay-server/issues/7) |
| 11 | No tracking libraries | confirmed for direct dependencies | `libs.versions.toml` lists only AndroidX, Media3, Compose, Hilt, coroutines and Oboe. Transitive dependencies were not checked. | [libs.versions.toml](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/gradle/libs.versions.toml) |
| 12 | A Play copy may carry a different certificate | unverified (inference) | Android's docs say Google re-signs with the app signing key unless the developer supplies their own. Which choice this developer made is unknown. | [Android app signing](https://developer.android.com/studio/publish/app-signing) |
| 13 | iOS/iPadOS 26.0 and 26.1 broke AirPlay PIN and pairing for third-party receivers; fixed in 26.2 | confirmed | Prowise names a PIN that does not show and having to tap the receiver twice. | [Prowise](https://service.prowise.com/hc/en-gb/articles/29653730908178-AirPlay-issues-resolved-by-update-to-iOS-iPadOS-macOS-26-2) |
| 14 | The UxPlay maintainer confirms iOS 26.6 works | confirmed | 4 Aug 2026. The reporter's problem was their own mistake. | [UxPlay #547](https://github.com/FDH2/UxPlay/issues/547) |
| 15 | iPadOS 26.6.2 only fixes software updates over cellular; nothing about AirPlay from 26.2 to 26.7.1 | confirmed | | [Apple](https://support.apple.com/en-hk/123074) |
| 16 | The iOS 27 issue is only "(probably?) fixed" | confirmed | Still open, tested on betas only. | [UxPlay #535](https://github.com/FDH2/UxPlay/issues/535) |
| 17 | UxPlay may lose "Legacy Protocol" in future iOS versions | confirmed | | [UxPlay README](https://github.com/FDH2/UxPlay) |
| 18 | HLS video works only for YouTube | partly, fixed | True for upstream UxPlay. The app's patch 0004 lifts the YouTube-only check and adds direct http(s) URLs, so it fetches from any video host. | [patch 0004](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/app/src/main/cpp/patches/UxPlay/0004-video-sender-compat.patch) |
| 19 | Features list, no DRM | confirmed | The README does not mention Google Cast or Miracast at all. "Not supported" is right for an AirPlay-only app, but it is an inference from that silence. | [README](https://github.com/jqssun/android-airplay-server) |
| 20 | Defaults (name "Android AirPlay", port 7000, PIN off, boot start on, and so on) | confirmed | One row added: `sync_client_volume` defaults to on (see 24). | [Prefs.kt](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/app/src/main/kotlin/io/github/jqssun/airplay/Prefs.kt) |
| 21 | SettingsReceiver is guarded by `android.permission.DUMP` | confirmed | Also: open the app before `LIST_SETTINGS`, the JSON comes back as result data, and unknown keys are refused. Added in place. | [manifest](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/app/src/main/AndroidManifest.xml), [SettingsReceiver.kt](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/app/src/main/kotlin/io/github/jqssun/airplay/SettingsReceiver.kt) |
| 22 | PIN text says "each new connection"; fixed PIN 1234 if generation fails | confirmed | The PIN is passed to UxPlay as `pin + 10000`. UxPlay trusts clients that come back without `-reg`, so "once per iPad" is plausible. Still observe it on the unit. | [strings](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/app/src/main/res/values/strings.xml), [native_bridge.cpp](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/app/src/main/cpp/native_bridge.cpp), [UxPlay README](https://github.com/FDH2/UxPlay) |
| 23 | #52 on an HY300 (H713, Android 11, 32-bit) with v0.0.31, closed 19 Oct; "the only free receiver…"; background start allowed by SYSTEM_ALERT_WINDOW | confirmed | | [#52](https://github.com/jqssun/android-airplay-server/issues/52) |
| 24 | #49, #51 and #53 fixed in "the latest build", closed 19 Oct | confirmed, fixed | #53 had a search link. The maintainer adds that the volume fix needs "Sync sender volume" turned off. Both added in place. | [#49](https://github.com/jqssun/android-airplay-server/issues/49), [#51](https://github.com/jqssun/android-airplay-server/issues/51), [#53](https://github.com/jqssun/android-airplay-server/issues/53) |
| 25 | mDNS through Android NSD; `_airplay._tcp` always, `_raop._tcp` when audio is advertised, both on the server port | confirmed | NSD does not re-register after a network change. | [AirPlayService.kt](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/app/src/main/kotlin/io/github/jqssun/airplay/service/AirPlayService.kt), [NsdServiceManager.kt](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/app/src/main/kotlin/io/github/jqssun/airplay/discovery/NsdServiceManager.kt) |
| 26 | TCP 7000 on `INADDR_ANY` and `in6addr_any`, at most 12 connections | confirmed | IPv6 is skipped if it fails ("Continuing without IPv6 support"). The 12 comes from UxPlay's `MAX_CONNECTIONS`, not from the app. | [httpd.c](https://raw.githubusercontent.com/FDH2/UxPlay/master/lib/httpd.c), [netutils.c](https://raw.githubusercontent.com/FDH2/UxPlay/master/lib/netutils.c) |
| 27 | Session ports are random: all start at 0, and the app never calls `raop_set_*_ports` | confirmed | The UxPlay README says ports are random without `-p`. `eventPort` is 0, so no socket opens for it. The NTP timing port is one of the UDP ports. | [raop.c](https://raw.githubusercontent.com/FDH2/UxPlay/master/lib/raop.c), [raop_handlers.h](https://raw.githubusercontent.com/FDH2/UxPlay/master/lib/raop_handlers.h), [native_bridge.cpp](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/app/src/main/cpp/native_bridge.cpp) |
| 28 | DACP remote control: HTTP to the iPad's `_dacp._tcp` port | confirmed | | [DacpController.kt](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/app/src/main/kotlin/io/github/jqssun/airplay/audio/DacpController.kt) |
| 29 | Apple's port list includes TCP 5000/6000/7000 | confirmed | | [Apple ports](https://support.apple.com/en-us/103229) |
| 30 | Boot receiver for `BOOT_COMPLETED` and `QUICKBOOT_POWERON`; foreground service with a low-importance channel; no retry on failure; no network-change restart | confirmed | | [manifest](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/app/src/main/AndroidManifest.xml), [BootReceiver.kt](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/app/src/main/kotlin/io/github/jqssun/airplay/BootReceiver.kt), [AirPlayService.kt](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/app/src/main/kotlin/io/github/jqssun/airplay/service/AirPlayService.kt) |
| 31 | Apps never opened or force-stopped get no broadcasts | confirmed | | [Android 3.1](https://developer.android.com/about/versions/android-3.1#launchcontrols) |
| 32 | SYSTEM_ALERT_WINDOW lets an app start activities from the background (Android 10+) | confirmed | | [background starts](https://developer.android.com/guide/components/activities/background-starts) |
| 33 | Android Go turns PiP and "draw over other apps" off by default | confirmed | The page does not name `ro.config.low_ram`. AOSP's Go defaults set that property, per a build commit; that link is a secondary source. | [Android Go](https://developer.android.com/guide/topics/androidgo), [AOSP commit](https://android.googlesource.com/platform/build/+/7267676%5E%21/) |
| 34 | `hasLocalNetwork` always passes on Android 11 | confirmed | | [Permissions.kt](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/app/src/main/kotlin/io/github/jqssun/airplay/Permissions.kt) |
| 35 | #50: SELinux blocks `/dev/ashmem` on a Hisense TV (Android 10, enforcing); still open | confirmed | The comment thread did not render, so "no maintainer reply" is unverified. The Android 10 rule applies to apps that target API 29 or newer, which this app does. Wording fixed. | [#50](https://github.com/jqssun/android-airplay-server/issues/50), [Android 10 changes](https://developer.android.com/about/versions/10/behavior-changes-10) |
| 36 | HY300 stock firmware is SELinux permissive | partly | Stated once, in the research repo's index. Not observed on an HY320. | [lolmam](https://github.com/lolmam/HY300-H713-Research) |
| 37 | #30/PR #31 fixed 16 Jul 2026; #7 workaround of about 5 s | confirmed | The reporter confirmed the fix on 17 Jul. | [#30](https://github.com/jqssun/android-airplay-server/issues/30), [#7](https://github.com/jqssun/android-airplay-server/issues/7) |
| 38 | H.265 only for allowlisted decoders; Allwinner is not on the list | partly, fixed | No Allwinner prefix, but any `c2.` decoder is allowlisted, and decoders that report low latency pass on Android 11+. The setting can now force H.265. The H713's decoder names were not found online. | [DecoderSelector.kt](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/app/src/main/kotlin/io/github/jqssun/airplay/renderer/DecoderSelector.kt), [#51](https://github.com/jqssun/android-airplay-server/issues/51) |
| 39 | Projector is 720p / panel native 1280x720 "per earlier research" | refuted, fixed | 02a (high, from the factory spec sheet) gives 1920x1080 for the Android 11 HY320. 720p is the "HY320 Mini". I did not reopen the spec sheet; it is the source 02a cites. Confirm the panel on the unit. | [02a data](02a-feasibility-data.json), [spec sheet](https://p.globalsources.com/IMAGES/PDT/SPEC/161/K1214116161.pdf) |
| 40 | #9 fixed 5 Jul 2026 | confirmed | Fixed in commit 8a3cc4c. | [#9](https://github.com/jqssun/android-airplay-server/issues/9) |
| 41 | #38 closed by the reporter "as a duplicate" | partly, fixed | Closed as completed with "didn't see the other issue". The word "duplicate" is not used. | [#38](https://github.com/jqssun/android-airplay-server/issues/38) |
| 42 | UxPlay #550 and #596 are HLS crashes | partly, fixed | #550 is a crash in desktop X11 full-screen code that the app does not use. #596 is an iPad YouTube black screen after re-pairing, not a crash, and has a direct link now. Both open. | [UxPlay #550](https://github.com/FDH2/UxPlay/issues/550), [UxPlay #596](https://github.com/FDH2/UxPlay/issues/596) |
| 43 | The app patches PIN pairing (0008) | confirmed | Patch 0004 also changes pairing: `use_pin` now sets only `register_check`. The effect on iPadOS is not documented. | [patches](https://github.com/jqssun/android-airplay-server/tree/main/app/src/main/cpp/patches/UxPlay), [patch 0004](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/app/src/main/cpp/patches/UxPlay/0004-video-sender-compat.patch) |

Nothing in the file was refuted beyond row 39. The overall conclusion holds: use the GitHub v0.0.36 APK, check both the hash and the certificate, and expect it to work with iPadOS 26.6.2 after a test on the unit.
