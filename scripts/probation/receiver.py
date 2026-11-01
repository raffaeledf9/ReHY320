"""HY320 probation: receive the ASUS router's syslog on UDP 514.

Keeps lines about the projector and the router's own non-firewall lines,
writes an hourly count of all lines, and resolves expected names every 10 min.

Usage: python receiver.py <pc_ip> <projector_ip> <expected.txt> <out_dir> [router_ip]

<projector_ip> may end in a dot, e.g. 192.168.1., to keep everything from that
range. That is for the projector's very first join, before it has an address
worth pinning: the first minutes online are the most telling, and they would
otherwise be dropped by a filter aimed at an address it does not have yet.

Runs with the base interpreter, not a venv: on Windows a venv's python.exe is a
redirector, and the firewall rule has to name the process that opens the socket.
The line it prints at start is that path.
"""
import datetime, pathlib, socket, sys, threading, time

PC_IP, PROJ_IP, NAMES, OUT = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3]), pathlib.Path(sys.argv[4])
ROUTER_IP = sys.argv[5] if len(sys.argv) > 5 else "192.168.1.1"
OUT.mkdir(parents=True, exist_ok=True)

def append(kind, text):
    t = datetime.datetime.now().astimezone()      # PC clock, with UTC offset (DST-safe)
    # ponytail: reopens the file per line; fine at a few lines per second
    with open(OUT / f"{kind}-{t:%Y-%m-%d}.tsv", "a", encoding="utf-8") as f:
        f.write(f"{t.isoformat(timespec='seconds')}\t{text}\n")

def resolver():                                  # what the router's DNS answers for expected names
    while True:
        # NAMES plus NAMES.local if present: the house's own entries are kept out of the
        # repository, so both have to be read here. See analyze.py.
        lines = NAMES.read_text(encoding="utf-8").splitlines()
        local = NAMES.with_name(NAMES.name + ".local")
        if local.exists():
            lines += local.read_text(encoding="utf-8").splitlines()
        for line in lines:
            name = line.split()[0] if line.strip() else ""
            if name and name[0] not in "#.":     # skip comments and .suffix entries
                try:
                    ips = socket.gethostbyname_ex(name)[2]
                except OSError:
                    ips = []
                append("dns", f"{name}\t{','.join(ips)}")
        time.sleep(600)

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 1 << 20)
sock.bind((PC_IP, 514))                          # fails loudly if the PC lost its fixed address
hello = (f"listening {PC_IP}:514/udp, router {ROUTER_IP}, keeping {PROJ_IP}, "
         f"interpreter {getattr(sys, '_base_executable', sys.executable)}")
print(hello, flush=True)
append("log", f"#start	{hello}")      # the scheduled task has no console to print to
threading.Thread(target=resolver, daemon=True).start()
hour, count = None, 0
while True:
    try:
        data, (src, _) = sock.recvfrom(65535)    # Windows errors on datagrams larger than the buffer
    except OSError as e:                         # one Winsock error must not end 7 days of logging
        append("log", f"#error\t{e}")
        time.sleep(1)
        continue
    if src != ROUTER_IP:
        continue
    now_hour = datetime.datetime.now().astimezone().strftime("%Y-%m-%dT%H%z")
    if now_hour != hour:
        if hour:
            append("log", f"#count\t{hour}\t{count}")
        hour, count = now_hour, 0
    count += 1
    msg = data.decode("utf-8", "replace").strip()
    f = dict(t.split("=", 1) for t in msg.split() if "=" in t)
    ours = (lambda v: bool(v) and v.startswith(PROJ_IP)) if PROJ_IP.endswith(".")         else (lambda v: v == PROJ_IP)
    if "SRC" not in f or ours(f.get("SRC")) or ours(f.get("DST")):
        append("log", msg)
