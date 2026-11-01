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

Source in `HY320/app/`, built with `app/build.ps1` into `<backup>pps\projector-tools-1.0.apk` (16 KB, `com.hy320.tools`, targets Android 11, works from Android 5 up). Built without a build system: the Android tools in the SDK already on this PC, plus the JDK, so there is nothing else to install. The signing key is kept beside the source, so later versions can replace it in place.

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
