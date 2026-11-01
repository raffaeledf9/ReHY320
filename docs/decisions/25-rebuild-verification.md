# 25 Rebuild verification with our own key

Type: research
Status: resolved
Blocked by: 20, 24

## Question

How exactly are the cleaned partitions given working verification again, using Google's own `avbtool` and a key we generate?
- Reproducing each partition's hash tree and error-correction data with the parameters read from this unit (version 1, SHA-1, 4096-byte blocks, 2 error-correction roots, the recorded salt), so the result occupies the same space inside the container.
- Building the three verification partitions (the top-level one, which also covers product and chains to the other two, plus the system and vendor ones), with our key and the flags cleared.
- What must match exactly for the device to boot, and what the failure looks like if it does not.
- Where the private key lives, and the honest statement of what signing with it does and does not protect against.
- How a later change to the system regenerates all of this, as a script.

## Answer

Findings in [research/25-rebuild-verification.md](../research/25-rebuild-verification.md), checked against AOSP's own sources, with all six tree and error-correction sizes reproducing to the byte.

It works with Google's own `avbtool`: each cleaned file system gets a fresh hash tree and error-correction data built with this unit's exact parameters, and three new verification partitions carry the resulting root hashes, signed with a key we generate.

The one new thing that can stop the projector booting is not a signature: Android's own start-up code compares the verification data against the digest the bootloader reports. So the procedure is done in two passes, and the first pass writes only the verification partitions, without touching the container. That proves this bootloader computes and reports the digest the way Android expects, before anything irreversible is written. Our evidence that it does is ticket 24 alone, so this check is worth its separate step.

What a wrong root hash looks like depends on a boot setting (`androidboot.veritymode`): absent or enforcing gives a projector that restarts in a loop, while "eio" gives one that boots and reports read errors. On this unit that setting is **absent** from the kernel command line captured in ticket 24 and from both boot images, so the restart loop is what to expect. Either way the way out is the same: hold the power button at start-up, reach fastboot, and write the relaxed verification partition back.

One risk to the schedule: the error-correction data needs a small host tool built from AOSP source, which has not been built here yet, and that is the one step that could stop the script. Error correction is optional; without it the system is still fully checked, it just cannot repair small damage by itself.
