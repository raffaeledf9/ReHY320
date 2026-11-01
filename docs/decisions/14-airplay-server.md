# 14 AirPlay Server on this projector

Type: research
Status: resolved

## Question

For AirPlay Server (io.github.jqssun.airplay) on Android 11, 32-bit, 1 GB RAM: which version and download channel to use, how its authenticity is checked, whether it works with iPadOS 26.6.2, which features it offers, which network ports it uses, whether it starts at boot, and what known problems exist on low-end devices?

## Answer

Use AirPlay Server 0.0.36 from its GitHub releases (one universal APK that includes the 32-bit build), checked twice before install: the file checksum against GitHub's, and the signing certificate against the one F-Droid pins. It very likely works with iPadOS 26.6.2. It listens on one fixed port plus discovery and session ports while casting, starts at boot once opened, and needs the "Display over other apps" permission. AirPlay video (not mirroring) streams from the video's own servers, which the projector's internet access now allows.

Findings: [research/14-airplay-server.md](../research/14-airplay-server.md)
