# 19 Keystone, shortcuts and screensaver app

Type: prototype
Status: resolved
Blocked by: 18, 22

## Question

What does the small own app look like and how is it used with the remote? It must cover:
- manual keystone: the four corners, adjusted with the arrow keys, with a reset. The corners are plain system properties (ticket 18), so no special interface is needed;
- projection orientation (ceiling, rear) if that proves reachable, which ticket 18 left open;
- shortcuts for the HDMI input, Settings and the file manager, for the launcher to show;
- an Android screensaver showing an image from the shared Pictures folder, with a default image we supply and which the user can replace with the file manager or a USB stick (ticket 22).

It is the replacement that the vendor settings app's removal waits on.

## Groundwork found while cleaning (2026-10-22)

The vendor's own configuration file for this model answers several of this ticket's unknowns: the tilt sensor's exact path, that projection mode is one of four numbered values, the activity names of the Wi-Fi and Bluetooth screens, and that the HDMI input on this model is HDMI2. See [research/19a-vendor-config.md](../research/19a-vendor-config.md).

Also settled by it: this model has no fan and no battery, which matters because Android refuses to start a screensaver on battery (ticket 22), and its firmware shuts the projector down on overheating, which explains any switch-off that is not the screensaver.

## Built, not yet tested (2026-10-22)

Source in `app/`, built with `app/build.ps1` into `<backup>\apps\projector-tools-1.0.apk` (16 KB, `com.hy320.tools`, targets Android 11, works from Android 5 up). Built without a build system: the Android tools in the SDK already on this PC, plus the JDK, so there is nothing else to install. The signing key is kept beside the source, so later versions can replace it in place.

What it contains:
- **Keystone correction**, driven by the remote alone: up and down choose a corner, left and right move it, the centre key switches between sideways and up-and-down, the menu key resets everything. It writes the firmware's own eight corner properties and then sends the same broadcast the vendor's settings app sends, so the display code applies it. Movement is capped at 200 either way so the picture cannot be thrown off the panel.
- **Projection**, the four orientations, written to the firmware's own `persist.sys.projection.position` with its own broadcast. The four values are shown next to the names, because which value means which orientation is not documented and gets confirmed by looking at the wall.
- **A screensaver** that shows `Pictures/screensaver.jpg` from the shared storage if the user puts one there, replaceable with the file manager or a USB stick. The default, if no picture is there, is a nearly black screen with a dim clock, which suits a projector: almost no light used and nothing bright standing on the panel.
- **An HDMI tile** on the home screen that switches straight to the input, trying each of the names these boards use.
- **A short settings list** with keystone, projection, Android's screensaver screen and the vendor's picture screen while that app is still installed.

Both the keystone and projection screens say plainly on screen if the projector refuses the change, rather than looking as if they worked: every write is read back before being reported as done.

**Nothing of this is tested.** It needs the projector: whether an ordinary app may set those properties at all (the framework normally restricts them, and this firmware's protection layer is only logging, which is why it is likely to work), whether the broadcast makes the change appear, which value is which orientation, and whether the screensaver can read a picture from the shared folder with the one permission it asks for. Those checks go in the runbook.

## Resolved as far as the map goes (2026-10-22)

The app exists and is built. Testing it is step 4 of the approved runbook, because it needs the projector. Nothing is left to decide here.

## An eighth tile, and three keys on the remote (2026-11-02)

Two things the app gained once it had been in use for a while, both because something was already there to be used and was not.

**Android's settings, as the eighth tile.** The menu had seven tiles in a grid of eight, and Android's own settings could be reached only by leaving the app for the home screen. They answer to `android.settings.SETTINGS`, which the manifest already asks about by name because the home screen needs it: on this firmware `com.android.tv.settings` carries no launcher entry of either kind, so nothing else ever finds it. The gear is drawn by `art/make-settings-icon.py` to the same measure as the rest -- 240x210, the menu's two blues, a glyph 108 pixels across the diagonal -- so it sits among the vendor's own icons without standing out.

**Three keys that did nothing.** All three come from the IR receiver `sunxi-ir-uinput` as scancodes, which `/vendor/usr/keylayout/sunxi-ir-uinput.kl` turns into keycodes:

| key on the remote | scancode | keycode | what the firmware does with it |
|---|---|---|---|
| under the source symbol | 245 | 288, `KEYCODE_PRJ_FOCUS_UP` | starts `com.softwinner.miracastReceiver/.Miracast` |
| under the cast symbol | 246 | 289, `KEYCODE_PRJ_FOCUS_DN` | started `com.waxrain.airplaydmr2/com.waxrain.ui.WaxPlayerSetting` |
| menu | 82 | 82, `KEYCODE_MENU` | nothing; it reaches whichever app is in front |

The top two are not unhandled. The vendor's `TvWindowManager` intercepts them in `interceptKeyBeforeQueueing` and starts an activity itself, before any app sees them. Both threw `ActivityNotFoundException`: the first because the Miracast module ships disabled, the second because the cleaning removed the vendor's AirPlay app for good.

So 288 is left exactly as it is. It already does, from wherever you happen to be, the thing the cast button is wanted for, and the module's `disable` file stays the switch that controls it; no ordinary app could match that, because only the focused app sees a key. 289 and the menu key are taken by the home screen, for the HDMI input and for this app. The two printed symbols therefore read backwards -- the alternative was a Magisk module overlaying the key layout in `/vendor` to swap the two scancodes, which is a lot of partition for a legend.

Two details shaped the code. Both top keys arrive on the way **up** only: the firmware's handler takes the press for itself and lets go of the release. And 289 has no constant in Android, being the vendor's own invention, so the launcher asks for it by name with `KeyEvent.keyCodeFromString("KEYCODE_PRJ_FOCUS_DN")` rather than writing the number; a firmware that has never heard of it answers `KEYCODE_UNKNOWN` and the key is simply left alone.

Checked on the projector: the menu key opens `com.hy320.tools/.MainActivity`, the cast key opens `com.softwinner.awlivetv/.MainActivity` which is what the HDMI tile starts, and the Settings tile opens `com.android.tv.settings/.MainSettings`. Miracast is **not** checked -- its module is disabled, and the evidence is only that the activity the firmware names is the one that APK declares.
