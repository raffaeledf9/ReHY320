# 06 Router facts

Type: task
Status: resolved

## Question

What do the home router settings actually show today, so probation and the settings check can rest on facts? HITL: the user reads the router's web page at home and changes nothing.

Checklist (the user writes the answers; never passwords, Wi-Fi keys, public IP or device addresses):
1. Firmware version.
2. Router IP address and subnet mask.
3. IPv6 connection type.
4. Guest network: bands offered, whether an "Access Intranet" option is shown, whether any guest network is on now.
5. Firewall: on or off; whether a "Logged packets type" option exists, and its value.
6. Whether a "Remote Log Server" field exists.
7. "Enable Web Access from WAN": yes or no.
8. Telnet and SSH: on or off.
9. UPnP: on or off.
10. Port forwarding (Virtual Server) and Port Trigger: any rules present, yes or no.
11. DHCP "Manual Assignment": present, yes or no.
12. Admin username still "admin", and admin password still the factory one: yes or no each.
13. Main Wi-Fi: security mode (e.g. WPA2-Personal) and WPS on or off.

Where each item is in the stock ASUSWRT web page (layout of the stock firmware; menu names may differ slightly):
- Firmware version: top bar of the main page, or Administration > Firmware Upgrade.
- Address range: LAN > LAN IP. IPv6: IPv6 page (connection type).
- Guest network: General > Guest Network.
- Firewall logging: Firewall > General.
- Sending the log elsewhere, remote access from the internet, Telnet/SSH, admin name: Administration > System (and System Log).
- Wi-Fi security mode: Wireless > General. WPS: Wireless > WPS.
- UPnP: WAN > Internet Connection. Port forwarding: WAN > Virtual Server / Port Forwarding, and Port Trigger.
- Fixed addresses: LAN > DHCP Server.

Two ways to capture it: screenshots of those pages, or the user logs in themselves in Claude's browser pane while on the home network and Claude reads the pages without changing anything.

## Answer

**The answers for this project's own router are not published.** Taken together
they are a security profile of one particular house — firmware version, which
features are on, what the admin account is called — and none of it helps anyone
reproduce the work. They stay in the author's local copy of this repository.

What matters to a reader is what the answers are *for*, which is the same for
any router:

- **Items 5 and 6 decide whether step 10 can use the router at all.** Connection
  logging needs the firewall switched on, and sending the log to a PC needs a
  Remote Log Server field. If your router has neither, skip straight to the
  projector's own record (`scripts/probation/netwatch.sh`), which is what this
  project ended up relying on anyway: this ASUS build's "Logged packets type"
  produced no ACCEPT lines at all. See
  [research/16-probation-tooling.md](../research/16-probation-tooling.md).
- **Item 11** is how the projector keeps one address across reboots, which
  every later step assumes.
- **Item 4** is how the projector gets internet without reaching your LAN while
  it is still on probation.
- **Items 1, 7–10, 12 and 13** are not about the projector. They are worth
  reading once because a projector behind a router with WPS on, the factory
  admin password, or web access from the internet is not meaningfully behind
  anything. Fix what you find before step 10, not after.

Record your own answers somewhere outside this repository, the way the
`.scratch/` directory is kept out of it.
