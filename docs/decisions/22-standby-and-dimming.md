# 22 Standby, dimming and the screensaver

Type: research
Status: resolved
Blocked by: 10

## Question

What exactly makes the projector dim or switch off when idle, and how is the behaviour the user asked for built from clean parts: a screensaver with a replaceable image, a timeout the user can change with a 30-minute default, and no interruption while something is playing? Covers Android's own screensaver framework and screen timeout, the `blank_screen` service, and anything the vendor settings app sets. The app itself is ticket 19.

## Answer

Findings in [research/22-standby-and-dimming.md](../research/22-standby-and-dimming.md).

What makes the picture go away is Android's own power settings, not anything exotic. Five settings give the user exactly what they asked for: the screen-off timeout starts the screensaver (30 minutes is already Android's own default, so the user's choice needs no change), sleeping is switched off entirely so the projector never powers the display down, the screensaver is set to start when it would have slept, the "attentive" timeout is switched off because it is the one timer that overrides a playing app's hold on the screen, and the stay-awake-while-plugged-in setting must be written as zero explicitly, because when the key is absent Android treats a mains-powered device as always awake and the screensaver would then never start at all.

There is no separate screensaver timeout setting in Android 11; the screen-off timeout is the timer.

All five can be set from the PC over USB debugging without root, and they survive a reboot unless the vendor's modified settings store re-seeds them, which has to be checked on the unit.

Two corrections the checker caught and fixed in the findings:
- The user's own screensaver image must live in the shared Pictures folder, not inside the app's private folder: on Android 11 no file manager can reach another app's private folder, so the image would not be replaceable. With it in Pictures, the user can swap it with the file manager or a USB stick.
- The settings screen is not under Display: on this kind of build, "Screen saver" and "Energy saver" sit side by side on the device-preferences screen. Worth confirming on the unit, since some builds have had that picker removed.

What ticket 19's app must provide: an Android screensaver showing an image from the shared Pictures folder, with a default we supply.

To confirm on the device, carried into the runbook: that the five values stick across a reboot; that the projector counts as mains-powered, since Android refuses to start a screensaver on battery; that the HDMI input and each kept player hold the screen awake while playing; that connecting the iPad over AirPlay dismisses the screensaver; and that the Allwinner blank_screen service is inert.
