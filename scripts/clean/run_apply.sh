#!/bin/sh
# Clean one or more images from the plan. Usage: run_apply.sh [image ...]
R=$(cd "$(dirname "$0")/../.." && pwd)   # this repository, wherever it was cloned
P=$R/scripts/clean/apply.py
J=$R/clean/clean-plan.json
S=${HY320_BACKUP:?set HY320_BACKUP to the folder holding your own dump of this projector, e.g. /mnt/d/hy320-backup}/analysis/logical
W=$HY320_BACKUP/cleaned
for img in "$@"; do
  echo "######## $img"
  python3 -I "$P" "$J" "$S" "$W" --image "$img" || exit 1
done
