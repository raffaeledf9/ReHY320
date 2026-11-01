#!/bin/sh
echo "######## catch-all property rules (what persist.display.keystone_* falls under)"
grep -nE '^persist\.[[:space:]]|^persist\.sys\.[[:space:]]|^\*[[:space:]]|^persist\.[a-z]*\.[[:space:]]' /mnt/hy320/system/system/etc/selinux/plat_property_contexts | head -20
echo
echo "######## rules that could cover an undeclared persist.display.* property"
grep -nE '^persist\.' /mnt/hy320/system/system/etc/selinux/plat_property_contexts | awk '{print $1" "$2}' | grep -E 'persist\.(display|sys)\.?[[:space:]]|persist\.[[:space:]]' | head
