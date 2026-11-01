#!/bin/sh
C=${HY320_BACKUP:?set HY320_BACKUP to your own folder}/cleaned
O=$HY320_BACKUP/analysis/logical
for n in system product; do
  for name in com.htc.storeos com.hotack.writesn com.mobisystems.office; do
    b=$(grep -c -a "$name" "$O/${n}_b.img" 2>/dev/null || echo 0)
    a=$(grep -c -a "$name" "$C/${n}_b.img" 2>/dev/null || echo 0)
    echo "  $n / $name: before $b, after $a"
  done
done
