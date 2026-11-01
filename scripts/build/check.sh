#!/bin/bash
# What the build environment has: host tools WSL already provides, and the image's state.
for c in curl unzip git perl make python3 file; do
    if command -v "$c" >/dev/null; then echo "$c ok"; else echo "$c MISSING"; fi
done
mountpoint /mnt/hy320-build 2>/dev/null && df -h /mnt/hy320-build | tail -1
ls -la ${HY320_BUILD:?set HY320_BUILD to your own folder} 2>/dev/null
