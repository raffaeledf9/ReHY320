#!/bin/bash
# Step 8b: install the root side -- the Magisk modules, the two scripts that run from
# service.d, and the small dex the standby script needs. Nothing here touches a partition:
# the undo for every line is deleting the file and rebooting.
#
#     bash scripts/install_magisk.sh
#
# The modules under magisk/ are copied as they are, except hy320_less_surface, which is
# built by scripts/clean/less-surface.sh because it is seven empty marker files; run that
# too. hy320_miracast needs an APK that is not in this repository -- see docs/EXTERNAL.md.
set -u
# The projector. Set ANDROID_SERIAL, or let it take the only device attached.
SERIAL="${ANDROID_SERIAL:-$(adb devices | awk 'NR==2{print $1}')}"
SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-${LOCALAPPDATA:-}/Android/sdk}}"
SDK=${SDK//\\//}
REPO=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
# MSYS_NO_PATHCONV is set here and not exported: Git Bash would otherwise rewrite
# /data/local/tmp into C:/Program Files/Git/data/local/tmp, but exporting it also stops it
# rewriting the Unix paths that javac and d8 need as Windows ones.
adb() { MSYS_NO_PATHCONV=1 command adb -s $SERIAL "$@" </dev/null; }
# Git Bash translates Unix paths to Windows ones before a Windows binary sees them, which
# turns the projector's /data/local/tmp into C:/Program Files/Git/data/local/tmp. The switch
# above stops that -- but it stops the translation the LOCAL side of a push needs, so that
# one is done here. Elsewhere there is no cygpath and no translation to undo.
winpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
# A module's own files are root-owned, so everything lands in /data/local/tmp first.
su() { adb shell "su -c '$1'" | tr -d '\r'; }

adb get-state >/dev/null 2>&1 || { echo "the projector is not reachable"; exit 1; }
su 'id' | grep -q 'uid=0' || { echo "no root: patch boot with Magisk first (step 7)"; exit 1; }

echo "### the dex the standby script needs"
# standby-warning.sh sends the audio HAL the "screen_state=on" the vendor's AudioService
# never sends, which is what brings the sound core back after a standby. It skips that if
# the dex is missing, so the projector would come back from standby silent.
D8=$(ls "$SDK"/build-tools/*/d8.bat "$SDK"/build-tools/*/d8 2>/dev/null | sort | tail -1)
PLATFORM="$SDK/platforms/android-30/android.jar"
if [ -n "$D8" ] && [ -f "$PLATFORM" ]; then
  javac -source 8 -target 8 -nowarn -bootclasspath "$PLATFORM" -d "$WORK" \
        "$REPO/scripts/analysis/AudioParam.java" 2>&1 | grep -v 'bootstrap class path' || true
  "$D8" --min-api 21 --output "$WORK" --lib "$PLATFORM" "$WORK/AudioParam.class" >/dev/null
  mv "$WORK/classes.dex" "$WORK/audioparam.dex"
  echo "  built  $(sha256sum "$WORK/audioparam.dex" | cut -c1-16)…"
else
  echo "  SKIPPED: no Android build-tools found under $SDK"
  echo "  Without it the projector comes back from standby with no sound. Build it with"
  echo "  javac + d8 from scripts/analysis/AudioParam.java and push it to"
  echo "  /data/adb/hy320/audioparam.dex, then re-run."
fi

echo "### pushing"
cd "$REPO"
# Each file is pushed, copied into place as root, and then read back: a push that silently
# landed nowhere is the kind of thing this whole project is about not assuming.
install_one() {  # local-path  device-path  mode
  # Android's shell stops at the first carriage return, with an error that names a command
  # ending in '\r'. A checkout on Windows can hand us CRLF whatever .gitattributes says --
  # a file committed before that rule was added keeps its endings until it is checked out
  # again -- so the endings are fixed here rather than trusted. The dex is bytes, not text.
  src=$1
  case "$1" in
    *.dex) ;;
    *) src="$WORK/$(basename "$1")"; tr -d '\r' < "$1" > "$src" ;;
  esac
  want=$(sha256sum "$src" | cut -d' ' -f1)
  adb push "$(winpath "$src")" /data/local/tmp/stage >/dev/null || { echo "  PUSH FAILED $2"; return 1; }
  su "mkdir -p $(dirname "$2") && cp /data/local/tmp/stage $2 && chmod $3 $2"
  got=$(su "sha256sum $2" | cut -d' ' -f1)
  if [ "$want" = "$got" ]; then printf '  ok       %s\n' "$2"
  else printf '  MISMATCH %s\n    pushed %s\n    reads  %s\n' "$2" "$want" "$got"; return 1; fi
}

fail=0
for m in magisk/*/; do
  id=$(basename "$m")
  # Asked before anything is pushed, because the answer decides whether the module's own
  # off switch is set below.
  existed=$(su "[ -d /data/adb/modules/$id ] && echo yes")
  for f in "$m"module.prop "$m"service.sh; do
    [ -f "$f" ] || continue
    mode=644; [ "$(basename "$f")" = service.sh ] && mode=755
    install_one "$f" "/data/adb/modules/$id/$(basename "$f")" $mode || fail=1
  done
  # "disable" is Magisk's own off switch and is empty, so it is created rather than pushed.
  # Only on a first install: on a projector that already has the module, the switch is
  # whatever its owner set it to, and a re-run has no business flipping it.
  if [ -f "$m"disable ]; then
    if [ -z "$existed" ]; then
      su "touch /data/adb/modules/$id/disable"
      echo "  ok       /data/adb/modules/$id/disable (module ships off)"
    else
      echo "  kept     /data/adb/modules/$id on/off as you left it"
    fi
  fi
done

install_one scripts/standby-warning.sh /data/adb/service.d/standby-warning.sh 755 || fail=1
install_one scripts/probation/netwatch.sh /data/adb/service.d/netwatch.sh 755 || fail=1
[ -f "$WORK/audioparam.dex" ] && { install_one "$WORK/audioparam.dex" /data/adb/hy320/audioparam.dex 644 || fail=1; }

su 'rm -f /data/local/tmp/stage'
echo
if [ "$fail" = 0 ]; then
  echo "all files verified on the device. Reboot to apply:  adb reboot"
else
  echo "something did not land as pushed -- read the lines above before rebooting"
  exit 1
fi
