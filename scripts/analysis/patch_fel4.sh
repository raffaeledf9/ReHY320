#!/bin/sh
cd /usr/local/src/sunxi-tools-h713 || exit 1
sed -n '215,285p' fel_lib.c
