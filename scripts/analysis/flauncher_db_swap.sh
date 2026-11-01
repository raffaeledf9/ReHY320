#!/system/bin/sh
# Pulls or puts FLauncher's app database, as root on the projector. Written as a file
# because quoting `$` through PowerShell and adb substituted a PC variable into the path.
#
#   sh flauncher_db_swap.sh pull   -> copies db.sqlite(+wal,shm) to /data/local/tmp/fl2/
#   sh flauncher_db_swap.sh put    <- installs /data/local/tmp/fl2/db-new.sqlite
#
# FLauncher is force-stopped first each time so its write-ahead log can't fight the
# edit; it is the home app, so Android starts it again by itself.
#   The new file is pushed by adb to /data/local/tmp/db-new.sqlite (adb cannot write
#   into a root-owned folder), and this moves it.
[ "$(id -u)" = 0 ] || { echo "must run as root"; exit 1; }
D=/data/data/me.efesser.flauncher/app_flutter
T=/data/local/tmp/fl2
am force-stop me.efesser.flauncher
sleep 1
case "$1" in
pull)
    rm -rf "$T"; mkdir -p "$T"
    cp "$D"/db.sqlite* "$T"/
    chmod 755 "$T"; chmod 644 "$T"/*
    ls -la "$T"
    md5sum "$D"/db.sqlite*
    ;;
put)
    [ -s /data/local/tmp/db-new.sqlite ] || { echo "no /data/local/tmp/db-new.sqlite"; exit 1; }
    mkdir -p "$T"
    mv /data/local/tmp/db-new.sqlite "$T/db-new.sqlite"
    cp "$T/db-new.sqlite" "$D/db.sqlite"
    rm -f "$D/db.sqlite-wal" "$D/db.sqlite-shm"
    chown u0_a21:u0_a21 "$D/db.sqlite"
    chmod 600 "$D/db.sqlite"
    restorecon "$D/db.sqlite"
    ls -laZ "$D"
    md5sum "$D/db.sqlite" "$T/db-new.sqlite"
    rm -rf "$T" /data/local/tmp/fldb
    ;;
esac
