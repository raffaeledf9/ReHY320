#!/bin/sh
cd /usr/local/src/sunxi-tools-h713 || exit 1
echo "### definitions of the transfer helpers"
grep -n "aw_fel_write(feldev\|aw_fel_read(feldev\|aw_usb_write\|aw_send_fel_request\|usb_bulk_send" fel.c | head -20
echo
echo "### the body of aw_fel_write"
awk '/aw_fel_write\(feldev_handle/,/^}/' fel.c
echo
echo "### the body of aw_fel_write_buffer or similar"
awk '/aw_fel_write_buffer\(feldev_handle/,/^}/' fel.c | head -30
