#!/bin/sh
# Who may set the keystone properties, and what the vendor settings app registers. Read-only.
OUT=${HY320_BACKUP:?set HY320_BACKUP to your own folder}/analysis/inventory
{
  echo "######## property contexts for the display and keystone properties"
  grep -rhE '^persist\.display|^persist\.sys\.keystone|^hotack|^persist\.sys\.(replace|eshare)' \
    /mnt/hy320/system/system/etc/selinux/*property_contexts \
    /mnt/hy320/vendor/etc/selinux/*property_contexts \
    /mnt/hy320/product/etc/selinux/*property_contexts 2>/dev/null | sort -u
  echo
  echo "######## default values of those properties in the prop files"
  grep -rhE 'keystone|anti_shake|replace_start' /mnt/hy320/system/system/build.prop \
    /mnt/hy320/vendor/build.prop /mnt/hy320/product/build.prop \
    /mnt/hy320/system/system/etc/prop.default 2>/dev/null | sort -u
  echo
  echo "######## which SELinux domains the policy lets write display properties"
  ls /mnt/hy320/system/system/etc/selinux/ 2>/dev/null
  echo
  echo "######## the focus motor and fan controls in the device tree"
  grep -rhoE 'motor[a-z_]*|speedlevel|prj_temp' /mnt/hy320/vendor/etc/init /mnt/hy320/system/system/etc/init 2>/dev/null | sort -u
} > "$OUT/props_acl.txt" 2>/dev/null
cat "$OUT/props_acl.txt"
