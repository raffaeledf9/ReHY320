# 31 Bring back brightness and colour

Type: research
Status: resolved 2026-10-25
Raised: 2026-10-25, after the vendor settings app was removed
Blocked by: nothing

## Question

How does this projector set picture brightness, colour temperature, contrast, hue and
saturation, and how can our own app set them now that the vendor settings app is gone?

- Which interface actually changes the panel, and whether an ordinary app can reach it,
  or whether it needs the superuser we now have.
- How to read the values the projector holds today, before writing anything.
- Whether a change applies at once, like keystone through the compositor, or needs the
  compositor restarted, like projection.
- What the safe range of each value is, and what a wrong one does.
- Whether "picture mode" presets exist underneath, or only the individual numbers.

## What is already known

All of this came out of the audit and the keystone work; none of it has been tested.

**The vendor app used a hardware interface, not properties.** Its code imports
`vendor.aw.homlet.tvsystem.tvserver@1.0::ITvServer` over `HwBinder`, and contains the
method names `factoryGetPanelValue`, `factorySetPanelValue`, `getBrightness` and
`getColorTemperature`. Its screens are `ScreenBrightnessActivity`,
`ColorTemperatureActivity` and a picture-mode screen, with sliders named `iv_bright`,
`iv_contrast`, `iv_hue` and `iv_saturation`.

**The policy already allows an ordinary app to reach that service.** From this unit's own
`/vendor/etc/selinux/vendor_sepolicy.cil`:

    (allow untrusted_app_30_0 tvserver_hwservice (hwservice_manager (find)

That is the opposite of what blocked the live keystone: the compositor refused us on a
**permission** check inside SurfaceFlinger, which SELinux had nothing to do with. Here
there may be no such check, in which case this works without superuser — and with it
either way.

**There is a second, unexplored candidate: a picture-quality HAL.** The same policy names
`hal_pqcontrol`, `hal_pqcontrol_exec` and `vendor_pqcontrol_hwservice`. Nothing has looked
at it yet. First checks on the device: `ls /vendor/bin/hw/ | grep -i pq`,
`grep -a pqcontrol /vendor/etc/selinux/vendor_hwservice_contexts`, and whether anything of
that name is running.

**Other threads worth pulling:**

- `persist.sys.panelvalue`, a property the vendor app reads and which is empty on this
  unit.
- `/system/framework/com.softwinner.tv.jar`, declared in
  `/system/etc/permissions/com.softwinner.tv.xml`, so an app may use it with
  `<uses-library>`. The vendor app also carried a bundled Softwinner SDK, the one whose
  `E_AW_PANEL_CONFIG_MIRROR` applies the projection flip; panel brightness probably sits
  beside it.
- The vendor APK is kept at `.scratch/vendor-app/HotackSettingsT08_QZ.apk`, so its
  bytecode can be read exactly as the keystone call was recovered: `dexdump -d`, find the
  call site, read the interface name, the transaction number and the order of the
  arguments. That is how `transact(1050, …)` and its eight floats were found.

## How to go about it

1. Read, before writing. Find the call that *gets* the current values and record them.
   Both the keystone and projection mechanisms were understood by measuring first, and
   both times the first guess was wrong.
2. Prefer the route that needs no superuser, so the screen keeps working if root is ever
   removed; fall back to superuser as keystone does.
3. Try one value with a visible effect, by hand, before building a screen around it.

## Safety note

`factorySetPanelValue` is named like factory calibration, not like a user setting. Panel
calibration data can be the sort of thing that is written once at the factory and not
meant to be rewritten. So: find the read path first, write the current values down, and
treat the first write as a real device change with its undo in hand — not as an
experiment. If the values turn out to live in a partition rather than in memory, that
needs the same care as any other partition write.

## What done looks like

Either a screen in our app that sets brightness and colour the way the keystone screen
sets corners, or a written statement of why it cannot be done without the vendor app,
with the evidence for it. Both outcomes close this ticket; a guess does not.

## Answer (2026-10-25)

**Yes, and without superuser.** Brightness was changed from the shell as an ordinary
caller and the change was visible on the wall, confirmed by alternating it between 25 and
75.

The route, recovered from the vendor app's own bytecode (`dexdump -d`, then following the
obfuscated classes):

    com.htc.util.e   "DisplayPQManager"   getBrightness -> a(1), setBrightness -> e(1, v)
      -> com.softwinner.a                 thin wrapper
        -> d.a.a.a.a.a.a$a                the generated HIDL proxy

| | |
|---|---|
| Interface | `vendor.aw.homlet.tvsystem.tvserver@1.0::ITvServer`, instance `default` |
| Transport | HwBinder, so `service call` cannot reach it; it is not a plain binder service |
| Get | transaction **98**, takes one int (the identifier), returns an int |
| Set | transaction **97**, takes the identifier and the value, returns a status |
| Brightness | identifier **1** |
| Colour temperature | identifier **12** |

**It needs no root.** The probe ran as plain `shell` and worked, and this unit's policy
already contains `(allow untrusted_app_30_0 tvserver_hwservice (hwservice_manager (find)`,
so our ordinary app can do the same. That is the opposite of keystone, where SurfaceFlinger
refused us on its own permission check.

**The values as found, before anything was changed** (and restored afterwards):

    id 0 = 1     id 4 = 50    id 8  = 0     id 12 = 0   (colour temperature)
    id 1 = 50    id 5 = 50    id 9  = 0     id 13 = 0
    id 2 = 50    id 6 = 100   id 10 = 0     ids 14-16 = -1 (unused)
    id 3 = 50    id 7 = 1     id 11 = 3

**The identifiers, established on the projector on 2026-10-25** by setting each in turn
between 0 and 100 and watching a solid blue screen with white writing:

| id | what it is | how it was told apart | default |
|---|---|---|---|
| 1 | brightness | named in the vendor app's own bytecode | 50 |
| 2 | saturation | drains the blue towards grey, barely touching the white | 50 |
| 3 | contrast | moves the blue **and** the white together, which saturation cannot | 50 |
| 4 | hue | blue turns green: unmistakable | 50 |
| 5 | unidentified | no visible change at either extreme; possibly sharpness | 50 |
| 12 | colour temperature | named in the vendor app's own bytecode | 0 |

Only 1, 12 and 4 are certain. 2 and 3 are told apart by the white: saturation cannot move
a white that has no colour to lose, so the one that moved the white is contrast.

Colour temperature stores whatever it is given, with no clamping, so it is a mode number
rather than a percentage; the HAL names `ColorTempMode` internally. **Only 0, 1 and 2 do
anything: 3 and above blank the picture completely**, found by trying them on 2026-10-25.
Nothing on the projector enforces that, so the app does: the screen stops at 2. Which
number is which mode is still unknown, so the raw number is shown.

A plain colour screen is the right test pattern. The first attempt was judged against the
launcher and gave the wrong answer for id 2.

The probe is `.scratch/pq/PqProbe.java`: it reads a range of identifiers, or sets
one, and is built with `javac` then `d8` and run with `app_process`. It writes nothing
unless told to.

## Done

A **Picture** screen is in the app, with brightness, contrast, saturation, hue and colour
temperature, reached from its own tile on the home screen. It talks to the display service
directly, with no superuser, so it keeps working if root is ever removed. The code is
`Picture.java` for the service and `PictureActivity.java` for the screen.

Still unchecked: whether the values survive a restart.
