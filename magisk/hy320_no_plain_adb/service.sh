#!/system/bin/sh
# Close the plain adb-over-TCP port the vendor leaves open.
#
# /default.prop in the boot ramdisk carries service.adb.tcp.port=5555, which
# adbd reads when it starts. The port is only read at start, so closing it
# means setting the property and restarting adbd.
#
# This runs after hy320_adb_wifi (alphabetical order), so if that module is
# enabled it has already asked for TLS and the single restart below brings
# adbd up with TLS on and 5555 closed.

until [ "$(getprop sys.boot_completed)" = "1" ]; do
  sleep 2
done
sleep 20          # let the framework settle; it rewrites adb properties at boot

resetprop service.adb.tcp.port -1
stop adbd
start adbd
