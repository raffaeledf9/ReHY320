# HY320 Projector: Feasibility of a Clean, AirPlay-Capable Rework

## 1. Verdict

Feasible, with real caveats. You can turn this into a simple, reliable, APK-installing Android box that **receives AirPlay** — the feature you care most about — using free, open-source software, at roughly zero hardware cost. The honest limits: (a) you cannot make it *trustworthy* and *fully offline at the same time*, because AirPlay needs the projector back on a network; (b) you almost certainly cannot get genuine **Google Chromecast** (Chromecast built-in) on it at all — that is cryptographically locked to Google-certified hardware; and (c) before you flash anything you must first confirm which chip your unit actually runs, because "HY320" is several different products. The safe, low-effort target is: **cleaned firmware + a lightweight launcher + an open-source AirPlay receiver app, kept on a network segment with its internet access blocked at your router.** Budget a weekend, some brick risk if you flash the wrong image, and the permanent assumption that this device is low-trust no matter what you do.

## 2. Per-goal feasibility

| Goal | Feasible? | How | Limits |
|---|---|---|---|
| Clean / trustworthy system | Partly | Reflash a community "clean" image or root-and-delete the malicious dirs yourself; keep it network-isolated | Even a cleaned base keeps test-signing keys, permissive SELinux and open services. Treat as permanently low-trust. |
| Simple, reliable launcher | Yes | Install Projectivy (or FLauncher), set it as default, add tiles for HDMI input and Settings | Setting default launcher can be fiddly on Android 11; install the new one *before* disabling the stock one. |
| Install APKs | Yes | Sideload via ADB or a file manager; F-Droid works | 32-bit (armeabi-v7a) userspace on H713 — arm64-only APKs won't install. 1 GB RAM is tight. |
| AirPlay screen mirroring | Yes | Open-source "AirPlay Server" by jqssun (F-Droid), built on UxPlay | Young, fast-moving app; F-Droid 0.0.31 (26 Aug 2026) ships an armeabi-v7a build, needs Android 7+; no reports on this exact SoC — test it. Phone and projector must share a subnet. |
| AirPlay video (HLS, e.g. YouTube) | Partly | Same app handles HLS playback | May need the projector to reach content servers — conflicts with a full internet block. Test with egress blocked. |
| Google Cast (Chromecast built-in) | No | — | Senders verify a factory-provisioned, Google-signed device key. Uncertified hardware fails ("couldn't be verified"). No success report exists on any such box. |
| Partial "cast"-like features | Partly | AirScreen (paid, closed-source) does partial Cast; YouTube "Link with TV code" via SmartTube works without Cast | AirScreen is subscription/ad, China-based, tracker-flagged. SmartTube had a supply-chain compromise in late 2025 — official source only. |
| DRM apps (Netflix etc.) | Poor | Native apps only, at low resolution | Widevine L3 (likely), no Google Play. Netflix ~540p, Prime ~480p. Netflix also dropped phone→TV casting for most devices in late 2025. |

## 3. Malware reality check

**The "htc" apps are not HTC.** On this projector family the "htc"/"hotack" package prefix is the OEM's own namespace (Hotack, the Chengdu manufacturer) — a thin disguise, not the phone company. The article you read is almost certainly Zane St. John's 5 Feb 2026 teardown of a Hotack-built Magcubic projector, which names exactly those packages. Independent coverage followed (CERT.gov.az, TuttoAndroid, an FBI PSA listing "digital projectors" among BADBOX 2.0 devices).

**Why uninstalling wasn't enough.** On the sibling H713 units that have been analysed, the malicious components ship as **firmware system apps on read-only partitions**. Removing them through Settings or `pm uninstall --user 0` only hides them *for your user* — the files stay on the partition, a factory reset brings them back, and an OTA/update component plus a startup script can re-add them. At least one owner reported the packages and their DNS traffic returning weeks after removal. Some builds also carry non-app weaknesses: a root helper started at boot, unauthenticated ADB on the network, permissive SELinux, and a device signed with the public AOSP test key (so anything signed with that key gets system privileges). The "lots of traffic" is the device being used as a residential-proxy node — your internet connection rented out to third parties.

**What this means for your decision:**
- **For offline HDMI-only use (what you do now): you are fine.** All the active stages need to reach their servers to do anything. Disconnected, it's inert.
- **To put it back on *any* network, in-place debloat is NOT enough.** The minimum safe step is a **reflash of an image with the malicious app directories and root binaries physically removed**, or rooting your own image and deleting them yourself. Even then, isolate it (see §5).
- **Caveat that bites your goal:** the stock AirPlay/casting receiver is part of the same vendor bundle. Removing the "htc" apps is very likely *why you lost AirPlay*. Restoring the vendor receiver brings back a phone-home component; better to replace it with the open-source app below.

Full technical detail and machine-readable indicator lists (domains/IPs to block, package names) live in the researchers' repos — see Sources. Load those lists straight into your Pi-hole/firewall rather than retyping them.

## 4. Options, ranked

**Option A — Reflash a cleaned image + Projectivy + open-source AirPlay app.** 
*Effort:* medium (identify board, back up, flash). *Risk:* medium brick risk if board mismatched; **trust risk is real** — the only community "HY300/HY320/L018 clean" image is an unaudited Google-Drive build from an anonymous author, ships pre-rooted (Magisk), and one commenter reports it still contacting the vendor OTA server. *You get:* debloated Android, clean launcher, APK install, AirPlay via the F-Droid app. *Cost:* €0. **Do not trust the image blindly — verify package list and outbound DNS after flashing.**

**Option B — In-place ADB debloat + launcher + AirPlay app, kept isolated.** 
*Effort:* low–medium. *Risk:* low brick risk; **trust: contains, does not cure** — system APKs remain on disk. *You get:* same user experience as A without flashing. *Cost:* €0. The pragmatic choice if you keep it strictly network-isolated and never factory-reset.

**Option C — Leave the projector offline; plug a trusted streamer into HDMI.** 
*Effort:* lowest. *Risk:* none to the projector; it stays unplugged from the network as today. *You get:* a cheap Apple TV gives flawless native AirPlay; a Google TV stick (Xiaomi TV Stick 4K ~€40, Google TV Streamer ~€120) gives *genuine* Chromecast + AirPlay (via an app) at Widevine L1. *Cost:* €40–300. **This is the only route that actually delivers real Chromecast, and it sidesteps the malware entirely.** The projector becomes a dumb, safe HDMI display.

**Option D — Mainline Linux + UxPlay.** 
*Effort:* high. *Risk:* high — the H713 Linux port is beta, verified only on a sibling model (HY310), no HY320 profile, hardware video decode unverified, no Bluetooth. *You get:* in theory a clean non-Android base running UxPlay for AirPlay — but it's not Android (no APKs, your stated goal), and it's not viable on your exact unit today. *Cost:* €0 + significant time. **Not recommended now.**

**Recommendation: C if you want real Chromecast and zero fuss; A or B (your call on flash-vs-contain) if you specifically want AirPlay *on the projector itself*.** A and B can be combined with C's logic — contain first, consider a streamer later.

## 5. Recommended path (step by step)

**Step 0 — Identify the exact board FIRST. This decides everything.** 
"HY320" is reused across very different hardware: the Android-11 H713 unit (the one with the htc/hotack apps, 1 GB/8 GB), an "HY320 Mini" 720p, and current Magcubic **HY320Pro / HY320F on the newer H726 chip with Android 14** — for which none of the H713 tooling below is documented. Your unit showing Android 11 + htc apps points to H713, but confirm it. Over ADB (USB debugging, no network needed):
```
adb shell getprop ro.build.fingerprint
adb shell getprop ro.board.platform
adb shell getprop ro.product.device
adb shell getprop ro.hardware
adb shell pm list packages -u
```
Also read the PCB silkscreen (e.g. `HYxxx_QZ713…`) and the panel resolution. **Do not flash any image built for a different board or panel** — wrong DRAM/panel parameters brick the unit or give a fuzzy picture. Note: the only community "HY320" image is tagged 720p; if your panel is 1080p, that is a mismatch to resolve before flashing.

**Step 1 — Back up the whole eMMC before touching anything.** On the sibling units the raw storage is world-readable over ADB without root:
```
adb exec-out "dd if=/dev/block/mmcblk0 bs=1M" > hy320_full.img
```
Keep this image forever. The SoC's USB recovery (FEL) mode is in ROM and cannot be erased by software, so a bad flash is recoverable **only if you have this dump plus your device-unique partitions.** Verify the dump's size looks right before proceeding.

**Step 2 — Decide flash (A) vs contain (B).** 
- *Contain (B):* factory-reset while on a no-internet network (so no downloaded payloads linger), then `pm disable-user --user 0` the vendor malware/OTA packages and fully `pm uninstall` anything unrecognised from `pm list packages -3`. Accept that system APKs remain on disk.
- *Flash (A):* only with Step 1 done and the board confirmed. Prefer rooting your *own* backed-up image and deleting the malicious `/product` directories to flashing a stranger's pre-built image. Use "keep data", not wipe options. Know your FEL recovery route before you start.

**Step 3 — Launcher + inputs.** Install Projectivy, set it as default (use its "override current launcher" option; disable the stock launcher only *after* the new one works). Add tiles for HDMI input (`am start -n com.softwinner.awlivetv/.MainActivity`) and Settings. Keep the autofocus app, and keep the stock launcher only if you need its keystone UI.

**Step 4 — AirPlay receiver.** Install **"AirPlay Server" by jqssun** from F-Droid (open-source, GPL, no DRM). Enable its PIN option. Note F-Droid may lag the latest GitHub build — if you hit the known HLS/H.265 bugs, grab the newer release from the project's GitHub.

**Step 5 — Network containment (this is the safety-critical part).** Put the projector where it can see your iPhone but not the internet:
- A dedicated IoT VLAN or a guest SSID.
- **Block all WAN egress from the projector at the firewall by IP/MAC — not just by DNS.** Hardcoded server IPs exist, so DNS sinkholing alone leaks. (If HLS video casting needs outbound access, open only what's required and watch the logs.)
- Block IoT→LAN except replies to sessions your iPhone starts.
- Because AirPlay discovery (mDNS, UDP 5353) doesn't cross subnets, either keep the iPhone on the same segment while casting, or run a filtered mDNS reflector limited to `_airplay._tcp` / `_raop._tcp`, plus firewall rules for the (dynamic) session ports. Turn off AP/client isolation on that SSID.

**Step 6 — Verify from the network, not the device.** The device has root backdoors, so don't trust what it says about itself. Check from your router/firewall:
- Firewall + connection-tracking logs: every outbound attempt from the projector should be dropped and logged.
- Pi-hole query log loaded with the published indicator lists (from the Sources repos).
- An `nmap` of the projector for backdoor listeners (e.g. unauthenticated ADB) — but ignore the normal AirPlay receiver ports, which overlap some published "signatures."

## 6. Open risks & unverified items

- **No analysis targets the HY320 by name.** All malware/hardware detail comes from sibling models (HY300 Pro/Pro+, HY310, L018, HY260Pro). Your unit *probably* matches, but confirm on the device.
- **H713 vs H726.** If yours is the newer H726/Android 14 HY320Pro/HY320F, the flashing tools, root methods and "clean" image above are not documented for it; Magcubic claims H726 units are unaffected (disputed by community reports on other H726 models).
- **Community "clean" image trust.** Unaudited, anonymous, pre-rooted, one report of residual OTA contact. Switching from vendor malware to an unverified rooted image is not automatically an improvement — verify after flashing.
- **AirPlay with WAN fully blocked.** Whether HLS/video casting (vs plain mirroring) keeps working once internet is blocked is untested on this hardware — try it.
- **iOS currency.** Apple's iOS 26 pairing changes temporarily broke third-party receivers (fixed in 26.2); UxPlay (the engine under the F-Droid app) is confirmed working on iOS 26.6 and probably on iOS 27 betas, but Apple could drop the legacy protocol in a future release.
- **Anti-rollback.** The USB update path may refuse an older image; overriding needs a serial console.
- **Performance.** 1 GB RAM + weak GPU; real-time 1080p AirPlay mirroring is plausible but unproven on this SoC — test before relying on it.
- **Chromecast is out.** Treat "add Chromecast" as achievable only via an external Google TV device (Option C), not via firmware.

## 7. Sources

Malware teardown & indicators (packages, C2 domains/IPs for blocklists):
- Zane St. John, 5 Feb 2026 — https://zanestjohn.com/blog/reing-with-claude-code
- Kavan00, Android-Projector-C2-Malware — https://github.com/Kavan00/Android-Projector-C2-Malware
- maximilian-sh, hy350max-badbox-removal (IOC lists) — https://github.com/maximilian-sh/hy350max-badbox-removal
- micha102, hy300pro-debloat (incl. HY320 data point) — https://github.com/micha102/hy300pro-debloat
- florentineprinzessinzusachsen, badbox-h713-projector — https://github.com/florentineprinzessinzusachsen/badbox-h713-projector
- CERT.gov.az — https://www.cert.gov.az/en/news/a-35-projector-has-turned-into-a-source-of-hidden-cyberthreats
- FBI PSA (BADBOX 2.0, lists projectors) — https://www.ic3.gov/PSA/2025/PSA250605

Hardware, flashing, root, backup (H713):
- lolmam, HY300-H713-Research — https://github.com/lolmam/HY300-H713-Research
- well0nez, magcubic-root — https://github.com/well0nez/magcubic-root
- well0nez, allwinner-h713-linux — https://github.com/well0nez/allwinner-h713-linux
- probonopd gist (HY300 Pro+ partitions) — https://gist.github.com/probonopd/3ad6b7777caea1503f00d5fe7710ad06
- Community "clean" firmware (unverified) — https://androidpctv.com/firmware-magcubic-hy300-hy320/
- Magcubic HY320Pro (H726) — https://www.magcubic.com/products/magcubic-projector-hy320pro
- Magcubic official statement — https://www.magcubic.com/pages/official-statement-regarding-certain-apk-files-on-magcubic-hy300-series-products

AirPlay / Cast software:
- AirPlay Server (jqssun, F-Droid) — https://f-droid.org/en/packages/io.github.jqssun.airplay/ and https://github.com/jqssun/android-airplay-server
- UxPlay — https://github.com/FDH2/UxPlay
- Google Cast device authentication (why Chromecast is locked) — https://tristanpenman.com/blog/posts/2025/03/22/chromecast-device-authentication/
- SmartTube (supply-chain note) — https://github.com/yuliskov/SmartTube ; https://bleepingcomputer.com/news/security/smarttube-youtube-app-for-android-tv-breached-to-push-malicious-update

Networking / AirPlay ports:
- Apple AirPlay ports — https://support.apple.com/en-us/103229
- Avahi reflector (filtered mDNS) — https://manpages.debian.org/avahi-daemon.conf(5)
- Krebs, Kimwolf botnet (why LAN isolation matters) — https://krebsonsecurity.com/2026/01/the-kimwolf-botnet-is-stalking-your-local-network/

Hardware alternatives:
- Xiaomi TV Stick 4K 2nd Gen — https://www.notebookcheck.net/Upgraded-Xiaomi-TV-Stick-4K-now-available-in-more-countries.1150436.0.html
- Apple TV 4K specs — https://www.apple.com/apple-tv-4k/specs/