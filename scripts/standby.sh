#!/bin/bash
# Step 5: standby. Five settings, each written then read back. No partition is touched.
#   show   - print the current values and save them, so they can be put back
#   set    - write our values and read each one back
#   check  - read them again (use after a restart, since this firmware's settings store
#            is a modified one and may not keep everything)
set -u
# The projector. Set ANDROID_SERIAL, or let it take the only device attached.
SERIAL="${ANDROID_SERIAL:-$(adb devices | awk 'NR==2{print $1}')}"
DREAM=com.hy320.tools/.ScreensaverService
OUT=${HY320_REPO:-$PWD}/.scratch/hy320-rework/standby-before.txt
adb() { command adb -s $SERIAL "$@" </dev/null; }

# namespace key wanted-value
ROWS="
secure sleep_timeout -1
secure screensaver_enabled 1
secure screensaver_components $DREAM
secure screensaver_activate_on_sleep 1
secure attentive_timeout -1
global stay_on_while_plugged_in 0
system screen_off_timeout 1800000
"

read_one() { adb shell settings get "$1" "$2" | tr -d '\r'; }

case "${1:-}" in
show)
  : > "$OUT"
  echo "$ROWS" | while read -r ns key want; do
    [ -z "${ns:-}" ] && continue
    v=$(read_one "$ns" "$key")
    printf '%-7s %-32s %s\n' "$ns" "$key" "$v" | tee -a "$OUT"
  done
  echo "saved to $OUT"
  ;;
set)
  echo "$ROWS" | while read -r ns key want; do
    [ -z "${ns:-}" ] && continue
    adb shell settings put "$ns" "$key" "$want" >/dev/null 2>&1
    got=$(read_one "$ns" "$key")
    if [ "$got" = "$want" ]; then printf '  ok       %-32s %s\n' "$key" "$got"
    else printf '  REFUSED  %-32s wanted %s, reads %s\n' "$key" "$want" "$got"; fi
  done
  ;;
check)
  echo "$ROWS" | while read -r ns key want; do
    [ -z "${ns:-}" ] && continue
    got=$(read_one "$ns" "$key")
    if [ "$got" = "$want" ]; then printf '  kept     %-32s %s\n' "$key" "$got"
    else printf '  CHANGED  %-32s wanted %s, reads %s\n' "$key" "$want" "$got"; fi
  done
  ;;
*) echo "usage: $0 show|set|check"; exit 2 ;;
esac
