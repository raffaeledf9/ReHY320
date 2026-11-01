#!/bin/bash
# Builds AirPlay Server inside the build image (see setup.sh), for this projector only.
#
#   wsl -u root -e bash /tmp/hy320-run.sh build      (log: <build>\build.log)
#
# Release build, minified as upstream ships it, but only armeabi-v7a: the projector is
# 32-bit, and skipping arm64/x86_64 roughly thirds the native work (FFmpeg, OpenSSL).
# Unsigned here; signing happens afterwards with our own key (sign.sh). The output is
# copied to <build>\out\ so Windows can reach it without mounting anything.
set -euo pipefail
MNT=/mnt/hy320-build
IMG=${HY320_BUILD:?set HY320_BUILD to your own folder}/build.img
mountpoint -q "$MNT" || { mkdir -p "$MNT"; mount -o loop,noatime "$IMG" "$MNT"; }

sudo -u "#${SUDO_UID:-1000}" env MNT="$MNT" bash <<'USER'
set -euo pipefail
export JAVA_HOME="$MNT/jdk" ANDROID_HOME="$MNT/sdk" GRADLE_USER_HOME="$MNT/gradle-home"
export PATH="$JAVA_HOME/bin:$PATH"
cd "$MNT/src"
echo "== $(date +%T) tree: $(git rev-parse --short HEAD), local changes:"
git status --short | sed 's/^/   /'
# Upstream's release block lists every ABI; narrow it for this build only, reverted after.
sed -i 's/ndk { abiFilters += allAbis }/ndk { abiFilters += listOf("armeabi-v7a") }/' app/build.gradle.kts
# undo only this narrowing, so the patch's own edits to the same file survive
trap 'sed -i "s/ndk { abiFilters += listOf(\"armeabi-v7a\") }/ndk { abiFilters += allAbis }/" app/build.gradle.kts' EXIT
chmod +x gradlew
echo "== $(date +%T) gradle assembleRelease (armeabi-v7a)"
./gradlew --no-daemon --console=plain -Dorg.gradle.jvmargs=-Xmx3g assembleRelease
out=app/build/outputs/apk/release
ls -la "$out"
mkdir -p $HY320_BUILD/out
cp "$out"/*.apk $HY320_BUILD/out/
echo "== $(date +%T) copied to $HY320_BUILD\\out"
USER
