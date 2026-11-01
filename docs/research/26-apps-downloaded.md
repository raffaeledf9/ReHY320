# The apps the projector will run — downloaded and checked

Downloaded to `<backup>\apps\` on 2026-10-22 with `HY320/scripts/apps/fetch.ps1`. Nothing was installed and the projector was not connected. Each file was checked against a digest its publisher states, and each signing certificate was recorded so that any later update signed by someone else is refused by Android automatically.

## AirPlay Server 0.0.36 — fully verified
- `io.github.jqssun.airplay`, 26.1 MB, needs Android 6 and up, carries the 32-bit build this projector needs.
- File digest `b8c7c595…cf2a4` **matches** the digest GitHub publishes for the release file.
- Signing certificate `64ca1fa3…f1a9` **matches** the key F-Droid pins for this app, which is an independent source from GitHub.
- Asks for internet access, as expected: casting a video link means fetching it.

## FLauncher 2025.07.001 — verified against the publisher's digest
- `me.efesser.flauncher`, the `armeabi-v7a` build, 10.5 MB, needs Android 5 and up.
- File digest `467fd0be…1e40` **matches** the digest GitHub publishes for that file.
- **No internet permission at all**, which is what a home screen should look like.
- Signing certificate `3ef9f30d…c101` recorded. No fingerprint is published anywhere, so this is pinned by the first install: Android then refuses any later update signed differently.

## Material Files 1.7.5 — verified against the publisher's digest
- `me.zhanghai.android.files`, 10.4 MB, needs Android 6 and up, includes the 32-bit build.
- Downloaded from F-Droid, and its digest `2fe900bf…6e8a` **matches** the digest the developer publishes on their own release page for the same file. Two independent sources agree on the bytes.
- Signing certificate `9c22a742…2b20` recorded, pinned by the first install.
- Asks for internet access, which it needs for the network share route (ticket 15).

## What could not be done, and why it does not matter
The second F-Droid mirror was unusable: its certificate does not match its hostname. Rather than disable certificate checking to fetch a security-relevant file, the comparison was done against the developer's own published digest instead, which is a stronger source anyway.

## Still to download later
Netflix, Disney+ or Prime Video, if the user wants them on the projector. These publish no download outside the app stores, so they come from a third-party mirror with their certificates compared against older versions, as ticket 05 sets out. They are not needed for the projector to work and can wait.
