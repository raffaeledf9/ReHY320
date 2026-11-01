#!/system/bin/sh
#
# Passpoint sign-up (com.android.hotspot2.osulogin) lives inside an APEX, and a
# Magisk module cannot mount over /apex, so it cannot be masked like the other
# seven components this module hides. Disabling it does not survive a reboot
# either: apexd re-scans at boot and the package returns at its default state,
# which was measured, not assumed. So it is disabled again on every boot from
# here, which also means removing this module brings it back.

until [ "$(getprop sys.boot_completed)" = 1 ]; do
    sleep 2
done
sleep 15                # package manager is not ready the instant boot completes
pm disable-user --user 0 com.android.hotspot2.osulogin >/dev/null 2>&1
