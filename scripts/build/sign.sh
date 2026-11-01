#!/bin/bash
# Signs the built AirPlay Server APK with our own key, inside the build image.
#
#   powershell -File scripts\build\start.ps1 sign      (log: <build>\sign.log)
#
# The key is made once and kept in the image AND copied to <build>\keys\, because
# every later build must be signed with the same key or Android refuses it as an update.
# The upstream release key is the developer's and is not available; this is the cost of a
# self-built app (ticket 14's pinned certificate no longer applies to it).
set -euo pipefail
MNT=/mnt/hy320-build
IMG=${HY320_BUILD:?set HY320_BUILD to your own folder}/build.img
mountpoint -q "$MNT" || { mkdir -p "$MNT"; mount -o loop,noatime "$IMG" "$MNT"; }

sudo -u "#${SUDO_UID:-1000}" env MNT="$MNT" bash <<'USER'
set -euo pipefail
export JAVA_HOME="$MNT/jdk" PATH="$MNT/jdk/bin:$PATH"
BT="$MNT/sdk/build-tools/36.0.0"
KS="$MNT/keys/airplay-hy320.jks"
mkdir -p "$MNT/keys" $HY320_BUILD/keys $HY320_BUILD/out
if [ ! -f "$KS" ]; then
    echo "== generating the signing key (kept: later builds must use the same one)"
    keytool -genkeypair -keystore "$KS" -storepass hy320airplay -keypass hy320airplay \
        -alias airplay -keyalg RSA -keysize 3072 -validity 10950 \
        -dname "CN=AirPlay Server (HY320 build), OU=Owner built, O=Private, C=IT"
fi
cp "$KS" $HY320_BUILD/keys/
IN=$(ls "$MNT"/src/app/build/outputs/apk/release/*.apk | head -1)
echo "== input $IN"
"$BT/zipalign" -c -p 4 "$IN" && echo "aligned"
OUT=$HY320_BUILD/out/airplay-server-0.0.36-hy320.5.apk
"$BT/apksigner" sign --ks "$KS" --ks-pass pass:hy320airplay --key-pass pass:hy320airplay \
    --ks-key-alias airplay --out "$MNT/signed.apk" "$IN"
"$BT/apksigner" verify --print-certs "$MNT/signed.apk" | grep -E 'Signer #1 certificate (DN|SHA-256)'
"$BT/aapt" dump badging "$MNT/signed.apk" | grep -E "^package:|native-code|sdkVersion"
cp "$MNT/signed.apk" "$OUT"
sha256sum "$OUT"
USER
