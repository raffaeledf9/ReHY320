#!/system/bin/sh
# Puts AirPlay Server's saved pairing identity back after a reinstall, so the iPad sees the
# same receiver. Run as root on the projector with the two files in /data/local/tmp.
# The owner uid is read from the installed package, since a reinstall assigns a new one.
D=/data/data/io.github.jqssun.airplay
U=$(stat -c %U "$D")
[ -n "$U" ] || { echo "app data dir missing"; exit 1; }
mkdir -p "$D/files" "$D/shared_prefs"
cp /data/local/tmp/airplay.pem "$D/files/airplay.pem"
cp /data/local/tmp/settings.xml "$D/shared_prefs/settings.xml"
chown "$U:$U" "$D/files" "$D/shared_prefs" "$D/files/airplay.pem" "$D/shared_prefs/settings.xml"
chmod 771 "$D/files" "$D/shared_prefs"
chmod 600 "$D/files/airplay.pem"
chmod 660 "$D/shared_prefs/settings.xml"
restorecon -R "$D/files" "$D/shared_prefs"
ls -laZ "$D/files" "$D/shared_prefs"
md5sum "$D/files/airplay.pem" "$D/shared_prefs/settings.xml"
rm -f /data/local/tmp/airplay.pem /data/local/tmp/settings.xml /data/local/tmp/restore_identity.sh
