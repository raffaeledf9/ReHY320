# HY320 Rework

Turning a malware-laden HY320 projector into a clean Android projector with AirPlay, without ever leaving it unrecoverable.

## Device states

**Dormant**:
The projector with its stock malware still on it, kept off every network so the malware cannot act. The state it is in today.
_Avoid_: Harmless, safe, uninstalled

**Contained**:
Malicious components disabled for the user but still present on the projector's storage. A temporary step only; a factory reset undoes it.
_Avoid_: Debloated, cleaned

**Clean**:
Only keep-list components remain on the projector's storage (everything else removed, not disabled): no root backdoor, no unauthenticated network ADB, no vendor updater, as verified from the router side rather than by asking the projector.
_Avoid_: Debloated, safe, fixed

**Keep-list**:
The components allowed to stay: stock Android, Allwinner hardware support, and vendor parts a kept feature cannot work without.
_Avoid_: Whitelist, safe list

**Probation**:
The first 7 days online after becoming clean, with all traffic logged; it ends only when every contacted server is explained, else the projector goes back offline.
_Avoid_: Trial, test period

**Deployed**:
Clean, out of probation, on the home Wi-Fi with internet, with the kept features working, AirPlay receiving, and APK installs possible from the PC.
_Avoid_: Done, finished

**Low-trust device**:
How the projector is treated on the home Wi-Fi even when deployed, because its Android security level is frozen: nothing listening beyond what kept features need, and re-checked after every change.
_Avoid_: Untrusted, IoT device

**Install session**:
A bounded window in which the projector accepts ADB from the PC's key only, closed and verified closed at its end.
_Avoid_: Debug mode, wireless debugging

## Features

**Kept features**:
Keystone, focus, projection orientation, HDMI input, picture and sound settings, Wi-Fi and Bluetooth, app list, file explorer, USB media playback, the remote.
_Avoid_: Stock features, parity

**Dropped features**:
Vendor firmware updates, vendor casting and Miracast, Play Store; given up on purpose.
_Avoid_: Missing features

## Safety

**Golden backup**:
The full, checksum-verified copy of this unit's storage taken before any change, kept forever, never executed.
_Avoid_: Dump, image, backup (unqualified)

**Recovery path**:
The chip's ROM-level USB mode (FEL) through which the PC can rewrite the projector even if nothing else boots; proven working before the first device write.
_Avoid_: Unbrick, flash mode

**Device write**:
Any action that changes the projector's storage or settings. Every one needs the user's explicit yes at that moment.
_Avoid_: Step, change

**Safety gate**:
The checks that must all pass before the first device write: golden backup verified, recovery path proven, fastboot answering, fingerprint matching the one recorded at backup.
_Avoid_: Precheck

## Plan

**Runbook**:
The ordered, scripted procedure from the dormant projector to the deployed one, each device write paired with its undo.
_Avoid_: Guide, tutorial
