# 18 Can an own app set keystone and orientation — findings

Examined in the golden backup on 2026-10-20, same method as ticket 09. The projector was not connected, so everything here still has to be confirmed once on the device.

## How keystone works on this unit

The correction itself is done by the graphics system, not by any app. The display server (SurfaceFlinger) loads `/system/lib/libkeystone.so`, which warps the picture on the GPU. Its internal names are plain: it builds a keystone shader, keeps a keystone matrix, and saves the corner values.

**The corners are plain system properties**, eight of them, with defaults of 0 set in the firmware:

```
persist.display.keystone_ltx   persist.display.keystone_lty    (one corner, x and y)
persist.display.keystone_rtx   persist.display.keystone_rty
persist.display.keystone_lbx   persist.display.keystone_lby
persist.display.keystone_rbx   persist.display.keystone_rby
```

The display server also reads `persist.sys.keystone_vaf` and `persist.sys.keystone_vafaa`, and `libkeystone.so` reads three more named `persist.display.keystone.alias.enable`, `.edge` and `.scale`, which look like edge smoothing. The word "persist" means Android stores them itself and restores them at every boot, so settings survive a restart without any app being involved.

This is better than expected: **an app does not need a special interface. It needs to set eight properties.**

## Who provides the screens today

Not the launcher. The keystone screen and its broadcast live in the **vendor settings app** (`com.htc.htcsettings`, file `HotackSettingsT08_QZ.apk`), which contains a keystone-correction screen, keystone settings, and references to the focus motor and to trapezoid correction.

The Allwinner factory test app (`com.softwinner.dragonbox`) also contains keystone code, a keystone receiver, a keystone angle, the motor control and an "anti-shake" setting, so it can do the automatic correction too. The focus motor is also referenced by `com.htc.closedialog` and the vendor test app.

So removing the stock **launcher** does not cost the keystone screens. Removing the vendor **settings app** does.

## Automatic keystone

There is a tilt sensor: the startup script sets a vendor "anti-shake" property at boot, and `/oem/gsensor_data` holds its calibration. The automatic correction is therefore possible on this hardware, but no separate component for it exists here. The component that sibling models use for this is not installed on your unit at all. So automatic keystone is tied to the vendor settings app or the factory test app, and ticket 19's own app would have to read the sensor itself to reproduce it. Manual correction is the realistic target; automatic is a stretch goal.

## Hardware that the same area controls

The device tree also exposes a focus motor (`motor_ctrl`, with a limiter) and the fan (`speedlevel`). `/system/camprjspe.ini` holds the projection geometry constants (focal length, half-width and half-height, axis offset, backlight, steps) with a checksum. An own app should not touch that file.

## Can an own app set those properties?

Right now, almost certainly yes. Two reasons:

1. The eight corner properties have no specific security rule, so they fall under the catch-all rule in the policy.
2. **The device boots with SELinux permissive**, so that layer only logs and never blocks. While that stays true, the property checks it would normally enforce do not apply.

That makes a simple own app workable today, but it rests on the device's security being switched off, which is itself something ticket 11 may want to change. Two honest consequences:

- If SELinux stays permissive, ticket 19's app can be an ordinary app.
- If it is switched to enforcing, the app has to be signed with the platform key (which is the public test key on this firmware, so that is possible) and placed as a system app, or the properties have to be set by a small root helper.

## What ticket 19 needs to do

1. Show a corner-adjustment screen usable with the remote's arrow keys.
2. Write the eight properties as the user adjusts them, and let the display server apply them live.
3. Offer a reset to zero.
4. Carry shortcuts for the HDMI input, Settings and the file manager.
5. Find out by testing which corner name belongs to which physical corner, because the naming cannot be trusted from the code alone.

## Still to confirm on the device

- That setting the eight properties really moves the picture, and whether the display server applies them immediately or needs a restart.
- Which physical corner each property controls.
- Whether projection orientation (ceiling, rear) is also a property; it was not found among them, so it may be a setting inside the vendor settings app or a call into the display hardware. This is the one part of ticket 18 that is unresolved.
- What the three "alias" properties and the two `keystone_vaf` properties do.
- Whether an ordinary app can set the properties in practice, which the first test will show.
