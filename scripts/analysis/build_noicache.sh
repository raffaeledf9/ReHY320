#!/bin/sh
# Build a second copy of the tool that skips the instruction-cache step for this chip.
# Only the H713 entry is changed; everything else stays as upstream has it.
set -e
SRC=/usr/local/src/sunxi-tools-h713
cd $SRC
if ! grep -q 'icache_fix = false, /\* H713' soc_info.c; then
  python3 -I - <<'PY'
from pathlib import Path
p = Path('/usr/local/src/sunxi-tools-h713/soc_info.c')
s = p.read_text()
i = s.index('0x1860')
j = s.index('},{', i)
block = s[i:j]
assert '.icache_fix   = true,' in block, 'H713 block does not set icache_fix'
s = s[:i] + block.replace('.icache_fix   = true,', '.icache_fix = false, /* H713: running code before a transfer stops this unit answering */') + s[j:]
p.write_text(s)
print('H713 entry: instruction-cache step disabled')
PY
fi
grep -n -A 2 '0x1860' soc_info.c | grep -i icache || true
make -s sunxi-fel 2>&1 | tail -3
cp sunxi-fel sunxi-fel-noicache
echo "built: $(ls -l sunxi-fel-noicache | awk '{print $5}') bytes"
# Restore the normal entry and rebuild the unmodified tool, so both exist side by side.
python3 -I - <<'PY'
from pathlib import Path
p = Path('/usr/local/src/sunxi-tools-h713/soc_info.c')
s = p.read_text().replace('.icache_fix = false, /* H713: running code before a transfer stops this unit answering */', '.icache_fix   = true,')
p.write_text(s)
PY
make -s sunxi-fel 2>&1 | tail -3
echo "both tools ready: sunxi-fel (as upstream) and sunxi-fel-noicache"
