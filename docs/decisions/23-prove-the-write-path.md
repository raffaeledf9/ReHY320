# 23 Prove that writing works, reversibly

Type: task
Status: resolved
Blocked by: 11

## Question

Can the PC write to this projector, and does the bootloader accept relaxed verification? HITL, three steps in this order, each with its undo. Nothing else in the project may be written before this ticket is resolved.

**Step A — a way in that does not need Android to boot.** Before anything is written, establish at least one write path that works while the projector is not running Android: either fastboot accepts writes, or the H713-specific recovery-mode tool is built and proven to write. Read-only checks only. This exists because step C can leave a projector that does not start, and the way back must already be known to work.

**Step B — a harmless write.** Write a recognisable pattern into part of the partition named `empty` (15 MB, confirmed to be all zeros and used by nothing), read it back over USB, compare, then restore the zeros and confirm. Proves the write path end to end with nothing at risk.

**Step C — relax verification.** Set the two flags in the 128 KB verification partition, restart, and confirm the projector still starts and reports verification relaxed. Undo: write the original 128 KB back from the golden backup, through the path proven in step A.

If step C fails and cannot be undone, the project stops and the projector stays dormant and HDMI-only.

## Guards every write script must have

- Refuse unless the connected unit's serial and build fingerprint match the ones recorded with the golden backup.
- Take the target's offset and length from the backup manifest by partition name; never from a hand-typed offset.
- Read the target region first and refuse if it does not match what the backup says is there, so what is being overwritten is always known.
- Read back and compare after every write.
- Keep the golden image read-only and write only from copies.
- Stop and ask the user immediately before each write.

## Progress — step A, PC side (2026-10-20)

Done without the projector:
- Built the H713-capable recovery tool (`sunxi-fel`) from source in WSL: the YuujiLab fork of the open-source sunxi-tools, GPLv2, commit c48f1aa, whose newest change is literally "fel: add support for Allwinner H713", and whose chip table lists 0x1860 as the H713 — the exact value this unit's chip reported. Needed packages: build-essential, pkg-config, libusb-1.0-0-dev, zlib1g-dev, libfdt-dev. Binary at `/usr/local/src/sunxi-tools-h713/sunxi-fel` inside WSL.
- The tool can load and start code in the chip's memory (`spl`, `uboot`, `execute`) and read memory (`hexdump`, `dump`). It cannot write storage by itself.
- Confirmed how writing through recovery mode actually works on this chip: the tool loads a U-Boot into memory, and that U-Boot then presents the projector's storage to the PC as an ordinary USB drive, which the PC reads and writes. Nothing is written while it is being loaded.
- Consequence: a U-Boot built for this chip is needed. It will be built from source rather than taken as a prebuilt binary. The published one targets the sibling HY310, which shares the chip and the same 1 GB memory size, so loading it is expected to work; loading it writes nothing, so trying it is low risk.

Still to do in step A, with the projector:
1. In fastboot: read-only checks of whether the bootloader knows the partition names and accepts a data upload without writing.
2. In recovery mode: prove the freshly built tool reads memory on this unit.
3. Then the U-Boot route, so a write path exists that does not need Android.

## Progress — step A, with the projector (2026-10-20)

Fastboot, read-only:
- Protocol version 0.5, maximum 32 MB per transfer. It answers no partition queries at all ("not supported" for every one), so it is a minimal implementation and the partition names it accepts are unknown until a write is attempted.
- **Uploading works**: 4 KB was sent to the device's memory and accepted, without writing anything. So the PC can hand data to the bootloader.
- Because of the 32 MB limit, the 1 GB system partition cannot be written through fastboot in one piece.
- **`fastboot oem efex` switches straight into recovery mode**, so the paperclip is no longer needed: power on normally, restart into fastboot over USB, then one command.

Recovery mode, read-only, with the tool built from source:
- It identifies the chip as `soc=00001860(H713)` and reads this unit's unique chip id.
- It reads memory correctly once the right addresses are used, taken from the tool's own chip table rather than guessed: scratch area 0x10c000, load area 0x104000, identity registers 0x03006200 (which returned real data). Memory reading is therefore proven on this unit.
- Lesson learned the hard way: one request to a wrong address makes recovery mode stop answering until the projector is power-cycled. Only addresses from the chip table are used from now on.
- The usbipd firewall rule must be enabled while the device is passed to WSL, and may be switched off afterwards.

Where the boot code lives, read from the backup:
- The `bootloader` partition is **not** boot code: it is a FAT volume holding boot resources (which is what the vendor's USB customisation script writes into).
- The real boot code is in the 37.7 MB reserved area at the very start of the storage, which the golden backup contains: the first-stage loader at offset 0x2000 with a second copy at 0x20000, and the U-Boot package (containing fastboot support) around 0xc00000.

Still open in step A: a way to write while Android is not running. The remaining candidate is loading a U-Boot into memory through recovery mode so that it presents the storage to the PC as a USB drive. That is PC-side build work, started next.

## Where step A stands, and the choice it reaches (2026-10-20)

Proven: reading in both modes, and uploading data to the bootloader. Not proven: writing.

The only route to writing while Android is not running is to load a U-Boot into memory through recovery mode, which then presents the storage to the PC as a USB drive. The H713 project has exactly this, in two variants: an installer one, and a **probe** one made for H713 devices they do not know, built with conservative memory timings and documented as writing nothing. Our HY320 is such an unknown device.

Building either from source here is not a small job: their build runs inside a podman container with an LLVM toolchain and their own U-Boot fork, none of which is installed, and the probe configuration is not even in the repository we cloned. Realistically hours, with a fair chance of friction on this old Ubuntu.

This also affects the real work, not just the undo: fastboot accepts at most 32 MB per transfer, while the system partition is 1 GB, and the active partitions cannot be rewritten while Android runs on them. So the USB-drive route is probably needed for the cleaning itself, whichever way the undo is solved.

Three ways forward, for the user to choose:
1. Build it from source (podman, LLVM, their U-Boot fork). Keeps the rule that nothing prebuilt is used. Hours of work.
2. Use the project's published probe binary, with its checksum checked against their release notes. It runs on the projector only, never on the PC, and is documented as writing nothing; a wrong one simply hangs until a power cycle. This relaxes the user's "no third-party binaries" rule for one file, so it is theirs to decide.
3. Do the verification test without a proven undo. If it fails, the projector is out of action, not destroyed: recovery mode is in read-only memory and cannot be lost, so option 1 or 2 can still be done afterwards to put it back.

## The WSL route is dead for writing, and a simpler one replaces it (2026-10-20)

Through the USB bridge into WSL, reading works and writing does not: a 32 KB transfer into the projector's memory times out every time, and after one failure recovery mode stops answering until a power cycle. Mirrored networking mode did not change it. Reads are fine, so this is the bridge's handling of transfers towards the device, not the projector and not the board's memory settings. Loading a U-Boot that way is therefore not possible from this PC without either a native Windows build of the tool or a Linux machine.

That matters less than it seemed, because fastboot needs no bridge at all: it runs natively on Windows, and uploading 4 KB to it already worked. So the plan becomes:
1. Write through fastboot, which covers everything up to its 32 MB limit, including the 128 KB verification partition.
2. Make the bootloader come up in fastboot on every start, by writing the standard boot-control command into the `misc` partition. Then fastboot stays reachable even if Android cannot boot, which is exactly the way back that step A was looking for. Whether this bootloader honours that command is testable, and the write is 32 bytes with the original in the golden backup.
3. The 1 GB system partition is larger than fastboot's limit, so writing it will need its own solution later; it is not needed for the verification test or for the undo.

A quirk to carry into the runbook: after a power cycle the projector's USB port comes up in host mode and the PC does not see it at all. Switching USB debugging off and on again on the projector fixes it every time.

## Step B — done and verified (2026-10-20)

Through fastboot, natively on Windows, with the projector's identity checked first:
1. Confirmed the target region (`empty`, 15 MB at offset 2,472,017,920) was exactly zeros on the device, matching the golden backup.
2. Wrote a 1 MB recognisable pattern with `fastboot flash empty`. Fastboot reported success but could not query the partition size, so the report alone meant nothing.
3. Read the region back from the other side, through Android's raw storage access, and compared byte for byte: **the pattern was there in full**.
4. Restored 15 MB of zeros the same way, read back the whole region, and its SHA-256 now matches the golden backup's recorded hash for that region exactly.

So writing works, verification works, and restoring to a byte-identical state works. The whole loop is proven on a partition nothing uses.

Notes for the runbook:
- Binary output must go through cmd, never PowerShell, which corrupts it (an early read came back five bytes too long).
- USB debugging survives a reboot; only a full power cycle makes the port come up in the wrong mode.
- The region's offset in sectors is 4,828,160, which is what the read commands use.

## Where it stands after the safety-net test (2026-10-20, late)

What was proven:
- Writing through fastboot works, verified by reading back and by restoring a region byte-identical to the golden backup.
- The bootloader reads its settings from the `env` partitions, which verified boot does not cover, and it obeys a change there: with `bootcmd` pointed at the vendor's own `boot_fastboot` variable, the projector stops booting Android and sits at its logo.

What went wrong:
- In that state the projector does not appear on USB at all, so fastboot cannot be reached. The vendor's `boot_fastboot=fastboot` variable evidently does not start a working fastboot; the command that `adb reboot bootloader` triggers must do more. Choosing that variable was the mistake.
- The projector is therefore unusable until its original settings are written back. It is not damaged: recovery mode still answers, and the original 256 KB of settings are in the golden backup.
- My ordering error: I tested the safety net before proving a write path that does not need Android, which is the one thing this ticket says to do first.

Why recovery mode cannot write, measured:
- Reads work. Writes of up to 4 KB work at every address tried, and 32 KB worked at the scratch address.
- Writes of 16 KB or more at the load address stop the session.
- Decisive: **executing even a single return instruction over recovery mode stops the chip answering.** Loading a U-Boot requires executing code, so that whole route is closed from this PC as it stands. Patching the tool to send 4 KB pieces, and building a version that skips its instruction-cache step, did not change it.
- Two candidate explanations, both still untested: the chip's recovery mode may run 64-bit code while the tool sends 32-bit instructions, or the instruction cache holds stale data at the address being executed. The first is testable with a single 64-bit return instruction.

Ways back in, in order of ease:
1. **A USB keyboard** plugged into the projector. The bootloader waits a second before running its boot command and may accept a keypress, giving its own prompt on screen, where one command restores the setting. Nothing to open, nothing to buy beyond a keyboard.
2. **A 3.3 V USB-to-serial adapter** on the board's console pads. The reliable route, and the one the vendor and the community use, but it means opening the case.
3. **Keep working on recovery-mode execution**: test a 64-bit return instruction, and try loading the projector's own first-stage loader from the golden backup instead of the mainline one, since it is built for this exact board.

A quirk worth keeping: recovery mode is only entered reliably when the mains power goes in **before** the USB cable, because the USB cable alone powers the board and starts the boot before the button is sampled.

## Final measurement on recovery-mode execution (2026-10-20, ~03:30)

With the instruction-cache step skipped, the load got one step further and failed differently: the tool executed a small routine to read a processor register and got `E121F001` back, which is not a register value but part of the instruction word it had just written. So the code did not run and the memory was read back unchanged.

Together with the earlier results this says: through recovery mode this unit reads and writes memory reliably, but **does not execute**. The earlier "it stops answering" results were the same thing seen through a crash rather than a message, and the bare-return test I ran was not a fair test anyway, since a bare return needs a valid return address that this chip's recovery mode may not provide. Both 32-bit and 64-bit attempts behaved the same.

Without execution, no code can be put on the device through recovery mode, so the storage cannot be written that way. The remaining doubt is whether the tool's scratch address for this chip is wrong, which only the project's author or a serial console could settle.

Ways back in, now in order of likelihood:
1. **USB keyboard** in the projector's port: the bootloader waits a second before its boot command and may take a keypress, giving its prompt on screen. One command then restores the setting.
2. **3.3 V USB-to-serial adapter** on the board's console pads: the route the community uses for this chip, and the one that always works. Means opening the case.
3. **Free to try any time:** power on normally and press remote keys during the logo, in case the bootloader watches the infrared receiver for a recovery or fastboot entry.

## Answer — step A and step B are both done (2026-10-20, ~03:40)

**The way in that does not need Android: hold the projector's own power button while it starts up.** It then comes up in fastboot and the PC sees it. Found by trying it, after recovery mode turned out to be unable to run code. No keyboard, no serial adapter, no Android.

That closes step A, and it is exactly the property the whole ticket was looking for: a mode that can write, reachable with nothing but the power button and the cable.

Proof of the full loop, all measured:
- **Write:** a 1 MB pattern into the unused `empty` partition through fastboot.
- **Verify:** read back from Android's side, byte for byte identical.
- **Restore:** 15 MB of zeros written back; the region's hash now matches the golden backup exactly.
- **Recovery from a self-inflicted dead end:** after the settings change left the projector stuck at its logo with no USB, the power-button route reached fastboot, both settings copies were restored from the golden backup, and Android booted again. Both copies were then read back from the device and match the backup's recorded hashes exactly. Nothing was lost.

What this ticket establishes for the runbook:
1. Writing goes through fastboot, up to 32 MB per transfer. It reports success even when it cannot query the partition, so **every write must be verified by reading back**.
2. Fastboot is reachable three ways: from Android (`adb reboot bootloader`), from the projector's power button held at start-up, and from fastboot into the chip's recovery mode (`fastboot oem efex`).
3. The golden backup plus fastboot is a complete undo for anything up to 32 MB, which includes the verification partition, the settings and the boot images.
4. Recovery mode is good for reading and for identifying the unit, but cannot run code on this unit, so it is not a write path. Do not count on it for the undo.
5. Do not use the vendor's `boot_fastboot` variable: it does not start a working fastboot. If a settings change is ever needed again, test it knowing the power-button route is the way back.

**Step C, relaxing verification, is not done yet.** It is now properly protected: a verified undo path exists that does not depend on Android booting.
