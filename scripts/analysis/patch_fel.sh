#!/bin/sh
# Show how the tool sends data, so the transfer can be split into smaller pieces.
cd /usr/local/src/sunxi-tools-h713 || exit 1
echo "### the write path"
grep -n "aw_fel_write\b" fel.c | head
echo
echo "### aw_fel_write and its helper"
sed -n '/^static void aw_fel_write(/,/^}/p' fel.c
echo
sed -n '/^void aw_write_buffer/,/^}/p' fel.c
echo
grep -n -A 14 'static void aw_send_fel_request\|static void aw_usb_write\|void aw_fel_send_file' fel.c | head -40
