#!/system/bin/sh
#
# Warns, one minute before the projector goes to standby, that it is about to.
#
# Android turns the display off after its own timeout, and on this projector that means
# the lamp and the fans go off. There is no way to show anything with Android's own screen
# saver, because the firmware powers the lamp down the moment Android starts dreaming. So
# this watches how long the projector has been idle and puts an ordinary screen up a
# minute before the dark.
#
# It runs as root from Magisk, which is the only way to read the idle clock: `dumpsys
# power` reports `mLastUserActivityTime=... (N ms ago)`, and nothing an ordinary app can
# reach gives that. Showing the screen does not count as using the projector, so this does
# not postpone the sleep it announces.
#
# It follows whatever standby time is set, rather than keeping its own copy, so changing it
# in the app changes this too.
#
# It also brings the sound core back after a real sleep, and the sound back when the mixer
# wedges after standby: see the top of the loop.
#
# And it keeps the projector awake while sound is playing (audio-only AirPlay holds no screen
# wake lock, so without this the music was cut off by standby): see "Something is playing".

WARN_MS=60000          # how long before the projector goes dark to say so
POLL_SECONDS=10        # how often to look
DREAM_FOR_MS=30000     # how long Android dreams (already dark) before it sleeps outright
REBOOT_MIN_UPTIME=600  # never reboot for sound within this many seconds of boot (no loops)
ACTIVITY=com.hy320.tools/.WarningActivity
AUDIOPARAM=/data/adb/hy320/audioparam.dex   # sends one key=value to the audio HAL

warned_for=""
woke_for=""            # the wake (mLastWakeTime) whose sound core was already brought back
wake_tries=0
last_frames=""
tried_audioserver=0
held=0                 # 1 while this script is keeping the display on for playing sound
quiet=0                # polls since sound last played, while held
QUIET_POLLS=2          # polls of silence before calling it stopped (gaps between tracks)

# Let the system finish starting before asking it anything.
sleep 60

# The hold below is a global setting and outlives a reboot (including the one this script
# does for a wedge), so never start with one left over. Assumes the owner never sets "stay
# awake" themselves.
settings put global stay_on_while_plugged_in 0

while true; do
    sleep "$POLL_SECONDS"
    power=$(dumpsys power 2>/dev/null)

    # The sound core after a real sleep. On SCREEN_OFF the vendor's AudioService sends the
    # HAL "screen_state=off", which uninitialises the Trident sound core (sound_Uninit,
    # sys.msp_thal_status 0). On SCREEN_ON it sends nothing, so the core stays down and
    # every sound after the wake is silent; AirPlay video then has an audio clock that
    # never moves, ExoPlayer calls it "stuck" after 10 s and the cast stops. Found in the
    # framework's own bytecode and the HAL's log on 2026-10-27; sending "screen_state=on"
    # by hand ran Sound_Init and brought the status back to 1 at once, with nothing else
    # restarted. So send the missing half, once per wake and only while the core is down:
    # a second Sound_Init on a running core is not something to try on a hunch.
    if echo "$power" | grep -q 'mWakefulness=Awake'; then
        wake=$(echo "$power" | grep -m1 -oE 'mLastWakeTime=[0-9]+' | grep -oE '[0-9]+$')
        if [ "$(getprop sys.msp_thal_status)" = "0" ] && [ -f "$AUDIOPARAM" ]; then
            [ "$wake" != "$woke_for" ] && wake_tries=0
            if [ "$wake_tries" -lt 2 ]; then
                log -t standby-warning "sound core down after wake $wake: sending screen_state=on"
                CLASSPATH="$AUDIOPARAM" app_process / AudioParam screen_state=on >/dev/null 2>&1
                wake_tries=$((wake_tries + 1))
                woke_for="$wake"
            fi
        fi
    fi

    # After a standby and wake the primary mixer writes a few thousand frames and then
    # stops draining (Frames written froze at 13440 on two separate wedges, measured
    # 2026-10-25), while sys.msp_thal_status still reads 1 -- so the old trigger, which
    # waited for that to read 0, could never fire. ExoPlayer times playback from the
    # audio position, so it calls the player stuck and AirPlay drops. A mixer out of
    # standby writes every ~20 ms, so "Standby: no" with no progress across a whole poll
    # is the wedge itself.
    #
    # Underneath it is a deadlock: the HAL's writer thread sits in
    # WriteIntoBufferOnceAvailable, the ALSA device reads "closed", and the init service
    # gets stuck in state "stopping" so it can never respawn. Restarting the audio HAL
    # does not clear it, and nor does restarting audioserver on its own -- measured. Only
    # a reboot does. audioserver is still tried first, because it is far cheaper and may
    # help a milder wedge; the reboot is the one that is known to work.
    af=$(timeout 5 dumpsys media.audio_flinger 2>/dev/null)
    frames=$(echo "$af" | grep -m1 -oE 'Frames written: [0-9]+' | grep -oE '[0-9]+$')
    playing=0
    echo "$af" | grep -m1 -oE 'Standby: (yes|no)' | grep -q 'no' && [ -n "$frames" ] && [ -n "$last_frames" ] && [ "$frames" -gt "$last_frames" ] && playing=1
    if echo "$af" | grep -m1 -oE 'Standby: (yes|no)' | grep -q 'no'         && [ -n "$frames" ] && [ -n "$last_frames" ] && [ "$frames" -gt 0 ]; then
        # frames of 0 means nothing has played since this thread started, which is how an
        # idle mixer looks in the moment before it drops into standby. The wedge always
        # shows a non-zero count (13440 both times), and the penalty for being wrong here
        # is a reboot, so an untouched mixer is never judged.
        if [ "$frames" = "$last_frames" ]; then
            if [ "$tried_audioserver" = "0" ]; then
                log -t standby-warning "mixer wedged at $frames frames: restarting audioserver"
                killall audioserver
                tried_audioserver=1
                frames=""           # new process, new counter: judge it from scratch
            elif [ "$(cut -d. -f1 /proc/uptime)" -ge "$REBOOT_MIN_UPTIME" ]; then
                log -t standby-warning "mixer still wedged at $frames frames: rebooting"
                reboot
            fi
        elif [ "$frames" -gt "$last_frames" ]; then
            tried_audioserver=0     # draining again: the next wedge gets the cheap fix first
        fi
    fi
    last_frames=$frames

    timeout=$(settings get system screen_off_timeout 2>/dev/null)
    case "$timeout" in
        ''|*[!0-9]*) timeout="" ;;      # not a number yet, or not set
    esac

    # The lamp goes out the moment Android starts dreaming, which is the display timeout
    # itself. The firmware says so in its own log -- "zztest sreenoff enable,do it" on
    # entering the dream, "awake from dreams,and screen,fans on" on leaving it -- and on
    # 2026-10-27 the owner saw the wall go dark at dream entry (21:25:17) and woke it at
    # 21:25:28, before Android's sleep timeout could have done anything. This used to count
    # to the sleep timeout instead, so the "1 minute" warning came only 20-30 s ahead.
    dark_at=$timeout

    # Android's sleep timeout still matters: without it Android dreams for ever and never
    # reaches Asleep. It is kept a little past the dark, in step with whatever standby time
    # the owner chose. It lives here rather than in the app because it is a Secure setting,
    # which needs a signature permission no ordinary app can hold, and this runs as root.
    if [ -n "$timeout" ]; then
        want_sleep=$((timeout + DREAM_FOR_MS))
        [ "$(settings get secure sleep_timeout 2>/dev/null)" = "$want_sleep" ] || settings put secure sleep_timeout "$want_sleep"
    fi

    # Android counts down from whichever came last: a keypress (mLastUserActivityTime) or a
    # screen hold letting go (mLastUserActivityTimeNoChangeLights). Reading only the first
    # warned during a mirror, which then restarted the countdown when it ended.
    stamps=$(echo "$power" | grep -oE 'mLastUserActivityTime(NoChangeLights)?=[0-9]+ \([0-9]+ ms ago\)')
    stamp=$(echo "$stamps" | grep -oE '=[0-9]+' | tr -d '=' | sort -n | tail -1)
    idle=$(echo "$stamps" | grep -oE '\([0-9]+' | tr -d '(' | sort -n | head -1)

    # Something is holding the screen on -- AirPlay mirroring, a film -- so no standby is
    # coming, and putting a screen over it would stop it: AirPlay drops its session the
    # moment it is covered. Measured 2026-10-25.
    screen_held=0
    echo "$power" | grep -qE '^ +(SCREEN_BRIGHT|SCREEN_DIM|FULL)_WAKE_LOCK' && screen_held=1

    # Something is playing: keep the display on, so no standby comes. Audio-only AirPlay
    # holds no screen wake lock, so the check further down does not see it, and standby cut
    # the music off. This also means the display-off path only ever runs on a mixer that
    # has been quiet long enough to drop into standby itself.
    if [ "$playing" = "1" ]; then
        [ "$held" = "0" ] && settings put global stay_on_while_plugged_in 7
        held=1
        quiet=0
        continue
    fi

    # The sound has stopped while held. Letting go only matters if standby is already due:
    # Android has been counting since the last keypress all along, so letting go then would
    # go dark at once, with no warning. In that case warn, and let go a minute later.
    # Otherwise let go quietly and leave the warning to the ordinary check below, at the
    # proper time. This used to warn every time the sound stopped, which on 2026-10-27 put
    # the warning over a paused AirPlay video 26 s after the pause, with standby still 25
    # minutes away, and tore down AirPlay's picture underneath it.
    if [ "$held" = "1" ]; then
        quiet=$((quiet + 1))
        [ "$quiet" -lt "$QUIET_POLLS" ] && continue     # perhaps only a gap between tracks
        if [ "$quiet" = "$QUIET_POLLS" ]; then
            due=1
            if [ "$screen_held" = "1" ]; then
                due=0                                   # something else keeps it awake anyway
            elif [ -n "$dark_at" ] && [ -n "$idle" ] && [ "$idle" -lt $((dark_at - WARN_MS)) ]; then
                due=0                                   # more than a minute to go
            fi
            if [ "$due" = "0" ]; then
                settings put global stay_on_while_plugged_in 0
                held=0
                quiet=0
            else
                am start -n "$ACTIVITY" >/dev/null 2>&1
                warned_for="$stamp"
                continue
            fi
        elif [ "$quiet" -ge $((QUIET_POLLS + WARN_MS / 1000 / POLL_SECONDS)) ]; then
            settings put global stay_on_while_plugged_in 0
            held=0
            quiet=0
            continue
        else
            continue
        fi
    fi

    [ -z "$dark_at" ] && continue
    [ "$dark_at" -le "$WARN_MS" ] && continue   # too short to warn inside
    [ "$screen_held" = "1" ] && continue
    [ -z "$idle" ] && continue

    # Already dark, or not yet near it: nothing to say.
    [ "$idle" -ge "$dark_at" ] && continue
    [ "$idle" -lt $((dark_at - WARN_MS)) ] && continue

    # One warning per idle spell: the stamp changes as soon as anything is pressed.
    [ "$stamp" = "$warned_for" ] && continue

    am start -n "$ACTIVITY" >/dev/null 2>&1
    warned_for="$stamp"
done
