"""Checks the probation receiver and analyzer against made-up router lines.

Runs the real receiver on loopback, pretending loopback is the router, sends it
one line of each kind that matters, then runs the real analyzer and asserts the
verdicts. Needs the internet for the name lookups the two scripts do anyway.

    python scripts/probation/selfcheck.py
"""
import pathlib, socket, subprocess, sys, tempfile, time, csv

HERE = pathlib.Path(__file__).resolve().parent
PROJ = "192.168.1.200"
LINE = ("<4>Oct 25 03:30:00 kernel: ACCEPT IN=br0 OUT=eth0 SRC={src} DST={dst} "
        "LEN=60 TOS=0x00 PREC=0x00 TTL=63 ID=1 DF PROTO={proto} SPT=41234 DPT={dpt}")

def main():
    out = pathlib.Path(tempfile.mkdtemp(prefix="hy320-probation-check-"))
    rx = subprocess.Popen([sys.executable, str(HERE / "receiver.py"), "127.0.0.1", PROJ,
                           str(HERE / "expected.txt"), str(out), "127.0.0.1"],
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    try:
        time.sleep(1)
        if rx.poll() is not None:
            sys.exit("receiver died at once:\n" + rx.stdout.read())

        # let the resolver write its answers, then borrow a real Google address
        deadline = time.time() + 60
        google = None
        while time.time() < deadline and not google:
            for p in out.glob("dns-*.tsv"):
                for line in p.read_text(encoding="utf-8").splitlines():
                    if "\twww.google.com\t" in line and line.rsplit("\t", 1)[1]:
                        google = line.rsplit("\t", 1)[1].split(",")[0]
            time.sleep(1)
        if not google:
            sys.exit("the resolver never answered for www.google.com; is this PC online?")

        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sent = [(google, "TCP", "443"),            # expected host, expected port
                (google, "TCP", "9999"),           # expected host, wrong port
                ("79.127.216.89", "TCP", "443"),   # on the known-bad list
                ("192.168.1.50", "TCP", "445"),    # reaching into the home network
                ("192.168.1.210", "TCP", "52345"), # the AirPlay sender, on its own random port
                ("185.199.108.153", "TCP", "443")] # unexplained
        for dst, proto, dpt in sent:
            sock.sendto(LINE.format(src=PROJ, dst=dst, proto=proto, dpt=dpt).encode(), ("127.0.0.1", 514))
        # a line from another device, which must be dropped
        sock.sendto(LINE.format(src="192.168.1.77", dst="1.1.1.1", proto="TCP", dpt="443").encode(),
                    ("127.0.0.1", 514))
        time.sleep(2)
    finally:
        rx.terminate()
        rx.wait(timeout=10)

    subprocess.run([sys.executable, str(HERE / "analyze.py"), str(out), PROJ,
                    str(HERE / "expected.txt"), str(HERE / "ioc.txt")], check=True)

    got = {(r["dst"], r["port"]): r["verdict"] for r in csv.DictReader((out / "destinations.csv").open(encoding="utf-8"))}
    assert got[(google, "443")].startswith("A www.google.com"), got[(google, "443")]
    assert got[(google, "9999")].startswith("CHECK port"), got[(google, "9999")]
    assert got[("79.127.216.89", "443")] == "FAIL ioc", got[("79.127.216.89", "443")]
    assert got[("192.168.1.50", "445")] == "FAIL lan attempt", got[("192.168.1.50", "445")]
    assert got[("192.168.1.210", "52345")] == "A 192.168.1.210", got[("192.168.1.210", "52345")]
    assert got[("185.199.108.153", "443")] == "CHECK", got[("185.199.108.153", "443")]
    assert not [k for k in got if k[0] == "1.1.1.1"], "a line from another device was kept"
    print(f"all {len(got)} verdicts as expected; another device's line dropped")

main()
