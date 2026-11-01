#!/bin/sh
# Zero the freed blocks in the cleaned images, so removed content is really gone.
C=${HY320_BACKUP:?set HY320_BACKUP to your own folder}/cleaned
command -v zerofree >/dev/null || apt-get install -y -qq zerofree >/dev/null 2>&1
for n in system product; do
  f="$C/${n}_b.img"
  e2fsck -fp "$f" >/dev/null 2>&1
  if zerofree "$f"; then echo "$n: freed blocks zeroed"; else echo "$n: zerofree FAILED"; fi
done
