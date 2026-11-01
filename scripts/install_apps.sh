#!/bin/bash
# Step 3: install the four apps over USB. Nothing here touches a partition; the undo for
# every line is "uninstall". Each file is checked against the digest recorded when it was
# downloaded, before it is installed.
set -u
# The projector. Set ANDROID_SERIAL, or let it take the only device attached.
SERIAL="${ANDROID_SERIAL:-$(adb devices | awk 'NR==2{print $1}')}"
A=${HY320_BACKUP:?set HY320_BACKUP to the folder holding your own dump of this projector, e.g. /mnt/d/hy320-backup}/apps
adb() { command adb -s $SERIAL "$@"; }

declare -A WANT=(
  [flauncher-armeabi-v7a-2025.07.001.apk]=467fd0befe6daa3993a8a34a3981a631858ace28b38d9836d691478af8b71e40
  [material-files-1.7.5.apk]=2fe900bf43d725b655008d438f5ca46d0da0f301e3784403b5b96c3fc2df6e8a
  [airplay-server-0.0.36.apk]=b8c7c595ed93f91562feedce92c27800f08f9c84df424f6ac2045e82324cf2a4
  [projector-tools-1.0.apk]=5e18813d541f05b10f4e2fe8497c6cef0d25af51dce56cc3f34585a59902f11b
)
ORDER="flauncher-armeabi-v7a-2025.07.001.apk material-files-1.7.5.apk airplay-server-0.0.36.apk projector-tools-1.0.apk"

echo "### checking the files before installing anything"
for f in $ORDER; do
  got=$(sha256sum "$A/$f" | cut -d' ' -f1)
  if [ "$got" = "${WANT[$f]}" ]; then echo "  ok      $f"
  else echo "  DIGEST MISMATCH $f"; echo "    have $got"; echo "    want ${WANT[$f]}"; exit 1; fi
done

adb get-state >/dev/null 2>&1 || { echo "the projector is not in Android over USB"; exit 1; }

echo "### installing"
declare -A PKG
for f in $ORDER; do
  before=$(adb shell pm list packages -3 | tr -d '\r' | sort)
  out=$(adb install -r "$A/$f" 2>&1 | tr -d '\r')
  echo "$out" | tail -1 | sed "s/^/  $f: /"
  after=$(adb shell pm list packages -3 | tr -d '\r' | sort)
  new=$(comm -13 <(echo "$before") <(echo "$after") | sed 's/^package://')
  if [ -n "$new" ]; then PKG[$f]="$new"; echo "    package: $new"
  else
    # already installed, or the install failed
    echo "    no new package appeared"
  fi
done

echo "### versions on the projector"
for f in $ORDER; do
  p=${PKG[$f]:-}
  [ -n "$p" ] && adb shell dumpsys package "$p" | tr -d '\r' | grep -m1 versionName | sed "s/^ */  $p /"
done

L=${PKG[flauncher-armeabi-v7a-2025.07.001.apk]:-}
if [ -n "$L" ]; then
  act=$(adb shell cmd package resolve-activity --brief -c android.intent.category.HOME "$L" | tr -d '\r' | tail -1)
  echo "### making the launcher the home screen: $act"
  adb shell cmd package set-home-activity "$act" | tr -d '\r' | sed 's/^/  /'
  echo "  home is now: $(adb shell cmd shortcut get-default-launcher 2>/dev/null | tr -d '\r' | tail -1)"
fi

P=${PKG[airplay-server-0.0.36.apk]:-}
if [ -n "$P" ]; then
  echo "### AirPlay: allowing it to draw over other apps, then opening it once"
  adb shell appops set "$P" SYSTEM_ALERT_WINDOW allow && echo "  permission allowed"
  adb shell monkey -p "$P" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 && echo "  opened"
fi

echo "### what is on screen now"
adb shell dumpsys window 2>/dev/null | tr -d '\r' | grep -E "mCurrentFocus|mFocusedApp" | sed 's/^ */  /'
echo "### third-party apps installed"
adb shell pm list packages -3 | tr -d '\r' | sed 's/^package:/  /' | sort
