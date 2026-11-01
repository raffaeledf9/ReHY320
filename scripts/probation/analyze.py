"""HY320 probation: list the projector's destinations and how each is explained.

Usage: python analyze.py <out_dir> <projector_ip> <expected.txt> <ioc.txt> [from] [to]
from/to: ISO times, e.g. 2026-10-21T08:00 (local). Writes destinations.csv.

Verdicts: `A <name>` explained by an expected destination on an expected port;
`CHECK port <name>` right host, wrong port; `CHECK` unexplained, for a person to
decide with the diary; `FAIL ioc` a known-bad address; `FAIL lan attempt` the
projector reaching into the home network.
"""
import csv, datetime, ipaddress, json, pathlib, socket, sys, urllib.request

OUT, PROJ, EXP, IOC = pathlib.Path(sys.argv[1]), sys.argv[2], pathlib.Path(sys.argv[3]), pathlib.Path(sys.argv[4])
ts = lambda s: datetime.datetime.fromisoformat(s).astimezone()   # naive = local time
FROM, TO = [ts(a) for a in sys.argv[5:7]] + [None] * (2 - len(sys.argv[5:7]))

def rows(kind, window):
    for p in sorted(OUT.glob(f"{kind}-*.tsv")):
        for line in p.read_text(encoding="utf-8").splitlines():
            t, _, rest = line.partition("\t")
            if not window or ((not FROM or ts(t) >= FROM) and (not TO or ts(t) <= TO)):
                yield t, rest

# A list, plus the same name with ".local" appended if that file exists. The published
# list says what any HY320 does; the .local one is for the addresses and names that belong
# to one house -- the AirPlay sender, the video sources it is pointed at -- which have no
# business in a repository. It is in .gitignore. Without it those destinations read
# "FAIL lan attempt" and "CHECK", which is the correct answer for someone who has not said
# they expect them.
def entries(p):
    rows = []
    for f in (p, p.with_name(p.name + ".local")):
        if f.exists():
            rows += [l.split() for l in f.read_text(encoding="utf-8").splitlines() if l.strip() and l[0] != "#"]
    return rows
exp = entries(EXP)                                    # name_or_.suffix  proto/port[,proto/port]  component
ports = {e[0]: set(e[1].split(",")) for e in exp}
ioc = {e[0] for e in entries(IOC) if e[0][0].isdigit()}
for name in (e[0] for e in entries(IOC) if not e[0][0].isdigit()):
    try: ioc.update(socket.gethostbyname_ex(name)[2])
    except OSError: pass
by_ip = {}
for _, rest in rows("dns", window=False):             # answers from the whole probation count
    name, _, ips = rest.partition("\t")
    for ip in filter(None, ips.split(",")):
        by_ip.setdefault(ip, set()).add(name)

dests = {}
for t, msg in rows("log", window=True):
    f = dict(x.split("=", 1) for x in msg.split() if "=" in x)
    if f.get("SRC") == PROJ:
        d = dests.setdefault((f["DST"], f.get("PROTO", "?").lower(), f.get("DPT", "")), [t, t, 0])
        d[1], d[2] = t, d[2] + 1

def fcrdns(ip):
    try:
        name = socket.gethostbyaddr(ip)[0]
        return name, ip in socket.gethostbyname_ex(name)[2]
    except OSError:
        return "", False

BOOT = None
def rdap(ip):
    global BOOT
    try:
        BOOT = BOOT or json.load(urllib.request.urlopen("https://data.iana.org/rdap/ipv4.json", timeout=30))["services"]
        a = ipaddress.ip_address(ip)
        _, urls = max(((ipaddress.ip_network(p), u) for ps, u in BOOT for p in ps if a in ipaddress.ip_network(p)),
                      key=lambda x: x[0].prefixlen)
        base = next(u for u in urls if u.startswith("https://"))
        req = urllib.request.Request(base.rstrip("/") + "/ip/" + ip, headers={"Accept": "application/rdap+json"})
        j = json.load(urllib.request.urlopen(req, timeout=30))
        orgs = {str(v[3]) for e in j.get("entities", []) for v in (e.get("vcardArray") or ["", []])[1] if v[0] in ("fn", "org")}
        return f"{j.get('name', '')} {j.get('country', '')} {'; '.join(sorted(orgs))}".strip()
    except Exception as e:                            # ponytail: one bad lookup must not stop the report
        return f"rdap failed: {e}"

with open(OUT / "destinations.csv", "w", newline="", encoding="utf-8") as fh:
    w = csv.writer(fh)
    w.writerow(["dst", "proto", "port", "first", "last", "count", "reverse_name", "rdap", "verdict"])
    for (ip, proto, port), (first, last, n) in sorted(dests.items()):
        pp, lan = f"{proto}/{port}", ipaddress.ip_address(ip) in ipaddress.ip_network("192.168.1.0/24")
        rname, ok = ("", False) if lan else fcrdns(ip)
        hit = sorted(by_ip.get(ip, set())) + [s for s in ports if s.startswith(".") and ok and rname.endswith(s)]
        if ip in ioc:
            v = "FAIL ioc"
        elif ip == "192.168.1.1" and port in ("67", "68", "53", "123"):
            v = "A gateway"          # the router's own DHCP, DNS and time
        elif lan and ip in ports:
            v = "A " + ip    # ponytail: a listed LAN peer (the AirPlay iPad) passes on any port; add ports if it ever misbehaves
        elif lan and ip != "192.168.1.1":             # router-bound lines are not expected at all (INPUT is not logged)
            v = "FAIL lan attempt"
        elif hit:
            v = ("A " if any(pp in ports.get(h, ()) for h in hit) else "CHECK port ") + ",".join(hit)
        else:
            v = "CHECK"                               # B, C or U: decided by a person, with the diary
        w.writerow([ip, proto, port, first, last, n, rname + ("" if ok or not rname else " (unconfirmed)"),
                    rdap(ip) if v == "CHECK" and not lan else "", v])
print(f"wrote {OUT / 'destinations.csv'}: {len(dests)} destinations")

# How much of the week was actually watched. The PC is a laptop that comes and
# goes, so silence is only evidence where there was someone listening: an hour
# with no `#count` line is an hour nobody saw, not an hour the projector was quiet.
hours, first, last, restarts = {}, None, None, 0
device_hours = set()
for t, msg in rows("log", window=True):
    first = first or t
    last = t
    # The projector's own record is the primary one and does not stop when the laptop
    # leaves. Counting only the router's hourly marks measured the laptop's uptime and
    # called every other hour unwatched, which was the opposite of the truth.
    if "SRC=" in msg:
        device_hours.add(t[:13])
    if msg.startswith("#count	"):
        _, hour, n = msg.split("	")
        hours[hour] = hours.get(hour, 0) + int(n)
    elif msg.startswith("#start	"):
        restarts += 1
if first:
    span = (ts(last) - ts(first))
    span_hours = max(1, round(span.total_seconds() / 3600))
    watched = len(hours)
    quiet = sorted(h for h, n in hours.items() if n == 0)
    print(f"coverage: the projector recorded itself in {len(device_hours)} of the "
          f"{span_hours} hours spanned ({first} to {last}).")
    print(f"          the router's own view covered {watched} hour(s), receiver started "
          f"{restarts} time(s) -- that is the laptop's uptime, not the projector's.")
    unwatched = span_hours - len(device_hours)
    if unwatched > 0:
        print(f"          {unwatched} hour(s) have no record from the projector at all: "
              f"either it was off or it was silent. Treat them as unwatched.")
    if quiet:
        print(f"          hours seen but empty: {', '.join(quiet)}")
else:
    print("coverage: nothing collected yet")
