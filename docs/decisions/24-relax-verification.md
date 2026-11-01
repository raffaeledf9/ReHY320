# 24 Does the bootloader accept relaxed verification

Type: task
Status: resolved
Blocked by: 23

## Question

The system, vendor and product partitions are covered by verified boot with the manufacturer's own key, so a changed partition cannot be re-signed (ticket 11). The only route is to set two flags in the 128 KB verification partition so Android skips the checks. **Whether the bootloader accepts that is the single fact the whole project rests on**, and it is the last unknown before the runbook can be written.

HITL, one write with its undo:
1. Set both flags in the active verification partition and write it with fastboot (128 KB, far inside the 32 MB limit).
2. Restart. Either Android comes up, or it does not.
3. Read the result back and check what Android reports about verification.

Undo, proven in ticket 23: hold the projector's power button while it starts to reach fastboot with no Android, then write the original 128 KB back from the golden backup.

Nothing is modified on the protected partitions in this ticket, so their contents still match their own checksums; only the checking changes.

If the bootloader refuses, the project stops here and the projector stays a dormant HDMI-only device, as agreed in ticket 11.

## Answer — yes, it accepts it (2026-10-22)

The bootloader does not enforce verified boot on this unit, and the project can go ahead.

What was done: 128 KB written to the active verification partition with fastboot, differing from the golden backup by **one byte** (the flags word, 0 to 3). The relaxed copy was extracted from the compressed golden copy on the PC and checked against the manifest's hash first, since the external drive was not connected at the time.

What happened: the projector rebooted straight into Android, normally.

Evidence that the change took effect and that checking is now off:
- The verification digest the bootloader reports changed from `e2fde0c6…` to `83a1346f…`, and the new value appears in the kernel command line. So the bootloader read our modified partition, hashed it, and booted anyway.
- All three protected partitions now mount as plain full-size mappings: system 2,041,744 sectors, vendor 225,064, product 631,400, each exactly the whole logical partition. A verity mapping would expose only the smaller signed area (system would be 2,009,368 sectors).
- Their device-mapper identifiers are ordinary ones, with none of the markings a verity mapping carries.
- The kernel log shows no verity set-up at all.

Consequences:
- The cleaned system, vendor and product partitions can be written and will boot. That was the project's last unknown.
- The projector currently runs with integrity checking switched off. That is the state the cleaning needs, and it is one 128 KB write away from being restored at any time (`vbmeta-original.img`, verified identical to the backup).
- Writes must still be verified by reading back, because fastboot reports success regardless.

Also learned: the user's phone is connected to this PC over Wi-Fi debugging, so every command must name the projector's serial explicitly rather than "the USB device".
