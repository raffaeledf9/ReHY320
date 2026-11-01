#!/bin/sh
# What does the vendor settings app use for projection mode and keystone? Read-only.
M=/mnt/hy320-cfg; mkdir -p $M; T=/tmp/vs; rm -rf $T; mkdir -p $T
mountpoint -q $M || mount -o ro,loop,noexec,nosuid,nodev ${HY320_BACKUP:?set HY320_BACKUP to your own folder}/analysis/logical/product_b.img $M
unzip -o -q -d $T "$M/app/HotackSettingsT08_QZ/HotackSettingsT08_QZ.apk" 'classes*.dex' 2>/dev/null
echo "### property names the vendor settings app uses"
cat $T/*.dex | strings -n 6 | grep -E '^(persist|ro|sys|hotack)\.[a-z0-9_.]+$' | sort -u
echo "### projection and orientation strings"
cat $T/*.dex | strings -n 5 | grep -iE 'project|flip|rotat|ceiling|rear|mirror' | sort -u | head -25
echo "### how it talks to the display service"
cat $T/*.dex | strings -n 6 | grep -iE 'keystone|displaymanager|surfaceflinger|1050|setKeystone' | sort -u | head -20
umount $M
