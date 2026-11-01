#!/bin/sh
# Print the full definition of the non-AOSP services and the vendor scripts. Read-only.
A=${HY320_BACKUP:?set HY320_BACKUP to your own folder}/analysis
OUT=$A/inventory
S=/mnt/hy320/system/system
{
  for rc in qw preinstall appsdisable gmsopt systemmix isomountservice gpioservice blank_screen multi_ir; do
    echo "######## $rc.rc"; cat "$S/etc/init/$rc.rc" 2>/dev/null; echo
  done
  echo "######## non-AOSP service blocks in init.rc"
  awk '/^service (esharecp|eshareover|iosmain|netflix_copy|replace_file)/,/^$/' "$S/etc/init/hw/init.rc"
  echo "######## shell scripts referenced by those services"
  for sh in eshare.sh netflix_copy.sh replace_file.sh logcatshell.sh; do
    echo "---- /system/bin/$sh"; cat "$S/bin/$sh" 2>/dev/null; echo
  done
  echo "######## services defined in vendor"
  find /mnt/hy320/vendor -name '*.rc' -exec grep -Hn '^service \|^    exec' {} \; 2>/dev/null | sed 's|/mnt/hy320||'
  echo
  echo "######## /oem mount options in fstab"
  grep -rn 'oem\|media_data' /mnt/hy320/vendor/etc/fstab* 2>/dev/null
  echo
  echo "######## file facts for the suspect binaries"
  for b in qw preinstall appsdisable gmsopt systemmixservice iosmain; do
    ls -l "$S/bin/$b" 2>/dev/null
  done
} > "$OUT/suspects.txt"
cat "$OUT/suspects.txt"
