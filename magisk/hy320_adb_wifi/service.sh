#!/system/bin/sh
# Ask adbd for TLS wireless debugging.
#
# adbd watches this property live -- its log says "Waiting for
# persist.adb.tls_server.enable=1" -- so it does not need its own restart;
# hy320_no_plain_adb restarts adbd shortly after this runs.
#
# The framework sets this property to 0 during boot, which is why it is set
# here rather than once by hand: it does not survive a reboot on its own.
#
# Disabling this module stops the TLS listener. It does not reopen the plain
# port, which hy320_no_plain_adb keeps shut.

until [ "$(getprop sys.boot_completed)" = "1" ]; do
  sleep 2
done
sleep 15          # before hy320_no_plain_adb's restart, after the framework

resetprop persist.adb.tls_server.enable 1
