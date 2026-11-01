#!/bin/sh
# Capture the state around an AirPlay VIDEO stall. Read-only. Start it, then start AirPlay video on the iPad.
# Usage: sh scripts/analysis/airplay_video_capture.sh [seconds, default 90]
OUT=.scratch/airplay-video-$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUT"
adb logcat -c
adb logcat -v threadtime -b main,system,crash > "$OUT/logcat.txt" &
LOG=$!
PID=$(adb shell pidof io.github.jqssun.airplay | tr -d '\r')
i=0
while [ $i -lt "${1:-90}" ]; do
  {
    echo "=== t=$i $(date +%T) thal=$(adb shell getprop sys.msp_thal_status | tr -d '')"
    adb shell dumpsys media.audio_flinger | grep -E 'Output thread|Standby|Tracks|Type Id|Server|Frames written|Underruns|Flags|Format|Sample rate|^ +[0-9]+ +(yes|no)'
    echo "--- audio players"
    adb shell dumpsys audio | grep -E 'AudioPlaybackConfiguration'
    echo "--- tcp from app pid $PID"
    adb shell netstat -tnp 2>/dev/null | grep -E "$PID/|ESTABLISHED"
  } >> "$OUT/poll.txt"
  i=$((i+1))
  sleep 1
done
adb shell dumpsys media.metrics > "$OUT/media-metrics.txt"
adb shell dumpsys connectivity > "$OUT/connectivity.txt"
adb shell ip -6 route > "$OUT/ip6-route.txt"
adb shell ip route > "$OUT/ip4-route.txt"
kill $LOG
echo "wrote $OUT"
