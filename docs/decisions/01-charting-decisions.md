# 01 Charting decisions

Type: grilling
Status: resolved

## Question

What is the destination of this effort, and which rules and scope decisions bind every later ticket? (Four grilling rounds, 2026-10-19.)

## Answer

Destination and scope
- The map ends at an approved runbook; building and running the scripts follows it.
- The deployed projector lives on the normal home Wi-Fi with internet, and its apps (e.g. Netflix) may use it. The user accepted the remaining risk of a frozen Android 11.
- Nothing changes on the iPad.
- Kept features: keystone, focus, projection orientation, HDMI input, picture and sound settings, Wi-Fi and Bluetooth, app list, file explorer, USB media, remote.
- Dropped features: vendor firmware updates, vendor casting and Miracast, Play Store.
- Netflix on the projector is best effort; the old cast-only Chromecast on HDMI is the quality path.

Cleaning
- Clean means only keep-list components remain; everything else is removed, not disabled. It is built from this unit's own golden backup, never from a community or vendor image.
- The stock launcher goes if compromised. Keystone must survive: manual keystone is required, automatic is optional. If no clean component provides keystone, a small open-source keystone app is built, separate from the launcher.
- Launcher: FLauncher (open source); Projectivy as fallback.

Safety
- Safety gate before the first device write: golden backup verified with a second copy, recovery path proven, fastboot answering, device identity matching the backup.
- PC tools: official or open-source only; nothing from the projector ever runs on the PC.
- Scripts live in this repository. Claude drives them; the user does the physical steps and says yes before every device write.
- Golden backup on the external drive; compressed second copy on the PC.
- A short USB-A to USB-A data cable is required.
- Until Clean, the projector never joins any network.

Network and installs
- Probation: 7 days on the ASUS guest network with the router's connection log collected on the PC; every destination must be explained before the projector moves to the home Wi-Fi. AirPlay is tested after the move.
- After every new app or change: a 24-hour re-check on the guest network.
- APKs install from the PC over Wi-Fi in short install sessions that only the PC can use, closed afterwards; a USB stick is the fallback; signatures are checked before install.
- The runbook includes a short router settings check.

Facts from the user
- Router: an end-of-life ASUS.
- An iPad; an old cast-only Chromecast.
- Projector: HY320, Android 11, build UI_Veng.projector.20241225.164550; factory-reset and offline.
- Has an external drive and a USB stick. Cable: the user's USB-A to USB-C cable plus a USB-C (female) to USB-A (male) adapter, plugged into a PC USB-A port, forms the USB-A to USB-A link. Plugging the cable's USB-C end straight into the PC's USB-C port is not used: that cable assumes the USB-A end is the computer.
- PC: adb and fastboot installed, WSL Ubuntu 20.04, Python, 28 GB free on C:.
