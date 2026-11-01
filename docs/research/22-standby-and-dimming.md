# 22 Standby, dimming and the screensaver: findings

Researched 2026-10-22 for ticket [22](../decisions/22-standby-and-dimming.md). Sources: Android 11 platform source (AOSP, the `android11-release` branch), source.android.com, the AirPlay app's own source, and this unit's own files — the live inventory in [unit/20261019-222433](../reference/stock-unit) and the golden backup on the PC. Four things were read out of the backup images on the PC with `debugfs` and `strings` (the vendor screensaver manifest, the `blank_screen` program, the vendor thermal config, the TvSettings class list). Nothing was run, and the projector was not connected.

Confidence marks: **high** means read in Android source code, in official docs, or in this unit's own files; **medium** means one first-party statement or a sound inference from code; **low** means inference or anecdote.

## Short answer

- **Four separate things can take the picture away on Android 11**, and they are not the same knob:
  1. `system screen_off_timeout` — with the screensaver armed (`secure screensaver_activate_on_sleep` = 1) this is *when the screensaver starts*, not when the screen dies. That is plain AOSP behaviour, not TV-specific; a TV build is just where the screensaver is normally armed.
  2. `secure sleep_timeout` — when the display actually switches off, ending the screensaver. Default: `-1`, never.
  3. `global stay_on_while_plugged_in` — if non-zero and the device counts as plugged in, nothing ever dims at all.
  4. `secure attentive_timeout` ("inattentive sleep") — a hard cut-off that **ignores wake locks** and so kills the picture mid-film. Default: `-1`, off.
- **There is no separate `screensaver_timeout` setting in Android 11.** The screensaver fires at `screen_off_timeout`. Anything you read about a `screensaver_timeout` key does not apply to this platform version.
- **The vendor screensaver is already a plain Android screensaver.** `com.htc.screensaver/com.htc.screensaver.ScreenSaverService` declares `android.service.dreams.DreamService` and `BIND_DREAM_SERVICE`. Ticket 19's app is a drop-in replacement, not a new mechanism.
- **Correction to the brief's premise (ticket 22 itself says nothing about a Settings app): this unit has TvSettings, not the phone Settings app.** `com.android.settings` is not installed; `com.android.tv.settings` is. That is good news — its **Screen saver** screen already lets the user pick the active screensaver and choose the start delay from 5 / 15 / 30 min / 1 h / 2 h. Ticket 19 needs no timeout UI of its own.
- **A 30-minute default needs no code either**: AOSP TvSettings' own built-in default for that delay is already 30 minutes.
- **Video playback does hold the picture**, but only because players set a window flag, not because they are playing. A window with `FLAG_KEEP_SCREEN_ON` makes WindowManager hold a screen-bright wake lock, and that blocks both the screensaver and screen-off. ExoPlayer's `setWakeMode` does **not** do this — it is a CPU lock for background audio.
- **AirPlay mirroring is fine**: the chosen app has a `keep_screen_on` preference, **on by default**, and sets `FLAG_KEEP_SCREEN_ON` whenever at least one sender is connected.
- **`blank_screen` is not a dimmer.** It is the unmodified AOSP `hardware/interfaces/light/utils` tool, and AOSP init starts it only at power-off and thermal shutdown. On this unit it is almost certainly a no-op anyway: there is no light HAL implementation installed.
- **Nothing on the Android side can dim the lamp.** The thermal config only throttles the CPU. The fan is a kernel PWM driver. Whatever the projector hardware does to the LED on its own is outside Android and can only be seen on the unit.

## 1 What makes an Android 11 TV device dim or switch off when idle

### 1.1 `Settings.System.screen_off_timeout` — the screensaver's start delay

- `PowerManagerService.updateSettingsLocked()` reads `Settings.System.SCREEN_OFF_TIMEOUT`, default `DEFAULT_SCREEN_OFF_TIMEOUT` = 15 s. **High.** [PowerManagerService (android11)](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android11-release/services/core/java/com/android/server/power/PowerManagerService.java)
- The literal key is `screen_off_timeout`. **High.** [Settings.java (android11)](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android11-release/core/java/android/provider/Settings.java)
- When it expires, `updateWakefulnessLocked()` does **not** necessarily switch the screen off. It asks `shouldNapAtBedTimeLocked()`, which returns true if `screensaver_activate_on_sleep` is set, or if `screensaver_activate_on_dock` is set and the device is docked. True means `napNoUpdateLocked` → the screensaver runs. False means `goToSleepNoUpdateLocked` → the display goes off. **High.** (same file)
- **The TV Settings app calls this delay the screensaver's "when to start".** `DaydreamFragment` reads and writes exactly `Settings.System.SCREEN_OFF_TIMEOUT` for its `dreamTime` list, with `DEFAULT_DREAM_TIME_MS = 30 * MINUTE_IN_MILLIS` = 1,800,000 ms. **High.** [DaydreamFragment (android11)](https://android.googlesource.com/platform/packages/apps/TvSettings/+/refs/heads/android11-release/Settings/src/com/android/tv/settings/device/display/daydream/DaydreamFragment.java)
- **"Never" is not an option for this one.** `getScreenOffTimeoutLocked()` starts from the raw setting, applies only `Math.min` caps (device admin, a WindowManager override, `sleep_timeout`, `attentive_timeout`) and ends with one floor: `Math.max(timeout, mMinimumScreenOffTimeoutConfig)`. There is no upper clamp and no sentinel value. `config_minimumScreenOffTimeout` is 10,000 ms, so a negative or tiny value becomes **10 seconds**, not "never". **High.** [PowerManagerService](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android11-release/services/core/java/com/android/server/power/PowerManagerService.java), [config.xml (android11)](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android11-release/core/res/res/values/config.xml)
  - The practical "never" is a very large number, e.g. `2147483647` ms ≈ 24.8 days. It is accepted because nothing caps it from above, not because it is special. **High** for the code path; the 2147483647 trick as common practice is **medium** ([Scalefusion](https://blog.scalefusion.com/pl/how-to-disable-screen-timeout-on-android-devices/)).
- **The dimming the user sees is the last few seconds before that.** `getScreenDimDurationLocked()` returns `Math.min(config_maximumScreenDimDuration, screenOffTimeout * config_maximumScreenDimRatio)` — AOSP defaults 7,000 ms and 20%. So with a 20-minute timeout the picture dims for the final 7 seconds and then the screensaver or screen-off takes over. **High.** (same two files)

### 1.2 The screensaver framework and `Settings.Secure`

Keys, with their literal names, all confirmed in `Settings.java` (**high**):

| Key | Namespace | Meaning | Default when unset |
|---|---|---|---|
| `screensaver_enabled` | secure | screensaver allowed at all | `config_dreamsEnabledByDefault` = **true** |
| `screensaver_activate_on_sleep` | secure | run it instead of switching off when idle | `config_dreamsActivatedOnSleepByDefault` = **false** |
| `screensaver_activate_on_dock` | secure | run it when docked | `config_dreamsActivatedOnDockByDefault` = **true** |
| `screensaver_components` | secure | comma-separated flattened component names; the first valid one wins | `screensaver_default_component` |
| `screensaver_default_component` | secure | fallback | `config_dreamsDefaultComponent` (AOSP: the Deskclock screensaver) |

- Which keys exist and what reads them: `DreamBackend` (the Settings-side helper) touches only `SCREENSAVER_ENABLED`, `SCREENSAVER_ACTIVATE_ON_DOCK` and `SCREENSAVER_ACTIVATE_ON_SLEEP`, as `1`/`0`. **High.** [DreamBackend (android11)](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android11-release/packages/SettingsLib/src/com/android/settingslib/dream/DreamBackend.java)
- `DreamManagerService.getDreamComponentsForUser()` reads `Settings.Secure.SCREENSAVER_COMPONENTS`, splits it on commas, unflattens each entry, drops any whose service cannot be resolved ("Dream … does not exist"), and falls back to `SCREENSAVER_DEFAULT_COMPONENT`. **High.** [DreamManagerService (android11)](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android11-release/services/core/java/com/android/server/dreams/DreamManagerService.java)
- Config defaults as listed above. **High.** [config.xml](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android11-release/core/res/res/values/config.xml)
- **There is no `screensaver_timeout` in Android 11.** It is absent from `DreamBackend`, from `PowerManagerService`, and from the TV Settings screensaver screen, all of which use `screen_off_timeout` instead. **High** (three independent files, all read).
- One caveat worth knowing: `canDreamLocked()` refuses to dream when the device is not powered and `config_dreamsEnabledOnBattery` is false (AOSP default **false**). A mains-only projector should count as powered, and the vendor screensaver demonstrably works on this unit today, so this is not a blocker — but it is a device check. **High** for the code, **medium** for "this unit counts as powered". [PowerManagerService](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android11-release/services/core/java/com/android/server/power/PowerManagerService.java)

### 1.3 `Settings.Secure.sleep_timeout` — when the display really dies

- Read by `PowerManagerService.updateSettingsLocked()` as `Settings.Secure.SLEEP_TIMEOUT`, literal `sleep_timeout`, default `DEFAULT_SLEEP_TIMEOUT` = **-1**. `getSleepTimeoutLocked()` returns -1 for any value `<= 0`, meaning disabled. **High.**
- In `updateUserActivitySummaryLocked()`, once the screen-off timeout has lapsed: if `sleepTimeout >= 0`, the device is marked `USER_ACTIVITY_SCREEN_DREAM` only until last-activity + `sleepTimeout`, then it sleeps. If `sleepTimeout` is negative, `USER_ACTIVITY_SCREEN_DREAM` is set with no timeout — **the screensaver runs forever**. **High.**
- `sleep_timeout` also caps `screen_off_timeout` through `Math.min`, so it must be left at -1 or set *above* the screensaver delay; setting it below collapses the screensaver window to nothing. **High** (code), **medium** (the consequence is my reading).
- **This is TvSettings' "Energy saver → turn off screen after".** `EnergySaverFragment` reads and writes `Settings.Secure.SLEEP_TIMEOUT`, offers `-1` as "Never", and shows 24 h when unset. **High.** [EnergySaverFragment (android11)](https://android.googlesource.com/platform/packages/apps/TvSettings/+/refs/heads/android11-release/Settings/src/com/android/tv/settings/device/display/daydream/EnergySaverFragment.java)

**Watch the array names in AOSP — they are the opposite of what they sound like.** Confirmed by matching each fragment's logging values against the arrays (**high**, [arrays.xml](https://android.googlesource.com/platform/packages/apps/TvSettings/+/refs/heads/android11-release/Settings/res/values/arrays.xml)):

| TvSettings screen | Setting written | Array it offers | Values |
|---|---|---|---|
| Screen saver → when to start | `system screen_off_timeout` | `sleep_timeout_values` | 300000, 900000, 1800000, 3600000, 7200000 |
| Energy saver → turn off screen after | `secure sleep_timeout` | `screen_off_timeout_values` | 900000, 1800000, 3600000, 14400000, 28800000, 43200000, 86400000, **-1** |

### 1.4 `Settings.Global.stay_on_while_plugged_in` — "stay awake while charging"

- Read as `Settings.Global.STAY_ON_WHILE_PLUGGED_IN`, literal `stay_on_while_plugged_in`. `updateStayOnLocked()` sets `mStayOn = mBatteryManagerInternal.isPowered(setting)` when the value is non-zero (and no device-admin cap applies). **High.** [PowerManagerService](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android11-release/services/core/java/com/android/server/power/PowerManagerService.java)
- `mStayOn` makes `isBeingKeptAwakeLocked()` true, which makes `isItBedTimeYetLocked()` false, so **nothing idles at all — no dim, no screensaver, no screen-off**. **High.**
- It is a bitmask of `BatteryManager.BATTERY_PLUGGED_*`: 1 AC, 2 USB, 4 wireless; `7` is the Developer-options "Stay awake" setting; `0` is off. **High** for the bitmask use in code; **medium** for the exact 1/2/4 numbers (`BatteryManager` constants, not re-read here).
- **If the key is absent from the settings store, PowerManagerService falls back to `BatteryManager.BATTERY_PLUGGED_AC`, not to 0**: `updateSettingsLocked()` passes that as the default. So an *unset* `stay_on_while_plugged_in` on a mains-powered unit would stop the screensaver ever starting, and writing `0` explicitly is not a no-op. **High.** (same file)
- source.android.com's own TV standby page tells you to turn it off before testing idle behaviour, because it "might prevent the feature from turning off the screen". **High.** [TV standby](https://source.android.com/docs/core/power/tv-standby)

### 1.5 `Settings.Secure.attentive_timeout` — the one that beats wake locks

This is the dangerous one for "nothing may interrupt playback".

- Added in Android 11 as "inattentive sleep": a user-inactivity timeout after which the screen turns off. Build default `config_attentiveTimeout` = **-1** (feature off); `Settings.Secure.ATTENTIVE_TIMEOUT` (literal `attentive_timeout`) overrides it at runtime. **High.** [TV standby](https://source.android.com/docs/core/power/tv-standby), [config.xml](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android11-release/core/res/res/values/config.xml), [Settings.java](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android11-release/core/java/android/provider/Settings.java)
- `isAttentiveTimeoutExpired()` is `attentiveTimeout >= 0 && now >= mLastUserActivityTime + attentiveTimeout`. Once it is true, `isItBedTimeYetLocked()` stops consulting `isBeingKeptAwakeLocked()` and consults `isBeingKeptFromInattentiveSleepLocked()` instead — which covers stay-on, brightness boost, proximity and recent user activity, but **not** the stay-awake wake lock. And `updateWakefulnessLocked()` then calls `goToSleepNoUpdateLocked`, not `napNoUpdateLocked`: straight to screen-off, no screensaver. **High.** [PowerManagerService](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android11-release/services/core/java/com/android/server/power/PowerManagerService.java)
- Google's own test recipe for the feature is "start video playback to hold a screen wakelock … confirm the screen turns off when the timeout expires". That is exactly the behaviour to avoid here. **High.** [TV standby](https://source.android.com/docs/core/power/tv-standby)
- source.android.com is explicit about the scope: the feature overrides windows with `FLAG_KEEP_SCREEN_ON` and the `FULL_WAKE_LOCK`, `SCREEN_BRIGHT_WAKE_LOCK` and `SCREEN_DIM_WAKE_LOCK` levels; "Wakelocks with level `PARTIAL_WAKE_LOCK` aren't affected by this feature". A warning dialog appears a few seconds before the cut-off. **High.** [TV standby](https://source.android.com/docs/core/power/tv-standby)
- In TvSettings it is hidden behind a per-OEM resource: the `allowTurnScreenOff` switch, and the writing of `attentive_timeout` at all, happen only if `config_show_standby_timeout` is true. AOSP's default is **false**. **High.** [EnergySaverFragment](https://android.googlesource.com/platform/packages/apps/TvSettings/+/refs/heads/android11-release/Settings/src/com/android/tv/settings/device/display/daydream/EnergySaverFragment.java), [TV standby](https://source.android.com/docs/core/power/tv-standby)
- Whether this vendor turned it on is unknown. Setting it to `-1` explicitly costs nothing and removes the risk.

### 1.6 What a vendor can add, and what this vendor actually did

A vendor can change any of the above three ways: overlay the `config_*` defaults, seed different values into the settings database, or add its own app. This one did the second and third.

- **The settings database defaults are seeded from vendor properties.** This unit's `SettingsProvider.apk` contains the strings `persist.screensaver.compnent` (the vendor's own typo), `persist.sys.screendream.enable` and `persist.sys.screendream.time` alongside `screen_off_timeout`, `screensaver_components`, `screensaver_enabled`, `sleep_timeout` and `stay_on_while_plugged_in`, plus `DatabaseHelper.java`, `loadSetting`/`loadSecureSettings`/`loadSystemSettings` and `android/os/SystemProperties`. Stock AOSP `SettingsProvider` has no such property names, so this is a vendor patch. **High** that the strings are there; **medium** that it seeds the defaults from them, since the code was not decompiled.
  - `DatabaseHelper`'s `loadSettings` path in AOSP runs when the settings store is first created, i.e. first boot after a factory reset — not on every boot. So a value written later with `settings put` should stick. **Medium**; verify on the unit by writing, rebooting and reading back.
- **The live property values match the symptom.** `persist.sys.screendream.time` = `1200000` (20 minutes), `persist.sys.screendream.enable` = `true`, `persist.sys.screenSaver` = `1`, `persist.screensaver.compnent` = `com.htc.screensaver/com.htc.screensaver.ScreenSaverService`. **High.** [getprop.txt](../reference/stock-unit/getprop.txt)
- **The vendor screensaver app is an ordinary Android screensaver.** Its manifest (read out of the backup) declares a `service` with the action `android.service.dreams.DreamService`, the permission `android.permission.BIND_DREAM_SERVICE`, plus `SYSTEM_ALERT_WINDOW` and `android.uid.system`. The component name matches the property exactly. **High** (manifest strings from `/system/app/ScreenSaverQZ/ScreenSaverQZ.apk` in the golden backup).
  - So nothing exotic is going on: removing the app leaves `screensaver_components` pointing at a component that no longer resolves, and `DreamManagerService` then falls back to `screensaver_default_component` — which on this build is most likely absent too, so no screensaver would run and the display would just switch off at the timeout. Point `screensaver_components` at the new app in the same step.
- **Two stock screensavers are already installed** as fallbacks, both ordinary dreams: `com.android.dreams.basic/com.android.dreams.basic.Colors` (the only dream in BasicDreams, and it needs OpenGL) and `com.android.dreams.web` (WebScreensaver, "Dream URL"). SystemUI also carries `com.android.systemui.DessertCaseDream`, disabled in AOSP. **High** (manifests read out of the backup; [packages-all.txt](../reference/stock-unit/packages-all.txt)).

## 2 Android's own screensaver framework for a third-party app

### 2.1 What a DreamService is and how to register one

- A dream is a `Service` subclass with its own window. AOSP's own words: "Extend this class to implement a custom dream" and "Dreams are interactive screensavers launched when a charging device is idle, or docked in a desk dock." **High.** [DreamService.java (android11)](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android11-release/core/java/android/service/dreams/DreamService.java)
- The manifest declaration. The android11 class javadoc's own sample has `android:name`, `android:exported`, `android:icon` and `android:label` and does **not** show the permission line; the permission is demanded by the prose next to the sample and enforced by `DreamManagerService.validateDream()`, so it belongs in the declaration anyway (**high**, same file):

```xml
<service
    android:name=".MyDream"
    android:exported="true"
    android:icon="@drawable/my_icon"
    android:label="@string/my_dream_label"
    android:permission="android.permission.BIND_DREAM_SERVICE">
    <intent-filter>
        <action android:name="android.service.dreams.DreamService" />
        <category android:name="android.intent.category.DEFAULT" />
    </intent-filter>
    <!-- Point to additional information for this dream (optional) -->
    <meta-data
        android:name="android.service.dream"
        android:resource="@xml/my_dream" />
</service>
```

- The permission is **required, not optional**: "When targeting api level 21 and above, you must declare the service in your manifest file with the `BIND_DREAM_SERVICE` permission." And `DreamManagerService.validateDream()` enforces it, rejecting any component whose `serviceInfo.permission` is not `BIND_DREAM_SERVICE` for apps targeting Lollipop or later. The app does **not** request this permission; it declares it *on* the service, so only the system can bind. **High.** [DreamService.java](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android11-release/core/java/android/service/dreams/DreamService.java), [DreamManagerService](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android11-release/services/core/java/com/android/server/dreams/DreamManagerService.java)
- Constants: `SERVICE_INTERFACE = "android.service.dreams.DreamService"`, `DREAM_META_DATA = "android.service.dream"`. The `meta-data` XML is only needed to point at a settings activity; without it the dream still appears, just with no "configure" entry. **High.** [DreamService.java](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android11-release/core/java/android/service/dreams/DreamService.java), [DreamBackend](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android11-release/packages/SettingsLib/src/com/android/settingslib/dream/DreamBackend.java)
- No special app permission is needed to *be* the active screensaver. Setting the active screensaver from code needs `WRITE_DREAM_STATE` (a signature permission), which is why the Settings app does it — but writing `secure screensaver_components` from ADB sidesteps that entirely (section 4). **High.** [DreamManagerService](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android11-release/services/core/java/com/android/server/dreams/DreamManagerService.java)

### 2.2 Showing a user-chosen image

Yes, with no framework help needed. A dream owns a normal window, so `setContentView` with an `ImageView` is all it takes; the "user can replace it" part is a file-path decision, not an Android one.

- **Not** the app's own external files directory. `/sdcard/Android/data/<package>/files/screensaver.jpg` is tempting because the app itself needs no permission for it, but on Android 11 nothing else can get in: "apps can no longer access files in *any* other app's dedicated, app-specific directory within external storage"; all-files access explicitly stops short of `/Android/data/`, `/sdcard/Android` and most of its subdirectories, and "apps that are granted this permission still can't access the app-specific directories that belong to other apps"; and `ACTION_OPEN_DOCUMENT_TREE` / `ACTION_OPEN_DOCUMENT` can no longer select anything under `Android/data/`. So Material Files could not put the image there however it is granted. **High.** [Android 11 storage updates](https://developer.android.com/about/versions/11/privacy/storage), [All files access](https://developer.android.com/training/data-storage/manage-all-files)
- **The arrangement that actually works: a fixed path in shared storage, `/sdcard/Pictures/screensaver.jpg`**, with a default image bundled in the APK as the fallback. Android 11 restored plain `File`-API and `fopen()` access to media files in shared storage by direct path, and `READ_EXTERNAL_STORAGE` on Android 11 is read-only access to all of shared storage — so an `ImageView` can load the file with no MediaStore code. Grant it once from the PC: `adb shell pm grant <pkg> android.permission.READ_EXTERNAL_STORAGE`. **High** for the platform rules; **medium** that a freshly pushed JPEG reads back by path without a media scan — device check. [Android 11 storage updates](https://developer.android.com/about/versions/11/privacy/storage)
- **Zero-permission alternative**, if that read ever misbehaves: let the app copy the picture once through the system file picker (`ACTION_OPEN_DOCUMENT`) into its own files directory. No permission at all and it works with the remote, but it is one more screen to build. **Medium** — standard Android, but a design proposal.
- Keep it a still image, not an animation: on 1 GB of RAM with an idle projector there is nothing to gain, and `com.android.dreams.basic.Colors` needs OpenGL for exactly that reason.

### 2.3 Whether the user can pick it from Settings

Yes — and with the TV Settings app this unit actually has, better than with the phone one.

- **The brief's premise is wrong for this unit**: `com.android.settings` is **not** installed. The installed settings app is `com.android.tv.settings` (`/system/system_ext/priv-app/TvSettings/TvSettings.apk`). **High.** [packages-all.txt](../reference/stock-unit/packages-all.txt)
- That APK really does carry the screensaver screens: its dex contains `DaydreamActivity`, `DaydreamFragment` (with `activeDream`, `dreamTime`, `getActiveDream`, `refreshActiveDreamPref`), `DreamTimePreference` and `EnergySaverFragment` (with `sleepTime`, `getSleepTime`, `getAttentiveSleepTime`), and its resources include `res/xml/daydream.xml` and `res/xml/energy_saver.xml`. **High** (read out of the golden backup).
- `DaydreamFragment` builds its list from `DreamBackend.getDreamInfos()`, which queries `PackageManager.queryIntentServices()` for `android.service.dreams.DreamService` with `GET_META_DATA`. Any correctly declared dream shows up by itself, labelled with its `android:label`. Picking it calls `setActiveDream`, which enables the backend and writes the component. **High.** [DaydreamFragment](https://android.googlesource.com/platform/packages/apps/TvSettings/+/refs/heads/android11-release/Settings/src/com/android/tv/settings/device/display/daydream/DaydreamFragment.java), [DreamBackend](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android11-release/packages/SettingsLib/src/com/android/settingslib/dream/DreamBackend.java)
- **Where the screen is.** In AOSP TvSettings android11 the **Screen saver** and **Energy saver** entries sit side by side on the Device Preferences screen (`res/xml/device.xml`, keys `daydream` and `energysaver`), not under Display & Sound. **High.** [device.xml (android11)](https://android.googlesource.com/platform/packages/apps/TvSettings/+/refs/heads/android11-release/Settings/res/xml/device.xml) — the vendor may have moved them, hence the device check in section 7.
- **So ticket 19's app needs no screensaver UI and no timeout UI.** The user picks the screensaver and the delay (5 / 15 / 30 min / 1 h / 2 h) in Settings → Screen saver. Give the app's dream a sensible `android:label` and that is the whole user interface. **High** for the mechanism; **medium** for "the user can reach that screen", because this unit's Settings has no launcher icon (ticket 13) and is reached through FLauncher's Settings tile.
- Settings also offers "Start now" (`dreamNow` → `DreamBackend.startDreaming()`), useful for checking the image without waiting 30 minutes. **High.** [DaydreamFragment](https://android.googlesource.com/platform/packages/apps/TvSettings/+/refs/heads/android11-release/Settings/src/com/android/tv/settings/device/display/daydream/DaydreamFragment.java)

### 2.4 How it starts and stops

- **Start.** `screen_off_timeout` lapses → `isItBedTimeYetLocked()` true → `shouldNapAtBedTimeLocked()` true (needs `screensaver_activate_on_sleep`) → `napNoUpdateLocked` → wakefulness becomes DREAMING → `DreamManagerService.startDreamLocked()` binds the chosen dream. A partial wake lock tagged `"startDream"` is held just over the launch. **High.** [PowerManagerService](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android11-release/services/core/java/com/android/server/power/PowerManagerService.java), [DreamManagerService](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android11-release/services/core/java/com/android/server/dreams/DreamManagerService.java)
- **Stop.** "Non-interactive dreams (default) will dismiss on the first input event", so any key on the remote brings the picture back. An interactive dream must call `finish()` itself. `wakeUp()` gives the dream about five seconds for an exit animation. **High.** [DreamService.java](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android11-release/core/java/android/service/dreams/DreamService.java)
- **The dream keeps the picture bright by itself.** The field is `private boolean mScreenBright = true;`, and `onWindowCreated()` sets `(mScreenBright ? WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON : 0)` on the dream's window. **High** (the class javadoc for `isScreenBright()` says "Defaults to false" — that javadoc is wrong against the code; trust the field). Calling `setScreenBright(true)` explicitly in `onAttachedToWindow` costs one line and removes the doubt.
- `setFullscreen(true)` sets `FLAG_FULLSCREEN` on the window. Worth setting for a projector. **High.** (same file)
- The dream ends on its own when `sleep_timeout` expires; with `sleep_timeout = -1` it does not end at all until someone presses a key. **High** (section 1.3).

## 3 Does playback keep the screen on

### 3.1 The mechanism, not the activity

Playing video does **not** by itself keep the screen on. What keeps it on is a visible window carrying `FLAG_KEEP_SCREEN_ON`:

- `RootWindowContainer.handleNotObscuredLocked()` records the session of any displayed window with `FLAG_KEEP_SCREEN_ON` into `mHoldScreen` and passes it to `WindowManagerService.setHoldScreenLocked()`. The hold is recomputed on every surface-placement pass, so it drops as soon as no such window is visible. **High.** [RootWindowContainer (android11)](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android11-release/services/core/java/com/android/server/wm/RootWindowContainer.java)
- WindowManagerService holds the real lock: `mHoldingScreenWakeLock = mPowerManager.newWakeLock(PowerManager.SCREEN_BRIGHT_WAKE_LOCK | PowerManager.ON_AFTER_RELEASE, TAG_WM)`, not reference-counted. **High.** [WindowManagerService (android11)](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android11-release/services/core/java/com/android/server/wm/WindowManagerService.java)
- A screen-bright wake lock makes `isBeingKeptAwakeLocked()` true, so `isItBedTimeYetLocked()` is false and the device neither dims, nor naps into the screensaver, nor sleeps. **High.** [PowerManagerService](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android11-release/services/core/java/com/android/server/power/PowerManagerService.java)
- **The single exception is `attentive_timeout`** (section 1.5): once expired it ignores that wake lock and goes straight to sleep. Nothing an app can do about it except not have it set.

### 3.2 ExoPlayer is not the answer

`ExoPlayer.setWakeMode()` does **not** keep the screen on, and its own javadoc says so (**high**, [ExoPlayer.java r2.19.1](https://raw.githubusercontent.com/google/ExoPlayer/r2.19.1/library/core/src/main/java/com/google/android/exoplayer2/ExoPlayer.java)):

- "Sets how the player should keep the device awake for playback when the screen is off."
- "It should be used together with a foreground `Service` for use cases where playback occurs and the screen is off (e.g. background audio playback). It is not useful when the screen will be kept on during playback (e.g. foreground video playback)."
- It holds a `PowerManager.WakeLock` and/or a `WifiManager.WifiLock` while in `STATE_READY`/`STATE_BUFFERING` with `playWhenReady`, and needs the `WAKE_LOCK` permission.

So: an ExoPlayer-based app keeps the CPU alive but will be interrupted unless it also sets `FLAG_KEEP_SCREEN_ON` (or `setKeepScreenOn` on its video view). Most video apps do; a bare one might not. **High** for the javadoc, **medium** for "most do".

### 3.3 AirPlay mirroring on this projector: it does hold the screen

Good news, against the ticket's worry. In the app chosen in ticket 14 (`jqssun/android-airplay-server`):

- `Prefs.kt` declares `val KEEP_SCREEN_ON = bool("keep_screen_on", true)` — **on by default**. **High.** [Prefs.kt](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/app/src/main/kotlin/io/github/jqssun/airplay/Prefs.kt)
- `MainActivity.kt` observes that preference together with the connection count and does `if (on) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) else window.clearFlags(...)`, with `on` = `keep && conns > 0`. It holds no `PowerManager` wake lock of its own and does not call `setKeepScreenOn`. **High.** [MainActivity.kt](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/app/src/main/kotlin/io/github/jqssun/airplay/MainActivity.kt)

Consequences:

- While an iPad is connected, the flag is set and nothing idles. Correct behaviour, no work needed.
- When the last sender disconnects, the flag is cleared and the idle clock restarts from the last user activity — so the screensaver appears some minutes after mirroring ends. That is what the user asked for.
- The flag lives on `MainActivity`'s window. If the AirPlay activity is ever not the visible window while mirroring (it should not be, since it draws the picture), the hold goes away. **Medium**, an inference from how `RootWindowContainer` recomputes the hold.
- **If a future player or receiver turns out not to set the flag**, the fixes in order of laziness are: turn on that app's own keep-awake option; raise `screen_off_timeout` (at the cost of the 30-minute screensaver); or, in the app being written anyway, have ticket 19's app poke `PowerManager.userActivity()` on a timer — which needs the signature permission `DEVICE_POWER` and so is only possible if that app ends up as a system app. Prefer the first two. **Medium.**

## 4 Setting all of this from a PC over ADB, no root

The `settings` shell command is part of SettingsProvider and runs as the shell user, which holds `WRITE_SECURE_SETTINGS` — so all three namespaces are writable with no root. Its own help text (**high**, [SettingsService (android11)](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android11-release/packages/SettingsProvider/src/com/android/providers/settings/SettingsService.java)):

```
get [--user <USER_ID> | current] NAMESPACE KEY
put [--user <USER_ID> | current] NAMESPACE KEY VALUE [TAG] [default]
delete [--user <USER_ID> | current] NAMESPACE KEY
list [--user <USER_ID> | current] NAMESPACE
reset [--user <USER_ID> | current] NAMESPACE {PACKAGE_NAME | RESET_MODE}
NAMESPACE is one of {system, secure, global}, case-insensitive
```

| What | Command | Accepted values |
|---|---|---|
| Screensaver start delay (and screen-off delay if no screensaver runs) | `adb shell settings put system screen_off_timeout <ms>` | any positive integer in ms; values below 10000 are floored to 10 s; no "never" — use a large number such as `2147483647`. TvSettings offers 300000 / 900000 / 1800000 / 3600000 / 7200000 |
| Screensaver on/off | `adb shell settings put secure screensaver_enabled 1` | `1` / `0` |
| Screensaver instead of screen-off when idle | `adb shell settings put secure screensaver_activate_on_sleep 1` | `1` / `0` — needed, AOSP default is false |
| Active screensaver | `adb shell settings put secure screensaver_components <pkg>/<fully.qualified.Service>` | comma-separated flattened component names; first resolvable one wins |
| Fallback screensaver | `adb shell settings put secure screensaver_default_component <pkg>/<Service>` | same form |
| When the display really switches off | `adb shell settings put secure sleep_timeout -1` | ms, or `-1` for never (anything `<= 0` means never) |
| Hard cut-off that beats wake locks | `adb shell settings put secure attentive_timeout -1` | ms, or `-1` for off |
| Keep the screen on while plugged in | `adb shell settings put global stay_on_while_plugged_in 0` | bitmask: 0 off, 1 AC, 2 USB, 4 wireless, 7 all |
| Show the screensaver now | `adb shell am start -n com.android.systemui/.Somnambulator` | — |
| Read any of them back | `adb shell settings get <namespace> <key>` | — |
| See the whole power state | `adb shell dumpsys power` | — |

- Every key and value above is sourced in sections 1 and 2. **High.**
- `com.android.systemui.Somnambulator` exists on this unit (its name is in the installed SystemUI manifest) and in AOSP it is an exported activity with `MAIN` + `DEFAULT`/`DESK_DOCK` that asks DreamManager to start dreaming. **High** for both. [SystemUI manifest (android11)](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android11-release/packages/SystemUI/AndroidManifest.xml); unit: manifest strings read out of the golden backup.
- **Reboot survival.** All `settings put` writes go through SettingsProvider, whose own words are that settings are "asynchronously persisted on mutation" and "stored in the user specific system directory"; some namespaces are even persisted synchronously. So they survive a reboot and are lost only on a factory reset or if SettingsProvider's data is cleared. **High** for AOSP ([SettingsProvider (android11)](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android11-release/packages/SettingsProvider/src/com/android/providers/settings/SettingsProvider.java)); **medium** for this unit, whose SettingsProvider is vendor-patched to seed defaults from `persist.sys.screendream.*` (section 1.6). AOSP seeds those defaults through `DatabaseHelper` on first creation only, so a later `settings put` should win, but **verify by writing, rebooting and reading back**.
- `setprop` is not the route. A plain `setprop` of a `persist.*` property from the shell will usually be refused by the property ACL, and even if it worked it would only change a *default* that is already past. Don't use it; write the settings.
- Nothing above needs the device to be rooted, and nothing above is a partition write — these are ordinary settings writes, so they are undone by writing the previous value back. Record the old values with `settings get` first.

## 5 Anything else on this unit that could take the picture away

### 5.1 `blank_screen`: not a dimmer, and probably inert here

- The program on this unit is **the unmodified AOSP tool**. Its symbols include `android.hardware.light@2.0::ILight::getService`, and its strings end with the AOSP source path `hardware/interfaces/light/utils/main.cpp`. **High** (`strings` on `/system/bin/blank_screen`, 19,904 bytes, extracted from the golden backup).
- That AOSP program is `blank_screen [color]`: with no argument it sets every light the light HAL exposes to 0, i.e. off. It touches lights (notification LEDs, backlight), not the display's power state — it makes no display or power-management calls at all. The android11 source asks for the AIDL `android.hardware.light.ILights` first and falls back to the HIDL `android.hardware.light@2.0::ILight`; this unit's binary carries the HIDL symbol. With no light service either way it prints "Could not retrieve light service." and exits -1. **High.** [light/utils/main.cpp (android11)](https://android.googlesource.com/platform/hardware/interfaces/+/refs/heads/android11-release/light/utils/main.cpp)
- This unit's `/system/etc/init/blank_screen.rc` (113 bytes) holds **the same five lines as the AOSP file** (`service blank_screen /system/bin/blank_screen` / `user system` / `oneshot` / `group system` / `shutdown critical`). **High.** [AOSP blank_screen.rc](https://android.googlesource.com/platform/hardware/interfaces/+/refs/heads/android11-release/light/utils/blank_screen.rc); unit: [startup.txt in the backup analysis](09-sort-components.md)
- **It is never started on a timer.** AOSP `init.rc` does not mention it. The only thing that starts it is `init`'s own `TurnOffBacklight()` in `reboot.cpp`, called from `HandlePowerctlMessage()` on `shutdown,thermal` and from `DoReboot()` when the command is power-off or a thermal shutdown — because the remaining shutdown work, such as fsck, can take a long time. **High.** [reboot.cpp (android11)](https://raw.githubusercontent.com/aosp-mirror/platform_system_core/android11-release/init/reboot.cpp), [init.rc (android11)](https://raw.githubusercontent.com/aosp-mirror/platform_system_core/android11-release/rootdir/init.rc)
- **And on this unit it has nothing to talk to.** There is no light HAL implementation: the vendor partition has no `android.hardware.light@2.0-service.*` binary and no light entry in `/vendor/etc/vintf/manifest/`, and no light service appears in `init.svc.*`. Only the client-side library `/system/lib/android.hardware.light@2.0.so` is present — which is what `blank_screen` links against. So the program would log "Could not retrieve light service." and exit. **High.** [vendor and system file inventories in the golden backup analysis](09-sort-components.md), [getprop.txt](../reference/stock-unit/getprop.txt)
- **Conclusion: `blank_screen` has nothing to do with the idle dimming, and keeping it on the keep-list is harmless.** It is the stock shutdown courtesy. Removing it would also be harmless, but there is no reason to.

### 5.2 Lamp and fan

- **Android's thermal framework cannot dim the picture on this unit.** `/vendor/etc/thermal_info_config.json` declares exactly two sensors, `cpu_thermal_zone` (CPU) and `gpu_thermal_zone` (GPU), and one cooling device, `thermal-cpufreq-0` (CPU). There is no lamp, LED, backlight or brightness cooling device, so Android's thermal mitigation can only throttle the CPU. **High** (file read out of the golden backup; the vendor thermal HAL is `android.hardware.thermal@2.0-service.aw`).
- **The fan is a kernel driver, not an Android service.** `/vendor/lib/modules/pwm_fan.ko` is a PWM fan module, and the vendor exposes `persist.sys.htc_fanctrl` (currently `0`) plus a `gpioservice`. Fan speed therefore changes with temperature regardless of what Android's display state is, and changing Android settings will not change fan behaviour. **High** for the files and the property; **medium** for the inference about who drives it.
- **Whether the projector's LED dims on its own cannot be answered from here.** Android's own screen-dim step (section 1.1) reduces the display brightness through the display HAL in the last few seconds before idle; on a projector that may or may not reach the LED. The live inventory shows `debug.tracing.screen_brightness` = `0.3976`, so Android does carry a brightness value on this unit, which suggests it maps to something real. There is no component here that would dim the lamp on a timer independent of Android. **Low** — this needs eyes on the unit.
- No supporting or contradicting report was found for HY300/H713 projectors specifically; the available web material is generic Android screen-timeout advice. **Low.** [Scalefusion](https://blog.scalefusion.com/pl/how-to-disable-screen-timeout-on-android-devices/), [r/projectors HY300 thread](https://lr.psf.lt/r/projectors/comments/1kbhuqo/projector_stuck_in_start_screen/mpw5b70/?context=3)

## 6 Recommended end state

Matching the ticket 10 decision: vendor screensaver gone, screensaver behaviour kept, image replaceable, timeout changeable, default 30 minutes, nothing interrupts playback.

### 6.1 The shape of it

- **Ticket 19's app carries one `DreamService`** that draws a full-screen still image: a bundled default, overridden by `/sdcard/Pictures/screensaver.jpg` if that file exists, read with `READ_EXTERNAL_STORAGE` granted once over ADB (section 2.2 — the app's own `Android/data` directory is the wrong place, because on Android 11 the file manager cannot reach it). Manifest exactly as in section 2.1. In `onAttachedToWindow`: `setInteractive(false)` (so any remote key dismisses it), `setFullscreen(true)`, `setScreenBright(true)`. Give the service an `android:label` the user will recognise in Settings.
- **No timeout UI and no screensaver picker in that app.** Settings → Screen saver already does both.
- **The display never switches off by itself.** `sleep_timeout` stays at `-1`, so the screensaver image stays up until someone presses a key. The user asked for the dimming to stop; this is the setting that stops it. If they later want the projector to genuinely go dark after a while, that one setting is the knob — call it out to them so they know it exists.

### 6.2 The commands

Record the current values first, so each write has its undo:

```
adb shell settings get system screen_off_timeout
adb shell settings get secure screensaver_enabled
adb shell settings get secure screensaver_activate_on_sleep
adb shell settings get secure screensaver_activate_on_dock
adb shell settings get secure screensaver_components
adb shell settings get secure screensaver_default_component
adb shell settings get secure sleep_timeout
adb shell settings get secure attentive_timeout
adb shell settings get global stay_on_while_plugged_in
```

Then, with the replacement app installed (substitute its real component name):

```
adb shell settings put secure screensaver_components io.example.hy320/io.example.hy320.ImageDream
adb shell settings put secure screensaver_default_component io.example.hy320/io.example.hy320.ImageDream
adb shell settings put secure screensaver_enabled 1
adb shell settings put secure screensaver_activate_on_sleep 1
adb shell settings put system screen_off_timeout 1800000
adb shell settings put secure sleep_timeout -1
adb shell settings put secure attentive_timeout -1
adb shell settings put global stay_on_while_plugged_in 0
adb shell pm grant io.example.hy320 android.permission.READ_EXTERNAL_STORAGE
```

Check and try it:

```
adb shell settings get secure screensaver_components
adb shell dumpsys power | findstr /i "mWakefulness mScreenOffTimeout mSleepTimeout mAttentiveTimeout mStayOn mDreams"
adb shell am start -n com.android.systemui/.Somnambulator
```

Then reboot and read the nine values back, because of the vendor's patched SettingsProvider (section 1.6).

Notes on the choices:

- `screensaver_default_component` is set as well so that a future mistake in `screensaver_components` falls back to the same app rather than to nothing.
- `screensaver_activate_on_dock` is left alone; a projector is never docked, and `shouldNapAtBedTimeLocked()` is already satisfied by the sleep flag.
- `stay_on_while_plugged_in 0` matters: if it is non-zero and this unit reports as plugged in, the screensaver would never start at all (section 1.4).
- `attentive_timeout -1` is the one line that guarantees nothing cuts playback (section 1.5).
- The vendor properties `persist.sys.screendream.*` and `persist.screensaver.compnent` are left as they are. They only seed defaults, and the component one will point at a removed app — which is fine, because the settings now hold explicit values. Mentioning them in the runbook is enough; do not try to `setprop` them.

### 6.3 What to tell the user they will see

- Leave the projector alone for 30 minutes and your picture is replaced by the screensaver image, full screen. Before that, the picture dims for the last few seconds — that is Android warning you, and it is normal.
- The projector does **not** switch off any more. The lamp stays on showing the image until you press a key on the remote, at which point you are back where you were. One keypress, no menu.
- To change the delay: Settings → Device Preferences → Screen saver → "When to start", with 5 minutes, 15 minutes, 30 minutes, 1 hour and 2 hours to choose from. The same screen has "Start now" to see the image immediately. (That is where AOSP puts it; if this vendor moved the entry, the runbook names the real path once section 7 item 5 has been run.)
- To change the image: put your own JPEG in the Pictures folder of internal storage, named `screensaver.jpg`, from the PC with `adb push` or on the projector with the file manager. Remove it and the built-in image comes back.
- While anything is playing — a film, HDMI, AirPlay from the iPad — the screensaver will not appear. The clock only starts once playback stops.
- Because the lamp now runs until you stop it, the projector will stay on all night if you forget it. If you would rather it went dark after a few hours, say so: it is one setting, not new software.

## 7 Only the unit can answer (read-only, over `adb shell`)

1. **The nine current values** in section 6.2. In particular whether `attentive_timeout` or `stay_on_while_plugged_in` is already set by the vendor, and whether `screen_off_timeout` is really 1200000 (as `persist.sys.screendream.time` suggests).
2. **Whether the vendor's SettingsProvider re-seeds those settings on every boot** or only on first boot. Write a value, reboot, read it back. This decides whether the runbook needs anything beyond `settings put`.
3. **Whether this unit counts as powered**, since `canDreamLocked()` refuses to dream on battery unless `config_dreamsEnabledOnBattery` is overlaid: `adb shell dumpsys battery` and `adb shell dumpsys power | grep -i mIsPowered`. The vendor screensaver works today, so the answer is probably yes.
4. **Whether `config_show_standby_timeout` is true in this TvSettings build**, which would expose the "allow screen off during media playback" switch and let a user re-enable the one thing that cuts playback. `adb shell cmd overlay lookup com.android.tv.settings com.android.tv.settings:bool/config_show_standby_timeout`.
5. **What the Screen saver and Energy saver screens actually look like here**, since the vendor may have overlaid the arrays or hidden the screens: `adb shell am start -n com.android.tv.settings/.device.display.daydream.DaydreamActivity`, and the same for the Energy saver entry.
6. **Whether Android's screen-dim step visibly dims the projected picture** or does nothing, which decides whether the last-seconds dim needs mentioning to the user at all.
7. **Whether `blank_screen` is inert as predicted**: `adb shell dumpsys -l | grep -i light`, `adb shell lshal | grep -i light`, and whether `init.svc.blank_screen` ever appears.
8. **Whether each kept player holds the screen**: start playback, then `adb shell dumpsys power | grep -A5 "Wake Locks"` and look for the WindowManager screen-bright lock. Do it for USB media playback, HDMI input, AirPlay and Netflix separately — HDMI input in particular is a vendor app and may not set the flag.
9. **Whether the remote's keys reach a non-interactive dream** and dismiss it, including the keys the infrared remote sends that are not standard.

## 8 Open points

- The exact code in this unit's patched `SettingsProvider` was not decompiled; only its strings were read. Item 2 above settles the only consequence that matters.
- `com.android.dreams.web` (WebScreensaver) is on the keep-list by default as a stock Android app, but it is a screensaver that loads a URL. On a low-trust device that is worth a second look in ticket 11 — it is one of the 71 stock packages, not something ticket 09 examined individually.
- `com.android.dreams.basic` can stay as a fallback screensaver, but `Colors` needs OpenGL and animates continuously, which is the wrong thing to leave running on 1 GB of RAM. It should never become the active component.
- If the HDMI input app turns out not to hold the screen awake (item 8), the fix is not in ticket 19's app and will need its own decision: a longer `screen_off_timeout` trades away the 30-minute screensaver.
- Whether the projector hardware dims or protects the LED on its own, independently of Android, is unresolved and cannot be resolved from the backup.

## Verification

Checked 2026-10-22 by a second pass that did not trust the first. Every cited URL above was opened. Where possible the claim was re-read from a *different* host or ref than the one cited: the canonical `android.googlesource.com` instead of the `aosp-mirror` GitHub copy, the `android-11.0.0_r48` release tag instead of the `android11-release` branch, the `androidx/media` repo instead of `google/ExoPlayer`, and the published developer docs instead of source. Nothing was run and the projector was not touched.

### The four knobs (section 1)

| Claim | Verdict | Note |
|---|---|---|
| `screen_off_timeout` default 15 s; literal key; read in `updateSettingsLocked` | **confirmed** | `private static final int DEFAULT_SCREEN_OFF_TIMEOUT = 15 * 1000;` and `Settings.System.SCREEN_OFF_TIMEOUT, DEFAULT_SCREEN_OFF_TIMEOUT` re-read at the r48 tag. [PMS r48](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-11.0.0_r48/services/core/java/com/android/server/power/PowerManagerService.java) |
| When it lapses the device naps into the screensaver instead of sleeping, if `screensaver_activate_on_sleep` (or dock + docked) | **confirmed** | `updateWakefulnessLocked`: `if (isAttentiveTimeoutExpired(time))` goes to sleep; `else if (shouldNapAtBedTimeLocked())` calls `napNoUpdateLocked`; else sleep. `shouldNapAtBedTimeLocked` returns `mDreamsActivateOnSleepSetting` or the dock condition. Same file |
| This is *the screensaver's* start delay, and it is what TvSettings' "when to start" writes | **confirmed, and corroborated independently** | `DaydreamFragment` imports `android.provider.Settings.System.SCREEN_OFF_TIMEOUT` and both reads and writes it, with `DEFAULT_DREAM_TIME_MS = (int) (30 * DateUtils.MINUTE_IN_MILLIS)`. [DaydreamFragment](https://android.googlesource.com/platform/packages/apps/TvSettings/+/refs/heads/android11-release/Settings/src/com/android/tv/settings/device/display/daydream/DaydreamFragment.java) |
| The 30-minute default needs no code | **confirmed** | Same constant, 30 minutes, same file |
| No "never" for `screen_off_timeout`; floor 10 s | **confirmed** | `return Math.max(timeout, mMinimumScreenOffTimeoutConfig);` plus `<integer name="config_minimumScreenOffTimeout">10000</integer>`. [config.xml r48](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-11.0.0_r48/core/res/res/values/config.xml) |
| `2147483647` as the practical never | **partly** (unchanged: medium) | No first-party source. Two device-management vendors describe it as the maximum accepted value, about 25 days, and say it is not the real "Never". [Esper](https://esper.io/blog/how-to-change-or-disable-screen-timeout-on-android), [Scalefusion](https://blog.scalefusion.com/de/how-to-disable-screen-timeout-on-android-devices/) |
| Dim is the last 7 s at most, 20% of the timeout | **confirmed** | `getScreenDimDurationLocked` returns `Math.min(mMaximumScreenDimDurationConfig, ...)`; `config_maximumScreenDimDuration` 7000, `config_maximumScreenDimRatio` 20%. config.xml r48 |
| The five `screensaver_*` secure keys, and **no `screensaver_timeout` in Android 11** | **confirmed** | Independent of the first pass: the platform's own settings proto has a `Screensaver` message with exactly `enabled`, `components`, `activate_on_dock`, `activate_on_sleep`, `default_component`, and no timeout field anywhere in the file. `DreamBackend` likewise has no timeout key. [secure.proto](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android11-release/core/proto/android/providers/settings/secure.proto), [DreamBackend](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android11-release/packages/SettingsLib/src/com/android/settingslib/dream/DreamBackend.java) |
| Literal key strings `screensaver_components` and the `<pkg>/<service>` value form | **confirmed** | Proto field names plus third-party practice: Aerial Views' own README and Fire TV guides both use `settings put secure screensaver_components <pkg>/<service>`. [Aerial Views](https://github.com/guillaumejparis/AerialViews), [aftvnews](https://www.aftvnews.com/?p=15295) |
| Config defaults: dreams enabled true, on-sleep **false**, on-dock true, on-battery false, default component Deskclock | **confirmed** | All five re-read verbatim in config.xml r48. So `screensaver_activate_on_sleep 1` really is needed |
| `sleep_timeout`: secure, default -1, anything 0 or less means never, caps `screen_off_timeout`, and -1 means the dream never ends | **confirmed** | `DEFAULT_SLEEP_TIMEOUT = -1`; `getSleepTimeoutLocked` returns -1 when disabled; `getScreenOffTimeoutLocked` applies it as a `Math.min` cap; `updateUserActivitySummaryLocked` sets `USER_ACTIVITY_SCREEN_DREAM` with `nextTimeout = -1` when it is negative. PMS r48 |
| TvSettings' "Energy saver, turn off screen after" writes `secure sleep_timeout`, offers -1, shows 24 h when unset | **confirmed** | `import static android.provider.Settings.Secure.SLEEP_TIMEOUT;` and `DEFAULT_SLEEP_TIME_MS = (int) (24 * DateUtils.HOUR_IN_MILLIS)`. [EnergySaverFragment](https://android.googlesource.com/platform/packages/apps/TvSettings/+/refs/heads/android11-release/Settings/src/com/android/tv/settings/device/display/daydream/EnergySaverFragment.java) |
| The swapped array names | **confirmed, exactly as stated** | `daydream.xml`'s `dreamTime` preference uses `android:entries="@array/sleep_timeout_entries"` and `android:entryValues="@array/sleep_timeout_values"` = 300000, 900000, 1800000, 3600000, 7200000; `EnergySaverFragment` validates against `R.array.screen_off_timeout_values` = 900000, 1800000, 3600000, 14400000, 28800000, 43200000, 86400000, **-1**. [daydream.xml](https://android.googlesource.com/platform/packages/apps/TvSettings/+/refs/heads/android11-release/Settings/res/xml/daydream.xml), [arrays.xml](https://android.googlesource.com/platform/packages/apps/TvSettings/+/refs/heads/android11-release/Settings/res/values/arrays.xml) |
| `stay_on_while_plugged_in` sets `mStayOn`, and then nothing idles | **confirmed, with one addition** | `updateStayOnLocked` re-read in full; `isBeingKeptAwakeLocked` starts `return mStayOn` then `mProximityPositive` then the `WAKE_LOCK_STAY_AWAKE` bit. **Addition now in section 1.4:** when the key is unset, PMS defaults to `BatteryManager.BATTERY_PLUGGED_AC`, not 0 |
| 1 AC / 2 USB / 4 wireless | **unverified** (unchanged: medium) | The `BatteryManager` constants were still not re-read. Nothing here depends on it: the recommended value is `0` |
| source.android.com says to turn it off when testing idle behaviour | **confirmed** | "Make sure the `stay_on_while_plugged_in` developer setting is off ... might prevent the feature from turning off the screen", with `adb shell settings put global stay_on_while_plugged_in 0`. [TV standby](https://source.android.com/docs/core/power/tv-standby) |
| `attentive_timeout`: new in Android 11, config default -1, settings key overrides it, beats wake locks, goes straight to sleep with no screensaver | **confirmed, and sharpened** | `<integer name="config_attentiveTimeout">-1</integer>`; the read is `Settings.Secure.ATTENTIVE_TIMEOUT, mAttentiveTimeoutConfig`; `isAttentiveTimeoutExpired` and the `isItBedTimeYetLocked` / `isBeingKeptFromInattentiveSleepLocked` switch are as described. source.android.com adds that the feature overrides `FLAG_KEEP_SCREEN_ON` and the FULL / SCREEN_BRIGHT / SCREEN_DIM levels but **not** `PARTIAL_WAKE_LOCK`, and that a warning dialog shows a few seconds before. Both added to section 1.5 |
| `config_show_standby_timeout` guards it in TvSettings, AOSP default false | **confirmed twice** | `return getResources().getBoolean(R.bool.config_show_standby_timeout);` guards both the `allowTurnScreenOff` preference and the `attentive_timeout` writes; source.android.com states the default is false. EnergySaverFragment, TV standby |

### The screensaver framework for an own app (section 2)

| Claim | Verdict | Note |
|---|---|---|
| A dream is a `Service` with its own window; the `SERVICE_INTERFACE` and `DREAM_META_DATA` values | **confirmed** | Re-read on googlesource rather than the GitHub mirror. [DreamService.java](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android11-release/core/java/android/service/dreams/DreamService.java) |
| The manifest snippet is "the class javadoc's own sample" | **partly, fixed in place** | The android11 sample carries `android:name`, `android:exported`, `android:icon` and `android:label` and **no** `android:permission` line. The permission is required by the prose beside it and by `validateDream()`. Section 2.1 now says so, and the snippet matches AOSP plus the permission |
| `BIND_DREAM_SERVICE` required for targetSdk 21 and up, declared *on* the service, enforced by the framework | **confirmed** | "When targeting api level 21 and above, you must declare the service in your manifest file" "with the BIND_DREAM_SERVICE permission"; `validateDream` checks `serviceInfo.permission` only when `serviceInfo.applicationInfo.targetSdkVersion >= Build.VERSION_CODES.LOLLIPOP`. [DreamManagerService](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android11-release/services/core/java/com/android/server/dreams/DreamManagerService.java) |
| Active components are read from the setting, comma-split, unresolvable ones dropped, falling back to `screensaver_default_component` | **confirmed** | `getDreamComponentsForUser` does exactly that, and it is called fresh on every `startDreamInternal` through `chooseDreamForUser`, so an ADB-written component takes effect without a reboot. Same file |
| Setting the active dream from code needs `WRITE_DREAM_STATE`, but ADB writes the setting directly | **confirmed** | `setDreamComponents` and `setDreamComponentsForUser` enforce `WRITE_DREAM_STATE` and then write `Settings.Secure.SCREENSAVER_COMPONENTS`; `DreamBackend.setActiveDream` goes through the manager, not the setting. Same files |
| Any correctly declared dream appears in the picker by itself | **confirmed** | `getDreamInfos` builds `new Intent(DreamService.SERVICE_INTERFACE)` and calls `pm.queryIntentServices(dreamIntent, PackageManager.GET_META_DATA)`; `DaydreamFragment` builds its list from it and offers `dreamNow`, which calls `mBackend.startDreaming()`, which calls `mDreamManager.dream()`. DreamBackend, DaydreamFragment |
| The image can live in the app's own external files directory, where the file manager can replace it | **refuted, fixed in place** | On Android 11 "apps can no longer access files in *any* other app's dedicated, app-specific directory within external storage"; all-files access excludes `/Android/data/` and most of `/sdcard/Android`, and "apps that are granted this permission still can't access the app-specific directories that belong to other apps"; and SAF cannot pick anything under `Android/data/`. Section 2.2 now recommends `/sdcard/Pictures/screensaver.jpg` with `READ_EXTERNAL_STORAGE` (Android 11 restored `File`-API access to media by direct path, and that permission is read-all), with the SAF-copy route as the zero-permission alternative. Sections 6.1, 6.2 and 6.3 follow. [Android 11 storage](https://developer.android.com/about/versions/11/privacy/storage), [All files access](https://developer.android.com/training/data-storage/manage-all-files), [app-specific storage](https://developer.android.com/training/data-storage/app-specific) |
| `mScreenBright = true` in the code while the javadoc says "Defaults to false" | **confirmed** | Both re-read: `private boolean mScreenBright = true;` and "Defaults to false, allowing the screen to dim if necessary." The advice to call `setScreenBright(true)` anyway stands. DreamService.java |
| `onWindowCreated` applies `FLAG_KEEP_SCREEN_ON` from that field; `setFullscreen` sets `FLAG_FULLSCREEN`; non-interactive dreams dismiss on the first input event | **confirmed** | The line is `\| (mScreenBright ? WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON : 0)`, and `setInteractive`'s javadoc says "Non-interactive dreams (default) will dismiss on the first input event." Same file |
| Settings' Screen saver screen is where the user picks both | **confirmed for AOSP; the menu path was wrong, fixed in place** | `device.xml` puts `daydream` (DaydreamFragment) and `energysaver` (EnergySaverFragment) side by side on the Device Preferences screen, not under Display & Sound. Sections 2.3 and 6.3 corrected. [device.xml](https://android.googlesource.com/platform/packages/apps/TvSettings/+/refs/heads/android11-release/Settings/res/xml/device.xml). Worth knowing: on Google TV builds this picker was removed by an update, one more reason to confirm the screen on the unit. [Aerial Views](https://github.com/guillaumejparis/AerialViews) |

### Playback (section 3)

| Claim | Verdict | Note |
|---|---|---|
| `FLAG_KEEP_SCREEN_ON` makes WindowManager hold a screen-bright wake lock | **confirmed** | `mHoldingScreenWakeLock = mPowerManager.newWakeLock(PowerManager.SCREEN_BRIGHT_WAKE_LOCK \| PowerManager.ON_AFTER_RELEASE, TAG_WM);` re-read at r48. [WMS r48](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-11.0.0_r48/services/core/java/com/android/server/wm/WindowManagerService.java) |
| and that blocks the screensaver as well as screen-off | **confirmed, chain closed** | `getWakeLockSummaryFlags` maps `SCREEN_BRIGHT_WAKE_LOCK` to `WAKE_LOCK_SCREEN_BRIGHT`, and `adjustWakeLockSummaryLocked` adds `WAKE_LOCK_CPU \| WAKE_LOCK_STAY_AWAKE` when a bright or dim lock is held and the device is AWAKE; `isBeingKeptAwakeLocked` tests `WAKE_LOCK_STAY_AWAKE`, so `isItBedTimeYetLocked` is false and there is no nap and no sleep. PMS r48. **One nuance the first pass missed:** that bit is added only while wakefulness is AWAKE, so a window that takes the flag *after* the screensaver is already up does not by itself end the dream (see the new open point) |
| `ExoPlayer.setWakeMode` is a CPU and wifi lock, not a screen lock | **confirmed from a different repo** | "It is not useful when the screen will be kept on during playback (e.g. foreground video playback)"; it requires `WAKE_LOCK` and holds a `PowerManager.WakeLock` and/or a `WifiManager.WifiLock`. [androidx/media 1.3.1 ExoPlayer.java](https://raw.githubusercontent.com/androidx/media/1.3.1/libraries/exoplayer/src/main/java/androidx/media3/exoplayer/ExoPlayer.java) |
| The AirPlay app has `keep_screen_on`, default on, and sets the window flag while senders are connected, with no `PowerManager` lock | **confirmed verbatim** | `val KEEP_SCREEN_ON = bool("keep_screen_on", true)`; the condition is `keep && conns > 0`, applied with `window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)` and cleared otherwise; the file references neither `PowerManager` nor `WakeLock`. [Prefs.kt](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/app/src/main/kotlin/io/github/jqssun/airplay/Prefs.kt), [MainActivity.kt](https://raw.githubusercontent.com/jqssun/android-airplay-server/main/app/src/main/kotlin/io/github/jqssun/airplay/MainActivity.kt). Both URLs are on `main`, a moving branch: pin the version actually installed (ticket 14 pins 0.0.36) |

### ADB (section 4)

| Claim | Verdict | Note |
|---|---|---|
| The `settings` help text, the namespaces, and the `[TAG] [default]` arguments | **confirmed verbatim** | Including "NAMESPACE is one of {system, secure, global}, case-insensitive". [SettingsService](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android11-release/packages/SettingsProvider/src/com/android/providers/settings/SettingsService.java) |
| The shell user can write all three namespaces with no root | **confirmed** | `com.android.shell` declares `WRITE_SETTINGS` and `WRITE_SECURE_SETTINGS`, sharedUserId `android.uid.shell`. [Shell manifest](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android11-release/packages/Shell/AndroidManifest.xml) |
| The writes survive a reboot | **confirmed for AOSP, confidence raised in place** | SettingsProvider's own javadoc: settings are "asynchronously persisted on mutation" and "stored in the user specific system directory", with some namespaces persisted synchronously. The vendor-patch caveat and the write-reboot-read check stay |
| `am start -n com.android.systemui/.Somnambulator` shows the screensaver now | **confirmed** | The activity is `android:exported="true"` with `android:label="@string/start_dreams"` and one intent-filter: `MAIN` plus categories `DEFAULT` and `DESK_DOCK`. [SystemUI manifest](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android11-release/packages/SystemUI/AndroidManifest.xml) |

### This unit, and the rest (sections 1.6 and 5)

| Claim | Verdict | Note |
|---|---|---|
| `com.android.settings` absent, `com.android.tv.settings` present, both stock dreams installed | **confirmed** | Re-read from the live inventory: zero matches for the stock Settings package; `TvSettings.apk`, `BasicDreams.apk` (`com.android.dreams.basic`), `WebScreensaver.apk` (`com.android.dreams.web`), `ScreenSaverQZ.apk` (`com.htc.screensaver`). [packages-all.txt](../reference/stock-unit/packages-all.txt) |
| The four vendor property values | **confirmed** | `persist.sys.screendream.time` 1200000, `persist.sys.screendream.enable` true, `persist.sys.screenSaver` 1, `persist.screensaver.compnent` = `com.htc.screensaver/com.htc.screensaver.ScreenSaverService`. [getprop.txt](../reference/stock-unit/getprop.txt) |
| `blank_screen` is the AOSP light tool, touches only lights, and is started only at power-off and thermal shutdown | **confirmed, with one refinement now in section 5.1** | `TurnOffBacklight()` finds the service by the name `"blank_screen"` and starts it, with the comment "Turn off backlight while we are performing power down cleanup activities", and it is called only from the `shutdown,thermal` branch of `HandlePowerctlMessage` and from `DoReboot` when the command is power-off or a thermal shutdown. The android11 tool asks for AIDL `ILights` first and falls back to HIDL `ILight@2.0`; either way it makes no display or power calls and fails with "Could not retrieve light service." [reboot.cpp](https://android.googlesource.com/platform/system/core/+/refs/heads/android11-release/init/reboot.cpp), [main.cpp](https://android.googlesource.com/platform/hardware/interfaces/+/refs/heads/android11-release/light/utils/main.cpp) |
| Everything read out of the golden backup: the vendor screensaver manifest, the patched `SettingsProvider` strings, the `blank_screen` binary and its `.rc`, the thermal config, the TvSettings dex and resources, the SystemUI manifest strings | **not independently checkable** | These rest on the first pass's `debugfs` and `strings` reads of the PC-side backup. No web source can confirm or refute them, and every AOSP file they were compared against checks out. Treat them as high for "the strings are present", medium for what the code does with them |
| Lamp and fan cannot be dimmed from the Android side on this unit | **unverified** (unchanged: low to medium) | Rests on the same backup files. No independent source for HY320 or H713 projector lamp behaviour turned up in this pass either |

### Open points this pass adds

1. **A player that takes `FLAG_KEEP_SCREEN_ON` while the screensaver is already showing does not, by that flag alone, end it** - `adjustWakeLockSummaryLocked` adds the stay-awake bit only while wakefulness is AWAKE. In practice launching an activity wakes the device, and the AirPlay app's `launch_on_connect` defaults to true, but that is an inference. Device check: with the screensaver up, connect the iPad and see whether the picture comes back by itself. **Medium.**
2. **Whether a JPEG pushed to `/sdcard/Pictures/` reads back by plain file path** for an app holding only `READ_EXTERNAL_STORAGE`, with no media scan in between. Device check: `adb push`, then open it from the app. If it fails, use the SAF-copy route in section 2.2.
3. **Whether `adb push` into `/sdcard/Android/data/...` still works on this build** - it is the half of the old recommendation that may survive, and it would let the runbook seed a default image before first run. Not needed if the Pictures path works.
4. **The two AirPlay URLs point at `main`,** a moving branch; re-read them against the pinned 0.0.36 tag when ticket 19 or the runbook is written, in case `keep_screen_on` arrived after that release.
