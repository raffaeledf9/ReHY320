# 16 Probation tooling: findings

Researched 2026-10-19 for ticket [16](../decisions/16-probation-tooling.md), using the router facts in [06](../decisions/06-router-facts.md) and the earlier verified data in [02b-planning-facts-data.json](02b-planning-facts-data.json) (`router` section) and [02a-feasibility-data.json](02a-feasibility-data.json) (`malware` section, IOC list). Web only. Nothing was downloaded, installed or run, and no device, router or network was touched. The two scripts below are specifications: **they have not been run**.

Confidence marks: **high** means read in source code or official docs; **medium** means one first-party statement, source code from a sister tree, or a strong inference from source; **low** means anecdote or my own inference.

## Short answer

- **What the router logs.** With the firewall on and "Logged packets type" = **Accepted**, the router writes one line for the **first packet of every new connection** that a home or guest device opens through it. A line holds the source and destination IPv4 address, protocol and ports. It has no host names, no byte counts and no device MAC. Guest SSIDs sit in the same `br0` bridge and the same 192.168.1.0/24 subnet as the home network, so **guest traffic is logged the same way**, and the projector is found by its IP address. (high, from ASUSWRT source)
- **How it reaches the PC.** The Remote Log Server setting starts BusyBox `syslogd -R <ip>[:port] -L`. Each line goes out as one **plain-text UDP datagram to port 514** (or the port you set), with no acknowledgement and no buffering. Lines sent while the PC is off are lost. (high, from source)
- **Receiver.** About 50 lines of Python standard library: a UDP socket bound to the PC's fixed home address on port 514. It keeps the projector's lines and the router's own event lines, and writes only an hourly count of everyone else's lines (proof the feed was alive, without storing the household's browsing). A second thread resolves the expected host names every 10 minutes. (Section 5)
- **Firewall rule.** One inbound Allow rule: UDP, local port 514, local address = the PC's address, remote address = 192.168.1.1, program = the base `python.exe`, profile = the one the home Wi-Fi already has (no need to switch it to Private; corrected in verification). Create it **before** the receiver's first run, so Windows never shows its "allow access" prompt. If you cancel that prompt, Windows creates Block rules, and Block always beats Allow. (high, Microsoft docs)
- **Fixed addresses.** Turn on LAN > DHCP Server > Enable Manual Assignment and bind **two** addresses: the PC (the remote log target) and the projector. Android 11 joins each Wi-Fi network with its own randomized MAC, stable until a factory reset, so bind the MAC the projector uses **on the guest SSID**. (high for stock Android; the vendor must have enabled randomization, so check on the unit)
- **Who owns an address.** The log carries no names, so ownership has four levels, from strong to weak: (A) the IP was returned for an expected host name by the router's own DNS during probation, or its reverse name is forward-confirmed under an expected domain such as `1e100.net` (Google) or `nflxvideo.net` (Netflix); (B) RDAP shows the expected company's own network; (C) a shared cloud (AWS, Akamai and similar) during a logged use of an app known to run there; (U) unexplained. Lookups use only DNS and RDAP and never connect to the destination. (Section 8)
- **Expected list for the cleaned system.** Android's connectivity check (`connectivitycheck.gstatic.com` tcp/80, `www.google.com` tcp/443 and tcp/80, `play.googleapis.com` tcp/80) and NTP (`time.android.com` udp/123, every 24 h), unless the vendor overrode them; check this on the unit. FLauncher, AirPlay Server (mirroring stays on the LAN) and Material Files are expected to add nothing during probation. Netflix, if installed later, adds Netflix's seven published domains plus AWS. (Section 9)
- **Pass after 7 days:** zero IOC hits, zero unexplained destinations, nothing but the Android baseline while idle, no DNS bypass (53/853 to the internet), no logged attempt to reach 192.168.1.0/24 (most such attempts are dropped at layer 2 without a log line, section 13), and an unbroken feed. **The 24-hour re-check** uses the same tools, the same guest SSID and the same IP. Its pass rule is "everything not in the last passing baseline is explained by the change". (Sections 10 and 11)
- **Router update to the last firmware first: yes, it changes none of the above.** The release notes mention no logging, firewall, DHCP or guest changes, and the 382-based source tree builds the same logging rules and the same syslogd command. Do it **before** probation: from 380 it is a manual upload, and an update mid-probation would interrupt the feed. Save the settings to a file first and check them again after. (Section 12)

## 1 What the router logs

**The mechanism (high).** ASUSWRT turns the GUI choice `fw_log_x` into iptables targets. Merlin's legacy tree shares this code with stock 380, and the 382-based tree has the same code (section 12):

- `if (nvram_match("fw_log_x", "accept") || nvram_match("fw_log_x", "both")) strcpy(logaccept, "logaccept");`, and the same for `drop` with `logdrop`.
- The `logaccept` chain logs only the first packet of a connection, then accepts it: `-A logaccept -m state --state NEW -j LOG --log-prefix "ACCEPT " --log-tcp-sequence --log-tcp-options --log-ip-options`.
- Every new connection from the LAN bridge goes through that chain: `-A FORWARD -i br0 -j logaccept` (`lan_if` is `br0`).
- Sources: [legacy firewall.c](https://raw.githubusercontent.com/RMerl/asuswrt-merlin/master/release/src/router/rc/firewall.c), [382.1 firewall.c](https://raw.githubusercontent.com/RMerl/asuswrt-merlin.ng/382.1/release/src/router/rc/firewall.c).
- The GUI choices are Dropped / Accepted / Both (manual p. 68, verified in [02b](02b-planning-facts-data.json); the user saw the same three). The stored default `fw_log_x` is `none`, meaning no logging. manual p. 68 (router-specific source removed), [defaults.c 382.1](https://raw.githubusercontent.com/RMerl/asuswrt-merlin.ng/382.1/release/src/router/shared/defaults.c)

**Guest traffic is included (high).**
- `start_lan()` adds every enabled guest interface (`wlX.Y`) to the LAN bridge with `brctl addif`. [lan.c](https://raw.githubusercontent.com/RMerl/asuswrt-merlin/master/release/src/router/rc/lan.c)
- "Access Intranet = Disable" adds only ebtables rules (`ebtables -A FORWARD -i <guest_if> -j DROP` and the matching `-o` rule, plus a `broute` rule for TCP to the LAN subnet). Internet-bound traffic still enters the router's IP layer from `br0` and hits `-A FORWARD -i br0 -j logaccept`. [lan.c](https://raw.githubusercontent.com/RMerl/asuswrt-merlin/master/release/src/router/rc/lan.c)
- Guests share the main subnet, verified in 02b. [SNBForums 31447](https://www.snbforums.com/threads/how-do-i-isolate-clients-on-guest-wifi.31447/)

**The source address is the projector's own (high).** The FORWARD hook runs before POST_ROUTING, where masquerading (source NAT) happens. So `SRC=` is the projector's 192.168.1.x address, not the router's public one. [netfilter hacking HOWTO §3](https://www.netfilter.org/documentation/HOWTO/netfilter-hacking-HOWTO-3.html)

**What one line contains (high for the fields, medium for the exact layout).**
- The kernel LOG target prints, in this order: the prefix, `IN=` and `OUT=`, optionally `PHYSIN=`/`PHYSOUT=` (bridge), `SRC= DST= LEN= TOS= PREC= TTL= ID=`, and the fragment flags.
- Then, per protocol:
  - TCP: `PROTO=TCP SPT= DPT=`, `SEQ= ACK=` (because of `--log-tcp-sequence`), `WINDOW= RES=`, the flags, `URGP=`, then the options.
  - UDP: `PROTO=UDP SPT= DPT= LEN=`.
  - ICMP: `PROTO=ICMP TYPE= CODE=`.
- **`MAC=` is printed only on the input path (`if (in && !out)`), so forwarded lines never carry the device's MAC.** That is why the projector needs a fixed IP.
- Source: [ipt_LOG.c, Linux 2.6.36](https://raw.githubusercontent.com/torvalds/linux/v2.6.36/net/ipv4/netfilter/ipt_LOG.c). A router's 2016 boot log shows `Linux version 2.6.36.4brcmarm` and BusyBox v1.17.4, so this kernel version applies to this model ([LKML post](https://lkml.iu.edu/hypermail/linux/kernel/2003.3/00593.html)). Newer kernels print `MAC=` whenever there is an input device, forwarded packets included ([nf_log_ipv4.c, Linux 4.19](https://raw.githubusercontent.com/torvalds/linux/v4.19/net/ipv4/netfilter/nf_log_ipv4.c)), so this holds only for this kernel line.
- BusyBox `klogd` hands each kernel line to syslog under the tag `kernel`. [klogd.c](https://raw.githubusercontent.com/RMerl/asuswrt-merlin/master/release/src/router/busybox/sysklogd/klogd.c)
- A projector line should therefore look roughly like this (assembled from the sources, not observed; `<wan>` is the router's WAN interface name, unknown):

```
<PRI>Oct 20 10:00:01 kernel: ACCEPT IN=br0 OUT=<wan> SRC=192.168.1.200 DST=203.0.113.7 LEN=60 TOS=0x00 PREC=0x00 TTL=63 ID=4242 DF PROTO=TCP SPT=40312 DPT=443 SEQ=... ACK=0 WINDOW=65535 RES=0x00 SYN URGP=0 OPT (...)
```

**Accepted or Both.**
- Choose **Accepted**. "Both" adds `DROP` lines, mostly unsolicited internet traffic hitting the router's WAN side (`-A INPUT -j logdrop`), which never names the projector. Inbound traffic is addressed to the router's public IP because there are no port forwards. [firewall.c](https://raw.githubusercontent.com/RMerl/asuswrt-merlin/master/release/src/router/rc/firewall.c)
- Use "Both" only if a Network Services Filter is later used as a kill switch, so blocked attempts show up (low: inference).

**Firewall switch.**
- In the legacy source the logging rules do not depend on `fw_enable_x`; only the FORWARD default policy and the DoS rules do (medium: read from source, GUI behaviour not checked).
- Turn the firewall on anyway, as decided in 06, then confirm that lines arrive.

**The router's log level does not block these lines (high).**
- Default `log_level` is 7 ("< LOG_INFO") and `console_loglevel` is 5. [defaults.c 382.1](https://raw.githubusercontent.com/RMerl/asuswrt-merlin.ng/382.1/release/src/router/shared/defaults.c)
- BusyBox syslogd sends every message to the remote host *before*, and independently of, its `-l` level filter, which applies only to the local copy. [syslogd.c](https://raw.githubusercontent.com/RMerl/asuswrt-merlin/master/release/src/router/busybox/sysklogd/syslogd.c) (added in verification)
- iptables LOG lines come in at warning level anyway: ASUSWRT's iptables sets `#define LOG_DEFAULT_LEVEL LOG_WARNING` (4) when a rule gives no `--log-level` ([libipt_LOG.c](https://raw.githubusercontent.com/RMerl/asuswrt-merlin/master/release/src/router/iptables/extensions/libipt_LOG.c)); the kernel's fallback in `ipt_LOG.c` is 5 (notice). Either way they are under the local cut-off too. `<PRI>` in the sample line may also show the "user" facility, because klogd notes that the C library may map LOG_KERN to LOG_USER. [ipt_LOG.c](https://raw.githubusercontent.com/torvalds/linux/v2.6.36/net/ipv4/netfilter/ipt_LOG.c), [klogd.c](https://raw.githubusercontent.com/RMerl/asuswrt-merlin/master/release/src/router/busybox/sysklogd/klogd.c)
- If Administration > System shows a "Log only messages more urgent than" field, leave it at its default.

## 2 How the Remote Log Server sends it

- **Command line (high).** If `log_ipaddr` is set, `start_syslogd` adds `-R <ip>` (or `<ip>:<log_port>` when `log_port` is non-zero) and `-L`, so the router also keeps logging locally. [services.c (legacy)](https://raw.githubusercontent.com/RMerl/asuswrt-merlin/master/release/src/router/rc/services.c), [services.c 382.1](https://raw.githubusercontent.com/RMerl/asuswrt-merlin.ng/382.1/release/src/router/rc/services.c)
- **Default port (high).** The default `log_port` is `514` ([defaults.c 382.1](https://raw.githubusercontent.com/RMerl/asuswrt-merlin.ng/382.1/release/src/router/shared/defaults.c)), and ASUS's own FAQ says "Remote log server port is [514] in default setting" ([ASUS FAQ 1044954](https://www.asus.com/support/faq/1044954/)). Whether stock 380/382 shows a port field at all is not documented. Either way the port is 514.
- **Protocol and format (high).** From BusyBox `syslogd.c` in the ASUSWRT tree ([syslogd.c](https://raw.githubusercontent.com/RMerl/asuswrt-merlin/master/release/src/router/busybox/sysklogd/syslogd.c)):
  - The usage text: "-R HOST[:PORT] Log to HOST:PORT (default PORT:514)".
  - The socket: `xsocket(..., SOCK_DGRAM, 0)`, so UDP.
  - The packet is the message exactly as the local program handed it over ("We are not modifying log messages in any way before send"), plus a newline. BusyBox adds no hostname or timestamp of its own. Whatever `<PRI>` and time the router's C library put in front stays.
  - So the receiver should stamp each line with the PC's clock.
- **Failure behaviour (high).** Send errors are ignored, except three that make syslogd reopen the socket. Nothing is queued, so **a PC that sleeps or reboots means lost lines**. The router's local copy is small (`log_size` 256 KB by default) and is overwritten quickly once every household connection is logged. [syslogd.c](https://raw.githubusercontent.com/RMerl/asuswrt-merlin/master/release/src/router/busybox/sysklogd/syslogd.c), [defaults.c 382.1](https://raw.githubusercontent.com/RMerl/asuswrt-merlin.ng/382.1/release/src/router/shared/defaults.c)
- **DHCP lines too (low).** In the 382-based Merlin tree dnsmasq writes `quiet-dhcp` only when `dhcpd_querylog` is `0`, and the default is `1`. But `dhcpd_querylog` sits in that file's "Merlin-specific settings" block, so stock firmware may handle this differently (corrected in verification). DHCP lease lines (MAC, IP, host name) may appear in the same feed. Useful as a cross-check, but don't rely on them. [services.c 382.1](https://raw.githubusercontent.com/RMerl/asuswrt-merlin.ng/382.1/release/src/router/rc/services.c), [defaults.c 382.1](https://raw.githubusercontent.com/RMerl/asuswrt-merlin.ng/382.1/release/src/router/shared/defaults.c), [dnsmasq man page](https://thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html)

## 3 Router settings for probation

To set once, after the firmware update (section 12) and before the projector's first join:

1. Firewall > General: Enable Firewall = Yes; Logged packets type = **Accepted**. manual p. 68 (router-specific source removed)
2. Administration > System: Remote Log Server = the PC's fixed address (section 4). If a port field is shown, leave it at 514. [ASUS FAQ 1044954](https://www.asus.com/support/faq/1044954/)
3. Guest Network: enable **one** guest SSID on one band. Set Access Intranet = **Disable** and the access time to unlimited. Only the projector joins it. 06 confirms the "Access Intranet" option is present. manual p. 27 (router-specific source removed)
4. LAN > DHCP Server: Enable Manual Assignment = Yes, with the two bindings from section 4.
5. Keep IPv6 disabled. With IPv6 on, the projector could use v6 paths this IPv4 check does not cover (02b gap).
6. The projector has only the guest SSID saved, so it cannot quietly join another network.

## 4 Fixed addresses (DHCP Manual Assignment)

- **How (high).** Advanced Settings > LAN > DHCP server > Enable Manual Assignment = Yes. Pick the device from the drop-down or type its MAC, enter the IP, click +, then Apply. The IP "needs to be in the IP pool of your DHCP server". The device itself stays on "obtain an IP automatically". [ASUS FAQ 1000906](https://www.asus.com/support/faq/1000906/) The home router takes up to 32 entries. manual p. 53 (router-specific source removed)
- **The PC.** Bind its MAC to, for example, 192.168.1.10. The Remote Log Server field takes an IP, and the receiver and the firewall rule bind to that IP.
- **The projector, and which MAC to bind (high).**
  - Android 10 and 11 use a randomized MAC by default. It is persistent per network: generated from the network's SSID and security type, it "remains the same until a factory reset" and does not change if you forget and re-add the network. Turning randomization off for a network makes Android use the factory MAC. [AOSP: MAC randomization behavior](https://source.android.com/docs/core/connect/wifi-mac-randomization-behavior)
  - This needs the device maker to set `config_wifi_connected_mac_randomization_supported` and the Wi-Fi HAL to support it. On a cheap vendor build it may be off, and then the projector uses its factory MAC on every network. The Wi-Fi network's privacy setting on the unit shows which. [AOSP: MAC randomization](https://source.android.com/docs/core/connect/wifi-mac-randomization) (added in verification)
  - So the projector shows the router one MAC on the guest SSID and a different one on the home SSID.
  - Bind the **guest-SSID MAC** to, for example, 192.168.1.200. Later, if the home network should be filtered too, add a second entry (e.g. 192.168.1.201) for the home-SSID MAC.
  - Any factory reset or reflash of the projector changes these MACs. Update the bindings afterwards.
- **First join.** The first lease may arrive before the binding exists (low: depends on how the MAC is learned). Two options:
  - Set "Privacy: use device MAC" for the guest SSID on the projector, and bind the factory MAC read earlier over USB.
  - Or let it join once, bind the MAC shown in the router's client list, and reconnect. Either way, the receiver runs **before** the first join. The very first minutes online are the most telling, and the router's DHCP lines (section 2) link that first lease to the MAC.

## 5 Receiver on the PC (Python standard library)

It runs with the **base** interpreter, not a venv. On Windows, a venv's `python.exe` is a redirector that launches the original interpreter from its home directory ([venv docs](https://docs.python.org/3/library/venv.html), [CPython venvlauncher.c](https://chromium.googlesource.com/external/github.com/python/cpython/+/d99f3fc474f34db4176ac67611efec18bde66c7e/PC/venvlauncher.c)). The process that opens the socket, which the firewall rule must name, is therefore the base `python.exe`. The script prints that path at start.

```python
"""HY320 probation: receive the ASUS router's syslog on UDP 514 (not run yet).
Keeps lines about the projector and the router's own non-firewall lines,
writes an hourly count of all lines, and resolves expected names every 10 min.
Usage: python receiver.py <pc_ip> <projector_ip> <expected.txt> <out_dir>"""
import datetime, pathlib, socket, sys, threading, time

PC_IP, PROJ_IP, NAMES, OUT = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3]), pathlib.Path(sys.argv[4])
ROUTER_IP = "192.168.1.1"
OUT.mkdir(parents=True, exist_ok=True)

def append(kind, text):
    t = datetime.datetime.now().astimezone()      # PC clock, with UTC offset (DST-safe)
    # ponytail: reopens the file per line; fine at a few lines per second
    with open(OUT / f"{kind}-{t:%Y-%m-%d}.tsv", "a", encoding="utf-8") as f:
        f.write(f"{t.isoformat(timespec='seconds')}\t{text}\n")

def resolver():                                  # what the router's DNS answers for expected names
    while True:
        for line in NAMES.read_text(encoding="utf-8").splitlines():
            name = line.split()[0] if line.strip() else ""
            if name and name[0] not in "#.":    # skip comments and .suffix entries
                try:
                    ips = socket.gethostbyname_ex(name)[2]
                except OSError:
                    ips = []
                append("dns", f"{name}\t{','.join(ips)}")
        time.sleep(600)

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 1 << 20)
sock.bind((PC_IP, 514))                          # fails loudly if the PC lost its fixed address
print(f"listening {PC_IP}:514/udp, interpreter {getattr(sys, '_base_executable', sys.executable)}", flush=True)
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
    if "SRC" not in f or PROJ_IP in (f.get("SRC"), f.get("DST")):
        append("log", msg)
```

Notes:
- **Socket calls.** They are the documented stdlib ones: `bind` and `recvfrom` on a `SOCK_DGRAM` socket, and `gethostbyname_ex` for IPv4 lookups. IPv6 is off. [Python socket docs](https://docs.python.org/3/library/socket.html)
- **Buffer size.** Windows reports `WSAEMSGSIZE` and drops the rest of a datagram larger than the buffer, which Python raises as an error. 65535 bytes avoids that. [Winsock recvfrom](https://learn.microsoft.com/en-us/windows/win32/api/winsock2/nf-winsock2-recvfrom)
- **Errors.** `recvfrom` can also fail with other Winsock errors (for example `WSAENETDOWN`, or `WSAECONNRESET` on a UDP socket). The loop writes an `#error` line and keeps listening instead of exiting (added in verification). [Winsock recvfrom](https://learn.microsoft.com/en-us/windows/win32/api/winsock2/nf-winsock2-recvfrom)
- **Exact match on SRC/DST.** A substring test would let `.20` match `.200`.
- **Port 514 and admin rights.** I found no official Microsoft statement that ports below 1024 need admin rights on Windows. A Cygwin/OpenSSH maintainer says there is no such restriction ([openssh-unix-dev, 2023](https://lists.mindrot.org/pipermail/openssh-unix-dev/2023-November/041076.html)) (low). If the bind fails, the error says why.
- **Privacy.** The household's own connection lines are counted, never stored. The DHCP lines that are kept include other devices' MACs and names. Keep the output folder out of any git repository, and delete it once probation and the re-checks are done.

## 6 Windows Defender Firewall rule

Run from an elevated PowerShell (Run as administrator). The `-Program` path is what the receiver printed. `-Profile` is what `Get-NetConnectionProfile` shows for the home Wi-Fi (Public in this example):

```powershell
New-NetFirewallRule -DisplayName "HY320 probation syslog" -Direction Inbound -Action Allow `
  -Protocol UDP -LocalPort 514 -LocalAddress 192.168.1.10 -RemoteAddress 192.168.1.1 `
  -Program "C:\Path\To\python.exe" -Profile Public `
  -Description "ASUS router syslog for HY320 probation and re-checks"
```

- **Parameters (high).** `-RemoteAddress` and `-LocalAddress` take single IPv4 addresses. `-Program` is "the full path to an application file". `-Profile` takes Any, Domain, Private or Public, and a rule "is active ... only when the specified profile is currently active". [New-NetFirewallRule](https://learn.microsoft.com/en-us/powershell/module/netsecurity/new-netfirewallrule)
- **Prompt and Block rules (high).**
  - The rules: "Explicit block rules take precedence over any conflicting allow rules". If no allow rule exists when an app first listens, Windows asks. Answering "No" or cancelling the prompt creates Block rules, "one each for TCP and UDP", and those keep blocking until deleted. [Windows Firewall rules](https://learn.microsoft.com/en-us/windows/security/operating-system-security/network-security/windows-firewall/rules)
  - So create the rule first.
  - Check that there is no old Block rule for Python: `Get-NetFirewallApplicationFilter | Where-Object Program -like '*python*' | Get-NetFirewallRule | Where-Object { $_.Direction -eq 'Inbound' -and $_.Action -eq 'Block' }`.
  - That a program-scoped Allow rule suppresses the prompt is my reading of "no active application or administrator-defined allow rule" (medium).
- **Network profile (high; corrected in verification).** Windows 11 sets a new network to Public by default, and Microsoft marks Public as recommended even at home; Private makes the PC discoverable to every device on the network. So don't switch the home Wi-Fi to Private for this. Give the rule the profile the network already has (`Get-NetConnectionProfile`), or the rule stays inactive. The rule is narrow anyway: one port, one program, one sender. [Microsoft support](https://support.microsoft.com/en-us/windows/experience/connectivity-networking/essential-network-settings-and-tasks-in-windows), [New-NetFirewallRule](https://learn.microsoft.com/en-us/powershell/module/netsecurity/new-netfirewallrule)
- **"Block all incoming connections".** If this box is ticked for that profile in Windows Security > Firewall & network protection, the firewall ignores the allowed-apps list, and the rule does nothing. Check that it is clear. [Microsoft support: Firewall and network protection](https://support.microsoft.com/windows/windows-ec0844f7-aebd-0583-67fe-601ecf5d774f)
- **Between checks.** `Disable-NetFirewallRule -DisplayName "HY320 probation syslog"`, and `Enable-...` again for each 24-hour re-check. The guest SSID cannot reach the PC anyway, because of Access Intranet = Disable.

## 7 Keeping the PC listening for 7 days

- **Sleep (high).** `powercfg /change standby-timeout-ac 0` and `powercfg /change hibernate-timeout-ac 0` (values are in minutes). Restore them afterwards. [powercfg options](https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/powercfg-command-line-options)
- **Updates (high).** Settings > Windows Update > pause until the end of probation. Pauses last up to 35 days, and while paused, "updates that might require a restart" are not installed. [Pause updates in Windows](https://support.microsoft.com/en-us/windows/deployment/updates-lifecycle/pause-updates-in-windows)
- **Restart after reboot (optional, high for the syntax).** `schtasks /create /tn "HY320 syslog" /sc onstart /delay 0002:00 /ru System /tr "<python.exe> <receiver.py> <args>"`. The `/tr` path is limited to 262 characters. [schtasks create](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/schtasks-create)
  - **Remove the 3-day stop (added in verification, high).** By default, Task Scheduler stops a task 72 hours after it starts, which would kill a receiver started by a reboot halfway through probation ([TaskSettings](https://learn.microsoft.com/en-us/windows/win32/taskschd/tasksettings), [ExecutionTimeLimit](https://learn.microsoft.com/en-us/windows/win32/taskschd/tasksettings-executiontimelimit): "PT0S will enable the task to run indefinitely"). After creating it, run `Set-ScheduledTask -TaskName "HY320 syslog" -Settings (New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries)`. The two battery switches matter only on a laptop. [New-ScheduledTaskSettingsSet](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtasksettingsset) That a zero TimeSpan is stored as PT0S is my reading (medium); `schtasks /query /tn "HY320 syslog" /v` should then no longer show 72:00 as the stop time.
  - Whether Wi-Fi is up before anyone logs in depends on the Wi-Fi profile (low). The hourly `#count` lines show any gap either way.
- **Clock.** The receiver stamps lines with the PC's clock. A wrong clock only shifts the diary match.

## 8 Matching each destination to its owner

The router log has no host names, and the projector's DNS questions go to the router, which never shows them (INPUT, not FORWARD). Owners are therefore found after the fact, using DNS and RDAP only.

1. **IOC first.** Check against the IP list in 02a, plus the 02a IOC domains, resolved by the analyzer on each run. Cloud IPs get reassigned over time, so a hit means "offline now, then investigate", not proof (low: inference). A copy of the 02a list in file form is under section 9.
2. **(A) Name match, strong.** The IP appears in the `dns-*.tsv` answers for an expected exact name. The router's dnsmasq "answers them from a small, local, cache or forwards them" ([dnsmasq man page](https://thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html)), and ASUS sets `cache-size=1500` ([services.c 382.1](https://raw.githubusercontent.com/RMerl/asuswrt-merlin.ng/382.1/release/src/router/rc/services.c)). The PC, asking the same router, therefore tends to get the same answers the projector got (medium: inference). The PC must use the router as its DNS server; check with `Get-DnsClientServerAddress`.
3. **(A) Forward-confirmed reverse name, strong.** `gethostbyaddr(ip)` gives a name, and resolving that name returns the same IP again. Only the domain's owner controls the forward zone. Example: "1e100.net is a Google-owned domain name used to identify the servers in our network" ([Google](https://support.google.com/faqs/answer/174717)).
4. **(B) Owner, medium.** RDAP. Pick the registry from IANA's bootstrap file `https://data.iana.org/rdap/ipv4.json`: longest matching prefix, HTTPS first ([RFC 9224](https://www.rfc-editor.org/rfc/rfc9224.html), [IANA file](https://data.iana.org/rdap/ipv4.json)). Then query `<base>ip/<address>`. The answer's IP network object has `name`, `country`, `startAddress`/`endAddress` and `entities`, with names in vCard `fn`/`org` ([RFC 9083](https://www.rfc-editor.org/rfc/rfc9083.html)). For the announcing AS, RIPEstat `https://stat.ripe.net/data/network-info/data.json?resource=<ip>` returns `asns` and `prefix` ([docs](https://stat.ripe.net/docs/data-api/api-endpoints/network-info)), and `as-overview` returns the AS `holder` ([docs](https://stat.ripe.net/docs/data-api/api-endpoints/as-overview)).
5. **(C) Shared cloud, weak.** AWS, Akamai, Cloudflare and similar host anyone. Accept such an address only on tcp/443, inside a diary window when an app that the vendor says runs there was in use. Example: Netflix runs all its customer-facing services on AWS, while video comes from Open Connect (section 9) (high, Netflix's own statement; source replaced in verification). [Netflix: Completing the cloud migration](https://about.netflix.com/en/news/completing-the-netflix-cloud-migration)
6. **(U)** Everything else. Unexplained.

Analyzer sketch (not run). It never connects to a destination:

```python
"""HY320 probation: list the projector's destinations and how each is explained (not run yet).
Usage: python analyze.py <out_dir> <projector_ip> <expected.txt> <ioc.txt> [from] [to]
from/to: ISO times, e.g. 2026-10-21T08:00 (local). Writes destinations.csv."""
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

entries = lambda p: [l.split() for l in p.read_text(encoding="utf-8").splitlines() if l.strip() and l[0] != "#"]
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
        elif lan and ip != "192.168.1.1":            # router-bound lines are not expected at all (INPUT is not logged)
            v = "FAIL lan attempt"
        elif hit:
            v = ("A " if any(pp in ports.get(h, ()) for h in hit) else "CHECK port ") + ",".join(hit)
        else:
            v = "CHECK"                                # B, C or U: decided by a person, with the diary
        w.writerow([ip, proto, port, first, last, n, rname + ("" if ok or not rname else " (unconfirmed)"),
                    rdap(ip) if v == "CHECK" and not lan else "", v])
```

- New connections from `br0` to the router itself hit a plain `ACCEPT` in INPUT, not `logaccept`. So the projector's DNS and DHCP traffic to 192.168.1.1 is not logged, and a 192.168.1.x destination can only mean another home device (high, from source). [firewall.c](https://raw.githubusercontent.com/RMerl/asuswrt-merlin/master/release/src/router/rc/firewall.c)
- `gethostbyaddr`, `gethostbyname_ex`, `herror` and `gaierror` are all `OSError`s in Python 3. [socket docs](https://docs.python.org/3/library/socket.html)
- A vCard `org` with several parts is a JSON array, not a string, so the analyzer turns each value into text with `str()` before collecting it (fixed in verification; before, one such answer made the whole lookup fail). [RFC 7095 §3.3.1.3](https://www.rfc-editor.org/rfc/rfc7095.html)
- RDAP volume is small, a few dozen addresses. If a registry rate-limits, rerun later.

**Optional, for names an app hides (low: inference, not tested).** Host names an app will contact are often plain strings in its APK. A stdlib `zipfile` plus a regex over `classes*.dex` can list the names under an app's documented domains, to add to `expected.txt`. This reads the APK as data on the PC and runs nothing. Obfuscated or built-at-runtime names are missed.

## 9 The expected-destinations list

`expected.txt`: one entry per line, `name_or_.suffix  proto/port[,proto/port]  component`. Exact names are resolved by the receiver every 10 minutes; `.suffix` entries match only forward-confirmed reverse names.

| Entry | Port | Component, when | Source |
|---|---|---|---|
| `connectivitycheck.gstatic.com` | tcp/80 | Android 11 connectivity check, HTTP probe. Runs on each Wi-Fi connect and on re-evaluation | AOSP NetworkStack `default_captive_portal_http_url` = `http://connectivitycheck.gstatic.com/generate_204` (high). [config.xml](https://android.googlesource.com/platform/packages/modules/NetworkStack/+/refs/heads/android11-release/res/values/config.xml) |
| `www.google.com` | tcp/443, tcp/80 | HTTPS probe `https://www.google.com/generate_204`; fallback `http://www.google.com/gen_204` | same (high) |
| `play.googleapis.com` | tcp/80 | Fallback probe `http://play.googleapis.com/generate_204` | same (high) |
| `time.android.com` | udp/123 | Network time. Polled every 24 h (`config_ntpPollingInterval` 86400000 ms); after a failure, retried every 60 s up to 3 times | [framework config.xml](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android11-release/core/res/res/values/config.xml), [SntpClient `NTP_PORT = 123`](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android11-release/core/java/android/net/SntpClient.java) (high) |
| `.1e100.net` | tcp/80, tcp/443, udp/123 | Google servers behind the four names above, for when the IP rotated between resolver runs | [Google](https://support.google.com/faqs/answer/174717) (high) |
| `.google.com` | udp/123 | Google's public time servers: `time.android.com` has pointed at 216.239.35.0/4/8/12, and 216.239.35.0 reverses to `time1.google.com`, not to 1e100.net (added in verification) | [Netify: time.android.com](https://www.netify.ai/resources/hostnames/time.android.com), [Netify: 216.239.35.0](https://www.netify.ai/resources/ips/216.239.35.0) (medium; third-party data up to 30 days old) |
| none | | FLauncher: the release manifest has no INTERNET permission | [13](13-launcher-and-file-manager.md) (medium) |
| none during probation | | AirPlay Server: mirroring stays on the LAN, and only AirPlay video fetches from the video's own host. AirPlay is tested only after the move to the home Wi-Fi | [14](14-airplay-server.md) (medium) |
| none | | Material Files: has INTERNET, but uses it only for a server you add | [13](13-launcher-and-file-manager.md) (high) |
| only if used: its update config on GitHub, its wallpaper providers, opt-in usage reports | | Projectivy, the fallback launcher | [13](13-launcher-and-file-manager.md) (high) |
| `.netflix.com .nflxext.com .nflximg.net .nflximg.com .nflxsearch.net .nflxso.net .nflxvideo.net` (one line each in the file) | tcp/443 | Netflix app, after its install and inside its 24-hour re-check. Video comes from Open Connect appliances (AS2906 at exchange points; AS40027 for appliances inside ISPs, which may sit in the ISP's own address space). The control plane runs on AWS, so expect level C there | [Netflix domain list](https://openconnect.netflix.com/mobiledeliverydomains.txt) (high), [APNIC/Netflix](https://blog.apnic.net/2018/06/20/netflix-content-distribution-through-open-connect/) (medium), [Open Connect](https://openconnect.netflix.com/en/) (that ISP-embedded appliances use the ISP's own addresses is unverified), [Netflix on AWS](https://about.netflix.com/en/news/completing-the-netflix-cloud-migration) (high) |
| nothing else | | All kept vendor parts (keystone, HDMI and so on): any vendor domain or Chinese cloud address is U at best | [01](../decisions/01-charting-decisions.md) |

Rules that go with the list:
- **Vendor overrides replace the Android defaults.** Read them on the cleaned unit: `settings get global captive_portal_http_url`, `captive_portal_https_url`, `captive_portal_fallback_url`, `captive_portal_other_fallback_urls` and `ntp_server`. The framework uses `Settings.Global` values over its built-in defaults (high). [config.xml comment](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android11-release/core/res/res/values/config.xml), [NtpTrustedTime](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android11-release/core/java/android/util/NtpTrustedTime.java)
  - But `settings get` does not show everything (added in verification, high). A vendor resource overlay setting `config_captive_portal_http_url` (and its https and fallback siblings) beats `Settings.Global` in NetworkMonitor, and an overlay can also replace the default `config_ntpServer`. Neither shows up in `settings`. So an empty answer does not prove the Google defaults. The log decides: unexpected probe or NTP hosts come out as CHECK. [NetworkMonitor.java](https://android.googlesource.com/platform/packages/modules/NetworkStack/+/refs/heads/android11-release/src/com/android/server/connectivity/NetworkMonitor.java), [NetworkStack config.xml](https://android.googlesource.com/platform/packages/modules/NetworkStack/+/refs/heads/android11-release/res/values/config.xml)
- **DNS goes to the router and never shows.** Android's default Private DNS mode "automatically upgrade[s] to DNS over TLS if a network's DNS server supports it" ([Android blog](https://android-developers.googleblog.com/2018/04/dns-over-tls-support-in-android-p.html)). Those probes go to the router too. **Any tcp/udp 53 or tcp 853 ([RFC 7858](https://www.rfc-editor.org/rfc/rfc7858)) to an internet address is therefore a DNS bypass and must be explained.**
- **The IOC file.** `ioc.txt`, copied from the 02a `malware` section and its sources ([Kavan00](https://github.com/Kavan00/Android-Projector-C2-Malware), [HY350 domains](https://github.com/maximilian-sh/hy350max-badbox-removal/blob/main/iocs/domains.txt), [HY350 IPs](https://github.com/maximilian-sh/hy350max-badbox-removal/blob/main/iocs/ips.txt)):
  - Domains: `store-api.aodintech.com cdn-store.aodintech.com event-api.aodintech.com pb-api.aodintech.com ota-api.aodintech.com api.pixelpioneerss.com sta.smartinnovate.net bur.thedynamicleap.com ota.triplesai.com otaapi.triplesai.com usmyip.kkoip.com kkoip.com soax.com shortx.srafx.com o.fecebbbk.xyz sd002.jaguar-distributor.syslogcollector.com balancer.api.net2fast.com www.sda-1.xyz api.ipdatacloud.com euads-o.api.leiniao.com int.vaicore.site int.dewrain.life int.akisinn.info hotack.com ip4exordir.shop zeromedia.cloud`.
  - IPs: `79.127.216.89 107.151.220.86 207.166.169.133 89.222.109.18 103.124.165.222 139.199.190.220 111.230.36.129 44.205.227.254 64.32.27.247 128.12.122.35`.
  - Added in verification from the cited HY350 lists: `hotack.com ip4exordir.shop zeromedia.cloud`, `64.32.27.247` (a past address of `api.pixelpioneerss.com`; the name may no longer resolve, so the analyzer's lookup would miss it) and `128.12.122.35` ("C2 geolocation data"). The same domain list also names analytics and vendor hosts (`statsigapi.net app-measurement.com hmma.baidu.com dxp.baidu.com zeasn.tv`) and marks `server.mphotool.com` as functional. They stay off `ioc.txt` because some are shared with ordinary apps, and on the cleaned unit they would come out as U anyway.
  - Ports tcp/12341, tcp/12342 and udp/16000 are dispatcher and proxy signatures. They are not on the expected list, so they come out as CHECK.
  - 02a calls 103.124.165.222 doubtful, and two of the domains are unconfirmed. Blocking costs nothing, so they stay.

## 10 Pass and fail: the 7-day probation

**Before the projector first joins (all must hold, or probation has not started):**
1. The firmware update is done and the settings from section 3 are in place.
2. The receiver has been running for at least 10 minutes, and household `ACCEPT` lines and `#count` lines are arriving.
3. `dns-*.tsv` holds answers for every exact name.
4. The PC's sleep is off and Windows Update is paused.
5. The projector's guest-SSID binding is set, or the first-join procedure from section 4 is ready.

**Daily:** run the analyzer on the day's window. An `FAIL ioc` row means **offline now**: turn the guest SSID off. Investigate any `CHECK` row the same day, while the diary is fresh.

**Pass at day 7, all of:**
1. **Feed:** a `#count` line above 0 for every hour of the 7 days. A missing hour is a gap; add it to the end of probation.
2. **IOC:** zero hits.
3. **Every row explained** at level A or B, or C under the C rule. A CHECK row becomes explained only when a written reason with a source is added to `expected.txt`. That added line becomes part of the baseline.
4. **Idle:** in diary windows where the projector was on and nobody used an app, only the Android baseline (section 9, rows 1 to 6) appears, and nothing at level C.
5. **No DNS bypass:** no 53/853 to the internet. No ports outside the list. No `FAIL lan attempt` rows.
6. **Exposure (proposed, not from a source):** on and connected at least 12 h on each day, with at least one idle stretch of 8 h or more overnight; every kept feature used at least once; and a cold boot on at least one day, so boot-time traffic is seen.

**Fail:** any IOC hit, or any row still U at day 7. The projector goes back offline: guest SSID off, or the Parental Controls / Network Services Filter block from 02b. Keep the logs. After a fix, run a **full new 7-day probation** ([GLOSSARY: Probation](../../GLOSSARY.md)).

**Keep at pass:** `destinations.csv` plus `expected.txt` become the **baseline**.

## 11 The 24-hour re-check

The same tools, the same guest SSID, the same MAC and fixed IP. Persistent randomization keeps the guest-SSID MAC until a factory reset ([AOSP](https://source.android.com/docs/core/connect/wifi-mac-randomization-behavior)).

1. **Before:** enable the firewall rule, start the receiver, add the change's documented names to `expected.txt` (e.g. the Netflix row), and check that the feed is alive.
2. **Window:** 24 h from the moment the projector joins the guest SSID. Use the new app or feature at least 3 times, logged in the diary, with one idle stretch of 8 h or more.
3. **Run:** `analyze.py <out> <projector_ip> expected.txt ioc.txt <join time> <join + 24 h>`.
4. **Pass:** rules 1 to 5 from section 10 over the window, plus: every destination whose name or owner is not in the last baseline is explained by the change, and new level C rows appear only inside that app's diary windows.
5. **On pass:** the new CSV and list become the baseline, and the projector goes back to the home Wi-Fi. **On fail:** it stays off the home Wi-Fi. Undo the change (uninstall), then re-check again.

A router-only change, such as a firmware update, needs no projector re-check, but it does mean repeating the setup checks.

## 12 Updating the router to the last firmware first

- **Nothing in this design changes (medium).**
  - ASUS's notes for every 382 build list only security fixes, Wi-Fi stability, the OTA function, a privacy page and IPv6 bug fixes. There is nothing on logging, firewall, DHCP or guest networks (high that the notes say nothing more). ASUS support page (router-specific source removed)
  - The 382-based Merlin tree has the same `fw_log_x` → `logaccept` code, the same `-A FORWARD -i br0 -j logaccept`, and the same `start_syslogd` `-R`/`log_port` code as the 380-based legacy tree. [382.1 firewall.c](https://raw.githubusercontent.com/RMerl/asuswrt-merlin.ng/382.1/release/src/router/rc/firewall.c), [382.1 services.c](https://raw.githubusercontent.com/RMerl/asuswrt-merlin.ng/382.1/release/src/router/rc/services.c)
  - Medium, because this is Merlin's tree built on ASUS GPL code, not this model's own GPL drop.
- **Do it before probation.** It is worth doing for security alone (06, 02b). Doing it mid-probation means a reboot, a gap in the feed, and a changed system under observation.
- **Manual upload.** The notes say devices on firmware older than 3.0.0.4.382.52259 need a manual update; 380 is older. ASUS publishes an MD5 for the last firmware. Check the download with `Get-FileHash <file> -Algorithm MD5` (MD5 is weak, but it is what ASUS gives). ASUS support page (router-specific source removed), [Get-FileHash](https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/get-filehash)
- **Save the settings first** (Administration > Restore/Save/Upload Setting > Save setting, without ticking the box that strips the password). Afterwards re-check every item from 06: firewall, logging, Remote Log Server, Manual Assignment, the guest network with Access Intranet, IPv6 off, WPS. The notes do not say a reset is needed (high that they don't). [ASUS FAQ 1001376](https://www.asus.com/support/faq/1001376/)
- **Keep the saved file as a record; don't upload it after the update (added in verification).** The same ASUS FAQ says that after a firmware update "it is recommended to reset the ASUS wireless router to its factory default settings and then reconfigure the router", rather than import an old file. If the router misbehaves after the update, reset it and set the items from 06 by hand. That also clears any planted SSH key (02b gap). [ASUS FAQ 1001376](https://www.asus.com/support/faq/1001376/)
- **What might differ (low).** 382 may show a Remote Log Server port field (leave 514). Guest-to-guest isolation may differ between 380 and 382 (02b open question). That matters for AirPlay later, not for logging.

## 13 What this cannot see

- **Host names and DNS.** Questions to the router are invisible, so DNS tunnelling through the router's resolver would go unseen. Only removing components (Clean) covers that.
- **Volume and duration.** One line per new connection, no byte counts.
- **Inside the network.** Traffic between two clients of the same guest SSID never reaches iptables. Layer-2 attempts toward the LAN dropped by ebtables are not logged (there is no LOG target in those rules; [lan.c](https://raw.githubusercontent.com/RMerl/asuswrt-merlin/master/release/src/router/rc/lan.c)).
- **The router's own connections**, and anything the projector does over a network other than this guest SSID.
- **A compromised router.** Its logs could lie. 02b lists AyySSHush and WrtHug against EOL ASUS models, so the hardening and update from 06 come first.

## Can only be confirmed at home or on the unit

1. The first receiver run: the line layout really is as in section 1, and the WAN interface name. Whether a `PHYSIN=wlX.Y` field appears; if it does, it names the guest interface.
2. Whether stock 380/382 shows a Remote Log Server port field, and a "Log only messages more urgent than" field.
3. Whether DHCP lease lines arrive in the feed (`dhcpd_querylog`).
4. That "Access Intranet" (present, per 06) can be set to Disable on the guest SSID used.
5. The cleaned projector's `captive_portal_*` and `ntp_server` overrides, and its guest-SSID MAC.
6. Whether Windows still prompts for `python.exe` despite the program-scoped rule, and whether the home Wi-Fi keeps the profile the rule names.
7. That household background traffic really yields lines every hour, so the `#count` gap rule works overnight.

## Verification

Independent check on 2026-10-19, web only (WebSearch/WebFetch). I opened the cited sources and looked for contradicting ones. Nothing was installed or run against any device or network. The two Python blocks were only syntax-checked with `ast.parse` after the fixes below; they have still **not been run**. Every fix made in place above is marked "corrected in verification" or "added in verification".

**Router: what is logged**
1. `fw_log_x` = accept/both selects `logaccept`; that chain logs only `--state NEW` with prefix `ACCEPT `; `-A FORWARD -i br0 -j logaccept` is written outside any `fw_enable_x` test. **Confirmed** in both trees. The only FORWARD item gated by `fw_enable_x` is the default policy (DROP vs ACCEPT), and the DoS jumps are gated too. [legacy firewall.c](https://raw.githubusercontent.com/RMerl/asuswrt-merlin/master/release/src/router/rc/firewall.c), [382.1 firewall.c](https://raw.githubusercontent.com/RMerl/asuswrt-merlin.ng/382.1/release/src/router/rc/firewall.c)
2. GUI choices "None / Dropped / Accepted / Both". **Partly.** Manual p. 68 lists only Dropped / Accepted / Both, and so did the user; `none` is the stored default. Fixed in section 1. manual p. 68 (router-specific source removed), [defaults.c 382.1](https://raw.githubusercontent.com/RMerl/asuswrt-merlin.ng/382.1/release/src/router/shared/defaults.c)
3. Router-bound traffic from `br0` hits a plain `ACCEPT` in INPUT, so DNS and DHCP to 192.168.1.1 are never logged. **Confirmed** (`-A INPUT -i %s -m state --state NEW -j ACCEPT`, inside the `fw_enable_x` block; with the firewall off there is no INPUT logging either). [legacy firewall.c](https://raw.githubusercontent.com/RMerl/asuswrt-merlin/master/release/src/router/rc/firewall.c)
4. Enabled guest interfaces are added to `br0`; Access Intranet = Disable adds only ebtables DROP rules with no LOG target. **Confirmed.** [lan.c](https://raw.githubusercontent.com/RMerl/asuswrt-merlin/master/release/src/router/rc/lan.c)
5. `SRC=` is the projector's private address because FORWARD runs before POST_ROUTING (source NAT). **Confirmed.** [netfilter hacking HOWTO §3](https://www.netfilter.org/documentation/HOWTO/netfilter-hacking-HOWTO-3.html)
6. Field layout, and no `MAC=` on forwarded lines (`if (in && !out)`). **Confirmed** for Linux 2.6.36, and a router's 2016 boot log shows `2.6.36.4brcmarm`. Newer kernels (`if (in != NULL)`) print the MAC, so this rests on the kernel line. Note added in section 1. [ipt_LOG.c 2.6.36](https://raw.githubusercontent.com/torvalds/linux/v2.6.36/net/ipv4/netfilter/ipt_LOG.c), [LKML boot log](https://lkml.iu.edu/hypermail/linux/kernel/2003.3/00593.html), [nf_log_ipv4.c 4.19](https://raw.githubusercontent.com/torvalds/linux/v4.19/net/ipv4/netfilter/nf_log_ipv4.c)
7. klogd tags lines `kernel`, and its comment says glibc may turn LOG_KERN into LOG_USER. **Confirmed.** [klogd.c](https://raw.githubusercontent.com/RMerl/asuswrt-merlin/master/release/src/router/busybox/sysklogd/klogd.c)
8. The router's log level does not block the lines. **Confirmed, and stronger than written.** BusyBox syslogd forwards to the remote host before its `-l` filter, which applies only locally. ASUSWRT's iptables also defaults the LOG level to `LOG_WARNING`, which the research had marked unchecked. Upgraded to high. [syslogd.c](https://raw.githubusercontent.com/RMerl/asuswrt-merlin/master/release/src/router/busybox/sysklogd/syslogd.c), [libipt_LOG.c](https://raw.githubusercontent.com/RMerl/asuswrt-merlin/master/release/src/router/iptables/extensions/libipt_LOG.c)

**Router: how it is sent**
9. `log_ipaddr` set → `-R <ip>[:<log_port>] -L`; default `log_port` 514; ASUS: "Remote log server port is [514] in default setting", and the port can be changed. **Confirmed** in both trees and the FAQ. [legacy services.c](https://raw.githubusercontent.com/RMerl/asuswrt-merlin/master/release/src/router/rc/services.c), [382.1 services.c](https://raw.githubusercontent.com/RMerl/asuswrt-merlin.ng/382.1/release/src/router/rc/services.c), [ASUS FAQ 1044954](https://www.asus.com/support/faq/1044954/)
10. Plain UDP, the message sent unmodified plus `\n`, nothing queued, errors ignored except ECONNRESET, ENOTCONN and EPIPE (socket reopened). **Confirmed.** The file read is the Merlin tree's BusyBox copy; the unit runs BusyBox 1.17.4, so the exact lines are medium and the behaviour high. [syslogd.c](https://raw.githubusercontent.com/RMerl/asuswrt-merlin/master/release/src/router/busybox/sysklogd/syslogd.c)
11. Default `log_size` 256, `log_level` 7 ("< LOG_INFO"), `console_loglevel` 5. **Confirmed.** [defaults.c 382.1](https://raw.githubusercontent.com/RMerl/asuswrt-merlin.ng/382.1/release/src/router/shared/defaults.c)
12. DHCP lines appear because `dhcpd_querylog` defaults to 1. **Partly.** The `quiet-dhcp` condition and the default are as stated, but the setting sits in defaults.c's "Merlin-specific settings" block, so it says nothing about stock. Downgraded to low and fixed in section 2; it stays an at-home check. [382.1 services.c](https://raw.githubusercontent.com/RMerl/asuswrt-merlin.ng/382.1/release/src/router/rc/services.c), [defaults.c 382.1](https://raw.githubusercontent.com/RMerl/asuswrt-merlin.ng/382.1/release/src/router/shared/defaults.c)
13. dnsmasq `cache-size=1500`. **Confirmed.** That the PC then sees the projector's answers stays an inference (medium). [382.1 services.c](https://raw.githubusercontent.com/RMerl/asuswrt-merlin.ng/382.1/release/src/router/rc/services.c)

**Fixed addresses**
14. Manual Assignment steps; the IP "needs to be in the IP pool of your DHCP server"; the device stays on automatic. **Confirmed.** [ASUS FAQ 1000906](https://www.asus.com/support/faq/1000906/)
15. Persistent randomized MAC per network, the same until a factory reset, unchanged by forget and re-add; the factory MAC when randomization is off. **Confirmed** for stock Android, **partly** for this unit: the maker must set `config_wifi_connected_mac_randomization_supported` and support the HAL calls. Caveat added in the Short answer and section 4. [AOSP behaviour](https://source.android.com/docs/core/connect/wifi-mac-randomization-behavior), [AOSP implementation](https://source.android.com/docs/core/connect/wifi-mac-randomization)

**Receiver and Windows**
16. A venv's `python.exe` on Windows is a redirector that starts the base interpreter as a child, so the base `python.exe` owns the socket. **Confirmed.** [venv docs](https://docs.python.org/3/library/venv.html), [venvlauncher.c](https://raw.githubusercontent.com/python/cpython/main/PC/venvlauncher.c)
17. `WSAEMSGSIZE` truncation for UDP. **Confirmed.** The same page lists other `recvfrom` errors; the loop now logs them and keeps going (fixed in section 5). [Winsock recvfrom](https://learn.microsoft.com/en-us/windows/win32/api/winsock2/nf-winsock2-recvfrom)
18. No admin rights needed for port 514 on Windows. **Unverified.** Still only the mailing-list statement; an old Microsoft Q&A thread claims the opposite without a Windows source. The bind error will tell. [openssh-unix-dev 2023](https://lists.mindrot.org/pipermail/openssh-unix-dev/2023-November/041076.html), [Microsoft Q&A](https://learn.microsoft.com/en-us/answers/questions/292450/what-port(s)-doesnt-need-administrator-privilege-t)
19. Block beats Allow; with no allow rule Windows prompts; No or cancel creates Block rules, one each for TCP and UDP. **Confirmed.** Microsoft also says to have allow rules in place before the first launch, which supports the research's medium reading. [Windows Firewall rules](https://learn.microsoft.com/en-us/windows/security/operating-system-security/network-security/windows-firewall/rules)
20. `New-NetFirewallRule` parameters (`-Program` full path, single IPv4 addresses, a rule active only while its profile is). **Confirmed.** [New-NetFirewallRule](https://learn.microsoft.com/en-us/powershell/module/netsecurity/new-netfirewallrule)
21. "Make the home Wi-Fi Private, or the rule stays inactive". **Refuted as advice.** The default-Public fact is right, but the rule can simply name the profile the network has. Microsoft marks Public "Recommended" at home too, and Private makes the PC discoverable. Fixed in the Short answer and section 6, plus a check of the "Block all incoming connections" box. [Microsoft support: network settings](https://support.microsoft.com/en-us/windows/experience/connectivity-networking/essential-network-settings-and-tasks-in-windows), [Microsoft support: Firewall and network protection](https://support.microsoft.com/windows/windows-ec0844f7-aebd-0583-67fe-601ecf5d774f)
22. `powercfg /change` values are in minutes. **Confirmed.** [powercfg](https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/powercfg-command-line-options)
23. Updates pause for up to 35 days; updates that need a restart wait. **Confirmed.** [Pause updates](https://support.microsoft.com/en-us/windows/deployment/updates-lifecycle/pause-updates-in-windows)
24. `schtasks` syntax, `/tr` up to 262 characters, `/delay mmmm:ss` valid for ONSTART. **Confirmed, but incomplete.** A scheduled task is stopped 72 hours after it starts by default, which would kill a reboot-started receiver mid-probation. Fixed in section 7 with `Set-ScheduledTask ... -ExecutionTimeLimit ([TimeSpan]::Zero)`. [schtasks create](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/schtasks-create), [TaskSettings](https://learn.microsoft.com/en-us/windows/win32/taskschd/tasksettings), [New-ScheduledTaskSettingsSet](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtasksettingsset)

**Owner lookup**
25. RDAP bootstrap: longest match, HTTPS first, base URLs end in `/`. **Confirmed.** [RFC 9224](https://www.rfc-editor.org/rfc/rfc9224.html)
26. RIPEstat `network-info` gives `asns` and `prefix`; `as-overview` gives `holder`. **Confirmed.** [network-info](https://stat.ripe.net/docs/data-api/api-endpoints/network-info), [as-overview](https://stat.ripe.net/docs/data-api/api-endpoints/as-overview)
27. Analyzer vCard parsing. **Bug fixed.** A multi-part `org` is a JSON array, which made the set comprehension raise and the whole RDAP result read "rdap failed". It now uses `str(v[3])`. [RFC 7095](https://www.rfc-editor.org/rfc/rfc7095.html)
28. 1e100.net is Google's server domain. **Confirmed.** But the `.1e100.net` row does not cover NTP well: Google's time servers reverse to names like `time1.google.com`. Added a `.google.com` udp/123 row (medium, third-party DNS data). [Google](https://support.google.com/faqs/answer/174717), [Netify 216.239.35.0](https://www.netify.ai/resources/ips/216.239.35.0)

**Expected list**
29. Android 11 probe URLs (`connectivitycheck.gstatic.com`, `www.google.com/generate_204`, fallbacks `www.google.com/gen_204` and `play.googleapis.com`). **Confirmed.** [NetworkStack config.xml](https://android.googlesource.com/platform/packages/modules/NetworkStack/+/refs/heads/android11-release/res/values/config.xml)
30. `time.android.com`, polled every 24 h, retried every 60 s up to 3 times. **Confirmed** (the `SntpClient` port line was not re-opened). [framework config.xml](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android11-release/core/res/res/values/config.xml)
31. Reading `settings get global captive_portal_*` and `ntp_server` shows the vendor's overrides. **Partly.** `Settings.Global.NTP_SERVER` does beat `config_ntpServer`. But in NetworkMonitor a vendor overlay `config_captive_portal_*_url` beats `Settings.Global`, and an overlay can replace `config_ntpServer` itself; `settings` shows neither. Note added in section 9; the log still catches it. [NtpTrustedTime](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android11-release/core/java/android/util/NtpTrustedTime.java), [NetworkMonitor.java](https://android.googlesource.com/platform/packages/modules/NetworkStack/+/refs/heads/android11-release/src/com/android/server/connectivity/NetworkMonitor.java)
32. By default, Private DNS upgrades to DNS over TLS when the network's DNS server supports it. **Confirmed.** The blog gives no port; 853 comes from RFC 7858, not re-opened. [Android blog](https://android-developers.googleblog.com/2018/04/dns-over-tls-support-in-android-p.html)
33. Netflix's seven delivery domains: **confirmed**. AS2906 at exchange points and AS40027 for ISP-embedded appliances: **confirmed**. Embedded appliances in the ISP's own address space: **unverified** (APNIC does not say so). Control plane on AWS: **confirmed** with a first-party source, replacing the unreadable PDF. [domain list](https://openconnect.netflix.com/mobiledeliverydomains.txt), [APNIC](https://blog.apnic.net/2018/06/20/netflix-content-distribution-through-open-connect/), [Netflix cloud migration](https://about.netflix.com/en/news/completing-the-netflix-cloud-migration)
34. IOC file "copied from 02a and its sources". **Partly.** The cited HY350 lists hold three more IOC domains and two more IPs that were left out; added in section 9. Names shared with ordinary apps were deliberately left off. [HY350 domains](https://github.com/maximilian-sh/hy350max-badbox-removal/blob/main/iocs/domains.txt), [HY350 IPs](https://github.com/maximilian-sh/hy350max-badbox-removal/blob/main/iocs/ips.txt)

**Pass rules**
35. Pass rule "no attempt to reach 192.168.1.0/24". **Partly.** ebtables drops guest-to-LAN frames without a LOG target, and same-subnet traffic never routes through iptables, so the log cannot show most attempts. Reworded to "no logged attempt" in the Short answer. [lan.c](https://raw.githubusercontent.com/RMerl/asuswrt-merlin/master/release/src/router/rc/lan.c)

**Router update**
36. the last firmware (2020/06/29), an MD5, a manual update below 382.52259, and no notes on logging, firewall, DHCP, guest networks or a reset. **Confirmed.** ASUS support page (router-specific source removed)
37. The 382-based tree builds the same logging rules and syslogd command. **Confirmed** in Merlin's 382.1 tree. It stays medium because it is not this model's own GPL drop. [382.1 firewall.c](https://raw.githubusercontent.com/RMerl/asuswrt-merlin.ng/382.1/release/src/router/rc/firewall.c), [382.1 services.c](https://raw.githubusercontent.com/RMerl/asuswrt-merlin.ng/382.1/release/src/router/rc/services.c)
38. Save the settings first, without ticking the box that strips the password. **Confirmed**: the FAQ describes that box. Missing: the same FAQ advises a factory reset and setting things up again by hand after a firmware update, rather than importing an old file. Added in section 12. [ASUS FAQ 1001376](https://www.asus.com/support/faq/1001376/)
39. Stale text: section 3 said "Access Intranet" was unanswered in 06, but 06 now records it as present. Fixed in section 3 and in the at-home list. [06](../decisions/06-router-facts.md)

**Corrected gist.** The stock ASUS can send the PC one plain-text UDP syslog line per new IPv4 connection: source and destination address and port, no names, and no MAC on this 2.6.36 kernel. A ~50-line stdlib Python receiver collects it, behind a narrow firewall rule on the network's existing profile; a scheduled task for it needs the 72-hour stop removed. Each destination is explained by a router-DNS name match, forward-confirmed reverse DNS or RDAP, and checked against the Android baseline (connectivity check, NTP) and the 02a/HY350 IOCs. The last firmware update changes none of this.
