# 13 Launcher and file manager

Type: research
Status: resolved

## Question

Does FLauncher (open source) work as the only home app on an Android 11, 32-bit projector, with tiles for HDMI input, Settings, a keystone app and a file manager, driven by the remote? Which build is current and trustworthy, does removing the stock launcher break anything Android needs, and is Material Files usable with a remote and able to install APKs? How does Projectivy compare as the fallback?

## Answer

FLauncher (open-source osrosal fork, 32-bit build, no internet permission) can be the only home app; Android needs no part of the stock launcher except that some home app exists. Settings gets a tile directly; HDMI input and keystone need a small own shortcut app. Material Files (F-Droid) works with the remote and installs APKs. Projectivy stays the fallback, but it is closed source and uses the network. To confirm on the unit: which services the stock launcher hosts besides its screens.

Findings: [research/13-launcher-and-file-manager.md](../research/13-launcher-and-file-manager.md)
