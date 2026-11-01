# Step 2: what listens on the network, and who owns it

Read from the cleaned projector on 2026-10-23, over USB. No partition was written.

## What was found

`/proc/net/tcp` and `/proc/net/tcp6` showed three programs waiting for connections,
and all three were bound to **every network interface**, not just the projector itself.

| Port | Runs as | What it is |
|---|---|---|
| 65528 | root | `/vendor/bin/dbgserver`, a chip-maker debugging service |
| 14035 | audioserver | the voice-trigger test component, inside `audioserver` |
| 5555 | shell | network ADB, key-authenticated |

Two UDP sockets on 5353 belong to the name-announcing service (`mdnsd`). Those are
normal and AirPlay needs them.

## 65528 — the chip-maker's debugging service

`/vendor/bin/dbgserver`, 31 KB, started at every boot by `/vendor/etc/init/dbgserver.rc`
as **root**. Its own text identifies it as Allwinner board-support code
(`vendor/aw/homlet/tvsystem/hal/bsp/Tools/DebugServer/Src/debug.c`, "dbgserver2 version 3.0").

It waits for connections and, on request, **reads and writes the projector's memory and
its chips' registers**. There is no password, key or token anywhere in the file, and the
connection is in clear text. It accepted five connections at once from the PC.

How it was attributed: of every program running as root, only this one and Android's own
network manager contain internet-address code at all, and the network manager uses local
sockets rather than a port. Nothing else on the projector refers to `dbgserver` except its
own startup file and the permission policy.

**This is the single worst thing left on the projector.** It is also the reason the
original firmware could be reprogrammed remotely: full memory access as root, offered to
anyone who can reach the device.

## 14035 — the voice-trigger test component

`/vendor/lib/hw/sound_trigger.primary.ares.so`, 14 KB, loaded inside `audioserver`
(which is why the port shows that account). It is Android's own *stub* component for
voice-wake testing: instead of listening to a microphone it takes typed commands over
the network to pretend a wake-word was heard. Its text contains the prompt `>>> `,
`get_command`, `Bad command %s.` and `Done processing commands over network.`

Proved by: the prompt string exists in this file and in no other audio component, and
connecting to the port produced exactly that prompt.

It is test code that should not be in a shipped product, but its powers are small: it can
only inject a fake wake-word, and this projector has no voice assistant for one to reach.
One connection was opened and closed from the PC, which **stopped its thread for this
boot** — the port is gone until the next restart.

## 5555 — network ADB

`service.adb.tcp.port` is set to 5555, so the debugging daemon also listens on the
network. Key authentication is on (`ro.adb.secure=1`), so a connection has to be approved
on screen; it is a surface, not an open door.

Nothing in any partition sets that property — not the startup scripts, not the property
files — so something sets it at run time each boot. The most likely candidate is the
vendor settings app, which step 8 removes. It closes immediately with `adb usb`, and
permanently when USB debugging is switched off in step 9.

## Everything else

- 34 startup services in the vendor partition were listed; only `dbgserver` is a network
  service. `hostapd` (access-point mode) is present but not running.
- The Widevine `move_data` service is Android's own, marked disabled and one-shot.
- `/system/bin/tcpdump`, and `devmem` and the i2c tools in `/vendor/bin`, are local
  command-line tools from the standard toolbox. They need root to be useful and do not
  listen for anything.

## Recommendation

Remove `/vendor/bin/dbgserver`, its startup file, and the voice-trigger test component,
before the projector ever joins a network. All three live in the vendor partition, so it
is one more write of the same kind as step 1, with the same undo.

## Outcome (2026-10-23)

Both vendor listeners were removed in one vendor write, verified by reading the container
and vendor's verification partition back byte-for-byte. After a full restart neither comes
back, and nothing listens on IPv4 from the system at all.

What listens now:

| Port | Runs as | What it is |
|---|---|---|
| 7000 | an ordinary app account | the AirPlay receiver, which starts itself at boot |
| 5555 | shell | ADB, key-authenticated, goes away with USB debugging |

The name-announcing service's UDP sockets on 5353 are still there, which AirPlay needs.
