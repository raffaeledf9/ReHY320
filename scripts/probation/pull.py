"""Brings the projector's own records to the PC and puts them in the analyzer's shape.

    python scripts/probation/pull.py [out_dir]

The projector writes two files under /data/adb/netwatch (see netwatch.sh). This
pulls both and rewrites them as `log-device.tsv` in the probation log directory,
using the same `SRC=... DST=... PROTO=... DPT=...` wording the router's syslog
uses, so `analyze.py` reads both sources without knowing the difference. An
`APP=` field is added where the projector could say which process held the
socket, which the router could never have known.

The whole file is rewritten every time rather than appended to, so pulling twice
cannot double-count anything.

Names the projector looked up go to `queries-device.tsv` alongside, one per line
with how often it asked. Those are judged by eye and against the known-bad list;
a name is the most telling thing about a destination.
"""
import collections, pathlib, re, subprocess, sys

HERE = pathlib.Path(__file__).resolve().parent
OUT = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else HERE.parents[1] / ".scratch" / "probation-log"
RAW = HERE.parents[1] / ".scratch" / "probation-device"
DEVICE_DIR = "/data/adb/netwatch"

QUERY = re.compile(r"^(\S+ \S+) IP (\d+\.\d+\.\d+\.\d+)\.\d+ > \S+\.53: .*?\s(?:A|AAAA)\? (\S+?)\.? \(")
SYN = re.compile(r"^(\S+ \S+) IP (\d+\.\d+\.\d+\.\d+)\.\d+ > (\d+\.\d+\.\d+\.\d+)\.(\d+): Flags \[S\],")
NTP = re.compile(r"^(\S+ \S+) IP (\d+\.\d+\.\d+\.\d+)\.\d+ > (\d+\.\d+\.\d+\.\d+)\.(123): ")
PEER = re.compile(r"^(\S+)\t(tcp|udp)\t(\d+\.\d+\.\d+\.\d+):(\d+)\t?(.*)$")
APP = re.compile(r'users:\(\("([^"]+)"')

def fetch(name):
    RAW.mkdir(parents=True, exist_ok=True)
    local = RAW / name
    r = subprocess.run(["adb", "shell", f"su -c 'cat {DEVICE_DIR}/{name}'"],
                       capture_output=True, timeout=300)
    if r.returncode != 0:
        print(f"  could not read {name}: {r.stderr.decode(errors='replace').strip()}")
        return []
    text = r.stdout.decode("utf-8", "replace").replace("\r\n", "\n")
    local.write_text(text, encoding="utf-8")
    return text.splitlines()

def when(stamp):
    """tcpdump's '2026-10-25 05:14:28.123456' as the ISO the analyzer parses."""
    return stamp.split(".")[0].replace(" ", "T")

OUT.mkdir(parents=True, exist_ok=True)
print(f"reading {DEVICE_DIR} from the projector")
capture = fetch("capture.log")
peers = fetch("peers.log")

lines, names = [], collections.Counter()
for line in capture:
    m = QUERY.match(line)
    if m:
        names[m.group(3)] += 1
        continue
    m = SYN.match(line) or NTP.match(line)
    if m:
        proto = "UDP" if m.re is NTP else "TCP"
        lines.append((when(m.group(1)),
                      f"SRC={m.group(2)} DST={m.group(3)} PROTO={proto} DPT={m.group(4)}"))

for line in peers:
    m = PEER.match(line)
    if not m:
        continue
    stamp, proto, ip, port, rest = m.groups()
    app = APP.search(rest)
    lines.append((stamp.split("+")[0],
                  f"SRC=<self> DST={ip} PROTO={proto.upper()} DPT={port}"
                  + (f" APP={app.group(1)}" if app else "")))

# The projector's own address, as it appears in what it captured of itself.
mine = collections.Counter(l.split("SRC=")[1].split()[0] for _, l in lines
                           if "SRC=" in l and "<self>" not in l)
me = mine.most_common(1)[0][0] if mine else "0.0.0.0"
out_lines = [f"{t}\t{l.replace('SRC=<self>', 'SRC=' + me)}" for t, l in sorted(lines)]

(OUT / "log-device.tsv").write_text("\n".join(out_lines) + ("\n" if out_lines else ""), encoding="utf-8")
with open(OUT / "queries-device.tsv", "w", encoding="utf-8") as f:
    for name, n in names.most_common():
        f.write(f"{name}\t{n}\n")

print(f"  projector is {me}")
print(f"  wrote {OUT / 'log-device.tsv'}: {len(out_lines)} connection records")
print(f"  wrote {OUT / 'queries-device.tsv'}: {len(names)} distinct names looked up")
