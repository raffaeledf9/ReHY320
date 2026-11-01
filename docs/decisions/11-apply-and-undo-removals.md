# 11 How removals are applied and undone

Type: research
Status: resolved
Blocked by: 09

## Question

For each place on this unit's storage where removable components live, what is the least risky way to remove them for good, and how is each change undone from the golden backup?

## Answer

Findings in [research/11-apply-and-undo-removals.md](../research/11-apply-and-undo-removals.md).

The system, vendor and product partitions are all covered by verified boot, signed with the manufacturer's own key, which does not match any of Android's published test keys. So a changed partition cannot be re-signed. The only route is to relax verification by setting two flags in the small verification partition, then write the cleaned partitions. Whether the bootloader accepts that is the one thing everything else depends on, and it is testable and reversible; if it refuses, the project stops and the projector stays a dormant HDMI-only device.

Writing can go through fastboot, the chip's recovery mode, or Android itself (the vendor leaves the raw storage writable by everything, which is also a cleaning item). The first device write in the runbook is a harmless test on the partition literally named `empty`, 15 MB of zeros: write a pattern, read it back, restore the zeros.

Every change is undone by writing the original bytes back from the golden backup, which holds per-partition hashes. Not to be touched: the key partition, factory-reset protection, the vendor data area, the boot control data, and this unit's projection geometry file.

Two side findings: no DRM keys are provisioned on this unit at all, which independently confirms that paid streaming will be standard definition at best; and the `permissive` setting comes from the vendor boot image, so ticket 20's change means rewriting that image and should wait until the cleaned system has proven stable.
