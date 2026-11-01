# How keystone correction really works on this projector

Worked out on the projector on 2026-10-24, after two wrong turns.

## The store

Eight properties, one per corner and axis:

    persist.display.keystone_ltx   persist.display.keystone_lty
    persist.display.keystone_rtx   persist.display.keystone_rty
    persist.display.keystone_lbx   persist.display.keystone_lby
    persist.display.keystone_rbx   persist.display.keystone_rby

**125 is neutral.** The compositor divides by a thousand, so 125 arrives as 0.125. x counts
to the right and y counts upwards. One press of the vendor's own screen changes a value by
one: measured by pressing Right ten times on the top left (125 to 139) and Down ten times
on the bottom right (125 to 115).

The other family, `persist.sys.keystone.lt` and friends holding "x,y" pairs, is **not** read
by anything. An earlier attempt drove those and appeared to work; it did not.

## What applies it

The vendor-patched compositor, in `/system/lib/libsurfaceflinger.so`, which loads
`libkeystone.so` and prints `mKeystoneTran[i][j]` for the eight values. It reads them
**only when it starts**. Writing a property changes nothing until then.

Its order is bottom left, top left, top right, bottom right, each x then y.

## The live route, and why we cannot use it

The vendor's settings app changes the picture as you press. Recovered from its own
bytecode:

    ServiceManager.getService("SurfaceFlinger")
    parcel.writeInterfaceToken("android.ui.ISurfaceComposer")
    eight floats, value * 0.001, in the compositor's order
    binder.transact(1050, parcel, null, 0)

Our app makes exactly that call and is refused:

    SurfaceFlinger: Permission Denial: can't access SurfaceFlinger pid=..., uid=10041

The compositor accepts this only from the system itself. The vendor app qualifies because
it runs as **uid 1000**, sharing `android.uid.system`, which needs the platform signing key.
That key is not in the firmware, so no app we build can ever have it -- not by being
installed as a privileged app, not by any allowlist. This route is closed, permanently.

## What our app does instead

- Saves the eight values, which is the real store.
- Draws the shape the picture will take, live, so the aiming is not done blind: a black
  background with the picture drawn as a filled shape whose corners move as you press.
- On the way out, applies for real by restarting the compositor
  (`ctl.restart surfaceflinger`). That takes about five seconds, blanks the picture, shows
  the logo and returns to the launcher. It does **not** restart the projector: uptime is
  unbroken and nothing crashes.

## Also found

- A panel node `/sys/devices/ff140000.i2c/i2c-2/2-001b/panel_keystone_enbale` (the
  misspelling is the vendor's), not yet explored.
- The compositor also reads `persist.sys.projection` and `persist.sys.keystone_vafaa`.
  Poking the latter does not make it re-read.
- Screen zoom lives in `persist.sys.zoom.value` and very probably needs the same
  compositor restart to take effect; it has not been retested since this was understood.
