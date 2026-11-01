# The vendor's own configuration file — what it gives ticket 19

Found while cleaning, in `/product/etc/config.ini`, read out of the golden backup on 2026-10-22. A copy is saved at `<backup>\analysis\inventory\product-config.ini`. It is the vendor settings app's own feature list for this exact model, so it is a statement of what this hardware has, written by the people who built it.

## Directly useful for the own app

- **The tilt sensor's path is named outright:**
  `/sys/devices/platform/soc@2900000/2502400.twi/i2c-1/1-0018/input/input3/stk83xx/value`
  So the sensor is an stk83xx on the second I²C bus at address 0x18, and its reading is a plain file. That is what automatic keystone would read. Whether an ordinary app may read that path has to be checked on the device; while the blocking layer is only logging, it probably can.
- **Keystone features this model declares:** automatic keystone on, manual keystone on, initial-angle correction on, screen zoom on. Four-corner correction ("correctionSettings") is **off** on this model, and so are automatic rotation, automatic focus and the focus settings screen.
- **Projection mode is a setting with four values:** `"projectMode": true, "projectValue": "0,1,3,2"`. So the orientation question ticket 18 left open has an answer shape: four modes selected by a small number, not something exotic. Which number means which orientation still has to be found by trying.
- **Direct entry points into the vendor settings screens**, usable as launcher tiles while that app is still installed:
  - Wi-Fi: `com.htc.htcsettings/com.htc.activity.WIFIActivity`
  - Bluetooth: `com.htc.htcsettings/com.htc.activity.BluetoothSettingActivity`
- **The HDMI input is HDMI2** on this model (`sourceHdmi`, `sameScreenHdmi`, `sourceList` all say HDMI2), which the HDMI tile must match.

## Hardware facts worth keeping

- No fan (`isFan: false`), no battery (`isBattery: false`), a speaker (`isHorn: true`). The projector is always mains-powered, which matters for the screensaver: Android refuses to start one on battery (ticket 22).
- **Temperature protection is on:** it shuts down above a threshold, after a number of consecutive high readings, and also on implausible readings. Nothing to change, but it explains any sudden switch-off that is not the screensaver.
- Audio, video and picture-mode screens are switched **off** on this model, so the vendor settings app shows far less than its code contains.

## The other leftover file

`/product/etc/hideApp.ini` carries a list of region-specific television apps (Brazilian, Philippine, Latin American) with icons, all commented out, plus a filter listing the vendor's own apps. Nothing of it is active, and the launcher that read it is being removed, but it is one more sign of what this firmware was built to push.

## Left in place deliberately

Both files, and `/system/etc/lmkd_whitelist`, still name apps that the cleaning removes. Naming an app that is not installed does nothing at all, and editing more vendor files would add risk for no benefit. Noted so it does not look like an oversight later.

## The keystone and focus logic is in the Android framework, not in the vendor app (2026-10-22)

Found by searching the system framework (`/system/framework/services.jar`) in the cleaned image. The vendor patched Android's own window manager, and that is where this hardware's behaviour lives:

- **Keystone:** receivers named `mKeystoneReceiver` and `mProjectiveModeKeystoneReceiver`, a lock around them, the intents `android.intent.hotack_keystone` and `com.htc.auto_keystone`, the log line "auto keystone successfully", and the eight `persist.display.keystone_*` corner properties ticket 18 identified.
- **Automatic keystone:** driven from here, with the properties `hotack.sensor.anti_shake`, `hotack.sensor.xvalue` and `hotack.vaf.runEnable`.
- **Focus motor:** `MOTOR_CTRL_PATH` pointing at `/sys/devices/platform/motor_ctr/motor_ctrl`, with `interceptMotorCtrlUp`/`Dn` and repeat handling, so the framework itself intercepts the remote's focus keys and drives the motor.

**What this changes:**
1. **Removing the vendor settings app costs no function.** It is only the user interface; keystone, projection mode and the focus motor are in the framework and keep working. That makes ticket 10's "remove it once the replacement exists" much safer than it looked.
2. **Focus keeps working from the remote** with no app involved, so the helper kept for the motor (`com.htc.closedialog`) may not be needed at all. Worth testing once cleaned, before deciding to keep it.
3. **Our own app has two ways in:** set the eight corner properties, or broadcast the vendor's own keystone intents. Both are already in the framework, so nothing has to be reimplemented.
4. The framework also expects an auto-focus app (`com.hysd.vafocus`) that is **not installed** on this unit, which matches the vendor's own configuration saying automatic focus is off for this model.

**An honest boundary of "clean":** the framework is vendor-modified and stays so. Replacing it would mean rebuilding Android, which is out of scope. What it contains was checked: no suspicious network destinations (only Android's standard ones), and the only app-pushing hook is one that would return to a Chinese television launcher (`com.dangbei.mimir.lightos.launcher`) which is not installed and therefore does nothing. The hooks that start the removed casting apps remain too, and will simply fail with a log line.
