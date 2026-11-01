#!/bin/sh
cd /usr/local/src/sunxi-tools-h713 || exit 1
echo "### where the transfer helpers are defined"
grep -rn "void aw_fel_write\|void aw_usb_write\|usb_bulk_send" --include=*.c --include=*.h . | head -20
