#!/system/bin/sh
#
# Records where the projector goes on the network, for its probation.
#
# The plan was for the router to log every accepted connection and send it to the
# PC. It cannot: this ASUS build's "Logged packets type" produces no ACCEPT lines
# at all, only system messages. So the projector watches itself instead, which is
# less independent -- a compromised system could in principle lie about its own
# traffic -- but it is what is available, it sees more than the router ever could,
# and it keeps recording while the owner's laptop is elsewhere.
#
# Two records, both plain text, both small:
#
#   capture.log  every name looked up, every TCP connection opened, and every
#                time request. Catching TCP at the SYN means no connection is
#                missed however short it is, which sampling cannot promise.
#   peers.log    what is connected right now, sampled, and which process owns it.
#                This is what catches sustained UDP flows such as QUIC, which
#                carry a lot of traffic on port 443 and start with no handshake,
#                and it is the only one of the two that can name the app.
#
# Duplicates are left in and removed on the PC: deduplicating here would mean
# keeping state across reboots for no gain.

OUT=/data/adb/netwatch
POLL=15
LIMIT=67108864          # 64 MB, after which a file is rolled once

mkdir -p "$OUT"
sleep 45                # let Android finish starting before asking for an interface

# Names, connection starts and time requests. tcpdump exits whenever wlan0 goes
# away, so it is simply restarted.
(
  while true; do
    tcpdump -i wlan0 -n -l -tttt \
      'udp dst port 53 or udp dst port 123 or (tcp[tcpflags] & (tcp-syn|tcp-ack)) == tcp-syn' \
      >> "$OUT/capture.log" 2>> "$OUT/capture.err"
    sleep 15
  done
) &

# What is connected now, and who opened it.
while true; do
  now=$(date +%Y-%m-%dT%H:%M:%S%z)
  ss -tunpH 2>/dev/null | while read netid state rq sq local peer rest; do
    case "$peer" in
      ''|*'*'*|127.0.0.1:*|'['*) continue ;;    # unbound, loopback, or IPv6
    esac
    echo "$now	$netid	$peer	$rest"
  done >> "$OUT/peers.log"

  for f in capture.log peers.log; do
    size=$(stat -c%s "$OUT/$f" 2>/dev/null || echo 0)
    [ "$size" -gt "$LIMIT" ] && mv "$OUT/$f" "$OUT/$f.1"
  done
  sleep "$POLL"
done
