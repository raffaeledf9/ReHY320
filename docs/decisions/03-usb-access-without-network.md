# 03 USB access without a network

Type: research
Status: resolved

## Question

How does the Windows PC talk to the HY320 over a USB-A to USB-A cable with no network, using only official or open-source tools: normal debugging, fastboot, and the chip's USB recovery mode? Which port, settings and drivers are needed for each, how is recovery mode entered and proven with a read-only check, and how is a full copy of the storage taken straight to an external drive and verified?

## Answer

One USB-A to USB-A link (the user's cable plus adapter) in the projector's rear USB-A port covers all three modes: normal debugging (after turning on USB debugging), fastboot (reached from debugging), and the chip's recovery mode (button above the HDMI port; proven by a read-only identification command from a patched open-source tool in WSL 2). The golden backup streams straight to the external drive and is checked by size and checksum. On stock firmware the raw storage is writable without permission checks, so the backup script must only ever read from it. To confirm on the unit: whether Windows needs the Google USB driver, the chip ID the recovery tool reports, and how recovery mode is entered from fastboot.

Findings: [research/03-usb-access-without-network.md](../research/03-usb-access-without-network.md)
