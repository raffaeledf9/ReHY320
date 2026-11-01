#!/bin/sh
OUT=${HY320_BACKUP:?set HY320_BACKUP to your own folder}/analysis/inventory
{
  echo "######## any property_contexts line mentioning display or keystone"
  grep -rhiE 'display|keystone' /mnt/hy320/system/system/etc/selinux/plat_property_contexts \
    /mnt/hy320/vendor/etc/selinux/*property_contexts 2>/dev/null | sort -u
  echo
  echo "######## which seapp_contexts entries exist for platform-signed apps"
  grep -hE 'seinfo=platform|user=system' /mnt/hy320/system/system/etc/selinux/plat_seapp_contexts 2>/dev/null
} > "$OUT/props_acl2.txt" 2>/dev/null
cat "$OUT/props_acl2.txt"
