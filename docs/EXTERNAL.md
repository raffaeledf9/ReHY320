# What to fetch, and from where

Nothing in this list is in the repository. Three reasons, in order of how much
they matter:

1. **Signing keys must never be published.** The app signing key and the AVB key
   are generated on your machine, by you, and stay there. If you had mine you
   could sign an update that replaced an app on my projector.
2. **The vendor's code is not mine to redistribute.** The projector's stock
   firmware, its settings app and its Miracast receiver belong to the people who
   wrote them. You already have a copy: it is on your projector.
3. **Everything else is better fetched from its own author**, at a version you
   can check, than copied through here.

Every digest below is SHA-256 of the file as downloaded, recorded on
2026-10-30. Check them. A mismatch is not a formality — these are the things
that get root on your projector.

---

## Host tools

| tool | where | note |
|---|---|---|
| Android SDK platform-tools | <https://developer.android.com/tools/releases/platform-tools> | `adb`, `fastboot` |
| Android SDK build-tools + platform-30 | Android Studio, or `sdkmanager` | `aapt2`, `d8`, `apksigner`, `zipalign` — needed to build the two apps |
| JDK 17 or newer | any distribution | `javac`, `keytool` |
| Python 3.11+ with Pillow | <https://www.python.org/> | the analysis scripts and the icon generators |
| `avbtool` | <https://android.googlesource.com/platform/external/avb/+/refs/heads/main/avbtool.py> | AOSP, Apache-2.0. Put it at `keys/avbtool`. |

The build script looks for the SDK at `%LOCALAPPDATA%\Android\sdk`. Pass `-Sdk`
if yours is elsewhere.

## Apps installed on the projector

| app | version | where | sha256 |
|---|---|---|---|
| Magisk | v30.7 | <https://github.com/topjohnwu/Magisk/releases> | `e0d32d2123532860f97123d927b1bb86c4e08e6fd8a48bfc6b5bee0afae9ebd5` |
| Material Files | 1.7.5 (40) | <https://f-droid.org/packages/me.zhanghai.android.files/> | `2fe900bf43d725b655008d438f5ca46d0da0f301e3784403b5b96c3fc2df6e8a` |
| android-airplay-server | 0.0.36 | <https://github.com/jqssun/android-airplay-server/releases> | `b8c7c595ed93f91562feedce92c27800f08f9c84df424f6ac2045e82324cf2a4` |

`scripts/apps/fetch.ps1` downloads the last two, checks the file digest **and**
the signing certificate, and refuses anything that does not match. Magisk is
fetched by hand because you should read its release notes before rooting
anything.

The two apps in this repository — `app/` and `keyboard/` — are built from
source by `app/build.ps1`. Nothing is downloaded for them.

VLC, a calculator, and anything else come from the Play Store afterwards, if you
want them. Nothing here depends on them.

## Things that only exist on your own projector

These cannot be downloaded and are not in the repository. Take them off your own
device before you change anything.

| what | why you need it | how to get it |
|---|---|---|
| Your stock partitions | the undo for every step, and the thing you verify against | `scripts/` — see [REPRODUCE.md](REPRODUCE.md) step 1 |
| `MiracastReceiver.apk` | optional; the Magisk module in `magisk/hy320_miracast/` puts it back after cleaning | pull it from your own `/system/app` **before** cleaning. On this unit: sha256 `5796233b345d01ad34ecd7ed8c6aa0d3af95ffef0517f397e2b5d7bcf8b60868`, signed by the same certificate as 33 other system apps. |
| The projector's own icons | `app/assets/icon_mode_*.png` — the tiles in the projector menu | they came out of the vendor settings app on this unit. They are in the repository because they are 20 small pictures of a lamp and a trapezoid, and because this project is for people who own the device they came from. If that sits badly with you, delete them and run `art/make-art.py`, which draws replacements. |

## Keys you generate yourself

| key | made by | used for |
|---|---|---|
| app signing key | `app/build.ps1` on first run, into `app/projector-tools.keystore` | signing the two apps so later versions update in place |
| AVB key | `scripts/verity/` — see [REPRODUCE.md](REPRODUCE.md) | re-signing `vbmeta` after the system partition changes |

Both are in `.gitignore`. Keep the keystore: if you lose it, the next build
cannot update the installed app and you have to uninstall first. Keep the AVB
key for as long as you intend to modify partitions again.

---

## A note on the Play Store

The projector reports itself as an ADT-3 — the identity is in the stock
firmware, not something this project did. The Play Store signs in and installs,
but the device is **not Play Protect certified**, so some apps will not appear
and anything wanting Widevine will not work properly. There are no DRM keys on
this hardware at all; paid streaming is standard definition at best. The runbook
has the measurements.
