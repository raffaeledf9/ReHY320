# 12 What stays on the finished system

Type: grilling
Status: resolved
Blocked by: 11, 23

## Question

Once cleaning is done, which of the tools used for cleaning stay on the deployed projector, and which are taken off again?

## Answer (user, 2026-10-22)

- **USB debugging: off on the finished projector.** While it is on, the single USB port acts as a computer connection and will not read USB sticks, and the user wants media playback from sticks. It is switched on only when something has to be installed from the PC, and off again afterwards.
- **Getting files to the projector over the home network instead:** yes, and it is the better route. The projector **pulls** files from a read-only share on the PC with the file manager (Material Files, which speaks SMB), so nothing new listens on the projector, no inbound port is opened, and USB debugging stays off. The share on the PC is switched on only while transferring. A USB stick stays as the offline fallback. The details are ticket 15.
- **Network debugging stays off permanently.** The stock firmware preset an open, unauthenticated debugging port for when Wi-Fi is on; the cleaning removes that and it is never re-enabled.
- **Nothing from the cleaning stays on the projector.** No root, no Magisk, no extra tools: everything is done from the PC through fastboot, so the finished system carries none of it.
- **Relaxed verification is permanent**, and not a choice: once the partitions are modified they no longer match the manufacturer's signed hashes, so verification can never be switched back on. Recorded in the findings for ticket 11.

## Amended (2026-10-22)

- **Relaxed verification is no longer permanent.** Ticket 20's revision rebuilds verification with our own key over the cleaned partitions, so the finished projector is hash-checked on every read again. What stays permanently gone is the manufacturer's signature chain, which this bootloader never enforced anyway.
- **Still no root and no debuggable build**, so nothing extra for streaming apps to object to.
