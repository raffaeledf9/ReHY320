#!/bin/bash
# Prepares a build environment for AirPlay Server entirely on the drive HY320_BUILD names,
# so nothing large lands on the system disk.
#
#   sudo bash scripts/build/setup.sh            (run inside WSL; idempotent)
#
# That drive is likely exFAT, which has no Linux permissions, symlinks or case sensitivity,
# so the build lives in an ext4 image file on it, loop-mounted at /mnt/hy320-build. Sparse: it
# takes only what is used. Everything goes inside it: JDK, Android SDK + NDK + CMake,
# Gradle's cache, the source and the build output. Nothing is installed with apt, and
# WSL's own disk is not used beyond this script's few lines in /tmp.
#
# Detach when done:  sudo umount /mnt/hy320-build
set -euo pipefail

IMG=${HY320_BUILD:?set HY320_BUILD to your own folder}/build.img
MNT=/mnt/hy320-build
SIZE=40G
CMDLINE_ZIP=commandlinetools-linux-16111833_latest.zip
JDK_URL="https://api.adoptium.net/v3/binary/latest/21/ga/linux/x64/jdk/hotspot/normal/eclipse"
NDK=27.0.12077973          # pinned by app/build.gradle.kts
CMAKE=3.22.1               # cmake_minimum_required in app/src/main/cpp/CMakeLists.txt
PLATFORM=android-37        # compileSdk = 37
BUILD_TOOLS=36.0.0
TAG=v0.0.36
REPO=https://github.com/jqssun/android-airplay-server.git

log() { echo "== $(date +%T) $*"; }

mkdir -p "$(dirname "$IMG")" ||
    { echo "cannot reach $(dirname "$IMG") -- is that drive mounted in WSL?"; exit 1; }

if ! mountpoint -q "$MNT"; then
    if [ ! -f "$IMG" ]; then
        log "creating sparse ext4 image $IMG ($SIZE)"
        truncate -s "$SIZE" "$IMG"
        mkfs.ext4 -q -F -L hy320-build "$IMG"
    fi
    mkdir -p "$MNT"
    mount -o loop,noatime "$IMG" "$MNT"
fi
chown "${SUDO_UID:-1000}:${SUDO_GID:-1000}" "$MNT"
log "mounted: $(df -h "$MNT" | tail -1)"

# Everything below runs as the normal user, inside the image.
sudo -u "#${SUDO_UID:-1000}" env MNT="$MNT" CMDLINE_ZIP="$CMDLINE_ZIP" JDK_URL="$JDK_URL" \
    NDK="$NDK" CMAKE="$CMAKE" PLATFORM="$PLATFORM" BUILD_TOOLS="$BUILD_TOOLS" TAG="$TAG" REPO="$REPO" \
    bash <<'USER'
set -euo pipefail
log() { echo "== $(date +%T) $*"; }
cd "$MNT"
mkdir -p dl

if [ ! -x jdk/bin/java ]; then
    log "JDK 21 (Temurin)"
    curl -fsSL -o dl/jdk.tar.gz "$JDK_URL"
    mkdir -p jdk && tar -xzf dl/jdk.tar.gz -C jdk --strip-components=1
fi
export JAVA_HOME="$MNT/jdk" PATH="$MNT/jdk/bin:$PATH"
java -version 2>&1 | head -1

export ANDROID_HOME="$MNT/sdk"
if [ ! -x sdk/cmdline-tools/latest/bin/sdkmanager ]; then
    log "Android command-line tools"
    curl -fsSL -o "dl/$CMDLINE_ZIP" "https://dl.google.com/android/repository/$CMDLINE_ZIP"
    mkdir -p sdk/cmdline-tools
    rm -rf sdk/cmdline-tools/latest sdk/cmdline-tools/cmdline-tools
    unzip -q "dl/$CMDLINE_ZIP" -d sdk/cmdline-tools
    mv sdk/cmdline-tools/cmdline-tools sdk/cmdline-tools/latest
fi
SDKM="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
yes | "$SDKM" --licenses >/dev/null 2>&1 || true
log "SDK packages: platform $PLATFORM, build-tools $BUILD_TOOLS, NDK $NDK, CMake $CMAKE"
"$SDKM" --install "platforms;$PLATFORM" "build-tools;$BUILD_TOOLS" "ndk;$NDK" "cmake;$CMAKE" "platform-tools" \
    | grep -vE '^\[=*' || true
"$SDKM" --list_installed 2>/dev/null | grep -E 'ndk|cmake|platforms|build-tools'

if [ ! -d src/.git ]; then
    log "source $TAG with submodules (shallow)"
    git clone --depth 1 --branch "$TAG" "$REPO" src
fi
cd src
git -c advice.detachedHead=false checkout -q "$TAG"
git submodule update --init --recursive --depth 1 2>&1 | grep -vE '^(Submodule path|Cloning into)' || true
git log -1 --format='%H %cd'
git submodule status
echo "sdk.dir=$ANDROID_HOME" > local.properties
log "done; image use: $(du -sh "$MNT" 2>/dev/null | cut -f1)"
USER
